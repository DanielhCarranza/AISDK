//
//  AIStepResultTests.swift
//  AISDK
//
//  Tests for AIStepResult - step result for multi-step agent loops
//

import Foundation
import Testing
@testable import AISDK

@Suite("AIStepResult Tests")
struct AIStepResultTests {
    // MARK: - Basic Initialization

    @Test("Creates result with minimal parameters")
    func testMinimalInit() {
        let result = AIStepResult(stepIndex: 0, text: "Hello, world!")

        #expect(result.stepIndex == 0)
        #expect(result.text == "Hello, world!")
        #expect(result.toolCalls.isEmpty)
        #expect(result.toolResults.isEmpty)
        #expect(result.usage == .zero)
        #expect(result.finishReason == .stop)
    }

    @Test("Creates result with all parameters")
    func testFullInit() {
        let toolCalls = [
            AIToolCallResult(id: "call-1", name: "get_weather", arguments: "{\"city\":\"NYC\"}")
        ]
        let toolResults = [
            AIToolResultData(id: "call-1", result: "{\"temp\":72}", metadata: nil)
        ]
        let usage = AIUsage(promptTokens: 100, completionTokens: 50)

        let result = AIStepResult(
            stepIndex: 3,
            text: "The weather in NYC is 72 degrees.",
            toolCalls: toolCalls,
            toolResults: toolResults,
            usage: usage,
            finishReason: .toolCalls
        )

        #expect(result.stepIndex == 3)
        #expect(result.text == "The weather in NYC is 72 degrees.")
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].name == "get_weather")
        #expect(result.toolResults.count == 1)
        #expect(result.toolResults[0].id == "call-1")
        #expect(result.usage.promptTokens == 100)
        #expect(result.usage.completionTokens == 50)
        #expect(result.finishReason == .toolCalls)
    }

    // MARK: - Step Index Tracking

    @Test("Step index is tracked correctly across multiple steps")
    func testStepIndexTracking() {
        let step0 = AIStepResult(stepIndex: 0, text: "First step")
        let step1 = AIStepResult(stepIndex: 1, text: "Second step")
        let step2 = AIStepResult(stepIndex: 2, text: "Third step")

        #expect(step0.stepIndex == 0)
        #expect(step1.stepIndex == 1)
        #expect(step2.stepIndex == 2)
    }

    @Test("Step index can be large number")
    func testLargeStepIndex() {
        let result = AIStepResult(stepIndex: 999, text: "Many steps later")
        #expect(result.stepIndex == 999)
    }

    // MARK: - Tool Calls and Results

    @Test("Tool calls are preserved")
    func testToolCallsPreserved() {
        let toolCalls = [
            AIToolCallResult(id: "call-1", name: "search", arguments: "{\"query\":\"weather\"}"),
            AIToolCallResult(id: "call-2", name: "fetch", arguments: "{\"url\":\"example.com\"}")
        ]

        let result = AIStepResult(
            stepIndex: 0,
            text: "Using tools",
            toolCalls: toolCalls
        )

        #expect(result.toolCalls.count == 2)
        #expect(result.toolCalls[0].id == "call-1")
        #expect(result.toolCalls[0].name == "search")
        #expect(result.toolCalls[1].id == "call-2")
        #expect(result.toolCalls[1].name == "fetch")
    }

    @Test("Tool results are included")
    func testToolResultsIncluded() {
        let toolResults = [
            AIToolResultData(id: "call-1", result: "Sunny, 72F", metadata: nil),
            AIToolResultData(id: "call-2", result: "Page content here", metadata: nil)
        ]

        let result = AIStepResult(
            stepIndex: 0,
            text: "Got results",
            toolResults: toolResults
        )

        #expect(result.toolResults.count == 2)
        #expect(result.toolResults[0].result == "Sunny, 72F")
        #expect(result.toolResults[1].result == "Page content here")
    }

    @Test("Tool calls match their results")
    func testToolCallsMatchResults() {
        let toolCalls = [
            AIToolCallResult(id: "call-abc", name: "get_weather", arguments: "{}")
        ]
        let toolResults = [
            AIToolResultData(id: "call-abc", result: "72F", metadata: nil)
        ]

        let result = AIStepResult(
            stepIndex: 0,
            text: "",
            toolCalls: toolCalls,
            toolResults: toolResults
        )

        #expect(result.toolCalls[0].id == result.toolResults[0].id)
    }

    // MARK: - Usage Tracking

    @Test("Usage is aggregated per step")
    func testUsageAggregatedPerStep() {
        let usage = AIUsage(promptTokens: 150, completionTokens: 75, totalTokens: 225)
        let result = AIStepResult(stepIndex: 0, text: "Test", usage: usage)

        #expect(result.usage.promptTokens == 150)
        #expect(result.usage.completionTokens == 75)
        #expect(result.usage.totalTokens == 225)
    }

    @Test("totalTokens helper returns correct sum")
    func testTotalTokens() {
        let usage = AIUsage(promptTokens: 100, completionTokens: 50)
        let result = AIStepResult(stepIndex: 0, text: "Test", usage: usage)

        #expect(result.totalTokens == 150)
    }

    // MARK: - Helper Properties

    @Test("hasToolCalls returns correct value")
    func testHasToolCalls() {
        let withoutTools = AIStepResult(stepIndex: 0, text: "No tools")
        let withTools = AIStepResult(
            stepIndex: 0,
            text: "With tools",
            toolCalls: [AIToolCallResult(id: "1", name: "test", arguments: "{}")]
        )

        #expect(withoutTools.hasToolCalls == false)
        #expect(withTools.hasToolCalls == true)
    }

    @Test("hasToolResults returns correct value")
    func testHasToolResults() {
        let withoutResults = AIStepResult(stepIndex: 0, text: "No results")
        let withResults = AIStepResult(
            stepIndex: 0,
            text: "With results",
            toolResults: [AIToolResultData(id: "1", result: "done", metadata: nil)]
        )

        #expect(withoutResults.hasToolResults == false)
        #expect(withResults.hasToolResults == true)
    }

    @Test("completedNormally checks finish reason")
    func testCompletedNormally() {
        let stopResult = AIStepResult(stepIndex: 0, text: "Done", finishReason: .stop)
        let toolCallsResult = AIStepResult(stepIndex: 0, text: "Done", finishReason: .toolCalls)
        let lengthResult = AIStepResult(stepIndex: 0, text: "Truncated", finishReason: .length)
        let errorResult = AIStepResult(stepIndex: 0, text: "Error", finishReason: .error)

        #expect(stopResult.completedNormally == true)
        #expect(toolCallsResult.completedNormally == true)
        #expect(lengthResult.completedNormally == false)
        #expect(errorResult.completedNormally == false)
    }

    @Test("wasTruncated checks for length finish reason")
    func testWasTruncated() {
        let normalResult = AIStepResult(stepIndex: 0, text: "Done", finishReason: .stop)
        let truncatedResult = AIStepResult(stepIndex: 0, text: "Truncated...", finishReason: .length)

        #expect(normalResult.wasTruncated == false)
        #expect(truncatedResult.wasTruncated == true)
    }

    // MARK: - Encoding/Decoding (Codable)

    @Test("Step result encodes correctly")
    func testStepResultEncoding() throws {
        let toolCalls = [
            AIToolCallResult(id: "call-1", name: "test", arguments: "{}")
        ]
        let usage = AIUsage(promptTokens: 10, completionTokens: 5)
        let result = AIStepResult(
            stepIndex: 2,
            text: "Test text",
            toolCalls: toolCalls,
            usage: usage,
            finishReason: .stop
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(result)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("\"stepIndex\":2"))
        #expect(jsonString.contains("\"text\":\"Test text\""))
        #expect(jsonString.contains("\"call-1\""))
    }

    @Test("Step result decodes correctly")
    func testStepResultDecoding() throws {
        let json = """
        {
            "stepIndex": 5,
            "text": "Decoded text",
            "toolCalls": [{"id": "tc-1", "name": "search", "arguments": "{}"}],
            "toolResults": [],
            "usage": {"promptTokens": 20, "completionTokens": 10, "totalTokens": 30},
            "finishReason": "stop"
        }
        """

        let decoder = JSONDecoder()
        let result = try decoder.decode(AIStepResult.self, from: json.data(using: .utf8)!)

        #expect(result.stepIndex == 5)
        #expect(result.text == "Decoded text")
        #expect(result.toolCalls.count == 1)
        #expect(result.toolCalls[0].name == "search")
        #expect(result.usage.promptTokens == 20)
        #expect(result.finishReason == .stop)
    }

    @Test("Step result round-trips through encoding")
    func testEncodingRoundTrip() throws {
        let original = AIStepResult(
            stepIndex: 3,
            text: "Round trip test",
            toolCalls: [AIToolCallResult(id: "id-1", name: "tool", arguments: "{\"key\":\"value\"}")],
            toolResults: [],
            usage: AIUsage(promptTokens: 50, completionTokens: 25),
            finishReason: .toolCalls
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(AIStepResult.self, from: data)

        #expect(decoded.stepIndex == original.stepIndex)
        #expect(decoded.text == original.text)
        #expect(decoded.toolCalls.count == original.toolCalls.count)
        #expect(decoded.usage.promptTokens == original.usage.promptTokens)
        #expect(decoded.finishReason == original.finishReason)
    }

    // MARK: - Equatable

    @Test("Results are equatable")
    func testEquatable() {
        let result1 = AIStepResult(stepIndex: 0, text: "Hello", finishReason: .stop)
        let result2 = AIStepResult(stepIndex: 0, text: "Hello", finishReason: .stop)
        let result3 = AIStepResult(stepIndex: 1, text: "Hello", finishReason: .stop)
        let result4 = AIStepResult(stepIndex: 0, text: "World", finishReason: .stop)

        #expect(result1 == result2)
        #expect(result1 != result3) // Different step index
        #expect(result1 != result4) // Different text
    }

    // MARK: - Various Finish Reasons

    @Test("All finish reasons are handled")
    func testAllFinishReasons() {
        let reasons: [AIFinishReason] = [
            .stop, .length, .toolCalls, .contentFilter, .error, .cancelled, .unknown
        ]

        for reason in reasons {
            let result = AIStepResult(stepIndex: 0, text: "Test", finishReason: reason)
            #expect(result.finishReason == reason)
        }
    }

    // MARK: - Empty Step

    @Test("Empty step has correct defaults")
    func testEmptyStep() {
        let empty = AIStepResult.empty

        #expect(empty.stepIndex == 0)
        #expect(empty.text == "")
        #expect(empty.toolCalls.isEmpty)
        #expect(empty.toolResults.isEmpty)
        #expect(empty.usage == .zero)
        #expect(empty.finishReason == .stop)
    }
}
