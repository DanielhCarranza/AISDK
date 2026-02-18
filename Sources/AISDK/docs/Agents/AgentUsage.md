# Agent Usage Guide

`AIAgentActor` is the core component of AISDK that manages interactions with AI language models and coordinates tool execution. It provides both non-streaming and streaming capabilities for building conversational AI applications.

## Table of Contents

1. [Overview](#overview)
2. [Initialization](#initialization)
3. [Basic Usage](#basic-usage)
4. [Streaming Conversations](#streaming-conversations)
5. [State Management](#state-management)
6. [Tool Integration](#tool-integration)
7. [Error Handling](#error-handling)
8. [Best Practices](#best-practices)
9. [Advanced Examples](#advanced-examples)

## Overview

`AIAgentActor` provides:
- **Actor-based concurrency**: Thread-safe by design using Swift actors
- **Provider-agnostic**: Works with any `AILanguageModel` provider (OpenRouter, LiteLLM, etc.)
- **Non-streaming execution**: Send messages and await a complete `AIAgentResult`
- **Streaming execution**: Real-time `AIStreamEvent` values via `AsyncThrowingStream`
- **Tool execution**: Automatic coordination of AI-requested tool calls
- **Observable state**: `@Observable` state for SwiftUI binding
- **Non-throwing init**: No `try` needed to create an agent

## Initialization

### Basic Initialization

```swift
import AISDK

// Create agent with OpenRouter (recommended multi-provider client)
let client = OpenRouterClient(apiKey: "your-api-key")
let agent = AIAgentActor(
    model: client,
    instructions: "You are a helpful assistant."
)

// Create agent targeting a specific model via ProviderRequest
// The model is specified per-request, not at agent creation
```

### With Tools

```swift
// Define available tools
let tools: [AITool.Type] = [
    WeatherTool.self,
    CalculatorTool.self,
    SearchTool.self
]

let client = OpenRouterClient(apiKey: "your-api-key")
let agent = AIAgentActor(
    model: client,
    tools: tools,
    instructions: "You are an assistant with access to weather, calculator, and search tools."
)
```

### With Initial Messages

```swift
// Pass conversation history as messages to execute/streamExecute
let history: [AIMessage] = [
    .user("Hello!"),
    .assistant("Hi! How can I help you today?"),
    .user("What's the weather?")
]

let client = OpenRouterClient(apiKey: "your-api-key")
let agent = AIAgentActor(model: client)

let result = try await agent.execute(messages: history)
```

## Basic Usage

### Non-Streaming Execution

Use `execute(messages:)` for simple request-response interactions:

```swift
do {
    let result = try await agent.execute(messages: [.user("What's the weather like in Paris?")])
    print("Agent response: \(result.text)")
} catch {
    print("Error: \(error.localizedDescription)")
}
```

### Passing Conversation History

```swift
// Pass full conversation history with each call
let messages: [AIMessage] = [
    .user("Previous question"),
    .assistant("Previous answer"),
    .user("Follow-up question")
]

let result = try await agent.execute(messages: messages)
```

### Simple Tool Usage

```swift
// Agent automatically uses tools when needed
let client = OpenRouterClient(apiKey: "your-api-key")
let agent = AIAgentActor(
    model: client,
    tools: [WeatherTool.self, CalculatorTool.self]
)

let result = try await agent.execute(messages: [.user("What's 15 * 23 and what's the weather in Tokyo?")])
print(result.text)
```

## Streaming Conversations

Streaming provides real-time response updates, ideal for chat interfaces:

### Basic Streaming

```swift
for try await event in agent.streamExecute(messages: [.user("Tell me a story")]) {
    switch event {
    case .textDelta(let text):
        // Append streaming text to UI
        print(text, terminator: "")

    case .toolCallStart(let id, let name):
        print("\n[Calling \(name)...]")

    case .toolResult(let id, let result):
        print("[Tool result: \(result.content)]")

    case .finish(let reason, let usage):
        print("\n[Done: \(reason)]")

    default:
        break
    }
}
```

### Stream Events Reference

| Event | Description |
|-------|-------------|
| `.start` | Stream beginning |
| `.textDelta(String)` | Text chunk |
| `.toolCallStart(id, name)` | Tool execution starting |
| `.toolCallDelta(id, argsDelta)` | Tool arguments streaming |
| `.toolCall(id, name, args)` | Tool call complete |
| `.toolResult(id, result)` | Tool result received |
| `.usage(TokenUsage)` | Token usage stats |
| `.finish(reason, usage)` | Stream complete |
| `.error(Error)` | Error occurred |

## State Management

### Observable State

`AIAgentActor` provides an `@Observable` state object for SwiftUI binding:

```swift
@Observable
public final class ObservableAgentState {
    public var isProcessing: Bool = false
    public var currentTool: String? = nil
    public var error: Error? = nil
}
```

### SwiftUI Integration

```swift
struct ChatView: View {
    let agent: AIAgentActor

    var body: some View {
        VStack {
            if agent.observableState.isProcessing {
                ProgressView("Processing...")
            }

            if let tool = agent.observableState.currentTool {
                Text("Using \(tool)...")
            }
        }
    }
}
```

### Stream-Based State Tracking

For more granular control, track state through stream events:

```swift
func processWithStateTracking(message: String) async {
    for try await event in agent.streamExecute(messages: [.user(message)]) {
        switch event {
        case .start:
            showLoadingIndicator("Thinking...")

        case .toolCallStart(_, let name):
            showLoadingIndicator("Using \(name)...")

        case .textDelta(let text):
            showLoadingIndicator("Responding...")
            appendToUI(text)

        case .finish:
            hideLoadingIndicator()

        case .error(let error):
            showError(error.localizedDescription)

        default:
            break
        }
    }
}
```

## Tool Integration

### Tool Execution Flow

1. User sends message
2. Agent processes with LLM
3. LLM requests tool execution
4. Agent executes tool(s)
5. Agent sends tool results back to LLM
6. LLM provides final response

### Handling Tool Responses

```swift
// Tools can return immediate responses
struct QuickAnswerTool: AITool {
    let name = "quick_answer"
    let description = "Returns a quick answer without model mediation"
    let returnToolResponse = true

    init() {}

    func execute() async throws -> AIToolResult {
        return AIToolResult(content: "Quick answer")
    }
}
```

### Tool Metadata

Tools can return metadata (files, images, etc.):

```swift
struct FileMetadata: ToolMetadata {
    let path: String
}

func execute() async throws -> AIToolResult {
    let result = "File created successfully"
    let metadata = FileMetadata(path: "/path/to/file.txt")
    let artifact = ToolArtifact(name: "file.txt", kind: .file, url: URL(fileURLWithPath: "/path/to/file.txt"))
    return AIToolResult(content: result, metadata: metadata, artifacts: [artifact])
}
```

## Error Handling

### Agent Errors

```swift
do {
    let result = try await agent.execute(messages: [.user("Hello")])
    print(result.text)
} catch AgentError.toolExecutionFailed(let message) {
    print("Tool failed: \(message)")
} catch AgentError.operationCancelled {
    print("Operation was cancelled")
} catch {
    print("Other error: \(error)")
}
```

### Streaming Error Handling

```swift
do {
    for try await event in agent.streamExecute(messages: [.user("Hello")]) {
        switch event {
        case .textDelta(let text):
            print(text, terminator: "")
        case .error(let error):
            handleStreamingError(error)
        default:
            break
        }
    }
} catch {
    handleStreamingError(error)
}
```

### Observable Error State

```swift
// Check for errors via observable state
if let error = agent.observableState.error {
    handleAgentError(error)
}
```

## Best Practices

### 1. Use Observable State for UI

```swift
struct AgentStatusView: View {
    let agent: AIAgentActor

    var body: some View {
        Group {
            if agent.observableState.isProcessing {
                ProgressView()
            }
        }
    }
}
```

### 2. Tool Selection

```swift
// Use specific tools for specific tasks
let client = OpenRouterClient(apiKey: "your-api-key")

let calculatorAgent = AIAgentActor(
    model: client,
    tools: [CalculatorTool.self],
    instructions: "You are a calculator assistant. Use the calculator tool for all math operations."
)

let weatherAgent = AIAgentActor(
    model: client,
    tools: [WeatherTool.self],
    instructions: "You provide weather information using the weather tool."
)
```

### 3. Error Recovery

```swift
func sendWithRetry(_ message: String, retries: Int = 3) async throws -> AIAgentResult {
    for attempt in 1...retries {
        do {
            return try await agent.execute(messages: [.user(message)])
        } catch {
            if attempt == retries { throw error }
            try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(attempt))
        }
    }
    throw AgentError.operationCancelled
}
```

## Advanced Examples

### 1. Context-Aware Agent

```swift
class ContextAwareAgent {
    private let agent: AIAgentActor
    private var context: [String: Any] = [:]

    init() {
        let client = OpenRouterClient(apiKey: "your-api-key")
        self.agent = AIAgentActor(
            model: client,
            instructions: "Use provided context to personalize responses."
        )
    }

    func updateContext(_ key: String, value: Any) {
        context[key] = value
    }

    func sendWithContext(_ message: String) async throws -> AIAgentResult {
        let contextualMessage = "Context: \(context)\n\nUser: \(message)"
        return try await agent.execute(messages: [.user(contextualMessage)])
    }
}
```

### 2. Multi-Agent Orchestration

```swift
class MultiAgentOrchestrator {
    let researchAgent: AIAgentActor
    let writerAgent: AIAgentActor

    init(model: any AILanguageModel) {
        self.researchAgent = AIAgentActor(
            model: model,
            tools: [SearchTool.self],
            instructions: "You are a research assistant. Find facts and evidence."
        )
        self.writerAgent = AIAgentActor(
            model: model,
            instructions: "You are a writer. Synthesize research into clear prose."
        )
    }

    func researchAndWrite(topic: String) async throws -> String {
        // Step 1: Research
        let research = try await researchAgent.execute(
            messages: [.user("Research: \(topic)")]
        )

        // Step 2: Write based on research
        let article = try await writerAgent.execute(
            messages: [
                .system("Use the following research:\n\(research.text)"),
                .user("Write a summary of: \(topic)")
            ]
        )

        return article.text
    }
}
```
