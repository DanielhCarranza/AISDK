# AISDK 2.0 Product Requirements Document

**Document Version**: 1.0
**Date**: 2026-01-22
**Status**: Approved
**Owner**: Engineering

---

## 1. Executive Summary

### 1.1 Product Vision

AISDK 2.0 modernizes the existing Swift AI SDK to achieve feature parity with Vercel AI SDK 6.x while maintaining healthcare-grade reliability (99.99% uptime) for the AI doctor application.

### 1.2 Problem Statement

The current AISDK has several limitations:
- Lacks unified streaming API across providers
- No built-in failover or circuit breaking
- Legacy Tool protocol incompatible with Swift concurrency
- No generative UI capabilities
- Insufficient test coverage for production healthcare use

### 1.3 Solution Overview

A comprehensive modernization delivering:
- Unified `AILanguageModel` protocol with streaming support
- Multi-provider routing via OpenRouter/LiteLLM
- Actor-based agents with observable state
- Generative UI using json-render pattern
- Healthcare-grade reliability layer

---

## 2. Goals and Success Metrics

### 2.1 Primary Goals

| Goal | Metric | Target |
|------|--------|--------|
| Feature Parity | Vercel AI SDK 6.x core features | 100% |
| Reliability | Uptime | 99.99% |
| Performance | P99 latency overhead | < 200ms |
| Quality | Test coverage (core) | 80%+ |
| Safety | Memory leaks in stress tests | 0 |
| Safety | Race conditions in stress tests | 0 |

### 2.2 Non-Goals

- Server-side rendering (iOS/macOS only)
- Database/persistence layer
- User authentication
- Analytics dashboard UI
- Custom model training

---

## 3. User Stories

### 3.1 Developer Personas

**Primary**: iOS/macOS developers integrating AI into healthcare apps
**Secondary**: SDK maintainers and contributors

### 3.2 Core User Stories

#### US-1: Basic Text Generation
```
As a developer,
I want to generate text from a language model,
So that I can provide AI-powered responses in my app.
```
**Acceptance Criteria**:
- Single method call: `model.generateText(request:)`
- Returns structured result with text, usage, finish reason
- Works with any provider conforming to `AILanguageModel`

#### US-2: Streaming Responses
```
As a developer,
I want to stream text generation in real-time,
So that users see responses as they're generated.
```
**Acceptance Criteria**:
- Returns `AsyncThrowingStream<AIStreamEvent, Error>`
- Emits 14 event types (textDelta, toolCallStart, etc.)
- Supports cancellation without memory leaks
- Bounded buffer (1000 events) prevents OOM

#### US-3: AITool Calling
```
As a developer,
I want to define tools that the AI can invoke,
So that the AI can perform actions and retrieve data.
```
**Acceptance Criteria**:
- Define tools via `AITool` protocol
- Automatic JSON schema generation from `Arguments` type
- Type-safe execution with `Codable` arguments
- Per-tool timeout configuration

#### US-4: Multi-Step Agent
```
As a developer,
I want an agent that can plan and execute multi-step tasks,
So that complex queries are handled automatically.
```
**Acceptance Criteria**:
- Actor-based `AIAgent` with configurable stop conditions
- Observable state for SwiftUI binding
- Step callbacks for monitoring/intervention
- Tool call repair for malformed arguments

#### US-5: Failover Reliability
```
As a developer,
I want automatic failover between providers,
So that my app remains available during provider outages.
```
**Acceptance Criteria**:
- Automatic failover chain execution
- Circuit breaker prevents cascading failures
- Capability-aware provider selection
- Cost-tier constraints prevent billing spikes
- PHI protection via provider allowlists

#### US-6: Generative UI
```
As a developer,
I want the AI to generate dynamic UI components,
So that responses can include interactive elements.
```
**Acceptance Criteria**:
- 8 core components: Text, Button, Card, Input, List, Image, Stack, Spacer
- JSON-based UI tree specification
- Progressive rendering during streaming
- Custom component registration
- Action handling with security allowlisting

#### US-7: Migration Path
```
As a developer with existing AISDK 1.x integration,
I want adapters for gradual migration,
So that I can adopt AISDK 2.0 incrementally.
```
**Acceptance Criteria**:
- `AILanguageModelAdapter` wraps legacy `LLM` protocol
- `AIAgentAdapter` wraps legacy `Agent` class
- Tools migrate directly to `AITool` (no adapter layer)
- No breaking changes required for initial adoption

---

## 4. Functional Requirements

### 4.1 Core Protocol Layer

#### FR-1.1: AILanguageModel Protocol
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

