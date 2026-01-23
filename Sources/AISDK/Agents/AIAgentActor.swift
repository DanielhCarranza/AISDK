//
//  AIAgentActor.swift
//  AISDK
//
//  Actor-based agent with full isolation and observable state
//  Based on Vercel AI SDK 6.x agent patterns with Swift 6 concurrency
//

import Foundation

// MARK: - AIAgentActor

/// Actor-based agent with full isolation and observable state for UI binding.
///
/// This actor provides thread-safe agent operations with an operation queue
/// to prevent reentrancy issues during concurrent execution.
///
/// ## Features
/// - Full actor isolation for thread safety
/// - Operation queue for serialized request handling
/// - Observable state bridge for SwiftUI integration
/// - Configurable stop conditions and timeout policies
///
/// ## Usage
/// ```swift
/// let agent = AIAgentActor(
///     model: myModel,
///     tools: [SearchTool.self, CalculatorTool.self],
///     instructions: "You are a helpful assistant."
/// )
///
/// // Non-streaming execution
/// let result = try await agent.execute(messages: [.user("Hello")])
///
/// // Check observable state from SwiftUI
/// @MainActor
/// var body: some View {
///     Text(agent.observableState.state.statusMessage)
/// }
/// ```
public actor AIAgentActor {
    // MARK: - Configuration (immutable after init)

    /// The language model to use for generation
    private let model: any AILanguageModel

    /// Available tool types for this agent
    private let tools: [Tool.Type]

    /// System instructions for the agent
    private let instructions: String?

    /// When to stop the agent loop
    private let stopCondition: StopCondition

    /// Timeout policy for operations
    private let timeout: TimeoutPolicy

    /// Maximum number of tool execution rounds
    private let maxToolRounds: Int

    /// Unique identifier for this agent
    public nonisolated let agentId: String

    /// Optional name for this agent
    public nonisolated let name: String?

    // MARK: - Reentrancy Protection

    /// Queue of pending operations
    private var operationQueue: [AIOperation] = []

    /// Whether the agent is currently processing an operation
    private var isProcessing: Bool = false

    /// Queue of pending streaming operations
    private var streamingOperationQueue: [AIStreamingOperation] = []

    /// Whether the agent is currently processing a streaming operation
    private var isStreamingProcessing: Bool = false

    // MARK: - Mutable State (actor-isolated)

    /// Current state of the agent
    private var currentState: AgentState = .idle

    /// History of step results
    private var stepHistory: [AIStepResult] = []

    /// Conversation message history
    private var messageHistory: [AIMessage] = []

    // MARK: - Observable State (for UI)

    /// Observable state wrapper for SwiftUI binding
    /// Access this from the main actor to observe state changes
    public nonisolated let observableState: ObservableAgentState

    // MARK: - Initialization

    /// Creates a new AI agent actor
    ///
    /// - Parameters:
    ///   - model: The language model to use for generation
    ///   - tools: Array of tool types available to the agent
    ///   - instructions: Optional system instructions for the agent
    ///   - stopCondition: When to stop the agent loop (default: 20 steps)
    ///   - timeout: Timeout policy for operations (default: standard)
    ///   - maxToolRounds: Maximum tool execution rounds per step (default: 10)
    ///   - name: Optional name for the agent
    ///   - agentId: Optional unique identifier (auto-generated if nil)
    public init(
        model: any AILanguageModel,
        tools: [Tool.Type] = [],
        instructions: String? = nil,
        stopCondition: StopCondition = .stepCount(20),
        timeout: TimeoutPolicy = .default,
        maxToolRounds: Int = 10,
        name: String? = nil,
        agentId: String? = nil
    ) {
        self.model = model
        self.tools = tools
        self.instructions = instructions
        self.stopCondition = stopCondition
        self.timeout = timeout
        self.maxToolRounds = maxToolRounds
        self.name = name
        self.agentId = agentId ?? UUID().uuidString
        self.observableState = ObservableAgentState()
    }

    // MARK: - Public API

    /// Execute a non-streaming agent loop with the given messages
    ///
    /// This method queues the operation and processes it when the agent is available.
    /// Concurrent calls are serialized through the operation queue.
    ///
    /// - Parameter messages: The initial messages for the conversation
    /// - Returns: The result of the agent execution
    /// - Throws: AIAgentActorError if execution fails
    public func execute(messages: [AIMessage]) async throws -> AIAgentResult {
        let operation = AIOperation(messages: messages)
        operationQueue.append(operation)
        await processNextIfIdle()
        return try await operation.result
    }

    /// Get the current state of the agent
    public var state: AgentState {
        currentState
    }

    /// Get the message history
    public var messages: [AIMessage] {
        messageHistory
    }

    /// Get the step history
    public var steps: [AIStepResult] {
        stepHistory
    }

    // MARK: - Streaming API

    /// Execute a streaming agent loop with the given messages
    ///
    /// This method provides real-time streaming of agent execution, emitting events as
    /// text is generated, tool calls are made, and steps complete. It uses the same
    /// operation queue as `execute()` to prevent reentrancy.
    ///
    /// - Parameter messages: The initial messages for the conversation
    /// - Returns: An async stream of AIStreamEvent for real-time updates
    ///
    /// ## Events Emitted
    /// - `.start`: Stream has started with metadata
    /// - `.stepStart`: A new step in the agent loop is starting
    /// - `.textDelta`: Partial text content during generation
    /// - `.toolCallStart`: A tool call has been requested
    /// - `.toolCallDelta`: Partial tool call arguments
    /// - `.toolCall`: Complete tool call with full arguments
    /// - `.toolResult`: Result from executing a tool
    /// - `.stepFinish`: A step has completed with its result
    /// - `.usage`: Token usage information
    /// - `.finish`: Stream has completed
    /// - `.error`: An error occurred
    ///
    /// ## Usage Example
    /// ```swift
    /// for try await event in agent.streamExecute(messages: [.user("Search for news")]) {
    ///     switch event {
    ///     case .textDelta(let text):
    ///         print(text, terminator: "")
    ///     case .toolCallStart(let id, let name):
    ///         print("Calling tool: \(name)")
    ///     case .stepFinish(let stepIndex, let result):
    ///         print("Step \(stepIndex) finished")
    ///     case .finish(let reason, let usage):
    ///         print("Done: \(reason), tokens: \(usage.totalTokens)")
    ///     default:
    ///         break
    ///     }
    /// }
    /// ```
    public nonisolated func streamExecute(messages: [AIMessage]) -> AsyncThrowingStream<AIStreamEvent, Error> {
        SafeAsyncStream.make { [self] continuation in
            let operation = AIStreamingOperation(messages: messages, continuation: continuation)
            await self.enqueueStreamingOperation(operation)
            try await operation.waitForCompletion()
        }
    }

    /// Enqueue a streaming operation for processing
    private func enqueueStreamingOperation(_ operation: AIStreamingOperation) {
        streamingOperationQueue.append(operation)
        Task {
            await processNextStreamingIfIdle()
        }
    }

    /// Process the next streaming operation in the queue if idle
    private func processNextStreamingIfIdle() async {
        guard !isStreamingProcessing, let operation = streamingOperationQueue.first else { return }
        streamingOperationQueue.removeFirst()
        isStreamingProcessing = true

        await setObservableIsProcessing(true)

        do {
            try await runStreamingAgentLoop(operation: operation)
        } catch {
            operation.continuation.yield(.error(error))
            operation.continuation.finish(throwing: error)
            operation.markCompleted(with: error)
        }

        isStreamingProcessing = false
        await setObservableIsProcessing(false)

        // Process next in queue
        await processNextStreamingIfIdle()
    }

    /// Run the streaming agent loop
    private func runStreamingAgentLoop(operation: AIStreamingOperation) async throws {
        let continuation = operation.continuation

        // Emit start event
        continuation.yield(.start(metadata: AIStreamMetadata(
            requestId: UUID().uuidString,
            model: model.modelId,
            provider: model.provider
        )))

        // Set up initial message history
        var workingMessages = operation.messages

        // Add system instructions if provided
        if let instructions = instructions {
            workingMessages.insert(.system(instructions), at: 0)
        }

        messageHistory = workingMessages
        stepHistory = []

        var stepIndex = 0
        var totalUsage = AIUsage.zero
        var lastText = ""

        // Main agent loop
        while !Task.isCancelled && !continuation.isTerminated {
            // Emit step start
            continuation.yield(.stepStart(stepIndex: stepIndex))

            // Update state
            currentState = .thinking
            await setObservableThinking(step: stepIndex)

            // Build request
            let request = AITextRequest(
                messages: workingMessages,
                tools: tools.map { $0.jsonSchema() }
            )

            // Stream the response
            var stepText = ""
            var toolCalls: [AIToolCallResult] = []
            var toolCallBuilders: [String: ToolCallBuilder] = [:]
            var stepUsage = AIUsage.zero
            var finishReason: AIFinishReason = .unknown

            do {
                let stream = model.streamText(request: request)

                for try await event in stream {
                    guard !continuation.isTerminated else { break }

                    switch event {
                    case .textDelta(let delta):
                        stepText += delta
                        continuation.yield(.textDelta(delta))

                    case .toolCallStart(let id, let name):
                        toolCallBuilders[id] = ToolCallBuilder(id: id, name: name)
                        continuation.yield(.toolCallStart(id: id, name: name))

                    case .toolCallDelta(let id, let argumentsDelta):
                        toolCallBuilders[id]?.appendArguments(argumentsDelta)
                        continuation.yield(.toolCallDelta(id: id, argumentsDelta: argumentsDelta))

                    case .toolCall(let id, let name, let arguments),
                         .toolCallFinish(let id, let name, let arguments):
                        let toolCall = AIToolCallResult(id: id, name: name, arguments: arguments)
                        toolCalls.append(toolCall)
                        continuation.yield(.toolCall(id: id, name: name, arguments: arguments))

                    case .usage(let eventUsage):
                        stepUsage = eventUsage

                    case .finish(let reason, let usage):
                        finishReason = reason
                        stepUsage = usage

                    case .error(let error):
                        throw error

                    default:
                        // Forward other events
                        continuation.yield(event)
                    }
                }

                // Build any incomplete tool calls from deltas
                for (id, builder) in toolCallBuilders {
                    if !toolCalls.contains(where: { $0.id == id }) {
                        let toolCall = builder.build()
                        toolCalls.append(toolCall)
                        continuation.yield(.toolCall(id: toolCall.id, name: toolCall.name, arguments: toolCall.arguments))
                    }
                }

            } catch {
                let agentError = AISDKErrorV2.from(error)
                currentState = .error(AgentError.underlying(error))
                await setObservableError(state: .error(AgentError.underlying(error)), error: agentError)
                throw error
            }

            totalUsage = totalUsage + stepUsage
            lastText = stepText

            // Add assistant message to history
            let assistantMessage: AIMessage
            if !toolCalls.isEmpty {
                let aiToolCalls = toolCalls.map { call in
                    AIMessage.ToolCall(id: call.id, name: call.name, arguments: call.arguments)
                }
                assistantMessage = .assistant(stepText, toolCalls: aiToolCalls)
            } else {
                assistantMessage = .assistant(stepText)
            }
            workingMessages.append(assistantMessage)
            messageHistory = workingMessages

            // Build step result
            var toolResults: [AIToolResultData] = []

            // Check if we should stop (no tool calls)
            guard !toolCalls.isEmpty else {
                // No tool calls, emit step finish and we're done
                let stepResult = AIStepResult(
                    stepIndex: stepIndex,
                    text: stepText,
                    toolCalls: toolCalls,
                    toolResults: toolResults,
                    usage: stepUsage,
                    finishReason: finishReason
                )
                stepHistory.append(stepResult)
                continuation.yield(.stepFinish(stepIndex: stepIndex, result: stepResult))
                currentState = .idle
                await setObservableState(.idle)
                break
            }

            // Execute tool calls
            let firstToolName = toolCalls.first?.name ?? "unknown"
            currentState = .executingTool(firstToolName)
            await setObservableState(.executingTool(firstToolName))

            for toolCall in toolCalls {
                do {
                    let toolResult = try await executeToolCall(toolCall)
                    let resultData = AIToolResultData(id: toolCall.id, result: toolResult, metadata: nil)
                    toolResults.append(resultData)
                    continuation.yield(.toolResult(id: toolCall.id, result: toolResult, metadata: nil))

                    let toolMessage = AIMessage.tool(toolResult, toolCallId: toolCall.id)
                    workingMessages.append(toolMessage)
                } catch {
                    // Tool failed, add error message
                    let errorResult = "Error: \(error.localizedDescription)"
                    let resultData = AIToolResultData(id: toolCall.id, result: errorResult, metadata: nil)
                    toolResults.append(resultData)
                    continuation.yield(.toolResult(id: toolCall.id, result: errorResult, metadata: nil))

                    let errorMessage = AIMessage.tool(errorResult, toolCallId: toolCall.id)
                    workingMessages.append(errorMessage)
                }
            }
            messageHistory = workingMessages

            // Build and emit step result
            let stepResult = AIStepResult(
                stepIndex: stepIndex,
                text: stepText,
                toolCalls: toolCalls,
                toolResults: toolResults,
                usage: stepUsage,
                finishReason: finishReason
            )
            stepHistory.append(stepResult)
            continuation.yield(.stepFinish(stepIndex: stepIndex, result: stepResult))

            // Check stop conditions (pass accumulated tokens for O(1) budget check)
            if shouldStop(stepResult, accumulatedTokens: totalUsage.totalTokens) {
                currentState = .idle
                await setObservableState(.idle)
                break
            }

            stepIndex += 1
        }

        if Task.isCancelled {
            continuation.finish(throwing: CancellationError())
            operation.markCompleted(with: CancellationError())
            return
        }

        // Emit final usage and finish
        continuation.yield(.usage(totalUsage))
        continuation.yield(.finish(finishReason: .stop, usage: totalUsage))
        continuation.finish()
        operation.markCompleted(with: nil)
    }

    /// Reset the agent's conversation and step history
    public func reset() {
        messageHistory = []
        stepHistory = []
        currentState = .idle
        Task { @MainActor in
            observableState.state = .idle
            observableState.currentStep = 0
            observableState.error = nil
            observableState.isProcessing = false
        }
    }

    /// Set the message history
    ///
    /// - Parameter messages: The new message history
    public func setMessages(_ messages: [AIMessage]) {
        messageHistory = messages
    }

    // MARK: - Internal Processing

    /// Process the next operation in the queue if idle
    private func processNextIfIdle() async {
        guard !isProcessing, let operation = operationQueue.first else { return }
        operationQueue.removeFirst()
        isProcessing = true

        await setObservableIsProcessing(true)

        do {
            let result = try await runAgentLoop(messages: operation.messages)
            operation.complete(with: result)
        } catch {
            operation.fail(with: error)
        }

        isProcessing = false
        await setObservableIsProcessing(false)

        // Process next in queue
        await processNextIfIdle()
    }

    /// Run the main agent loop
    ///
    /// - Parameter messages: The messages to process
    /// - Returns: The agent result
    private func runAgentLoop(messages: [AIMessage]) async throws -> AIAgentResult {
        // Set up initial message history
        var workingMessages = messages

        // Add system instructions if provided
        if let instructions = instructions {
            workingMessages.insert(.system(instructions), at: 0)
        }

        messageHistory = workingMessages
        stepHistory = []

        var stepIndex = 0
        var totalUsage = AIUsage.zero
        var lastText = ""

        // Main agent loop
        while !Task.isCancelled {
            // Update state
            currentState = .thinking
            await setObservableThinking(step: stepIndex)

            // Build request
            let request = AITextRequest(
                messages: workingMessages,
                tools: tools.map { $0.jsonSchema() }
            )

            // Generate response
            let result: AITextResult
            do {
                result = try await TimeoutExecutor(policy: timeout).execute {
                    try await self.model.generateText(request: request)
                }
            } catch {
                let agentError = AISDKErrorV2.from(error)
                currentState = .error(AgentError.underlying(error))
                await setObservableError(state: .error(AgentError.underlying(error)), error: agentError)
                throw error
            }

            totalUsage = totalUsage + result.usage
            lastText = result.text

            // Add assistant message to history
            let toolCalls = result.toolCalls
            let assistantMessage: AIMessage
            if !toolCalls.isEmpty {
                let aiToolCalls = toolCalls.map { call in
                    AIMessage.ToolCall(id: call.id, name: call.name, arguments: call.arguments)
                }
                assistantMessage = .assistant(result.text, toolCalls: aiToolCalls)
            } else {
                assistantMessage = .assistant(result.text)
            }
            workingMessages.append(assistantMessage)
            messageHistory = workingMessages

            // Check if we should stop (no tool calls)
            guard !toolCalls.isEmpty else {
                // No tool calls - build step result and we're done
                let stepResult = AIStepResult(
                    stepIndex: stepIndex,
                    text: result.text,
                    toolCalls: toolCalls,
                    toolResults: [],
                    usage: result.usage,
                    finishReason: result.finishReason
                )
                stepHistory.append(stepResult)
                currentState = .idle
                await setObservableState(.idle)
                break
            }

            // Execute tool calls and collect results
            let firstToolName = toolCalls.first?.name ?? "unknown"
            currentState = .executingTool(firstToolName)
            await setObservableState(.executingTool(firstToolName))

            var toolResults: [AIToolResultData] = []
            for toolCall in toolCalls {
                do {
                    let toolResult = try await executeToolCall(toolCall)
                    toolResults.append(AIToolResultData(id: toolCall.id, result: toolResult, metadata: nil))
                    let toolMessage = AIMessage.tool(toolResult, toolCallId: toolCall.id)
                    workingMessages.append(toolMessage)
                } catch {
                    // Tool failed, add error message
                    let errorResult = "Error: \(error.localizedDescription)"
                    toolResults.append(AIToolResultData(id: toolCall.id, result: errorResult, metadata: nil))
                    let errorMessage = AIMessage.tool(errorResult, toolCallId: toolCall.id)
                    workingMessages.append(errorMessage)
                }
            }
            messageHistory = workingMessages

            // Build step result with tool results (matching streaming path)
            let stepResult = AIStepResult(
                stepIndex: stepIndex,
                text: result.text,
                toolCalls: toolCalls,
                toolResults: toolResults,
                usage: result.usage,
                finishReason: result.finishReason
            )
            stepHistory.append(stepResult)

            // Check stop conditions (pass accumulated tokens for O(1) budget check)
            if shouldStop(stepResult, accumulatedTokens: totalUsage.totalTokens) {
                currentState = .idle
                await setObservableState(.idle)
                break
            }

            stepIndex += 1
        }

        if Task.isCancelled {
            throw CancellationError()
        }

        return AIAgentResult(
            text: lastText,
            steps: stepHistory,
            messages: messageHistory,
            usage: totalUsage
        )
    }

    /// Execute a single tool call
    ///
    /// - Parameter toolCall: The tool call to execute
    /// - Returns: The tool result as a string
    private func executeToolCall(_ toolCall: AIToolCallResult) async throws -> String {
        // Find tool type by name
        guard let toolType = tools.first(where: { $0.init().name == toolCall.name }) else {
            throw AISDKErrorV2.toolNotFound(toolCall.name)
        }

        // Create and configure tool instance
        let argumentsData = toolCall.arguments.data(using: .utf8) ?? Data()

        let configuredTool: Tool
        do {
            var tool = toolType.init()
            configuredTool = try tool.validateAndSetParameters(argumentsData)
        } catch {
            throw AISDKErrorV2.toolExecutionFailed(
                tool: toolCall.name,
                reason: "Invalid parameters: \(error.localizedDescription)"
            )
        }

        // Execute with timeout - capture the configured tool
        let toolToExecute = configuredTool
        let (content, _) = try await TimeoutExecutor(policy: timeout).execute(
            timeout: timeout.operationTimeout,
            operationName: "tool:\(toolCall.name)"
        ) {
            try await toolToExecute.execute()
        }

        return content
    }

    /// Check if the agent should stop based on the current step result
    ///
    /// - Parameters:
    ///   - result: The current step result
    ///   - accumulatedTokens: Total tokens used so far (for O(1) token budget check)
    /// - Returns: Whether to stop the agent loop
    private func shouldStop(_ result: AIStepResult, accumulatedTokens: Int) -> Bool {
        switch stopCondition {
        case .stepCount(let max):
            // Safe comparison avoiding overflow with max - 1
            // stepHistory.count is the number of steps completed (1-indexed after append)
            return max <= 0 || stepHistory.count >= max
        case .noToolCalls:
            return result.toolCalls.isEmpty
        case .tokenBudget(let maxTokens):
            // Use pre-computed accumulated tokens for O(1) check
            return accumulatedTokens >= maxTokens
        case .custom(let predicate):
            return predicate(result)
        }
    }

    // MARK: - MainActor State Helpers

    /// Set observable processing state
    private func setObservableIsProcessing(_ processing: Bool) async {
        await MainActor.run {
            observableState.isProcessing = processing
        }
    }

    /// Set observable state to thinking with step index
    private func setObservableThinking(step: Int) async {
        await MainActor.run {
            observableState.state = .thinking
            observableState.currentStep = step
        }
    }

    /// Set observable state
    private func setObservableState(_ agentState: AgentState) async {
        await MainActor.run {
            observableState.state = agentState
        }
    }

    /// Set observable error state
    private func setObservableError(state agentState: AgentState, error: AISDKErrorV2) async {
        await MainActor.run {
            observableState.state = agentState
            observableState.error = error
        }
    }
}

