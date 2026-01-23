# Plan: AISDK Swift Modernization

**Generated**: 2026-01-22
**Estimated Complexity**: High
**Total Phases**: 6

## Overview
This modernization aligns AISDK with Vercel AI SDK 6.x semantics, centering the SDK on a Swift-native, composable core API (`generateText`, `streamText`, `generateObject`, `streamObject`) and a unified streaming/event model. The strategy is additive-first: introduce a new Core layer with strict typing, structured streaming events, and privacy-safe telemetry, then adapt existing providers through thin adapters. This preserves current integrations while enabling 6.x patterns such as multi-step agent loops, tool repair, and step callbacks.

Healthcare reliability drives sequencing and design. Phase 1 establishes the 6.x API surface and data contracts. Phase 2 adds model routing (OpenRouter/LiteLLM) with capability-aware selection. Phase 3 hardens reliability (failover chains, circuit breakers, timeouts, idempotency) and audit trails. Phase 4 upgrades agents and tools to deterministic, step-based execution. Phase 5 delivers generative UI for SwiftUI with a JSON-render-style schema that supports medical components. Phase 6 completes a test matrix with deterministic streaming, fault injection, provider contracts, and UI schema validation.

## Prerequisites
- Access to OpenAI, Anthropic, Gemini, OpenRouter, and LiteLLM endpoints (API keys and base URLs).
- Swift 5.9 toolchain, Xcode 15+.
- Define PHI/PII redaction policy and audit retention requirements.
- Add env vars alongside `Tests/env.example`: `OPENROUTER_API_KEY`, `LITELLM_BASE_URL`, `LITELLM_API_KEY`.
- Review Vercel AI SDK 6.x public docs/spec to confirm parity targets and naming.

## Phase 1: Foundation - Core Protocol Modernization
**Goal**: Establish the unified API surface matching Vercel AI SDK 6.x patterns

### Task 1.1: Define New Core Protocols
- **Location**: `Sources/AISDK/Core/Protocols/`
- **Description**: Create Swift equivalents of Vercel's 6.x core functions
- **Dependencies**: None
- **Complexity**: 7
- **Implementation Details**:
  - Add `AIGeneratable` with `generateText`, `streamText`, `generateObject`, `streamObject`.
  - Add `AIStreamable` returning `AsyncSequence<AIStreamEvent>`.
  - Add `AIObjectGeneratable` with `Codable` + `JSONSchemaRepresentable` bridge.
  - Mark public types as `Sendable` where safe.
- **Test-First Approach**:
  - `Tests/AISDKTests/Core/Protocols/AIGeneratableTests.swift` using mock adapters.
  - `Tests/AISDKTests/Core/Protocols/AIStreamableTests.swift` for event ordering.
- **Acceptance Criteria**:
  - Protocols compile and are implementable by existing providers.
  - Stream events are strongly typed and documented.

### Task 1.2: Introduce Unified Request/Response Models
- **Location**: `Sources/AISDK/Core/Models/`
- **Description**: Add 6.x-style request/response types with explicit usage, trace, and safety
- **Dependencies**: Task 1.1
- **Complexity**: 7
- **Implementation Details**:
  - Add `AITextRequest`, `AIObjectRequest<T>`, `AIStreamRequest`, `AIToolRequest`.
  - Define `AIResult`, `AIStreamEvent` (token/toolCall/toolResult/step/finish/error), `AIUsage`, `AISafety`, `AITraceContext`.
  - Include `requestId`, `traceId`, `provider`, `model`, and latency metrics.
- **Test-First Approach**:
  - `Tests/AISDKTests/Core/Models/AIResultTests.swift` for encode/decode.
  - `Tests/AISDKTests/Core/Models/AIStreamEventTests.swift` for event typing.
- **Acceptance Criteria**:
  - Round-trip encoding for all models.
  - Trace metadata available on all results.

### Task 1.3: Swift-Concurrency-First Streaming Pipeline
- **Location**: `Sources/AISDK/Core/Streaming/`
- **Description**: A streaming engine that maps provider streams to `AIStreamEvent`
- **Dependencies**: Task 1.2
- **Complexity**: 6
- **Implementation Details**:
  - Add `AIStreamMapper` to translate provider chunks to events.
  - Use `AsyncStream` with `@Sendable` handlers and backpressure control.
  - Avoid shared mutable state; prefer `actor` for aggregation.
- **Test-First Approach**:
  - `Tests/AISDKTests/Core/Streaming/AIStreamMapperTests.swift`.
- **Acceptance Criteria**:
  - Deterministic event ordering for text + tool calls.

