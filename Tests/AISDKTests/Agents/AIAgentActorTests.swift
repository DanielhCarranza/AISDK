//
//  AIAgentActorTests.swift
//  AISDKTests
//
//  Tests for AIAgentActor core functionality
//

import XCTest
@testable import AISDK

final class AIAgentActorTests: XCTestCase {

    // MARK: - Test Helpers

    /// Mock language model for testing
    private class MockLanguageModel: AILanguageModel, @unchecked Sendable {
        let provider = "mock"
        let modelId = "mock-model"
        let capabilities: LLMCapabilities = []

        var generateTextHandler: ((AITextRequest) async throws -> AITextResult)?
        var generateTextCallCount = 0
        var lastRequest: AITextRequest?

        // Track when calls complete for timing tests
        var callCompletions: [Date] = []
        let lock = NSLock()

        func generateText(request: AITextRequest) async throws -> AITextResult {
            lock.lock()
            generateTextCallCount += 1
            lastRequest = request
            lock.unlock()

            if let handler = generateTextHandler {
                let result = try await handler(request)
                lock.lock()
                callCompletions.append(Date())
                lock.unlock()
                return result
            }

            let result = AITextResult(
                text: "Mock response",
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .stop
            )

            lock.lock()
            callCompletions.append(Date())
            lock.unlock()

            return result
        }