// MARK: - AIAgentResult

/// The result of an AI agent execution
public struct AIAgentResult: Sendable {
    /// The final text response from the agent
    public let text: String

    /// All steps executed during the agent loop
    public let steps: [AIStepResult]

    /// The complete message history
    public let messages: [AIMessage]

    /// Total token usage across all steps
    public let usage: AIUsage

    public init(
        text: String,
        steps: [AIStepResult],
        messages: [AIMessage],
        usage: AIUsage
    ) {
        self.text = text
        self.steps = steps
        self.messages = messages
        self.usage = usage
    }
}

// MARK: - ObservableAgentState

/// Observable state wrapper for SwiftUI binding
///
/// This class bridges actor-isolated state to SwiftUI's observation system.
/// All properties are MainActor-isolated for safe UI access.
@Observable
public final class ObservableAgentState: @unchecked Sendable {
    /// Current state of the agent
    @MainActor public internal(set) var state: AgentState = .idle

    /// Current step index in the agent loop
    @MainActor public internal(set) var currentStep: Int = 0

    /// Last error that occurred (if any)
    @MainActor public internal(set) var error: AISDKErrorV2?

    /// Whether the agent is currently processing
    @MainActor public internal(set) var isProcessing: Bool = false

    public init() {}
}

// MARK: - AIOperation

