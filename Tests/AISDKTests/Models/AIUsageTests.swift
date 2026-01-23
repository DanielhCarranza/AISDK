//
//  AIUsageTests.swift
//  AISDK
//
//  Tests for AIUsage and AIFinishReason
//

import Foundation
import Testing
@testable import AISDK

@Suite("AIUsage Tests")
struct AIUsageTests {
    // MARK: - Basic Initialization

    @Test("Creates usage with minimal parameters")
    func testMinimalInit() {
        let usage = AIUsage(promptTokens: 100, completionTokens: 50)

        #expect(usage.promptTokens == 100)
        #expect(usage.completionTokens == 50)
        #expect(usage.totalTokens == 150)
        #expect(usage.reasoningTokens == nil)
        #expect(usage.cachedTokens == nil)
    }

    @Test("Total tokens is computed from prompt and completion")
    func testTotalTokensComputed() {
        let usage = AIUsage(promptTokens: 100, completionTokens: 50)

        // totalTokens should always be computed, never stored separately
        #expect(usage.totalTokens == 150)
    }

    @Test("Creates usage with all parameters")
    func testFullInit() {
        let usage = AIUsage(
            promptTokens: 100,
            completionTokens: 50,
            reasoningTokens: 20,
            cachedTokens: 30
        )

        #expect(usage.promptTokens == 100)
        #expect(usage.completionTokens == 50)
        #expect(usage.totalTokens == 150)
        #expect(usage.reasoningTokens == 20)
        #expect(usage.cachedTokens == 30)
    }

    // MARK: - Zero Usage

    @Test("Zero usage has all values at zero")
    func testZeroUsage() {
        let zero = AIUsage.zero

        #expect(zero.promptTokens == 0)
        #expect(zero.completionTokens == 0)
        #expect(zero.totalTokens == 0)
        #expect(zero.reasoningTokens == nil)
        #expect(zero.cachedTokens == nil)
    }

    // MARK: - Addition Operator

    @Test("Adding two usages combines all values")
    func testAddition() {
        let usage1 = AIUsage(promptTokens: 100, completionTokens: 50)
        let usage2 = AIUsage(promptTokens: 200, completionTokens: 75)

        let combined = usage1 + usage2

        #expect(combined.promptTokens == 300)
        #expect(combined.completionTokens == 125)
        #expect(combined.totalTokens == 425)
    }

    @Test("Adding usages with reasoning tokens")
    func testAdditionWithReasoningTokens() {
        let usage1 = AIUsage(promptTokens: 100, completionTokens: 50, reasoningTokens: 10)
        let usage2 = AIUsage(promptTokens: 200, completionTokens: 75, reasoningTokens: 20)

        let combined = usage1 + usage2

        #expect(combined.reasoningTokens == 30)
    }

    @Test("Adding usages with nil reasoning tokens")
    func testAdditionWithNilReasoningTokens() {
        let usage1 = AIUsage(promptTokens: 100, completionTokens: 50)
        let usage2 = AIUsage(promptTokens: 200, completionTokens: 75, reasoningTokens: 20)

        let combined = usage1 + usage2

        #expect(combined.reasoningTokens == 20)
    }

    @Test("Adding usages where both have nil reasoning tokens")
    func testAdditionBothNilReasoningTokens() {
        let usage1 = AIUsage(promptTokens: 100, completionTokens: 50)
        let usage2 = AIUsage(promptTokens: 200, completionTokens: 75)

        let combined = usage1 + usage2

        #expect(combined.reasoningTokens == nil)
    }

    @Test("Adding usages with cached tokens")
    func testAdditionWithCachedTokens() {
        let usage1 = AIUsage(promptTokens: 100, completionTokens: 50, cachedTokens: 25)
        let usage2 = AIUsage(promptTokens: 200, completionTokens: 75, cachedTokens: 50)

        let combined = usage1 + usage2

        #expect(combined.cachedTokens == 75)
    }

    // MARK: - Equatable

    @Test("Usages are equatable")
    func testEquatable() {
        let usage1 = AIUsage(promptTokens: 100, completionTokens: 50)
        let usage2 = AIUsage(promptTokens: 100, completionTokens: 50)
        let usage3 = AIUsage(promptTokens: 100, completionTokens: 60)

        #expect(usage1 == usage2)
        #expect(usage1 != usage3)
    }

    @Test("Zero equals zero")
    func testZeroEquality() {
        let zero1 = AIUsage.zero
        let zero2 = AIUsage(promptTokens: 0, completionTokens: 0)

        #expect(zero1 == zero2)
    }

    // MARK: - Hashable

