# AISDK Modernization - Detailed Implementation Plan

**Generated**: 2026-01-22
**Based On**: aisdk-modernization-spec-v2.md
**Total Tasks**: 47
**Estimated Duration**: 13 weeks

---

## Phase 1: Core Protocol Layer

**Goal**: Establish unified API surface matching Vercel AI SDK 6.x
**Duration**: 2 weeks
**Dependencies**: None

### Task 1.1: Define AILanguageModel Protocol

- **Location**: `Sources/AISDK/Core/Protocols/AILanguageModel.swift`
- **Dependencies**: None
- **Complexity**: 6/10
- **Description**: Core protocol defining language model interface with actor isolation

**Implementation**:
```swift
// Create new file with:
// - AILanguageModel protocol (actor, Sendable)
// - generateText, streamText, generateObject, streamObject methods
// - provider, modelId, capabilities properties
```

**Test-First**:
```
Tests/AISDKTests/Core/Protocols/AILanguageModelTests.swift
- test_protocol_conformance_compiles
- test_mock_implementation_works
- test_sendable_requirements_met
```

**Acceptance Criteria**:
- [ ] Protocol compiles with actor isolation
- [ ] Mock implementation passes all tests
- [ ] All types are Sendable

---

### Task 1.2: Define AIStreamEvent Enum

- **Location**: `Sources/AISDK/Core/Models/AIStreamEvent.swift`
- **Dependencies**: None
- **Complexity**: 5/10
- **Description**: Full 10+ event model matching Vercel AI SDK 6.x

**Implementation**:
```swift
// Create enum with cases:
// - textDelta, textCompletion
// - toolCallStart, toolCallDelta, toolCallFinish, toolResult
// - stepStart, stepFinish
// - finish, error
// - reasoningStart, reasoningDelta, reasoningFinish
```

**Test-First**:
```
Tests/AISDKTests/Core/Models/AIStreamEventTests.swift
- test_all_events_are_codable
- test_all_events_are_sendable
- test_event_encoding_decoding_roundtrip
- test_event_equality
```

**Acceptance Criteria**:
- [ ] All 10+ event types defined
- [ ] Codable conformance for all events
- [ ] Sendable conformance

---

### Task 1.3: Define AITextRequest and AITextResult

- **Location**: `Sources/AISDK/Core/Models/AITextRequest.swift`
- **Location**: `Sources/AISDK/Core/Models/AITextResult.swift`
- **Dependencies**: Task 1.2
- **Complexity**: 5/10
- **Description**: Request and response models for text generation

**Implementation**:
```swift
// AITextRequest: messages, model, temperature, maxTokens, tools, instructions, etc.
// AITextResult: text, toolCalls, toolResults, finishReason, usage, traceContext, latency
```

**Test-First**:
```
Tests/AISDKTests/Core/Models/AITextRequestTests.swift
Tests/AISDKTests/Core/Models/AITextResultTests.swift
- test_request_encoding
- test_result_decoding
- test_optional_fields_handled
- test_trace_context_preserved
```

**Acceptance Criteria**:
- [ ] All fields from spec implemented
- [ ] Codable round-trip works
- [ ] Optional fields handled correctly

---

### Task 1.4: Define AIObjectRequest and AIObjectResult

- **Location**: `Sources/AISDK/Core/Models/AIObjectRequest.swift`
- **Location**: `Sources/AISDK/Core/Models/AIObjectResult.swift`
- **Dependencies**: Task 1.2
- **Complexity**: 6/10
- **Description**: Generic request/response for structured output

**Implementation**:
```swift
// AIObjectRequest<T: Codable>: messages, model, schema type, etc.
// AIObjectResult<T: Codable>: object, partialObject, finishReason, usage
```

**Test-First**:
```
Tests/AISDKTests/Core/Models/AIObjectRequestTests.swift
Tests/AISDKTests/Core/Models/AIObjectResultTests.swift
- test_generic_type_encoding
- test_schema_generation_from_type
- test_partial_object_handling
```

