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

    func test_strategy_autoRepairMax_with_zero_does_not_allow_repair() {
        let strategy = ToolCallRepair.Strategy.autoRepairMax(0)
        XCTAssertFalse(strategy.allowsRepair)
        XCTAssertEqual(strategy.maxAttempts, 0)
    }

    func test_strategy_autoRepairMax_with_negative_does_not_allow_repair() {
        let strategy = ToolCallRepair.Strategy.autoRepairMax(-5)
        XCTAssertFalse(strategy.allowsRepair)
        XCTAssertEqual(strategy.maxAttempts, 0)
    }

    func test_strategy_custom_allows_repair() {
        let strategy = ToolCallRepair.Strategy.custom { _, _, _ in nil }
        XCTAssertTrue(strategy.allowsRepair)
        XCTAssertEqual(strategy.maxAttempts, 1)
    }

    func test_strategy_default_is_autoRepairOnce() {
        let strategy = ToolCallRepair.Strategy.default
        XCTAssertTrue(strategy.matches(.autoRepairOnce))
    }

    // MARK: - Strategy Matching Tests

    func test_strategy_matches_strict() {
        XCTAssertTrue(ToolCallRepair.Strategy.strict.matches(.strict))
        XCTAssertFalse(ToolCallRepair.Strategy.strict.matches(.autoRepairOnce))
    }

    func test_strategy_matches_autoRepairOnce() {
        XCTAssertTrue(ToolCallRepair.Strategy.autoRepairOnce.matches(.autoRepairOnce))
        XCTAssertFalse(ToolCallRepair.Strategy.autoRepairOnce.matches(.strict))
    }

    func test_strategy_matches_autoRepairMax() {
        XCTAssertTrue(ToolCallRepair.Strategy.autoRepairMax(3).matches(.autoRepairMax(3)))
        XCTAssertFalse(ToolCallRepair.Strategy.autoRepairMax(3).matches(.autoRepairMax(5)))
    }

    func test_strategy_matches_custom_by_type() {
        let custom1 = ToolCallRepair.Strategy.custom { _, _, _ in nil }
        let custom2 = ToolCallRepair.Strategy.custom { _, _, _ in nil }
        // Custom strategies match by type, not by closure identity
        XCTAssertTrue(custom1.matches(custom2))
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

    // MARK: - RequestContext Tests

    func test_requestContext_default_values() {
        let context = ToolCallRepair.RequestContext()
        XCTAssertNil(context.allowedProviders)
        XCTAssertEqual(context.sensitivity, .standard)
        XCTAssertNil(context.metadata)
    }

    func test_requestContext_from_request() {
        let request = AITextRequest(
            messages: [.user("test")],
            allowedProviders: ["provider1"],
            sensitivity: .phi,
            metadata: ["key": "value"]
        )
        let context = ToolCallRepair.RequestContext.from(request)
        XCTAssertEqual(context.allowedProviders, ["provider1"])
        XCTAssertEqual(context.sensitivity, .phi)
        XCTAssertEqual(context.metadata, ["key": "value"])
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

    func test_repair_accepts_generic_error() async throws {
        // Mock model that returns corrected JSON
        let mock = MockAILanguageModel.withResponse(#"{"query": "fixed"}"#)

        let originalCall = AIToolCallResult(
            id: "call-1",
            name: "search",
            arguments: #"{"broken": true}"#
        )
        // Use a generic NSError instead of ToolError
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Generic error"])

        let repaired = try await ToolCallRepair.repair(
            toolCall: originalCall,
            error: error,
            model: mock
        )

        XCTAssertNotNil(repaired)
        XCTAssertEqual(repaired?.arguments, #"{"query": "fixed"}"#)
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

    func test_repair_returns_nil_for_json_array_response() async throws {
        // Mock model that returns a JSON array (invalid for tool arguments)
        let mock = MockAILanguageModel.withResponse(#"["item1", "item2"]"#)

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

        XCTAssertNil(repaired, "Should return nil when model returns JSON array instead of object")
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

    func test_repair_preserves_request_context() async throws {
        let mock = MockAILanguageModel.withResponse(#"{"fixed": true}"#)

        let originalCall = AIToolCallResult(
            id: "1",
            name: "test",
            arguments: #"{"broken": true}"#
        )
        let error = ToolError.invalidParameters("test")

        let context = ToolCallRepair.RequestContext(
            allowedProviders: ["safe-provider"],
            sensitivity: .phi,
            metadata: ["trace": "123"]
        )

        _ = try await ToolCallRepair.repair(
            toolCall: originalCall,
            error: error,
            model: mock,
            requestContext: context
        )

        // Verify the request preserved context settings
        XCTAssertNotNil(mock.lastTextRequest)
        XCTAssertEqual(mock.lastTextRequest?.allowedProviders, ["safe-provider"])
        XCTAssertEqual(mock.lastTextRequest?.sensitivity, .phi)
        XCTAssertEqual(mock.lastTextRequest?.metadata, ["trace": "123"])
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

    func test_attemptRepair_custom_receives_generic_error() async throws {
        var receivedError: Error?

        let customStrategy = ToolCallRepair.Strategy.custom { call, error, _ in
            receivedError = error
            return AIToolCallResult(id: call.id, name: call.name, arguments: #"{"fixed": true}"#)
        }

        let mock = MockAILanguageModel.withResponse("{}")
        let originalCall = AIToolCallResult(id: "1", name: "test", arguments: "{}")
        let error = NSError(domain: "test", code: 42, userInfo: nil)

        _ = try await ToolCallRepair.attemptRepair(
            toolCall: originalCall,
            error: error,
            model: mock,
            strategy: customStrategy
        )

        XCTAssertNotNil(receivedError)
        XCTAssertEqual((receivedError as NSError?)?.code, 42)
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

    func test_attemptRepair_autoRepairMax_succeeds_on_first_attempt() async throws {
        // Mock returns valid JSON on first call
        let mock = MockAILanguageModel.withResponse(#"{"fixed": "first"}"#)

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
            strategy: .autoRepairMax(3)
        )

        XCTAssertEqual(mock.requestCount, 1, "Should succeed on first attempt")
        if case .repaired(let call) = result {
            XCTAssertEqual(call.arguments, #"{"fixed": "first"}"#)
        } else {
            XCTFail("Expected .repaired result")
        }
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

        XCTAssertEqual(mock.requestCount, 2, "Should exhaust all 2 attempts")
        if case .failed(let reason) = result {
            XCTAssertTrue(reason.contains("Exhausted"))
            XCTAssertTrue(reason.contains("2"))
        } else {
            XCTFail("Expected .failed result after exhausting attempts")
        }
    }

    func test_attemptRepair_autoRepairMax_with_zero_returns_failed() async throws {
        let mock = MockAILanguageModel.withResponse(#"{"fixed": true}"#)

        let originalCall = AIToolCallResult(id: "1", name: "test", arguments: "{}")
        let error = ToolError.invalidParameters("test")

        let result = try await ToolCallRepair.attemptRepair(
            toolCall: originalCall,
            error: error,
            model: mock,
            strategy: .autoRepairMax(0)
        )

        XCTAssertEqual(mock.requestCount, 0, "Should not make any requests with zero attempts")
        if case .failed(let reason) = result {
            XCTAssertTrue(reason.contains("Invalid maxAttempts"))
        } else {
            XCTFail("Expected .failed result for zero attempts")
        }
    }

    func test_attemptRepair_autoRepairMax_with_negative_returns_failed() async throws {
        let mock = MockAILanguageModel.withResponse(#"{"fixed": true}"#)

        let originalCall = AIToolCallResult(id: "1", name: "test", arguments: "{}")
        let error = ToolError.invalidParameters("test")

        let result = try await ToolCallRepair.attemptRepair(
            toolCall: originalCall,
            error: error,
            model: mock,
            strategy: .autoRepairMax(-1)
        )

        XCTAssertEqual(mock.requestCount, 0, "Should not make any requests with negative attempts")
        if case .failed(let reason) = result {
            XCTAssertTrue(reason.contains("Invalid maxAttempts"))
        } else {
            XCTFail("Expected .failed result for negative attempts")
        }
    }

    // MARK: - Integration with Tool Schema

    func test_repair_uses_tool_schema_when_provided() async throws {
        let mock = MockAILanguageModel.withResponse(#"{"location": "New York"}"#)

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
