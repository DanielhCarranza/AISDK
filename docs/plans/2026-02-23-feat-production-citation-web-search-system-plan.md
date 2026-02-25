---
title: "Production Citation & Web Search System"
type: feat
status: completed
date: 2026-02-23
origin: docs/brainstorms/2026-02-23-ai-system-citation.md
---

# Production Citation & Web Search System

## Overview

Enhance AISDK's citation and web search infrastructure from a minimal, partially-implemented feature to a production-grade, cross-provider system. Today, `AISource` has four fields (with `snippet` always nil), only streaming paths emit sources, position data is silently dropped, web search lifecycle events are ignored, and Anthropic/Gemini citation data is largely discarded. This plan delivers complete citation support across OpenAI Responses, Anthropic, and Gemini — with position-based inline citations, snippet extraction, search lifecycle events, non-streaming source support, and proper multi-turn citation preservation.

## Problem Statement

AIDoctor (and any app using AISDK for web search) is forced into workarounds: regex-parsing raw text for citation markers, guessing titles from URLs, and building custom source drawers with incomplete data. The SDK has the raw types decoded (e.g., `URLCitationAnnotation` with `startIndex`/`endIndex`, `ResponseOutputWebSearchCall` with `query` and `sources`) but never surfaces them through the event pipeline. Meanwhile, Anthropic's 5 citation types and Gemini's `groundingSupports` with positional segments are entirely unhandled.

## Proposed Solution

A phased implementation that:
1. Expands public API types (`AISource`, `AIStreamEvent`, `AITextResult`, `ProviderStreamEvent`) with citation and search lifecycle data
2. Fixes all three provider adapters to populate these types fully
3. Adds the OpenAI `include` parameter pipeline and `web_search` tool type
4. Adds Anthropic `citations_delta` handling and `encrypted_content` preservation
5. Adds Gemini `groundingSupports` decoding and positional citation mapping
6. Provides unit tests with mock SSE fixtures and live integration tests

## Technical Approach

### Architecture

The citation data flow is:

```
Provider SSE → ResponseChunk/ACAStream/GCAResponse
    → Adapter (OpenAI/Anthropic/Gemini)
        → ProviderStreamEvent (.source, .webSearchStarted, .webSearchCompleted)
            → toAIStreamEvent() mapping
                → AIStreamEvent (.source, .webSearchStarted, .webSearchCompleted)
                    → AIStreamAccumulator (parts: [AIMessagePart])
                        → SwiftUI / UIKit consumer
```

For non-streaming:
```
Provider Response → Adapter.execute()
    → ProviderResponse (sources: [AISource])
        → AITextResult (sources: [AISource])
            → Consumer
```

### Index Unit Convention

**Decision: All `startIndex`/`endIndex` values on `AISource` are UTF-16 code unit offsets.**

Rationale:
- OpenAI uses UTF-16 code unit offsets (matching JavaScript `string.indexOf`)
- Swift's `NSString`/`String.utf16` view uses UTF-16 natively
- Anthropic's `char_location` uses Unicode code point offsets — we convert at the adapter boundary
- Gemini's segment indices are UTF-8 byte offsets — we convert at the adapter boundary
- We provide a `String` extension helper for safe substring extraction

### Implementation Phases

#### Phase 1: Public API Types (Foundation)

Expand the shared types that all providers and consumers depend on. This must land first as all subsequent phases build on it.

**1.1 Expand `AISource`** (`Sources/AISDK/Core/Models/AIStreamEvent.swift`)

```swift
public struct AISource: Sendable, Codable, Hashable {
    public let id: String
    public let url: String?
    public let title: String?
    public let snippet: String?
    public let startIndex: Int?       // NEW — UTF-16 offset in response text
    public let endIndex: Int?         // NEW — UTF-16 offset in response text
    public let sourceType: AISourceType?  // NEW — web, file, document, etc.

    public init(
        id: String,
        url: String? = nil,
        title: String? = nil,
        snippet: String? = nil,
        startIndex: Int? = nil,
        endIndex: Int? = nil,
        sourceType: AISourceType? = nil
    ) { ... }
}

public enum AISourceType: String, Sendable, Codable {
    case web           // URL citation from web search
    case file          // File citation (OpenAI file_search)
    case containerFile // Container file citation (OpenAI code interpreter)
    case document      // Document citation (Anthropic char/page/block location)
    case searchResult  // Search result citation (Anthropic search_result_location)
}
```

Backward compatible: existing callers using `AISource(id:url:title:snippet:)` still compile.

**1.2 Add Web Search Types** (`Sources/AISDK/Core/Models/AIStreamEvent.swift`)

```swift
/// Result of a web search performed by the model
public struct AIWebSearchResult: Sendable, Codable {
    public let query: String?
    public let sources: [AIWebSearchSource]

    public init(query: String? = nil, sources: [AIWebSearchSource] = []) {
        self.query = query
        self.sources = sources
    }
}

/// A URL consulted during web search (superset of cited sources)
public struct AIWebSearchSource: Sendable, Codable {
    public let url: String
    public let title: String?
    public let type: String  // "url", "oai-sports", "oai-weather", etc.

    public init(url: String, title: String? = nil, type: String = "url") {
        self.url = url
        self.title = title
        self.type = type
    }
}
```