**Acceptance Criteria**:
- [ ] Generic type parameter works
- [ ] JSON schema auto-generated from Codable type
- [ ] Partial object streaming supported

---

### Task 1.5: Define AIStepResult

- **Location**: `Sources/AISDK/Core/Models/AIStepResult.swift`
- **Dependencies**: Tasks 1.2, 1.3
- **Complexity**: 4/10
- **Description**: Step result for multi-step agent loops

**Test-First**:
```
Tests/AISDKTests/Core/Models/AIStepResultTests.swift
- test_step_result_encoding
- test_step_index_tracking
- test_tool_results_included
```

**Acceptance Criteria**:
- [ ] Step index tracked correctly
- [ ] Tool calls and results preserved
- [ ] Usage aggregated per step

---

### Task 1.6: Define AIUsage and AIFinishReason

- **Location**: `Sources/AISDK/Core/Models/AIUsage.swift`
- **Location**: `Sources/AISDK/Core/Models/AIFinishReason.swift`
- **Dependencies**: None
- **Complexity**: 3/10
- **Description**: Usage tracking and finish reason enum

**Test-First**:
```
Tests/AISDKTests/Core/Models/AIUsageTests.swift
- test_usage_encoding
- test_finish_reason_raw_values
- test_cached_tokens_optional
```

**Acceptance Criteria**:
- [ ] All token types tracked
- [ ] Finish reasons match Vercel spec
- [ ] Optional fields handled

---

### Task 1.7: Define AIError Taxonomy

- **Location**: `Sources/AISDK/Core/Errors/AIError.swift`
- **Dependencies**: None
- **Complexity**: 6/10
- **Description**: Comprehensive error types with PHI-safe redaction

**Implementation**:
```swift
// Error cases: authentication, rateLimit, contextLength, validation,
// toolExecution, providerUnavailable, network, timeout, cancelled
// Include redaction policy for sensitive data
```

**Test-First**:
```
Tests/AISDKTests/Core/Errors/AIErrorTests.swift
- test_error_mapping_from_http_status
- test_error_localized_description
- test_phi_redaction_in_description
- test_error_recovery_suggestions
```

**Acceptance Criteria**:
- [ ] All error cases from spec defined
- [ ] PHI never appears in error descriptions
- [ ] HTTP status codes map correctly

---

### Task 1.8: Define AITraceContext

- **Location**: `Sources/AISDK/Core/Models/AITraceContext.swift`
- **Dependencies**: None
- **Complexity**: 4/10
- **Description**: Request tracing for debugging and observability

**Test-First**:
```
Tests/AISDKTests/Core/Models/AITraceContextTests.swift
- test_trace_id_generation
- test_parent_span_linking
- test_context_propagation
```

**Acceptance Criteria**:
- [ ] Unique trace IDs generated
- [ ] Parent-child span linking works
- [ ] Context flows through all operations

---

### Task 1.9: Define AISDKConfiguration

- **Location**: `Sources/AISDK/Core/Configuration/AISDKConfiguration.swift`
- **Dependencies**: Tasks 1.1-1.8
- **Complexity**: 6/10
- **Description**: Central configuration with DI support

**Implementation**:
```swift
// Configuration for: providers, routing, reliability, telemetry
// Support environment variables and per-request overrides
```

**Test-First**:
```
Tests/AISDKTests/Core/Configuration/AISDKConfigurationTests.swift
- test_default_configuration
- test_environment_variable_override
- test_per_request_override
- test_provider_registry
```

**Acceptance Criteria**:
- [ ] All configuration options exposed
- [ ] Environment variables work
- [ ] No singletons required

---

## Phase 2: Provider & Routing Layer

**Goal**: Model-agnostic routing with OpenRouter and LiteLLM
**Duration**: 2 weeks
**Dependencies**: Phase 1

### Task 2.1: Define ProviderClient Protocol