### Task 1.4: Error Taxonomy + PHI-Safe Redaction
- **Location**: `Sources/AISDK/Core/Errors/`
- **Description**: Standardize errors and redact sensitive content in logs/telemetry
- **Dependencies**: Task 1.2
- **Complexity**: 8
- **Implementation Details**:
  - Add `AIError` cases for auth, rate-limit, validation, tool error, provider down.
  - Add `RedactionPolicy` and `SensitiveField` markers for headers/prompts/tool args.
  - Ensure all `CustomStringConvertible` text is redacted by default.
- **Test-First Approach**:
  - `Tests/AISDKTests/Core/Errors/AIErrorTests.swift`.
  - `Tests/AISDKTests/Core/Errors/RedactionPolicyTests.swift`.
- **Acceptance Criteria**:
  - Provider errors map to `AIError` consistently.
  - PHI is never logged by default.

### Task 1.5: Core Configuration & Dependency Injection
- **Location**: `Sources/AISDK/Core/Configuration/AISDKConfiguration.swift`
- **Description**: Central config for routing, reliability, and observability
- **Dependencies**: Tasks 1.1–1.4
- **Complexity**: 6
- **Implementation Details**:
  - Add `AISDKConfiguration` with provider registry, routing policy, reliability policy.
  - Support environment overrides and per-request overrides.
- **Test-First Approach**:
  - `Tests/AISDKTests/Core/Configuration/AISDKConfigurationTests.swift`.
- **Acceptance Criteria**:
  - All core components are configurable without singletons.

## Phase 2: Provider Abstraction & Model Routing
**Goal**: Implement model-agnostic routing with OpenRouter and LiteLLM support

### Task 2.1: Define ProviderClient Protocol
- **Location**: `Sources/AISDK/Core/Routing/ProviderClient.swift`
- **Description**: Standard interface for all providers and routers
- **Dependencies**: Phase 1
- **Complexity**: 6
- **Implementation Details**:
  - `ProviderClient` exposes `generateText`, `streamText`, `generateObject`.
  - Include capability flags, supported modalities, and tool support.
- **Test-First Approach**:
  - `Tests/AISDKTests/Routing/ProviderClientTests.swift` using mocks.
- **Acceptance Criteria**:
  - Existing providers can conform via adapters.

### Task 2.2: Implement OpenRouter Client
- **Location**: `Sources/AISDK/Core/Routing/OpenRouterClient.swift`
- **Description**: Hosted routing using OpenRouter-compatible API
- **Dependencies**: Task 2.1
- **Complexity**: 7
- **Implementation Details**:
  - Implement request/response mapping and auth headers.
  - Support model aliases, provider hints, and usage metadata.
- **Test-First Approach**:
  - `Tests/AISDKTests/Routing/OpenRouterClientTests.swift` with mock responses.
  - Integration tests gated by `OPENROUTER_API_KEY`.
- **Acceptance Criteria**:
  - `generateText` + `streamText` succeed via OpenRouter.

### Task 2.3: Implement LiteLLM Client
- **Location**: `Sources/AISDK/Core/Routing/LiteLLMClient.swift`
- **Description**: Self-hosted routing with configurable base URL
- **Dependencies**: Task 2.1
- **Complexity**: 7
- **Implementation Details**:
  - Add base URL + API key support in `AISDKConfiguration`.
  - Support routing across multiple providers + local model fallback.
- **Test-First Approach**:
  - `Tests/AISDKTests/Routing/LiteLLMClientTests.swift`.
  - Integration tests gated by `LITELLM_BASE_URL`.
- **Acceptance Criteria**:
  - Routing works for hosted and self-hosted scenarios.

### Task 2.4: Model Registry + Capability Resolution
- **Location**: `Sources/AISDK/Core/Routing/ModelRegistry.swift`
- **Description**: Capability-aware model selection aligned to 6.x
- **Dependencies**: Phase 1
- **Complexity**: 6
- **Implementation Details**:
  - Extend `LLMModelProtocol` with `aliases`, `routingHints`, `costTier`.
  - Add `ModelRegistry.resolve(request:)` based on modality/tool needs.
- **Test-First Approach**:
  - `Tests/AISDKTests/Routing/ModelRegistryTests.swift`.
- **Acceptance Criteria**:
  - Correct model selected by capabilities and constraints.

### Task 2.5: Provider Adapters for Existing Implementations
- **Location**: `Sources/AISDK/Core/Adapters/`
- **Description**: Thin adapters for OpenAI/Anthropic/Gemini to `ProviderClient`
- **Dependencies**: Tasks 2.1–2.4
- **Complexity**: 6
- **Implementation Details**:
  - Add `OpenAIClientAdapter`, `AnthropicClientAdapter`, `GeminiClientAdapter`.
  - Map their existing streaming to `AIStreamEvent`.