    @Test("Usages are hashable")
    func testHashable() {
        let usage1 = AIUsage(promptTokens: 100, completionTokens: 50)
        let usage2 = AIUsage(promptTokens: 100, completionTokens: 50)
        let usage3 = AIUsage(promptTokens: 200, completionTokens: 100)

        var set: Set<AIUsage> = []
        set.insert(usage1)
        set.insert(usage2)
        set.insert(usage3)

        #expect(set.count == 2)
    }

    // MARK: - Codable

    @Test("Usage encodes and decodes correctly")
    func testCodable() throws {
        let original = AIUsage(
            promptTokens: 100,
            completionTokens: 50,
            reasoningTokens: 20,
            cachedTokens: 30
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIUsage.self, from: data)

        #expect(decoded == original)
    }

    @Test("Usage decodes from JSON with nil optionals")
    func testDecodeWithNilOptionals() throws {
        let json = """
        {
            "prompt_tokens": 100,
            "completion_tokens": 50
        }
        """

        let decoder = JSONDecoder()
        let usage = try decoder.decode(AIUsage.self, from: json.data(using: .utf8)!)

        #expect(usage.promptTokens == 100)
        #expect(usage.completionTokens == 50)
        #expect(usage.totalTokens == 150)
        #expect(usage.reasoningTokens == nil)
        #expect(usage.cachedTokens == nil)
    }

    @Test("Usage encodes with snake_case keys")
    func testEncodesWithSnakeCase() throws {
        let usage = AIUsage(promptTokens: 100, completionTokens: 50, reasoningTokens: 20)

        let encoder = JSONEncoder()
        let data = try encoder.encode(usage)
        let jsonString = String(data: data, encoding: .utf8)!

        #expect(jsonString.contains("prompt_tokens"))
        #expect(jsonString.contains("completion_tokens"))
        #expect(jsonString.contains("reasoning_tokens"))
    }

    // MARK: - Legacy Initialization

    @Test("Legacy init with nil usage returns zero")
    func testLegacyInitNil() {
        let usage = AIUsage(legacy: nil)

        #expect(usage.promptTokens == 0)
        #expect(usage.completionTokens == 0)
        #expect(usage.totalTokens == 0)
        #expect(usage.reasoningTokens == nil)
    }
}

// MARK: - AIFinishReason Tests

@Suite("AIFinishReason Tests")
struct AIFinishReasonTests {
    // MARK: - Raw Values

    @Test("All finish reasons have correct raw values")
    func testRawValues() {
        #expect(AIFinishReason.stop.rawValue == "stop")
        #expect(AIFinishReason.length.rawValue == "length")
        #expect(AIFinishReason.toolCalls.rawValue == "tool_calls")
        #expect(AIFinishReason.contentFilter.rawValue == "content_filter")
        #expect(AIFinishReason.error.rawValue == "error")
        #expect(AIFinishReason.cancelled.rawValue == "cancelled")
        #expect(AIFinishReason.unknown.rawValue == "unknown")
    }

    // MARK: - Legacy Reason Conversion

    @Test("Converts OpenAI stop reason")
    func testLegacyStop() {
        let reason = AIFinishReason(legacyReason: "stop")
        #expect(reason == .stop)
    }

    @Test("Converts Anthropic end_turn reason")
    func testLegacyEndTurn() {
        let reason = AIFinishReason(legacyReason: "end_turn")
        #expect(reason == .stop)
    }

    @Test("Converts Anthropic stop_sequence reason")
    func testLegacyStopSequence() {
        let reason = AIFinishReason(legacyReason: "stop_sequence")
        #expect(reason == .stop)
    }

    @Test("Converts length reason")
    func testLegacyLength() {
        let reason = AIFinishReason(legacyReason: "length")
        #expect(reason == .length)
    }

    @Test("Converts max_tokens reason")
    func testLegacyMaxTokens() {
        let reason = AIFinishReason(legacyReason: "max_tokens")
        #expect(reason == .length)
    }

    @Test("Converts tool_calls reason")
    func testLegacyToolCalls() {
        let reason = AIFinishReason(legacyReason: "tool_calls")
        #expect(reason == .toolCalls)
    }

    @Test("Converts function_call reason")
    func testLegacyFunctionCall() {
        let reason = AIFinishReason(legacyReason: "function_call")
        #expect(reason == .toolCalls)
    }

    @Test("Converts tool_use reason (Anthropic)")
    func testLegacyToolUse() {
        let reason = AIFinishReason(legacyReason: "tool_use")
        #expect(reason == .toolCalls)
    }

    @Test("Converts content_filter reason")
    func testLegacyContentFilter() {
        let reason = AIFinishReason(legacyReason: "content_filter")
        #expect(reason == .contentFilter)
    }