- **Location**: `Sources/AISDK/Core/Routing/ProviderClient.swift`
- **Dependencies**: Phase 1
- **Complexity**: 5/10
- **Description**: Standard interface for all providers

**Test-First**:
```
Tests/AISDKTests/Routing/ProviderClientTests.swift
- test_protocol_conformance
- test_capability_flags
- test_supported_models_list
```

**Acceptance Criteria**:
- [ ] Protocol defined with actor isolation
- [ ] Existing providers can conform via adapters

---

### Task 2.2: Implement OpenRouterClient

- **Location**: `Sources/AISDK/Core/Routing/OpenRouterClient.swift`
- **Dependencies**: Task 2.1
- **Complexity**: 7/10
- **Description**: Primary routing via OpenRouter API

**Implementation**:
- Model alias support (gpt-5 -> openai/gpt-5)
- Provider hints
- Usage metadata extraction
- Streaming with AIStreamEvent mapping

**Test-First**:
```
Tests/AISDKTests/Routing/OpenRouterClientTests.swift
- test_generate_text_success (mock)
- test_stream_text_events (mock)
- test_model_alias_resolution
- test_auth_header_included

Tests/AISDKTests/Routing/OpenRouterIntegrationTests.swift (gated by API key)
- test_real_api_generate_text
- test_real_api_stream_text
```

**Acceptance Criteria**:
- [ ] generateText and streamText work
- [ ] Model aliases resolve correctly
- [ ] Real API integration passes

---

### Task 2.3: Implement LiteLLMClient

- **Location**: `Sources/AISDK/Core/Routing/LiteLLMClient.swift`
- **Dependencies**: Task 2.1
- **Complexity**: 6/10
- **Description**: Self-hosted routing via LiteLLM

**Implementation**:
- Configurable base URL
- Optional API key
- Same interface as OpenRouterClient

**Test-First**:
```
Tests/AISDKTests/Routing/LiteLLMClientTests.swift
- test_custom_base_url
- test_generate_text_success (mock)
- test_stream_text_events (mock)
```

**Acceptance Criteria**:
- [ ] Custom base URL works
- [ ] Same interface as OpenRouter
- [ ] Mocked tests pass

---

### Task 2.4: Implement ModelRegistry

- **Location**: `Sources/AISDK/Core/Routing/ModelRegistry.swift`
- **Dependencies**: Phase 1
- **Complexity**: 6/10
- **Description**: Capability-aware model selection

**Implementation**:
- Extend existing LLMModelProtocol
- Add resolve(request:) method
- Filter by capabilities, cost tier, latency tier

**Test-First**:
```
Tests/AISDKTests/Routing/ModelRegistryTests.swift
- test_resolve_by_capability
- test_resolve_prefers_lower_cost
- test_resolve_with_provider_hint
- test_models_matching_capabilities
```

**Acceptance Criteria**:
- [ ] Correct model selected by capabilities
- [ ] Cost/latency preferences respected
- [ ] Provider hints work

---

### Task 2.5: OpenAI Provider Adapter

- **Location**: `Sources/AISDK/Core/Adapters/OpenAIClientAdapter.swift`
- **Dependencies**: Tasks 2.1, Phase 1
- **Complexity**: 6/10
- **Description**: Adapt existing OpenAIProvider to ProviderClient

**Implementation**:
- Wrap existing OpenAIProvider
- Map ChatCompletionChunk to AIStreamEvent
- Expose capabilities from LLMModelProtocol

**Test-First**:
```
Tests/AISDKTests/Adapters/OpenAIClientAdapterTests.swift
- test_generate_text_maps_correctly
- test_stream_events_mapped
- test_tool_calls_handled
```

**Acceptance Criteria**:
- [ ] Existing provider wrapped successfully
- [ ] Stream events map to AIStreamEvent
- [ ] All existing functionality preserved

---

### Task 2.6: Anthropic Provider Adapter

