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
    .package(url: "https://github.com/DanielhCarranza/AISDK.git", exact: "2.0.0-beta.1")
]
```

In Xcode: File > Add Package Dependencies, paste the repository URL, and select **Exact Version** `2.0.0-beta.1`.

> **Note:** Beta versions require `.exact()` — SPM does not resolve pre-release versions with range-based requirements like `.upToNextMajor()`.

## Quick Start

```swift
import AISDK

// Create a provider
let provider = OpenAIProvider(apiKey: "sk-...")

// Wrap in v2 adapter
let model = AILanguageModelAdapter(
    llm: provider,
    provider: "openai",
    modelId: "gpt-4o",
    capabilities: [.text, .tools, .streaming]
)

// Create an agent
let agent = Agent(model: model, systemPrompt: "You are a helpful assistant.")

// Stream a response
for try await event in agent.streamExecute("Hello!") {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .finished:
        print()
    default:
        break
    }
}
```

## Providers

| Provider | Class | Setup |
|----------|-------|-------|
| OpenAI | `OpenAIProvider` | `OpenAIProvider(apiKey: "sk-...")` |
| Anthropic | `AnthropicProvider` | `AnthropicProvider(apiKey: "sk-ant-...")` |
| Gemini | `GeminiProvider` | `GeminiProvider(apiKey: "AIza...")` |
| OpenRouter | `OpenRouterClient` | `OpenRouterClient(apiKey: "sk-or-...", appName: "MyApp")` |
| LiteLLM | `LiteLLMClient` | `LiteLLMClient(baseURL: URL(string: "http://localhost:4000")!)` |

All legacy providers (`OpenAIProvider`, `AnthropicProvider`, `GeminiProvider`) must be wrapped with `AILanguageModelAdapter` to use with the v2 `Agent` and `LLM` protocol.

## Features

- **Multi-provider agents** with tool calling, streaming, and structured output
- **Reliability** — retry policies, circuit breakers, failover, health monitoring
- **Generative UI** — spec-driven SwiftUI generation from LLM responses
- **Sessions** — persistence with InMemory, FileSystem, and SQLite stores
- **MCP** — Model Context Protocol client for external tool servers
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