- **Test-First Approach**:
  - Contract tests in `Tests/AISDKTests/Providers/Contracts/ProviderContractTests.swift`.
- **Acceptance Criteria**:
  - All providers pass shared contract tests.

## Phase 3: Reliability & Failover System
**Goal**: Implement 99.9% uptime with provider fallback chains

### Task 3.1: Reliability Policy & Execution Budget
- **Location**: `Sources/AISDK/Core/Reliability/ReliabilityPolicy.swift`
- **Description**: Define retry/timeout/hedge behavior with request budgets
- **Dependencies**: Phase 2
- **Complexity**: 7
- **Implementation Details**:
  - Define `RetryPolicy`, `TimeoutPolicy`, `HedgingPolicy`, `BudgetPolicy`.
  - Add per-request overrides for clinical priority.
- **Test-First Approach**:
  - `Tests/AISDKTests/Reliability/ReliabilityPolicyTests.swift`.
- **Acceptance Criteria**:
  - Policies are deterministic and measurable.

### Task 3.2: Circuit Breaker + Provider Health Monitor
- **Location**: `Sources/AISDK/Core/Reliability/CircuitBreaker.swift`
- **Description**: Protect against cascading failures
- **Dependencies**: Task 3.1
- **Complexity**: 8
- **Implementation Details**:
  - Implement `CircuitBreaker` with half-open probing.
  - Track provider health metrics and expose status.
- **Test-First Approach**:
  - `Tests/AISDKTests/Reliability/CircuitBreakerTests.swift`.
- **Acceptance Criteria**:
  - Provider ejection and recovery works under fault injection.

### Task 3.3: Failover Chain Execution Engine
- **Location**: `Sources/AISDK/Core/Reliability/FailoverExecutor.swift`
- **Description**: Execute requests across fallback chain with consistent tracing
- **Dependencies**: Tasks 3.1–3.2
- **Complexity**: 9
- **Implementation Details**:
  - Execute fallback chain with tool-call idempotency protection.
  - Preserve `traceId` and merge usage for audit.
- **Test-First Approach**:
  - `Tests/AISDKTests/Reliability/FailoverExecutorTests.swift` with mock providers.
- **Acceptance Criteria**:
  - Failover occurs without duplicate tool execution.

### Task 3.4: Audit Logging + PHI-Safe Telemetry
- **Location**: `Sources/AISDK/Core/Observability/`
- **Description**: HIPAA-minded audit trail and event hooks
- **Dependencies**: Tasks 1.4, 3.3
- **Complexity**: 8
- **Implementation Details**:
  - Add `AIAuditEvent`, `AIEventSink`, `AITraceContext`.
  - Provide OSLog integration with redaction by default.
- **Test-First Approach**:
  - `Tests/AISDKTests/Observability/AIAuditEventTests.swift`.
- **Acceptance Criteria**:
  - All requests emit traceable, redacted audit events.

### Task 3.5: Idempotency + Tool Execution Safeguards
- **Location**: `Sources/AISDK/Core/Reliability/IdempotencyStore.swift`
- **Description**: Ensure retries/failovers do not re-run side-effecting tools
- **Dependencies**: Task 3.3
- **Complexity**: 6
- **Implementation Details**:
  - Add idempotency keys for tool calls and results.
  - Cache tool results per trace + toolCallId.
- **Test-First Approach**:
  - `Tests/AISDKTests/Reliability/IdempotencyStoreTests.swift`.
- **Acceptance Criteria**:
  - Tool execution is at-most-once per trace.

## Phase 4: Enhanced Agent & Tool Framework
**Goal**: Multi-step agents with tool call repair

### Task 4.1: Implement Step-Based Agent Loop
- **Location**: `Sources/AISDK/Agents/AgentLoop.swift`
- **Description**: 6.x-style loop with `maxSteps`, `prepareStep`, `onStepFinish`
- **Dependencies**: Phase 1
- **Complexity**: 8
- **Implementation Details**:
  - Introduce `AgentStepContext`, `AgentStepResult`, `AgentLoopConfig`.
  - Provide `@Sendable` callbacks and `AsyncSequence` for step events.
- **Test-First Approach**:
  - `Tests/AISDKTests/Agents/AgentLoopTests.swift` with deterministic steps.
- **Acceptance Criteria**:
  - Steps are bounded, cancellable, and emit completion events.