- **Location**: `Sources/AISDK/Core/Adapters/AnthropicClientAdapter.swift`
- **Dependencies**: Tasks 2.1, Phase 1
- **Complexity**: 5/10
- **Description**: Adapt existing AnthropicProvider to ProviderClient

**Test-First**:
```
Tests/AISDKTests/Adapters/AnthropicClientAdapterTests.swift
- test_generate_text_maps_correctly
- test_claude_constraints_enforced
```

**Acceptance Criteria**:
- [ ] Claude constraints preserved (n=1, temp <= 1.0)
- [ ] Stream events mapped correctly

---

### Task 2.7: Gemini Provider Adapter

- **Location**: `Sources/AISDK/Core/Adapters/GeminiClientAdapter.swift`
- **Dependencies**: Tasks 2.1, Phase 1
- **Complexity**: 6/10
- **Description**: Adapt existing GeminiProvider to ProviderClient

**Implementation**:
- Fix return type inconsistency (AsyncCompactMapSequence -> AsyncThrowingStream)
- Map Gemini events to AIStreamEvent

**Test-First**:
```
Tests/AISDKTests/Adapters/GeminiClientAdapterTests.swift
- test_stream_type_is_correct
- test_events_mapped_correctly
```

**Acceptance Criteria**:
- [ ] Return type matches protocol
- [ ] Streaming works correctly

---

### Task 2.8: Provider Contract Tests

- **Location**: `Tests/AISDKTests/Providers/Contracts/ProviderContractTests.swift`
- **Dependencies**: Tasks 2.5-2.7
- **Complexity**: 5/10
- **Description**: Shared tests all providers must pass

**Implementation**:
- Define ProviderContractTests protocol
- Test basic generate, stream, error handling
- Run against all adapters

**Acceptance Criteria**:
- [ ] All adapters pass contract tests
- [ ] Error mapping consistent

---

## Phase 3: Reliability Layer

**Goal**: 99.99% uptime with failover chains
**Duration**: 2 weeks
**Dependencies**: Phase 2

### Task 3.1: Implement AdaptiveCircuitBreaker

- **Location**: `Sources/AISDK/Core/Reliability/AdaptiveCircuitBreaker.swift`
- **Dependencies**: Phase 1
- **Complexity**: 8/10
- **Description**: Smart circuit breaker with error-type awareness

**Implementation**:
- State machine: closed -> open -> halfOpen -> closed
- Different thresholds by error type
- Exponential backoff with jitter
- Health probing in half-open state

**Test-First**:
```
Tests/AISDKTests/Reliability/AdaptiveCircuitBreakerTests.swift
- test_opens_after_threshold
- test_auth_error_opens_immediately
- test_rate_limit_has_lower_threshold
- test_half_open_probing
- test_exponential_backoff
- test_jitter_applied
```

**Acceptance Criteria**:
- [ ] State transitions work correctly
- [ ] Error-type awareness implemented
- [ ] Backoff with jitter works

---

### Task 3.2: Implement RetryPolicy

- **Location**: `Sources/AISDK/Core/Reliability/RetryPolicy.swift`
- **Dependencies**: Task 3.1
- **Complexity**: 5/10
- **Description**: Configurable retry behavior

**Implementation**:
- Max retries, initial delay, max delay
- Jitter factor
- Retryable error detection

**Test-First**:
```
Tests/AISDKTests/Reliability/RetryPolicyTests.swift
- test_retry_on_transient_error
- test_no_retry_on_auth_error
- test_backoff_calculation
- test_max_retries_respected
```

**Acceptance Criteria**:
- [ ] Retries work correctly
- [ ] Non-retryable errors fail fast

---

### Task 3.3: Implement TimeoutPolicy

- **Location**: `Sources/AISDK/Core/Reliability/TimeoutPolicy.swift`
- **Dependencies**: None
- **Complexity**: 4/10
- **Description**: Request timeout configuration

