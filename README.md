# AISDK

Single-import Swift SDK for multi-provider LLM integration. Agents, tool calling, streaming, structured output, generative UI, and session management across OpenAI, Anthropic, and Google Gemini.

## Requirements

- iOS 17+ / macOS 14+ / watchOS 10+ / tvOS 17+
- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/DanielhCarranza/AISDK.git", exact: "2.0.0-beta.7")
]
```

In Xcode: File > Add Package Dependencies, paste the repository URL, and select **Exact Version** `2.0.0-beta.7`.

> **Note:** Beta versions require `.exact()` — SPM does not resolve pre-release versions with range-based requirements like `.upToNextMajor()`.

## Quick Start

```swift
import AISDK

// Recommended: use a factory method for v2 providers
let model = ProviderLanguageModelAdapter.openAIResponses(
    apiKey: "sk-...",
    modelId: "gpt-4o"
)

// Create an agent
let agent = Agent(model: model, instructions: "You are a helpful assistant.")

// Stream a response
for try await event in agent.streamExecute(messages: [
    AIMessage(role: .user, content: "Hello!")
]) {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .finish:
        print()
    default:
        break
    }
}
```

### Using legacy providers

```swift
let provider = OpenAIProvider(apiKey: "sk-...")
let model = AILanguageModelAdapter(
    llm: provider,
    provider: "openai",
    modelId: "gpt-4o",
    capabilities: [.text, .streaming]
)
```

## Providers

| Provider | Type | Setup |
|----------|------|-------|
| OpenAI (Responses) | `ProviderLanguageModelAdapter` | `.openAIResponses(apiKey:modelId:)` |
| OpenAI (Chat) | `ProviderLanguageModelAdapter` | `.openAIChatCompletions(apiKey:modelId:)` |
| OpenAI (Legacy) | `OpenAIProvider` | Wrap with `AILanguageModelAdapter` |
| Anthropic | `AnthropicProvider` | Wrap with `AILanguageModelAdapter` |
| Gemini | `GeminiProvider` | Wrap with `AILanguageModelAdapter` |
| OpenRouter | `OpenRouterClient` (actor) | `OpenRouterClient(apiKey:)` → `ProviderLanguageModelAdapter` |
| LiteLLM | `LiteLLMClient` (actor) | `LiteLLMClient(baseURL:)` → `ProviderLanguageModelAdapter` |

Legacy providers (`OpenAIProvider`, `AnthropicProvider`, `GeminiProvider`) must be wrapped with `AILanguageModelAdapter` to use with the v2 `Agent` and `LLM` protocol. The recommended path for new code is `ProviderLanguageModelAdapter` with factory methods.

## Features

- **Multi-provider agents** with tool calling, streaming, and structured output
- **Reliability** — retry policies, circuit breakers, failover, health monitoring
- **Generative UI** — spec-driven SwiftUI generation from LLM responses
- **Sessions** — persistence with InMemory, FileSystem, and SQLite stores
- **MCP** — Model Context Protocol client for external tool servers
- **Computer use** — Anthropic computer use tool integration
- **Web search** — built-in web search tool with citation support
- **Reasoning controls** — extended thinking for o1/o3 and Claude models
- **v1 compatibility** — typealiases and adapters for gradual migration

## Documentation

- [v2 API Reference](docs/AISDK-V2-REFERENCE.md)
- [Migration Guide (v1 to v2)](docs/MIGRATION-GUIDE.md)
- [Architecture](docs/AISDK-ARCHITECTURE.md)
- [What's New in v2](docs/WHATS_NEW_AISDK_2.md)
- [Changelog](CHANGELOG.md)
- [Examples](Examples/)

## Migration from v1

v1 type aliases (`ChatMessage`, `AgentState`, `Message`) are included so existing code compiles without changes. See the [Migration Guide](docs/MIGRATION-GUIDE.md) for the incremental path to native v2 APIs.

## License

MIT
