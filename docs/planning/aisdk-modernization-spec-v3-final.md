# AISDK Swift Modernization - Final Specification v3

**Generated**: 2026-01-22
**Version**: 3.0 (Final - Post External Review)
**Total Phases**: 8 (including Phase 0: Adapters)
**Total Tasks**: 53
**Timeline**: 15 weeks
**Reliability Target**: 99.99% uptime

---

## Executive Summary

This is the final, reviewed specification for modernizing AISDK to achieve feature parity with Vercel AI SDK 6.x. It incorporates:
- Stakeholder interview decisions (GPT-5-mini default, full actor isolation, Core 8 UI components)
- Research findings (Vercel patterns, current codebase analysis)
- External review feedback (reentrancy safety, memory management, PHI protection)

**Key Architecture Decisions**:

| Area | Decision | Rationale |
|------|----------|-----------|
| Concurrency | Actor-based with ObservableState | Thread safety + UI reactivity |
| Streaming | Bounded AsyncThrowingStream | Memory safety |
| Routing | OpenRouter primary | Managed, production-ready |
| Failover | Capability-aware with cost constraints | Reliability + cost control |
| Tools | Immutable Sendable protocol | Concurrency safety |
| UI | json-render pattern with Core 8 | Progressive enhancement |

---

## Phase 0: Adapter Layer (Week 1)

**Goal**: Safe migration path for existing consumers
**Rationale**: External review identified high risk in "clean slate" approach

### Task 0.1: AILanguageModelAdapter
- **Location**: `Sources/AISDK/Core/Adapters/Legacy/AILanguageModelAdapter.swift`
- **Complexity**: 3/10
- **Description**: Wrap existing `LLM` protocol to conform to new `AILanguageModel`

### Task 0.2: AIAgentAdapter
- **Location**: `Sources/AISDK/Core/Adapters/Legacy/AIAgentAdapter.swift`
- **Complexity**: 4/10
- **Description**: Wrap existing `Agent` class with new `AIAgent` interface

### Task 0.3: ToolAdapter
- **Location**: `Sources/AISDK/Core/Adapters/Legacy/ToolAdapter.swift`
- **Complexity**: 3/10
- **Description**: Adapt `@Parameter`-based tools to new `AITool` protocol

---

## Phase 1: Core Protocol Layer (Weeks 2-3)

**Goal**: Unified API surface with safety guarantees

### Task 1.1: AILanguageModel Protocol
- **Location**: `Sources/AISDK/Core/Protocols/AILanguageModel.swift`
- **Complexity**: 6/10
- **Implementation**:
```swift
public protocol AILanguageModel: Actor, Sendable {
    var provider: String { get }
    var modelId: String { get }
    var capabilities: LLMCapabilities { get }

    func generateText(request: AITextRequest) async throws -> AITextResult
    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
    func generateObject<T: Codable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T>
    func streamObject<T: Codable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error>
}
```

### Task 1.2: AIStreamEvent (10+ Events)
- **Location**: `Sources/AISDK/Core/Models/AIStreamEvent.swift`
- **Complexity**: 5/10
- **Events**: textDelta, textCompletion, toolCallStart, toolCallDelta, toolCallFinish, toolResult, stepStart, stepFinish, finish, error, reasoningStart, reasoningDelta, reasoningFinish, **heartbeat** (new)

### Task 1.3: AITextRequest/AITextResult
- **Location**: `Sources/AISDK/Core/Models/`
- **Complexity**: 5/10
- **New Fields** (from review):
  - `allowedProviders: Set<String>?` - PHI protection
  - `sensitivity: DataSensitivity` - Data classification
  - `bufferPolicy: StreamBufferPolicy?` - Memory control

### Task 1.4: AIObjectRequest/AIObjectResult
- **Location**: `Sources/AISDK/Core/Models/`
- **Complexity**: 6/10

### Task 1.5: AIStepResult
- **Location**: `Sources/AISDK/Core/Models/AIStepResult.swift`
- **Complexity**: 4/10

### Task 1.6: AIUsage/AIFinishReason
- **Location**: `Sources/AISDK/Core/Models/`
- **Complexity**: 3/10

### Task 1.7: AIError Taxonomy
- **Location**: `Sources/AISDK/Core/Errors/AIError.swift`
- **Complexity**: 6/10
- **New**: PHI redaction enforcement

### Task 1.8: AITraceContext
- **Location**: `Sources/AISDK/Core/Models/AITraceContext.swift`
- **Complexity**: 4/10

### Task 1.9: AISDKConfiguration
- **Location**: `Sources/AISDK/Core/Configuration/AISDKConfiguration.swift`
- **Complexity**: 4/10
- **New**: Startup validation with fail-fast

### Task 1.10: AISDKObserver Protocol (NEW)
- **Location**: `Sources/AISDK/Core/Telemetry/AISDKObserver.swift`
- **Complexity**: 4/10
- **Description**: Telemetry hooks from day one
```swift
public protocol AISDKObserver: Sendable {
    func didStartRequest(_ context: AITraceContext)
    func didReceiveEvent(_ event: AIStreamEvent, context: AITraceContext)
    func didCompleteRequest(_ result: AITextResult, context: AITraceContext)
    func didFailRequest(_ error: AIError, context: AITraceContext)
}
```