**Test-First**:
```
Tests/AISDKTests/Reliability/TimeoutPolicyTests.swift
- test_timeout_triggers_cancellation
- test_per_request_override
```

**Acceptance Criteria**:
- [ ] Timeouts enforced correctly
- [ ] Per-request overrides work

---

### Task 3.4: Implement FailoverExecutor

- **Location**: `Sources/AISDK/Core/Reliability/FailoverExecutor.swift`
- **Dependencies**: Tasks 3.1-3.3, Phase 2
- **Complexity**: 8/10
- **Description**: Execute requests across fallback chain

**Implementation**:
- Ordered provider chain
- Circuit breaker per provider
- Skip unhealthy providers
- Trace context for debugging

**Test-First**:
```
Tests/AISDKTests/Reliability/FailoverExecutorTests.swift
- test_executes_on_first_provider
- test_failover_to_second_provider
- test_skips_open_circuit_breaker
- test_all_providers_fail
- test_trace_context_preserved
```

**Acceptance Criteria**:
- [ ] Failover chain works
- [ ] Circuit breakers respected
- [ ] Tracing works

---

### Task 3.5: Implement ProviderHealthMonitor

- **Location**: `Sources/AISDK/Core/Reliability/ProviderHealthMonitor.swift`
- **Dependencies**: Task 3.1
- **Complexity**: 6/10
- **Description**: Proactive health checking

**Implementation**:
- Periodic health checks
- Latency percentile tracking
- Error rate calculation

**Test-First**:
```
Tests/AISDKTests/Reliability/ProviderHealthMonitorTests.swift
- test_health_status_updated
- test_latency_percentiles
- test_error_rate_calculation
```

**Acceptance Criteria**:
- [ ] Health status accurate
- [ ] Metrics calculated correctly

---

## Phase 4: Agent & Tools

**Goal**: Multi-step agents with tool call repair
**Duration**: 2 weeks
**Dependencies**: Phases 1-3

### Task 4.1: Implement AIAgent Actor

- **Location**: `Sources/AISDK/Agents/AIAgent.swift`
- **Dependencies**: Phases 1-3
- **Complexity**: 9/10
- **Description**: Full actor-based agent with multi-step support

**Implementation**:
- Actor for thread safety
- Execute and executeStream methods
- Step callbacks (onStepFinish, prepareStep)
- Stop conditions

**Test-First**:
```
Tests/AISDKTests/Agents/AIAgentTests.swift
- test_simple_text_response
- test_tool_execution_loop
- test_max_steps_respected
- test_on_step_finish_called
- test_prepare_step_modifies_request
- test_concurrent_access_safe
```

**Acceptance Criteria**:
- [ ] Actor isolation works
- [ ] Multi-step loop correct
- [ ] Callbacks invoked properly

---

### Task 4.2: Implement StopCondition

- **Location**: `Sources/AISDK/Agents/StopCondition.swift`
- **Dependencies**: Task 4.1
- **Complexity**: 4/10
- **Description**: Configurable stop conditions for agent loop

**Test-First**:
```
Tests/AISDKTests/Agents/StopConditionTests.swift
- test_step_count_stops_at_limit
- test_no_tool_calls_stops
- test_custom_condition_evaluated
```

**Acceptance Criteria**:
- [ ] All stop conditions work
- [ ] Custom conditions supported

---

### Task 4.3: Implement ToolCallRepair

- **Location**: `Sources/AISDK/Tools/ToolCallRepair.swift`
- **Dependencies**: Task 4.1
- **Complexity**: 7/10
- **Description**: Hybrid auto-repair for failed tool calls

**Implementation**:
- Detect tool validation failures
- Send error context to model
- Retry once with repaired arguments
- Fail with detailed error if still invalid

**Test-First**:
```
Tests/AISDKTests/Tools/ToolCallRepairTests.swift
- test_repair_fixes_invalid_arguments
- test_fails_after_one_repair_attempt
- test_strict_mode_fails_immediately
- test_error_context_sent_to_model
```

