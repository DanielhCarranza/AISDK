# Agents

> Agent implementation for multi-step AI workflows

## AIAgent Protocol vs AIAgentActor

AISDK provides two related but distinct types for agent functionality:

- **`AIAgent`** (protocol) - Defines the unified interface for AI agents. Located in `Sources/AISDK/Core/Protocols/AIAgent.swift`.
- **`AIAgentActor`** (actor) - The concrete actor-based implementation of the agent pattern. Located in `Sources/AISDK/Agents/AIAgentActor.swift`.

The protocol defines the contract (properties like `agentId`, `state`, `messages`, `tools` and methods like `send()`, `sendStream()`, `reset()`), while the actor provides the thread-safe, observable implementation.

In most cases, you'll use `AIAgentActor` directly for creating agents.

---

## AIAgentActor

The primary agent implementation using Swift actors.

```swift
public actor AIAgentActor {
    /// Execute a non-streaming agent loop
    public func execute(messages: [AIMessage]) async throws -> AIAgentResult

    /// Execute a streaming agent loop
    public nonisolated func streamExecute(messages: [AIMessage]) -> AsyncThrowingStream<AIStreamEvent, Error>

    /// Current state of the agent
    public var state: AgentState { get }

    /// Message history
    public var messages: [AIMessage] { get }

    /// Step history
    public var steps: [AIStepResult] { get }

    /// Observable state for SwiftUI
    public nonisolated let observableState: ObservableAgentState
}
```

### Initialization

```swift
public init(
    model: any AILanguageModel,
    tools: [AITool.Type] = [],
    instructions: String? = nil,
    requestOptions: AIAgentActor.RequestOptions = AIAgentActor.RequestOptions(),
    stopCondition: StopCondition = .stepCount(20),
    timeout: TimeoutPolicy = .default,
    maxToolRounds: Int = 10,
    name: String? = nil,
    agentId: String? = nil
)
```

### Usage

```swift
// Create agent with tools
let agent = AIAgentActor(
    model: openRouterClient,
    tools: [WeatherTool.self, SearchTool.self],
    instructions: "You are a helpful assistant."
)

// Execute (non-streaming)
let result = try await agent.execute(
    messages: [.user("What's the weather in Tokyo?")]
)
print(result.text)

// Execute (streaming)
for try await event in agent.streamExecute(messages: messages) {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .toolCallStart(_, let name):
        print("\n[Calling \(name)...]")
    case .toolResult(_, let result, _):
        print("\n[Tool result: \(result)]")
    case .finish:
        print("\n[Done]")
    default:
        break
    }
}
```

---

## AIAgentResult

Result from agent execution.

```swift
public struct AIAgentResult: Sendable {
    /// Final text response
    public let text: String

    /// Steps executed during the agent loop
    public let steps: [AIStepResult]

    /// All messages in the conversation
    public let messages: [AIMessage]

    /// Total token usage
    public let usage: AIUsage
}
```

---

## StopCondition

Controls when agent execution stops.

```swift
public enum StopCondition: Sendable {
    /// Stop after N steps
    case stepCount(Int)

    /// Stop when no tool calls are made
    case noToolCalls

    /// Stop when token budget is exceeded
    case tokenBudget(maxTokens: Int)

    /// Custom stop condition
    case custom(@Sendable (AIStepResult) -> Bool)
}
```

### Usage

```swift
// Stop after 5 steps
let result = try await agent.execute(
    messages: messages,
    stopCondition: .stepCount(5)
)

// Stop when email is sent
let result = try await agent.execute(
    messages: messages,
    stopCondition: .toolCalled("send_email")
)

// Custom condition
let result = try await agent.execute(
    messages: messages,
    stopCondition: .custom { result in
        result.text.contains("DONE")
    }
)
```

---

## ObservableAgentState

SwiftUI-compatible observable state for agents.

```swift
@Observable
public final class ObservableAgentState: Sendable {
    /// Current agent state
    public private(set) var state: AIAgentState

    /// Current text being generated
    public private(set) var currentText: String

    /// Active tool being executed
    public private(set) var activeTool: String?

    /// Error message if any
    public private(set) var error: String?

    /// Whether the agent is currently processing
    public var isProcessing: Bool

    /// Stream of state changes
    public var stateStream: AsyncStream<AIAgentState>
}
```

### SwiftUI Integration

