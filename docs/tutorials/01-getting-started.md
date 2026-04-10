# Getting Started with AISDK

> A quick introduction to AISDK for Swift developers

## Prerequisites

- Swift 5.9 or later
- iOS 17+ / macOS 14+ / watchOS 10+ / tvOS 17+
- Xcode 15 or later

## Installation

Add AISDK to your Swift package:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/your-org/AISDK.git", from: "2.0.0")
]
```

Or add via Xcode: File > Add Package Dependencies.

## Your First Request

```swift
import AISDK

// Create a provider client
let client = OpenRouterClient(apiKey: "your-api-key")

// Make a simple request
let request = ProviderRequest(
    modelId: "openai/gpt-4",
    messages: [.user("Hello! What is 2 + 2?")]
)

let response = try await client.execute(request: request)
print(response.content)
// Output: "2 + 2 equals 4."
```

## Using the Agent

For conversations with tool support, use `Agent`:

```swift
let agent = Agent(
    model: client,
    tools: [],
    instructions: "You are a helpful assistant."
)

let result = try await agent.execute(
    messages: [.user("Tell me a joke")]
)

print(result.text)
```

## Environment Variables

AISDK supports API keys via environment variables:

- `OPENROUTER_API_KEY` - OpenRouter
- `OPENAI_API_KEY` - OpenAI
- `ANTHROPIC_API_KEY` - Anthropic
- `GOOGLE_API_KEY` or `GEMINI_API_KEY` - Google

```swift
// API key is read from environment automatically
let client = OpenRouterClient()
```

## Next Steps

- [Streaming Basics](02-streaming-basics.md) - Real-time responses
- [Tool Creation](03-tool-creation.md) - Adding custom tools
- [Multi-Step Agents](04-multi-step-agents.md) - Complex workflows
- [Sessions & Persistence](08-sessions.md) - Persist conversations across app launches