**1.3 Add `AIStreamEvent` Cases** (`Sources/AISDK/Core/Models/AIStreamEvent.swift`)

```swift
public enum AIStreamEvent: Sendable {
    // ... existing cases ...

    /// Web search initiated — includes the query
    case webSearchStarted(query: String)

    /// Web search completed — includes query and all consulted sources
    case webSearchCompleted(AIWebSearchResult)
}
```

**1.4 Add `ProviderStreamEvent` Cases** (`Sources/AISDK/Core/Providers/ProviderClient.swift`)

```swift
public enum ProviderStreamEvent: Sendable {
    // ... existing cases ...
    case webSearchStarted(query: String)
    case webSearchCompleted(AIWebSearchResult)
}
```

Update `toAIStreamEvent()`:
```swift
case .webSearchStarted(let query):
    return .webSearchStarted(query: query)
case .webSearchCompleted(let result):
    return .webSearchCompleted(result)
```

**1.5 Add Sources to Non-Streaming Types**

`ProviderResponse` (`Sources/AISDK/Core/Providers/ProviderClient.swift`):
```swift
public struct ProviderResponse: Sendable {
    // ... existing fields ...
    public let sources: [AISource]  // NEW, default []
}
```

`AITextResult` (`Sources/AISDK/Core/Models/AITextResult.swift`):
```swift
public struct AITextResult: Sendable {
    // ... existing fields ...
    public let sources: [AISource]  // NEW, default []
}
```

Update `ProviderResponse.toAITextResult()` to forward sources.

**1.6 Update `AIStreamAccumulator`** (`Sources/AISDK/Core/Models/AIStreamAccumulator.swift`)

```swift
case .webSearchStarted(let query):
    // Store search state for UI consumers
    let id = "websearch-\(parts.count)"
    parts.append(.webSearch(id: id, query: query, sources: []))

case .webSearchCompleted(let result):
    // Update the last webSearch part with results, or append new one
    if let lastIndex = parts.lastIndex(where: {
        if case .webSearch = $0 { return true }
        return false
    }) {
        parts[lastIndex] = .webSearch(
            id: "websearch-\(lastIndex)",
            query: result.query ?? "",
            sources: result.sources.map { AISource(id: $0.url, url: $0.url, title: $0.title, sourceType: .web) }
        )
    }

case .source(let source):
    // Deduplicate by URL
    let isDuplicate = parts.contains(where: {
        if case .source(_, let existing) = $0 { return existing.url == source.url && existing.url != nil }
        return false
    })
    if !isDuplicate {
        let id = "source-\(parts.count)"
        parts.append(.source(id: id, source: source))
    }
```

**1.7 Add `AIMessagePart.webSearch` Case** (`Sources/AISDK/Core/Models/AIMessagePart.swift`)

```swift
public enum AIMessagePart: Sendable, Identifiable {
    // ... existing cases ...
    case webSearch(id: String, query: String, sources: [AISource])
}
```

**1.8 String Extension for Safe Substring Extraction**

Add a utility for consumers to extract cited text:

```swift
// Sources/AISDK/Core/Extensions/String+Citation.swift
extension String {
    /// Extract substring using UTF-16 code unit offsets (as returned by AISource.startIndex/endIndex)
    public func citedText(startIndex: Int, endIndex: Int) -> String? {
        let utf16 = self.utf16
        guard startIndex >= 0,
              endIndex >= startIndex,
              let start = utf16.index(utf16.startIndex, offsetBy: startIndex, limitedBy: utf16.endIndex),
              let end = utf16.index(utf16.startIndex, offsetBy: endIndex, limitedBy: utf16.endIndex),
              let result = String(utf16[start..<end]) else {
            return nil
        }
        return result
    }
}
```

**Phase 1 Acceptance Criteria:**
- [ ] `AISource` has `startIndex`, `endIndex`, `sourceType` fields with defaults
- [ ] `AIStreamEvent.webSearchStarted` and `.webSearchCompleted` exist
- [ ] `ProviderStreamEvent` has matching cases with `toAIStreamEvent()` mapping
- [ ] `ProviderResponse` and `AITextResult` have `sources: [AISource]` fields
- [ ] `AIStreamAccumulator` handles new events with source deduplication
- [ ] `AIMessagePart.webSearch` case exists
- [ ] `String.citedText(startIndex:endIndex:)` helper exists
- [ ] `swift build` passes with no errors

---

#### Phase 2: OpenAI Responses Adapter (Critical Path)

This is the highest-priority adapter since AIDoctor uses o4-mini via the Responses API.

**2.1 Add `web_search` Tool Type** (`Sources/AISDK/LLMs/OpenAI/APIModels/Responses/ResponseTool.swift`)