/// Internal operation wrapper for the operation queue
///
/// This class wraps a pending operation and provides continuation-based
/// result delivery for async/await integration.
private final class AIOperation: @unchecked Sendable {
    /// The messages for this operation
    let messages: [AIMessage]

    /// The continuation for result delivery
    private var continuation: CheckedContinuation<AIAgentResult, Error>?

    /// Lock for thread-safe continuation access
    private let lock = NSLock()

    init(messages: [AIMessage]) {
        self.messages = messages
    }

    /// Await the result of this operation
    var result: AIAgentResult {
        get async throws {
            try await withCheckedThrowingContinuation { cont in
                lock.lock()
                self.continuation = cont
                lock.unlock()
            }
        }
    }

    /// Complete the operation with a successful result
    func complete(with result: AIAgentResult) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: result)
    }

    /// Fail the operation with an error
    func fail(with error: Error) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}

// MARK: - StopCondition

/// Stop conditions for the agent loop
public enum StopCondition: Sendable {
    /// Stop after a maximum number of steps
    case stepCount(Int)

    /// Stop when no tool calls are made
    case noToolCalls

    /// Stop when token budget is exceeded
    case tokenBudget(maxTokens: Int)

    /// Custom stop condition
    case custom(@Sendable (AIStepResult) -> Bool)
}

