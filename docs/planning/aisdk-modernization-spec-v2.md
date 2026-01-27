# AISDK Swift Modernization - Comprehensive Specification v2

**Generated**: 2026-01-22
**Version**: 2.0 (Post-Interview Synthesis)
**Estimated Complexity**: High
**Total Phases**: 7
**Reliability Target**: 99.99% uptime

---

## Executive Summary

This specification defines the complete modernization of AISDK to achieve feature parity with Vercel AI SDK 6.x while maintaining Swift/iOS best practices. Based on stakeholder interviews and codebase research, this is a **full rewrite** (clean slate) with no backward compatibility constraints.

### Key Architectural Decisions (From Interview)

| Decision Area | Choice | Rationale |
|--------------|--------|-----------|
| **Default Provider** | GPT-5-mini | Model-agnostic, easily switchable |
| **Primary Router** | OpenRouter | Managed, production-ready |
| **Secondary Router** | LiteLLM | Self-hosted option supported |
| **Streaming Events** | Full Vercel parity (10+ events) | Complete feature parity |
| **Tool Call Repair** | Hybrid (auto-repair once, then fail) | Balance reliability & debuggability |
| **Circuit Breaker** | Adaptive smart approach | 99.99% uptime requirement |
| **Agent Concurrency** | Full actor-based isolation | Thread safety guaranteed |
| **Generative UI** | json-render pattern, Core 8 components | Progressive enhancement path |
| **Testing** | Hybrid (mocks + real API) | Fast CI + realistic validation |
| **Metadata/Telemetry** | UI focus now, full telemetry later | Phased approach |
| **Documentation** | Full with tutorials | Production readiness |

---

## Part 1: Core Protocol Layer

### 1.1 AILanguageModel Protocol

**Location**: `Sources/AISDK/Core/Protocols/AILanguageModel.swift`

```swift
/// Core language model protocol - Swift equivalent of Vercel's LanguageModelV3
public protocol AILanguageModel: Actor, Sendable {
    /// Provider identifier (e.g., "openai", "anthropic", "gemini")
    var provider: String { get }

    /// Model identifier (e.g., "gpt-5-mini", "claude-4-sonnet")
    var modelId: String { get }

    /// Model capabilities for routing decisions
    var capabilities: LLMCapabilities { get }

    /// Generate text completion (non-streaming)
    func generateText(request: AITextRequest) async throws -> AITextResult

    /// Stream text completion with full event model
    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>

    /// Generate structured object (non-streaming)
    func generateObject<T: Codable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T>

    /// Stream structured object with partial updates
    func streamObject<T: Codable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error>
}
```

### 1.2 Streaming Event Model (Full Vercel Parity)

**Location**: `Sources/AISDK/Core/Models/AIStreamEvent.swift`

```swift
/// Unified streaming event model - matches Vercel AI SDK 6.x exactly
public enum AIStreamEvent: Sendable, Codable {
    // Text Events
    case textDelta(String)
    case textCompletion(String)

    // Tool Call Events (10+ events for full parity)
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCallFinish(id: String, arguments: String)
    case toolResult(id: String, result: String, metadata: ToolMetadata?)

    // Step Events (multi-step agent support)
    case stepStart(stepIndex: Int)
    case stepFinish(AIStepResult)

    // Completion Events
    case finish(finishReason: AIFinishReason, usage: AIUsage)
    case error(AIError)

    // Reasoning/Thinking Events (for reasoning models)
    case reasoningStart
    case reasoningDelta(String)
    case reasoningFinish(String)
}

public enum AIFinishReason: String, Sendable, Codable {
    case stop
    case length
    case toolCalls = "tool_calls"
    case contentFilter = "content_filter"
    case error
}
```

### 1.3 Request/Response Models

**Location**: `Sources/AISDK/Core/Models/`

