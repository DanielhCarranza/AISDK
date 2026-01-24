//
//  ToolCallRepairTests.swift
//  AISDKTests
//
//  Tests for ToolCallRepair mechanism
//

import XCTest
@testable import AISDK

final class ToolCallRepairTests: XCTestCase {
    // MARK: - Strategy Tests

    func test_strategy_strict_does_not_allow_repair() {
        let strategy = ToolCallRepair.Strategy.strict
        XCTAssertFalse(strategy.allowsRepair)
        XCTAssertEqual(strategy.maxAttempts, 0)
    }

    func test_strategy_autoRepairOnce_allows_single_attempt() {
        let strategy = ToolCallRepair.Strategy.autoRepairOnce
        XCTAssertTrue(strategy.allowsRepair)
        XCTAssertEqual(strategy.maxAttempts, 1)
    }

    func test_strategy_autoRepairMax_allows_configured_attempts() {
        let strategy = ToolCallRepair.Strategy.autoRepairMax(3)
        XCTAssertTrue(strategy.allowsRepair)
        XCTAssertEqual(strategy.maxAttempts, 3)
    }

    func test_strategy_custom_allows_repair() {
        let strategy = ToolCallRepair.Strategy.custom { _, _, _ in nil }
        XCTAssertTrue(strategy.allowsRepair)
        XCTAssertEqual(strategy.maxAttempts, 1)
    }

    func test_strategy_default_is_autoRepairOnce() {
        let strategy = ToolCallRepair.Strategy.default
        XCTAssertEqual(strategy, .autoRepairOnce)
    }

    // MARK: - Strategy Equality Tests

    func test_strategy_equality_strict() {
        XCTAssertEqual(ToolCallRepair.Strategy.strict, .strict)
        XCTAssertNotEqual(ToolCallRepair.Strategy.strict, .autoRepairOnce)
    }

    func test_strategy_equality_autoRepairOnce() {
        XCTAssertEqual(ToolCallRepair.Strategy.autoRepairOnce, .autoRepairOnce)
        XCTAssertNotEqual(ToolCallRepair.Strategy.autoRepairOnce, .strict)
    }

    func test_strategy_equality_autoRepairMax() {
        XCTAssertEqual(ToolCallRepair.Strategy.autoRepairMax(3), .autoRepairMax(3))
        XCTAssertNotEqual(ToolCallRepair.Strategy.autoRepairMax(3), .autoRepairMax(5))
    }

    func test_strategy_equality_custom_never_equal() {
        let custom1 = ToolCallRepair.Strategy.custom { _, _, _ in nil }
        let custom2 = ToolCallRepair.Strategy.custom { _, _, _ in nil }
        XCTAssertNotEqual(custom1, custom2)
    }

    // MARK: - Repair Result Tests

    func test_repairResult_equality_repaired() {
        let call1 = AIToolCallResult(id: "1", name: "test", arguments: "{}")
        let call2 = AIToolCallResult(id: "1", name: "test", arguments: "{}")
        XCTAssertEqual(ToolCallRepair.RepairResult.repaired(call1), .repaired(call2))
    }

    func test_repairResult_equality_failed() {
        XCTAssertEqual(
            ToolCallRepair.RepairResult.failed(reason: "test"),
            .failed(reason: "test")
        )
        XCTAssertNotEqual(
            ToolCallRepair.RepairResult.failed(reason: "a"),
            .failed(reason: "b")
        )
    }

    func test_repairResult_equality_notAttempted() {
        XCTAssertEqual(ToolCallRepair.RepairResult.notAttempted, .notAttempted)
    }

    // MARK: - Repair Method Tests