Add `case webSearch(ResponseWebSearchTool)` alongside existing `webSearchPreview`. The newer tool type uses `"web_search"` as the type string, supports `filters.allowed_domains`, and costs $10/1K calls vs $25/1K.

**2.2 Wire `include` Parameter**

End-to-end path: `AITextRequest` → `ProviderRequest` → `ResponseRequest.include`

- Add `include: [String]?` to `ProviderRequest`
- In `OpenAIResponsesClientAdapter.convertToAITextRequest()`, when `builtInTools` contains `.webSearch`, auto-append `"web_search_call.results"` to `include`
- Allow override via `providerOptions["include"]`

**2.3 Handle `case .webSearchCall`** (`Sources/AISDK/Core/Providers/OpenAIResponsesClientAdapter.swift`)

Replace the `default: break` that silently drops web search calls:

```swift
case .webSearchCall(let webSearch):
    // Emit search query
    if let query = webSearch.query ?? webSearch.action?.query {
        continuation.yield(.webSearchStarted(query: query))
    }

    // Emit completion with consulted sources
    if webSearch.status == "completed" {
        let sources = webSearch.action?.sources?.map { source in
            AIWebSearchSource(url: source.url, type: source.type)
        } ?? []
        let query = webSearch.query ?? webSearch.action?.query
        continuation.yield(.webSearchCompleted(AIWebSearchResult(
            query: query,
            sources: sources
        )))
    }
```

**2.4 Pass Position Data and Extract Snippet**

Track accumulated text during streaming to extract snippets at annotation time:

```swift
// At top of streaming closure:
var accumulatedText = ""

// On text delta:
accumulatedText += delta

// On urlCitation annotation:
if case .urlCitation(let citation) = annotation {
    let snippet = accumulatedText.citedText(
        startIndex: citation.startIndex,
        endIndex: citation.endIndex
    )

    continuation.yield(.source(AISource(
        id: citation.url,
        url: citation.url,
        title: citation.title,
        snippet: snippet,
        startIndex: citation.startIndex,
        endIndex: citation.endIndex,
        sourceType: .web
    )))
}
```

**2.5 Handle File Citations**

Currently `fileCitation`, `containerFileCitation`, and `filePath` annotations are silently dropped. Emit them as `.source()` events:

```swift
if case .fileCitation(let citation) = annotation {
    continuation.yield(.source(AISource(
        id: citation.fileId,
        url: nil,
        title: citation.filename,
        sourceType: .file
    )))
}

if case .containerFileCitation(let citation) = annotation {
    continuation.yield(.source(AISource(
        id: "\(citation.containerId)/\(citation.fileId)",
        url: nil,
        title: citation.filename,
        startIndex: citation.startIndex,
        endIndex: citation.endIndex,
        sourceType: .containerFile
    )))
}
```

**2.6 Non-Streaming Source Extraction**

In `buildProviderResponse()`, extract sources from the response's output items:

```swift
var sources: [AISource] = []
for item in response.output {
    if case .message(let msg) = item {
        for content in msg.content {
            if case .outputText(let textContent) = content,
               let annotations = textContent.annotations {
                for annotation in annotations {
                    if case .urlCitation(let citation) = annotation {
                        sources.append(AISource(
                            id: citation.url,
                            url: citation.url,
                            title: citation.title,
                            snippet: textContent.text?.citedText(
                                startIndex: citation.startIndex,
                                endIndex: citation.endIndex
                            ),
                            startIndex: citation.startIndex,
                            endIndex: citation.endIndex,
                            sourceType: .web
                        ))
                    }
                }
            }
        }
    }
}
// Pass sources to ProviderResponse
```

**Phase 2 Acceptance Criteria:**
- [ ] `web_search` tool type encodes/decodes correctly
- [ ] `include` parameter is auto-set when web search is enabled
- [ ] `.webSearchStarted(query:)` emits when web search call has a query
- [ ] `.webSearchCompleted(...)` emits with sources when status is "completed"
- [ ] `.source()` events include `startIndex`, `endIndex`, `snippet`
- [ ] File and container file citations emit `.source()` events
- [ ] Non-streaming `generateText` returns sources in `AITextResult.sources`
- [ ] Unit tests with mock SSE fixtures pass
- [ ] Live integration test with o4-mini web search passes

---

#### Phase 3: Anthropic Adapter

**3.1 Decode `citations_delta` Events** (`Sources/AISDK/Core/Providers/AnthropicClientAdapter.swift`)

Add `citationsDelta` case to `ACAStreamDelta`:

```swift
enum ACAStreamDelta: Decodable {
    // ... existing cases ...
    case citationsDelta(AnthropicCitation)
}
```

Define the 5 Anthropic citation types:

```swift
enum AnthropicCitation: Decodable {
    case charLocation(AnthropicCharLocationCitation)
    case pageLocation(AnthropicPageLocationCitation)
    case contentBlockLocation(AnthropicContentBlockLocationCitation)
    case webSearchResultLocation(AnthropicWebSearchResultLocationCitation)
    case searchResultLocation(AnthropicSearchResultLocationCitation)
}

struct AnthropicWebSearchResultLocationCitation: Decodable {
    let type: String  // "web_search_result_location"
    let citedText: String
    let url: String
    let title: String?
    let encryptedIndex: String
}

struct AnthropicCharLocationCitation: Decodable {
    let type: String  // "char_location"
    let citedText: String
    let documentIndex: Int
    let documentTitle: String?
    let startCharIndex: Int
    let endCharIndex: Int
}
// ... similar for page_location, content_block_location, search_result_location
```

**3.2 Handle `server_tool_use` for Web Search**

When a `content_block_start` delivers a `server_tool_use` block with `name: "web_search"`, emit `webSearchStarted`. Extract the query from the subsequent `input_json_delta` events:

```swift
case .serverToolUse(let block) where block.name == "web_search":
    // Accumulate input JSON from deltas to extract query
    // On block stop, parse the accumulated JSON for {"query": "..."}
    // Emit .webSearchStarted(query: parsedQuery)
```

**3.3 Handle `web_search_tool_result` Block**

When a `content_block_start` delivers a `web_search_tool_result` block:

```swift
case .webSearchToolResult(let resultBlock):
    let sources = resultBlock.content.map { result in
        AIWebSearchSource(url: result.url, title: result.title)
    }
    continuation.yield(.webSearchCompleted(AIWebSearchResult(
        query: currentSearchQuery,  // from the preceding server_tool_use
        sources: sources
    )))

    // Also emit individual .source() events
    for result in resultBlock.content {
        continuation.yield(.source(AISource(
            id: result.url,
            url: result.url,
            title: result.title,
            sourceType: .web
        )))
    }
```

**3.4 Map `citations_delta` to `AISource`**

When `citations_delta` arrives during text streaming:

```swift
case .citationsDelta(let citation):
    switch citation {
    case .webSearchResultLocation(let loc):
        // Convert Anthropic char offsets to UTF-16 offsets
        let (start16, end16) = convertCharToUTF16Offsets(
            charStart: /* derive from cited text position */,
            in: accumulatedText
        )
        continuation.yield(.source(AISource(
            id: loc.url,
            url: loc.url,
            title: loc.title,
            snippet: loc.citedText,
            startIndex: start16,
            endIndex: end16,
            sourceType: .web
        )))

    case .charLocation(let loc):
        let (start16, end16) = convertCharToUTF16Offsets(
            charStart: loc.startCharIndex,
            charEnd: loc.endCharIndex,
            in: accumulatedText
        )
        continuation.yield(.source(AISource(
            id: "doc-\(loc.documentIndex)",
            url: nil,
            title: loc.documentTitle,
            snippet: loc.citedText,
            startIndex: start16,
            endIndex: end16,
            sourceType: .document
        )))
    // ... handle other citation types similarly
    }
```

**3.5 Add `encryptedContent` to `ACAWebSearchResult`**

```swift
struct ACAWebSearchResult: Decodable {
    let type: String
    let title: String?
    let url: String?
    let encryptedContent: String?  // NEW — must be preserved for multi-turn
    let pageAge: String?
}
```

Ensure this is round-tripped when building multi-turn message arrays.

**3.6 Fix Non-Streaming Source Handling**

In `buildProviderResponse()`, stop concatenating "title - url" into text content. Instead, extract structured `AISource` objects:

```swift
case .webSearchResult(let resultBlock):
    for result in resultBlock.content {
        sources.append(AISource(
            id: result.url ?? "source_\(sources.count)",
            url: result.url,
            title: result.title,
            sourceType: .web
        ))
    }
    // Do NOT append to textContent
```

**Phase 3 Acceptance Criteria:**
- [ ] `citations_delta` events are decoded with all 5 citation types
- [ ] `server_tool_use` with `name: "web_search"` emits `webSearchStarted`
- [ ] `web_search_tool_result` emits `webSearchCompleted` and individual `.source()` events
- [ ] Citation positions are converted from char offsets to UTF-16 offsets
- [ ] `encryptedContent` is preserved on `ACAWebSearchResult` for multi-turn
- [ ] Non-streaming no longer corrupts text content with source metadata
- [ ] Unit tests with mock SSE fixtures pass
- [ ] Live integration test with Claude web search passes

---

#### Phase 4: Gemini Adapter

**4.1 Expand `GCAGroundingMetadata`** (`Sources/AISDK/Core/Providers/GeminiClientAdapter.swift`)

Add missing fields:

```swift
struct GCAGroundingMetadata: Decodable {
    let groundingChunks: [GCAGroundingChunk]?
    let webSearchQueries: [String]?
    let groundingSupports: [GCAGroundingSupport]?  // NEW
    let searchEntryPoint: GCASearchEntryPoint?      // NEW
    let retrievalMetadata: GCARetrievalMetadata?    // NEW
}

struct GCAGroundingSupport: Decodable {
    let segment: GCASegment?
    let groundingChunkIndices: [Int]?
    let confidenceScores: [Double]?
}

struct GCASegment: Decodable {
    let partIndex: Int?      // NEW — which Part the offsets refer to
    let startIndex: Int?     // UTF-8 byte offset
    let endIndex: Int?       // UTF-8 byte offset
    let text: String?        // the exact cited text (snippet)
}

struct GCASearchEntryPoint: Decodable {
    let renderedContent: String?  // HTML widget — legally required to display
}

struct GCARetrievalMetadata: Decodable {
    let googleSearchDynamicRetrievalScore: Double?
}
```