        func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("Mock"))
                continuation.yield(.finish(finishReason: .stop, usage: AIUsage.zero))
                continuation.finish()
            }
        }

        func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    // MARK: - Initialization Tests

    func test_actor_initialization() async throws {
        // Given
        let model = MockLanguageModel()

        // When
        let agent = AIAgentActor(
            model: model,
            tools: [],
            instructions: "You are a helpful assistant.",
            stopCondition: .stepCount(10),
            timeout: .default,
            maxToolRounds: 5,
            name: "TestAgent"
        )

        // Then
        XCTAssertEqual(agent.name, "TestAgent")
        XCTAssertFalse(agent.agentId.isEmpty)

        // Verify initial state
        let state = await agent.state
        XCTAssertEqual(state, .idle)

        let messages = await agent.messages
        XCTAssertTrue(messages.isEmpty)

        let steps = await agent.steps
        XCTAssertTrue(steps.isEmpty)
    }

    func test_actor_initialization_with_defaults() async throws {
        // Given
        let model = MockLanguageModel()

        // When
        let agent = AIAgentActor(model: model)

        // Then
        XCTAssertNil(agent.name)
        XCTAssertFalse(agent.agentId.isEmpty)

        let state = await agent.state
        XCTAssertEqual(state, .idle)
    }

    func test_actor_initialization_with_custom_agentId() async throws {
        // Given
        let model = MockLanguageModel()
        let customId = "custom-agent-123"

        // When
        let agent = AIAgentActor(
            model: model,
            agentId: customId
        )

        // Then
        XCTAssertEqual(agent.agentId, customId)
    }

    // MARK: - Observable State Tests

    func test_observable_state_accessible() async throws {
        // Given
        let model = MockLanguageModel()
        let agent = AIAgentActor(model: model)

        // When - Access observable state from nonisolated context
        let observableState = agent.observableState

        // Then - Verify state is accessible on MainActor
        await MainActor.run {
            XCTAssertEqual(observableState.state, .idle)
            XCTAssertEqual(observableState.currentStep, 0)
            XCTAssertNil(observableState.error)
            XCTAssertFalse(observableState.isProcessing)
        }
    }

    func test_observable_state_updates_during_execution() async throws {
        // Given
        let model = MockLanguageModel()
        var stateChanges: [AgentState] = []
        var isProcessingChanges: [Bool] = []

        model.generateTextHandler = { _ in
            // Simulate some processing time
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            return AITextResult(
                text: "Response",
                toolCalls: [],
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .stop
            )
        }

        let agent = AIAgentActor(model: model)
        let observableState = agent.observableState

        // Capture initial state
        await MainActor.run {
            stateChanges.append(observableState.state)
            isProcessingChanges.append(observableState.isProcessing)
        }

        // When
        let _ = try await agent.execute(messages: [.user("Hello")])

        // Then - Final state should be idle
        await MainActor.run {
            XCTAssertEqual(observableState.state, .idle)
            XCTAssertFalse(observableState.isProcessing)
        }
    }

    // MARK: - Operation Queue Tests

    func test_operation_queue_serializes_requests() async throws {
        // Given
        let model = MockLanguageModel()
        var callOrder: [Int] = []
        let lock = NSLock()

        model.generateTextHandler = { request in
            // Extract call order from message
            let messageText = request.messages.last?.content.textValue ?? ""

            // Add delay to ensure sequential processing
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms

            lock.lock()
            if messageText.contains("1") {
                callOrder.append(1)
            } else if messageText.contains("2") {
                callOrder.append(2)
            } else if messageText.contains("3") {
                callOrder.append(3)
            }
            lock.unlock()

            return AITextResult(
                text: "Response to \(messageText)",
                toolCalls: [],
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .stop
            )
        }

        let agent = AIAgentActor(model: model)

        // When - Execute calls sequentially (they should be queued)
        async let result1 = agent.execute(messages: [.user("Message 1")])

        // Small delay to ensure first request is queued
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        async let result2 = agent.execute(messages: [.user("Message 2")])

        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        async let result3 = agent.execute(messages: [.user("Message 3")])

        // Wait for all results
        _ = try await (result1, result2, result3)

        // Then - Calls should be processed in order
        lock.lock()
        let finalOrder = callOrder
        lock.unlock()

        XCTAssertEqual(finalOrder, [1, 2, 3], "Requests should be processed in order")
    }

    func test_concurrent_execute_calls_queued() async throws {
        // Given
        let model = MockLanguageModel()
        let startTime = Date()
        let processingTime: UInt64 = 50_000_000 // 50ms per call

        model.generateTextHandler = { _ in
            try await Task.sleep(nanoseconds: processingTime)
            return AITextResult(
                text: "Response",
                toolCalls: [],
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .stop
            )
        }

        let agent = AIAgentActor(model: model)

        // When - Launch multiple concurrent requests
        async let result1 = agent.execute(messages: [.user("1")])
        async let result2 = agent.execute(messages: [.user("2")])
        async let result3 = agent.execute(messages: [.user("3")])

        // Wait for all results
        _ = try await (result1, result2, result3)

        let endTime = Date()
        let totalTime = endTime.timeIntervalSince(startTime)

        // Then - Total time should be at least 3x processing time (serialized)
        // Allow some tolerance for overhead
        let expectedMinTime = Double(3 * processingTime) / 1_000_000_000.0 * 0.8 // 80% of expected
        XCTAssertGreaterThan(totalTime, expectedMinTime,
            "Requests should be serialized, total time (\(totalTime)s) should be > \(expectedMinTime)s")

        // Verify all calls were made
        XCTAssertEqual(model.generateTextCallCount, 3)
    }

    // MARK: - Execution Tests

    func test_execute_returns_result() async throws {
        // Given
        let model = MockLanguageModel()
        model.generateTextHandler = { _ in
            AITextResult(
                text: "Hello! How can I help you?",
                toolCalls: [],
                usage: AIUsage(promptTokens: 15, completionTokens: 8),
                finishReason: .stop
            )
        }

        let agent = AIAgentActor(
            model: model,
            instructions: "Be helpful."
        )

        // When
        let result = try await agent.execute(messages: [.user("Hi")])

        // Then
        XCTAssertEqual(result.text, "Hello! How can I help you?")
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.usage.promptTokens, 15)
        XCTAssertEqual(result.usage.completionTokens, 8)

        // Messages should include system, user, and assistant
        XCTAssertEqual(result.messages.count, 3)
    }

    func test_execute_updates_message_history() async throws {
        // Given
        let model = MockLanguageModel()
        let agent = AIAgentActor(model: model)

        // When
        _ = try await agent.execute(messages: [.user("Hello")])

        // Then
        let messages = await agent.messages
        XCTAssertEqual(messages.count, 2) // user + assistant
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[1].role, .assistant)
    }

    // MARK: - Stop Condition Tests

    func test_stop_condition_step_count() async throws {
        // Given
        let model = MockLanguageModel()
        var callCount = 0

        model.generateTextHandler = { _ in
            callCount += 1
            // Always return tool calls to continue the loop
            return AITextResult(
                text: "Thinking...",
                toolCalls: [AIToolCallResult(id: "1", name: "test", arguments: "{}")],
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .toolCalls
            )
        }

        let agent = AIAgentActor(
            model: model,
            stopCondition: .stepCount(3)
        )

        // When - This should stop after 3 steps due to stop condition
        // Note: Without actual tool implementation, it will hit max steps
        do {
            _ = try await agent.execute(messages: [.user("Test")])
        } catch {
            // Expected - tools not found
        }

        // Then - Should have attempted up to 3 steps
        let steps = await agent.steps
        XCTAssertLessThanOrEqual(steps.count, 3)
    }

    func test_stop_condition_no_tool_calls() async throws {
        // Given
        let model = MockLanguageModel()

        model.generateTextHandler = { _ in
            // Return no tool calls - should stop immediately
            AITextResult(
                text: "Done",
                toolCalls: [],
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .stop
            )
        }

        let agent = AIAgentActor(
            model: model,
            stopCondition: .noToolCalls
        )

        // When
        let result = try await agent.execute(messages: [.user("Test")])

        // Then - Should stop after first step
        XCTAssertEqual(result.steps.count, 1)
        XCTAssertEqual(result.text, "Done")
    }

    // MARK: - Reset Tests

    func test_reset_clears_state() async throws {
        // Given
        let model = MockLanguageModel()
        let agent = AIAgentActor(model: model)

        // Execute to populate history
        _ = try await agent.execute(messages: [.user("Hello")])

        // Verify state is populated
        var messages = await agent.messages
        XCTAssertFalse(messages.isEmpty)

        // When
        await agent.reset()

        // Then
        messages = await agent.messages
        XCTAssertTrue(messages.isEmpty)

        let steps = await agent.steps
        XCTAssertTrue(steps.isEmpty)

        let state = await agent.state
        XCTAssertEqual(state, .idle)

        await MainActor.run {
            XCTAssertEqual(agent.observableState.state, .idle)
            XCTAssertEqual(agent.observableState.currentStep, 0)
            XCTAssertNil(agent.observableState.error)
            XCTAssertFalse(agent.observableState.isProcessing)
        }
    }

    // MARK: - Set Messages Tests

    func test_setMessages_updates_history() async throws {
        // Given
        let model = MockLanguageModel()
        let agent = AIAgentActor(model: model)

        let newMessages: [AIMessage] = [
            .system("You are helpful"),
            .user("Previous question"),
            .assistant("Previous answer")
        ]

        // When
        await agent.setMessages(newMessages)

        // Then
        let messages = await agent.messages
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[1].role, .user)
        XCTAssertEqual(messages[2].role, .assistant)
    }
}

