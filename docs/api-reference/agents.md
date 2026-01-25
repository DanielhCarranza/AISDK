# Agents

> Agent implementation for multi-step AI workflows

## AIAgentActor

The primary agent implementation using Swift actors.

```swift
public actor AIAgentActor: AIAgent {
    // MARK: - Properties

    /// The underlying language model
    public let model: any AILanguageModel

    /// Available tools
    public let tools: [AnyAITool]

    /// System prompt for the agent
    public let systemPrompt: String?

    /// Maximum steps before stopping
    public let maxSteps: Int

    /// Whether to execute tools in parallel
    public let parallelToolCalls: Bool
}
```

### Initialization

```swift
public init(
    model: any AILanguageModel,
    tools: [any AITool.Type] = [],
    systemPrompt: String? = nil,
    maxSteps: Int = 10,
    parallelToolCalls: Bool = true,
    configuration: AIAgentConfiguration = .default
)

// Convenience initializer with tool type array
public init(
    model: any AILanguageModel,
    tools: [AnyAITool],
    systemPrompt: String? = nil,
    maxSteps: Int = 10
)
```

### Usage

```swift
// Create agent with tools
let agent = AIAgentActor(
    model: openRouterClient,
    tools: [WeatherTool.self, SearchTool.self],
    systemPrompt: "You are a helpful assistant.",
    maxSteps: 10
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

    /// All messages in the conversation
    public let messages: [AIMessage]

    /// Tool calls made during execution
    public let toolCalls: [AIToolCall]

    /// Tool results from execution
    public let toolResults: [AIToolResult]

    /// Total token usage
    public let usage: AIUsage

    /// Final finish reason
    public let finishReason: AIFinishReason

    /// Number of steps taken
    public let steps: Int
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
    case tokenBudget(Int)

    /// Stop when specific tool is called
    case toolCalled(String)

    /// Custom stop condition
    case custom(@Sendable (AIAgentResult) -> Bool)
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

Configuration options for agent behavior.

```swift
public struct AIAgentConfiguration: Sendable {
    /// Default timeout for operations
    public let timeout: Duration

    /// Whether to include tool results in response
    public let includeToolResults: Bool

    /// Whether to retry failed tool calls
    public let retryFailedTools: Bool

    /// Maximum retries per tool
    public let maxToolRetries: Int

    /// Callbacks for agent events
    public let callbacks: AIAgentCallbacks?

    public static let `default` = AIAgentConfiguration()
}
```

### AIAgentCallbacks

```swift
public struct AIAgentCallbacks: Sendable {
    /// Called before each step
    public let onStepStart: (@Sendable (Int) async -> Void)?

    /// Called after each step
    public let onStepEnd: (@Sendable (Int, AIAgentStepResult) async -> Void)?

    /// Called when a tool is about to execute
    public let onToolStart: (@Sendable (String, String) async -> Void)?

    /// Called after tool execution
    public let onToolEnd: (@Sendable (String, AIToolResult) async -> Void)?
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
    /// Maximum steps exceeded
    case maxStepsExceeded(Int)

    /// Tool execution failed
    case toolExecutionFailed(tool: String, error: Error)

    /// Tool not found
    case toolNotFound(String)

    /// Invalid tool arguments
    case invalidToolArguments(tool: String, reason: String)

    /// Model error
    case modelError(Error)

    /// Operation cancelled
    case cancelled
}
```

### Handling Errors

```swift
do {
    let result = try await agent.execute(messages: messages)
} catch AIAgentError.maxStepsExceeded(let steps) {
    print("Agent hit limit after \(steps) steps")
} catch AIAgentError.toolExecutionFailed(let tool, let error) {
    print("Tool \(tool) failed: \(error)")
} catch AIAgentError.toolNotFound(let name) {
    print("Unknown tool: \(name)")
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
    maxSteps: 10  // Reasonable limit
)
```

### 2. Use System Prompts

```swift
let agent = AIAgentActor(
    model: model,
    tools: tools,
    systemPrompt: """
        You are a research assistant.
        Always cite your sources.
        If unsure, say so.
        """
)
```

### 3. Handle Errors Gracefully

```swift
let result = try await agent.execute(messages: messages)

// Check if tools had errors
for toolResult in result.toolResults {
    if toolResult.isError {
        print("Tool error: \(toolResult.content)")
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
