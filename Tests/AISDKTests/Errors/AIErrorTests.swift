//
//  AIErrorTests.swift
//  AISDKTests
//
//  Tests for AISDKErrorV2 and related error types
//

import XCTest
@testable import AISDK

final class AIErrorTests: XCTestCase {

    // MARK: - AIErrorCode Tests

    func testErrorCodeRetryable() {
        // Retryable errors
        XCTAssertTrue(AIErrorCode.rateLimitExceeded.isRetryable)
        XCTAssertTrue(AIErrorCode.providerUnavailable.isRetryable)
        XCTAssertTrue(AIErrorCode.networkFailed.isRetryable)
        XCTAssertTrue(AIErrorCode.timeout.isRetryable)
        XCTAssertTrue(AIErrorCode.streamConnectionFailed.isRetryable)
        XCTAssertTrue(AIErrorCode.streamInterrupted.isRetryable)
        XCTAssertTrue(AIErrorCode.streamTimeout.isRetryable)

        // Non-retryable errors
        XCTAssertFalse(AIErrorCode.invalidRequest.isRetryable)
        XCTAssertFalse(AIErrorCode.authenticationFailed.isRetryable)
        XCTAssertFalse(AIErrorCode.providerNotAllowed.isRetryable)
        XCTAssertFalse(AIErrorCode.contentFiltered.isRetryable)
    }

    func testErrorCodeClientError() {
        // Client errors
        XCTAssertTrue(AIErrorCode.invalidRequest.isClientError)
        XCTAssertTrue(AIErrorCode.missingParameter.isClientError)
        XCTAssertTrue(AIErrorCode.invalidModel.isClientError)
        XCTAssertTrue(AIErrorCode.validationFailed.isClientError)
        XCTAssertTrue(AIErrorCode.authenticationFailed.isClientError)
        XCTAssertTrue(AIErrorCode.quotaExceeded.isClientError)
        XCTAssertTrue(AIErrorCode.contextLengthExceeded.isClientError)
        XCTAssertTrue(AIErrorCode.invalidToolArguments.isClientError)
        XCTAssertTrue(AIErrorCode.providerNotAllowed.isClientError)
        XCTAssertTrue(AIErrorCode.phiRequiresAllowlist.isClientError)

        // Server/system errors
        XCTAssertFalse(AIErrorCode.networkFailed.isClientError)
        XCTAssertFalse(AIErrorCode.providerUnavailable.isClientError)
        XCTAssertFalse(AIErrorCode.internalError.isClientError)
    }

    func testErrorCodeSecurityRelated() {
        // Security-related errors
        XCTAssertTrue(AIErrorCode.providerNotAllowed.isSecurityRelated)
        XCTAssertTrue(AIErrorCode.phiRequiresAllowlist.isSecurityRelated)
        XCTAssertTrue(AIErrorCode.sensitiveDataExposure.isSecurityRelated)
        XCTAssertTrue(AIErrorCode.authenticationFailed.isSecurityRelated)

        // Non-security errors
        XCTAssertFalse(AIErrorCode.invalidRequest.isSecurityRelated)
        XCTAssertFalse(AIErrorCode.networkFailed.isSecurityRelated)
        XCTAssertFalse(AIErrorCode.toolExecutionFailed.isSecurityRelated)
    }

    func testErrorCodeCodable() throws {
        let code = AIErrorCode.rateLimitExceeded
        let encoded = try JSONEncoder().encode(code)
        let decoded = try JSONDecoder().decode(AIErrorCode.self, from: encoded)
        XCTAssertEqual(code, decoded)

        // Test raw value encoding
        let json = String(data: encoded, encoding: .utf8)!
        XCTAssertEqual(json, "\"rate_limit_exceeded\"")
    }

    // MARK: - AIErrorContext Tests

    func testErrorContextCreation() {
        let context = AIErrorContext(
            requestId: "req-123",
            provider: "openai",
            model: "gpt-4",
            statusCode: 429,
            phiRedacted: false,
            metadata: ["key": "value"]
        )

        XCTAssertEqual(context.requestId, "req-123")
        XCTAssertEqual(context.provider, "openai")
        XCTAssertEqual(context.model, "gpt-4")
        XCTAssertEqual(context.statusCode, 429)
        XCTAssertFalse(context.phiRedacted)
        XCTAssertEqual(context.metadata, ["key": "value"])
    }