#### FR-1.2: AIStreamEvent (14 Events)
| Event | Description |
|-------|-------------|
| textDelta | Incremental text chunk |
| textCompletion | Full accumulated text |
| toolCallStart | Tool invocation begins |
| toolCallDelta | Tool arguments streaming |
| toolCallFinish | Tool invocation complete |
| toolResult | Tool execution result |
| stepStart | Agent step begins |
| stepFinish | Agent step complete |
| finish | Generation complete |
| error | Error occurred |
| reasoningStart | Chain-of-thought begins |
| reasoningDelta | Reasoning text chunk |
| reasoningFinish | Reasoning complete |
| heartbeat | Connection alive signal |

#### FR-1.3: AITextRequest
| Field | Type | Required | Description |
|-------|------|----------|-------------|
| messages | [AIMessage] | Yes | Conversation history |
| model | String? | No | Model override |
| temperature | Double? | No | Randomness (0-2) |
| maxTokens | Int? | No | Token limit |
| tools | [any AITool.Type]? | No | Available tools |
| toolChoice | ToolChoice? | No | Tool selection mode |
| allowedProviders | Set<String>? | No | PHI-safe providers |
| sensitivity | DataSensitivity | No | Data classification |
| bufferPolicy | StreamBufferPolicy? | No | Memory control |

### 4.2 Provider Layer

#### FR-2.1: OpenRouterClient
- Primary routing provider
- Model aliases (gpt-5-mini → openai/gpt-5-mini)
- Provider preference hints
- Usage metadata extraction
- SSE streaming support

#### FR-2.2: LiteLLMClient
- Secondary/self-hosted provider
- OpenAI-compatible API
- Custom base URL configuration
- Health monitoring integration

#### FR-2.3: Provider Adapters
- OpenAIClientAdapter
- AnthropicClientAdapter
- GeminiClientAdapter

### 4.3 Reliability Layer

#### FR-3.1: AdaptiveCircuitBreaker
| State | Behavior |
|-------|----------|
| Closed | Requests pass through |
| Open | Requests fail fast |
| Half-Open | Limited test requests |

Error-type-aware thresholds:
- Authentication: 1 failure = immediate open
- Rate limit: 3 failures
- Timeout/Network: 5 failures

#### FR-3.2: FailoverExecutor
- Ordered provider chain
- Circuit breaker per provider
- Capability matching (token limits)
- Cost constraint enforcement
- PHI provider filtering

#### FR-3.3: RetryPolicy
| Strategy | Use Case |
|----------|----------|
| None | No retries |
| Immediate | Quick retry |
| Exponential | Backoff with jitter |
| RateLimitAware | Respect Retry-After |

### 4.4 Agent Layer

#### FR-4.1: AIAgent Actor
```swift
public actor AIAgent {
    // Observable state for SwiftUI
    public nonisolated let observableState: ObservableAgentState

    // Synchronous execution
    public func execute(messages: [AIMessage]) async throws -> AIAgentResult

    // Streaming execution with callbacks
    public func executeStream(
        messages: [AIMessage],
        onStepFinish: @escaping (AIStepResult) async -> StepAction,
        prepareStep: @escaping (Int, [AIMessage]) async -> StepPreparation
    ) -> AsyncThrowingStream<AIStreamEvent, Error>
}
```

#### FR-4.2: StopCondition
| Condition | Description |
|-----------|-------------|
| stepCount(Int) | Max iterations |
| tokenBudget(Int) | Max total tokens |
| custom((AIStepResult) -> Bool) | Custom predicate |

#### FR-4.3: AITool Protocol
```swift
public protocol AITool: Sendable {
    var name: String { get }
    var description: String { get }
    var returnToolResponse: Bool { get }

    init()
    static func jsonSchema() -> ToolSchema
    static func validate(arguments: [String: Any]) throws
    mutating func setParameters(from arguments: [String: Any]) throws
    mutating func validateAndSetParameters(_ argumentsData: Data) throws -> Self

    func execute() async throws -> AIToolResult
}
```

### 4.5 Generative UI Layer

#### FR-5.1: Core 8 Components
| Component | Props |
|-----------|-------|
| Text | content, style, accessibilityLabel |
| Button | title, action, disabled, accessibilityLabel |
| Card | title, children, style |
| Input | placeholder, value, onChange |
| List | items, renderItem |
| Image | source, alt, size |
| Stack | direction, spacing, children |
| Spacer | size |

#### FR-5.2: UITree Model
```swift
public struct UITree: Codable, Sendable, Equatable {
    public let root: String
    public let elements: [String: UIElement]
}

public struct UIElement: Codable, Sendable, Equatable {
    public let key: String
    public let type: String
    public let props: [String: AnyCodable]
    public let children: [String]?
    public let visible: VisibilityCondition?
}
```

#### FR-5.3: GenerativeUIView
- SwiftUI view for rendering UITree
- Action handler delegation
- Custom component registration
- Accessibility support