**Acceptance Criteria**:
- [ ] Auto-repair works once
- [ ] Fails correctly on second failure
- [ ] Error context helpful

---

### Task 4.4: Enhance Tool Protocol

- **Location**: `Sources/AISDK/Tools/Tool.swift` (modify existing)
- **Dependencies**: None
- **Complexity**: 5/10
- **Description**: Add validation and artifact support

**Implementation**:
- Add static validate() method
- Add ToolExecutionResult with artifacts
- Keep existing @Parameter wrapper

**Test-First**:
```
Tests/AISDKTests/Tools/EnhancedToolTests.swift
- test_validation_catches_invalid_params
- test_artifacts_returned
- test_backward_compatibility
```

**Acceptance Criteria**:
- [ ] Validation works
- [ ] Artifacts supported
- [ ] Existing tools still work

---

### Task 4.5: Implement AgentState Observable

- **Location**: `Sources/AISDK/Agents/AgentState.swift` (modify existing)
- **Dependencies**: Task 4.1
- **Complexity**: 4/10
- **Description**: Observable state for UI binding

**Implementation**:
- State enum with all cases
- Add stepIndex to executingTool
- Make queryable from actor

**Test-First**:
```
Tests/AISDKTests/Agents/AgentStateTests.swift
- test_state_transitions
- test_state_queryable_from_outside
```

**Acceptance Criteria**:
- [ ] State observable
- [ ] All transitions covered

---

## Phase 5: Generative UI

**Goal**: Dynamic UI from LLM responses
**Duration**: 2 weeks
**Dependencies**: Phase 4

### Task 5.1: Implement UICatalog

- **Location**: `Sources/AISDK/GenerativeUI/Catalog/UICatalog.swift`
- **Dependencies**: None
- **Complexity**: 6/10
- **Description**: Component catalog following json-render pattern

**Implementation**:
- Component definitions with Codable props
- Action definitions
- Validator definitions
- Prompt generation for LLM

**Test-First**:
```
Tests/AISDKTests/GenerativeUI/UICatalogTests.swift
- test_core8_components_defined
- test_prompt_generation
- test_schema_validation
```

**Acceptance Criteria**:
- [ ] Core 8 components in catalog
- [ ] Prompt generation works

---

### Task 5.2: Implement Core 8 Component Definitions

- **Location**: `Sources/AISDK/GenerativeUI/Components/`
- **Dependencies**: Task 5.1
- **Complexity**: 5/10
- **Description**: Text, Button, Card, Input, List, Image, Stack, Spacer

**Implementation**:
- One file per component definition
- Props struct with Codable
- JSON schema generation

**Test-First**:
```
Tests/AISDKTests/GenerativeUI/ComponentDefinitionTests.swift
- test_text_props_schema
- test_button_props_schema
- test_card_with_children
- test_input_validation_rules
```

**Acceptance Criteria**:
- [ ] All 8 components defined
- [ ] Props schemas correct

---

### Task 5.3: Implement UITree Model

- **Location**: `Sources/AISDK/GenerativeUI/Models/UITree.swift`
- **Dependencies**: Task 5.2
- **Complexity**: 5/10
- **Description**: Flat element map structure

**Implementation**:
- UITree with root and elements dictionary
- UIElement with key, type, props, children
- UIVisibilityCondition for conditional rendering

**Test-First**:
```
Tests/AISDKTests/GenerativeUI/UITreeTests.swift
- test_tree_decoding_from_json
- test_element_children_resolution
- test_visibility_condition_evaluation
```

**Acceptance Criteria**:
- [ ] JSON decoding works
- [ ] Children resolve correctly

---

### Task 5.4: Implement UIComponentRegistry

- **Location**: `Sources/AISDK/GenerativeUI/Registry/UIComponentRegistry.swift`
- **Dependencies**: Tasks 5.2, 5.3
- **Complexity**: 6/10
- **Description**: Map element types to SwiftUI views

