# Agent Usage Guide

The Agent class is the core component of AISDK that manages interactions with AI language models and coordinates tool execution. It provides both synchronous and asynchronous streaming capabilities for building conversational AI applications.

## Table of Contents

1. [Overview](#overview)
2. [Initialization](#initialization)
3. [Basic Usage](#basic-usage)
4. [Streaming Conversations](#streaming-conversations)
5. [State Management](#state-management)
6. [Callbacks System](#callbacks-system)
7. [Tool Integration](#tool-integration)
8. [Error Handling](#error-handling)
9. [Best Practices](#best-practices)
10. [Advanced Examples](#advanced-examples)

## Overview

The Agent class provides:
- **Provider-centric architecture**: Works directly with OpenAI, Anthropic, and Gemini providers
- **Synchronous messaging**: Send a message and wait for a complete response
- **Streaming messaging**: Real-time streaming responses for dynamic UI updates
- **Tool execution**: Automatic coordination of AI-requested tool calls
- **State management**: Track agent processing states (idle, thinking, executing tools, etc.)
- **Callback system**: Hook into agent lifecycle events for custom behavior
- **Message history**: Maintain conversation context automatically

## Initialization

### Provider-Centric Initialization (Recommended)

```swift
import AISDK

// Create agent with OpenAI provider (uses smart default: gpt-4o)
let openai = OpenAIProvider()
let agent = Agent(
    llm: openai,
    instructions: "You are a helpful assistant."
)

// Create agent with specific model
let openaiMini = OpenAIProvider(model: OpenAIModels.gpt4oMini)
let agentMini = Agent(llm: openaiMini)

// Create agent with Anthropic provider (uses smart default: sonnet-3.7)
let anthropic = AnthropicService()
let claudeAgent = Agent(
    llm: anthropic,
    instructions: "You are a helpful assistant."
)

// Create agent with Gemini provider (uses smart default: gemini-2.5-flash)
let gemini = GeminiProvider()
let geminiAgent = Agent(
    llm: gemini,
    instructions: "You are a helpful assistant."
)
```

### With Tools

```swift
// Define available tools
let tools: [Tool.Type] = [
    WeatherTool.self,
    CalculatorTool.self,
    SearchTool.self
]

let openai = OpenAIProvider()
let agent = Agent(
    llm: openai,
    tools: tools,
    instructions: "You are an assistant with access to weather, calculator, and search tools."
)
```

### With Initial Messages

```swift
// Start with conversation history
let initialMessages = [
    ChatMessage(message: .user(content: .text("Hello!"))),
    ChatMessage(message: .assistant(content: .text("Hi! How can I help you today?")))
]

let openai = OpenAIProvider()
let agent = Agent(
    llm: openai,
    tools: tools,
    messages: initialMessages,
    instructions: "Continue this conversation naturally."
)
```

### Legacy Initialization (Backward Compatibility)

```swift
// Legacy approach - still supported but deprecated
let agent = Agent(
    model: AgenticModels.gpt4,
    tools: [],
    instructions: "You are a helpful assistant."
)
```

## Basic Usage

### Synchronous Messaging

Use `send(_:)` for simple request-response interactions:

```swift
do {
    let response = try await agent.send("What's the weather like in Paris?")
    print("Agent response: \(response.displayContent)")
} catch {
    print("Error: \(error.localizedDescription)")
}
```

### Setting Message History

```swift
// Update the conversation history
let newMessages = [
    ChatMessage(message: .user(content: .text("Previous question"))),
    ChatMessage(message: .assistant(content: .text("Previous answer")))
]

agent.setMessages(newMessages)
```

### Simple Tool Usage

```swift
// Agent automatically uses tools when needed
let openai = OpenAIProvider()
let agent = Agent(
    llm: openai,
    tools: [WeatherTool.self, CalculatorTool.self]
)

let response = try await agent.send("What's 15 * 23 and what's the weather in Tokyo?")
print(response.displayContent)
```

## Streaming Conversations

Streaming provides real-time response updates, ideal for chat interfaces:

### Basic Streaming

```swift
let userMessage = ChatMessage(message: .user(content: .text("Tell me a story")))

for try await message in agent.sendStream(userMessage) {
    switch message.message {
    case .assistant(let content):
        // Update UI with streaming content
        updateChatUI(with: content.text ?? "")
        
    case .tool(let content, let name, _):
        // Handle tool execution feedback
        print("Tool \(name) executed: \(content)")
        
    default:
        break
    }
}
```

### Streaming with Required Tool

Force the agent to use a specific tool:

```swift
let userMessage = ChatMessage(message: .user(content: .text("Calculate 15 * 23")))

for try await message in agent.sendStream(userMessage, requiredTool: "calculator") {
    // Handle streaming response
    handleStreamingMessage(message)
}
```

### Handling Streaming States

```swift
func handleStreamingMessage(_ message: ChatMessage) {
    if message.isPending {
        // Message is still being streamed
        updateTypingIndicator()
    } else {
        // Message is complete
        finalizeMessage(message)
    }
    
    // Access metadata if available
    if let metadata = message.metadata {
        processMetadata(metadata)
    }
}
```

## State Management

### Agent States

The agent maintains internal state that you can observe:

```swift
public enum AgentState {
    case idle                    // Ready for new requests
    case thinking               // Processing user input
    case executingTool(String)  // Running a specific tool
    case responding             // Generating response
    case error(AIError)         // Error occurred
}
```

### State Observation

```swift
// Monitor state changes for UI updates
agent.onStateChange = { state in
    DispatchQueue.main.async {
        switch state {
        case .idle:
            hideLoadingIndicator()
            
        case .thinking:
            showLoadingIndicator("Thinking...")
            
        case .executingTool(let toolName):
            showLoadingIndicator("Using \(toolName)...")
            
        case .responding:
            showLoadingIndicator("Responding...")
            
        case .error(let error):
            showError(error.localizedDescription)
        }
    }
}
```

### State Properties

```swift
// Check if agent is busy
if agent.state.isProcessing {
    // Show loading UI
}

// Get status message for UI
let statusMessage = agent.state.statusMessage
updateStatusLabel(statusMessage)
```

## Callbacks System

Callbacks allow you to hook into the agent's lifecycle for custom behavior:

### Implementing Callbacks

```swift
class MyAgentCallbacks: AgentCallbacks {
    func onMessageReceived(message: Message) async -> CallbackResult {
        // Log incoming messages
        print("Received: \(message)")
        return .continue
    }
    
    func onBeforeToolExecution(name: String, arguments: String) async -> CallbackResult {
        // Validate or modify tool execution
        print("About to execute \(name) with \(arguments)")
        
        // You can cancel execution
        if name == "dangerous_tool" {
            return .cancel
        }
        
        return .continue
    }
    
    func onAfterToolExecution(name: String, result: String) async -> CallbackResult {
        // Process tool results
        print("Tool \(name) completed with result: \(result)")
        return .continue
    }
    
    func onStreamChunk(chunk: Message) async -> CallbackResult {
        // Handle streaming chunks
        return .continue
    }
}
```

### Registering Callbacks

```swift
let callbacks = MyAgentCallbacks()
agent.addCallbacks(callbacks)

// Remove when done
agent.removeCallbacks(callbacks)
```

### Metadata Tracking

Use the built-in `MetadataTracker` for tool metadata:

```swift
let metadataTracker = MetadataTracker()
agent.addCallbacks(metadataTracker)

// Access metadata after tool execution
if let metadata = metadataTracker.lastMetadata {
    // Process metadata (files, images, etc.)
    handleToolMetadata(metadata)
}
```

### Callback Results

Callbacks can modify agent behavior:

```swift
func onMessageReceived(message: Message) async -> CallbackResult {
    // Continue normal processing
    return .continue
    
    // Cancel current operation
    return .cancel
    
    // Replace message with custom content
    let customMessage = Message.assistant(content: .text("Custom response"))
    return .replace(customMessage)
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
class QuickAnswerTool: Tool {
    var returnToolResponse: Bool = true  // Skip LLM interpretation
    
    func execute() async throws -> (String, ToolMetadata?) {
        return ("Quick answer", nil)
    }
}
```

### Tool Metadata

Tools can return metadata (files, images, etc.):

```swift
func execute() async throws -> (String, ToolMetadata?) {
    let result = "File created successfully"
    let metadata = ToolMetadata(
        files: [URL(fileURLWithPath: "/path/to/file.txt")],
        images: [],
        data: ["key": "value"]
    )
    return (result, metadata)
}
```

## Error Handling

### Agent Errors

```swift
do {
    let response = try await agent.send("Hello")
    print(response.displayContent)
} catch AgentError.toolExecutionFailed(let message) {
    print("Tool failed: \(message)")
} catch AgentError.invalidToolResponse {
    print("Invalid tool response")
} catch AgentError.operationCancelled {
    print("Operation was cancelled")
} catch {
    print("Other error: \(error)")
}
```

### Streaming Error Handling

```swift
do {
    for try await message in agent.sendStream(userMessage) {
        handleMessage(message)
    }
} catch {
    handleStreamingError(error)
}
```

### Error States

```swift
agent.onStateChange = { state in
    if case .error(let error) = state {
        handleAgentError(error)
    }
}
```

## Best Practices

### 1. State Management

```swift
// Always observe state changes for UI updates
agent.onStateChange = { state in
    DispatchQueue.main.async {
        updateUI(for: state)
    }
}
```


### 3. Tool Selection

```swift
// Use specific tools for specific tasks
let calculatorAgent = try Agent(
    model: model,
    tools: [CalculatorTool.self],
    instructions: "You are a calculator assistant. Use the calculator tool for all math operations."
)

let weatherAgent = try Agent(
    model: model,
    tools: [WeatherTool.self],
    instructions: "You provide weather information using the weather tool."
)
```

### 4. Error Recovery

```swift
func sendWithRetry(_ message: String, retries: Int = 3) async throws -> ChatMessage {
    for attempt in 1...retries {
        do {
            return try await agent.send(message)
        } catch {
            if attempt == retries { throw error }
            try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(attempt))
        }
    }
    throw AgentError.operationCancelled
}
```

## Advanced Examples


### 2. Function Calling with Validation

```swift
class ValidatedAgent {
    private let agent: Agent
    
    init(model: LLMModel, tools: [Tool.Type]) throws {
        self.agent = try Agent(model: model, tools: tools)
        
        // Add validation callback
        let validator = ToolValidator()
        agent.addCallbacks(validator)
    }
}

class ToolValidator: AgentCallbacks {
    func onBeforeToolExecution(name: String, arguments: String) async -> CallbackResult {
        // Validate tool arguments
        guard validateToolArguments(name: name, arguments: arguments) else {
            return .cancel
        }
        
        // Check permissions
        guard hasPermissionForTool(name) else {
            let deniedMessage = Message.assistant(content: .text("I don't have permission to use \(name)."))
            return .replace(deniedMessage)
        }
        
        return .continue
    }
    
    private func validateToolArguments(name: String, arguments: String) -> Bool {
        // Custom validation logic
        return true
    }
    
    private func hasPermissionForTool(_ name: String) -> Bool {
        // Permission checking logic
        return true
    }
}
```

### 3. Context-Aware Agent

```swift
class ContextAwareAgent {
    private let agent: Agent
    private var context: [String: Any] = [:]
    
    init() {
        let openai = OpenAIProvider()
        self.agent = Agent(
            llm: openai,
            instructions: "Use provided context to personalize responses."
        )
    }
    
    func updateContext(_ key: String, value: Any) {
        context[key] = value
    }
    
    func sendWithContext(_ message: String) async throws -> ChatMessage {
        let contextualMessage = "Context: \(context)\n\nUser: \(message)"
        return try await agent.send(contextualMessage)
    }
}
```