    func testErrorContextEmpty() {
        let context = AIErrorContext.empty
        XCTAssertNil(context.requestId)
        XCTAssertNil(context.provider)
        XCTAssertNil(context.model)
        XCTAssertNil(context.statusCode)
        XCTAssertFalse(context.phiRedacted)
        XCTAssertTrue(context.metadata.isEmpty)
    }

    func testErrorContextRedaction() {
        let context = AIErrorContext(
            requestId: "req-123",
            provider: "openai",
            model: "gpt-4",
            statusCode: 200,
            phiRedacted: false,
            metadata: ["sensitive": "data"]
        )

        let redacted = context.redacted()

        // Should preserve non-PHI fields
        XCTAssertEqual(redacted.requestId, "req-123")
        XCTAssertEqual(redacted.provider, "openai")
        XCTAssertEqual(redacted.model, "gpt-4")
        XCTAssertEqual(redacted.statusCode, 200)

        // Should mark as redacted and clear metadata
        XCTAssertTrue(redacted.phiRedacted)
        XCTAssertTrue(redacted.metadata.isEmpty)
    }

    // MARK: - AISDKErrorV2 Factory Method Tests

    func testInvalidRequestError() {
        let error = AISDKErrorV2.invalidRequest("Bad parameters")
        XCTAssertEqual(error.code, .invalidRequest)
        XCTAssertEqual(error.message, "Bad parameters")
    }

    func testMissingParameterError() {
        let error = AISDKErrorV2.missingParameter("model")
        XCTAssertEqual(error.code, .missingParameter)
        XCTAssertTrue(error.message.contains("model"))
    }

    func testInvalidModelError() {
        let error = AISDKErrorV2.invalidModel("gpt-99")
        XCTAssertEqual(error.code, .invalidModel)
        XCTAssertTrue(error.message.contains("gpt-99"))
    }

    func testAuthenticationFailedError() {
        let error = AISDKErrorV2.authenticationFailed(provider: "openai")
        XCTAssertEqual(error.code, .authenticationFailed)
        XCTAssertEqual(error.context.provider, "openai")
        XCTAssertEqual(error.context.statusCode, 401)
    }

    func testRateLimitExceededError() {
        let error = AISDKErrorV2.rateLimitExceeded(provider: "anthropic", retryAfter: 30)
        XCTAssertEqual(error.code, .rateLimitExceeded)
        XCTAssertTrue(error.message.contains("30"))
        XCTAssertEqual(error.context.statusCode, 429)
    }

    func testProviderUnavailableError() {
        let error = AISDKErrorV2.providerUnavailable(provider: "openai")
        XCTAssertEqual(error.code, .providerUnavailable)
        XCTAssertEqual(error.context.statusCode, 503)
    }

    func testModelNotAvailableError() {
        let error = AISDKErrorV2.modelNotAvailable(model: "gpt-5", provider: "openai")
        XCTAssertEqual(error.code, .modelNotAvailable)
        XCTAssertTrue(error.message.contains("gpt-5"))
        XCTAssertTrue(error.message.contains("openai"))
    }

    func testContentFilteredError() {
        let error = AISDKErrorV2.contentFiltered(reason: "Violence detected")
        XCTAssertEqual(error.code, .contentFiltered)
        XCTAssertTrue(error.message.contains("Violence detected"))
    }

    func testContextLengthExceededError() {
        let error = AISDKErrorV2.contextLengthExceeded(tokenCount: 150000, maxTokens: 128000)
        XCTAssertEqual(error.code, .contextLengthExceeded)
        XCTAssertTrue(error.message.contains("150000"))
        XCTAssertTrue(error.message.contains("128000"))
    }

    func testStreamConnectionFailedError() {
        let error = AISDKErrorV2.streamConnectionFailed(reason: "Server refused")
        XCTAssertEqual(error.code, .streamConnectionFailed)
        XCTAssertTrue(error.message.contains("Server refused"))
    }

    func testStreamTimeoutError() {
        let error = AISDKErrorV2.streamTimeout(after: 60)
        XCTAssertEqual(error.code, .streamTimeout)
        XCTAssertTrue(error.message.contains("60"))
    }