```swift
/// Text generation request
public struct AITextRequest: Sendable {
    public let messages: [AIMessage]
    public let model: String?
    public let temperature: Double?
    public let maxTokens: Int?
    public let tools: [any AITool.Type]?
    public let toolChoice: AIToolChoice?
    public let responseFormat: AIResponseFormat?
    public let instructions: String?  // System prompt (renamed per Vercel 6.x)

    // Reliability overrides
    public let timeout: TimeInterval?
    public let retryPolicy: RetryPolicy?
    public let traceContext: AITraceContext?
}

/// Text generation result
public struct AITextResult: Sendable {
    public let text: String
    public let toolCalls: [AIToolCall]
    public let toolResults: [AIToolResult]
    public let finishReason: AIFinishReason
    public let usage: AIUsage
    public let traceContext: AITraceContext
    public let latency: TimeInterval
}

/// Step result for multi-step agents
public struct AIStepResult: Sendable, Codable {
    public let stepIndex: Int
    public let text: String?
    public let toolCalls: [AIToolCall]
    public let toolResults: [AIToolResult]
    public let finishReason: AIFinishReason
    public let usage: AIUsage
}

/// Usage tracking
public struct AIUsage: Sendable, Codable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let cachedTokens: Int?
    public let reasoningTokens: Int?
}
```

---

## Part 2: Provider & Routing Layer

### 2.1 Provider Architecture

**Research Finding**: Current providers have 95% code duplication in streaming. Solution: Unified `ProviderClient` protocol with shared streaming infrastructure.

```swift
/// Provider client protocol - all providers implement this
public protocol ProviderClient: Actor, Sendable {
    var providerId: String { get }
    var supportedModels: [String] { get }
    var capabilities: LLMCapabilities { get }

    func generate(request: ProviderRequest) async throws -> ProviderResponse
    func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error>
}

/// Adapter to convert legacy providers to new protocol
public struct ProviderAdapter<P: LLM>: ProviderClient {
    private let provider: P
    private let streamMapper: AIStreamMapper

    public func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderChunk, Error> {
        // Maps legacy AsyncThrowingStream<ChatCompletionChunk> to unified ProviderChunk
    }
}
```

### 2.2 OpenRouter Client (Primary)

**Location**: `Sources/AISDK/Core/Routing/OpenRouterClient.swift`

```swift
/// OpenRouter client - primary routing solution
public actor OpenRouterClient: ProviderClient {
    public let providerId = "openrouter"

    private let apiKey: String
    private let baseURL: URL
    private let defaultModel: String  // "openai/gpt-5-mini"

    public init(
        apiKey: String = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? "",
        defaultModel: String = "openai/gpt-5-mini"
    )

    // Supports model aliases: "gpt-5" -> "openai/gpt-5"
    // Supports provider hints: prefer specific providers
    // Includes usage metadata in responses
}
```

### 2.3 LiteLLM Client (Secondary)

**Location**: `Sources/AISDK/Core/Routing/LiteLLMClient.swift`

```swift
/// LiteLLM client - self-hosted routing option
public actor LiteLLMClient: ProviderClient {
    public let providerId = "litellm"

    private let baseURL: URL
    private let apiKey: String?

    public init(
        baseURL: URL = URL(string: ProcessInfo.processInfo.environment["LITELLM_BASE_URL"] ?? "http://localhost:4000")!,
        apiKey: String? = ProcessInfo.processInfo.environment["LITELLM_API_KEY"]
    )
}
```

### 2.4 Model Registry

```swift
/// Capability-aware model selection
public actor ModelRegistry {
    public static let shared = ModelRegistry()

    /// Resolve best model for request based on capabilities
    public func resolve(
        request: AITextRequest,
        preferredProvider: String? = nil,
        requiredCapabilities: LLMCapabilities = []
    ) -> ResolvedModel

    /// Get all models matching capabilities
    public func models(matching capabilities: LLMCapabilities) -> [LLMModel]
}

public struct ResolvedModel {
    public let provider: String
    public let modelId: String
    public let capabilities: LLMCapabilities
    public let costTier: CostTier
    public let latencyTier: LatencyTier
}
```

---

## Part 3: Reliability Layer

### 3.1 Adaptive Circuit Breaker (99.99% Uptime)

