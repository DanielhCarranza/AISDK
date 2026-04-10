# Streaming Basics

> Real-time responses with AsyncThrowingStream

## Overview

Streaming lets you display responses as they're generated, providing a better user experience than waiting for the complete response.

## Basic Streaming

```swift
import AISDK

let client = OpenRouterClient(apiKey: "your-api-key")

let request = ProviderRequest(
    modelId: "openai/gpt-4",
    messages: [.user("Write a haiku about coding")]
)

// Stream the response
for try await event in client.stream(request: request) {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")

    case .finish(let reason, let usage):
        print("\n[Done: \(reason)]")

    default:
        break
    }
}
```

## Agent Streaming

For agent conversations with tool support:

```swift
let agent = Agent(model: client, tools: [])

for try await event in agent.streamExecute(messages: [.user("Count to 5")]) {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")

    case .toolCallStart(_, let name):
        print("\n[Calling \(name)...]")

    case .finish:
        print()

    default:
        break
    }
}
```

## SwiftUI Integration

```swift
struct ChatView: View {
    @State private var response = ""
    @State private var isLoading = false

    var body: some View {
        VStack {
            Text(response)
            if isLoading { ProgressView() }
        }
        .task { await streamResponse() }
    }

    func streamResponse() async {
        isLoading = true
        defer { isLoading = false }

        do {
            for try await event in agent.streamExecute(messages: messages) {
                if case .textDelta(let text) = event {
                    response += text
                }
            }
        } catch {
            response = "Error: \(error.localizedDescription)"
        }
    }
}
```

## Stream Events

| Event | Description |
|-------|-------------|
| `.start` | Stream beginning |
| `.textDelta` | Text chunk |
| `.toolCallStart` | Tool execution starting |
| `.toolCallDelta` | Tool arguments streaming |
| `.toolCall` | Tool call complete |
| `.toolResult` | Tool result received |
| `.usage` | Token usage stats |
| `.finish` | Stream complete |
| `.error` | Error occurred |

## Next Steps

- [Tool Creation](03-tool-creation.md) - Add custom tools
- [Multi-Step Agents](04-multi-step-agents.md) - Complex workflows