### Task 1.11: SafeAsyncStream Utility (NEW)
- **Location**: `Sources/AISDK/Core/Utilities/SafeAsyncStream.swift`
- **Complexity**: 5/10
- **Description**: Memory-safe stream creation with cancellation handling
```swift
public struct SafeAsyncStream {
    public static func make<Element>(
        bufferingPolicy: StreamBufferPolicy = .bounded(capacity: 1000),
        _ build: @escaping @Sendable (Continuation) async throws -> Void
    ) -> AsyncThrowingStream<Element, Error>
}
```

### Task 1.12: MockAILanguageModel (moved from Phase 6)
- **Location**: `Tests/AISDKTests/Mocks/MockAILanguageModel.swift`
- **Complexity**: 5/10

### Task 1.13: simulateStream Helper (moved from Phase 6)
- **Location**: `Tests/AISDKTests/Helpers/StreamSimulation.swift`
- **Complexity**: 4/10

---

## Phase 2: Provider & Routing Layer (Weeks 4-5)

### Task 2.1: ProviderClient Protocol
- **Complexity**: 5/10

### Task 2.2: OpenRouterClient (Primary)
- **Complexity**: 8/10 (adjusted)
- **Features**: Model aliases, provider hints, usage metadata

### Task 2.3: LiteLLMClient (Secondary)
- **Complexity**: 6/10

### Task 2.4: ModelRegistry
- **Complexity**: 6/10

### Task 2.5: OpenAIClientAdapter
- **Complexity**: 6/10

### Task 2.6: AnthropicClientAdapter
- **Complexity**: 4/10 (adjusted)

### Task 2.7: GeminiClientAdapter
- **Complexity**: 7/10 (adjusted)

### Task 2.8: ProviderContractTests
- **Complexity**: 5/10

---

## Phase 3: Reliability Layer (Weeks 6-7)

### Task 3.1: AdaptiveCircuitBreaker
- **Complexity**: 8/10
- **New Features**:
  - Monotonic time (not wall clock)
  - Per-provider configuration
  - State persistence option

### Task 3.2: RetryPolicy
- **Complexity**: 3/10 (adjusted)

### Task 3.3: TimeoutPolicy
- **Complexity**: 4/10

### Task 3.4: FailoverExecutor
- **Complexity**: 8/10

### Task 3.5: ProviderHealthMonitor
- **Complexity**: 6/10

### Task 3.6: CapabilityAwareFailover (NEW)
- **Location**: `Sources/AISDK/Core/Reliability/CapabilityAwareFailover.swift`
- **Complexity**: 4/10
- **Description**: Check token limits and cost constraints before failover
```swift
public struct FailoverPolicy: Sendable {
    public let maxCostMultiplier: Double
    public let requireCapabilityMatch: Bool

    func isCompatible(request: AITextRequest, provider: ProviderClient) -> Bool
}
```

### Task 3.7: FaultInjector (moved from Phase 6)
- **Location**: `Tests/AISDKTests/Helpers/FaultInjector.swift`
- **Complexity**: 5/10

---

## Phase 4: Agent & Tools (Weeks 8-9.5)

### Task 4.1a: AIAgent Core Shell (SPLIT)
- **Location**: `Sources/AISDK/Agents/AIAgent.swift`
- **Complexity**: 4/10
- **Description**: Actor structure, state management, ObservableAgentState

```swift
public actor AIAgent {
    public nonisolated let observableState: ObservableAgentState
    private var operationQueue: [AIOperation] = []  // Reentrancy protection

    public func execute(messages: [AIMessage]) async throws -> AIAgentResult
}

@Observable
public final class ObservableAgentState: @unchecked Sendable {
    @MainActor public internal(set) var state: AgentState = .idle
    @MainActor public internal(set) var currentStep: Int = 0
}
```

### Task 4.1b: AIAgent Streaming (SPLIT)
- **Complexity**: 5/10
- **Description**: executeStream with step callbacks, bounded stream creation

### Task 4.1c: AIAgent Tool Execution (SPLIT)
- **Complexity**: 5/10
- **Description**: Tool execution loop with repair integration, per-tool timeout

### Task 4.2: StopCondition
- **Complexity**: 4/10
- **New**: `.tokenBudget(maxTokens: Int)` condition

### Task 4.3: ToolCallRepair
- **Complexity**: 8/10 (adjusted)

### Task 4.4: AITool Protocol (Redesigned)
- **Location**: `Sources/AISDK/Tools/AITool.swift`
- **Complexity**: 6/10
- **Description**: Immutable, Sendable-compliant
```swift
public protocol AITool: Sendable {
    associatedtype Arguments: Codable & Sendable
    associatedtype Metadata: ToolMetadata = EmptyMetadata

    static var name: String { get }
    static var description: String { get }
    static var timeout: TimeInterval { get }  // NEW: per-tool timeout

    static func execute(arguments: Arguments) async throws -> AIToolResult<Metadata>
}
```

### Task 4.5: AgentState Observable
- **Complexity**: 4/10
- **New**: AsyncStream<AgentState> for reactive UI