**Interview Decision**: Smart/adaptive approach with error-type awareness

**Location**: `Sources/AISDK/Core/Reliability/AdaptiveCircuitBreaker.swift`

```swift
/// Adaptive circuit breaker with error-type awareness
public actor AdaptiveCircuitBreaker {
    public enum State: Sendable {
        case closed      // Normal operation
        case open        // Failing, rejecting requests
        case halfOpen    // Testing recovery
    }

    public struct Configuration {
        /// Failure thresholds by error type
        public let authErrorThreshold: Int = 1      // Immediate open
        public let rateLimitThreshold: Int = 3      // Quick open
        public let timeoutThreshold: Int = 5        // Standard threshold
        public let genericErrorThreshold: Int = 5   // Standard threshold

        /// Time windows
        public let windowDuration: TimeInterval = 60
        public let openDuration: TimeInterval = 30
        public let halfOpenTestCount: Int = 3

        /// Exponential backoff
        public let initialBackoff: TimeInterval = 1
        public let maxBackoff: TimeInterval = 60
        public let backoffMultiplier: Double = 2
        public let jitterFactor: Double = 0.1
    }

    public func recordSuccess()
    public func recordFailure(error: AIError)
    public func shouldAllow() -> Bool
    public func state() -> State
}
```

### 3.2 Failover Chain

```swift
/// Provider failover chain for high availability
public actor FailoverExecutor {
    private let chain: [ProviderClient]
    private let circuitBreakers: [String: AdaptiveCircuitBreaker]
    private let healthMonitor: ProviderHealthMonitor

    public init(chain: [ProviderClient]) {
        // Default chain: OpenRouter -> OpenAI -> Anthropic -> Gemini
    }

    /// Execute with automatic failover
    public func execute<T>(
        request: AITextRequest,
        operation: (ProviderClient, AITextRequest) async throws -> T
    ) async throws -> (result: T, provider: String, attempts: Int)
}
```

### 3.3 Health Monitoring

```swift
/// Provider health monitoring for proactive failover
public actor ProviderHealthMonitor {
    public struct HealthStatus: Sendable {
        public let providerId: String
        public let isHealthy: Bool
        public let latencyP50: TimeInterval
        public let latencyP99: TimeInterval
        public let errorRate: Double
        public let lastChecked: Date
    }

    /// Get current health status for all providers
    public func healthStatus() -> [HealthStatus]

    /// Proactive health check (called periodically)
    public func performHealthCheck() async
}
```

---

## Part 4: Agent & Tool Framework

### 4.1 Actor-Based Agent (Full Isolation)

**Interview Decision**: Full actor-based isolation for thread safety

**Location**: `Sources/AISDK/Agents/AIAgent.swift`

```swift
/// Multi-step agent with full actor isolation
public actor AIAgent {
    // Configuration
    public let model: any AILanguageModel
    public let tools: [any AITool.Type]
    public let instructions: String?
    public let stopCondition: StopCondition

    // State (actor-isolated)
    private var state: AgentState = .idle
    private var stepHistory: [AIStepResult] = []
    private var messageHistory: [AIMessage] = []

    public init(
        model: any AILanguageModel,
        tools: [any AITool.Type] = [],
        instructions: String? = nil,
        stopCondition: StopCondition = .stepCount(20)  // Vercel 6.x default
    )

    /// Execute agent loop (non-streaming)
    public func execute(messages: [AIMessage]) async throws -> AIAgentResult

    /// Execute agent loop (streaming with step callbacks)
    public func executeStream(
        messages: [AIMessage],
        onStepFinish: @Sendable @escaping (AIStepResult) async -> StepAction = { _ in .continue },
        prepareStep: @Sendable @escaping (Int, [AIMessage]) async -> StepPreparation = { _, _ in .default }
    ) -> AsyncThrowingStream<AIStreamEvent, Error>

    /// Current state (observable)
    public func currentState() -> AgentState
}

/// Stop conditions for agent loop
public enum StopCondition: Sendable {
    case stepCount(Int)
    case noToolCalls
    case custom(@Sendable (AIStepResult) -> Bool)
}

/// Step action for callback control
public enum StepAction: Sendable {
    case `continue`
    case stop
    case inject([AIMessage])  // Inject additional context
}

/// Step preparation for dynamic configuration
public struct StepPreparation: Sendable {
    public let model: (any AILanguageModel)?
    public let tools: [any AITool.Type]?
    public let temperature: Double?

    public static let `default` = StepPreparation(model: nil, tools: nil, temperature: nil)
}
```