    func testToolExecutionFailedError() {
        let error = AISDKErrorV2.toolExecutionFailed(tool: "calculator", reason: "Division by zero")
        XCTAssertEqual(error.code, .toolExecutionFailed)
        XCTAssertTrue(error.message.contains("calculator"))
        XCTAssertTrue(error.message.contains("Division by zero"))
    }

    func testToolNotFoundError() {
        let error = AISDKErrorV2.toolNotFound("nonexistent_tool")
        XCTAssertEqual(error.code, .toolNotFound)
        XCTAssertTrue(error.message.contains("nonexistent_tool"))
    }

    func testToolTimeoutError() {
        let error = AISDKErrorV2.toolTimeout(tool: "slow_tool", after: 30)
        XCTAssertEqual(error.code, .toolTimeout)
        XCTAssertTrue(error.message.contains("slow_tool"))
        XCTAssertTrue(error.message.contains("30"))
    }

    func testNetworkFailedError() {
        let underlying = URLError(.timedOut)
        let error = AISDKErrorV2.networkFailed("Connection lost", underlyingError: underlying)
        XCTAssertEqual(error.code, .networkFailed)
        XCTAssertNotNil(error.underlyingError)
    }

    func testTimeoutError() {
        let error = AISDKErrorV2.timeout(after: 120)
        XCTAssertEqual(error.code, .timeout)
        XCTAssertTrue(error.message.contains("120"))
    }

    func testCancelledError() {
        let error = AISDKErrorV2.cancelled()
        XCTAssertEqual(error.code, .cancelled)
    }

    // MARK: - PHI/Security Error Tests

    func testProviderNotAllowedError() {
        let error = AISDKErrorV2.providerNotAllowed(
            provider: "openai",
            allowedProviders: ["anthropic", "azure"],
            sensitivity: .phi
        )

        XCTAssertEqual(error.code, .providerNotAllowed)
        XCTAssertTrue(error.message.contains("openai"))
        XCTAssertTrue(error.message.contains("anthropic"))
        XCTAssertTrue(error.message.contains("azure"))
        XCTAssertTrue(error.message.contains("phi"))
        XCTAssertTrue(error.context.phiRedacted)  // Always redacted for PHI errors
    }

    func testPHIRequiresAllowlistError() {
        let context = AIErrorContext(
            requestId: "req-123",
            provider: "openai",
            metadata: ["sensitive": "data"]
        )
        let error = AISDKErrorV2.phiRequiresAllowlist(sensitivity: .phi, context: context)

        XCTAssertEqual(error.code, .phiRequiresAllowlist)
        XCTAssertTrue(error.context.phiRedacted)
        XCTAssertTrue(error.context.metadata.isEmpty)  // Metadata cleared on redaction
    }

    // MARK: - Error Conversion Tests

    func testConvertFromAISDKErrorV2() {
        let original = AISDKErrorV2.invalidRequest("Test")
        let converted = AISDKErrorV2.from(original)
        XCTAssertEqual(original, converted)
    }

    func testConvertFromAIProviderAccessError() {
        let accessError = AIProviderAccessError.providerNotAllowed(
            provider: "openai",
            allowedProviders: ["anthropic"]
        )
        let converted = AISDKErrorV2.from(accessError)
        XCTAssertEqual(converted.code, .providerNotAllowed)
    }

    func testConvertFromLLMError() {
        let llmError = LLMError.rateLimitExceeded
        let context = AIErrorContext(provider: "openai")
        let converted = AISDKErrorV2.from(llmError, context: context)
        XCTAssertEqual(converted.code, .rateLimitExceeded)
    }

    func testConvertFromAgentError() {
        let agentError = AgentError.operationCancelled
        let converted = AISDKErrorV2.from(agentError)
        XCTAssertEqual(converted.code, .cancelled)
    }

    func testConvertFromToolError() {
        let toolError = ToolError.executionFailed("Test failure")
        let converted = AISDKErrorV2.from(toolError)
        XCTAssertEqual(converted.code, .toolExecutionFailed)
    }

    func testConvertFromCancellationError() {
        let error = CancellationError()
        let converted = AISDKErrorV2.from(error)
        XCTAssertEqual(converted.code, .cancelled)
    }

