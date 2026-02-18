//
//  AIStreamAccumulatorTests.swift
//  AISDKTests
//
//  Tests for AIStreamAccumulator event-to-parts conversion
//

import XCTest
@testable import AISDK

@MainActor
final class AIStreamAccumulatorTests: XCTestCase {

    // MARK: - Thinking Events

    func testThinkingEventsCreateThinkingPart() {
        let acc = AIStreamAccumulator()
        acc.process(.reasoningStart)
        acc.process(.reasoningDelta("Let me think"))
        acc.process(.reasoningDelta(" about this"))
        acc.process(.reasoningFinish(""))

        XCTAssertEqual(acc.parts.count, 1)
        if case .thinking(_, let text, let duration) = acc.parts[0] {
            XCTAssertEqual(text, "Let me think about this")
            XCTAssertNotNil(duration)
        } else {
            XCTFail("Expected thinking part")
        }
    }

    // MARK: - Tool Call Lifecycle

    func testToolCallLifecycle() {
        let acc = AIStreamAccumulator()
        acc.process(.toolCallStart(id: "t1", name: "calculator"))
        acc.process(.toolCallDelta(id: "t1", argumentsDelta: "{\"a\":"))
        acc.process(.toolCallDelta(id: "t1", argumentsDelta: "5}"))
        acc.process(.toolCall(id: "t1", name: "calculator", arguments: "{\"a\":5}"))
        acc.process(.toolResult(id: "t1", result: "42", metadata: nil))

        XCTAssertEqual(acc.parts.count, 1)
        if case .toolCall(_, let call) = acc.parts[0] {
            XCTAssertEqual(call.toolName, "calculator")
            XCTAssertEqual(call.state, .outputAvailable)
            XCTAssertEqual(call.input, "{\"a\":5}")
            XCTAssertEqual(call.output, "42")
            XCTAssertNotNil(call.durationSeconds)
        } else {
            XCTFail("Expected toolCall part")
        }
    }

    // MARK: - Text Accumulation

    func testTextDeltasAccumulate() {
        let acc = AIStreamAccumulator()
        acc.process(.textDelta("Hello"))
        acc.process(.textDelta(" world"))

        XCTAssertEqual(acc.parts.count, 1)
        if case .text(_, let text) = acc.parts[0] {
            XCTAssertEqual(text, "Hello world")
        } else {
            XCTFail("Expected text part")
        }
    }

    func testTextAfterToolCallCreatesNewTextPart() {
        let acc = AIStreamAccumulator()
        acc.process(.textDelta("Before"))
        acc.process(.toolCallStart(id: "t1", name: "search"))
        acc.process(.toolCall(id: "t1", name: "search", arguments: "{}"))
        acc.process(.toolResult(id: "t1", result: "found", metadata: nil))
        acc.process(.textDelta("After"))

        XCTAssertEqual(acc.parts.count, 3)
        if case .text(_, let text) = acc.parts[0] {
            XCTAssertEqual(text, "Before")
        }
        if case .toolCall = acc.parts[1] {
            // ok
        } else {
            XCTFail("Expected toolCall part at index 1")
        }
        if case .text(_, let text) = acc.parts[2] {
            XCTAssertEqual(text, "After")
        }
    }

    // MARK: - Interleaved Sequence (Full Agent Loop)

    func testFullAgentLoopSequence() {
        let acc = AIStreamAccumulator()

        // Step 0: thinking + tool call
        acc.process(.stepStart(stepIndex: 0))
        acc.process(.reasoningStart)
        acc.process(.reasoningDelta("I need to calculate"))
        acc.process(.reasoningFinish(""))
        acc.process(.toolCallStart(id: "c1", name: "calculator"))
        acc.process(.toolCall(id: "c1", name: "calculator", arguments: "{\"a\":5,\"b\":7}"))
        acc.process(.toolResult(id: "c1", result: "35", metadata: nil))
        acc.process(.stepFinish(stepIndex: 0, result: .empty))

        // Step 1: final text
        acc.process(.stepStart(stepIndex: 1))
        acc.process(.textDelta("The answer is 35."))
        acc.process(.stepFinish(stepIndex: 1, result: .empty))
        acc.process(.finish(finishReason: .stop, usage: .zero))

        XCTAssertEqual(acc.parts.count, 3) // thinking, toolCall, text
        XCTAssertTrue(acc.isComplete)
        XCTAssertEqual(acc.currentStepIndex, 1)

        if case .thinking = acc.parts[0] {} else { XCTFail("Expected thinking") }
        if case .toolCall = acc.parts[1] {} else { XCTFail("Expected toolCall") }
        if case .text(_, let text) = acc.parts[2] {
            XCTAssertEqual(text, "The answer is 35.")
        } else { XCTFail("Expected text") }
    }

