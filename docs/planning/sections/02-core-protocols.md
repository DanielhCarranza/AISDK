# Phase 1: Core Protocol Layer

**Duration**: 2 weeks
**Tasks**: 13
**Dependencies**: Phase 0

---

## Goal

Establish the unified API surface matching Vercel AI SDK 6.x patterns with Swift-native safety guarantees including actor isolation, Sendable compliance, and bounded streaming.

---

## Context Files (Read First)

```
Sources/AISDK/LLMs/LLMProtocol.swift           # Current minimal interface
Sources/AISDK/LLMs/LLMModelProtocol.swift      # 31+ capability flags (558 lines)
Sources/AISDK/Models/AIMessage.swift           # Current message types
Sources/AISDK/Models/ChatMessage.swift         # Application-level message
Sources/AISDK/Errors/AISDKError.swift          # Current error types
docs/planning/claude-research.md               # Vercel AI SDK 6.x patterns
```

---

## Tasks

### Task 1.1: AILanguageModel Protocol

**Location**: `Sources/AISDK/Core/Protocols/AILanguageModel.swift`
**Complexity**: 6/10
**Dependencies**: None

**Implementation**:
```swift
/// Core language model protocol with actor isolation
/// Swift equivalent of Vercel's LanguageModelV3
public protocol AILanguageModel: Actor, Sendable {
    /// Provider identifier (e.g., "openai", "anthropic")
    var provider: String { get }

    /// Model identifier (e.g., "gpt-5-mini")
    var modelId: String { get }

    /// Model capabilities for routing
    var capabilities: LLMCapabilities { get }

    /// Generate text (non-streaming)
    func generateText(request: AITextRequest) async throws -> AITextResult

    /// Stream text with full event model
    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>

    /// Generate structured object
    func generateObject<T: Codable & Sendable>(
        request: AIObjectRequest<T>
    ) async throws -> AIObjectResult<T>

    /// Stream structured object
    func streamObject<T: Codable & Sendable>(
        request: AIObjectRequest<T>
    ) -> AsyncThrowingStream<AIStreamEvent, Error>
}
```

**Test-First**:
```
Tests/AISDKTests/Core/Protocols/AILanguageModelTests.swift
- test_protocol_compiles_with_actor_requirement
- test_mock_implementation_conforms
- test_all_methods_are_async
- test_sendable_constraint_enforced
```

**Acceptance Criteria**:
- [ ] Protocol compiles with actor isolation
- [ ] MockAILanguageModel can conform
- [ ] All types in signatures are Sendable

---

### Task 1.2: AIStreamEvent (10+ Events)

**Location**: `Sources/AISDK/Core/Models/AIStreamEvent.swift`
**Complexity**: 5/10
**Dependencies**: None

**Implementation**:
```swift
/// Unified streaming event model - full Vercel AI SDK 6.x parity
public enum AIStreamEvent: Sendable, Codable, Equatable {
    // Text Events
    case textDelta(String)
    case textCompletion(String)

    // Tool Call Events
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCallFinish(id: String, arguments: String)
    case toolResult(id: String, result: String, metadata: AnyToolMetadata?)

    // Step Events
    case stepStart(stepIndex: Int)
    case stepFinish(AIStepResult)

    // Completion Events
    case finish(finishReason: AIFinishReason, usage: AIUsage)
    case error(AIError)

    // Reasoning Events (o3/o4 models)
    case reasoningStart
    case reasoningDelta(String)
    case reasoningFinish(String)

    // Keepalive (for long-running operations)
    case heartbeat(timestamp: Date, requestId: String)
}

public enum AIFinishReason: String, Sendable, Codable {
    case stop
    case length
    case toolCalls = "tool_calls"
    case contentFilter = "content_filter"
    case error
}
```

**Test-First**:
```
Tests/AISDKTests/Core/Models/AIStreamEventTests.swift
- test_all_events_are_codable
- test_all_events_are_sendable
- test_encoding_decoding_roundtrip
- test_equatable_implementation
```

**Acceptance Criteria**:
- [ ] All 14 event types defined
- [ ] Codable round-trip works
- [ ] Sendable for all associated types

