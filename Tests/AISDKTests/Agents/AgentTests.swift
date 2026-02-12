//
//  AgentTests.swift
//  AISDKTests
//
//  Tests for Agent core functionality
//

import XCTest
@testable import AISDK

final class AgentTests: XCTestCase {

    // MARK: - Test Helpers

    /// Mock language model for testing
    private class MockLanguageModel: LLM, @unchecked Sendable {
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
        let agent = Agent(
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
        let agent = Agent(model: model)

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
        let agent = Agent(
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
        let agent = Agent(model: model)

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
        var stateChanges: [LegacyAgentState] = []
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

        let agent = Agent(model: model)
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

        let agent = Agent(model: model)

        // When - Execute calls sequentially (they should be queued)
        async let result1 = agent.execute(messages: [.user("LegacyMessage 1")])

        // Small delay to ensure first request is queued
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        async let result2 = agent.execute(messages: [.user("LegacyMessage 2")])

        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        async let result3 = agent.execute(messages: [.user("LegacyMessage 3")])

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

        let agent = Agent(model: model)

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

        let agent = Agent(
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
        let agent = Agent(model: model)

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
                toolCalls: [ToolCallResult(id: "1", name: "test", arguments: "{}")],
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .toolCalls
            )
        }

        let agent = Agent(
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

        let agent = Agent(
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
        let agent = Agent(model: model)

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
        let agent = Agent(model: model)

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

    func test_tokenBudget_condition_stops_when_budget_exceeded() async throws {
        // Given
        class MockLanguageModel: LLM, @unchecked Sendable {
            let provider = "mock"
            let modelId = "mock-model"
            let capabilities: LLMCapabilities = []
            var callCount = 0
            let lock = NSLock()
            let maxCalls = 10 // Fail-safe to prevent infinite loop if token budget logic regresses

            func generateText(request: AITextRequest) async throws -> AITextResult {
                lock.lock()
                callCount += 1
                let currentCall = callCount
                lock.unlock()

                // Fail-safe: stop returning tool calls after maxCalls to prevent hanging
                if currentCall > maxCalls {
                    return AITextResult(
                        text: "Fail-safe triggered - no more tool calls",
                        toolCalls: [],
                        usage: AIUsage(promptTokens: 50, completionTokens: 50),
                        finishReason: .stop
                    )
                }

                // Return tool calls to keep the loop going until budget is exceeded
                // Each step uses 100 tokens total (50 prompt + 50 completion)
                return AITextResult(
                    text: "Step \(currentCall)",
                    toolCalls: [ToolCallResult(id: "call-\(currentCall)", name: "mock_tool", arguments: "{}")],
                    usage: AIUsage(promptTokens: 50, completionTokens: 50),
                    finishReason: .toolCalls
                )
            }

            func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }

            func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        }

        let model = MockLanguageModel()

        // Stop when total tokens >= 250
        // Token accumulation: step0=100, step1=200, step2=300
        // Budget check happens after step with accumulated tokens
        // At step 2 completion: 300 >= 250, should stop
        let agent = Agent(
            model: model,
            stopCondition: .tokenBudget(maxTokens: 250)
        )

        // When - Execute (tool errors are swallowed and loop continues until stop condition)
        do {
            _ = try await agent.execute(messages: [.user("Test")])
        } catch {
            // Tool not found errors are handled internally
        }

        // Then - Should have stopped due to token budget
        let steps = await agent.steps
        // The agent loop should stop when accumulated tokens >= 250
        // Step 0: 100 tokens, < 250, continue
        // Step 1: 200 tokens, < 250, continue
        // Step 2: 300 tokens, >= 250, stop
        XCTAssertEqual(steps.count, 3, "Should stop after exactly 3 steps when token budget (250) exceeded (300 tokens)")

        // Verify total usage matches expectation
        let totalTokens = steps.reduce(0) { $0 + $1.usage.totalTokens }
        XCTAssertEqual(totalTokens, 300, "Total tokens should be 300 (3 steps x 100 tokens)")
        XCTAssertGreaterThanOrEqual(totalTokens, 250, "Total tokens should exceed budget")

        // Verify model was called exactly 3 times
        model.lock.lock()
        let callCount = model.callCount
        model.lock.unlock()
        XCTAssertEqual(callCount, 3, "Model should have been called 3 times")
    }

    func test_stepCount_condition_stops_at_max_steps() async throws {
        // Given
        class MockLanguageModel: LLM, @unchecked Sendable {
            let provider = "mock"
            let modelId = "mock-model"
            let capabilities: LLMCapabilities = []
            var callCount = 0
            let lock = NSLock()

            func generateText(request: AITextRequest) async throws -> AITextResult {
                lock.lock()
                callCount += 1
                let currentCall = callCount
                lock.unlock()

                // Always return tool calls to keep the loop going
                return AITextResult(
                    text: "Step \(currentCall)",
                    toolCalls: [ToolCallResult(id: "call-\(currentCall)", name: "mock_tool", arguments: "{}")],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            }

            func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }

            func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        }

        let model = MockLanguageModel()

        // Stop after exactly 2 steps
        let agent = Agent(
            model: model,
            stopCondition: .stepCount(2)
        )

        // When
        do {
            _ = try await agent.execute(messages: [.user("Test")])
        } catch {
            // Tool errors are handled internally
        }

        // Then
        let steps = await agent.steps
        XCTAssertEqual(steps.count, 2, "Should stop after exactly 2 steps with stepCount(2)")

        model.lock.lock()
        let callCount = model.callCount
        model.lock.unlock()
        XCTAssertEqual(callCount, 2, "Model should have been called exactly 2 times")
    }

    func test_stepCount_zero_stops_immediately() async throws {
        // Given
        class MockLanguageModel: LLM, @unchecked Sendable {
            let provider = "mock"
            let modelId = "mock-model"
            let capabilities: LLMCapabilities = []
            var callCount = 0

            func generateText(request: AITextRequest) async throws -> AITextResult {
                callCount += 1
                return AITextResult(
                    text: "Response",
                    toolCalls: [ToolCallResult(id: "call-1", name: "mock_tool", arguments: "{}")],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            }

            func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }

            func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        }

        let model = MockLanguageModel()

        // stepCount(0) should stop immediately after first step
        let agent = Agent(
            model: model,
            stopCondition: .stepCount(0)
        )

        // When
        do {
            _ = try await agent.execute(messages: [.user("Test")])
        } catch {
            // Tool errors are handled internally
        }

        // Then - Edge case: stepCount(0) means max <= 0, should stop after 1 step
        let steps = await agent.steps
        XCTAssertEqual(steps.count, 1, "stepCount(0) should stop after 1 step (edge case)")
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

    // MARK: - State Stream Tests

    @MainActor
    func test_stateStream_emits_current_state_immediately() async throws {
        // Given
        let observableState = ObservableAgentState()
        observableState.state = .thinking

        // When
        var receivedStates: [LegacyAgentState] = []
        let task = Task {
            for await state in observableState.stateStream {
                receivedStates.append(state)
                if receivedStates.count >= 1 {
                    break
                }
            }
        }

        // Wait for subscription to receive initial state
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        task.cancel()

        // Then - Should have received the current state immediately
        XCTAssertEqual(receivedStates.count, 1)
        XCTAssertEqual(receivedStates.first, .thinking)
    }

    @MainActor
    func test_stateStream_emits_state_changes() async throws {
        // Given
        let observableState = ObservableAgentState()
        var receivedStates: [LegacyAgentState] = []

        let task = Task {
            for await state in observableState.stateStream {
                receivedStates.append(state)
                if receivedStates.count >= 4 {
                    break
                }
            }
        }

        // When - Wait for subscription, then change states
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms - wait for subscription
        observableState.state = .thinking
        try await Task.sleep(nanoseconds: 10_000_000)
        observableState.state = .executingTool("search")
        try await Task.sleep(nanoseconds: 10_000_000)
        observableState.state = .idle

        // Wait for task to collect states
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        task.cancel()

        // Then
        XCTAssertEqual(receivedStates.count, 4)
        XCTAssertEqual(receivedStates[0], .idle) // initial
        XCTAssertEqual(receivedStates[1], .thinking)
        XCTAssertEqual(receivedStates[2], .executingTool("search"))
        XCTAssertEqual(receivedStates[3], .idle)
    }

    @MainActor
    func test_stateStream_supports_multiple_subscribers() async throws {
        // Given
        let observableState = ObservableAgentState()
        var subscriber1States: [LegacyAgentState] = []
        var subscriber2States: [LegacyAgentState] = []

        // When - Create two subscribers
        let task1 = Task {
            for await state in observableState.stateStream {
                subscriber1States.append(state)
                if subscriber1States.count >= 2 {
                    break
                }
            }
        }

        let task2 = Task {
            for await state in observableState.stateStream {
                subscriber2States.append(state)
                if subscriber2States.count >= 2 {
                    break
                }
            }
        }

        // Wait for subscriptions
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms

        // Change state
        observableState.state = .thinking

        // Wait for tasks to collect states
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        task1.cancel()
        task2.cancel()

        // Then - Both subscribers should have received the same states
        XCTAssertEqual(subscriber1States.count, 2)
        XCTAssertEqual(subscriber2States.count, 2)
        XCTAssertEqual(subscriber1States[0], .idle)
        XCTAssertEqual(subscriber1States[1], .thinking)
        XCTAssertEqual(subscriber2States[0], .idle)
        XCTAssertEqual(subscriber2States[1], .thinking)
    }

    @MainActor
    func test_stateStream_cleans_up_on_task_cancellation() async throws {
        // Given
        let observableState = ObservableAgentState()
        let receivedFirstState = expectation(description: "Received first state")

        // When - Create and cancel a subscriber
        let task = Task {
            for await _ in observableState.stateStream {
                receivedFirstState.fulfill()
                // Break after first state to avoid waiting forever
                break
            }
        }

        // Wait for subscription to receive first state
        await fulfillment(of: [receivedFirstState], timeout: 1.0)

        // Cancel the task
        task.cancel()

        // Wait for cleanup
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms

        // Then - State changes after cancellation should not crash
        observableState.state = .thinking
        observableState.state = .idle

        // The test passes if no crash occurs
    }

    func test_stateStream_terminates_when_observableState_deallocated() async throws {
        // Given - Use a class to track deallocation
        let streamTerminated = expectation(description: "Stream should terminate")

        // Create observableState in a scope so it can be deallocated
        var stream: AsyncStream<LegacyAgentState>?
        autoreleasepool {
            let observableState = ObservableAgentState()
            stream = observableState.stateStream
        }

        // When - Start iterating and wait for termination
        let iterationTask = Task {
            guard let stream = stream else { return }
            for await _ in stream {
                // Just iterate
            }
            // Stream finished (either naturally or due to deallocation)
            streamTerminated.fulfill()
        }

        // Give some time for iteration to start
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Force cleanup
        stream = nil

        // Then - Stream should terminate (with timeout to avoid hanging)
        await fulfillment(of: [streamTerminated], timeout: 2.0)
        iterationTask.cancel()
    }

    func test_stateStream_integration_with_agent_execution() async throws {
        // Given
        class MockLanguageModel: LLM, @unchecked Sendable {
            let provider = "mock"
            let modelId = "mock-model"
            let capabilities: LLMCapabilities = []
            var callCount = 0

            func generateText(request: AITextRequest) async throws -> AITextResult {
                callCount += 1
                // Simulate some processing time
                try await Task.sleep(nanoseconds: 30_000_000) // 30ms
                return AITextResult(
                    text: "Response",
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .stop
                )
            }

            func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
                AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta("Response"))
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

        // Thread-safe state collection actor
        actor StateCollector {
            var states: [LegacyAgentState] = []

            func append(_ state: LegacyAgentState) {
                states.append(state)
            }

            func getStates() -> [LegacyAgentState] {
                return states
            }

            var count: Int {
                return states.count
            }
        }

        let model = MockLanguageModel()
        let agent = Agent(model: model)
        let stateCollector = StateCollector()
        let collectedEnoughStates = expectation(description: "Collected enough states")

        // When - Subscribe to state stream and execute
        let streamTask = Task {
            for await state in agent.observableState.stateStream {
                await stateCollector.append(state)
                let currentCount = await stateCollector.count
                // Stop after seeing idle again (execution complete) or after max states
                if (currentCount > 1 && state == .idle) || currentCount >= 5 {
                    collectedEnoughStates.fulfill()
                    break
                }
            }
        }

        // Allow the stream subscription task to start before executing
        await Task.yield()
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms to ensure subscription is active

        // Execute agent
        _ = try await agent.execute(messages: [.user("Hello")])

        // Wait for stream to collect states with proper expectation
        await fulfillment(of: [collectedEnoughStates], timeout: 2.0)
        streamTask.cancel()

        // Then - Should have observed state transitions
        let observedStates = await stateCollector.getStates()
        XCTAssertGreaterThanOrEqual(observedStates.count, 2) // At least initial idle + thinking
        XCTAssertEqual(observedStates.first, .idle) // Initial state
        XCTAssertTrue(observedStates.contains(.thinking)) // Saw thinking state
    }
}

// MARK: - Streaming Tests

final class AgentStreamingTests: XCTestCase {

    // MARK: - Test Helpers

    /// Mock language model with streaming support
    private class MockStreamingLanguageModel: LLM, @unchecked Sendable {
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
        let agent = Agent(model: model)

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
        let agent = Agent(model: model)

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
        let agent = Agent(model: model)

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
        let agent = Agent(model: model)

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
        let agent = Agent(model: model)

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
        let agent = Agent(model: model)

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

        let agent = Agent(model: model, stopCondition: .stepCount(1))

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

        let agent = Agent(model: model, stopCondition: .stepCount(1))

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

        let agent = Agent(model: model, stopCondition: .stepCount(1))

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

        let agent = Agent(model: model, stopCondition: .stepCount(3))

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

        let agent = Agent(model: model)

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

        let agent = Agent(model: model)
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

        let agent = Agent(model: model)

        // When - Execute two streams concurrently
        async let stream1: () = {
            for try await _ in agent.streamExecute(messages: [.user("LegacyMessage 1")]) {}
        }()

        // Small delay to ensure first is queued first
        try await Task.sleep(nanoseconds: 5_000_000) // 5ms

        async let stream2: () = {
            for try await _ in agent.streamExecute(messages: [.user("LegacyMessage 2")]) {}
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

        let agent = Agent(model: model)

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

    // MARK: - LegacyMessage History Tests

    func test_streamExecute_updates_message_history() async throws {
        // Given
        let model = MockStreamingLanguageModel()
        let agent = Agent(model: model)

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
        let agent = Agent(
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
        let agent = Agent(model: model)

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

// MARK: - Agent Tool Execution Tests

final class AgentToolExecutionTests: XCTestCase {

    // MARK: - Test Tools

    /// Simple test tool for weather queries
    private struct MockWeatherTool: Tool {
        let name = "get_weather"
        let description = "Get the current weather for a location"

        @Parameter(description: "City name")
        var city: String = ""

        init() {}

        func execute() async throws -> ToolResult {
            return ToolResult(content: "Weather in \(city): 22°C, sunny")
        }
    }

    /// Test tool for calculator operations
    private struct MockCalculatorTool: Tool {
        let name = "calculate"
        let description = "Perform basic arithmetic"

        @Parameter(description: "First number")
        var a: Double = 0.0

        @Parameter(description: "Second number")
        var b: Double = 0.0

        @Parameter(description: "Operation (+, -, *, /)")
        var operation: String = "+"

        init() {}

        func execute() async throws -> ToolResult {
            let result: Double
            switch operation {
            case "+": result = a + b
            case "-": result = a - b
            case "*": result = a * b
            case "/":
                guard b != 0 else { throw ToolError.executionFailed("Division by zero") }
                result = a / b
            default: throw ToolError.executionFailed("Invalid operation")
            }
            return ToolResult(content: "Result: \(result)")
        }
    }

    /// Test tool that always fails
    private struct FailingTool: Tool {
        let name = "failing_tool"
        let description = "A tool that always fails"

        init() {}

        func execute() async throws -> ToolResult {
            throw ToolError.executionFailed("This tool always fails")
        }
    }

    // MARK: - Mock Language Model with Tool Support

    private class MockToolLanguageModel: LLM, @unchecked Sendable {
        let provider = "mock"
        let modelId = "mock-tool-model"
        let capabilities: LLMCapabilities = []

        var generateTextHandler: ((AITextRequest) async throws -> AITextResult)?
        var streamTextHandler: ((AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>)?
        var generateTextCallCount = 0
        let lock = NSLock()

        func generateText(request: AITextRequest) async throws -> AITextResult {
            lock.lock()
            generateTextCallCount += 1
            lock.unlock()

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
            if let handler = streamTextHandler {
                return handler(request)
            }

            return AsyncThrowingStream { continuation in
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

    // MARK: - Successful Tool Execution Tests

    func test_execute_with_single_tool_call_succeeds() async throws {
        // Given
        let model = MockToolLanguageModel()
        var callCount = 0

        model.generateTextHandler = { _ in
            callCount += 1
            if callCount == 1 {
                // First call: return a tool call
                return AITextResult(
                    text: "Let me check the weather...",
                    toolCalls: [ToolCallResult(id: "call-1", name: "get_weather", arguments: "{\"city\":\"London\"}")],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                // Second call: return final response after tool execution
                return AITextResult(
                    text: "The weather in London is 22°C and sunny!",
                    toolCalls: [],
                    usage: AIUsage(promptTokens: 20, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            tools: [MockWeatherTool.self],
            instructions: "You are a helpful weather assistant."
        )

        // When
        let result = try await agent.execute(messages: [.user("What's the weather in London?")])

        // Then
        XCTAssertEqual(result.text, "The weather in London is 22°C and sunny!")
        XCTAssertEqual(result.steps.count, 2)
        XCTAssertEqual(model.generateTextCallCount, 2)

        // Verify tool call was in the first step
        XCTAssertEqual(result.steps[0].toolCalls.count, 1)
        XCTAssertEqual(result.steps[0].toolCalls[0].name, "get_weather")

        // Verify message history contains tool messages
        let messages = await agent.messages
        XCTAssertTrue(messages.contains { $0.role == .tool })
    }

    func test_execute_with_multiple_sequential_tool_calls() async throws {
        // Given
        let model = MockToolLanguageModel()
        var callCount = 0

        model.generateTextHandler = { _ in
            callCount += 1
            switch callCount {
            case 1:
                // First call: weather tool
                return AITextResult(
                    text: "Checking weather...",
                    toolCalls: [ToolCallResult(id: "call-1", name: "get_weather", arguments: "{\"city\":\"Paris\"}")],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            case 2:
                // Second call: calculator tool
                return AITextResult(
                    text: "Let me calculate...",
                    toolCalls: [ToolCallResult(id: "call-2", name: "calculate", arguments: "{\"a\":22,\"b\":10,\"operation\":\"+\"}")],
                    usage: AIUsage(promptTokens: 15, completionTokens: 5),
                    finishReason: .toolCalls
                )
            default:
                // Final response
                return AITextResult(
                    text: "Paris is 22°C and if we add 10, we get 32°C!",
                    toolCalls: [],
                    usage: AIUsage(promptTokens: 25, completionTokens: 15),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            tools: [MockWeatherTool.self, MockCalculatorTool.self],
            stopCondition: .stepCount(5)
        )

        // When
        let result = try await agent.execute(messages: [.user("What's the weather in Paris plus 10?")])

        // Then
        XCTAssertEqual(result.steps.count, 3)
        XCTAssertEqual(result.steps[0].toolCalls.first?.name, "get_weather")
        XCTAssertEqual(result.steps[1].toolCalls.first?.name, "calculate")
        XCTAssertTrue(result.steps[2].toolCalls.isEmpty) // Final response has no tool calls
    }

    // MARK: - Tool Not Found Tests

    func test_execute_with_unknown_tool_handles_gracefully() async throws {
        // Given
        let model = MockToolLanguageModel()
        var callCount = 0

        model.generateTextHandler = { _ in
            callCount += 1
            if callCount == 1 {
                // Request an unknown tool
                return AITextResult(
                    text: "Calling unknown tool...",
                    toolCalls: [ToolCallResult(id: "call-1", name: "unknown_tool", arguments: "{}")],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "Tool failed, here's an alternative response",
                    toolCalls: [],
                    usage: AIUsage(promptTokens: 15, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            tools: [MockWeatherTool.self], // Only weather tool, not the requested one
            stopCondition: .stepCount(3)
        )

        // When
        let result = try await agent.execute(messages: [.user("Use the unknown tool")])

        // Then - Should continue with error message in tool response
        XCTAssertGreaterThanOrEqual(result.steps.count, 1)

        // Verify model was called twice (initial call + response after error)
        XCTAssertEqual(model.generateTextCallCount, 2, "Model should be called twice: once for tool call, once after error")

        // Verify final response matches expected fallback
        XCTAssertEqual(result.text, "Tool failed, here's an alternative response")

        // Check that the error was handled (tool message should contain "Error" or similar)
        let messages = await agent.messages
        let toolMessages = messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.count, 1, "Should have exactly one tool message with error")
        if let toolMessage = toolMessages.first {
            XCTAssertTrue(toolMessage.content.textValue.contains("Error") ||
                         toolMessage.content.textValue.contains("not found"))
            // Verify tool call ID matches
            XCTAssertEqual(toolMessage.toolCallId, "call-1")
        }
    }

    // MARK: - Tool Execution Failure Tests

    func test_execute_with_failing_tool_handles_error() async throws {
        // Given
        let model = MockToolLanguageModel()
        var callCount = 0

        model.generateTextHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return AITextResult(
                    text: "Calling failing tool...",
                    toolCalls: [ToolCallResult(id: "fail-call-1", name: "failing_tool", arguments: "{}")],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "The tool failed, but I can help anyway",
                    toolCalls: [],
                    usage: AIUsage(promptTokens: 15, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            tools: [FailingTool.self],
            stopCondition: .stepCount(3)
        )

        // When
        let result = try await agent.execute(messages: [.user("Use the failing tool")])

        // Then - Should continue after error, not crash
        XCTAssertGreaterThanOrEqual(result.steps.count, 1)

        // Verify model was called twice
        XCTAssertEqual(model.generateTextCallCount, 2, "Model should be called twice: once for tool call, once after error")

        // Verify final response
        XCTAssertEqual(result.text, "The tool failed, but I can help anyway")

        // Verify error was captured in message history
        let messages = await agent.messages
        let toolMessages = messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.count, 1, "Should have exactly one tool message with error")
        if let toolMessage = toolMessages.first {
            XCTAssertTrue(toolMessage.content.textValue.contains("Error"))
            // Verify tool call ID matches
            XCTAssertEqual(toolMessage.toolCallId, "fail-call-1")
        }
    }

    // MARK: - Tool Results in LegacyMessage History Tests

    func test_tool_results_added_to_message_history() async throws {
        // Given
        let model = MockToolLanguageModel()
        var callCount = 0

        model.generateTextHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return AITextResult(
                    text: "Checking weather...",
                    toolCalls: [ToolCallResult(id: "tool-call-123", name: "get_weather", arguments: "{\"city\":\"Tokyo\"}")],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "The weather in Tokyo is great!",
                    toolCalls: [],
                    usage: AIUsage(promptTokens: 20, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            tools: [MockWeatherTool.self]
        )

        // When
        _ = try await agent.execute(messages: [.user("Weather in Tokyo?")])

        // Then
        let messages = await agent.messages

        // Should have: system (optional), user, assistant (with tool call), tool, assistant (final)
        let toolMessages = messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.count, 1)

        // Verify tool result content
        if let toolMessage = toolMessages.first {
            XCTAssertTrue(toolMessage.content.textValue.contains("Weather in Tokyo"))
            XCTAssertTrue(toolMessage.content.textValue.contains("22°C"))
        }
    }

    // MARK: - Streaming Tool Execution Tests

    func test_streamExecute_with_tool_call_emits_toolResult_event() async throws {
        // Given
        let model = MockToolLanguageModel()
        var callCount = 0

        model.streamTextHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta("Checking..."))
                    continuation.yield(.toolCallStart(id: "call-1", name: "get_weather"))
                    continuation.yield(.toolCallDelta(id: "call-1", argumentsDelta: "{\"city\":"))
                    continuation.yield(.toolCallDelta(id: "call-1", argumentsDelta: "\"Berlin\"}"))
                    continuation.yield(.toolCall(id: "call-1", name: "get_weather", arguments: "{\"city\":\"Berlin\"}"))
                    continuation.yield(.finish(finishReason: .toolCalls, usage: AIUsage(promptTokens: 10, completionTokens: 5)))
                    continuation.finish()
                }
            } else {
                return AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta("It's sunny in Berlin!"))
                    continuation.yield(.finish(finishReason: .stop, usage: AIUsage(promptTokens: 15, completionTokens: 10)))
                    continuation.finish()
                }
            }
        }

        let agent = Agent(
            model: model,
            tools: [MockWeatherTool.self],
            stopCondition: .stepCount(3)
        )

        // When
        var toolResultEvents: [(id: String, result: String)] = []
        for try await event in agent.streamExecute(messages: [.user("Weather in Berlin?")]) {
            if case .toolResult(let id, let result, _) = event {
                toolResultEvents.append((id: id, result: result))
            }
        }

        // Then
        XCTAssertGreaterThanOrEqual(toolResultEvents.count, 1)
        if let firstResult = toolResultEvents.first {
            XCTAssertEqual(firstResult.id, "call-1")
            XCTAssertTrue(firstResult.result.contains("Weather in Berlin"))
        }
    }

    func test_streamExecute_tool_execution_updates_observable_state() async throws {
        // Given
        let model = MockToolLanguageModel()
        var callCount = 0

        model.streamTextHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return AsyncThrowingStream { continuation in
                    continuation.yield(.toolCallStart(id: "call-1", name: "get_weather"))
                    continuation.yield(.toolCall(id: "call-1", name: "get_weather", arguments: "{\"city\":\"Rome\"}"))
                    continuation.yield(.finish(finishReason: .toolCalls, usage: AIUsage.zero))
                    continuation.finish()
                }
            } else {
                return AsyncThrowingStream { continuation in
                    continuation.yield(.textDelta("Done"))
                    continuation.yield(.finish(finishReason: .stop, usage: AIUsage.zero))
                    continuation.finish()
                }
            }
        }

        let agent = Agent(
            model: model,
            tools: [MockWeatherTool.self],
            stopCondition: .stepCount(3)
        )

        // When - Execute and track toolResult events (which indicate tool was executed)
        var toolResultCount = 0
        let observableState = agent.observableState

        // Start streaming
        for try await event in agent.streamExecute(messages: [.user("Weather?")]) {
            // Track tool results as evidence that tools were executed
            if case .toolResult = event {
                toolResultCount += 1
            }
        }

        // Then - Tool should have been executed at least once
        XCTAssertGreaterThanOrEqual(toolResultCount, 1, "Expected at least one tool to be executed")

        // Final state should be idle
        await MainActor.run {
            XCTAssertEqual(observableState.state, .idle)
        }
    }

    // MARK: - Tool with Multiple Parameters Tests

    func test_execute_passes_correct_parameters_to_tool() async throws {
        // Given
        let model = MockToolLanguageModel()
        var callCount = 0

        model.generateTextHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return AITextResult(
                    text: "Calculating...",
                    toolCalls: [ToolCallResult(
                        id: "call-1",
                        name: "calculate",
                        arguments: "{\"a\":100,\"b\":25,\"operation\":\"*\"}"
                    )],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "The result is 2500",
                    toolCalls: [],
                    usage: AIUsage(promptTokens: 15, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            tools: [MockCalculatorTool.self]
        )

        // When
        let result = try await agent.execute(messages: [.user("What is 100 times 25?")])

        // Then
        XCTAssertEqual(result.text, "The result is 2500")

        // Verify tool was called and result contains the calculation
        let messages = await agent.messages
        let toolMessages = messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.count, 1)
        if let toolMessage = toolMessages.first {
            XCTAssertTrue(toolMessage.content.textValue.contains("Result: 2500"))
        }
    }

    // MARK: - Stop Condition with Tools Tests

    func test_stop_condition_respects_max_steps_with_tools() async throws {
        // Given
        let model = MockToolLanguageModel()

        // Model always returns tool calls - should be stopped by step limit
        model.generateTextHandler = { _ in
            AITextResult(
                text: "Calling tool...",
                toolCalls: [ToolCallResult(id: "call-\(UUID().uuidString)", name: "get_weather", arguments: "{\"city\":\"Test\"}")],
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .toolCalls
            )
        }

        let agent = Agent(
            model: model,
            tools: [MockWeatherTool.self],
            stopCondition: .stepCount(3) // Stop after 3 steps
        )

        // When
        let result = try await agent.execute(messages: [.user("Keep checking weather")])

        // Then - Should stop after 3 steps even with continuous tool calls
        XCTAssertEqual(result.steps.count, 3)
    }

    // MARK: - Usage Accumulation with Tools Tests

    func test_usage_accumulates_across_tool_calls() async throws {
        // Given
        let model = MockToolLanguageModel()
        var callCount = 0

        model.generateTextHandler = { _ in
            callCount += 1
            if callCount == 1 {
                return AITextResult(
                    text: "Step 1",
                    toolCalls: [ToolCallResult(id: "call-1", name: "get_weather", arguments: "{\"city\":\"A\"}")],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else if callCount == 2 {
                return AITextResult(
                    text: "Step 2",
                    toolCalls: [ToolCallResult(id: "call-2", name: "get_weather", arguments: "{\"city\":\"B\"}")],
                    usage: AIUsage(promptTokens: 20, completionTokens: 10),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "Final",
                    toolCalls: [],
                    usage: AIUsage(promptTokens: 30, completionTokens: 15),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            tools: [MockWeatherTool.self]
        )

        // When
        let result = try await agent.execute(messages: [.user("Check weather")])

        // Then - Usage should be sum of all steps
        XCTAssertEqual(result.usage.promptTokens, 60) // 10 + 20 + 30
        XCTAssertEqual(result.usage.completionTokens, 30) // 5 + 10 + 15
        XCTAssertEqual(result.usage.totalTokens, 90)
    }
}
