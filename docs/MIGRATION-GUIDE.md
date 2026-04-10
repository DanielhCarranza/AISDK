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
| **Agent** | Class-based (now `LegacyAgent`) | Actor-based (`Agent`) |
| **Streaming** | Callback-based | `AsyncThrowingStream` |
| **State** | KVO patterns | `@Observable` |
| **Reliability** | None | Circuit breakers, failover, health monitoring |
| **Provider Protocol** | `LegacyLLM` protocol | `LLM` protocol |
| **Tool Protocol** | `Tool` with `@Parameter` | `Tool` protocol (same name, new design) |

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
protocol LLM {
    var provider: String { get }
    var modelId: String { get }
    var capabilities: LLMCapabilities { get }

    func generateText(request: AITextRequest) async throws -> AITextResult
    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
    func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T>
}
```

### Agent Changes

```swift
// 1.x Agent (class-based)
let agent = Agent(llm: provider, tools: [WeatherTool.self])
let response = try await agent.send("Hello")

// 2.0 Agent (actor-based)
let agent = Agent(model: languageModel, tools: [WeatherTool.self])
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

### LLMAdapter

Wraps a `LegacyLLM` to conform to `LLM`:

```swift
import AISDK

// Existing 1.x code
let openai = OpenAIProvider(apiKey: "sk-...")

// Wrap with adapter
let adaptedModel = LLMAdapter(
    llm: openai,
    provider: "openai",
    modelId: "gpt-4",
    capabilities: [.text, .tools, .streaming, .vision]
)

// Now use with 2.0 agent
let agent = Agent(model: adaptedModel)
let result = try await agent.execute(messages: [.user("Hello")])
```

**For new code, use v2 factory methods instead of adapters:**

```swift
// OpenAI (recommended)
let model = ProviderLanguageModelAdapter.openAIResponses(apiKey: "sk-...", modelId: "gpt-4o")

// Anthropic
let model = ProviderLanguageModelAdapter.anthropic(apiKey: "sk-ant-...", modelId: "claude-sonnet-4-20250514")

// Gemini
let model = ProviderLanguageModelAdapter.gemini(apiKey: "AIza...", modelId: "gemini-2.0-flash")
```

### Tool Migration

Tools use the `Tool` protocol with `@Parameter`. There is no adapter layer—migrate tools directly.

### AIAgentAdapter

Wraps a `LegacyAgent` to provide 2.0 interfaces:

```swift
// Existing 1.x agent
let legacyAgent = LegacyAgent(llm: openai, tools: [WeatherTool.self])

// Wrap with adapter (requires both the agent and an adapted model)
let adaptedModel = LLMAdapter(llm: openai, provider: "openai", modelId: "gpt-4")
let adapter = AIAgentAdapter(agent: legacyAgent, modelAdapter: adaptedModel)

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
    let model: any LLM

    init() {
        let openai = OpenAIProvider(apiKey: "sk-...")
        self.model = LLMAdapter(llm: openai, provider: "openai", modelId: "gpt-4")
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
    let agent: Agent
    let state = ObservableAgentState()

    init() {
        let model = ProviderLanguageModelAdapter.openAIResponses(apiKey: "sk-...", modelId: "gpt-4o")
        agent = Agent(
            model: model,
            tools: [WeatherTool.self, SearchTool.self],
            instructions: "You are a helpful assistant"
        )
    }

    func send(_ message: String) async throws -> AIAgentResult {
        return try await agent.execute(messages: [.user(message)])
    }

    func stream(_ message: String) -> AsyncThrowingStream<AIStreamEvent, Error> {
        return agent.streamExecute(messages: [.user(message)])
    }
}
```

### After (2.0) - Using Adapter for Gradual Migration

```swift
class ChatManager {
    let legacyAgent: LegacyAgent
    let adapter: AIAgentAdapter

    init() {
        let llm = OpenAIProvider(apiKey: "sk-...")
        legacyAgent = LegacyAgent(llm: llm, tools: [WeatherTool.self])
        let adaptedModel = LLMAdapter(llm: llm, provider: "openai", modelId: "gpt-4")
        adapter = AIAgentAdapter(agent: legacyAgent, modelAdapter: adaptedModel)
    }
}
```

---

## Migrating Tools

### Before (1.x)

```swift
// Legacy 1.x tool
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

### After (2.0) - Native Tool

```swift
struct WeatherTool: Tool {
    enum TemperatureUnit: String, Codable, CaseIterable {
        case celsius
        case fahrenheit
    }

    let name = "get_weather"
    let description = "Get current weather for a location"

    @Parameter(description: "City name")
    var location: String = ""

    @Parameter(description: "Temperature unit")
    var unit: TemperatureUnit = .fahrenheit

    required init() {}

    func execute() async throws -> ToolResult {
        let temp = unit == .celsius ? "22C" : "72F"
        return ToolResult(content: "Weather in \(location): \(temp), sunny")
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

    case .toolResult(let id, let result, _):
        updateToolResult(result)

    case .finish(let finishReason, let usage):
        hideLoadingIndicator()
        showUsage(usage)

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
class MyAdapter: LLM {
    var mutableState: Int = 0  // Not Sendable!
}

// CORRECT - Mark as @unchecked Sendable with proper synchronization
final class MyAdapter: LLM, @unchecked Sendable {
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
    let agent = Agent(...)

    func process() {
        agent.execute(...)  // Missing await!
    }
}

// CORRECT - Await actor methods
actor MyActor {
    let agent = Agent(...)

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
let adaptedModel = AILanguageModelAdapter(
    llm: existingProvider,
    provider: "openai",
    modelId: "gpt-4"
)

// Migrate tools to Tool (no adapter layer)
let tools: [Tool.Type] = [WeatherTool.self, CalculatorTool.self]

// Create 2.0 agent with adapted components
let agent = Agent(model: adaptedModel, tools: tools)
```

### Phase 2: Migrate New Code

1. Write all new code using 2.0 patterns
2. Use `Agent` for new agents
3. Use `Tool` protocol for new tools

### Phase 3: Replace Legacy Components

1. Migrate tools from `Tool` to `Tool`
2. Switch from `LegacyLLM` to `LLM` protocol
3. Update message handling to `AIMessage`

### Phase 4: Remove Adapters

1. Once all code is migrated, remove adapter usage
2. Delete adapter imports
3. Simplify dependency graph

---

## Summary

| Migration Task | Adapter | Native Alternative |
|---------------|---------|-------------------|
| Wrap `LegacyLLM` provider | `AILanguageModelAdapter` | Use `ProviderLanguageModelAdapter` factory methods |
| Wrap `LegacyAgent` | `AIAgentAdapter` | Use `Agent` actor |
| Convert messages | Manual | Use `AIMessage` constructors |
| Handle streaming | Adapter auto-converts | Use `AsyncThrowingStream` events |

The adapter approach allows incremental migration without rewriting everything at once. Start by wrapping providers/agents, and migrate tools directly to `Tool`.
