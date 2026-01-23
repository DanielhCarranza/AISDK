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
Sources/AISDK/Tools/Tool.swift                 # Current Tool protocol
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

### Task 0.3: ToolAdapter

**Location**: `Sources/AISDK/Core/Adapters/Legacy/ToolAdapter.swift`
**Complexity**: 3/10
**Dependencies**: None

**Description**: Adapt `@Parameter`-based tools to new immutable `AITool` protocol.

**Implementation**:
```swift
/// Type-erased wrapper for legacy @Parameter-based tools
public struct LegacyToolAdapter: Sendable {
    public let name: String
    public let description: String
    public let schema: ToolSchema

    private let executeHandler: @Sendable ([String: Any]) async throws -> ToolExecutionResult

    public init<T: Tool>(_ toolType: T.Type) {
        self.name = T.name
        self.description = T.description
        self.schema = T.jsonSchema()

        self.executeHandler = { arguments in
            var tool = T()
            try tool.setParameters(from: arguments)
            let (content, metadata) = try await tool.execute()
            return ToolExecutionResult(content: content, metadata: metadata)
        }
    }

    public func execute(arguments: [String: Any]) async throws -> ToolExecutionResult {
        try await executeHandler(arguments)
    }
}
```

**Test-First**:
```
Tests/AISDKTests/Adapters/Legacy/ToolAdapterTests.swift
- test_adapts_parameter_based_tool
- test_schema_preserved
- test_execution_works
```

**Acceptance Criteria**:
- [ ] Existing @Parameter tools work through adapter
- [ ] JSON schema generation preserved
- [ ] Sendable compliance maintained

---

## Parallel Opportunities

All 3 tasks can be developed in parallel as they have no inter-dependencies.

---

## Verification

Run all adapter tests:
```bash
swift test --filter "Legacy"
```