// MARK: - AIStreamingOperation

/// Internal operation wrapper for streaming operations
///
/// This class wraps a pending streaming operation and provides
/// continuation-based completion signaling.
private final class AIStreamingOperation: @unchecked Sendable {
    /// The messages for this operation
    let messages: [AIMessage]

    /// The stream continuation for emitting events
    let continuation: SafeAsyncStream.Continuation<AIStreamEvent>

    /// Completion continuation for signaling when done
    private var completionContinuation: CheckedContinuation<Void, Error>?

    /// Lock for thread-safe access
    private let lock = NSLock()

    /// Whether the operation has completed
    private var isCompleted = false

    init(messages: [AIMessage], continuation: SafeAsyncStream.Continuation<AIStreamEvent>) {
        self.messages = messages
        self.continuation = continuation
    }

    /// Wait for the operation to complete
    func waitForCompletion() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            lock.lock()
            if isCompleted {
                lock.unlock()
                cont.resume()
            } else {
                completionContinuation = cont
                lock.unlock()
            }
        }
    }

    /// Mark the operation as completed
    func markCompleted(with error: Error?) {
        lock.lock()
        isCompleted = true
        let cont = completionContinuation
        completionContinuation = nil
        lock.unlock()

        if let error = error {
            cont?.resume(throwing: error)
        } else {
            cont?.resume()
        }
    }
}

// MARK: - ToolCallBuilder

/// Helper for building tool calls from streaming deltas
private final class ToolCallBuilder: @unchecked Sendable {
    let id: String
    let name: String
    private var arguments: String = ""
    private let lock = NSLock()

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    func appendArguments(_ delta: String) {
        lock.lock()
        arguments += delta
        lock.unlock()
    }

    func build() -> AIToolCallResult {
        lock.lock()
        let args = arguments
        lock.unlock()
        return AIToolCallResult(id: id, name: name, arguments: args)
    }
}