    // MARK: - No Thinking (OpenAI)

    func testNoThinkingEventsProducesNoThinkingParts() {
        let acc = AIStreamAccumulator()
        acc.process(.toolCallStart(id: "t1", name: "search"))
        acc.process(.toolCall(id: "t1", name: "search", arguments: "{}"))
        acc.process(.toolResult(id: "t1", result: "result", metadata: nil))
        acc.process(.textDelta("Here you go"))
        acc.process(.finish(finishReason: .stop, usage: .zero))

        XCTAssertTrue(acc.isComplete)
        XCTAssertNil(acc.thinkingDuration)
        XCTAssertEqual(acc.toolCallCount, 1)

        // Summary should not mention thinking
        XCTAssertFalse(acc.summary.contains("Thought"))
        XCTAssertTrue(acc.summary.contains("search"))
    }

    // MARK: - Summary

    func testSummaryText() {
        let acc = AIStreamAccumulator()
        acc.process(.toolCallStart(id: "t1", name: "calculator"))
        acc.process(.toolCall(id: "t1", name: "calculator", arguments: "{}"))
        acc.process(.toolResult(id: "t1", result: "5", metadata: nil))
        acc.process(.toolCallStart(id: "t2", name: "calculator"))
        acc.process(.toolCall(id: "t2", name: "calculator", arguments: "{}"))
        acc.process(.toolResult(id: "t2", result: "10", metadata: nil))

        XCTAssertEqual(acc.toolCallCount, 2)
        XCTAssertTrue(acc.summary.contains("calculator"))
        XCTAssertTrue(acc.summary.contains("2 times"))
    }

    func testMultipleToolNamesSummary() {
        let acc = AIStreamAccumulator()
        acc.process(.toolCallStart(id: "t1", name: "calculator"))
        acc.process(.toolCall(id: "t1", name: "calculator", arguments: "{}"))
        acc.process(.toolResult(id: "t1", result: "5", metadata: nil))
        acc.process(.toolCallStart(id: "t2", name: "weather"))
        acc.process(.toolCall(id: "t2", name: "weather", arguments: "{}"))
        acc.process(.toolResult(id: "t2", result: "sunny", metadata: nil))

        XCTAssertEqual(acc.toolCallCount, 2)
        XCTAssertTrue(acc.summary.contains("2 tools"))
    }

    // MARK: - Reset

    func testReset() {
        let acc = AIStreamAccumulator()
        acc.process(.textDelta("Hello"))
        acc.process(.finish(finishReason: .stop, usage: .zero))

        XCTAssertTrue(acc.isComplete)
        XCTAssertFalse(acc.parts.isEmpty)

        acc.reset()

        XCTAssertFalse(acc.isComplete)
        XCTAssertTrue(acc.parts.isEmpty)
        XCTAssertEqual(acc.currentStepIndex, 0)
    }

    // MARK: - Error Handling

    func testErrorMarksToolCallsAsFailed() {
        let acc = AIStreamAccumulator()
        acc.process(.toolCallStart(id: "t1", name: "search"))
        acc.process(.error(NSError(domain: "test", code: -1)))

        XCTAssertTrue(acc.isComplete)
        if case .toolCall(_, let call) = acc.parts[0] {
            XCTAssertEqual(call.state, .outputError)
        } else {
            XCTFail("Expected toolCall part")
        }
    }

    // MARK: - hasActivity

    func testHasActivityWithOnlyText() {
        let acc = AIStreamAccumulator()
        acc.process(.textDelta("Just text"))
        XCTAssertFalse(acc.hasActivity)
    }

    func testHasActivityWithToolCall() {
        let acc = AIStreamAccumulator()
        acc.process(.toolCallStart(id: "t1", name: "search"))
        XCTAssertTrue(acc.hasActivity)
    }
}
