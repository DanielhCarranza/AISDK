---
title: "AISDK Citation System PRD — From beta.5 to Production-Grade"
type: prd
status: draft
date: 2026-02-23
target: AISDK v2.0.0-beta.6+
---

# AISDK Citation System PRD — From beta.5 to Production-Grade 

## Context

AIDoctor uses AISDK's `AIStreamEvent.source(AISource)` to power inline citations and a "Sources" drawer when the AI does web search. The current implementation in beta.5 has critical gaps that force app-level workarounds (regex parsing raw text, guessing titles from URLs, no search query transparency). This PRD documents exactly what exists, what's broken, and what the SDK needs to provide so client apps get a complete, first-class citation experience without hacks.

---

## 1. Current State (AISDK v2.0.0-beta.5)

### 1.1 `AISource` Struct (AIStreamEvent.swift:109-121)

```swift
public struct AISource: Sendable, Codable {
    public let id: String       // URL string (set to citation.url by adapter)
    public let url: String?     // Source URL
    public let title: String?   // Page title (often nil or truncated)
    public let snippet: String? // NEVER populated by any adapter
}
```

**Problems:**
- `snippet` is defined but **never set** by any adapter (always nil)
- `id` is set to `citation.url` — not a stable identifier, just a duplicate of `url`
- No position data (`startIndex`/`endIndex` exist in the API response but are dropped)
- No search query context
- No way to know which part of the response text this source backs

### 1.2 `AIStreamEvent.source` Emission

Only 3 adapters emit `.source()`:

| Adapter | File:Line | Trigger | Fields Populated |
|---------|-----------|---------|-----------------|
| `OpenAIResponsesClientAdapter` | `:357` | `urlCitation` annotations in `output_item.done` message | `id=url, url, title` |
| `AnthropicClientAdapter` | `:878` | `webSearchResult` content blocks | `id=url, url, title` |
| `GeminiClientAdapter` | `:1073` | `groundingMetadata.groundingChunks` | `id=uri, url=uri, title` |

**`OpenAIClientAdapter`** (Chat Completions): No citation support at all. Throws on built-in tools.

### 1.3 OpenAI Responses Adapter — Data Loss

**Current code** (OpenAIResponsesClientAdapter.swift:350-369):

```swift
case .message(let msg):
    for content in msg.content {
        if case .outputText(let textContent) = content,
           let annotations = textContent.annotations {
            for annotation in annotations {
                if case .urlCitation(let citation) = annotation {
                    continuation.yield(.source(AISource(
                        id: citation.url,
                        url: citation.url,
                        title: citation.title
                        // snippet: NOT SET (always nil)
                        // startIndex: DROPPED (exists on citation)
                        // endIndex: DROPPED (exists on citation)
                    )))
                }
            }
        }
    }

// Line 367-369:
default:
    break  // ← .webSearchCall falls here — COMPLETELY IGNORED
```

**What the API provides but AISDK drops:**

| Data | API Type | Where It Lives | Status |
|------|----------|---------------|--------|
| Search query | `String?` | `ResponseOutputWebSearchCall.query` | **DROPPED** (unhandled case) |
| Consulted source URLs | `[ResponseWebSearchSource]` | `ResponseOutputWebSearchCall.action.sources` | **DROPPED** |
| Citation start position | `Int` | `URLCitationAnnotation.startIndex` | **DROPPED** |
| Citation end position | `Int` | `URLCitationAnnotation.endIndex` | **DROPPED** |
| Search progress events | SSE events | `response.web_search_call.in_progress/searching/completed` | **DROPPED** |
| Snippet/cited text span | Derivable | `text[startIndex..<endIndex]` | **NEVER EXTRACTED** |

### 1.4 What the OpenAI API Actually Has (Already Decoded in AISDK)

These types already exist in `ResponseObject.swift` — they just aren't mapped to `AIStreamEvent`:

```swift
// ResponseObject.swift:316-331
public struct ResponseOutputWebSearchCall: Codable {
    public let id: String
    public let query: String?                          // ← THE SEARCH QUERY
    public let result: String?
    public let status: String?                         // in_progress, searching, completed
    public let action: WebSearchAction?
}

// ResponseObject.swift:334-350
public struct WebSearchAction: Codable {
    public let type: String                            // "search"
    public let query: String?                          // duplicate query
    public let queries: [String]?                      // multiple queries
    public let sources: [ResponseWebSearchSource]?     // ← CONSULTED URLs
    public let url: String?                            // for open_page
    public let pattern: String?                        // for find_in_page
}

// ResponseObject.swift:353-361
public struct ResponseWebSearchSource: Codable {
    public let type: String                            // "url"
    public let url: String
}

// ResponseObject.swift:837-856
public struct URLCitationAnnotation: Codable {
    public let type: String = "url_citation"
    public let url: String
    public let title: String?
    public let startIndex: Int                         // ← CHARACTER POSITION (dropped!)
    public let endIndex: Int                           // ← CHARACTER POSITION (dropped!)
}
```