Also add `domain` to `GCAGroundingChunk.WebInfo`:

```swift
struct WebInfo: Decodable {
    let uri: String?
    let title: String?
    let domain: String?  // NEW
}
```

**4.2 Emit Web Search Lifecycle Events**

Since Gemini doesn't send mid-stream search events, use `webSearchQueries` from `groundingMetadata`:

```swift
if let groundingMetadata = candidate.groundingMetadata {
    // Emit webSearchStarted for each query
    if let queries = groundingMetadata.webSearchQueries {
        for query in queries {
            continuation.yield(.webSearchStarted(query: query))
        }
    }

    // Emit sources from groundingChunks (deduplicated)
    if let chunks = groundingMetadata.groundingChunks {
        var emittedURLs = Set<String>()
        for chunk in chunks {
            guard let web = chunk.web, let uri = web.uri else { continue }
            guard emittedURLs.insert(uri).inserted else { continue }
            continuation.yield(.source(AISource(
                id: uri,
                url: uri,
                title: web.title,
                sourceType: .web
            )))
        }

        // Emit webSearchCompleted
        let webSources = chunks.compactMap { chunk -> AIWebSearchSource? in
            guard let web = chunk.web, let uri = web.uri else { return nil }
            return AIWebSearchSource(url: uri, title: web.title)
        }
        continuation.yield(.webSearchCompleted(AIWebSearchResult(
            query: groundingMetadata.webSearchQueries?.first,
            sources: webSources
        )))
    }

    // Map groundingSupports to positional AISource events
    if let supports = groundingMetadata.groundingSupports,
       let chunks = groundingMetadata.groundingChunks {
        for support in supports {
            guard let segment = support.segment,
                  let chunkIndices = support.groundingChunkIndices else { continue }

            for chunkIndex in chunkIndices {
                guard chunkIndex < chunks.count,
                      let web = chunks[chunkIndex].web,
                      let uri = web.uri else { continue }

                // Convert UTF-8 byte offsets to UTF-16
                let (start16, end16) = convertUTF8ToUTF16Offsets(
                    utf8Start: segment.startIndex ?? 0,
                    utf8End: segment.endIndex ?? 0,
                    in: accumulatedText
                )

                continuation.yield(.source(AISource(
                    id: uri,
                    url: uri,
                    title: web.title,
                    snippet: segment.text,
                    startIndex: start16,
                    endIndex: end16,
                    sourceType: .web
                )))
            }
        }
    }
}
```

**4.3 Non-Streaming Source Extraction**

In `buildProviderResponse()`, read `groundingMetadata` from the candidate and build sources:

```swift
var sources: [AISource] = []
if let metadata = candidate.groundingMetadata {
    // Same extraction logic as streaming, minus lifecycle events
}
```

**4.4 Source Deduplication in Streaming**

Track emitted source URLs per streaming session to prevent duplicates from intermediate chunks:

```swift
var emittedSourceURLs = Set<String>()
// Before emitting .source(), check: guard emittedSourceURLs.insert(url).inserted
```

**Phase 4 Acceptance Criteria:**
- [ ] `GCAGroundingMetadata` decodes `groundingSupports`, `searchEntryPoint`, `retrievalMetadata`
- [ ] `GCASegment` includes `partIndex`
- [ ] `webSearchStarted` emits with queries from `webSearchQueries`
- [ ] Positional sources emit from `groundingSupports` with UTF-8→UTF-16 offset conversion
- [ ] Sources are deduplicated within a streaming session
- [ ] Non-streaming `generateText` returns sources in `AITextResult.sources`
- [ ] Unit tests with mock response fixtures pass
- [ ] Live integration test with Gemini + Google Search grounding passes

---

#### Phase 5: OpenRouter & LiteLLM Compatibility

Both OpenRouter and LiteLLM proxy to upstream providers using OpenAI-compatible APIs.

**5.1 OpenRouter**

OpenRouter passes through upstream provider responses. When routing to an OpenAI model with web search, the response format matches OpenAI. When routing to Anthropic or Gemini, OpenRouter normalizes to OpenAI-compatible format.

- The `OpenRouterClient` extends `OpenAIClientAdapter` (Chat Completions format)
- Citations from OpenRouter come through as OpenAI-compatible annotations if the upstream model supports them
- No special adapter changes needed — the Chat Completions adapter's citation handling (if added) covers this
- **Note:** Chat Completions API itself has no native web search tool, so web search citations only appear when the upstream model (e.g., Perplexity via OpenRouter) includes them in the response