### Task 4.2: Tool Call Validation + Repair
- **Location**: `Sources/AISDK/Tools/ToolRepair.swift`
- **Description**: Schema validation and repair for tool arguments
- **Dependencies**: Task 4.1
- **Complexity**: 7
- **Implementation Details**:
  - Add `ToolRepairPolicy`, `ToolValidationError`.
  - Implement repair loop with bounded retries and structured errors.
- **Test-First Approach**:
  - `Tests/AISDKTests/Tools/ToolRepairTests.swift`.
- **Acceptance Criteria**:
  - Invalid tool args repaired or fail deterministically.

### Task 4.3: Agent Integration with New Core API
- **Location**: `Sources/AISDK/Agents/Agent.swift`
- **Description**: Backward-compatible Agent that delegates to `AgentLoop`
- **Dependencies**: Tasks 4.1–4.2
- **Complexity**: 6
- **Implementation Details**:
  - Add `Agent.generateText/streamText` wrappers.
  - Keep `send`/`sendStream` with deprecation notes.
- **Test-First Approach**:
  - Update `Tests/AISDKTests/AgentIntegrationTests.swift` for step callbacks.
- **Acceptance Criteria**:
  - Existing tests pass; new loop behavior validated.

### Task 4.4: Structured Tool Results + Metadata
- **Location**: `Sources/AISDK/Tools/Tool.swift`
- **Description**: Standardize tool outputs and metadata encoding
- **Dependencies**: Task 4.2
- **Complexity**: 5
- **Implementation Details**:
  - Introduce `ToolResult` with `content`, `metadata`, `warnings`.
  - Ensure metadata encoding uses `AnyToolMetadata` and versioned types.
- **Test-First Approach**:
  - `Tests/AISDKTests/Tools/ToolResultTests.swift`.
- **Acceptance Criteria**:
  - Tool results are serializable and safe for persistence.

### Task 4.5: Safety Guardrails for Clinical Context
- **Location**: `Sources/AISDK/Agents/SafetyGuardrails.swift`
- **Description**: Enforce safety checks on tool usage and response output
- **Dependencies**: Task 4.1
- **Complexity**: 6
- **Implementation Details**:
  - Add configurable safety rules (blocked tool categories, PHI constraints).
  - Allow per-request overrides for approved clinical workflows.
- **Test-First Approach**:
  - `Tests/AISDKTests/Agents/SafetyGuardrailsTests.swift`.
- **Acceptance Criteria**:
  - Guardrails prevent unsafe tool calls and unsafe outputs.

## Phase 5: SwiftUI Generative UI
**Goal**: Dynamic UI generation from LLM responses

### Task 5.1: Define JSON Render Schema + Registry
- **Location**: `Sources/AISDKChat/GenerativeUI/Schema/`
- **Description**: JSON-render-style schema for SwiftUI views
- **Dependencies**: Phase 4
- **Complexity**: 7
- **Implementation Details**:
  - Define `AIGenerativeNode` (type, props, children, actions).
  - Include schema versioning and fallback types.
  - Implement registry that maps node types to SwiftUI view builders.
- **Test-First Approach**:
  - `Tests/AISDKChatTests/GenerativeUI/SchemaValidationTests.swift`.
- **Acceptance Criteria**:
  - Schema validates and registry resolves view types.

### Task 5.2: SwiftUI JSON Renderer
- **Location**: `Sources/AISDKChat/GenerativeUI/Renderer/JSONRenderer.swift`
- **Description**: Render JSON nodes into SwiftUI with safe defaults
- **Dependencies**: Task 5.1
- **Complexity**: 8
- **Implementation Details**:
  - Render nodes via a registry with strict props validation.
  - Provide error placeholders for unknown components.
  - Ensure `Sendable` view models and avoid main-thread blocking.
- **Test-First Approach**:
  - `Tests/AISDKChatTests/GenerativeUI/RendererTests.swift`.
- **Acceptance Criteria**:
  - Renderer produces stable UI for valid and invalid schemas.

### Task 5.3: Medical UI Component Pack (P2)
- **Location**: `Sources/AISDKChat/GenerativeUI/Components/Medical/`
- **Description**: Vitals, labs, trends, summary cards with Charts
- **Dependencies**: Tasks 5.1–5.2
- **Complexity**: 6
- **Implementation Details**:
  - Define components with strict schemas and units.
  - Provide accessibility labels and clinical-grade formatting.
- **Test-First Approach**:
  - `Tests/AISDKChatTests/GenerativeUI/MedicalComponentTests.swift`.
- **Acceptance Criteria**:
  - Components render with sample JSON and pass validation tests.

