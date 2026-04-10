# Built-in Tools Guide

AISDK supports provider-native built-in tools: web search, code execution, file search, image generation, URL context, and computer use. These run server-side — no client implementation needed.

## Quick Start: Agent with Web Search + Code Execution

```swift
import AISDK

let openai = ProviderLanguageModelAdapter.openAIResponses(apiKey: key, modelId: "gpt-4o")
let request = AITextRequest(
    messages: [.user("What's the population of Tokyo? Calculate the per-capita GDP.")],
    builtInTools: [.webSearchDefault, .codeExecutionDefault]
)
let result = try await openai.generateText(request: request)
print(result.text)
print("Sources: \(result.sources)")  // Structured citations
```

## Available Tools

| Tool | OpenAI Responses | Anthropic | Gemini | OpenAI Chat |
|------|:---:|:---:|:---:|:---:|
| `.webSearchDefault` | Yes | Yes | Yes | No |
| `.codeExecutionDefault` | Yes | Yes | Yes | No |
| `.fileSearch(config)` | Yes | No | Yes | No |
| `.imageGenerationDefault` | Yes | No | No | No |
| `.urlContext` | No | No | Yes | No |
| `.computerUseDefault` | Yes | Yes | No | No |

## Structured Citations

Web search results include full citation metadata:

```swift
let request = AITextRequest(
    messages: [.user("Latest Swift concurrency updates")],
    builtInTools: [.webSearchDefault]
)
let result = try await llm.generateText(request: request)

for source in result.sources {
    print("Title: \(source.title ?? "N/A")")
    print("URL: \(source.url ?? "N/A")")
    print("Snippet: \(source.snippet ?? "N/A")")
    // startIndex/endIndex for inline citation positioning
}
```

`AISource` fields:
- `url: String?` — source URL
- `title: String?` — page title
- `snippet: String?` — relevant text excerpt
- `startIndex: Int?` / `endIndex: Int?` — UTF-16 offsets for inline citation rendering
- `sourceType: AISourceType?` — `.web`, `.file`, `.document`, etc.

## Configure Web Search

```swift
let config = WebSearchConfig(
    maxUses: 3,
    searchContextSize: .medium,
    allowedDomains: ["pubmed.ncbi.nlm.nih.gov", "who.int"],
    blockedDomains: ["reddit.com"],
    userLocation: UserLocation(country: "US", timezone: "America/New_York")
)

let request = AITextRequest(
    messages: [.user("Latest COVID vaccine research")],
    builtInTools: [.webSearch(config)]
)
let result = try await llm.generateText(request: request)
```

## File Search

Search uploaded documents server-side. Store identifiers are provider-specific:

```swift
// OpenAI — vector store IDs
let openaiConfig = FileSearchConfig(
    vectorStoreIds: ["vs_abc123"],
    maxNumResults: 5,
    scoreThreshold: 0.7
)

// Gemini — file search store names
let geminiConfig = FileSearchConfig(
    vectorStoreIds: ["fileSearchStores/my-store-id"]
)

let request = AITextRequest(
    messages: [.user("What does the contract say about termination?")],
    builtInTools: [.fileSearch(geminiConfig)]
)
let result = try await gemini.generateText(request: request)

// File search citations use sourceType: .file
for source in result.sources {
    print("Document: \(source.title ?? "N/A")")
    print("Excerpt: \(source.snippet ?? "N/A")")
}
```

| Config field | OpenAI | Gemini |
|---|---|---|
| `vectorStoreIds` | Vector store IDs (`vs_...`) | Store names (`fileSearchStores/...`) |
| `maxNumResults` | Supported | Not supported |
| `scoreThreshold` | Supported | Not supported |

## URL Context (Gemini)

Fetches and grounds responses against the content of up to 20 URLs. The model extracts text from the URLs and uses it as context.

```swift
let gemini = ProviderLanguageModelAdapter.gemini(apiKey: key, modelId: "gemini-2.5-flash")
let request = AITextRequest(
    messages: [.user("Summarize https://example.com/article")],
    builtInTools: [.urlContext]
)
let result = try await gemini.generateText(request: request)
```

Limits: max 20 URLs per request, 34 MB total content. Cannot combine with custom function calling tools.

## Error Handling for Unsupported Tools

When you request a tool the provider doesn't support, you get an actionable error:

```swift
do {
    // imageGeneration is OpenAI-only
    let request = AITextRequest(
        messages: [.user("Generate an image")],
        builtInTools: [.imageGenerationDefault]
    )
    let result = try await gemini.generateText(request: request)
} catch let error as ProviderError {
    // "imageGeneration is not supported by Gemini."
    print(error.localizedDescription)
}
```

Note: OpenAI Chat Completions API does not support any built-in tools. Use the Responses API via `ProviderLanguageModelAdapter.openAIResponses(...)`.

## Streaming with Tools

```swift
let request = AITextRequest(
    messages: [.user("Find and summarize recent AI papers")],
    builtInTools: [.webSearchDefault]
)
for try await event in llm.streamText(request: request) {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .source(let source):
        print("\n[Citation: \(source.title ?? source.url ?? "")]")
    default:
        break
    }
}
```