**Streaming event types** (already in `ResponseEventType` enum):
```swift
case responseWebSearchCallInProgress = "response.web_search_call.in_progress"
case responseWebSearchCallSearching = "response.web_search_call.searching"
case responseWebSearchCallCompleted = "response.web_search_call.completed"
```

These are decoded but never mapped to any `AIStreamEvent` case.

---

## 2. Required Changes

### 2.1 New `AIStreamEvent` Cases

Add to `AIStreamEvent` enum in `AIStreamEvent.swift`:

```swift
/// Web search initiated — includes the query the model is searching for
case webSearchStarted(query: String)

/// Web search completed — includes query and all consulted source URLs
case webSearchCompleted(AIWebSearchResult)
```

### 2.2 New Types (AIStreamEvent.swift)

```swift
/// Result of a web search performed by the model
public struct AIWebSearchResult: Sendable, Codable {
    /// The search query the model used
    public let query: String?
    /// All URLs the model consulted (superset of cited sources)
    public let sources: [AIWebSearchSource]

    public init(query: String? = nil, sources: [AIWebSearchSource] = []) {
        self.query = query
        self.sources = sources
    }
}

/// A URL consulted during web search
public struct AIWebSearchSource: Sendable, Codable {
    public let url: String
    public let type: String  // "url", "web", etc.

    public init(url: String, type: String = "url") {
        self.url = url
        self.type = type
    }
}
```

### 2.3 Expand `AISource` with Position Data

Add two optional fields to `AISource`:

```swift
public struct AISource: Sendable, Codable {
    public let id: String
    public let url: String?
    public let title: String?
    public let snippet: String?
    public let startIndex: Int?    // NEW — character position in response text
    public let endIndex: Int?      // NEW — character position in response text

    public init(
        id: String,
        url: String? = nil,
        title: String? = nil,
        snippet: String? = nil,
        startIndex: Int? = nil,    // NEW (default nil for backward compat)
        endIndex: Int? = nil       // NEW (default nil for backward compat)
    ) { ... }
}
```

**Backward compatible**: existing callers using `AISource(id:url:title:snippet:)` still compile since new params have defaults.

### 2.4 Fix `OpenAIResponsesClientAdapter.performStreaming()`

**Change 1: Handle `case .webSearchCall`** (currently falls to `default: break`)

```swift
case .webSearchCall(let webSearch):
    // Emit search query when available
    if let query = webSearch.query ?? webSearch.action?.query {
        continuation.yield(.webSearchStarted(query: query))
    }

    // Emit completion with consulted sources when done
    if webSearch.status == "completed" {
        let sources = webSearch.action?.sources?.map { source in
            AIWebSearchSource(url: source.url, type: source.type)
        } ?? []
        continuation.yield(.webSearchCompleted(AIWebSearchResult(
            query: webSearch.query ?? webSearch.action?.query,
            sources: sources
        )))
    }
```

**Change 2: Pass position data and snippet through `.source()` events**

Track accumulated text during streaming to extract snippets:

```swift
// At top of streaming closure:
var accumulatedText = ""

// On text delta:
accumulatedText += delta

// On urlCitation:
if case .urlCitation(let citation) = annotation {
    // Extract snippet from text span
    let snippet: String?
    let startIdx = citation.startIndex
    let endIdx = min(citation.endIndex, accumulatedText.count)
    if startIdx < accumulatedText.count {
        let start = accumulatedText.index(accumulatedText.startIndex, offsetBy: startIdx)
        let end = accumulatedText.index(accumulatedText.startIndex, offsetBy: endIdx)
        snippet = String(accumulatedText[start..<end])
    } else {
        snippet = nil
    }

    continuation.yield(.source(AISource(
        id: citation.url,
        url: citation.url,
        title: citation.title,
        snippet: snippet,                  // NEW: extracted from text
        startIndex: citation.startIndex,   // NEW: pass through
        endIndex: citation.endIndex        // NEW: pass through
    )))
}
```

### 2.5 Update `ProviderStreamEvent` and Mapping

**ProviderClient.swift** — Add new cases to `ProviderStreamEvent`:

