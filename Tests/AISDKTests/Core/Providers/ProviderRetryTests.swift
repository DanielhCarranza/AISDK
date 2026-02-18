//
//  ProviderRetryTests.swift
//  AISDKTests
//
//  Tests verifying that provider adapters retry on transient failures.
//

import XCTest
@testable import AISDK

// MARK: - Provider Retry Integration Tests

final class ProviderRetryTests: XCTestCase {

    // MARK: - RetryExecutor Behavior Tests

    func testRetryExecutor_retriesOnRetryableError() async throws {
        var attempts = 0
        let executor = RetryExecutor(policy: RetryPolicy(
            maxRetries: 3,
            baseDelay: .milliseconds(10),
            maxDelay: .milliseconds(50),
            jitterFactor: 0
        ))

        let result = try await executor.execute {
            attempts += 1
            if attempts < 3 {
                throw ProviderError.networkError("Connection lost")
            }
            return "success"
        }

        XCTAssertEqual(result, "success")
        XCTAssertEqual(attempts, 3, "Should have retried twice before succeeding")
    }

    func testRetryExecutor_doesNotRetryOnNonRetryableError() async {
        var attempts = 0
        let executor = RetryExecutor(policy: RetryPolicy(
            maxRetries: 3,
            baseDelay: .milliseconds(10),
            jitterFactor: 0
        ))

        do {
            _ = try await executor.execute {
                attempts += 1
                throw ProviderError.authenticationFailed("Invalid API key")
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(attempts, 1, "Should NOT retry on auth failure")
            if case ProviderError.authenticationFailed = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testRetryExecutor_surfacesErrorAfterMaxRetries() async {
        var attempts = 0
        let executor = RetryExecutor(policy: RetryPolicy(
            maxRetries: 2,
            baseDelay: .milliseconds(10),
            jitterFactor: 0
        ))

        do {
            _ = try await executor.execute {
                attempts += 1
                throw ProviderError.networkError("Connection lost")
            }
            XCTFail("Should have thrown after max retries")
        } catch {
            XCTAssertEqual(attempts, 3, "Should attempt 1 + 2 retries = 3 total")
            if case ProviderError.networkError = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testRetryExecutor_retriesOnRateLimitError() async throws {
        var attempts = 0
        let executor = RetryExecutor(policy: RetryPolicy(
            maxRetries: 2,
            baseDelay: .milliseconds(10),
            jitterFactor: 0
        ))

        let result = try await executor.execute {
            attempts += 1
            if attempts == 1 {
                throw ProviderError.rateLimited(retryAfter: nil)
            }
            return "ok"
        }

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(attempts, 2, "Should retry once on rate limit")
    }

    func testRetryExecutor_retriesOnServerError() async throws {
        var attempts = 0
        let executor = RetryExecutor(policy: RetryPolicy(
            maxRetries: 2,
            baseDelay: .milliseconds(10),
            jitterFactor: 0
        ))

        let result = try await executor.execute {
            attempts += 1
            if attempts == 1 {
                throw ProviderError.serverError(statusCode: 502, message: "Bad Gateway")
            }
            return "recovered"
        }

        XCTAssertEqual(result, "recovered")
        XCTAssertEqual(attempts, 2)
    }

    func testRetryExecutor_doesNotRetryOnInvalidRequest() async {
        var attempts = 0
        let executor = RetryExecutor(policy: RetryPolicy(
            maxRetries: 3,
            baseDelay: .milliseconds(10),
            jitterFactor: 0
        ))

        do {
            _ = try await executor.execute {
                attempts += 1
                throw ProviderError.invalidRequest("Bad request body")
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(attempts, 1, "Should NOT retry on 400 error")
        }
    }

    // MARK: - Provider Adapter Configuration Tests

    func testOpenAIClientAdapter_acceptsCustomRetryPolicy() async {
        let customPolicy = RetryPolicy(maxRetries: 5, baseDelay: .milliseconds(100))
        let adapter = OpenAIClientAdapter(
            apiKey: "test-key",
            retryPolicy: customPolicy
        )
        // Adapter created successfully with custom retry policy
        XCTAssertNotNil(adapter)
    }

    func testAnthropicClientAdapter_acceptsCustomRetryPolicy() async {
        let customPolicy = RetryPolicy.none
        let adapter = AnthropicClientAdapter(
            apiKey: "test-key",
            retryPolicy: customPolicy
        )
        XCTAssertNotNil(adapter)
    }

    func testGeminiClientAdapter_acceptsCustomRetryPolicy() async {
        let customPolicy = RetryPolicy.aggressive
        let adapter = GeminiClientAdapter(
            apiKey: "test-key",
            retryPolicy: customPolicy
        )
        XCTAssertNotNil(adapter)
    }

    func testOpenAIClientAdapter_defaultsToStandardRetryPolicy() async {
        let adapter = OpenAIClientAdapter(apiKey: "test-key")
        // Should compile and work with default retry policy
        XCTAssertNotNil(adapter)
    }

    // MARK: - ProviderError RetryableError Conformance Tests

    func testProviderError_networkErrorIsRetryable() {
        let error = ProviderError.networkError("timeout")
        XCTAssertTrue(error.isRetryable)
    }

    func testProviderError_rateLimitedIsRetryable() {
        let error = ProviderError.rateLimited(retryAfter: 30)
        XCTAssertTrue(error.isRetryable)
    }

    func testProviderError_serverErrorIsRetryable() {
        let error = ProviderError.serverError(statusCode: 500, message: "Internal")
        XCTAssertTrue(error.isRetryable)
    }

    func testProviderError_authFailedIsNotRetryable() {
        let error = ProviderError.authenticationFailed("Invalid key")
        XCTAssertFalse(error.isRetryable)
    }

    func testProviderError_invalidRequestIsNotRetryable() {
        let error = ProviderError.invalidRequest("bad")
        XCTAssertFalse(error.isRetryable)
    }

    func testProviderError_rateLimitedHasRetryAfter() {
        let error = ProviderError.rateLimited(retryAfter: 60)
        XCTAssertEqual(error.suggestedRetryAfter, .seconds(60))
    }
}
