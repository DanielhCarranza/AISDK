# AISDK v2 Reference

Single-import Swift SDK for multi-provider LLM integration with agents, tools, streaming, generative UI, and HIPAA-grade data sensitivity controls.

```swift
import AISDK
```

**Platforms**: iOS 17+, macOS 14+, watchOS 10+, tvOS 17+

**5 Core Protocols**: `LLM`, `Tool`, `SessionStore`, `ProviderClient`, `JSONSchemaModel`

---

## Table of Contents

1. [Provider Layer](#1-provider-layer)
2. [Agent System](#2-agent-system)
3. [Tool Calling](#3-tool-calling)
4. [Streaming](#4-streaming)
5. [Reasoning & Thinking](#5-reasoning--thinking)
6. [Generative UI](#6-generative-ui)
7. [Structured Output](#7-structured-output)
8. [Sessions & Persistence](#8-sessions--persistence)
9. [Reliability](#9-reliability)
10. [MCP Integration](#10-mcp-integration)
11. [Skills System](#11-skills-system)
12. [Computer Use](#12-computer-use)
13. [Error Handling](#13-error-handling)
14. [Provider Capability Matrix](#14-provider-capability-matrix)
15. [Configuration Reference](#15-configuration-reference)
16. [SwiftUI Integration](#16-swiftui-integration)

---

## 1. Provider Layer

The `LLM` protocol is the unified interface every provider implements. Agents, streaming, and structured output all flow through it.

### Key Types

| Type | File |
|------|------|
| `LLM` (protocol) | `Sources/AISDK/Core/Protocols/LLM.swift` |
| `AILanguageModelAdapter` | `Sources/AISDK/Core/Adapters/Legacy/AILanguageModelAdapter.swift` |
| `ProviderLanguageModelAdapter` | `Sources/AISDK/Core/Adapters/Provider/ProviderLanguageModelAdapter.swift` |
| `OpenAIProvider` | `Sources/AISDK/LLMs/OpenAI/OpenAIProvider.swift` |
| `AnthropicProvider` | `Sources/AISDK/LLMs/Anthropic/AnthropicProvider.swift` |
| `GeminiProvider` | `Sources/AISDK/LLMs/Gemini/GeminiProvider.swift` |
| `OpenRouterClient` | `Sources/AISDK/Core/Providers/OpenRouterClient.swift` |
| `LiteLLMClient` | `Sources/AISDK/Core/Providers/LiteLLMClient.swift` |
| `LLMCapabilities` | `Sources/AISDK/LLMs/LLMModelProtocol.swift` |

### LLM Protocol

```swift
public protocol LLM: Sendable {
    var provider: String { get }
    var modelId: String { get }
    var capabilities: LLMCapabilities { get }

    func generateText(request: AITextRequest) async throws -> AITextResult
    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
    func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T>
    func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error>
}
```

### Usage: Direct Provider (Legacy API)

Legacy providers (`OpenAIProvider`, `AnthropicProvider`, `GeminiProvider`) implement `LegacyLLM` and must be wrapped in an adapter to use with `Agent` and the v2 `LLM` protocol.

```swift
// OpenAI via legacy provider + adapter
let openai = AILanguageModelAdapter(
    llm: OpenAIProvider(apiKey: "sk-..."),
    provider: "openai",
    modelId: "gpt-4o",
    capabilities: [.text, .tools, .streaming, .structuredOutputs, .vision]
)

// Anthropic via legacy provider + adapter
let anthropic = AILanguageModelAdapter(
    llm: AnthropicProvider(apiKey: "sk-ant-..."),
    provider: "anthropic",
    modelId: "claude-3-5-sonnet-20241022",
    capabilities: [.text, .tools, .streaming, .reasoning, .computerUse]
)

// Gemini via legacy provider + adapter
let gemini = AILanguageModelAdapter(
    llm: GeminiProvider(apiKey: "AIza..."),
    provider: "google",
    modelId: "gemini-2.5-flash",
    capabilities: [.text, .tools, .streaming, .vision, .audio, .video]
)
```

### Usage: ProviderClient (v2 API)

`ProviderClient` actors (`OpenRouterClient`, `LiteLLMClient`) use `ProviderLanguageModelAdapter`:

```swift
// OpenRouter — 200+ models via single key
let openRouter = OpenRouterClient(apiKey: "sk-or-...", appName: "MyApp")
let model = ProviderLanguageModelAdapter(
    client: openRouter,
    modelId: "anthropic/claude-3.5-sonnet",
    capabilities: [.text, .tools, .streaming]
)

// LiteLLM — self-hosted proxy (default: http://localhost:4000)
let litellm = LiteLLMClient(baseURL: URL(string: "http://localhost:4000")!)
let localModel = ProviderLanguageModelAdapter(
    client: litellm,
    modelId: "gpt-4o",
    capabilities: [.text, .tools, .streaming]
)
```

### Customize

- Swap any `LLM` into `Agent` — the agent doesn't care which provider backs it.
- Use `LLMCapabilities` option set to declare what features a model supports: `.text`, `.vision`, `.tools`, `.streaming`, `.reasoning`, `.computerUse`, `.structuredOutputs`, `.webSearch`, `.caching`, and 20+ more.
- `OpenAIProvider` supports custom `baseUrl` for any OpenAI-compatible endpoint.

### Gotchas

- Legacy providers (`OpenAIProvider`, `AnthropicProvider`, `GeminiProvider`) are **not** `LLM`-conformant — always wrap with `AILanguageModelAdapter`.
- `AnthropicProvider` enforces `n=1` and caps temperature at `1.0`. Logprobs, penalties, and seed are silently dropped.
- `GeminiProvider` uses its own native API format (not OpenAI-compatible). It has built-in retry with exponential backoff (3 retries, 1s base delay).
- `OpenRouterClient` and `LiteLLMClient` are actors — health status and model availability are cached for 5 minutes.

---

## 2. Agent System

The `Agent` actor runs an agentic loop: send messages, receive response, execute tool calls, feed results back, repeat until a stop condition is met.

### Key Types

| Type | File |
|------|------|
| `Agent` (actor) | `Sources/AISDK/Agents/Agent.swift` |
| `ObservableAgentState` | `Sources/AISDK/Agents/Agent.swift` |
| `AIAgentResult` | `Sources/AISDK/Agents/Agent.swift` |
| `AIStepResult` | `Sources/AISDK/Core/Models/AIStepResult.swift` |
| `StopCondition` | `Sources/AISDK/Agents/Agent.swift` |

### Usage: Basic Agent

```swift
let agent = Agent(
    model: model,                         // any LLM
    tools: [WebSearchTool.self],          // Tool types
    instructions: "You are a helpful assistant.",
    stopCondition: .stepCount(20),        // max 20 LLM round-trips
    maxToolRounds: 10                     // max 10 tool executions per step
)

// Non-streaming
let result = try await agent.execute(messages: [.user("Search for Swift concurrency best practices")])
print(result.text)
print(result.steps.count)  // how many LLM round-trips occurred
print(result.usage)        // aggregate token usage

// Streaming
let stream = agent.streamExecute(messages: [.user("Explain quantum computing")])
for try await event in stream {
    switch event {
    case .textDelta(let delta): print(delta, terminator: "")
    case .toolCallStart(_, let name): print("\n[Calling \(name)...]")
    case .stepFinish(let idx, _): print("\n[Step \(idx) complete]")
    case .finish(_, let usage): print("\nTokens: \(usage.totalTokens)")
    default: break
    }
}
```

### Agent Init (Full Signature)

```swift
public init(
    model: any LLM,
    tools: [Tool.Type] = [],
    builtInTools: [BuiltInTool] = [],
    mcpServers: [MCPServerConfiguration] = [],
    skillConfiguration: SkillConfiguration = .default,
    instructions: String? = nil,
    requestOptions: RequestOptions = RequestOptions(),
    stopCondition: StopCondition = .stepCount(20),
    timeout: TimeoutPolicy = .default,
    maxToolRounds: Int = 10,
    progressiveRendering: ProgressiveRenderingMode = .disabled,
    contextPolicy: ContextPolicy? = nil,
    name: String? = nil,
    agentId: String? = nil
)
```

### Stop Conditions

```swift
public enum StopCondition: Sendable {
    case stepCount(Int)                                    // max N LLM calls
    case noToolCalls                                       // stop when model stops calling tools
    case tokenBudget(maxTokens: Int)                       // stop when cumulative tokens exceed budget
    case custom(@Sendable (AIStepResult) -> Bool)          // your logic
}
```

### ObservableAgentState (for SwiftUI)

```swift
@Observable
public final class ObservableAgentState: @unchecked Sendable {
    @MainActor public private(set) var state: LegacyAgentState   // .idle | .thinking | .executingTool(name) | .responding | .error
    @MainActor public private(set) var currentStep: Int
    @MainActor public private(set) var error: AISDKErrorV2?
    @MainActor public private(set) var isProcessing: Bool
    public var stateStream: AsyncStream<LegacyAgentState> { get }
}
```

Access via `agent.observableState` — bind directly in SwiftUI views.

### Customize

- `requestOptions` lets you set `maxTokens`, `temperature`, `topP`, `reasoning`, `caching`, and `metadata` for every LLM call the agent makes.
- `contextPolicy` enables automatic context compaction when conversations grow long (see [Sessions](#8-sessions--persistence)).
- `progressiveRendering: .enabled` activates generative UI streaming.
- Inject `mcpServers` for external tool discovery, or `builtInTools` for provider-native tools (web search, code execution).

### Gotchas

- `Agent` is an **actor** — call `execute`/`streamExecute` with `await`. Access `messages` and `steps` from the actor's isolation context.
- `streamExecute` is `nonisolated` and returns immediately — consume the stream to drive execution.
- `maxToolRounds` caps tool calls **per step**, while `stopCondition: .stepCount(N)` caps total LLM round-trips.
- The agent automatically handles tool call → execution → result injection. You only intervene via `mcpApprovalHandler` or `computerUseHandler`.

---

## 3. Tool Calling

Tools are Swift structs conforming to `Tool`. Parameters use the `@Parameter` property wrapper for automatic JSON schema generation.

### Key Types

| Type | File |
|------|------|
| `Tool` (protocol) | `Sources/AISDK/Tools/Tool.swift` |
| `Parameter` (property wrapper) | `Sources/AISDK/Tools/Parameter.swift` |
| `ToolResult` | `Sources/AISDK/Tools/Tool.swift` |
| `ToolRegistry` | `Sources/AISDK/Tools/Tool.swift` |
| `ToolSchema` | `Sources/AISDK/LLMs/OpenAI/APIModels/ChatCompletion/ChatCompletionRequest.swift` |
| `BuiltInTool` | `Sources/AISDK/Core/Models/BuiltInTool.swift` |

### Usage: Define a Tool

```swift
struct WeatherTool: Tool {
    var name: String { "get_weather" }
    var description: String { "Get current weather for a city" }
    var returnToolResponse: Bool { false }

    @Parameter(description: "City name", required: true)
    var city: String = ""

    @Parameter(description: "Temperature unit", validation: .init(enum: ["celsius", "fahrenheit"]))
    var unit: String = "celsius"

    func execute() async throws -> ToolResult {
        let temp = try await WeatherAPI.fetch(city: city, unit: unit)
        return ToolResult(content: "Temperature in \(city): \(temp)\(unit == "celsius" ? "C" : "F")")
    }
}
```

### Usage: Register and Use

```swift
// With Agent (preferred)
let agent = Agent(model: model, tools: [WeatherTool.self])

// Manual registration (for direct LLM calls)
ToolRegistry.shared.register(WeatherTool.self)
let schemas = ToolRegistry.shared.schemas  // [ToolSchema] for LLM request
let result = try await ToolRegistry.shared.execute(name: "get_weather", arguments: "{\"city\":\"Tokyo\"}")
```

### Execution Flow

1. Agent sends `AITextRequest` with `tools: [ToolSchema]` to the LLM
2. LLM returns `.toolCall(id:, name:, arguments:)` events
3. Agent deserializes arguments, creates tool instance, calls `setParameters(from:)`
4. Agent calls `tool.execute()` → `ToolResult`
5. Agent injects `AIMessage.tool(result.content, toolCallId: id)` back into messages
6. Loop continues until stop condition

### Built-In Tools (Provider-Native)

```swift
let agent = Agent(
    model: model,
    builtInTools: [
        .webSearchDefault,                                    // provider-native web search
        .codeExecutionDefault,                                // sandboxed code execution
        .computerUseDefault,                                  // screen interaction (Anthropic/OpenAI)
        .fileSearch(FileSearchConfig(vectorStoreIds: ["vs_..."])),
        .imageGeneration(ImageGenerationConfig(quality: "hd", size: "1024x1024")),
    ]
)
```

### Customize

- `returnToolResponse: true` makes the agent return the tool result directly to the user instead of feeding it back to the LLM.
- Implement `RenderableTool` protocol to attach SwiftUI views to tool results.
- `ToolResult` can include `metadata` (any `ToolMetadata`-conforming type) and `artifacts` (files, images, JSON blobs).
- `@Parameter` supports `validation` for enum constraints, ranges, and patterns.

### Gotchas

- Tools must have a parameterless `init()`. All state comes through `@Parameter` properties.
- `ToolSchema` uses OpenAI's function calling format (`type: "function"`, `function: ToolFunction`).
- Tool names must be unique within an agent. MCP tools are namespaced as `serverLabel_toolName`.

---

## 4. Streaming

All streaming in AISDK v2 flows through `AIStreamEvent` — a 22-case enum covering text, reasoning, tools, objects, UI patches, and lifecycle.

### Key Types

| Type | File |
|------|------|
| `AIStreamEvent` | `Sources/AISDK/Core/Models/AIStreamEvent.swift` |
| `AIStreamMetadata` | `Sources/AISDK/Core/Models/AIStreamEvent.swift` |
| `AISource` | `Sources/AISDK/Core/Models/AIStreamEvent.swift` |
| `StreamBufferPolicy` | `Sources/AISDK/Core/Models/AITextRequest.swift` |

### All Stream Event Cases

```swift
public enum AIStreamEvent: Sendable {
    // Text
    case textDelta(String)                                           // incremental text chunk
    case textCompletion(String)                                      // full accumulated text

    // Reasoning (o1/o3/Claude extended thinking)
    case reasoningStart
    case reasoningDelta(String)
    case reasoningFinish(String)

    // Tool Calls
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCall(id: String, name: String, arguments: String)       // complete tool call
    case toolCallFinish(id: String, name: String, arguments: String)
    case toolResult(id: String, result: String, metadata: ToolMetadata?)

    // Structured Output
    case objectDelta(Data)                                           // partial JSON bytes

    // Sources & Files
    case source(AISource)                                            // web search citation
    case file(AIFileEvent)                                           // generated file

    // Usage & Lifecycle
    case usage(AIUsage)
    case start(metadata: AIStreamMetadata?)
    case stepStart(stepIndex: Int)
    case stepFinish(stepIndex: Int, result: AIStepResult)
    case heartbeat(timestamp: Date)
    case finish(finishReason: AIFinishReason, usage: AIUsage)

    // Generative UI
    case uiPatch(SpecPatchBatch)                                     // progressive UI update

    // Computer Use
    case computerUseAction(ComputerUseToolCall)

    // Errors
    case error(Error)
}
```

### Usage: Consume a Stream

```swift
let stream = model.streamText(request: AITextRequest(
    messages: [.user("Explain relativity")],
    bufferPolicy: .bounded(capacity: 500)
))

var fullText = ""
for try await event in stream {
    switch event {
    case .textDelta(let delta):
        fullText += delta
    case .usage(let usage):
        print("Tokens so far: \(usage.totalTokens)")
    case .finish(let reason, let finalUsage):
        print("Done: \(reason), total tokens: \(finalUsage.totalTokens)")
    default: break
    }
}
```

### Buffer Policies

```swift
public enum StreamBufferPolicy: Sendable, Equatable {
    case unbounded                        // no limit (memory risk for long streams)
    case dropOldest(capacity: Int)        // drop oldest events when full
    case dropNewest(capacity: Int)        // drop newest events when full
    static let bounded                    // .dropOldest(capacity: 1000)
}
```

### Gotchas

- Always handle `.error` — stream errors are delivered as events, not thrown from the `for try await` loop in some edge cases.
- `.textDelta` is incremental; `.textCompletion` is the full accumulated text. Don't concatenate both.
- `.finish` always arrives last (even after errors). Use it for cleanup.
- Agent streams emit `.stepStart`/`.stepFinish` around each LLM round-trip — useful for progress tracking.

---

## 5. Reasoning & Thinking

Extended thinking for models that support chain-of-thought reasoning (OpenAI o1/o3, Claude with extended thinking).

### Key Types

| Type | File |
|------|------|
| `AIReasoningConfig` | `Sources/AISDK/Core/Models/AIReasoningConfig.swift` |
| `AIReasoningEffort` | `Sources/AISDK/Core/Models/AIReasoningConfig.swift` |

### Usage

```swift
// Via Agent requestOptions
let agent = Agent(
    model: model,
    requestOptions: Agent.RequestOptions(
        reasoning: AIReasoningConfig(effort: .high, budgetTokens: 5000)
    )
)

// Via direct LLM request
let request = AITextRequest(
    messages: [.user("Prove the Pythagorean theorem")],
    reasoning: .effort(.high)
)
let stream = model.streamText(request: request)
for try await event in stream {
    switch event {
    case .reasoningStart: print("[Thinking...]")
    case .reasoningDelta(let thought): print(thought, terminator: "")
    case .reasoningFinish(let fullThought): print("\n[Thought complete: \(fullThought.count) chars]")
    case .textDelta(let text): print(text, terminator: "")
    default: break
    }
}
```

### Config

```swift
public struct AIReasoningConfig: Sendable, Equatable, Codable {
    public let effort: AIReasoningEffort?    // .low | .medium | .high
    public let budgetTokens: Int?            // max tokens for reasoning

    public static func effort(_ effort: AIReasoningEffort) -> AIReasoningConfig
}
```

### Gotchas

- Not all providers support reasoning. Check `capabilities.contains(.reasoning)` before sending.
- `budgetTokens` is a hint — Anthropic uses it for extended thinking budget, OpenAI uses it for reasoning effort.
- Reasoning tokens are tracked separately in `AIUsage.reasoningTokens`.

---

## 6. Generative UI

Stream JSON-described UI specs from the LLM, compile them progressively into a `UITree`, and render with SwiftUI.

### Key Types

| Type | File |
|------|------|
| `UISpec` | `Sources/AISDK/GenerativeUI/SpecStream/UISpec.swift` |
| `UITree` | `Sources/AISDK/GenerativeUI/Models/UITree.swift` |
| `UINode` | `Sources/AISDK/GenerativeUI/Models/UITree.swift` |
| `SpecStreamCompiler` | `Sources/AISDK/GenerativeUI/SpecStream/SpecStreamCompiler.swift` |
| `GenerativeUIView` | `Sources/AISDK/GenerativeUI/Views/GenerativeUIView.swift` |
| `GenerativeUISpecView` | `Sources/AISDK/GenerativeUI/Views/GenerativeUIView.swift` |
| `UIComponentRegistry` | `Sources/AISDK/GenerativeUI/Registry/UIComponentRegistry.swift` |
| `GenerativeUIViewModel` | `Sources/AISDK/GenerativeUI/ViewModels/GenerativeUIViewModel.swift` |

### Usage: Progressive Rendering

```swift
let agent = Agent(
    model: model,
    progressiveRendering: .enabled
)

let compiler = SpecStreamCompiler()
let viewModel = GenerativeUIViewModel.streaming()

// Subscribe to agent stream
let stream = agent.streamExecute(messages: [.user("Show me a dashboard")])
viewModel.startSubscription(toEvents: stream, compiler: compiler) { text in
    // Handle text deltas alongside UI patches
    print(text, terminator: "")
}

// In SwiftUI
struct ContentView: View {
    @State var viewModel: GenerativeUIViewModel

    var body: some View {
        GenerativeUISpecView(
            spec: viewModel.tree.map { UISpec(tree: $0) },
            isLoading: viewModel.isLoading,
            error: viewModel.error,
            registry: .secureDefault,
            onAction: { action in print("Action: \(action)") }
        )
    }
}
```

### UITree Structure

A `UITree` is a flat dictionary of keyed `UINode`s with a root key. Each node has a `type` (component name), `propsData` (JSON), and `childKeys`.

```swift
public struct UITree: Sendable, Equatable {
    public let rootKey: String
    public let nodes: [String: UINode]

    public static func parse(from data: Data, validatingWith catalog: UICatalog? = nil) throws -> UITree
    public func children(of node: UINode) -> [UINode]
    public func traverse(_ visitor: (UINode, Int) -> Void)
}

public struct UINode: Sendable, Equatable {
    public let key: String
    public let type: String           // e.g., "VStack", "Text", "Button"
    public let propsData: Data        // JSON-encoded component props
    public let childKeys: [String]
}
```

### Component Registries

```swift
UIComponentRegistry.default          // all built-in components
UIComponentRegistry.secureDefault    // default + action allowlist enforcement
UIComponentRegistry.extended         // default + additional community components
UIComponentRegistry.secureExtended   // extended + action allowlist

// Register custom component
var registry = UIComponentRegistry.secureDefault
registry.register("CustomCard") { node, tree, decoder, actionHandler, childBuilder in
    let props = try decoder.decode(CardProps.self, from: node.propsData)
    return AnyView(CardView(title: props.title))
}
registry.allowAction("card_tap")     // whitelist actions
```

### Gotchas

- Always use `.secureDefault` or `.secureExtended` in production — they enforce action allowlists.
- `SpecStreamCompiler` is stateful — one instance per conversation stream.
- `.uiPatch` events arrive interleaved with `.textDelta` events. The compiler accumulates patches into a coherent tree.
- Parse failures from malformed LLM JSON are silently skipped (tracked via `compiler.skippedPatchCount`).

---

## 7. Structured Output

Generate typed Swift objects from LLM responses using JSON schema enforcement.

### Key Types

| Type | File |
|------|------|
| `AIObjectRequest<T>` | `Sources/AISDK/Core/Models/AIObjectRequest.swift` |
| `AIObjectResult<T>` | `Sources/AISDK/Core/Models/AIObjectResult.swift` |
| `JSONSchemaModel` (protocol) | `Sources/AISDK/Utilities/JSONSchemaRepresentable.swift` |
| `SchemaBuilder<T>` | `Sources/AISDK/Utilities/JSONSchemaRepresentable.swift` |
| `Field` (property wrapper) | `Sources/AISDK/Utilities/JSONSchemaRepresentable.swift` |

### Usage

```swift
// 1. Define your model
struct MovieReview: JSONSchemaModel, Codable, Sendable {
    @Field(description: "Movie title")
    var title: String = ""

    @Field(description: "Rating from 1-10", validation: ["minimum": .integer(1), "maximum": .integer(10)])
    var rating: Int = 0

    @Field(description: "Brief review text")
    var review: String = ""
}

// 2. Generate
let result = try await model.generateObject(request: AIObjectRequest<MovieReview>(
    messages: [.user("Review 'Inception'")],
    schema: SchemaBuilder(MovieReview()),
    schemaName: "movie_review",
    strict: true
))

print(result.object.title)   // "Inception"
print(result.object.rating)  // 9
print(result.object.review)  // "A masterpiece of..."
print(result.usage)           // token counts
```

### Streaming Structured Output

```swift
let stream = model.streamObject(request: AIObjectRequest<MovieReview>(
    messages: [.user("Review 'Inception'")],
    schema: SchemaBuilder(MovieReview())
))
for try await event in stream {
    switch event {
    case .objectDelta(let partialJSON):
        // Progressive JSON bytes — use ProgressiveJSONParser for partial decoding
        break
    case .finish(_, let usage):
        print("Done: \(usage.totalTokens) tokens")
    default: break
    }
}
```

### Customize

- `strict: true` (default) uses provider-native JSON schema enforcement. `strict: false` relies on prompt-based enforcement.
- `@Field` supports `validation` with `minimum`, `maximum`, `enum` values, `minLength`, `maxLength`, `pattern`.
- Use `ValidationValue.enumArray(MyEnum.self)` for automatic enum validation from `CaseIterable` types.

### Gotchas

- `JSONSchemaModel` requires a parameterless `init()` and `Codable` conformance.
- Not all providers support structured output equally. OpenAI has native JSON schema support; others may fall back to prompt-based enforcement.
- `AIObjectResult.wasTruncated` tells you if the response was cut off before completing the JSON.

---

## 8. Sessions & Persistence

Sessions track conversation history with checkpoints, compaction, and pluggable storage backends.

### Key Types

| Type | File |
|------|------|
| `AISession` | `Sources/AISDK/Sessions/Models/Session.swift` |
| `SessionStore` (protocol) | `Sources/AISDK/Sessions/Protocols/SessionStore.swift` |
| `SessionCompactionService` | `Sources/AISDK/Sessions/Services/SessionCompactionService.swift` |
| `ContextPolicy` | `Sources/AISDK/Sessions/Models/ContextPolicy.swift` |
| `SessionStatus` | `Sources/AISDK/Sessions/Models/Session.swift` |
| `ChatViewModel` | `Sources/AISDK/Sessions/ViewModels/ChatViewModel.swift` |

### Usage: Session Lifecycle

```swift
// Create
var session = AISession(userId: "user_123", title: "Chat about Swift")

// Add messages
session.messages.append(.user("Hello"))
session.messages.append(.assistant("Hi there!"))

// Checkpoints (for rewind)
session.createCheckpoint(type: .assistantComplete, label: "After greeting")

// Rewind to checkpoint
session.rewind(to: 0)

// Fork (create branch from current state)
let forked = session.fork()
```

### SessionStore Protocol

```swift
public protocol SessionStore: Sendable {
    // CRUD
    func create(_ session: AISession) async throws -> AISession
    func load(id: String) async throws -> AISession?
    func save(_ session: AISession) async throws
    func delete(id: String) async throws

    // Query
    func list(userId: String, status: SessionStatus?, limit: Int,
              cursor: String?, orderBy: SessionOrderBy) async throws -> SessionListResult

    // Incremental
    func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws
    func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws
    func updateStatus(_ status: SessionStatus, forSession sessionId: String) async throws

    // Real-time (optional)
    func observe(sessionId: String) -> AsyncThrowingStream<AISession, Error>?
}
```

Implement this protocol for your storage backend (CoreData, CloudKit, Firebase, etc.). The 5 core methods (`create`, `load`, `save`, `delete`, `list`) are required. The incremental update methods (`appendMessage`, `updateLastMessage`, `updateStatus`) and `observe` have default implementations that fall back to full `load` + `save`.

### Context Compaction

```swift
let compactor = SessionCompactionService(llm: model)

let policy = ContextPolicy(
    maxTokens: 128_000,
    compactionThreshold: 0.9,          // compact at 90% capacity
    compactionStrategy: .summarize,     // .truncate | .summarize | .slidingWindow
    preserveSystemPrompt: true,
    minMessagesToKeep: 4
)

if compactor.needsCompaction(session.messages, policy: policy) {
    let compacted = try await compactor.compact(session.messages, policy: policy)
    session.messages = compacted
}

// Or wire it into Agent automatically
let agent = Agent(model: model, contextPolicy: policy)
```

### Gotchas

- `AISession` is a **value type** (struct). Mutations create copies — always `save()` after changes.
- `SessionCompactionService` with `.summarize` strategy calls the LLM — it costs tokens.
- Checkpoints store message indices, not copies. Rewind truncates `messages` array.
- `SessionStatus`: `.active`, `.completed`, `.paused`, `.error`, `.archived`.

---

## 9. Reliability

Production-grade retry, circuit breaking, timeout, and failover across multiple providers.

### Key Types

| Type | File |
|------|------|
| `RetryPolicy` | `Sources/AISDK/Core/Reliability/RetryPolicy.swift` |
| `RetryExecutor` | `Sources/AISDK/Core/Reliability/RetryPolicy.swift` |
| `AdaptiveCircuitBreaker` | `Sources/AISDK/Core/Reliability/AdaptiveCircuitBreaker.swift` |
| `TimeoutPolicy` | `Sources/AISDK/Core/Reliability/TimeoutPolicy.swift` |
| `FailoverExecutor` | `Sources/AISDK/Core/Reliability/FailoverExecutor.swift` |
| `FailoverPolicy` | `Sources/AISDK/Core/Reliability/CapabilityAwareFailover.swift` |

### RetryPolicy

```swift
// Presets
RetryPolicy.default          // 3 retries, 1s base, 30s max, 0.2 jitter, exponential(2.0)
RetryPolicy.none             // no retries
RetryPolicy.aggressive       // 5 retries, 500ms base, 60s max
RetryPolicy.conservative     // 2 retries, 2s base, 10s max
RetryPolicy.immediate        // 3 retries, 10ms base, 100ms max, no jitter

// Custom
let policy = RetryPolicy(
    maxRetries: 3,
    baseDelay: .seconds(1),
    maxDelay: .seconds(30),
    jitterFactor: 0.2,
    exponentialBase: 2.0,
    respectRetryAfter: true,           // honor 429 Retry-After headers
    errorClassifier: { error in        // custom retryability check
        (error as? AISDKErrorV2)?.code.isRetryable ?? false
    }
)

// Execute with retry
let executor = RetryExecutor(policy: policy)
let result = try await executor.execute({
    try await model.generateText(request: request)
}, onRetry: { error, attempt, delay in
    print("Retry \(attempt) after \(delay): \(error)")
})
```

### AdaptiveCircuitBreaker

```swift
let breaker = AdaptiveCircuitBreaker(
    configuration: CircuitBreakerConfiguration(
        failureThreshold: 5,           // open after 5 consecutive failures
        recoveryTimeout: .seconds(30), // try again after 30s
        successThreshold: 2,           // close after 2 successes in half-open
        halfOpenMaxProbes: 3           // max concurrent probes in half-open
    )
)

let result = try await breaker.execute {
    try await model.generateText(request: request)
}

// Check state
let state = await breaker.currentState  // .closed | .open(until:) | .halfOpen
let metrics = await breaker.metrics     // totalSuccesses, totalFailures, etc.
```

### FailoverExecutor

```swift
let failover = FailoverExecutorBuilder()
    .with(providers: [openRouterClient, litellmClient])
    .with(configuration: FailoverExecutorConfiguration(
        retryPolicy: .default,
        timeoutPolicy: .default,
        failoverPolicy: FailoverPolicy(
            maxCostMultiplier: 5.0,
            requireCapabilityMatch: true
        )
    ))
    .build()

let result = try await failover.executeRequest(request: request, modelId: "gpt-4o")
print("Served by: \(result.provider), attempts: \(result.attempts)")
```

### TimeoutPolicy

```swift
TimeoutPolicy.default       // connection: 10s, request: 60s, stream: 30s, operation: 120s
TimeoutPolicy.aggressive    // shorter timeouts
TimeoutPolicy.lenient       // longer timeouts
TimeoutPolicy.streaming     // optimized for long-running streams
```

### Gotchas

- Circuit breakers track failures **per provider** via `CircuitBreakerRegistry`.
- `FailoverPolicy.requireCapabilityMatch` ensures the fallback provider supports the same features (tools, streaming, etc.).
- `AIErrorCode.isRetryable` returns `true` for rate limits, provider unavailable, stream interruptions, and timeouts. Client errors (auth, validation) are not retryable.
- `RetryPolicy.respectRetryAfter: true` reads `suggestedRetryAfter` from `RetryableError`-conforming errors.

---

## 10. MCP Integration

Model Context Protocol client for discovering and calling tools on external MCP servers.

### Key Types

| Type | File |
|------|------|
| `MCPClient` (actor) | `Sources/AISDK/MCP/MCPClient.swift` |
| `MCPServerConfiguration` | `Sources/AISDK/MCP/MCPServerConfiguration.swift` |
| `MCPToolSchema` | `Sources/AISDK/MCP/MCPServerConfiguration.swift` |
| `MCPApprovalContext` | `Sources/AISDK/MCP/MCPServerConfiguration.swift` |
| `MCPCallResult` | `Sources/AISDK/MCP/MCPServerConfiguration.swift` |

### Usage: With Agent

```swift
let agent = Agent(
    model: model,
    mcpServers: [
        MCPServerConfiguration(
            serverLabel: "filesystem",
            serverUrl: "http://localhost:3000/mcp",
            transport: .http,
            requireApproval: .dangerous,     // .never | .always | .dangerous
            allowedTools: ["read_file", "list_directory"],
            blockedTools: ["delete_file"]
        )
    ]
)

// Approval handler (required when requireApproval != .never)
agent.mcpApprovalHandler = { context in
    print("MCP tool '\(context.toolName)' on '\(context.serverLabel)' with args: \(context.argumentsJSON)")
    return true  // approve
}
```

### Usage: Direct Client

```swift
let client = MCPClient()
let config = MCPServerConfiguration(
    serverLabel: "weather",
    serverUrl: "http://localhost:3001/mcp"
)

// Discover tools
let tools = try await client.listTools(server: config)
for tool in tools {
    print("\(tool.namespacedName): \(tool.description ?? "")")
}

// Call a tool
let result = try await client.callTool(
    server: config,
    name: "get_forecast",
    arguments: ["city": .string("Tokyo"), "days": .int(5)]
)
print(result.textContent)
```

### Gotchas

- MCP tools are namespaced as `serverLabel_toolName` to avoid collisions with local tools.
- `MCPClient` caches server initialization. Use `clearCache(for:)` if a server restarts.
- Transports: `.http` (HTTP+SSE), `.stdio` (subprocess). Most servers use `.http`.
- `MCPCallResult.content` can contain `.text`, `.image`, or `.resource` variants.

---

## 11. Skills System

Skills are discoverable, file-based capability packages that can be loaded into agents at runtime.

### Key Types

| Type | File |
|------|------|
| `SkillRegistry` (actor) | `Sources/AISDK/Skills/SkillRegistry.swift` |
| `SkillConfiguration` | `Sources/AISDK/Skills/SkillConfiguration.swift` |
| `SkillDescriptor` | `Sources/AISDK/Skills/SkillDescriptor.swift` |
| `LoadedSkill` | `Sources/AISDK/Skills/SkillDescriptor.swift` |

### Usage

```swift
// Discover available skills
let skills = try await agent.getAvailableSkills()  // ["data-analysis", "code-review", ...]

// Activate a skill (loads its instructions and tools)
let loaded = try await agent.activateSkill(named: "data-analysis")
print(loaded.body)           // skill instructions markdown
print(loaded.scriptPaths)   // associated scripts
print(loaded.referencePaths) // reference documents

// Check activation
let isActive = await agent.isSkillActivated(named: "data-analysis")

// Deactivate
await agent.deactivateSkill(named: "data-analysis")
```

### Skill Structure on Disk

```
skills/
  data-analysis/
    skill.md          # frontmatter (name, description, license) + instructions body
    scripts/           # optional scripts
    references/        # optional reference documents
    assets/            # optional binary assets
```

### Configuration

```swift
let config = SkillConfiguration(
    searchRoots: [URL(fileURLWithPath: "/path/to/skills")],
    enableValidation: true,
    maxSkillSizeBytes: 32 * 1024,    // 32 KB max
    maxSkillLines: 500,
    enabled: true,
    strictFrontmatter: false
)

let agent = Agent(model: model, skillConfiguration: config)
```

### Gotchas

- Skills are scoped: `.project` (in the project directory) or `.user` (user-level).
- `SkillRegistry` caches discovered skills. Call `refresh()` to re-scan.
- Maximum skill size is 32 KB / 500 lines by default to keep agent context manageable.

---

## 12. Computer Use

Screen interaction for browser/desktop automation. The agent sends actions; your handler executes them and returns screenshots.

### Key Types

| Type | File |
|------|------|
| `ComputerUseAction` | `Sources/AISDK/Core/Models/ComputerUse/ComputerUseAction.swift` |
| `ComputerUseToolCall` | `Sources/AISDK/Core/Models/ComputerUse/ComputerUseAction.swift` |
| `ComputerUseResult` | `Sources/AISDK/Core/Models/ComputerUse/ComputerUseResult.swift` |

### Usage

```swift
let agent = Agent(
    model: model,
    builtInTools: [.computerUseDefault]
)

agent.computerUseHandler = { toolCall in
    switch toolCall.action {
    case .screenshot:
        let base64 = try await captureScreen()
        return .screenshot(base64, mediaType: .png)

    case .click(let x, let y, let button):
        try await performClick(x: x, y: y, button: button)
        let base64 = try await captureScreen()
        return .screenshot(base64)

    case .type(let text):
        try await typeText(text)
        let base64 = try await captureScreen()
        return .screenshot(base64)

    case .keypress(let keys):
        try await pressKeys(keys)
        return .screenshot(try await captureScreen())

    case .scroll(let x, let y, _, _, let direction, let amount):
        try await scroll(x: x, y: y, direction: direction, amount: amount)
        return .screenshot(try await captureScreen())

    default:
        return .error("Unsupported action")
    }
}
```

### Actions

```swift
public enum ComputerUseAction: Sendable, Equatable {
    case screenshot
    case click(x: Int, y: Int, button: ClickButton = .left)
    case doubleClick(x: Int, y: Int)
    case tripleClick(x: Int, y: Int)
    case type(text: String)
    case keypress(keys: [String])
    case scroll(x: Int, y: Int, scrollX: Int?, scrollY: Int?, direction: ScrollDirection?, amount: Int?)
    case move(x: Int, y: Int)
    case drag(path: [Coordinate])
    case wait(durationMs: Int?)
    case cursorPosition
    case zoom(region: [Int])
}
```

### Gotchas

- Computer use works with both Anthropic and OpenAI formats — the SDK normalizes to `ComputerUseAction`.
- Always return a screenshot after every action — the model needs visual feedback to plan the next step.
- `ComputerUseToolCall.safetyChecks` contains provider safety warnings. Log and review these.
- Requires `.computerUse` capability on the model.

---

## 13. Error Handling

Structured error taxonomy with machine-readable codes, PHI-safe redaction, and retryability classification.

### Key Types

| Type | File |
|------|------|
| `AISDKErrorV2` | `Sources/AISDK/Core/Errors/AIError.swift` |
| `AIErrorCode` | `Sources/AISDK/Core/Errors/AIError.swift` |
| `AIErrorContext` | `Sources/AISDK/Core/Errors/AIError.swift` |

### Error Code Taxonomy

| Category | Codes | Retryable? |
|----------|-------|-----------|
| **Request** | `invalidRequest`, `missingParameter`, `invalidModel`, `validationFailed` | No |
| **Provider** | `authenticationFailed`, `rateLimitExceeded`, `providerUnavailable`, `modelNotAvailable`, `quotaExceeded` | Rate limit & unavailable: Yes |
| **Content** | `contentFiltered`, `contextLengthExceeded`, `invalidResponse`, `parsingFailed` | No |
| **Stream** | `streamConnectionFailed`, `streamInterrupted`, `streamTimeout` | Yes |
| **Tool** | `toolExecutionFailed`, `toolNotFound`, `invalidToolArguments`, `toolTimeout` | Timeout: Yes |
| **Network** | `networkFailed`, `timeout` | Yes |
| **PHI/Security** | `providerNotAllowed`, `phiRequiresAllowlist`, `sensitiveDataExposure` | No |
| **System** | `internalError`, `cancelled`, `unknown` | No |

### Usage

```swift
do {
    let result = try await agent.execute(messages: [.user("Hello")])
} catch let error as AISDKErrorV2 {
    print("Code: \(error.code)")                    // .rateLimitExceeded
    print("Retryable: \(error.code.isRetryable)")   // true
    print("Security: \(error.code.isSecurityRelated)") // false
    print("Provider: \(error.context.provider)")     // "openai"
    print("Status: \(error.context.statusCode)")     // 429

    // PHI-safe logging
    let safe = error.redactedForLogging()
    logger.error("\(safe.toLogDictionary())")
}
```

### Factory Methods

```swift
// Common patterns
AISDKErrorV2.rateLimitExceeded(provider: "openai", retryAfter: 30)
AISDKErrorV2.contextLengthExceeded(tokenCount: 150_000, maxTokens: 128_000)
AISDKErrorV2.toolExecutionFailed(tool: "web_search", reason: "Network timeout")
AISDKErrorV2.providerNotAllowed(
    provider: "openrouter",
    allowedProviders: ["openai"],
    sensitivity: .phi
)

// Convert any Error
let sdkError = AISDKErrorV2.from(someError, context: AIErrorContext(provider: "openai"))
```

### PHI Redaction

```swift
let error = AISDKErrorV2.internalError("Patient John Doe SSN 123-45-6789")
let redacted = error.redactedForLogging()
// Message becomes generic, context.phiRedacted = true
```

### Gotchas

- `AISDKErrorV2` is **not** the same as `AIError` (legacy). V2 code uses `AISDKErrorV2` exclusively.
- `error.code.isRetryable` is the source of truth for retry decisions — `RetryPolicy` uses this internally.
- Always use `redactedForLogging()` before writing errors to external logging systems when `sensitivity == .phi`.
- Agent errors are surfaced via `ObservableAgentState.error` for SwiftUI binding.

---

## 14. Provider Capability Matrix

What each provider supports natively vs. what requires adapter wrapping or direct invocation.

| Feature | OpenAI | Anthropic | Gemini | OpenRouter | LiteLLM |
|---------|--------|-----------|--------|-----------|---------|
| Text Generation | Yes | Yes | Yes | Yes | Yes |
| Streaming | Yes (SSE) | Yes (SSE) | Yes (AsyncLineSequence) | Yes (SSE) | Yes (SSE) |
| Tool Calling | Yes | Yes | Yes | Yes | Yes |
| Structured Output | Native JSON Schema | Via prompt | Via prompt | Model-dependent | Model-dependent |
| Vision (Images) | Yes | Yes | Yes | Model-dependent | Model-dependent |
| Audio Input | Yes | No | Yes | No | No |
| Video Input | No | No | Yes | No | No |
| File Upload | No | No | Yes (resumable) | No | No |
| Reasoning/Thinking | Yes (o1/o3) | Yes (extended thinking) | Yes | Model-dependent | Model-dependent |
| Computer Use | Yes (Responses API) | Yes (native) | No | No | No |
| Web Search | Yes (built-in tool) | Yes (built-in tool) | Yes (grounding) | Model-dependent | No |
| Code Execution | Yes (built-in tool) | Yes (built-in tool) | Yes (native) | No | No |
| Image Generation | Yes (built-in tool) | No | Yes (Imagen) | No | No |
| Caching | No | Yes (prompt caching) | Yes (cached content) | No | No |
| Responses API | Yes | No | No | No | No |
| Health Monitoring | No | No | No | Yes | Yes |
| Model Discovery | No | No | No | Yes | Yes |
| Built-in Retry | No | No | Yes (3x expo) | No | No |
| Actor-based | No | No | No | Yes | Yes |
| LLM Protocol | Via Adapter | Via Adapter | Via Adapter | Via Adapter | Via Adapter |

### Provider-Specific Notes

**OpenAI**: Has two APIs — Chat Completions (legacy) and Responses API (v1). The Responses API supports web search, code interpreter, and file search as built-in tools. Use `createResponse()` / `createResponseStream()` for the Responses API.

**Anthropic**: Enforces `n=1`, caps `temperature` at 1.0. Silently drops unsupported params (logprobs, penalties, seed). Extended thinking uses `budgetTokens` from `AIReasoningConfig`.

**Gemini**: Native multimodal (text, image, audio, video). File uploads support resumable chunked upload (256KB chunks). Built-in retry with exponential backoff.

**OpenRouter**: Aggregates 200+ models. Capabilities are model-dependent — check `capabilities(for: modelId)`. Supports `appName` and `siteURL` for attribution.

**LiteLLM**: Self-hosted proxy at `localhost:4000` by default. API key optional. Inherits capabilities from underlying provider. Good for local development and testing.

---

## 15. Configuration Reference

Global SDK configuration with provider setup, reliability tuning, and PHI enforcement.

### Key Types

| Type | File |
|------|------|
| `AISDKConfiguration` | `Sources/AISDK/Core/Configuration/AISDKConfiguration.swift` |
| `AIProviderConfiguration` | `Sources/AISDK/Core/Configuration/AISDKConfiguration.swift` |
| `AIReliabilityConfiguration` | `Sources/AISDK/Core/Configuration/AISDKConfiguration.swift` |
| `AITelemetryConfiguration` | `Sources/AISDK/Core/Configuration/AISDKConfiguration.swift` |
| `DataSensitivity` | `Sources/AISDK/Core/Models/AITextRequest.swift` |

### Usage: Configure at Launch

```swift
try AISDKConfiguration.configure { builder in
    builder.defaultModel("gpt-4o")

    builder.addProvider(.openai(
        apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
        defaultModel: "gpt-4o",
        trustedForPHI: false
    ))

    builder.addProvider(.anthropic(
        apiKey: ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
        defaultModel: "claude-3-5-sonnet-20241022",
        trustedForPHI: true             // allowed for PHI data
    ))

    builder.addProvider(.google(
        apiKey: ProcessInfo.processInfo.environment["GOOGLE_API_KEY"],
        defaultModel: "gemini-1.5-pro",
        trustedForPHI: false
    ))

    builder.addProvider(.openRouter(
        apiKey: ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
        trustedForPHI: false
    ))

    builder.defaultSensitivity(.standard)
    builder.enforcePHIProtection(true)
    builder.maxConcurrentRequests(10)

    builder.reliability(AIReliabilityConfiguration(
        defaultTimeout: 60.0,
        maxRetries: 3,
        circuitBreakerEnabled: true,
        circuitBreakerThreshold: 5,
        failoverEnabled: true,
        failoverMaxCostMultiplier: 2.0
    ))

    builder.telemetry(AITelemetryConfiguration(
        isEnabled: true,
        includeContent: false,          // never log message content
        logErrors: true,
        samplingRate: 1.0
    ))
}
```

### Data Sensitivity Levels

```swift
public enum DataSensitivity: String, Sendable, Codable {
    case standard     // no restrictions
    case sensitive    // logged carefully, no external analytics
    case phi          // HIPAA-grade: only trustedForPHI providers, redacted logging
}
```

When `sensitivity == .phi` and `enforcePHIProtection == true`:
- Requests are blocked if sent to a provider where `trustedForPHI == false`
- Error: `AISDKErrorV2.providerNotAllowed`
- Use `allowedProviders` on `AITextRequest` to further restrict

### Provider Configuration

```swift
// Custom provider
let custom = AIProviderConfiguration(
    provider: "azure-openai",
    apiKey: "...",
    apiKeyEnvVars: ["AZURE_OPENAI_KEY", "AZURE_API_KEY"],  // fallback env vars
    baseURL: URL(string: "https://myinstance.openai.azure.com"),
    organizationId: "org-...",
    defaultModel: "gpt-4o",
    maxRequestsPerMinute: 60,
    maxTokensPerMinute: 100_000,
    customHeaders: ["api-version": "2024-02-01"],
    isEnabled: true,
    trustedForPHI: true,
    requiresAPIKey: true
)
```

API keys resolve in order: explicit `apiKey` parameter > environment variables from `apiKeyEnvVars`.

### Gotchas

- `AISDKConfiguration.configure()` can only be called **once**. Subsequent calls throw.
- Use `AISDKConfiguration._resetForTesting()` in test setup.
- `AIProviderConfiguration` convenience methods (`.openai()`, `.anthropic()`, etc.) use standard env var names (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `OPENROUTER_API_KEY`).
- `maxConcurrentRequests: 0` means unlimited.

---

## 16. SwiftUI Integration

Observable patterns for binding agent state, chat sessions, and generative UI to SwiftUI views.

### Key Types

| Type | File |
|------|------|
| `ObservableAgentState` | `Sources/AISDK/Agents/Agent.swift` |
| `ChatViewModel` | `Sources/AISDK/Sessions/ViewModels/ChatViewModel.swift` |
| `GenerativeUIViewModel` | `Sources/AISDK/GenerativeUI/ViewModels/GenerativeUIViewModel.swift` |
| `GenerativeUIView` | `Sources/AISDK/GenerativeUI/Views/GenerativeUIView.swift` |
| `GenerativeUISpecView` | `Sources/AISDK/GenerativeUI/Views/GenerativeUIView.swift` |

### ChatViewModel

Full-featured chat management with session persistence, streaming, checkpoints, and rewind.

```swift
@Observable
@MainActor
public final class ChatViewModel {
    public private(set) var session: AISession
    public private(set) var isStreaming: Bool
    public private(set) var error: Error?

    public init(agent: Agent, store: any SessionStore, session: AISession? = nil)

    // Lifecycle
    public func createSession(userId: String, title: String? = nil) async throws
    public func loadSession(id: String) async throws

    // Messaging
    public func send(_ text: String) async          // send + stream response
    public func resume() async                       // resume after error
    public func rewind(to checkpointIndex: Int) async
    public func retryLastTurn() async
    public func cancel()
}
```

### Usage: Chat View

```swift
struct ChatView: View {
    @State var viewModel: ChatViewModel

    init(agent: Agent, store: any SessionStore) {
        _viewModel = State(initialValue: ChatViewModel(agent: agent, store: store))
    }

    var body: some View {
        VStack {
            ScrollView {
                ForEach(viewModel.session.messages, id: \.id) { message in
                    MessageBubble(message: message)
                }
            }

            if viewModel.isStreaming {
                ProgressView("Thinking...")
            }

            if let error = viewModel.error {
                ErrorBanner(error: error) {
                    Task { await viewModel.retryLastTurn() }
                }
            }

            MessageInput { text in
                Task { await viewModel.send(text) }
            }
        }
        .task {
            try? await viewModel.createSession(userId: "user_123")
        }
    }
}
```

### Agent State Binding

```swift
struct AgentStatusView: View {
    let agent: Agent

    var body: some View {
        let state = agent.observableState

        VStack {
            switch state.state {
            case .idle: Text("Ready")
            case .thinking: ProgressView("Thinking...")
            case .executingTool(let name): Text("Running \(name)...")
            case .responding: Text("Writing response...")
            case .error(let err): Text("Error: \(err.localizedDescription)")
            }

            if state.isProcessing {
                Text("Step \(state.currentStep)")
            }
        }
    }
}
```

### GenerativeUIViewModel

```swift
struct GenerativeUIScreen: View {
    @State var viewModel = GenerativeUIViewModel.streaming()
    let agent: Agent

    var body: some View {
        VStack {
            if let tree = viewModel.tree {
                GenerativeUIView(tree: tree, registry: .secureDefault) { action in
                    print("User action: \(action)")
                }
            }

            if viewModel.isLoading {
                ProgressView()
            }
        }
        .task {
            let compiler = SpecStreamCompiler()
            let stream = agent.streamExecute(messages: [.user("Show dashboard")])
            await viewModel.subscribe(toEvents: stream, compiler: compiler) { text in
                // Handle interleaved text
            }
        }
    }
}
```

### Gotchas

- `ChatViewModel` and `GenerativeUIViewModel` are `@MainActor` — access from main thread only.
- `ObservableAgentState` properties are `@MainActor` but the agent itself is an actor — reads are main-thread-safe.
- `ChatViewModel.send()` handles the full cycle: append user message, stream response, persist to store, create checkpoint.
- Call `viewModel.cancel()` to interrupt an in-flight stream.
- `GenerativeUIViewModel.cancelSubscription()` stops listening to streams — call when the view disappears.

---

## Quick Reference: Message Construction

```swift
AIMessage.user("Hello")
AIMessage.assistant("Hi there!")
AIMessage.system("You are a helpful assistant.")
AIMessage.tool("Result data", toolCallId: "call_abc123")

// Multimodal
AIMessage(role: .user, content: .parts([
    .text("What's in this image?"),
    .image(imageData, mimeType: "image/png"),
]))
```

## Quick Reference: AIMessage Content Parts

```swift
public enum ContentPart: Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case imageURL(String)
    case audio(Data, mimeType: String)
    case file(Data, filename: String, mimeType: String)
    case video(Data, mimeType: String)
    case videoURL(String)
}
```

## Quick Reference: Minimal Agent + Tools

```swift
import AISDK

struct CalculatorTool: Tool {
    var name: String { "calculate" }
    var description: String { "Evaluate a math expression" }
    var returnToolResponse: Bool { false }

    @Parameter(description: "Math expression to evaluate")
    var expression: String = ""

    func execute() async throws -> ToolResult {
        // Your evaluation logic
        ToolResult(content: "42")
    }
}

let model = AILanguageModelAdapter(
    llm: OpenAIProvider(apiKey: "sk-..."),
    provider: "openai",
    modelId: "gpt-4o",
    capabilities: [.text, .tools, .streaming]
)

let agent = Agent(model: model, tools: [CalculatorTool.self])
let result = try await agent.execute(messages: [.user("What is 6 * 7?")])
print(result.text)  // "The result of 6 * 7 is 42."
```