---

### Task 1.3: AITextRequest/AITextResult

**Location**: `Sources/AISDK/Core/Models/AITextRequest.swift`
**Location**: `Sources/AISDK/Core/Models/AITextResult.swift`
**Complexity**: 5/10
**Dependencies**: Task 1.2

**Implementation**:
```swift
public struct AITextRequest: Sendable {
    public let messages: [AIMessage]
    public let model: String?
    public let temperature: Double?
    public let maxTokens: Int?
    public let tools: [any AITool.Type]?
    public let toolChoice: AIToolChoice?
    public let responseFormat: AIResponseFormat?
    public let instructions: String?

    // Reliability overrides
    public let timeout: TimeInterval?
    public let retryPolicy: RetryPolicy?
    public let traceContext: AITraceContext?

    // PHI protection (from review)
    public let allowedProviders: Set<String>?
    public let sensitivity: DataSensitivity?

    // Memory control (from review)
    public let bufferPolicy: StreamBufferPolicy?
}

public struct AITextResult: Sendable {
    public let text: String
    public let toolCalls: [AIToolCall]
    public let toolResults: [AIToolResult]
    public let finishReason: AIFinishReason
    public let usage: AIUsage
    public let traceContext: AITraceContext
    public let latency: TimeInterval
    public let provider: String
    public let model: String
}

public enum DataSensitivity: String, Sendable, Codable {
    case `public`
    case `internal`
    case phi  // Protected Health Information
}

public enum StreamBufferPolicy: Sendable {
    case unbounded
    case bounded(capacity: Int)
    case suspending(capacity: Int)
}
```

**Test-First**:
```
Tests/AISDKTests/Core/Models/AITextRequestTests.swift
Tests/AISDKTests/Core/Models/AITextResultTests.swift
- test_request_encoding
- test_result_decoding
- test_optional_fields_handled
- test_sensitivity_defaults_to_internal
```

---

### Task 1.4: AIObjectRequest/AIObjectResult

**Location**: `Sources/AISDK/Core/Models/AIObjectRequest.swift`
**Location**: `Sources/AISDK/Core/Models/AIObjectResult.swift`
**Complexity**: 6/10
**Dependencies**: Task 1.2

**Implementation**:
```swift
public struct AIObjectRequest<T: Codable & Sendable>: Sendable {
    public let messages: [AIMessage]
    public let schema: T.Type
    public let model: String?
    public let temperature: Double?
    public let instructions: String?
    public let traceContext: AITraceContext?
}

public struct AIObjectResult<T: Codable & Sendable>: Sendable {
    public let object: T
    public let partialObject: T?  // For streaming
    public let finishReason: AIFinishReason
    public let usage: AIUsage
    public let traceContext: AITraceContext
}
```

---

### Task 1.5: AIStepResult

**Location**: `Sources/AISDK/Core/Models/AIStepResult.swift`
**Complexity**: 4/10
**Dependencies**: Tasks 1.2, 1.3

---

### Task 1.6: AIUsage/AIFinishReason

**Location**: `Sources/AISDK/Core/Models/AIUsage.swift`
**Complexity**: 3/10
**Dependencies**: None

```swift
public struct AIUsage: Sendable, Codable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let cachedTokens: Int?
    public let reasoningTokens: Int?

    public static func + (lhs: AIUsage, rhs: AIUsage) -> AIUsage {
        // Aggregate usage across steps
    }
}
```

---

### Task 1.7: AIError Taxonomy

**Location**: `Sources/AISDK/Core/Errors/AIError.swift`
**Complexity**: 6/10
**Dependencies**: None

```swift
public enum AIError: Error, Sendable, Equatable {
    case authentication(provider: String, message: String)
    case rateLimit(provider: String, retryAfter: TimeInterval?)
    case contextLengthExceeded(provider: String, maxTokens: Int, requestedTokens: Int)
    case validation(field: String, message: String)
    case toolExecution(toolName: String, underlyingError: String)
    case providerUnavailable(provider: String, reason: String)
    case network(statusCode: Int?, message: String)
    case timeout(operation: String, duration: TimeInterval)
    case cancelled
    case streamError(message: String)
    case decodingError(type: String, message: String)
    case agentDeallocated

    /// Error type for circuit breaker classification
    public var errorType: AIErrorType { ... }

    /// PHI-safe description (redacts sensitive data)
    public var safeDescription: String { ... }
}

public enum AIErrorType: Sendable {
    case authentication
    case rateLimit
    case timeout
    case network
    case validation
    case generic
}
```

