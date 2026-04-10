# Built-in Tools Guide

AISDK supports provider-native built-in tools: web search, code execution, file search, image generation, URL context, and computer use. These run server-side — no client implementation needed.

## Quick Start: Agent with Web Search + Code Execution

```swift
import AISDK

let openai = ProviderLanguageModelAdapter.openAIResponses(apiKey: key, modelId: "gpt-4o")
let result = try await openai.generateText(
    messages: [.user("What's the population of Tokyo? Calculate the per-capita GDP.")],
    builtInTools: [.webSearchDefault, .codeExecutionDefault]
)
print(result.text)
print("Sources: \(result.sources)")  // Structured citations
```

## Available Tools

| Tool | OpenAI Responses | Anthropic | Gemini | OpenAI Chat |
|------|:---:|:---:|:---:|:---:|
| `.webSearchDefault` | Yes | Yes | Yes | No |
| `.codeExecutionDefault` | Yes | Yes | Yes | No |
| `.fileSearch(config)` | Yes | No | No | No |
| `.imageGenerationDefault` | Yes | No | No | No |
| `.urlContext` | No | No | Yes | No |
| `.computerUseDefault` | Yes | Yes | No | No |

## Structured Citations

Web search results include full citation metadata:

```swift
let result = try await llm.generateText(
    messages: [.user("Latest Swift concurrency updates")],
    builtInTools: [.webSearchDefault]
)

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

let result = try await llm.generateText(
    messages: [.user("Latest COVID vaccine research")],
    builtInTools: [.webSearch(config)]
)
```

## Error Handling for Unsupported Tools

When you request a tool the provider doesn't support, you get an actionable error:

```swift
do {
    // fileSearch is OpenAI-only
    let result = try await gemini.generateText(
        messages: [.user("Search my files")],
        builtInTools: [.fileSearch(FileSearchConfig(vectorStoreIds: ["vs_123"]))]
    )
} catch let error as ProviderError {
    // "fileSearch is not supported by Gemini.
    //  Supported: webSearch, codeExecution, urlContext."
    print(error.localizedDescription)
}
```

Note: OpenAI Chat Completions API does not support any built-in tools. Use the Responses API via `ProviderLanguageModelAdapter.openAIResponses(...)`.

## Streaming with Tools

```swift
for try await event in llm.streamText(
    messages: [.user("Find and summarize recent AI papers")],
    builtInTools: [.webSearchDefault]
) {
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
