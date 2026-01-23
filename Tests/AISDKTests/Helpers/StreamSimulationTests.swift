//
//  StreamSimulationTests.swift
//  AISDKTests
//
//  Tests for StreamSimulation helper
//

import XCTest
@testable import AISDK

final class StreamSimulationTests: XCTestCase {
    // MARK: - Text Stream Tests

    func testTextStreamGeneratesCorrectEvents() {
        let events = StreamSimulation.textStream("Hello world")

        // Should have: start, textDelta("Hello"), textDelta(" world"), textCompletion, usage, finish
        XCTAssertGreaterThanOrEqual(events.count, 5)

        // First event should be start
        if case .start(let metadata) = events[0] {
            XCTAssertNotNil(metadata)
            XCTAssertEqual(metadata?.model, StreamSimulation.defaultModel)
            XCTAssertEqual(metadata?.provider, StreamSimulation.defaultProvider)
        } else {
            XCTFail("First event should be .start")
        }

        // Should contain text deltas
        let textDeltas = events.compactMap { event -> String? in
            if case .textDelta(let delta) = event { return delta }
            return nil
        }
        XCTAssertFalse(textDeltas.isEmpty)
        XCTAssertEqual(textDeltas.joined(), "Hello world")

        // Should have text completion
        let hasTextCompletion = events.contains { event in
            if case .textCompletion(let text) = event {
                return text == "Hello world"
            }
            return false
        }
        XCTAssertTrue(hasTextCompletion)

        // Should have usage
        let hasUsage = events.contains { event in
            if case .usage = event { return true }
            return false
        }
        XCTAssertTrue(hasUsage)

        // Last event should be finish
        if case .finish(let reason, _) = events.last {
            XCTAssertEqual(reason, .stop)
        } else {
            XCTFail("Last event should be .finish")
        }
    }

    func testTextStreamChunksByCharacters() {
        let events = StreamSimulation.textStream("Hi", chunkByWords: false)

        let textDeltas = events.compactMap { event -> String? in
            if case .textDelta(let delta) = event { return delta }
            return nil
        }
        XCTAssertEqual(textDeltas, ["H", "i"])
    }

    func testTextStreamWithCustomModelAndProvider() {
        let events = StreamSimulation.textStream(
            "Test",
            model: "claude-3",
            provider: "anthropic"
        )

        if case .start(let metadata) = events[0] {
            XCTAssertEqual(metadata?.model, "claude-3")
            XCTAssertEqual(metadata?.provider, "anthropic")
        } else {
            XCTFail("First event should be .start")
        }
    }

    // MARK: - Tool Call Stream Tests

    func testToolCallStreamGeneratesCorrectEvents() {
        let events = StreamSimulation.toolCallStream(
            toolName: "get_weather",
            arguments: #"{"city": "NYC"}"#
        )

        // Should have: start, toolCallStart, toolCallDelta(s), toolCallFinish, usage, finish
        XCTAssertGreaterThanOrEqual(events.count, 5)

        // First event should be start
        guard case .start = events[0] else {
            XCTFail("First event should be .start")
            return
        }

        // Should have tool call start
        let hasToolStart = events.contains { event in
            if case .toolCallStart(_, let name) = event {
                return name == "get_weather"
            }
            return false
        }
        XCTAssertTrue(hasToolStart)

        // Should have tool call finish
        let hasToolFinish = events.contains { event in
            if case .toolCallFinish(_, let name, let args) = event {
                return name == "get_weather" && args == #"{"city": "NYC"}"#
            }
            return false
        }
        XCTAssertTrue(hasToolFinish)

        // Last event should be finish with toolCalls reason
        if case .finish(let reason, _) = events.last {
            XCTAssertEqual(reason, .toolCalls)
        } else {
            XCTFail("Last event should be .finish")
        }
    }

    func testMultiToolCallStream() {
        let events = StreamSimulation.multiToolCallStream(toolCalls: [
            (name: "tool1", arguments: "{}"),
            (name: "tool2", arguments: "{}")
        ])

        let toolStarts = events.compactMap { event -> String? in
            if case .toolCallStart(_, let name) = event { return name }
            return nil
        }
        XCTAssertEqual(toolStarts.count, 2)
        XCTAssertEqual(toolStarts, ["tool1", "tool2"])
    }

    // MARK: - Mixed Stream Tests

    func testTextThenToolStream() {
        let events = StreamSimulation.textThenToolStream(
            text: "Let me check",
            toolName: "search",
            arguments: #"{"query": "test"}"#
        )

        // Should have text first, then tool
        var sawTextCompletion = false
        var sawToolAfterText = false

        for event in events {
            if case .textCompletion = event {
                sawTextCompletion = true
            }
            if case .toolCallStart = event, sawTextCompletion {
                sawToolAfterText = true
            }
        }

        XCTAssertTrue(sawTextCompletion)
        XCTAssertTrue(sawToolAfterText)
    }

