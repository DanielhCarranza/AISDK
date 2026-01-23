//
//  AITextResultTests.swift
//  AISDK
//
//  Tests for AITextResult
//

import Testing
@testable import AISDK

@Suite("AITextResult Tests")
struct AITextResultTests {
    // MARK: - Basic Initialization

    @Test("Creates result with minimal parameters")
    func testMinimalInit() {
        let result = AITextResult(text: "Hello, world!")

        #expect(result.text == "Hello, world!")
        #expect(result.toolCalls.isEmpty)
        #expect(result.usage == .zero)
        #expect(result.finishReason == .stop)
        #expect(result.requestId == nil)
        #expect(result.model == nil)
        #expect(result.provider == nil)
    }

    @Test("Creates result with all parameters")
    func testFullInit() {
        let toolCalls = [
            AIToolCallResult(id: "call-1", name: "get_weather", arguments: "{\"city\":\"NYC\"}")
        ]
        let usage = AIUsage(promptTokens: 100, completionTokens: 50)

        let result = AITextResult(
            text: "The weather in NYC is sunny.",
            toolCalls: toolCalls,
            usage: usage,
            finishReason: .toolCalls,
            requestId: "req-123",
            model: "gpt-4",
            provider: "openai"
        )

        #expect(result.text == "The weather in NYC is sunny.")
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].name == "get_weather")
        #expect(result.usage.promptTokens == 100)
        #expect(result.usage.completionTokens == 50)
        #expect(result.finishReason == .toolCalls)
        #expect(result.requestId == "req-123")
        #expect(result.model == "gpt-4")
        #expect(result.provider == "openai")
    }

    // MARK: - Helper Properties

    @Test("hasToolCalls returns correct value")
    func testHasToolCalls() {
        let withoutTools = AITextResult(text: "Hello")
        let withTools = AITextResult(
            text: "Let me check that",
            toolCalls: [AIToolCallResult(id: "1", name: "search", arguments: "{}")]
        )

        #expect(withoutTools.hasToolCalls == false)
        #expect(withTools.hasToolCalls == true)
    }

    @Test("completedNormally checks finish reason")
    func testCompletedNormally() {
        let stopResult = AITextResult(text: "Done", finishReason: .stop)
        let toolCallsResult = AITextResult(text: "Done", finishReason: .toolCalls)
        let lengthResult = AITextResult(text: "Truncated", finishReason: .length)
        let errorResult = AITextResult(text: "Error", finishReason: .error)

        #expect(stopResult.completedNormally == true)
        #expect(toolCallsResult.completedNormally == true)
        #expect(lengthResult.completedNormally == false)
        #expect(errorResult.completedNormally == false)
    }

    @Test("wasTruncated checks for length finish reason")
    func testWasTruncated() {
        let normalResult = AITextResult(text: "Done", finishReason: .stop)
        let truncatedResult = AITextResult(text: "Truncated...", finishReason: .length)

        #expect(normalResult.wasTruncated == false)
        #expect(truncatedResult.wasTruncated == true)
    }

    @Test("totalTokens returns correct sum")
    func testTotalTokens() {
        let usage = AIUsage(promptTokens: 100, completionTokens: 50)
        let result = AITextResult(text: "Test", usage: usage)

        #expect(result.totalTokens == 150)
    }

    // MARK: - Empty Result

    @Test("Empty result has correct defaults")
    func testEmptyResult() {
        let empty = AITextResult.empty

        #expect(empty.text == "")
        #expect(empty.toolCalls.isEmpty)
        #expect(empty.usage == .zero)
        #expect(empty.finishReason == .stop)
    }

    // MARK: - Equatable

    @Test("Results are equatable")
    func testEquatable() {
        let result1 = AITextResult(text: "Hello", finishReason: .stop)
        let result2 = AITextResult(text: "Hello", finishReason: .stop)
        let result3 = AITextResult(text: "World", finishReason: .stop)

        #expect(result1 == result2)
        #expect(result1 != result3)
    }

    // MARK: - Various Finish Reasons

    @Test("All finish reasons are handled")
    func testAllFinishReasons() {
        let reasons: [AIFinishReason] = [
            .stop, .length, .toolCalls, .contentFilter, .error, .cancelled, .unknown
        ]

        for reason in reasons {
            let result = AITextResult(text: "Test", finishReason: reason)
            #expect(result.finishReason == reason)
        }
    }
}