**5.2 LiteLLM**

LiteLLM also uses OpenAI-compatible format as a proxy:

- Same coverage as OpenRouter — relies on Chat Completions adapter
- If LiteLLM is routing to an OpenAI Responses API model, the response format may differ
- **Action:** Ensure the `LiteLLMClient` can optionally use the Responses adapter when the user specifies `providerOptions["use_responses_api": true]`

**Phase 5 Acceptance Criteria:**
- [ ] OpenRouter web search responses with citations are handled
- [ ] LiteLLM proxy responses pass through citations when available
- [ ] No breaking changes to OpenRouter/LiteLLM client configuration

---

#### Phase 6: Testing & Verification

**6.1 Unit Tests — Mock SSE Fixtures**

Create fixture files in `Tests/AISDKTests/Fixtures/`:

| Fixture | Contents |
|---------|----------|
| `openai_web_search_stream.jsonl` | Full SSE sequence: web_search_call.in_progress → searching → completed → output_item.done (webSearchCall) → text deltas → annotation.added (url_citation) → output_item.done (message) |
| `anthropic_web_search_stream.jsonl` | message_start → content_block_start (server_tool_use) → input_json_delta → content_block_stop → content_block_start (web_search_tool_result) → content_block_stop → content_block_start (text) → text_delta → citations_delta → content_block_stop → message_stop |
| `gemini_grounding_response.json` | generateContent response with groundingMetadata including groundingChunks, groundingSupports, webSearchQueries, searchEntryPoint |

**Unit test cases:**

1. `testOpenAIWebSearchCallEmitsLifecycleEvents` — Mock stream with webSearchCall → verify `.webSearchStarted` and `.webSearchCompleted` yielded with correct query and sources
2. `testOpenAIUrlCitationIncludesPositionData` — Mock stream with URLCitationAnnotation(startIndex: 10, endIndex: 50) → verify `AISource.startIndex == 10`, `AISource.endIndex == 50`
3. `testOpenAISnippetExtractedFromTextSpan` — Stream text deltas building "Hello world this is cited text here", then annotation with startIndex/endIndex spanning "cited text" → verify `snippet == "cited text"`
4. `testOpenAIWebSearchCallWithNilQuery` — query: nil → no `.webSearchStarted`, graceful handling
5. `testOpenAIMultipleWebSearchCalls` — Two search calls → two started/completed pairs
6. `testOpenAIFileCitationEmitsSource` — fileCitation annotation → `.source()` with `sourceType: .file`
7. `testOpenAINonStreamingReturnsSourcesInResult` — Non-streaming response with url_citation → `AITextResult.sources` is non-empty
8. `testAnthropicCitationsDeltaDecodesAllTypes` — Each of the 5 citation types → correct `AISource` with appropriate fields
9. `testAnthropicServerToolUseEmitsWebSearchStarted` — server_tool_use with name "web_search" → `.webSearchStarted(query:)`
10. `testAnthropicWebSearchToolResultEmitsCompleted` — web_search_tool_result block → `.webSearchCompleted` with sources
11. `testAnthropicEncryptedContentPreserved` — web_search_result with encrypted_content → field is preserved on internal type
12. `testAnthropicNonStreamingNoTextCorruption` — Non-streaming response with web_search_tool_result → text content does NOT contain "title - url" strings
13. `testGeminiGroundingSupportsEmitPositionalSources` — Response with groundingSupports → `.source()` events with startIndex/endIndex and snippet
14. `testGeminiWebSearchQueriesEmitLifecycleEvents` — Response with webSearchQueries → `.webSearchStarted` for each query
15. `testGeminiSourceDeduplication` — Same groundingChunk appearing in multiple streaming chunks → only one `.source()` event per unique URL
16. `testGeminiUTF8ToUTF16OffsetConversion` — String with emoji + CJK characters → offset conversion produces correct substring
17. `testAISourceBackwardCompatibility` — `AISource(id:url:title:snippet:)` still compiles and works
18. `testAIStreamAccumulatorDeduplicatesSources` — Multiple `.source()` events with same URL → accumulator has one source part
19. `testProviderStreamEventMapsWebSearchEvents` — `.webSearchStarted` and `.webSearchCompleted` map correctly through `toAIStreamEvent()`
20. `testStringCitedTextHelper` — Various strings including emoji → `citedText(startIndex:endIndex:)` returns correct substring

**6.2 Live Integration Tests** (require API keys, `RUN_LIVE_TESTS=1`)

| Test | Provider | Query | Assertions |
|------|----------|-------|------------|
| `testLiveOpenAIWebSearch` | OpenAI (o4-mini) | "What are the latest ADA diabetes guidelines?" | Stream contains `.webSearchStarted`, `.webSearchCompleted`, `.source()` with non-nil startIndex/endIndex/snippet |
| `testLiveAnthropicWebSearch` | Anthropic (Claude 3.7 Sonnet) | "What are the latest ADA diabetes guidelines?" | Stream contains `.webSearchStarted`, `.source()` with non-nil snippet |
| `testLiveGeminiWebSearch` | Gemini (gemini-2.0-flash) | "What are the latest ADA diabetes guidelines?" | Stream contains `.webSearchStarted`, `.source()` with non-nil snippet from groundingSupports |
| `testLiveOpenAINonStreamingCitations` | OpenAI (o4-mini) | Same query | `AITextResult.sources` is non-empty |

