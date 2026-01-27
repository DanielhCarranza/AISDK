# Phase 4: Agent & Tools

**Duration**: 2.5 weeks
**Tasks**: 7
**Dependencies**: Phases 1-3

---

## Goal

Implement actor-based multi-step agents with tool call repair and observable state for UI binding.

---

## Context Files (Read First)

```
Sources/AISDK/Agents/Agent.swift               # Current implementation (656 lines)
Sources/AISDK/Agents/AgentState.swift          # Current state machine
Sources/AISDK/Agents/AgentCallbacks.swift      # Current callbacks
Sources/AISDK/Tools/Tool.swift                 # Current tool protocol
docs/planning/external-review-feedback.md      # Actor reentrancy concerns
```

---

## Tasks

### Task 4.1a: AIAgent Core Shell (SPLIT)

**Location**: `Sources/AISDK/Agents/AIAgent.swift`
**Complexity**: 4/10
**Dependencies**: Phases 1-3

```swift
/// Actor-based agent with full isolation and observable state
public actor AIAgent {
    // MARK: - Configuration (immutable after init)
    private let model: any AILanguageModel
    private let tools: [any AITool.Type]
    private let instructions: String?
    private let stopCondition: StopCondition
    private let repairStrategy: ToolCallRepair.Strategy
    private let timeout: TimeoutPolicy

    // MARK: - Reentrancy Protection
    private var operationQueue: [AIOperation] = []
    private var isProcessing: Bool = false

    // MARK: - Mutable State (actor-isolated)
    private var currentState: AgentState = .idle
    private var stepHistory: [AIStepResult] = []
    private var messageHistory: [AIMessage] = []

    // MARK: - Observable State (for UI)
    public nonisolated let observableState: ObservableAgentState

    public init(
        model: any AILanguageModel,
        tools: [any AITool.Type] = [],
        instructions: String? = nil,
        stopCondition: StopCondition = .stepCount(20),
        repairStrategy: ToolCallRepair.Strategy = .autoRepairOnce,
        timeout: TimeoutPolicy = .default
    ) {
        self.model = model
        self.tools = tools
        self.instructions = instructions
        self.stopCondition = stopCondition
        self.repairStrategy = repairStrategy
        self.timeout = timeout
        self.observableState = ObservableAgentState()
    }

    /// Non-streaming execution
    public func execute(messages: [AIMessage]) async throws -> AIAgentResult {
        let operation = AIOperation(messages: messages)
        operationQueue.append(operation)
        await processNextIfIdle()
        return try await operation.result
    }

    private func processNextIfIdle() async {
        guard !isProcessing, let operation = operationQueue.first else { return }
        operationQueue.removeFirst()
        isProcessing = true

        do {
            let result = try await runAgentLoop(messages: operation.messages)
            operation.complete(with: result)
        } catch {
            operation.fail(with: error)
        }

        isProcessing = false
        await processNextIfIdle()  // Process next in queue
    }
}

/// Observable state for SwiftUI binding
@Observable
public final class ObservableAgentState: @unchecked Sendable {
    @MainActor public internal(set) var state: AgentState = .idle
    @MainActor public internal(set) var currentStep: Int = 0
    @MainActor public internal(set) var error: AIError?
    @MainActor public internal(set) var isProcessing: Bool = false
}

/// Internal operation wrapper for queue
private final class AIOperation: @unchecked Sendable {
    let messages: [AIMessage]
    private var continuation: CheckedContinuation<AIAgentResult, Error>?

    init(messages: [AIMessage]) {
        self.messages = messages
    }

    var result: AIAgentResult {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
            }
        }
    }

    func complete(with result: AIAgentResult) {
        continuation?.resume(returning: result)
    }

    func fail(with error: Error) {
        continuation?.resume(throwing: error)
    }
}
```

**Test-First**:
```
Tests/AISDKTests/Agents/AIAgentCoreTests.swift
- test_actor_initialization
- test_observable_state_accessible
- test_operation_queue_serializes_requests
- test_concurrent_execute_calls_queued
```

---

### Task 4.1b: AIAgent Streaming (SPLIT)

**Location**: `Sources/AISDK/Agents/AIAgent.swift` (extension)
**Complexity**: 5/10
**Dependencies**: Task 4.1a