### 4.2 Tool Call Repair (Hybrid)

**Interview Decision**: Auto-repair once, then fail

```swift
/// Tool call repair mechanism
public struct ToolCallRepair {
    public enum Strategy: Sendable {
        case strict           // Fail immediately
        case autoRepairOnce   // Retry with error context (SELECTED)
        case autoRepairMax(Int)
        case custom(@Sendable (AIToolCall, ToolError) async throws -> AIToolCall?)
    }

    /// Attempt to repair a failed tool call
    public static func repair(
        toolCall: AIToolCall,
        error: ToolError,
        model: any AILanguageModel,
        strategy: Strategy = .autoRepairOnce
    ) async throws -> AIToolCall?
}
```

### 4.3 Enhanced Tool Protocol

```swift
/// Enhanced tool protocol with validation
public protocol AITool: Sendable {
    /// Tool identifier
    var name: String { get }

    /// Human-readable description
    var description: String { get }

    /// Whether to return result to model
    var returnToolResponse: Bool { get }

    /// Generate JSON schema for parameters
    static func jsonSchema() -> ToolSchema

    /// Validate parameters before execution
    static func validate(arguments: [String: Any]) throws

    /// Initialize with parameters
    init()
    mutating func setParameters(from arguments: [String: Any]) throws
    mutating func validateAndSetParameters(_ argumentsData: Data) throws -> Self

    /// Execute the tool
    func execute() async throws -> AIToolResult
}

public struct AIToolResult: Sendable {
    public let content: String
    public let metadata: ToolMetadata?
    public let artifacts: [ToolArtifact]?  // Files, images, etc.
}
```

---

## Part 5: Generative UI (json-render Pattern)

### 5.1 Component Catalog

**Interview Decision**: Core 8 components, progressive enhancement

**Location**: `Sources/AISDK/GenerativeUI/Catalog/`

```swift
/// Component catalog - defines available UI components for LLM
public struct UICatalog: Sendable {
    public let components: [String: UIComponentDefinition]
    public let actions: [String: UIActionDefinition]
    public let validators: [String: UIValidatorDefinition]

    /// Generate system prompt for LLM
    public func generatePrompt() -> String

    /// Core 8 components (initial catalog)
    public static let core8 = UICatalog(components: [
        "Text": TextComponentDefinition(),
        "Button": ButtonComponentDefinition(),
        "Card": CardComponentDefinition(),
        "Input": InputComponentDefinition(),
        "List": ListComponentDefinition(),
        "Image": ImageComponentDefinition(),
        "Stack": StackComponentDefinition(),
        "Spacer": SpacerComponentDefinition()
    ])
}

/// Component definition with Codable props schema
public protocol UIComponentDefinition: Sendable {
    associatedtype Props: Codable & Sendable

    var type: String { get }
    var hasChildren: Bool { get }
    var propsSchema: JSONSchema { get }
}
```

### 5.2 UI Tree Model

```swift
/// UI tree - flat element map (json-render pattern)
public struct UITree: Codable, Sendable {
    public let root: String
    public let elements: [String: UIElement]
}

public struct UIElement: Codable, Sendable {
    public let key: String
    public let type: String
    public let props: [String: AnyCodable]
    public let children: [String]?
    public let visible: UIVisibilityCondition?
}
```

### 5.3 SwiftUI Component Registry