```swift
public enum ProviderStreamEvent: Sendable {
    // ... existing cases ...

    /// Web search started with query
    case webSearchStarted(query: String)

    /// Web search completed with results
    case webSearchCompleted(AIWebSearchResult)
}
```

**Update `toAIStreamEvent()`** mapping:

```swift
case .webSearchStarted(let query):
    return .webSearchStarted(query: query)
case .webSearchCompleted(let result):
    return .webSearchCompleted(result)
```

### 2.6 Update `AIStreamAccumulator`

Handle new events in `AIStreamAccumulator.swift`:

```swift
case .webSearchStarted:
    break  // No accumulation needed, consumed by UI layer

case .webSearchCompleted:
    break  // No accumulation needed, consumed by UI layer
```

### 2.7 Cross-Provider Parity (Lower Priority)

| Adapter | Change |
|---------|--------|
| `AnthropicClientAdapter` | Populate `snippet` from web search result content if available |
| `GeminiClientAdapter` | Emit `.webSearchStarted` from `groundingMetadata.searchEntryPoint` if available |

These are nice-to-have. The OpenAI Responses adapter is the critical path since AIDoctor uses o4-mini via Responses API for web search.

---

## 3. Summary of All Changes

### New Types

| Type | File | Purpose |
|------|------|---------|
| `AIWebSearchResult` | `AIStreamEvent.swift` | Search query + consulted sources |
| `AIWebSearchSource` | `AIStreamEvent.swift` | Single consulted URL |
| `AIStreamEvent.webSearchStarted(query:)` | `AIStreamEvent.swift` | New event case |
| `AIStreamEvent.webSearchCompleted(_:)` | `AIStreamEvent.swift` | New event case |

### Modified Types

| Type | File | Change |
|------|------|--------|
| `AISource` | `AIStreamEvent.swift` | Add `startIndex: Int?`, `endIndex: Int?` |
| `ProviderStreamEvent` | `ProviderClient.swift` | Add `webSearchStarted`, `webSearchCompleted` cases |

### Adapter Changes

| File | Changes |
|------|---------|
| `OpenAIResponsesClientAdapter.swift` | 1) Handle `case .webSearchCall` → emit `webSearchStarted`/`webSearchCompleted`  2) Pass `startIndex`/`endIndex` in `.source()` events  3) Extract snippet from accumulated text span |
| `ProviderClient.swift` | Update `toAIStreamEvent()` mapping for new cases |
| `AIStreamAccumulator.swift` | Handle new event cases (no-op) |

### No Changes Needed

| File | Why |
|------|-----|
| `ResponseObject.swift` | Already has `ResponseOutputWebSearchCall`, `URLCitationAnnotation` with `startIndex`/`endIndex` |
| `ResponseChunk.swift` | Already decodes web search streaming events |
| `OpenAIClientAdapter.swift` | Chat Completions has no citation support (by design) |

---

## 4. How AIDoctor Will Use These

With these SDK changes, the app will:

1. **Show "Searching: [query]"** during streaming via `.webSearchStarted(query:)` — Grok-style transparency
2. **Position-based citation rendering** via `startIndex`/`endIndex` — replace regex parsing with exact character ranges
3. **Rich source drawer** with actual `snippet` text — like Grok's "Pages" view
4. **Clean streaming text** — knowing exact citation positions means we can strip markers during streaming and render pills on finish
5. **Search transparency header** — "Searched 3 sources for 'ADA diabetes guidelines 2026'"

---

## 5. Verification Plan

### AISDK Unit Tests

1. **`testWebSearchCallEmitsSearchEvents`** — Chunk with `ResponseOutputWebSearchCall(query: "test", status: "completed", action: ...)` → verify `.webSearchStarted("test")` and `.webSearchCompleted(...)` yielded
2. **`testUrlCitationIncludesPositionData`** — Chunk with `URLCitationAnnotation(startIndex: 10, endIndex: 50)` → verify `AISource.startIndex == 10`, `AISource.endIndex == 50`
3. **`testSnippetExtractedFromTextSpan`** — Stream text deltas, then send annotation → verify `snippet` == `text[10..<50]`
4. **`testWebSearchCallWithNilQuery`** — `query: nil` → no `.webSearchStarted`, graceful handling
5. **`testMultipleWebSearchCalls`** — Two searches → two `started`/`completed` pairs
6. **`testBackwardCompatibility`** — `AISource(id:url:title:snippet:)` still compiles

### AIDoctor Integration (Manual)

1. Ask health question triggering web search
2. Verify `.webSearchStarted` provides query string
3. Verify `.source()` events have non-nil `startIndex`/`endIndex`/`snippet`
4. Verify Sources drawer shows full titles + snippet previews