    // MARK: - Reasoning Stream Tests

    func testReasoningStream() {
        let events = StreamSimulation.reasoningStream(
            reasoning: "Let me think about this",
            response: "The answer is 42"
        )

        // Should have reasoning events before text events
        var sawReasoningStart = false
        var sawReasoningFinish = false
        var sawTextAfterReasoning = false

        for event in events {
            if case .reasoningStart = event {
                sawReasoningStart = true
            }
            if case .reasoningFinish = event {
                sawReasoningFinish = true
            }
            if case .textDelta = event, sawReasoningFinish {
                sawTextAfterReasoning = true
            }
        }

        XCTAssertTrue(sawReasoningStart)
        XCTAssertTrue(sawReasoningFinish)
        XCTAssertTrue(sawTextAfterReasoning)
    }

    // MARK: - Error Stream Tests

    func testErrorStream() {
        let testError = LLMError.rateLimitExceeded
        let events = StreamSimulation.errorStream(error: testError)

        // Should have start and error
        XCTAssertGreaterThanOrEqual(events.count, 2)

        guard case .start = events[0] else {
            XCTFail("First event should be .start")
            return
        }

        let hasError = events.contains { event in
            if case .error = event { return true }
            return false
        }
        XCTAssertTrue(hasError)
    }

    func testErrorStreamWithPrecedingEvents() {
        let testError = AISDKError.custom("test")
        let events = StreamSimulation.errorStream(error: testError, afterEvents: 3)

        // Should have: start, 3 text deltas, error
        XCTAssertEqual(events.count, 5)

        let textDeltas = events.compactMap { event -> String? in
            if case .textDelta(let delta) = event { return delta }
            return nil
        }
        XCTAssertEqual(textDeltas.count, 3)
    }

    func testPartialThenErrorStream() {
        let testError = LLMError.networkError(nil, "Connection lost")
        let events = StreamSimulation.partialThenErrorStream(
            partialText: "Partial response",
            error: testError
        )

        // Should have text deltas but no textCompletion (since it errored)
        let hasTextCompletion = events.contains { event in
            if case .textCompletion = event { return true }
            return false
        }
        XCTAssertFalse(hasTextCompletion)

        // Should end with error
        if case .error = events.last {
            // Expected
        } else {
            XCTFail("Last event should be .error")
        }
    }

    // MARK: - Heartbeat Stream Tests

    func testHeartbeatStream() {
        let events = StreamSimulation.heartbeatStream(
            text: "This is a longer text with multiple words for heartbeats",
            heartbeatCount: 2
        )

        let heartbeats = events.filter { event in
            if case .heartbeat = event { return true }
            return false
        }
        // Should emit exactly 2 heartbeats as requested
        XCTAssertEqual(heartbeats.count, 2)
    }

    func testHeartbeatStreamExactCount() {
        // Test various heartbeat counts
        for count in [0, 1, 3, 5, 10] {
            let events = StreamSimulation.heartbeatStream(
                text: "Word1 Word2 Word3 Word4 Word5",
                heartbeatCount: count
            )

            let heartbeats = events.filter { event in
                if case .heartbeat = event { return true }
                return false
            }
            XCTAssertEqual(heartbeats.count, count, "Should emit exactly \(count) heartbeats")
        }
    }

    func testHeartbeatStreamWithNegativeCount() {
        // Negative count should be treated as zero
        let events = StreamSimulation.heartbeatStream(
            text: "Some text here",
            heartbeatCount: -5
        )

        let heartbeats = events.filter { event in
            if case .heartbeat = event { return true }
            return false
        }
        XCTAssertEqual(heartbeats.count, 0)
    }

    func testHeartbeatStreamSingleWord() {
        // Even with a single word, should emit requested heartbeats
        let events = StreamSimulation.heartbeatStream(
            text: "Hello",
            heartbeatCount: 3
        )

        let heartbeats = events.filter { event in
            if case .heartbeat = event { return true }
            return false
        }
        XCTAssertEqual(heartbeats.count, 3)
    }

    // MARK: - Async Stream Tests

    func testAsStreamEmitsAllEvents() async throws {
        let events = StreamSimulation.textStream("Test message")
        let stream = StreamSimulation.asStream(events)

        var collected: [AIStreamEvent] = []
        for try await event in stream {
            collected.append(event)
        }

        XCTAssertEqual(collected.count, events.count)
    }

