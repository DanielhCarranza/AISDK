# AISDK 2.0 Migration Guide

> Migrating from AISDK 1.x to AISDK 2.0

This guide helps you migrate existing code from AISDK 1.x to the modernized AISDK 2.0 architecture.

---

## Table of Contents

1. [Overview](#overview)
2. [Breaking Changes Summary](#breaking-changes-summary)
3. [Migration Adapters](#migration-adapters)
4. [Migrating LLM Providers](#migrating-llm-providers)
5. [Migrating Agents](#migrating-agents)
6. [Migrating Tools](#migrating-tools)
7. [Migrating Message Types](#migrating-message-types)
8. [Migrating Streaming Code](#migrating-streaming-code)
9. [Common Pitfalls](#common-pitfalls)
10. [Incremental Migration Strategy](#incremental-migration-strategy)

---

## Overview

AISDK 2.0 introduces significant architectural improvements:

| Aspect | 1.x | 2.0 |
|--------|-----|-----|
| **Concurrency** | Closures, GCD | Swift Concurrency (`async`/`await`) |
| **Agent** | Class-based (`Agent`) | Actor-based (`AIAgentActor`) |
| **Streaming** | Callback-based | `AsyncThrowingStream` |
| **State** | KVO patterns | `@Observable` |
| **Reliability** | None | Circuit breakers, failover, health monitoring |
| **Provider Protocol** | `LLM` protocol | `AILanguageModel` protocol |
| **Tool Protocol** | `Tool` with `@Parameter` | `AITool` protocol |

To enable gradual migration, AISDK 2.0 provides **adapter classes** that wrap legacy implementations.

---

## Breaking Changes Summary

### Protocol Changes

```swift
// 1.x Protocol
protocol LLM {
    func sendChatCompletion(request: ChatCompletionRequest) async throws -> ChatCompletionResponse
    func sendChatCompletionStream(request: ChatCompletionRequest) async throws -> AsyncThrowingStream<ChatCompletionChunk, Error>
}

// 2.0 Protocol
protocol AILanguageModel {
    var provider: String { get }
    var modelId: String { get }
    var capabilities: LLMCapabilities { get }

    func generateText(request: AITextRequest) async throws -> AITextResult
    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
    func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T>
    func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error>
}
```

### Agent Changes

```swift
// 1.x Agent (class-based)
let agent = Agent(llm: provider, tools: [WeatherTool.self])
let response = try await agent.send("Hello")

// 2.0 Agent (actor-based)
let agent = AIAgentActor(model: languageModel, tools: [weatherTool])
let result = try await agent.execute(messages: [.user("Hello")])
```

### Message Changes

```swift
// 1.x Messages
let message = Message.user(content: .text("Hello"))
let systemMessage = Message.system(content: .text("You are helpful"))

// 2.0 Messages
let message = AIMessage.user("Hello")
let systemMessage = AIMessage.system("You are helpful")
```

---

## Migration Adapters

AISDK 2.0 provides three adapter classes for incremental migration.

### AILanguageModelAdapter

Wraps a legacy `LLM` to conform to `AILanguageModel`:

```swift
import AISDK

// Existing 1.x code
let openai = OpenAIProvider(apiKey: "sk-...")

// Wrap with adapter
let adaptedModel = AILanguageModelAdapter(
    llm: openai,
    provider: "openai",
    modelId: "gpt-4",
    capabilities: [.text, .tools, .streaming, .vision]
)

// Now use with 2.0 agent
let agent = AIAgentActor(model: adaptedModel, tools: [])
let result = try await agent.execute(messages: [.user("Hello")])
```

**Factory methods for common providers:**

```swift
// OpenAI
let adapted = AILanguageModelAdapter.fromOpenAI(openaiProvider, model: "gpt-4")

// Anthropic
let adapted = AILanguageModelAdapter.fromAnthropic(anthropicProvider, model: "claude-3-opus")

// Any LLM
let adapted = AILanguageModelAdapter.from(
    customLLM,
    provider: "custom",
    model: "my-model",
    capabilities: [.text, .streaming]
)
```

### ToolAdapter

Wraps a legacy `Tool` for use with the new agent system:

```swift
// Existing 1.x tool
class WeatherTool: Tool {
    let name = "get_weather"
    let description = "Get weather for a location"

    @Parameter(description: "City name")
    var location: String = ""

    func execute() async throws -> (String, ToolMetadata?) {
        return ("Weather in \(location): Sunny, 72F", nil)
    }
}

// Wrap with adapter
let weatherAdapter = try ToolAdapter(toolType: WeatherTool.self)

// Use with 2.0 agent
let agent = AIAgentActor(
    model: adaptedModel,
    tools: [weatherAdapter.toAITool()]
)
```

### AIAgentAdapter

Wraps a legacy `Agent` to provide 2.0 interfaces:

```swift
// Existing 1.x agent
let legacyAgent = Agent(llm: openai, tools: [WeatherTool.self])

// Wrap with adapter
let adapter = AIAgentAdapter(legacyAgent: legacyAgent)

// Use 2.0 streaming interface
for try await event in adapter.streamExecute(messages: [.user("What's the weather?")]) {
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

---

## Migrating LLM Providers

### Before (1.x)

```swift
class MyService {
    let llm: LLM

    init() {
        self.llm = OpenAIProvider(apiKey: "sk-...")
    }

    func chat(message: String) async throws -> String {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [Message.user(content: .text(message))]
        )
        let response = try await llm.sendChatCompletion(request: request)
        return response.choices.first?.message.content ?? ""
    }
}
```

### After (2.0) - Using Adapter

```swift
class MyService {
    let model: AILanguageModel

    init() {
        let openai = OpenAIProvider(apiKey: "sk-...")
        self.model = AILanguageModelAdapter.fromOpenAI(openai, model: "gpt-4")
    }

    func chat(message: String) async throws -> String {
        let request = AITextRequest(messages: [.user(message)])
        let result = try await model.generateText(request: request)
        return result.text
    }
}
```

### After (2.0) - Using Native Provider

```swift
class MyService {
    let client: OpenRouterClient

    init() {
        self.client = OpenRouterClient(apiKey: "sk-...")
    }

    func chat(message: String) async throws -> String {
        let request = ProviderRequest(
            modelId: "openai/gpt-4",
            messages: [.user(message)]
        )
        let response = try await client.execute(request: request)
        return response.content
    }
}
```

---

## Migrating Agents

### Before (1.x)

```swift
class ChatManager {
    let agent: Agent

    init() {
        let llm = OpenAIProvider(apiKey: "sk-...")
        agent = Agent(
            llm: llm,
            tools: [WeatherTool.self, SearchTool.self],
            instructions: "You are a helpful assistant"
        )

        // State observation via closure
        agent.onStateChange = { [weak self] state in
            self?.handleStateChange(state)
        }
    }

    func send(_ message: String) async throws -> ChatMessage {
        return try await agent.send(message)
    }

    func stream(_ message: ChatMessage) -> AsyncStream<ChatMessage> {
        return agent.sendStream(message)
    }
}
```

### After (2.0) - Using Native Agent

```swift
class ChatManager {
    let agent: AIAgentActor
    @Observable var state = ObservableAgentState()

    init() {
        let client = OpenRouterClient(apiKey: "sk-...")
        agent = AIAgentActor(
            model: client,
            tools: [weatherTool, searchTool],
            systemPrompt: "You are a helpful assistant"
        )
    }

    func send(_ message: String) async throws -> AIAgentResult {
        state.isProcessing = true
        defer { state.isProcessing = false }

        return try await agent.execute(messages: [.user(message)])
    }

    func stream(_ message: String) -> AsyncThrowingStream<AIAgentEvent, Error> {
        return agent.streamExecute(messages: [.user(message)])
    }
}
```

### After (2.0) - Using Adapter for Gradual Migration

```swift
class ChatManager {
    let legacyAgent: Agent
    let adapter: AIAgentAdapter

    init() {
        let llm = OpenAIProvider(apiKey: "sk-...")
        legacyAgent = Agent(llm: llm, tools: [WeatherTool.self])
        adapter = AIAgentAdapter(legacyAgent: legacyAgent)
    }

    // Use new streaming interface with legacy agent
    func stream(_ message: String) -> AsyncThrowingStream<AIAgentEvent, Error> {
        return adapter.streamExecute(messages: [.user(message)])
    }
}
```

---

## Migrating Tools

### Before (1.x)

```swift
class WeatherTool: Tool {
    let name = "get_weather"
    let description = "Get current weather for a location"
    let returnToolResponse = false

    @Parameter(description: "City name")
    var location: String = ""

    @Parameter(description: "Temperature unit", validation: ["enum": ["celsius", "fahrenheit"]])
    var unit: String = "fahrenheit"

    required init() {}

    func execute() async throws -> (String, ToolMetadata?) {
        // Fetch weather...
        return ("Weather in \(location): 72\(unit == "celsius" ? "C" : "F"), sunny", nil)
    }
}
```

### After (2.0) - Using Adapter

```swift
// Keep existing tool, wrap with adapter
let adapter = try ToolAdapter(toolType: WeatherTool.self)
let aiTool = adapter.toAITool()

// Use with agent
let agent = AIAgentActor(model: model, tools: [aiTool])
```

### After (2.0) - Using Native AITool

```swift
struct WeatherTool: AITool {
    static let name = "get_weather"
    static let description = "Get current weather for a location"

    struct Parameters: Codable, Sendable {
        let location: String
        let unit: TemperatureUnit

        enum TemperatureUnit: String, Codable {
            case celsius, fahrenheit
        }
    }

    static func execute(parameters: Parameters) async throws -> AIToolResult {
        // Fetch weather...
        let temp = parameters.unit == .celsius ? "22C" : "72F"
        return AIToolResult(
            content: "Weather in \(parameters.location): \(temp), sunny"
        )
    }
}
```

---

## Migrating Message Types

### Before (1.x)

```swift
// Creating messages
let userMsg = Message.user(content: .text("Hello"))
let systemMsg = Message.system(content: .text("You are helpful"))
let assistantMsg = Message.assistant(content: .text("Hi there!"), toolCalls: nil)
let toolMsg = Message.tool(content: "72F", name: "weather", toolCallId: "call_123")

// Multimodal
let imageMsg = Message.user(content: .parts([
    .text("What's in this image?"),
    .imageURL(.url(imageURL), detail: .high)
]))
```

### After (2.0)

```swift
// Creating messages
let userMsg = AIMessage.user("Hello")
let systemMsg = AIMessage.system("You are helpful")
let assistantMsg = AIMessage.assistant("Hi there!")
let toolMsg = AIMessage.tool(content: "72F", toolCallId: "call_123", name: "weather")

// Multimodal
let imageMsg = AIMessage.user(content: .parts([
    .text("What's in this image?"),
    .image(imageData, mimeType: "image/jpeg")
]))

// Or use URL
let imageMsg = AIMessage.user(content: .parts([
    .text("What's in this image?"),
    .imageURL("https://example.com/image.jpg")
]))
```

---

## Migrating Streaming Code

### Before (1.x)

```swift
// Streaming with callback-style
let userMessage = ChatMessage(message: .user(content: .text("Hello")))

for try await message in agent.sendStream(userMessage) {
    if message.isPending {
        // Partial update
        updateUI(message.displayContent)
    } else {
        // Final message
        showFinal(message)
    }
}
```

### After (2.0)

```swift
// Streaming with typed events
for try await event in agent.streamExecute(messages: [.user("Hello")]) {
    switch event {
    case .textDelta(let text):
        appendToUI(text)

    case .toolCallStart(let id, let name):
        showToolIndicator(name)

    case .toolCallDelta(let id, let argsDelta):
        // Optional: show streaming arguments
        break

    case .toolCall(let id, let name, let args):
        showToolResult(name)

    case .toolResult(let id, let result):
        updateToolResult(result)

    case .finish(let reason, let usage):
        hideLoadingIndicator()
        showUsage(usage)

    case .error(let error):
        showError(error)

    default:
        break
    }
}
```

---

## Common Pitfalls

### 1. Not Awaiting Stream Events

```swift
// WRONG - Stream never consumed
let stream = agent.streamExecute(messages: messages)
// Stream is discarded!

// CORRECT - Consume the stream
for try await event in agent.streamExecute(messages: messages) {
    // Process events
}
```

### 2. Mixing Legacy and Modern Types

```swift
// WRONG - Incompatible types
let legacyMessage = Message.user(content: .text("Hello"))
let result = try await aiAgent.execute(messages: [legacyMessage]) // Type error!

// CORRECT - Use AIMessage
let message = AIMessage.user("Hello")
let result = try await aiAgent.execute(messages: [message])
```

### 3. Forgetting @unchecked Sendable for Adapters

```swift
// WRONG - Compiler error in concurrent context
class MyAdapter: AILanguageModel {
    var mutableState: Int = 0  // Not Sendable!
}

// CORRECT - Mark as @unchecked Sendable with proper synchronization
final class MyAdapter: AILanguageModel, @unchecked Sendable {
    private let lock = NSLock()
    private var _state: Int = 0

    var state: Int {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }
}
```

### 4. Not Handling Actor Isolation

```swift
// WRONG - Blocking call in actor context
actor MyActor {
    let agent = AIAgentActor(...)

    func process() {
        agent.execute(...)  // Missing await!
    }
}

// CORRECT - Await actor methods
actor MyActor {
    let agent = AIAgentActor(...)

    func process() async throws {
        let result = try await agent.execute(messages: [.user("Hi")])
    }
}
```

### 5. Ignoring Provider Access Validation

```swift
// WRONG - Sensitive data without allowlist
let request = AITextRequest(
    messages: [.user("My SSN is 123-45-6789")],
    sensitivity: .phi  // PHI data!
)
let result = try await model.generateText(request: request)
// Throws AIProviderAccessError.sensitiveDataRequiresAllowlist

// CORRECT - Specify allowed providers for sensitive data
let request = AITextRequest(
    messages: [.user("My SSN is 123-45-6789")],
    sensitivity: .phi,
    allowedProviders: ["hipaa-compliant-provider"]
)
```

---

## Incremental Migration Strategy

### Phase 1: Wrap Legacy Code

1. Keep all existing code working
2. Add adapters around legacy components
3. Test thoroughly

```swift
// Wrap existing providers
let adaptedModel = AILanguageModelAdapter.fromOpenAI(existingProvider)

// Wrap existing tools
let adaptedTools = existingToolTypes.map { try! ToolAdapter(toolType: $0).toAITool() }

// Create 2.0 agent with adapted components
let agent = AIAgentActor(model: adaptedModel, tools: adaptedTools)
```

### Phase 2: Migrate New Code

1. Write all new code using 2.0 patterns
2. Use `AIAgentActor` for new agents
3. Use `AITool` protocol for new tools

### Phase 3: Replace Legacy Components

1. Migrate tools from `Tool` to `AITool`
2. Switch from `LLM` to `AILanguageModel`
3. Update message handling to `AIMessage`

### Phase 4: Remove Adapters

1. Once all code is migrated, remove adapter usage
2. Delete adapter imports
3. Simplify dependency graph

---

## Summary

| Migration Task | Adapter | Native Alternative |
|---------------|---------|-------------------|
| Wrap `LLM` provider | `AILanguageModelAdapter` | Implement `AILanguageModel` |
| Wrap `Tool` | `ToolAdapter` | Implement `AITool` |
| Wrap `Agent` | `AIAgentAdapter` | Use `AIAgentActor` |
| Convert messages | Manual | Use `AIMessage` constructors |
| Handle streaming | Adapter auto-converts | Use `AsyncThrowingStream` events |

The adapter approach allows incremental migration without rewriting everything at once. Start by wrapping existing code, then gradually replace with native 2.0 implementations.