// MARK: - AIAgentResult Tests

final class AIAgentResultTests: XCTestCase {

    func test_result_initialization() {
        // Given
        let steps = [
            AIStepResult(stepIndex: 0, text: "Step 1"),
            AIStepResult(stepIndex: 1, text: "Step 2")
        ]
        let messages: [AIMessage] = [.user("Hi"), .assistant("Hello")]
        let usage = AIUsage(promptTokens: 20, completionTokens: 10)

        // When
        let result = AIAgentResult(
            text: "Final response",
            steps: steps,
            messages: messages,
            usage: usage
        )

        // Then
        XCTAssertEqual(result.text, "Final response")
        XCTAssertEqual(result.steps.count, 2)
        XCTAssertEqual(result.messages.count, 2)
        XCTAssertEqual(result.usage.totalTokens, 30)
    }
}

// MARK: - StopCondition Tests

final class StopConditionTests: XCTestCase {

    func test_stepCount_condition() {
        // Given
        let condition = StopCondition.stepCount(5)

        // Then - Just verify it compiles and can be used
        switch condition {
        case .stepCount(let count):
            XCTAssertEqual(count, 5)
        default:
            XCTFail("Expected stepCount condition")
        }
    }

    func test_noToolCalls_condition() {
        // Given
        let condition = StopCondition.noToolCalls

        // Then
        switch condition {
        case .noToolCalls:
            break // Expected
        default:
            XCTFail("Expected noToolCalls condition")
        }
    }

