# Provider Switching Guide

AISDK lets you switch between OpenAI, Anthropic, and Gemini by changing one line. All providers share the same `LLM` protocol — `generateText`, `streamText`, `generateObject`, and `streamObject`.

## One-Line Provider Switch

```swift
import AISDK

// OpenAI Responses API (recommended for OpenAI)
let llm = ProviderLanguageModelAdapter.openAIResponses(apiKey: openAIKey, modelId: "gpt-4o")

// OpenAI Chat Completions
let llm = ProviderLanguageModelAdapter.openAIChatCompletions(apiKey: openAIKey, modelId: "gpt-4o")

// Anthropic
let llm = ProviderLanguageModelAdapter.anthropic(apiKey: anthropicKey, modelId: "claude-sonnet-4-20250514")

// Gemini
let llm = ProviderLanguageModelAdapter.gemini(apiKey: geminiKey, modelId: "gemini-2.0-flash")

// All use the same API:
let request = AITextRequest(messages: [.user("Hello")])
let result = try await llm.generateText(request: request)
```

## Proxy Providers

For OpenRouter and LiteLLM, construct the client then wrap it:

```swift
// OpenRouter
let client = OpenRouterClient(apiKey: "sk-or-...")
let llm = ProviderLanguageModelAdapter(client: client, modelId: "anthropic/claude-3-opus")

// LiteLLM
let client = LiteLLMClient(baseURL: URL(string: "http://localhost:4000")!)
let llm = ProviderLanguageModelAdapter(client: client, modelId: "gpt-4")
```

Note: OpenRouter model IDs use `provider/model` format (e.g., `anthropic/claude-3-opus`).

## Feature Support Matrix

| Feature | OpenAI Responses | OpenAI Chat | Anthropic | Gemini |
|---------|:---:|:---:|:---:|:---:|
| Text generation | Yes | Yes | Yes | Yes |
| Streaming | Yes | Yes | Yes | Yes |
| Vision (images) | Yes | Yes | Yes | Yes |
| Video | No | No | No | Yes |
| Audio | No | No | No | Yes |
| Tool calling | Yes | Yes | Yes | Yes |
| Structured output | Yes | Yes | Yes | Yes |
| Web search | Yes | No | Yes | Yes |
| Code execution | Yes | No | Yes | Yes |
| File search | Yes | No | No | No |
| Computer use | Yes | No | Yes | No |
| Reasoning | Yes (o-series) | Yes (o-series) | Yes (Opus, Sonnet 4, Haiku 4.5) | Yes (2.5+) |
| Prompt caching | Automatic | Automatic | Manual (.enabled) | Automatic |
| PDF input | No | No | Yes | Yes |

## Known Provider-Specific Behaviors

### conversationId
Only works with OpenAI Responses API (maps to `previousResponseId`). Silently ignored by other providers.

### Built-in tools
Not available on OpenAI Chat Completions API. Use `openAIResponses` instead.

### Streaming structured output
Legacy adapters (`AILanguageModelAdapter`) batch `streamObject` calls — they generate the full object then emit it in one event. Use `ProviderLanguageModelAdapter` for true streaming.

## Error Messages

Unsupported features throw actionable errors:

```
// Video on OpenAI:
"Unsupported modality: 'video' is not supported by OpenAI.
 Providers that support video: Gemini."

// fileSearch on Gemini:
"fileSearch is not supported by Gemini.
 Supported: webSearch, codeExecution, urlContext."
```

All `ProviderError` messages name the unsupported feature and list alternatives.