    @Test("Converts safety reason")
    func testLegacySafety() {
        let reason = AIFinishReason(legacyReason: "safety")
        #expect(reason == .contentFilter)
    }

    @Test("Converts cancelled and canceled spellings")
    func testLegacyCancelled() {
        let reason1 = AIFinishReason(legacyReason: "cancelled")
        let reason2 = AIFinishReason(legacyReason: "canceled")

        #expect(reason1 == .cancelled)
        #expect(reason2 == .cancelled)
    }

    @Test("Unknown reason converts to unknown")
    func testLegacyUnknown() {
        let reason = AIFinishReason(legacyReason: "some_random_reason")
        #expect(reason == .unknown)
    }

    @Test("Nil reason converts to unknown")
    func testNilReason() {
        let reason = AIFinishReason(legacyReason: nil)
        #expect(reason == .unknown)
    }

    @Test("Case insensitive conversion")
    func testCaseInsensitiveConversion() {
        let reason1 = AIFinishReason(legacyReason: "STOP")
        let reason2 = AIFinishReason(legacyReason: "Stop")
        let reason3 = AIFinishReason(legacyReason: "TOOL_CALLS")

        #expect(reason1 == .stop)
        #expect(reason2 == .stop)
        #expect(reason3 == .toolCalls)
    }

    // MARK: - isSuccess Property

    @Test("Stop is successful")
    func testStopIsSuccess() {
        #expect(AIFinishReason.stop.isSuccess == true)
    }

    @Test("Length is successful (completed but truncated)")
    func testLengthIsSuccess() {
        #expect(AIFinishReason.length.isSuccess == true)
    }

    @Test("Tool calls is successful")
    func testToolCallsIsSuccess() {
        #expect(AIFinishReason.toolCalls.isSuccess == true)
    }

    @Test("Content filter is not successful")
    func testContentFilterNotSuccess() {
        #expect(AIFinishReason.contentFilter.isSuccess == false)
    }

    @Test("Error is not successful")
    func testErrorNotSuccess() {
        #expect(AIFinishReason.error.isSuccess == false)
    }

    @Test("Cancelled is not successful")
    func testCancelledNotSuccess() {
        #expect(AIFinishReason.cancelled.isSuccess == false)
    }

    @Test("Unknown is not successful")
    func testUnknownNotSuccess() {
        #expect(AIFinishReason.unknown.isSuccess == false)
    }

    // MARK: - mayBeTruncated Property

    @Test("Length may be truncated")
    func testLengthMayBeTruncated() {
        #expect(AIFinishReason.length.mayBeTruncated == true)
    }

    @Test("Stop is not truncated")
    func testStopNotTruncated() {
        #expect(AIFinishReason.stop.mayBeTruncated == false)
    }

    @Test("Tool calls is not truncated")
    func testToolCallsNotTruncated() {
        #expect(AIFinishReason.toolCalls.mayBeTruncated == false)
    }

    // MARK: - CaseIterable

    @Test("All cases are iterable")
    func testCaseIterable() {
        let allCases = AIFinishReason.allCases

        #expect(allCases.count == 7)
        #expect(allCases.contains(.stop))
        #expect(allCases.contains(.length))
        #expect(allCases.contains(.toolCalls))
        #expect(allCases.contains(.contentFilter))
        #expect(allCases.contains(.error))
        #expect(allCases.contains(.cancelled))
        #expect(allCases.contains(.unknown))
    }

    // MARK: - Codable

    @Test("Finish reason encodes and decodes correctly")
    func testCodable() throws {
        let original = AIFinishReason.toolCalls

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIFinishReason.self, from: data)

        #expect(decoded == original)
    }

    @Test("Decodes from JSON string")
    func testDecodeFromString() throws {
        let json = "\"tool_calls\""

        let decoder = JSONDecoder()
        let reason = try decoder.decode(AIFinishReason.self, from: json.data(using: .utf8)!)

        #expect(reason == .toolCalls)
    }

    @Test("Decodes unknown future values to unknown")
    func testDecodesUnknownFutureValues() throws {
        let json = "\"some_new_future_reason\""

        let decoder = JSONDecoder()
        let reason = try decoder.decode(AIFinishReason.self, from: json.data(using: .utf8)!)

        #expect(reason == .unknown)
    }

    @Test("Case insensitive decoding")
    func testCaseInsensitiveDecoding() throws {
        let json = "\"STOP\""

        let decoder = JSONDecoder()
        let reason = try decoder.decode(AIFinishReason.self, from: json.data(using: .utf8)!)

        #expect(reason == .stop)
    }
}