    func test_tokenBudget_condition() {
        // Given
        let condition = StopCondition.tokenBudget(maxTokens: 1000)

        // Then
        switch condition {
        case .tokenBudget(let max):
            XCTAssertEqual(max, 1000)
        default:
            XCTFail("Expected tokenBudget condition")
        }
    }

    func test_custom_condition() {
        // Given
        let condition = StopCondition.custom { result in
            result.text.contains("STOP")
        }

        // Then
        switch condition {
        case .custom(let predicate):
            let shouldStop = predicate(AIStepResult(stepIndex: 0, text: "STOP"))
            XCTAssertTrue(shouldStop)

            let shouldNotStop = predicate(AIStepResult(stepIndex: 0, text: "Continue"))
            XCTAssertFalse(shouldNotStop)
        default:
            XCTFail("Expected custom condition")
        }
    }
}

// MARK: - ObservableAgentState Tests

final class ObservableAgentStateTests: XCTestCase {

    @MainActor
    func test_observable_state_initialization() {
        // Given/When
        let state = ObservableAgentState()

        // Then
        XCTAssertEqual(state.state, .idle)
        XCTAssertEqual(state.currentStep, 0)
        XCTAssertNil(state.error)
        XCTAssertFalse(state.isProcessing)
    }

    @MainActor
    func test_observable_state_is_sendable() {
        // This test verifies ObservableAgentState conforms to Sendable
        // by passing it across isolation boundaries
        let state = ObservableAgentState()

        Task.detached {
            // Access nonisolated - this should compile if Sendable
            _ = type(of: state)
        }
    }
}

// MARK: - Streaming Tests

final class AIAgentActorStreamingTests: XCTestCase {

    // MARK: - Test Helpers

    /// Mock language model with streaming support
    private class MockStreamingLanguageModel: AILanguageModel, @unchecked Sendable {
        let provider = "mock"
        let modelId = "mock-streaming-model"
        let capabilities: LLMCapabilities = []