    func testAsStreamWithDelay() async throws {
        let events = [
            AIStreamEvent.start(metadata: nil),
            AIStreamEvent.textDelta("test"),
            AIStreamEvent.finish(finishReason: .stop, usage: AIUsage(promptTokens: 1, completionTokens: 1))
        ]

        let start = ContinuousClock.now
        let stream = StreamSimulation.asStream(events, delay: .milliseconds(10))

        var count = 0
        for try await _ in stream {
            count += 1
        }

        let elapsed = ContinuousClock.now - start
        XCTAssertEqual(count, 3)
        // Should take at least 20ms (2 delays between 3 events, no delay after last)
        XCTAssertGreaterThan(elapsed, .milliseconds(15))
    }

    // MARK: - Multi-Step Stream Tests

    func testMultiStepStream() {
        let step1 = AIStepResult(
            stepIndex: 0,
            text: "Step one result",
            toolCalls: [],
            toolResults: [],
            usage: AIUsage(promptTokens: 10, completionTokens: 20),
            finishReason: .stop
        )
        let step2 = AIStepResult(
            stepIndex: 1,
            text: "Step two result",
            toolCalls: [],
            toolResults: [],
            usage: AIUsage(promptTokens: 15, completionTokens: 25, reasoningTokens: 5),
            finishReason: .stop
        )

        let events = StreamSimulation.multiStepStream(steps: [step1, step2])

        // Should have step starts and finishes with correct indices
        var stepStartIndices: [Int] = []
        var stepFinishIndices: [Int] = []

        for event in events {
            if case .stepStart(let stepIndex) = event {
                stepStartIndices.append(stepIndex)
            }
            if case .stepFinish(let stepIndex, _) = event {
                stepFinishIndices.append(stepIndex)
            }
        }

        XCTAssertEqual(stepStartIndices.count, 2)
        XCTAssertEqual(stepFinishIndices.count, 2)

        // Verify indices match the step results
        XCTAssertEqual(stepStartIndices, [0, 1])
        XCTAssertEqual(stepFinishIndices, [0, 1])

        // Check total usage is aggregated correctly
        let usageEvent = events.first { event in
            if case .usage = event { return true }
            return false
        }

        if case .usage(let usage) = usageEvent {
            XCTAssertEqual(usage.promptTokens, 25) // 10 + 15
            XCTAssertEqual(usage.completionTokens, 45) // 20 + 25
            XCTAssertEqual(usage.reasoningTokens, 5) // Only step2 has reasoning tokens
        } else {
            XCTFail("Should have usage event")
        }
    }

    func testAsStreamThrowsOnError() async {
        let testError = AISDKError.custom("test error")
        let events = StreamSimulation.errorStream(error: testError)
        let stream = StreamSimulation.asStream(events)

        do {
            for try await _ in stream {
                // Consume events
            }
            XCTFail("Stream should have thrown an error")
        } catch {
            // Expected - error was thrown
        }
    }

    // MARK: - Convenience Method Tests

    func testSimulateTextStream() async throws {
        let stream = StreamSimulation.simulateTextStream("Hello")

        var events: [AIStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertFalse(events.isEmpty)

        // Should contain the text
        let text = events.compactMap { event -> String? in
            if case .textCompletion(let t) = event { return t }
            return nil
        }.first
        XCTAssertEqual(text, "Hello")
    }

    func testSimulateToolStream() async throws {
        let stream = StreamSimulation.simulateToolStream(
            toolName: "test_tool",
            arguments: "{}"
        )

        var events: [AIStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let hasToolCall = events.contains { event in
            if case .toolCallFinish(_, let name, _) = event {
                return name == "test_tool"
            }
            return false
        }
        XCTAssertTrue(hasToolCall)
    }

    // MARK: - Pattern Tests

    func testEventsForPattern() {
        let events = StreamSimulation.eventsForPattern("start,text,finish")

        // start, textDelta, textCompletion, finish = 4 events
        // Note: "text" generates textDelta + textCompletion, usage is separate
        XCTAssertEqual(events.count, 4)

        guard case .start = events[0] else {
            XCTFail("First event should be .start")
            return
        }

        guard case .finish = events.last else {
            XCTFail("Last event should be .finish")
            return
        }
    }

    func testEventsForPatternWithTool() {
        let events = StreamSimulation.eventsForPattern("start,tool,finish")

        let hasToolStart = events.contains { event in
            if case .toolCallStart = event { return true }
            return false
        }
        XCTAssertTrue(hasToolStart)
    }

    func testEventsForPatternWithReasoning() {
        let events = StreamSimulation.eventsForPattern("start,reasoning,text,finish")

        let hasReasoningStart = events.contains { event in
            if case .reasoningStart = event { return true }
            return false
        }
        XCTAssertTrue(hasReasoningStart)
    }
}