    func testConvertFromURLError() {
        let urlError = URLError(.timedOut)
        let converted = AISDKErrorV2.from(urlError)
        XCTAssertEqual(converted.code, .timeout)

        let networkError = URLError(.notConnectedToInternet)
        let networkConverted = AISDKErrorV2.from(networkError)
        XCTAssertEqual(networkConverted.code, .networkFailed)
    }

    func testConvertFromUnknownError() {
        struct CustomError: Error {}
        let error = CustomError()
        let converted = AISDKErrorV2.from(error)
        XCTAssertEqual(converted.code, .unknown)
        XCTAssertTrue(converted.context.phiRedacted)  // Unknown errors are redacted
    }

    // MARK: - PHI Redaction Tests

    func testRedactedForLogging() {
        let context = AIErrorContext(
            requestId: "req-123",
            provider: "openai",
            metadata: ["patient_id": "12345"]
        )
        let error = AISDKErrorV2.providerNotAllowed(
            provider: "openai",
            allowedProviders: ["anthropic"],
            sensitivity: .phi,
            context: context
        )

        let redacted = error.redactedForLogging()

        XCTAssertTrue(redacted.context.phiRedacted)
        XCTAssertTrue(redacted.context.metadata.isEmpty)
        XCTAssertNil(redacted.underlyingError)
        // Security-related errors should have generic messages
        XCTAssertFalse(redacted.message.contains("openai"))
    }

    func testToLogDictionary() {
        let context = AIErrorContext(
            requestId: "req-123",
            provider: "anthropic",
            model: "claude-3",
            statusCode: 429
        )
        let error = AISDKErrorV2.rateLimitExceeded(provider: "anthropic", context: context)

        let dict = error.toLogDictionary()

        XCTAssertEqual(dict["code"] as? String, "rate_limit_exceeded")
        XCTAssertEqual(dict["requestId"] as? String, "req-123")
        XCTAssertEqual(dict["provider"] as? String, "anthropic")
        XCTAssertEqual(dict["model"] as? String, "claude-3")
        XCTAssertEqual(dict["statusCode"] as? Int, 429)
        XCTAssertEqual(dict["isRetryable"] as? Bool, true)
        XCTAssertEqual(dict["phiRedacted"] as? Bool, true)  // Always true for safety
    }

    // MARK: - LocalizedError Conformance Tests

    func testLocalizedErrorConformance() {
        let error = AISDKErrorV2.rateLimitExceeded(provider: "openai")

        XCTAssertEqual(error.errorDescription, error.message)
        XCTAssertEqual(error.failureReason, "rate_limit_exceeded")
        XCTAssertNotNil(error.recoverySuggestion)  // Retryable errors have suggestions
    }

    func testNonRetryableHasNoRecoverySuggestion() {
        let error = AISDKErrorV2.invalidRequest("Bad input")
        XCTAssertNil(error.recoverySuggestion)
    }

    // MARK: - Equatable Tests

    func testErrorEquatable() {
        let error1 = AISDKErrorV2.invalidRequest("Test")
        let error2 = AISDKErrorV2.invalidRequest("Test")
        let error3 = AISDKErrorV2.invalidRequest("Different")

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    func testErrorEquatableWithContext() {
        let context1 = AIErrorContext(provider: "openai")
        let context2 = AIErrorContext(provider: "anthropic")

        let error1 = AISDKErrorV2.invalidRequest("Test", context: context1)
        let error2 = AISDKErrorV2.invalidRequest("Test", context: context1)
        let error3 = AISDKErrorV2.invalidRequest("Test", context: context2)

        XCTAssertEqual(error1, error2)
        XCTAssertNotEqual(error1, error3)
    }

    // MARK: - Description Tests

    func testCustomStringConvertible() {
        let context = AIErrorContext(
            provider: "openai",
            model: "gpt-4",
            statusCode: 429,
            phiRedacted: true
        )
        let error = AISDKErrorV2.rateLimitExceeded(provider: "openai", context: context)

        let description = error.description

        XCTAssertTrue(description.contains("rate_limit_exceeded"))
        XCTAssertTrue(description.contains("openai"))
        XCTAssertTrue(description.contains("gpt-4"))
        XCTAssertTrue(description.contains("429"))
        XCTAssertTrue(description.contains("PHI redacted"))
    }
}