```swift
/// Registry mapping element types to SwiftUI views
public struct UIComponentRegistry {
    public typealias ViewBuilder = @Sendable (UIElement, UITree, UIActionHandler) -> AnyView

    private var builders: [String: ViewBuilder]

    public mutating func register<V: View>(
        _ type: String,
        builder: @escaping @Sendable (UIElement, UITree, UIActionHandler) -> V
    )

    public func build(element: UIElement, tree: UITree, actionHandler: UIActionHandler) -> AnyView

    /// Default registry with Core 8 components
    public static let `default`: UIComponentRegistry
}
```

### 5.4 Streaming UI Renderer

```swift
/// SwiftUI view for streaming generative UI
public struct GenerativeUIView: View {
    @StateObject private var viewModel: GenerativeUIViewModel

    public init(
        stream: AsyncThrowingStream<AIStreamEvent, Error>,
        catalog: UICatalog = .core8,
        registry: UIComponentRegistry = .default,
        onAction: @escaping UIActionHandler = { _ in }
    )

    public var body: some View {
        // Renders UITree progressively as stream updates
    }
}

@MainActor
public class GenerativeUIViewModel: ObservableObject {
    @Published public var tree: UITree?
    @Published public var isLoading: Bool = true
    @Published public var error: AIError?

    /// Process streaming events and update tree
    public func process(event: AIStreamEvent)
}
```

---

## Part 6: Testing Infrastructure

### 6.1 Mock Provider

**Interview Decision**: Hybrid testing (mocks for unit, real for integration)

```swift
/// Mock language model for deterministic testing
public actor MockAILanguageModel: AILanguageModel {
    public let provider = "mock"
    public var modelId: String
    public var capabilities: LLMCapabilities

    // Configurable handlers
    public var generateHandler: (@Sendable (AITextRequest) async throws -> AITextResult)?
    public var streamHandler: (@Sendable (AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>)?

    /// Preset responses for common test scenarios
    public static func withResponse(_ text: String) -> MockAILanguageModel
    public static func withToolCall(_ name: String, arguments: String) -> MockAILanguageModel
    public static func failing(with error: AIError) -> MockAILanguageModel
}
```

### 6.2 Stream Simulation

```swift
/// Simulate streaming for tests
public func simulateStream(
    events: [AIStreamEvent],
    intervalMs: UInt64 = 50
) -> AsyncThrowingStream<AIStreamEvent, Error> {
    AsyncThrowingStream { continuation in
        Task {
            for event in events {
                try await Task.sleep(nanoseconds: intervalMs * 1_000_000)
                continuation.yield(event)
            }
            continuation.finish()
        }
    }
}

/// Simulate realistic text streaming
public func simulateTextStream(
    text: String,
    chunkSize: Int = 5,
    intervalMs: UInt64 = 30
) -> AsyncThrowingStream<AIStreamEvent, Error>
```

### 6.3 Provider Contract Tests

```swift
/// Shared contract tests all providers must pass
public protocol ProviderContractTests {
    /// The provider under test
    var provider: any ProviderClient { get }

    // Required tests
    func testGenerateText_simplePrompt() async throws
    func testGenerateText_withTools() async throws
    func testStreamText_emitsCorrectEvents() async throws
    func testGenerateObject_decodesCorrectly() async throws
    func testErrorHandling_authError() async throws
    func testErrorHandling_rateLimitError() async throws
}
```

### 6.4 Fault Injection

```swift
/// Fault injection for reliability testing
public actor FaultInjector {
    public enum Fault: Sendable {
        case latency(TimeInterval)
        case error(AIError)
        case timeout
        case rateLimited
        case partialResponse(afterTokens: Int)
    }

    public func inject(_ fault: Fault, for providerId: String)
    public func clearAll()
}
```

---

## Part 7: Documentation & Migration

### 7.1 Documentation Structure

```
docs/
  AISDK-ARCHITECTURE.md          # Updated architecture doc
  MIGRATION-GUIDE.md             # Migration from old API
  tutorials/
    01-getting-started.md
    02-streaming-basics.md
    03-tool-creation.md
    04-multi-step-agents.md
    05-generative-ui.md
    06-reliability-patterns.md
    07-testing-strategies.md
  api-reference/
    core-protocols.md
    providers.md
    agents.md
    tools.md
    generative-ui.md
    reliability.md
```