**6.3 CLI Demo Verification**

Update `Examples/AISDKCLI` or create a new `CitationDemo` example that:
1. Sends a web search query to each provider
2. Prints search lifecycle events as they arrive
3. Prints each source with URL, title, snippet, and position
4. Demonstrates `String.citedText()` helper
5. Verifies sources appear in non-streaming results

**Phase 6 Acceptance Criteria:**
- [ ] All 20 unit tests pass
- [ ] All 4 live integration tests pass with `RUN_LIVE_TESTS=1`
- [ ] CLI demo demonstrates end-to-end citation flow for all 3 providers
- [ ] `swift test` passes with no regressions

---

## Alternative Approaches Considered

**1. Typed citation union instead of expanded AISource**

Instead of adding `startIndex`/`endIndex`/`sourceType` to `AISource`, create a `AICitation` enum with provider-specific cases. Rejected because: (a) forces consumers to `switch` on every citation, (b) the normalized flat struct is simpler for 90% of use cases, (c) provider-specific details can be accessed via `providerOptions` or raw event data if needed.

**2. Separate AIWebSearchEvent instead of expanding AIStreamEvent**

Create a separate event protocol for web search events. Rejected because: (a) `AIStreamEvent` is already the single event type consumers observe, (b) adding a parallel event stream doubles the API surface, (c) the accumulator already handles `AIStreamEvent` uniformly.

**3. Auto-extract snippet for all providers at the accumulator level**

Instead of extracting snippets in each adapter, accumulate text in `AIStreamAccumulator` and extract snippets when sources arrive. Rejected because: (a) Gemini provides snippets natively via `segment.text`, (b) Anthropic provides `citedText` in citation deltas, (c) only OpenAI requires text accumulation for snippet extraction, (d) the accumulator is a consumer-level type and shouldn't know about provider-specific extraction logic.

## System-Wide Impact

### Interaction Graph

- `AISource` is used by `AIStreamEvent.source()` → `AIStreamAccumulator` → `AIMessagePart.source` → consumer UI
- `AITextResult` is returned by `LLM.generateText()` and `Agent.run()` — adding `sources` affects all consumers
- `ProviderStreamEvent` is the boundary between adapters and `ProviderLanguageModelAdapter` — new cases require all adapters to handle them (or default to no-op)
- `AIStreamEvent` is consumed by `ChatViewModel`, `Agent`, and any custom streaming handler

### Error Propagation

- Malformed citation data (e.g., startIndex > text length) → `citedText()` returns nil gracefully
- Missing `include` parameter → `sources` array is empty but no error (silent degradation)
- Unknown citation type from Anthropic → falls to default case, logged as warning, not thrown
- Gemini redirect URLs expire → not an SDK concern; documented for consumers

### State Lifecycle Risks

- `accumulatedText` in streaming adapters must be reset per-request to avoid leaking across requests
- `emittedSourceURLs` dedup set must be scoped to a single streaming session
- `encryptedContent` for Anthropic must survive session serialization if sessions are persisted

### API Surface Parity

| Interface | Needs Update |
|-----------|-------------|
| `LLM.generateText()` | Returns `AITextResult` which gains `sources` |
| `LLM.streamText()` | Returns `AsyncThrowingStream<AIStreamEvent>` — gains new event cases |
| `Agent.run()` | Uses `generateText` internally — sources flow through |
| `ChatViewModel` | Uses `AIStreamAccumulator` — gains `webSearch` and deduplicated `source` parts |

### Integration Test Scenarios

1. **Multi-turn with Anthropic web search** — Turn 1 triggers search, turn 2 references cited page → verify `encrypted_content` is round-tripped and turn 2 response is grounded
2. **OpenAI web search with emoji in text** — Query produces text with emoji → verify `startIndex`/`endIndex` correctly extract cited substring via UTF-16 offsets
3. **Gemini streaming with repeated grounding chunks** — Mock stream with overlapping groundingMetadata → verify deduplication produces exactly N unique sources
4. **Non-streaming generateText with all 3 providers** — Each returns sources in `AITextResult.sources` with at least URL and title populated
5. **Agent with web search tool** — Agent uses web search as part of a multi-step workflow → verify sources accumulate correctly across steps

## Acceptance Criteria

### Functional Requirements