### Task 5.4: Streaming UI Updates
- **Location**: `Sources/AISDKChat/GenerativeUI/StreamingViewRenderer.swift`
- **Description**: Render UI incrementally from `AIStreamEvent`
- **Dependencies**: Task 5.2
- **Complexity**: 7
- **Implementation Details**:
  - Map `AIStreamEvent` to partial UI state.
  - Add debounce/throttle to prevent UI churn.
- **Test-First Approach**:
  - `Tests/AISDKChatTests/GenerativeUI/StreamingRendererTests.swift`.
- **Acceptance Criteria**:
  - Streaming UI updates are stable under rapid events.

## Phase 6: Testing Infrastructure
**Goal**: Comprehensive testing with mocks and simulation

### Task 6.1: Deterministic Streaming Test Harness
- **Location**: `Tests/AISDKTests/Streaming/`
- **Description**: Simulate streams with deterministic timing
- **Dependencies**: Phase 1
- **Complexity**: 6
- **Implementation Details**:
  - Add `StreamTestScheduler` and `MockStreamSequence`.
  - Provide helpers for `AIStreamEvent` sequences.
- **Test-First Approach**:
  - Use harness to test `AIStreamEvent` ordering and buffering.
- **Acceptance Criteria**:
  - Streaming tests pass without flakiness.

### Task 6.2: Fault Injection + Chaos Tests
- **Location**: `Tests/AISDKTests/Reliability/`
- **Description**: Validate failover, retry, and circuit breaker behavior
- **Dependencies**: Phase 3
- **Complexity**: 8
- **Implementation Details**:
  - Add `FlakyProviderMock` with configurable error rates and latency.
  - Simulate partial tool failures and timeouts.
- **Test-First Approach**:
  - `Tests/AISDKTests/Reliability/FailoverChaosTests.swift`.
- **Acceptance Criteria**:
  - Reliability policies withstand randomized failures.

### Task 6.3: Provider Contract Tests
- **Location**: `Tests/AISDKTests/Providers/Contracts/`
- **Description**: Ensure provider adapters follow 6.x core semantics
- **Dependencies**: Phases 1–2
- **Complexity**: 5
- **Implementation Details**:
  - Shared contract tests for `generateText`, `streamText`, `generateObject`.
  - Gated integration tests per provider key.
- **Test-First Approach**:
  - `ProviderContractTests.swift` with optional env gating.
- **Acceptance Criteria**:
  - Each provider passes contract tests for required features.

### Task 6.4: UI Schema + Renderer Tests
- **Location**: `Tests/AISDKChatTests/GenerativeUI/`
- **Description**: Validate schema parsing, rendering stability, and error fallback
- **Dependencies**: Phase 5
- **Complexity**: 5
- **Implementation Details**:
  - Test invalid schema fallback and error placeholders.
  - Validate medical component JSON schemas.
- **Test-First Approach**:
  - `RendererErrorHandlingTests.swift`.
- **Acceptance Criteria**:
  - UI generation is deterministic and fails safely.

## Testing Strategy

### Unit Tests
- Mock providers for deterministic testing
- Stream simulation helpers
- Schema validation tests

### Integration Tests
- Real API tests with environment variables
- Provider switching tests
- Failover chain tests

### E2E Tests
- Full conversation flows
- Tool execution chains
- Streaming UI updates

### Test Coverage Goals
- 80% coverage on core protocols
- 100% coverage on error handling paths
- All public APIs have at least one test

## Dependency Graph
- Phase 1 must complete before Phase 2–4
- Phase 2 and 3 can run in parallel
- Phase 4 depends on Phase 1
- Phase 5 depends on Phase 4
- Phase 6 can run in parallel with all phases

## Migration Guide
- Deprecate existing `Agent.send`/`sendStream` in favor of `generateText`/`streamText` wrappers.
- Provide compatibility layer: `Agent` conforms to `AIGeneratable` and `AIStreamable`.
- Example migration:
  - Old: `try await agent.send("Hello")`
  - New: `try await agent.generateText(.init(messages: [.user("Hello")]))`
- Add `docs/Upgrade-Guide-6x.md` with breaking change list.

## Potential Risks
- Provider feature mismatch across OpenAI/Anthropic/Gemini/OpenRouter/LiteLLM.
- Added latency from failover policies if misconfigured.
- Tool repair loops causing extra tokens or unintended side effects.
- UI generation safety and PHI exposure via logs/telemetry.

## Rollback Plan
- Feature-flag the 6.x core API (e.g., `AISDKConfiguration.enable6x`).
- Keep legacy `LLM` protocol and `Agent` methods until v1.1.x stabilization.
- Roll back by switching configuration to legacy pipeline and disabling routing.