---

## Phase 5: Generative UI (Weeks 10-11)

### Task 5.1: UICatalog
- **Complexity**: 6/10
- **New**: Schema validation during decode

### Task 5.2: Core 8 Component Definitions
- **Complexity**: 5/10
- **New**: Accessibility props on all components
```swift
struct ButtonProps: Codable, Sendable {
    let title: String
    let action: String
    let accessibilityLabel: String?
    let accessibilityHint: String?
    let accessibilityTraits: [String]?
}
```

### Task 5.3: UITree Model
- **Complexity**: 6/10 (adjusted)

### Task 5.4: UIComponentRegistry
- **Complexity**: 6/10
- **New**: Action allowlisting for security

### Task 5.5: Core 8 SwiftUI Views
- **Complexity**: 6/10

### Task 5.6: GenerativeUIView
- **Complexity**: 7/10

### Task 5.7: GenerativeUIViewModel
- **Complexity**: 7/10 (adjusted)
- **New**: Update batching for jank prevention
```swift
private func scheduleUpdate(_ update: UITreeUpdate) {
    pendingUpdates.append(update)
    updateTask?.cancel()
    updateTask = Task {
        try? await Task.sleep(for: .milliseconds(16)) // 60fps
        applyBatchedUpdates()
    }
}
```

---

## Phase 6: Testing Infrastructure (Week 12)

### Task 6.1: Integration Test Suite
- **Complexity**: 6/10

### Task 6.2: UI Snapshot Tests
- **Complexity**: 5/10

### Task 6.3: ConcurrencyStressTests (NEW)
- **Location**: `Tests/AISDKTests/Stress/ConcurrencyStressTests.swift`
- **Complexity**: 5/10
- **Tests**:
  - test_100_concurrent_agent_executions
  - test_rapid_circuit_breaker_state_changes
  - test_stream_cancellation_during_tool_execution
  - test_provider_failover_under_load

### Task 6.4: MemoryLeakTests (NEW)
- **Location**: `Tests/AISDKTests/Memory/StreamMemoryTests.swift`
- **Complexity**: 4/10
- **Tests**:
  - test_stream_deallocation_after_completion
  - test_stream_deallocation_after_error
  - test_no_retain_cycles_in_step_callbacks

---

## Phase 7: Documentation (Weeks 13-14)

### Task 7.1: Update AISDK-ARCHITECTURE.md
- **Complexity**: 4/10

### Task 7.2: Write Migration Guide
- **Complexity**: 5/10
- **Includes**: Adapter usage, breaking changes, code examples

### Task 7.3: Write Tutorials (7 tutorials)
- **Complexity**: 6/10

### Task 7.4: Generate API Reference
- **Complexity**: 4/10

---

## Phase 8: Buffer & Polish (Week 15)

### Task 8.1: Address Review Findings
- **Complexity**: Variable
- **Description**: Fix issues found during development

### Task 8.2: Performance Optimization
- **Complexity**: Variable
- **Description**: Profile and optimize hot paths

### Task 8.3: Optional Telemetry Layer
- **Complexity**: 7/10
- **Status**: Implement if time permits

---

## Dependency Graph

```
Phase 0 (Adapters) ─────────────────────────────────────────┐
    │                                                        │
Phase 1 (Core + Testing Mocks) ─────────────────────────────┤
    │                                                        │
    ├──► Phase 2 (Routing) ──► Phase 3 (Reliability) ───────┤
    │                                                        │
    └──► Phase 4 (Agents) ──► Phase 5 (Generative UI) ──────┤
                                                             │
Phase 6 (Integration Tests) ◄───────────────────────────────┘
    │
    ▼
Phase 7 (Documentation) ──► Phase 8 (Buffer)
```

---

## Risk Register

| Risk | Probability | Impact | Mitigation | Owner |
|------|-------------|--------|------------|-------|
| Actor reentrancy corruption | High | Critical | Operation queue, assertions | Phase 4 |
| Memory leak in streams | Medium | High | SafeAsyncStream, leak tests | Phase 1 |
| PHI leakage in failover | Medium | Critical | Provider allowlists, audit | Phase 3 |
| Timeline overrun | Medium | Medium | 1-week buffer, parallel tasks | PM |
| Breaking changes impact | Low | High | Adapter layer (Phase 0) | Phase 0 |

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Feature parity | 100% of Vercel AI SDK 6.x core | Feature checklist |
| Reliability | 99.99% uptime | Telemetry dashboard |
| Performance | P99 < 200ms overhead | Benchmark tests |
| Test coverage | 80%+ core, 100% errors | Coverage report |
| Memory safety | 0 leaks in stress tests | Memory tests |
| Concurrency safety | 0 races in stress tests | Concurrency tests |

---

## Approval

This specification requires user approval before proceeding to implementation.

**Documents Generated**:
1. `aisdk-modernization-spec-v3-final.md` (this document)
2. `implementation-plan.md` (47 original tasks)
3. `external-review-feedback.md` (changes from review)
4. `interview-transcript.md` (stakeholder decisions)
5. `claude-research.md` (research findings)