- [ ] `AISource` has `startIndex: Int?`, `endIndex: Int?`, `sourceType: AISourceType?` fields
- [ ] `AIStreamEvent` has `.webSearchStarted(query:)` and `.webSearchCompleted(_:)` cases
- [ ] OpenAI Responses adapter emits web search lifecycle events from `webSearchCall` items
- [ ] OpenAI Responses adapter passes `startIndex`/`endIndex`/`snippet` through `.source()` events
- [ ] OpenAI `include` parameter is auto-set when web search is enabled
- [ ] `web_search` tool type is supported alongside `web_search_preview`
- [ ] Anthropic adapter decodes `citations_delta` with all 5 citation types
- [ ] Anthropic adapter emits `webSearchStarted` from `server_tool_use` blocks
- [ ] Anthropic `encrypted_content` is preserved for multi-turn
- [ ] Gemini adapter decodes `groundingSupports` with segment positions
- [ ] Gemini adapter emits `webSearchStarted` from `webSearchQueries`
- [ ] All providers return `sources` in non-streaming `AITextResult`
- [ ] Sources are deduplicated in `AIStreamAccumulator`
- [ ] `String.citedText(startIndex:endIndex:)` helper works with multi-byte characters

### Non-Functional Requirements

- [ ] No breaking changes to existing `AISource(id:url:title:snippet:)` initializer
- [ ] No breaking changes to existing streaming consumers (new events are additive)
- [ ] All new types conform to `Sendable`, `Codable`
- [ ] Swift 6 concurrency compliance maintained

### Quality Gates

- [ ] 20+ unit tests with mock fixtures
- [ ] 4 live integration tests (one per provider + non-streaming)
- [ ] CLI demo showing end-to-end flow
- [ ] `swift build` and `swift test` pass clean
- [ ] Zero regressions in existing 2,397 tests

## Dependencies & Prerequisites

- OpenAI API key with web search access (for live tests)
- Anthropic API key with web search tool access (for live tests)
- Google AI API key with search grounding enabled (for live tests)
- Existing SSE fixture infrastructure in `Tests/AISDKTests/Fixtures/StreamEventFixtures.swift`

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| UTF-16 offset conversion errors with multi-byte characters | Medium | High (wrong citations) | Comprehensive unit test with emoji/CJK strings; `citedText()` returns nil on out-of-bounds |
| Anthropic `encrypted_content` format changes | Low | Medium (multi-turn breaks) | Treat as opaque `String?`, no parsing |
| OpenAI `web_search` tool type not available on all models | Low | Low (fallback to `web_search_preview`) | Support both tool types, let developer choose |
| Gemini `confidenceScores` empty on 2.5+ models | Confirmed | Low (cosmetic) | Treat empty array as "no scores"; don't error |
| Breaking change if consumer manually constructs `ProviderResponse` | Medium | Medium | Use default parameter values for `sources: [AISource] = []` |

## Documentation Plan

After implementation:
- [ ] Update `docs/api-reference/` with new types and events
- [ ] Update streaming events documentation with web search lifecycle
- [ ] Add citation tutorial to `docs/tutorials/`
- [ ] Update provider comparison table with citation capabilities
- [ ] Document `String.citedText()` helper usage
- [ ] Document Google attribution requirements (searchEntryPoint rendering)

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-02-23-ai-system-citation.md](docs/brainstorms/2026-02-23-ai-system-citation.md) — Key decisions carried forward: expand AISource with position data, add webSearchStarted/webSearchCompleted events, fix OpenAI webSearchCall handling, extract snippets from accumulated text

### Internal References

- `AISource` struct: `Sources/AISDK/Core/Models/AIStreamEvent.swift:109-121`
- `AIStreamEvent` enum: `Sources/AISDK/Core/Models/AIStreamEvent.swift:1-107`
- `ProviderStreamEvent`: `Sources/AISDK/Core/Providers/ProviderClient.swift:506-536`
- `OpenAIResponsesClientAdapter`: `Sources/AISDK/Core/Providers/OpenAIResponsesClientAdapter.swift:350-369`
- `AnthropicClientAdapter`: `Sources/AISDK/Core/Providers/AnthropicClientAdapter.swift:875-883`
- `GeminiClientAdapter`: `Sources/AISDK/Core/Providers/GeminiClientAdapter.swift:1068-1075`
- `ResponseObject.swift` web search types: `Sources/AISDK/LLMs/OpenAI/APIModels/Responses/ResponseObject.swift:316-361`
- `AIStreamAccumulator`: `Sources/AISDK/Core/Models/AIStreamAccumulator.swift:120-123`
- Existing SSE fixtures: `Tests/AISDKTests/Fixtures/StreamEventFixtures.swift`
- OpenAI Responses API plan: `docs/plans/2026-02-21-feat-openai-responses-api-integration-plan.md`

### External References

- [OpenAI Web Search Tool Guide](https://platform.openai.com/docs/guides/tools-web-search)
- [OpenAI Responses API Reference](https://platform.openai.com/docs/api-reference/responses)
- [Anthropic Citations API](https://docs.anthropic.com/en/docs/build-with-claude/citations)
- [Anthropic Web Search Tool](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/web-search-tool)
- [Gemini Grounding with Google Search](https://ai.google.dev/gemini-api/docs/google-search)
- [Gemini GroundingMetadata REST Schema](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/reference/rest/v1beta1/GroundingMetadata)