---

### Task 1.8: AITraceContext

**Location**: `Sources/AISDK/Core/Models/AITraceContext.swift`
**Complexity**: 4/10
**Dependencies**: None

---

### Task 1.9: AISDKConfiguration

**Location**: `Sources/AISDK/Core/Configuration/AISDKConfiguration.swift`
**Complexity**: 4/10
**Dependencies**: Tasks 1.1-1.8

```swift
public struct AISDKConfiguration: Sendable {
    public let defaultProvider: String
    public let defaultModel: String
    public let observers: [any AISDKObserver]
    public let reliabilityPolicy: ReliabilityPolicy
    public let phiRedactionEnabled: Bool

    /// Validated configuration - fails fast on missing keys
    public static func validated() throws -> AISDKConfiguration {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
              !apiKey.isEmpty else {
            throw AISDKConfigurationError.missingRequiredKey("OPENROUTER_API_KEY")
        }
        // ...
    }
}
```

---

### Task 1.10: AISDKObserver Protocol (NEW)

**Location**: `Sources/AISDK/Core/Telemetry/AISDKObserver.swift`
**Complexity**: 4/10
**Dependencies**: Tasks 1.2, 1.8

```swift
/// Telemetry hooks for observability
public protocol AISDKObserver: Sendable {
    func didStartRequest(_ context: AITraceContext)
    func didReceiveEvent(_ event: AIStreamEvent, context: AITraceContext)
    func didCompleteRequest(_ result: AITextResult, context: AITraceContext)
    func didFailRequest(_ error: AIError, context: AITraceContext)
    func didSelectProvider(_ provider: String, reason: String, context: AITraceContext)
}

/// No-op implementation for default
public struct NoOpObserver: AISDKObserver {
    public init() {}
    public func didStartRequest(_ context: AITraceContext) {}
    // ...
}
```

---

### Task 1.11: SafeAsyncStream Utility (NEW)

**Location**: `Sources/AISDK/Core/Utilities/SafeAsyncStream.swift`
**Complexity**: 5/10
**Dependencies**: Task 1.3

```swift
/// Memory-safe stream creation with proper cancellation
public struct SafeAsyncStream {
    public static func make<Element: Sendable>(
        bufferingPolicy: StreamBufferPolicy = .bounded(capacity: 1000),
        _ build: @escaping @Sendable (
            AsyncThrowingStream<Element, Error>.Continuation
        ) async throws -> Void
    ) -> AsyncThrowingStream<Element, Error> {

        let policy: AsyncThrowingStream<Element, Error>.Continuation.BufferingPolicy
        switch bufferingPolicy {
        case .unbounded:
            policy = .unbounded
        case .bounded(let capacity):
            policy = .bufferingNewest(capacity)
        case .suspending(let capacity):
            policy = .bufferingOldest(capacity)
        }

        return AsyncThrowingStream(bufferingPolicy: policy) { continuation in
            let task = Task {
                do {
                    try await build(continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination {
                    task.cancel()
                }
            }
        }
    }
}
```

---

### Task 1.12: MockAILanguageModel

**Location**: `Tests/AISDKTests/Mocks/MockAILanguageModel.swift`
**Complexity**: 5/10
**Dependencies**: Task 1.1

---

### Task 1.13: simulateStream Helper

**Location**: `Tests/AISDKTests/Helpers/StreamSimulation.swift`
**Complexity**: 4/10
**Dependencies**: Task 1.2

---

## Parallel Opportunities

- Tasks 1.1, 1.2, 1.6, 1.7, 1.8 have no dependencies - run in parallel
- Tasks 1.10, 1.11, 1.12, 1.13 can run in parallel once 1.2 is done

---

## Verification

```bash
swift test --filter "Core"
```