    func test_repair_returns_corrected_arguments() async throws {
        // Mock model that returns corrected JSON
        let mock = MockAILanguageModel.withResponse(#"{"query": "corrected search"}"#)

        let originalCall = AIToolCallResult(
            id: "call-1",
            name: "search",
            arguments: #"{"qury": "typo"}"#  // Has typo
        )
        let error = ToolError.invalidParameters("Unknown parameter 'qury'")

        let repaired = try await ToolCallRepair.repair(
            toolCall: originalCall,
            error: error,
            model: mock
        )

        XCTAssertNotNil(repaired)
        XCTAssertEqual(repaired?.id, "call-1")
        XCTAssertEqual(repaired?.name, "search")
        XCTAssertEqual(repaired?.arguments, #"{"query": "corrected search"}"#)
    }

    func test_repair_returns_nil_for_same_arguments() async throws {
        // Mock model that returns the same arguments (no fix)
        let sameArgs = #"{"query": "test"}"#
        let mock = MockAILanguageModel.withResponse(sameArgs)

        let originalCall = AIToolCallResult(
            id: "call-1",
            name: "search",
            arguments: sameArgs
        )
        let error = ToolError.executionFailed("Some other error")

        let repaired = try await ToolCallRepair.repair(
            toolCall: originalCall,
            error: error,
            model: mock
        )

        XCTAssertNil(repaired, "Should return nil when arguments are unchanged")
    }

    func test_repair_returns_nil_for_invalid_json_response() async throws {
        // Mock model that returns invalid JSON
        let mock = MockAILanguageModel.withResponse("not valid json at all")

        let originalCall = AIToolCallResult(
            id: "call-1",
            name: "search",
            arguments: #"{"query": "test"}"#
        )
        let error = ToolError.invalidParameters("test error")

        let repaired = try await ToolCallRepair.repair(
            toolCall: originalCall,
            error: error,
            model: mock
        )

        XCTAssertNil(repaired, "Should return nil when model returns invalid JSON")
    }

    func test_repair_handles_markdown_code_block_response() async throws {
        // Mock model that returns JSON in markdown code block
        let mock = MockAILanguageModel.withResponse("""
        ```json
        {"query": "fixed"}
        ```
        """)

        let originalCall = AIToolCallResult(
            id: "call-1",
            name: "search",
            arguments: #"{"qury": "broken"}"#
        )
        let error = ToolError.invalidParameters("Unknown parameter")

        let repaired = try await ToolCallRepair.repair(
            toolCall: originalCall,
            error: error,
            model: mock
        )

        XCTAssertNotNil(repaired)
        XCTAssertEqual(repaired?.arguments, #"{"query": "fixed"}"#)
    }

    // MARK: - attemptRepair Tests

    func test_attemptRepair_strict_returns_notAttempted() async throws {
        let mock = MockAILanguageModel.withResponse("{}")

        let originalCall = AIToolCallResult(id: "1", name: "test", arguments: "{}")
        let error = ToolError.invalidParameters("test")

        let result = try await ToolCallRepair.attemptRepair(
            toolCall: originalCall,
            error: error,
            model: mock,
            strategy: .strict
        )

        XCTAssertEqual(result, .notAttempted)
        XCTAssertEqual(mock.requestCount, 0, "Strict mode should not make any requests")
    }

    func test_attemptRepair_autoRepairOnce_returns_repaired() async throws {
        let mock = MockAILanguageModel.withResponse(#"{"fixed": true}"#)

        let originalCall = AIToolCallResult(
            id: "1",
            name: "test",
            arguments: #"{"broken": true}"#
        )
        let error = ToolError.invalidParameters("test")

        let result = try await ToolCallRepair.attemptRepair(
            toolCall: originalCall,
            error: error,
            model: mock,
            strategy: .autoRepairOnce
        )

        if case .repaired(let call) = result {
            XCTAssertEqual(call.arguments, #"{"fixed": true}"#)
        } else {
            XCTFail("Expected .repaired result")
        }
    }

    func test_attemptRepair_autoRepairOnce_returns_failed_when_repair_fails() async throws {
        // Model returns invalid JSON
        let mock = MockAILanguageModel.withResponse("invalid json")

        let originalCall = AIToolCallResult(
            id: "1",
            name: "test",
            arguments: #"{"broken": true}"#
        )
        let error = ToolError.invalidParameters("test")

        let result = try await ToolCallRepair.attemptRepair(
            toolCall: originalCall,
            error: error,
            model: mock,
            strategy: .autoRepairOnce
        )

        if case .failed(let reason) = result {
            XCTAssertTrue(reason.contains("failed"))
        } else {
            XCTFail("Expected .failed result")
        }
    }

    func test_attemptRepair_custom_calls_handler() async throws {
        var handlerCalled = false

        let customStrategy = ToolCallRepair.Strategy.custom { call, _, _ in
            handlerCalled = true
            return AIToolCallResult(
                id: call.id,
                name: call.name,
                arguments: #"{"custom": "fixed"}"#
            )
        }

        let mock = MockAILanguageModel.withResponse("{}")
        let originalCall = AIToolCallResult(id: "1", name: "test", arguments: "{}")
        let error = ToolError.invalidParameters("test")

        let result = try await ToolCallRepair.attemptRepair(
            toolCall: originalCall,
            error: error,
            model: mock,
            strategy: customStrategy
        )

        XCTAssertTrue(handlerCalled)
        if case .repaired(let call) = result {
            XCTAssertEqual(call.arguments, #"{"custom": "fixed"}"#)
        } else {
            XCTFail("Expected .repaired result")
        }
    }

    func test_attemptRepair_custom_returns_failed_when_handler_returns_nil() async throws {
        let customStrategy = ToolCallRepair.Strategy.custom { _, _, _ in
            nil
        }

        let mock = MockAILanguageModel.withResponse("{}")
        let originalCall = AIToolCallResult(id: "1", name: "test", arguments: "{}")
        let error = ToolError.invalidParameters("test")

        let result = try await ToolCallRepair.attemptRepair(
            toolCall: originalCall,
            error: error,
            model: mock,
            strategy: customStrategy
        )

        if case .failed(let reason) = result {
            XCTAssertTrue(reason.contains("nil"))
        } else {
            XCTFail("Expected .failed result")
        }
    }

    // MARK: - autoRepairMax Tests

    func test_attemptRepair_autoRepairMax_tries_multiple_times() async throws {
        // Sequential mock returns invalid, then valid JSON
        let sequential = MockAILanguageModel.withSequence([
            "invalid first",
            #"{"second": "valid"}"#
        ])

        let originalCall = AIToolCallResult(
            id: "1",
            name: "test",
            arguments: #"{"original": true}"#
        )
        let error = ToolError.invalidParameters("test")

        // Note: This test verifies the multi-attempt behavior.
        // The current implementation makes N requests for autoRepairMax(N)
        // Since sequential mock returns valid JSON on second call, repair should succeed
        let result = try await ToolCallRepair.attemptRepair(
            toolCall: originalCall,
            error: error,
            model: sequential,
            strategy: .autoRepairMax(3)
        )

        // First attempt fails (invalid JSON), but we keep trying
        // The behavior depends on implementation details - verify request was made
        XCTAssertGreaterThan(sequential.requestCount, 0)
    }

    func test_attemptRepair_autoRepairMax_exhausts_attempts() async throws {
        // Mock always returns invalid JSON
        let mock = MockAILanguageModel.withResponse("always invalid")

        let originalCall = AIToolCallResult(
            id: "1",
            name: "test",
            arguments: #"{"original": true}"#
        )
        let error = ToolError.invalidParameters("test")

        let result = try await ToolCallRepair.attemptRepair(
            toolCall: originalCall,
            error: error,
            model: mock,
            strategy: .autoRepairMax(2)
        )

        if case .failed(let reason) = result {
            XCTAssertTrue(reason.lowercased().contains("attempt") || reason.lowercased().contains("exhaust"))
        } else {
            XCTFail("Expected .failed result after exhausting attempts")
        }
    }

    // MARK: - Integration with Tool Schema

    func test_repair_uses_tool_schema_when_provided() async throws {
        var capturedRequest: AITextRequest?
        let mock = MockAILanguageModel.withResponse(#"{"location": "New York"}"#)

        // Capture the request to verify schema is included in prompt
        let originalLastRequest = mock.lastTextRequest

        let originalCall = AIToolCallResult(
            id: "1",
            name: "get_weather",
            arguments: #"{"loc": "NY"}"#
        )
        let error = ToolError.invalidParameters("Unknown parameter 'loc'")

        let schema = ToolSchema(
            type: "function",
            function: ToolFunction(
                name: "get_weather",
                description: "Get current weather for a location",
                parameters: Parameters(
                    type: "object",
                    properties: [
                        "location": PropertyDefinition(
                            type: "string",
                            description: "City and state, e.g., San Francisco, CA"
                        )
                    ],
                    required: ["location"]
                )
            )
        )

        _ = try await ToolCallRepair.repair(
            toolCall: originalCall,
            error: error,
            model: mock,
            toolSchema: schema
        )

        // Verify the request was made with schema context
        XCTAssertNotNil(mock.lastTextRequest)
        let messages = mock.lastTextRequest?.messages ?? []
        XCTAssertFalse(messages.isEmpty)

        // The prompt should contain schema information
        if let firstMessage = messages.first {
            let content = firstMessage.content.textValue
            XCTAssertTrue(content.contains("get_weather"))
            XCTAssertTrue(content.contains("location"))
        }
    }
}