```swift
struct ChatView: View {
    let agent: AIAgentActor
    @State private var state: ObservableAgentState

    var body: some View {
        VStack {
            // Show current state
            switch state.state {
            case .idle:
                Text("Ready")
            case .thinking:
                ProgressView("Thinking...")
            case .executingTool(let name):
                Text("Running \(name)...")
            case .responding:
                Text(state.currentText)
            case .error(let message):
                Text("Error: \(message)")
                    .foregroundColor(.red)
            }
        }
        .task {
            // Subscribe to state changes
            for await newState in state.stateStream {
                // State updates automatically
            }
        }
    }
}
```

---

## AIAgentConfiguration

Configuration options for creating an agent.

```swift
public struct AIAgentConfiguration: Sendable {
    /// The language model to use
    public let model: AILanguageModel

    /// Tool schemas available to the agent
    public let tools: [ToolSchema]

    /// System instructions for the agent
    public let instructions: String?

    /// Initial conversation history
    public let initialMessages: [AIMessage]

    /// Maximum number of tool execution rounds
    public let maxToolRounds: Int

    /// Data sensitivity for PHI protection
    public let sensitivity: DataSensitivity

    /// Optional agent name
    public let name: String?
}
```

### AIAgentCallbacks

```swift
public protocol AIAgentCallbacks: AnyObject, Sendable {
    /// Called when the agent state changes
    func onStateChange(state: AIAgentState) async

    /// Called when a message is received
    func onMessageReceived(message: AIMessage) async -> AIAgentCallbackResult

    /// Called before a tool is executed
    func onBeforeToolExecution(name: String, arguments: String) async -> AIAgentCallbackResult

    /// Called after a tool is executed
    func onAfterToolExecution(name: String, result: String, metadata: ToolMetadata?) async -> AIAgentCallbackResult

    /// Called when a tool execution fails
    func onToolError(name: String, error: Error) async -> AIAgentCallbackResult
}
```

---

## Execution Flow

```
User Message
     │
     ▼
┌─────────────────────────┐
│   Add to messages       │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│   Send to LLM           │◄──────┐
└───────────┬─────────────┘       │
            │                      │
            ▼                      │
      ┌─────────────┐              │
      │ Tool calls? │              │
      └──────┬──────┘              │
             │                      │
    ┌────────┴────────┐            │
    │Yes              │No          │
    ▼                 ▼            │
┌─────────────┐  ┌─────────────┐  │
│Execute tools│  │   Done      │  │
└──────┬──────┘  └─────────────┘  │
       │                           │
       ▼                           │
┌─────────────────────────┐       │
│Add tool results to msgs │───────┘
└─────────────────────────┘
```

---

## Error Handling

```swift
public enum AIAgentError: Error, Sendable {
    case operationCancelled
    case toolExecutionFailed(String)
    case invalidToolResponse
    case maxToolRoundsExceeded
    case noResponse
    case streamError(String)
    case configurationError(String)
    case underlying(Error)
}
```

### Handling Errors

```swift
do {
    let result = try await agent.execute(messages: messages)
} catch AIAgentError.maxToolRoundsExceeded {
    print("Agent hit max tool rounds")
} catch AIAgentError.toolExecutionFailed(let message) {
    print("Tool execution failed: \(message)")
} catch {
    print("Agent error: \(error)")
}
```

---

## Best Practices

### 1. Limit Max Steps

```swift
// Prevent runaway loops
let agent = AIAgentActor(
    model: model,
    tools: tools,
    stopCondition: .stepCount(10)
)
```

### 2. Use Instructions

```swift
let agent = AIAgentActor(
    model: model,
    tools: tools,
    instructions: """
        You are a research assistant.
        Always cite your sources.
        If unsure, say so.
        """
)
```

### 3. Inspect Tool Results Per Step

```swift
let result = try await agent.execute(messages: messages)

for step in result.steps {
    for toolResult in step.toolResults {
        print("Tool result: \(toolResult.result)")
    }
}
```

### 4. Use Streaming for Long Tasks

```swift
// Keep user informed during multi-step operations
for try await event in agent.streamExecute(messages: messages) {
    switch event {
    case .textDelta(let text):
        updateUI(text)
    case .toolCallStart(_, let name):
        showToolIndicator(name)
    default:
        break
    }
}
```

## See Also

- [Core Protocols](core-protocols.md) - AIAgent protocol
- [Tools](tools.md) - Creating tools for agents
- [Models](models.md) - Message and request types