### 7.2 Migration Examples

```swift
// OLD API
let provider = OpenAIProvider(apiKey: "...")
let response = try await provider.sendChatCompletion(request: request)

// NEW API
let model = OpenRouterClient()
let result = try await model.generateText(request: AITextRequest(
    messages: [.user("Hello")],
    model: "openai/gpt-5-mini"
))

// OLD Agent
let agent = Agent(provider: provider, tools: [WeatherTool.self])
let response = try await agent.send("What's the weather?")

// NEW Agent
let agent = AIAgent(
    model: model,
    tools: [WeatherTool.self],
    stopCondition: .stepCount(10)
)
let result = try await agent.execute(messages: [.user("What's the weather?")])
```

---

## Implementation Phases

### Phase 1: Core Protocol Layer (Weeks 1-2)
- Task 1.1: AILanguageModel protocol
- Task 1.2: AIStreamEvent model (10+ events)
- Task 1.3: Request/Response models
- Task 1.4: AIError taxonomy
- Task 1.5: Core configuration

### Phase 2: Provider & Routing (Weeks 3-4)
- Task 2.1: ProviderClient protocol
- Task 2.2: OpenRouterClient (primary)
- Task 2.3: LiteLLMClient (secondary)
- Task 2.4: ModelRegistry
- Task 2.5: Provider adapters

### Phase 3: Reliability Layer (Weeks 5-6)
- Task 3.1: Adaptive circuit breaker
- Task 3.2: Failover chain executor
- Task 3.3: Health monitoring
- Task 3.4: Retry/timeout policies

### Phase 4: Agent & Tools (Weeks 7-8)
- Task 4.1: Actor-based AIAgent
- Task 4.2: AITool call repair (hybrid)
- Task 4.3: Step callbacks
- Task 4.4: Enhanced Tool protocol

### Phase 5: Generative UI (Weeks 9-10)
- Task 5.1: UICatalog system
- Task 5.2: UITree model
- Task 5.3: Component registry
- Task 5.4: GenerativeUIView
- Task 5.5: Core 8 components

### Phase 6: Testing Infrastructure (Weeks 11-12)
- Task 6.1: MockAILanguageModel
- Task 6.2: Stream simulation
- Task 6.3: Contract tests
- Task 6.4: Fault injection
- Task 6.5: CI integration

### Phase 7: Documentation & Polish (Week 13)
- Task 7.1: Architecture docs
- Task 7.2: Migration guide
- Task 7.3: Tutorials
- Task 7.4: API reference
- Task 7.5: Optional telemetry layer

---

## Dependency Graph

```
Phase 1 (Core) ─────────────────────────────────────────┐
    │                                                   │
    ├──► Phase 2 (Routing) ──► Phase 3 (Reliability) ──┤
    │                                                   │
    └──► Phase 4 (Agents) ──► Phase 5 (Generative UI) ─┤
                                                        │
Phase 6 (Testing) ◄────────────────────────────────────┘
    │
    ▼
Phase 7 (Documentation)
```

**Parallel Execution**:
- Phase 2 and Phase 4 can run in parallel after Phase 1
- Phase 6 can run in parallel with all phases
- Phase 3 depends on Phase 2
- Phase 5 depends on Phase 4

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Actor overhead | Benchmark early, optimize hot paths |
| Streaming complexity | Comprehensive event tests |
| Provider API changes | Adapter pattern isolates changes |
| Circuit breaker false positives | Tunable thresholds, health probing |
| Generative UI complexity | Start with Core 8, expand later |

---

## Success Criteria

1. **Feature Parity**: All Vercel AI SDK 6.x core features implemented
2. **Reliability**: 99.99% uptime with failover chains
3. **Performance**: P99 latency < 200ms overhead
4. **Test Coverage**: 80%+ on core, 100% on error paths
5. **Documentation**: Complete tutorials and API reference
6. **Migration**: Working migration guide with examples