```swift
extension AIAgent {
    /// Streaming execution with step callbacks
    public func executeStream(
        messages: [AIMessage],
        onStepFinish: @Sendable @escaping (AIStepResult) async -> StepAction = { _ in .continue },
        prepareStep: @Sendable @escaping (Int, [AIMessage]) async -> StepPreparation = { _, _ in .default }
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        SafeAsyncStream.make { [self] continuation in
            self.messageHistory = messages
            var stepIndex = 0

            while !Task.isCancelled {
                // Update state
                await self.updateState(.thinking, step: stepIndex)
                continuation.yield(.stepStart(stepIndex: stepIndex))

                // Prepare step (allows dynamic model/tool changes)
                let preparation = await prepareStep(stepIndex, self.messageHistory)
                let stepModel = preparation.model ?? self.model
                let stepTools = preparation.tools ?? self.tools

                // Build request
                let request = AITextRequest(
                    messages: self.messageHistory,
                    tools: stepTools,
                    temperature: preparation.temperature,
                    instructions: self.instructions
                )

                // Stream from model
                var stepText = ""
                var stepToolCalls: [AIToolCall] = []
                var stepUsage: AIUsage = .zero

                for try await event in stepModel.streamText(request: request) {
                    // Forward events
                    continuation.yield(event)

                    // Accumulate step data
                    switch event {
                    case .textDelta(let delta):
                        stepText += delta
                    case .toolCallFinish(let id, let args):
                        stepToolCalls.append(AIToolCall(id: id, name: "", arguments: args))
                    case .finish(let reason, let usage):
                        stepUsage = usage
                    default:
                        break
                    }
                }

                // Execute tools if needed
                if !stepToolCalls.isEmpty {
                    try await self.executeTools(
                        toolCalls: stepToolCalls,
                        stepIndex: stepIndex,
                        continuation: continuation
                    )
                }

                // Build step result
                let stepResult = AIStepResult(
                    stepIndex: stepIndex,
                    text: stepText.isEmpty ? nil : stepText,
                    toolCalls: stepToolCalls,
                    toolResults: [],
                    finishReason: .stop,
                    usage: stepUsage
                )
                self.stepHistory.append(stepResult)
                continuation.yield(.stepFinish(stepResult))

                // Check stop conditions
                let action = await onStepFinish(stepResult)
                switch action {
                case .stop:
                    await self.updateState(.idle, step: stepIndex)
                    continuation.finish()
                    return
                case .continue:
                    if self.shouldStop(stepResult) {
                        await self.updateState(.idle, step: stepIndex)
                        continuation.finish()
                        return
                    }
                case .inject(let additionalMessages):
                    self.messageHistory.append(contentsOf: additionalMessages)
                }

                stepIndex += 1
            }

            throw CancellationError()
        }
    }

    private func shouldStop(_ result: AIStepResult) -> Bool {
        switch stopCondition {
        case .stepCount(let max):
            return result.stepIndex >= max - 1
        case .noToolCalls:
            return result.toolCalls.isEmpty
        case .tokenBudget(let maxTokens):
            let totalTokens = stepHistory.reduce(0) { $0 + $1.usage.totalTokens }
            return totalTokens >= maxTokens
        case .custom(let predicate):
            return predicate(result)
        }
    }

    @MainActor
    private func updateState(_ state: AgentState, step: Int) {
        self.currentState = state
        self.observableState.state = state
        self.observableState.currentStep = step
    }
}

/// Step action returned by callback
public enum StepAction: Sendable {
    case `continue`
    case stop
    case inject([AIMessage])
}

/// Step preparation for dynamic configuration
public struct StepPreparation: Sendable {
    public let model: (any AILanguageModel)?
    public let tools: [any AITool.Type]?
    public let temperature: Double?

    public static let `default` = StepPreparation(model: nil, tools: nil, temperature: nil)
}
```

**Test-First**:
```
Tests/AISDKTests/Agents/AIAgentStreamingTests.swift
- test_stream_emits_step_events
- test_on_step_finish_called
- test_prepare_step_modifies_request
- test_step_action_stop_terminates
- test_step_action_inject_adds_messages
```

---

### Task 4.1c: AIAgent Tool Execution (SPLIT)

**Location**: `Sources/AISDK/Agents/AIAgent.swift` (extension)
**Complexity**: 5/10
**Dependencies**: Tasks 4.1a, 4.1b, 4.3