        var streamTextHandler: ((AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>)?
        var generateTextHandler: ((AITextRequest) async throws -> AITextResult)?
        var streamCallCount = 0
        let lock = NSLock()

        func generateText(request: AITextRequest) async throws -> AITextResult {
            if let handler = generateTextHandler {
                return try await handler(request)
            }
            return AITextResult(
                text: "Mock response",
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .stop
            )
        }

        func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
            lock.lock()
            streamCallCount += 1
            lock.unlock()

            if let handler = streamTextHandler {
                return handler(request)
            }

            // Default: emit text deltas then finish
            return AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("Hello"))
                continuation.yield(.textDelta(" "))
                continuation.yield(.textDelta("World"))
                continuation.yield(.finish(finishReason: .stop, usage: AIUsage(promptTokens: 10, completionTokens: 5)))
                continuation.finish()
            }
        }

        func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    // MARK: - Basic Streaming Tests

    func test_streamExecute_emits_start_event() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        let agent = AIAgentActor(model: model)

        // When
        var events: [AIStreamEvent] = []
        for try await event in agent.streamExecute(messages: [.user("Hello")]) {
            events.append(event)
        }

        // Then - First event should be start
        guard case .start(let metadata) = events.first else {
            XCTFail("First event should be .start")
            return
        }
        XCTAssertEqual(metadata?.model, "mock-streaming-model")
        XCTAssertEqual(metadata?.provider, "mock")
    }

    func test_streamExecute_emits_textDelta_events() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        let agent = AIAgentActor(model: model)

        // When
        var textDeltas: [String] = []
        for try await event in agent.streamExecute(messages: [.user("Hello")]) {
            if case .textDelta(let delta) = event {
                textDeltas.append(delta)
            }
        }

        // Then
        XCTAssertEqual(textDeltas, ["Hello", " ", "World"])
    }

    func test_streamExecute_emits_stepStart_event() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        let agent = AIAgentActor(model: model)

        // When
        var stepStartEvents: [Int] = []
        for try await event in agent.streamExecute(messages: [.user("Hello")]) {
            if case .stepStart(let stepIndex) = event {
                stepStartEvents.append(stepIndex)
            }
        }

        // Then - Should have at least one step start
        XCTAssertEqual(stepStartEvents, [0])
    }

    func test_streamExecute_emits_stepFinish_event() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        let agent = AIAgentActor(model: model)

        // When
        var stepFinishEvents: [(Int, AIStepResult)] = []
        for try await event in agent.streamExecute(messages: [.user("Hello")]) {
            if case .stepFinish(let stepIndex, let result) = event {
                stepFinishEvents.append((stepIndex, result))
            }
        }

        // Then
        XCTAssertEqual(stepFinishEvents.count, 1)
        XCTAssertEqual(stepFinishEvents[0].0, 0)
        XCTAssertEqual(stepFinishEvents[0].1.text, "Hello World")
    }

    func test_streamExecute_emits_finish_event() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        let agent = AIAgentActor(model: model)

        // When
        var finishEvents: [(AIFinishReason, AIUsage)] = []
        for try await event in agent.streamExecute(messages: [.user("Hello")]) {
            if case .finish(let reason, let usage) = event {
                finishEvents.append((reason, usage))
            }
        }

        // Then - Should have exactly one finish event at the end
        XCTAssertEqual(finishEvents.count, 1)
        XCTAssertEqual(finishEvents[0].0, .stop)
    }

    func test_streamExecute_emits_usage_event() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        let agent = AIAgentActor(model: model)

        // When
        var usageEvents: [AIUsage] = []
        for try await event in agent.streamExecute(messages: [.user("Hello")]) {
            if case .usage(let usage) = event {
                usageEvents.append(usage)
            }
        }

        // Then
        XCTAssertGreaterThanOrEqual(usageEvents.count, 1)
    }

    // MARK: - Tool Call Streaming Tests

    func test_streamExecute_emits_toolCallStart_event() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        model.streamTextHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.toolCallStart(id: "tool-1", name: "search"))
                continuation.yield(.toolCallDelta(id: "tool-1", argumentsDelta: "{\"query\":"))
                continuation.yield(.toolCallDelta(id: "tool-1", argumentsDelta: "\"test\"}"))
                continuation.yield(.toolCall(id: "tool-1", name: "search", arguments: "{\"query\":\"test\"}"))
                continuation.yield(.finish(finishReason: .toolCalls, usage: AIUsage.zero))
                continuation.finish()
            }
        }

        let agent = AIAgentActor(model: model, stopCondition: .stepCount(1))

        // When
        var toolCallStartEvents: [(String, String)] = []
        for try await event in agent.streamExecute(messages: [.user("Search for something")]) {
            if case .toolCallStart(let id, let name) = event {
                toolCallStartEvents.append((id, name))
            }
        }

        // Then
        XCTAssertEqual(toolCallStartEvents.count, 1)
        XCTAssertEqual(toolCallStartEvents[0].0, "tool-1")
        XCTAssertEqual(toolCallStartEvents[0].1, "search")
    }

    func test_streamExecute_emits_toolCallDelta_events() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        model.streamTextHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.toolCallStart(id: "tool-1", name: "search"))
                continuation.yield(.toolCallDelta(id: "tool-1", argumentsDelta: "{\"q\":"))
                continuation.yield(.toolCallDelta(id: "tool-1", argumentsDelta: "\"test\"}"))
                continuation.yield(.toolCall(id: "tool-1", name: "search", arguments: "{\"q\":\"test\"}"))
                continuation.yield(.finish(finishReason: .toolCalls, usage: AIUsage.zero))
                continuation.finish()
            }
        }

        let agent = AIAgentActor(model: model, stopCondition: .stepCount(1))

        // When
        var toolCallDeltas: [(String, String)] = []
        for try await event in agent.streamExecute(messages: [.user("Search")]) {
            if case .toolCallDelta(let id, let delta) = event {
                toolCallDeltas.append((id, delta))
            }
        }

        // Then
        XCTAssertEqual(toolCallDeltas.count, 2)
        XCTAssertEqual(toolCallDeltas[0].1, "{\"q\":")
        XCTAssertEqual(toolCallDeltas[1].1, "\"test\"}")
    }

    func test_streamExecute_emits_toolCall_event() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        model.streamTextHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.toolCallStart(id: "tool-1", name: "search"))
                continuation.yield(.toolCall(id: "tool-1", name: "search", arguments: "{\"query\":\"test\"}"))
                continuation.yield(.finish(finishReason: .toolCalls, usage: AIUsage.zero))
                continuation.finish()
            }
        }

        let agent = AIAgentActor(model: model, stopCondition: .stepCount(1))

        // When
        var toolCallEvents: [(String, String, String)] = []
        for try await event in agent.streamExecute(messages: [.user("Search")]) {
            if case .toolCall(let id, let name, let args) = event {
                toolCallEvents.append((id, name, args))
            }
        }

        // Then
        XCTAssertGreaterThanOrEqual(toolCallEvents.count, 1)
        XCTAssertEqual(toolCallEvents[0].0, "tool-1")
        XCTAssertEqual(toolCallEvents[0].1, "search")
        XCTAssertEqual(toolCallEvents[0].2, "{\"query\":\"test\"}")
    }

    // MARK: - Multi-Step Streaming Tests

    func test_streamExecute_multi_step_emits_multiple_stepStart_events() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        var callCount = 0

        model.streamTextHandler = { _ in
            callCount += 1
            if callCount == 1 {
                // First call: return tool call
                return AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta("Let me search..."))
                    continuation.yield(.toolCallStart(id: "tool-1", name: "mock_tool"))
                    continuation.yield(.toolCall(id: "tool-1", name: "mock_tool", arguments: "{}"))
                    continuation.yield(.finish(finishReason: .toolCalls, usage: AIUsage(promptTokens: 5, completionTokens: 3)))
                    continuation.finish()
                }
            } else {
                // Second call: return final response
                return AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta("Done!"))
                    continuation.yield(.finish(finishReason: .stop, usage: AIUsage(promptTokens: 10, completionTokens: 5)))
                    continuation.finish()
                }
            }
        }

        let agent = AIAgentActor(model: model, stopCondition: .stepCount(3))

        // When
        var stepStartIndices: [Int] = []
        for try await event in agent.streamExecute(messages: [.user("Do something")]) {
            if case .stepStart(let stepIndex) = event {
                stepStartIndices.append(stepIndex)
            }
        }

        // Then - Should have step 0 and step 1
        XCTAssertEqual(stepStartIndices, [0, 1])
    }

    // MARK: - Error Handling Tests

    func test_streamExecute_emits_error_event_on_model_failure() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        let expectedError = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Model failed"])

        model.streamTextHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("Starting..."))
                continuation.yield(.error(expectedError))
                continuation.finish(throwing: expectedError)
            }
        }

        let agent = AIAgentActor(model: model)

        // When
        var errorEvents: [Error] = []
        do {
            for try await event in agent.streamExecute(messages: [.user("Hello")]) {
                if case .error(let error) = event {
                    errorEvents.append(error)
                }
            }
        } catch {
            // Expected - stream throws after error
        }

        // Then
        XCTAssertEqual(errorEvents.count, 1)
    }

    // MARK: - Observable State During Streaming Tests

    func test_streamExecute_updates_observable_state() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        model.streamTextHandler = { _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("Response"))
                continuation.yield(.finish(finishReason: .stop, usage: AIUsage.zero))
                continuation.finish()
            }
        }

        let agent = AIAgentActor(model: model)
        let observableState = agent.observableState

        // Capture initial state
        let initialIsProcessing = await MainActor.run { observableState.isProcessing }
        XCTAssertFalse(initialIsProcessing)

        // When - Start streaming
        let stream = agent.streamExecute(messages: [.user("Hello")])

        // Consume stream
        for try await _ in stream {
            // Just consume
        }

        // Allow time for async state updates to propagate
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Then - Final state should be idle and not processing
        await MainActor.run {
            XCTAssertEqual(observableState.state, .idle)
            XCTAssertFalse(observableState.isProcessing)
        }
    }

    // MARK: - Operation Queue Tests for Streaming

    func test_streamExecute_operations_are_serialized() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        var callOrder: [Int] = []
        let lock = NSLock()

        model.streamTextHandler = { request in
            AsyncThrowingStream { continuation in
                Task {
                    // Add delay to ensure serialization
                    try? await Task.sleep(nanoseconds: 30_000_000) // 30ms

                    let messageText = request.messages.last?.content.textValue ?? ""
                    lock.lock()
                    if messageText.contains("1") {
                        callOrder.append(1)
                    } else if messageText.contains("2") {
                        callOrder.append(2)
                    }
                    lock.unlock()

                    continuation.yield(.textDelta("Response"))
                    continuation.yield(.finish(finishReason: .stop, usage: AIUsage.zero))
                    continuation.finish()
                }
            }
        }

        let agent = AIAgentActor(model: model)

        // When - Execute two streams concurrently
        async let stream1: () = {
            for try await _ in agent.streamExecute(messages: [.user("Message 1")]) {}
        }()

        // Small delay to ensure first is queued first
        try await Task.sleep(nanoseconds: 5_000_000) // 5ms

        async let stream2: () = {
            for try await _ in agent.streamExecute(messages: [.user("Message 2")]) {}
        }()

        // Wait for both
        _ = try await (stream1, stream2)

        // Then - Calls should be serialized (order 1, 2)
        lock.lock()
        let finalOrder = callOrder
        lock.unlock()

        XCTAssertEqual(finalOrder, [1, 2], "Streaming operations should be serialized")
    }

    // MARK: - Cancellation Tests

    func test_streamExecute_handles_task_cancellation() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        model.streamTextHandler = { _ in
            AsyncThrowingStream { continuation in
                Task {
                    for i in 0..<100 {
                        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms each
                        continuation.yield(.textDelta("Chunk \(i)"))
                    }
                    continuation.yield(.finish(finishReason: .stop, usage: AIUsage.zero))
                    continuation.finish()
                }
            }
        }

        let agent = AIAgentActor(model: model)

        // When - Start streaming and cancel after a short time
        var receivedCount = 0
        let task = Task {
            for try await event in agent.streamExecute(messages: [.user("Hello")]) {
                if case .textDelta = event {
                    receivedCount += 1
                }
                if receivedCount >= 3 {
                    break // Early exit
                }
            }
        }

        // Wait for task to complete
        try await task.value

        // Then - Should have received some events but not all
        XCTAssertGreaterThanOrEqual(receivedCount, 3)
        XCTAssertLessThan(receivedCount, 100)
    }

    // MARK: - Message History Tests

    func test_streamExecute_updates_message_history() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        let agent = AIAgentActor(model: model)

        // When
        for try await _ in agent.streamExecute(messages: [.user("Hello")]) {
            // Consume
        }

        // Then
        let messages = await agent.messages
        XCTAssertEqual(messages.count, 2) // user + assistant
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertEqual(messages[1].content.textValue, "Hello World")
    }

    func test_streamExecute_with_instructions_prepends_system_message() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        let agent = AIAgentActor(
            model: model,
            instructions: "You are helpful."
        )

        // When
        for try await _ in agent.streamExecute(messages: [.user("Hello")]) {
            // Consume
        }

        // Then
        let messages = await agent.messages
        XCTAssertEqual(messages.count, 3) // system + user + assistant
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertEqual(messages[0].content.textValue, "You are helpful.")
    }

    // MARK: - Step History Tests

    func test_streamExecute_updates_step_history() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        let agent = AIAgentActor(model: model)

        // When
        for try await _ in agent.streamExecute(messages: [.user("Hello")]) {
            // Consume
        }

        // Then
        let steps = await agent.steps
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].stepIndex, 0)
        XCTAssertEqual(steps[0].text, "Hello World")
    }
}
