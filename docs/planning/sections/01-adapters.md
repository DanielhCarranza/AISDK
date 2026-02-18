# Phase 0: Adapter Layer

**Duration**: 1 week
**Tasks**: 3
**Dependencies**: None

---

## Goal

Create a migration safety net by implementing adapters that wrap existing APIs with new interfaces. This allows existing consumers to continue working while new code is developed.

---

## Context Files (Read First)

```
Sources/AISDK/LLMs/LLMProtocol.swift           # Current LLM protocol
Sources/AISDK/Agents/Agent.swift               # Current Agent class (656 lines)
Sources/AISDK/Tools/AITool.swift               # AITool protocol
```

---

## Tasks

### Task 0.1: AILanguageModelAdapter

**Location**: `Sources/AISDK/Core/Adapters/Legacy/AILanguageModelAdapter.swift`
**Complexity**: 3/10
**Dependencies**: None

**Description**: Wrap existing `LLM` protocol to conform to new `AILanguageModel` actor protocol.

**Implementation**:
```swift
/// Adapter wrapping legacy LLM protocol for backward compatibility
public actor AILanguageModelAdapter: AILanguageModel {
    private let legacyProvider: any LLM
    private let modelInfo: LLMModel

    public var provider: String { modelInfo.provider.rawValue }
    public var modelId: String { modelInfo.id }
    public var capabilities: LLMCapabilities { modelInfo.capabilities }

    public init(legacyProvider: any LLM, modelInfo: LLMModel) {
        self.legacyProvider = legacyProvider
        self.modelInfo = modelInfo
    }

    public func generateText(request: AITextRequest) async throws -> AITextResult {
        // Convert AITextRequest -> ChatCompletionRequest
        let legacyRequest = convertToLegacyRequest(request)
        let legacyResponse = try await legacyProvider.sendChatCompletion(request: legacyRequest)
        return convertFromLegacyResponse(legacyResponse)
    }

    public func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        SafeAsyncStream.make { continuation in
            let legacyRequest = convertToLegacyRequest(request)
            for try await chunk in try await legacyProvider.sendChatCompletionStream(request: legacyRequest) {
                let event = convertChunkToEvent(chunk)
                continuation.yield(event)
            }
        }
    }
    // ... generateObject, streamObject
}
```

**Test-First**:
```
Tests/AISDKTests/Adapters/Legacy/AILanguageModelAdapterTests.swift
- test_adapter_conforms_to_protocol
- test_generate_text_maps_request
- test_stream_text_emits_events
- test_legacy_provider_errors_mapped
```

**Acceptance Criteria**:
- [ ] Adapter compiles and conforms to AILanguageModel
- [ ] Existing OpenAI/Anthropic/Gemini providers work through adapter
- [ ] Streaming events map correctly

---

### Task 0.2: AIAgentAdapter

**Location**: `Sources/AISDK/Core/Adapters/Legacy/AIAgentAdapter.swift`
**Complexity**: 4/10
**Dependencies**: Task 0.1

**Description**: Wrap existing `Agent` class with new `AIAgent` interface.

**Implementation**:
```swift
/// Adapter exposing legacy Agent with new AIAgent interface
public actor AIAgentAdapter {
    private let legacyAgent: Agent
    public nonisolated let observableState: ObservableAgentState

    public init(legacyAgent: Agent) {
        self.legacyAgent = legacyAgent
        self.observableState = ObservableAgentState()

        // Bridge legacy callbacks to observable state
        legacyAgent.onStateChange = { [weak observableState] state in
            Task { @MainActor in
                observableState?.state = convertState(state)
            }
        }
    }

    public func execute(messages: [AIMessage]) async throws -> AIAgentResult {
        let legacyMessages = messages.map(convertToLegacyMessage)
        // ... use legacy agent
    }
}
```

**Test-First**:
```
Tests/AISDKTests/Adapters/Legacy/AIAgentAdapterTests.swift
- test_adapter_wraps_legacy_agent
- test_state_changes_propagate
- test_tool_execution_works
```

**Acceptance Criteria**:
- [ ] Legacy Agent behavior preserved
- [ ] State changes visible in ObservableAgentState
- [ ] Tool execution works through adapter

---

### Task 0.3: Tool Migration

**Location**: `Sources/AISDK/Tools/AITool.swift`
**Complexity**: 3/10
**Dependencies**: None

**Description**: Migrate tools directly to the instance-based `AITool` protocol using `@AIParameter`.

**Acceptance Criteria**:
- [ ] Tools use `@AIParameter` for schema + validation
- [ ] `validate(arguments:)` and `setParameters(from:)` are available via defaults
- [ ] No adapter layer required for tools

---

## Parallel Opportunities

All 3 tasks can be developed in parallel as they have no inter-dependencies.

---

## Verification

Run all adapter tests:
```bash
swift test --filter "Legacy"
```