```swift
extension AIAgent {
    /// Execute tools with repair mechanism
    private func executeTools(
        toolCalls: [AIToolCall],
        stepIndex: Int,
        continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    ) async throws {
        for toolCall in toolCalls {
            await updateState(.executingTool(toolCall.name, stepIndex: stepIndex), step: stepIndex)

            do {
                // Find tool type
                guard let toolType = tools.first(where: { $0.name == toolCall.name }) else {
                    throw ToolError.unknownTool(toolCall.name)
                }

                // Execute with timeout
                let result = try await withTimeout(timeout.requestTimeout) {
                    try await toolType.execute(arguments: toolCall.decodedArguments)
                }

                // Emit result event
                continuation.yield(.toolResult(
                    id: toolCall.id,
                    result: result.content,
                    metadata: result.metadata as? AnyToolMetadata
                ))

                // Add to message history
                messageHistory.append(.tool(
                    content: result.content,
                    toolCallId: toolCall.id
                ))

            } catch let error as ToolError {
                // Attempt repair if configured
                if case .autoRepairOnce = repairStrategy {
                    do {
                        let repairedCall = try await ToolCallRepair.repair(
                            toolCall: toolCall,
                            error: error,
                            model: model
                        )

                        if let repaired = repairedCall {
                            // Retry with repaired arguments
                            let toolType = tools.first { $0.name == repaired.name }!
                            let result = try await toolType.execute(arguments: repaired.decodedArguments)

                            continuation.yield(.toolResult(
                                id: repaired.id,
                                result: result.content,
                                metadata: result.metadata as? AnyToolMetadata
                            ))

                            messageHistory.append(.tool(
                                content: result.content,
                                toolCallId: repaired.id
                            ))
                            continue
                        }
                    } catch {
                        // Repair failed, rethrow original error
                    }
                }

                throw AIError.toolExecution(toolName: toolCall.name, underlyingError: error.localizedDescription)
            }
        }
    }
}

/// Timeout wrapper
private func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: duration)
            throw AIError.timeout(operation: "tool execution", duration: duration.components.seconds)
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

---

### Task 4.2: StopCondition

**Location**: `Sources/AISDK/Agents/StopCondition.swift`
**Complexity**: 4/10
**Dependencies**: Task 4.1a

```swift
/// Stop conditions for agent loop
public enum StopCondition: Sendable {
    case stepCount(Int)
    case noToolCalls
    case tokenBudget(maxTokens: Int)  // NEW: from review
    case custom(@Sendable (AIStepResult) -> Bool)
}
```

---

### Task 4.3: ToolCallRepair

**Location**: `Sources/AISDK/Tools/ToolCallRepair.swift`
**Complexity**: 8/10
**Dependencies**: Phase 1

```swift
/// Tool call repair mechanism - hybrid strategy
public struct ToolCallRepair {
    public enum Strategy: Sendable {
        case strict
        case autoRepairOnce
        case autoRepairMax(Int)
        case custom(@Sendable (AIToolCall, ToolError) async throws -> AIToolCall?)
    }

    /// Attempt to repair a failed tool call
    public static func repair(
        toolCall: AIToolCall,
        error: ToolError,
        model: any AILanguageModel
    ) async throws -> AIToolCall? {
        // Build repair prompt
        let repairPrompt = """
        The tool call failed with the following error:
        Tool: \(toolCall.name)
        Arguments: \(toolCall.arguments)
        Error: \(error.localizedDescription)

        Please provide corrected arguments for this tool call.
        """

        // Ask model to fix
        let request = AITextRequest(
            messages: [.user(repairPrompt)],
            responseFormat: .json
        )

        let result = try await model.generateText(request: request)

        // Parse corrected arguments
        guard let correctedArgs = parseArguments(from: result.text) else {
            return nil
        }

        return AIToolCall(
            id: toolCall.id,
            name: toolCall.name,
            arguments: correctedArgs
        )
    }

    private static func parseArguments(from text: String) -> String? {
        // Extract JSON from response
        guard let data = text.data(using: .utf8),
              let _ = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return text
    }
}
```

---

### Task 4.4: AITool Protocol (Redesigned)

**Location**: `Sources/AISDK/Tools/AITool.swift`
**Complexity**: 6/10
**Dependencies**: None

```swift
/// Instance-based tool protocol
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

public struct AIToolResult: Sendable {
    public let content: String
    public let metadata: ToolMetadata?
    public let artifacts: [ToolArtifact]?
}
```

---

### Task 4.5: AgentState Observable

**Location**: `Sources/AISDK/Agents/AgentState.swift`
**Complexity**: 4/10
**Dependencies**: Task 4.1a

```swift
/// Agent execution state
public enum AgentState: Sendable, Equatable {
    case idle
    case thinking
    case executingTool(String, stepIndex: Int)
    case responding
    case error(AIError)
}

extension AIAgent {
    /// Reactive state stream for UI binding
    public func stateStream() -> AsyncStream<AgentState> {
        AsyncStream { continuation in
            // Observe ObservableAgentState changes
            // This bridges @Observable to AsyncStream
        }
    }
}
```

---

## Verification

```bash
swift test --filter "Agents"
swift test --filter "Tools"
```