---

## 5. Non-Functional Requirements

### 5.1 Performance

| Metric | Requirement |
|--------|-------------|
| SDK initialization | < 100ms |
| Request overhead | < 50ms |
| P99 end-to-end | < 200ms (excluding model latency) |
| Memory per stream | < 10MB |

### 5.2 Reliability

| Metric | Requirement |
|--------|-------------|
| Uptime | 99.99% |
| Failover time | < 2s |
| Circuit breaker recovery | Adaptive (30s-5min) |

### 5.3 Security

| Requirement | Implementation |
|-------------|----------------|
| PHI protection | Provider allowlists, sensitivity classification |
| API key security | Keychain storage recommended |
| Error redaction | PHI stripped from error messages |
| Audit logging | AISDKObserver hooks |

### 5.4 Compatibility

| Platform | Minimum Version |
|----------|-----------------|
| iOS | 17.0 |
| macOS | 14.0 |
| Swift | 5.9 |
| Xcode | 15.0 |

---

## 6. Technical Architecture

### 6.1 Module Structure

```
AISDK/
├── Core/           # Protocols, models, errors, configuration
├── Providers/      # OpenRouter, LiteLLM, adapters
├── Agents/         # AIAgent, stop conditions
├── Tools/          # AITool protocol, repair
├── Reliability/    # Circuit breaker, failover
├── GenerativeUI/   # Components, rendering
└── Telemetry/      # Observer protocol
```

### 6.2 Dependency Graph

```
Core → Providers → Reliability → Agents → GenerativeUI
         ↓
       Tools
```

### 6.3 Concurrency Model

- All public APIs are actor-isolated or Sendable
- AsyncThrowingStream for all streaming operations
- ObservableAgentState bridges actors to SwiftUI
- SafeAsyncStream utility prevents memory leaks

---

## 7. Testing Strategy

### 7.1 Test Pyramid

| Level | Coverage Target | Tools |
|-------|-----------------|-------|
| Unit | 80%+ | XCTest, MockAILanguageModel |
| Integration | Key paths | Real API (CI only) |
| Stress | 100 concurrent | TaskGroup |
| Memory | 0 leaks | weak refs, autoreleasepool |
| Snapshot | UI components | SnapshotTesting |

### 7.2 CI Pipeline

```yaml
jobs:
  unit-tests:     swift test --filter "^(?!.*Integration).*$"
  integration:    swift test --filter "Integration"  # API key required
  stress:         swift test --filter "Stress"
  memory:         swift test --filter "Memory"
```

---

## 8. Release Plan

### 8.1 Milestones

| Week | Phase | Deliverables |
|------|-------|--------------|
| 1 | Phase 0 | Adapter layer for migration |
| 2-3 | Phase 1 | Core protocols, models, testing infrastructure |
| 4-5 | Phase 2 | Provider clients, routing |
| 6-7 | Phase 3 | Reliability layer |
| 8-9.5 | Phase 4 | Agent and tool system |
| 10-11 | Phase 5 | Generative UI |
| 12 | Phase 6 | Integration and stress tests |
| 13-14 | Phase 7 | Documentation and tutorials |
| 15 | Phase 8 | Buffer, polish, release |

### 8.2 Release Criteria

- [ ] All 53 tasks complete
- [ ] `swift test` passes (0 failures)
- [ ] Integration tests pass with real API
- [ ] Memory tests show 0 leaks
- [ ] Stress tests show 0 races
- [ ] Documentation complete
- [ ] Migration guide verified
- [ ] Example app working

---

## 9. Risks and Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Actor reentrancy | High | Critical | Operation queue pattern |
| Memory leaks | Medium | High | SafeAsyncStream, leak tests |
| PHI leakage | Medium | Critical | Provider allowlists |
| Timeline overrun | Medium | Medium | 1-week buffer |
| Breaking changes | Low | High | Adapter layer |

---

## 10. Appendix

### 10.1 Related Documents

- `aisdk-modernization-spec-v3-final.md` - Technical specification
- `implementation-plan.md` - Detailed task breakdown
- `external-review-feedback.md` - Review findings
- `interview-transcript.md` - Stakeholder decisions
- `sections/*.md` - Phase implementation guides
- `ralph-loop-prompt.md` - Autonomous implementation guide

### 10.2 Glossary

| Term | Definition |
|------|------------|
| PHI | Protected Health Information (HIPAA) |
| Circuit Breaker | Pattern to prevent cascading failures |
| Failover | Automatic switch to backup provider |
| Generative UI | AI-generated user interface components |
| json-render | Vercel pattern for streaming UI |

### 10.3 Approval

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Product Owner | | | |
| Tech Lead | | | |
| Engineering | | | |