**Implementation**:
- ViewBuilder closures per type
- Default registry with Core 8 views
- Custom registration support

**Test-First**:
```
Tests/AISDKTests/GenerativeUI/UIComponentRegistryTests.swift
- test_default_registry_has_core8
- test_custom_component_registration
- test_unknown_type_handled
```

**Acceptance Criteria**:
- [ ] Core 8 views implemented
- [ ] Custom registration works

---

### Task 5.5: Implement Core 8 SwiftUI Views

- **Location**: `Sources/AISDK/GenerativeUI/Views/`
- **Dependencies**: Task 5.4
- **Complexity**: 6/10
- **Description**: Actual SwiftUI view implementations

**Implementation**:
- GenerativeText, GenerativeButton, GenerativeCard, etc.
- Action handling via closure
- Children rendering support

**Test-First**:
```
Tests/AISDKTests/GenerativeUI/SwiftUIViewTests.swift
- test_text_renders_correctly
- test_button_action_triggers
- test_card_renders_children
- test_stack_layout_correct
```

**Acceptance Criteria**:
- [ ] All views render correctly
- [ ] Actions work
- [ ] Children rendered

---

### Task 5.6: Implement GenerativeUIView

- **Location**: `Sources/AISDK/GenerativeUI/Views/GenerativeUIView.swift`
- **Dependencies**: Tasks 5.3-5.5
- **Complexity**: 7/10
- **Description**: Main SwiftUI view for streaming UI

**Implementation**:
- StateObject for view model
- Process AIStreamEvent for UI updates
- Progressive rendering as tree builds

**Test-First**:
```
Tests/AISDKTests/GenerativeUI/GenerativeUIViewTests.swift
- test_renders_from_stream
- test_handles_partial_updates
- test_error_state_displayed
- test_loading_state_shown
```

**Acceptance Criteria**:
- [ ] Streaming UI works
- [ ] Error handling correct
- [ ] Loading states shown

---

### Task 5.7: Implement GenerativeUIViewModel

- **Location**: `Sources/AISDK/GenerativeUI/ViewModels/GenerativeUIViewModel.swift`
- **Dependencies**: Task 5.6
- **Complexity**: 6/10
- **Description**: View model for UI state management

**Implementation**:
- @Published properties for tree, loading, error
- Process stream events method
- JSONL parsing for partial updates

**Test-First**:
```
Tests/AISDKTests/GenerativeUI/GenerativeUIViewModelTests.swift
- test_processes_tree_events
- test_handles_partial_json
- test_error_captured
```

**Acceptance Criteria**:
- [ ] State management correct
- [ ] Partial JSON handled

---

## Phase 6: Testing Infrastructure

**Goal**: Comprehensive testing with mocks and simulation
**Duration**: 2 weeks
**Dependencies**: Phases 1-5

### Task 6.1: Implement MockAILanguageModel

- **Location**: `Tests/AISDKTests/Mocks/MockAILanguageModel.swift`
- **Dependencies**: Phase 1
- **Complexity**: 5/10
- **Description**: Fully configurable mock for tests

**Implementation**:
- Configurable handlers for all methods
- Preset factory methods
- Call recording for verification

**Acceptance Criteria**:
- [ ] All protocol methods mockable
- [ ] Presets work correctly

---

### Task 6.2: Implement simulateStream Helper

- **Location**: `Tests/AISDKTests/Helpers/StreamSimulation.swift`
- **Dependencies**: Task 1.2
- **Complexity**: 4/10
- **Description**: Simulate streaming for deterministic tests

**Acceptance Criteria**:
- [ ] Events emitted at intervals
- [ ] Text chunking works

---

### Task 6.3: Implement FaultInjector

- **Location**: `Tests/AISDKTests/Helpers/FaultInjector.swift`
- **Dependencies**: Phase 3
- **Complexity**: 5/10
- **Description**: Inject faults for reliability testing

**Acceptance Criteria**:
- [ ] All fault types injectable
- [ ] Per-provider targeting works

---

### Task 6.4: Integration Test Suite

- **Location**: `Tests/AISDKTests/Integration/`
- **Dependencies**: All phases
- **Complexity**: 6/10
- **Description**: Real API integration tests

**Implementation**:
- Gated by environment variables
- Test all providers
- Test failover scenarios

**Acceptance Criteria**:
- [ ] All providers tested
- [ ] CI can run with API keys

---

### Task 6.5: UI Snapshot Tests

- **Location**: `Tests/AISDKTests/GenerativeUI/SnapshotTests.swift`
- **Dependencies**: Phase 5
- **Complexity**: 5/10
- **Description**: Visual regression tests for generated UI

**Acceptance Criteria**:
- [ ] Core 8 components have snapshots
- [ ] CI can compare snapshots

---

## Phase 7: Documentation

**Goal**: Full documentation with tutorials
**Duration**: 1 week
**Dependencies**: Phases 1-6

### Task 7.1: Update AISDK-ARCHITECTURE.md

- **Location**: `docs/AISDK-ARCHITECTURE.md`
- **Dependencies**: All phases
- **Complexity**: 4/10
- **Description**: Update architecture documentation

**Acceptance Criteria**:
- [ ] All new components documented
- [ ] Diagrams updated

---

### Task 7.2: Write Migration Guide

- **Location**: `docs/MIGRATION-GUIDE.md`
- **Dependencies**: All phases
- **Complexity**: 5/10
- **Description**: Guide for migrating from old API

**Acceptance Criteria**:
- [ ] All breaking changes documented
- [ ] Code examples provided

---

### Task 7.3: Write Tutorials

- **Location**: `docs/tutorials/`
- **Dependencies**: All phases
- **Complexity**: 6/10
- **Description**: Step-by-step tutorials

**Implementation**:
- 01-getting-started.md
- 02-streaming-basics.md
- 03-tool-creation.md
- 04-multi-step-agents.md
- 05-generative-ui.md
- 06-reliability-patterns.md
- 07-testing-strategies.md

**Acceptance Criteria**:
- [ ] All tutorials complete
- [ ] Code samples work

---

### Task 7.4: Generate API Reference

- **Location**: `docs/api-reference/`
- **Dependencies**: All phases
- **Complexity**: 4/10
- **Description**: API documentation

**Acceptance Criteria**:
- [ ] All public APIs documented
- [ ] Examples included

---

### Task 7.5: Optional Telemetry Layer (Deferred)

- **Location**: `Sources/AISDK/Telemetry/`
- **Dependencies**: All phases
- **Complexity**: 7/10
- **Description**: Full telemetry (cost, latency, error rates)
- **Status**: DEFERRED - implement after core launch

---

## Summary

| Phase | Tasks | Complexity | Dependencies |
|-------|-------|------------|--------------|
| Phase 1: Core | 9 | 6-8 | None |
| Phase 2: Routing | 8 | 5-7 | Phase 1 |
| Phase 3: Reliability | 5 | 5-8 | Phase 2 |
| Phase 4: Agents | 5 | 4-9 | Phases 1-3 |
| Phase 5: Generative UI | 7 | 5-7 | Phase 4 |
| Phase 6: Testing | 5 | 4-6 | All |
| Phase 7: Docs | 5 | 4-6 | All |
| **Total** | **47** | | |

---

## Parallel Execution Opportunities

1. **Phase 1 tasks 1.1-1.8** can run in parallel
2. **Phase 2 tasks 2.2-2.3** (OpenRouter, LiteLLM) can run in parallel
3. **Phase 2 tasks 2.5-2.7** (adapters) can run in parallel
4. **Phase 5 tasks 5.1-5.2** can run in parallel
5. **Phase 6** can run in parallel with implementation phases
