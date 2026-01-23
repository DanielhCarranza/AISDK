//
//  RetryPolicyTests.swift
//  AISDKTests
//
//  Comprehensive tests for RetryPolicy
//

import XCTest
@testable import AISDK

// MARK: - Test Helpers

/// Custom retryable error for testing.
struct TestRetryableError: RetryableError {
    let isRetryable: Bool
    let suggestedRetryAfter: Duration?

    init(isRetryable: Bool = true, suggestedRetryAfter: Duration? = nil) {
        self.isRetryable = isRetryable
        self.suggestedRetryAfter = suggestedRetryAfter
    }
}

/// Non-retryable test error.
struct TestNonRetryableError: Error {}

// MARK: - RetryPolicy Configuration Tests

final class RetryPolicyConfigurationTests: XCTestCase {

    func testDefault_hasExpectedValues() {
        let policy = RetryPolicy.default
        XCTAssertEqual(policy.maxRetries, 3)
        XCTAssertEqual(policy.baseDelay, .seconds(1))
        XCTAssertEqual(policy.maxDelay, .seconds(30))
        XCTAssertEqual(policy.jitterFactor, 0.2)
        XCTAssertEqual(policy.exponentialBase, 2.0)
        XCTAssertTrue(policy.respectRetryAfter)
    }

    func testNone_hasZeroRetries() {
        let policy = RetryPolicy.none
        XCTAssertEqual(policy.maxRetries, 0)
    }

    func testAggressive_hasMoreRetries() {
        let policy = RetryPolicy.aggressive
        XCTAssertEqual(policy.maxRetries, 5)
        XCTAssertEqual(policy.baseDelay, .milliseconds(500))
    }

    func testConservative_hasFewerRetries() {
        let policy = RetryPolicy.conservative
        XCTAssertEqual(policy.maxRetries, 2)
        XCTAssertEqual(policy.baseDelay, .seconds(2))
    }

    func testImmediate_hasMinimalDelay() {
        let policy = RetryPolicy.immediate
        XCTAssertEqual(policy.baseDelay, .milliseconds(10))
        XCTAssertEqual(policy.jitterFactor, 0.0)
    }

    func testCustom_acceptsParameters() {
        let policy = RetryPolicy(
            maxRetries: 5,
            baseDelay: .milliseconds(500),
            maxDelay: .seconds(60),
            jitterFactor: 0.5,
            exponentialBase: 3.0,
            respectRetryAfter: false
        )

        XCTAssertEqual(policy.maxRetries, 5)
        XCTAssertEqual(policy.baseDelay, .milliseconds(500))
        XCTAssertEqual(policy.maxDelay, .seconds(60))
        XCTAssertEqual(policy.jitterFactor, 0.5)
        XCTAssertEqual(policy.exponentialBase, 3.0)
        XCTAssertFalse(policy.respectRetryAfter)
    }

    func testClamps_negativeMaxRetries() {
        let policy = RetryPolicy(maxRetries: -5)
        XCTAssertEqual(policy.maxRetries, 0)
    }

    func testClamps_jitterFactor() {
        let policyHigh = RetryPolicy(jitterFactor: 2.0)
        XCTAssertEqual(policyHigh.jitterFactor, 1.0)

        let policyLow = RetryPolicy(jitterFactor: -0.5)
        XCTAssertEqual(policyLow.jitterFactor, 0.0)
    }

    func testClamps_exponentialBase() {
        let policy = RetryPolicy(exponentialBase: 0.5)
        XCTAssertEqual(policy.exponentialBase, 1.0)
    }
}

// MARK: - Delay Calculation Tests

final class RetryPolicyDelayTests: XCTestCase {

    func testDelay_exponentialGrowth() {
        let policy = RetryPolicy(
            baseDelay: .seconds(1),
            jitterFactor: 0.0,
            exponentialBase: 2.0
        )

        // Attempt 0: 1s * 2^0 = 1s
        let delay0 = policy.delay(forAttempt: 0)
        XCTAssertEqual(delay0, .seconds(1))

        // Attempt 1: 1s * 2^1 = 2s
        let delay1 = policy.delay(forAttempt: 1)
        XCTAssertEqual(delay1, .seconds(2))

        // Attempt 2: 1s * 2^2 = 4s
        let delay2 = policy.delay(forAttempt: 2)
        XCTAssertEqual(delay2, .seconds(4))

        // Attempt 3: 1s * 2^3 = 8s
        let delay3 = policy.delay(forAttempt: 3)
        XCTAssertEqual(delay3, .seconds(8))
    }

    func testDelay_respectsMaxDelay() {
        let policy = RetryPolicy(
            baseDelay: .seconds(1),
            maxDelay: .seconds(5),
            jitterFactor: 0.0,
            exponentialBase: 2.0
        )

        // Attempt 3 would be 8s, but capped at 5s
        let delay3 = policy.delay(forAttempt: 3)
        XCTAssertEqual(delay3, .seconds(5))

        // Attempt 10 would be huge, but still capped at 5s
        let delay10 = policy.delay(forAttempt: 10)
        XCTAssertEqual(delay10, .seconds(5))
    }

    func testDelay_withJitter() {
        let policy = RetryPolicy(
            baseDelay: .seconds(1),
            jitterFactor: 0.5,
            exponentialBase: 1.0 // No exponential growth
        )

        // With 50% jitter, delay should be between 1s and 1.5s
        var delays: [Duration] = []
        for _ in 0..<100 {
            delays.append(policy.delay(forAttempt: 0))
        }

        // Check that we get some variation (jitter is working)
        let uniqueDelays = Set(delays)
        XCTAssertGreaterThan(uniqueDelays.count, 1, "Jitter should produce varying delays")

        // All delays should be >= 1s and <= 1.5s
        for delay in delays {
            XCTAssertGreaterThanOrEqual(delay, .seconds(1))
            XCTAssertLessThanOrEqual(delay, .milliseconds(1500))
        }
    }

    func testDelay_noJitterWhenZero() {
        let policy = RetryPolicy(
            baseDelay: .seconds(1),
            jitterFactor: 0.0,
            exponentialBase: 1.0
        )

        // Without jitter, delay should always be exactly 1s
        for _ in 0..<10 {
            let delay = policy.delay(forAttempt: 0)
            XCTAssertEqual(delay, .seconds(1))
        }
    }

    func testDelay_negativeAttemptReturnsBaseDelay() {
        let policy = RetryPolicy(baseDelay: .seconds(1), jitterFactor: 0.0)
        let delay = policy.delay(forAttempt: -1)
        XCTAssertEqual(delay, .seconds(1))
    }

    func testDelay_respectsRetryAfterFromError() {
        let policy = RetryPolicy(respectRetryAfter: true)
        let error = TestRetryableError(suggestedRetryAfter: .seconds(60))

        let delay = policy.delay(for: error, attempt: 0)
        XCTAssertEqual(delay, .seconds(60))
    }

    func testDelay_respectsRetryAfterFromProviderError() {
        let policy = RetryPolicy(jitterFactor: 0.0, respectRetryAfter: true)
        let error = ProviderError.rateLimited(retryAfter: 120)

        let delay = policy.delay(for: error, attempt: 0)
        XCTAssertEqual(delay, Duration.seconds(120))
    }

    func testDelay_ignoresRetryAfterWhenDisabled() {
        let policy = RetryPolicy(
            baseDelay: .seconds(1),
            jitterFactor: 0.0,
            respectRetryAfter: false
        )
        let error = TestRetryableError(suggestedRetryAfter: .seconds(60))

        let delay = policy.delay(for: error, attempt: 0)
        XCTAssertEqual(delay, .seconds(1))
    }
}

// MARK: - Should Retry Tests

final class RetryPolicyShouldRetryTests: XCTestCase {

    func testShouldRetry_withinLimit() {
        let policy = RetryPolicy(maxRetries: 3)
        let error = TestRetryableError(isRetryable: true)

        XCTAssertTrue(policy.shouldRetry(error: error, attempt: 0))
        XCTAssertTrue(policy.shouldRetry(error: error, attempt: 1))
        XCTAssertTrue(policy.shouldRetry(error: error, attempt: 2))
    }

    func testShouldRetry_exceedsLimit() {
        let policy = RetryPolicy(maxRetries: 3)
        let error = TestRetryableError(isRetryable: true)

        XCTAssertFalse(policy.shouldRetry(error: error, attempt: 3))
        XCTAssertFalse(policy.shouldRetry(error: error, attempt: 4))
    }

    func testShouldRetry_nonRetryableError() {
        let policy = RetryPolicy(maxRetries: 10)
        let error = TestRetryableError(isRetryable: false)

        XCTAssertFalse(policy.shouldRetry(error: error, attempt: 0))
    }

    func testShouldRetry_zeroMaxRetries() {
        let policy = RetryPolicy.none
        let error = TestRetryableError(isRetryable: true)

        XCTAssertFalse(policy.shouldRetry(error: error, attempt: 0))
    }
}

// MARK: - Error Classification Tests

final class RetryPolicyErrorClassificationTests: XCTestCase {

    func testIsRetryable_providerErrorRateLimited() {
        let policy = RetryPolicy.default
        let error = ProviderError.rateLimited(retryAfter: 30)

        XCTAssertTrue(policy.isRetryable(error))
    }

    func testIsRetryable_providerErrorTimeout() {
        let policy = RetryPolicy.default
        let error = ProviderError.timeout(30)

        XCTAssertTrue(policy.isRetryable(error))
    }

    func testIsRetryable_providerErrorServerError5xx() {
        let policy = RetryPolicy.default

        XCTAssertTrue(policy.isRetryable(ProviderError.serverError(statusCode: 500, message: "Error")))
        XCTAssertTrue(policy.isRetryable(ProviderError.serverError(statusCode: 502, message: "Error")))
        XCTAssertTrue(policy.isRetryable(ProviderError.serverError(statusCode: 503, message: "Error")))
    }

    func testIsRetryable_providerErrorNetworkError() {
        let policy = RetryPolicy.default
        let error = ProviderError.networkError("Connection lost")

        XCTAssertTrue(policy.isRetryable(error))
    }

    func testIsRetryable_providerErrorAuthFailed() {
        let policy = RetryPolicy.default
        let error = ProviderError.authenticationFailed("Invalid key")

        XCTAssertFalse(policy.isRetryable(error))
    }

    func testIsRetryable_providerErrorInvalidRequest() {
        let policy = RetryPolicy.default
        let error = ProviderError.invalidRequest("Bad request")

        XCTAssertFalse(policy.isRetryable(error))
    }

    func testIsRetryable_providerErrorModelNotFound() {
        let policy = RetryPolicy.default
        let error = ProviderError.modelNotFound("unknown-model")

        XCTAssertFalse(policy.isRetryable(error))
    }

    func testIsRetryable_circuitBreakerErrorOpen() {
        let policy = RetryPolicy.default
        let error = CircuitBreakerError.circuitOpen(until: ContinuousClock().now)

        XCTAssertFalse(policy.isRetryable(error))
    }

    func testIsRetryable_circuitBreakerErrorHalfOpenLimit() {
        let policy = RetryPolicy.default
        let error = CircuitBreakerError.halfOpenLimitExceeded

        XCTAssertTrue(policy.isRetryable(error))
    }

    func testIsRetryable_customClassifier() {
        // Custom classifier that marks all errors as retryable
        let policy = RetryPolicy(
            errorClassifier: { _ in true }
        )

        XCTAssertTrue(policy.isRetryable(TestNonRetryableError()))
    }

    func testIsRetryable_retryableErrorProtocol() {
        let policy = RetryPolicy.default

        let retryable = TestRetryableError(isRetryable: true)
        XCTAssertTrue(policy.isRetryable(retryable))

        let nonRetryable = TestRetryableError(isRetryable: false)
        XCTAssertFalse(policy.isRetryable(nonRetryable))
    }
}

// MARK: - RetryExecutor Tests

final class RetryExecutorTests: XCTestCase {

    func testExecute_successOnFirstAttempt() async throws {
        let executor = RetryExecutor(policy: .default)
        var attempts = 0

        let result = try await executor.execute {
            attempts += 1
            return "success"
        }

        XCTAssertEqual(result, "success")
        XCTAssertEqual(attempts, 1)
    }

    func testExecute_retriesOnFailure() async throws {
        let executor = RetryExecutor(policy: .immediate)
        var attempts = 0

        let result = try await executor.execute {
            attempts += 1
            if attempts < 3 {
                throw ProviderError.networkError("Connection failed")
            }
            return "success"
        }

        XCTAssertEqual(result, "success")
        XCTAssertEqual(attempts, 3)
    }

    func testExecute_throwsAfterMaxRetries() async {
        let executor = RetryExecutor(policy: RetryPolicy(maxRetries: 2))
        var attempts = 0

        do {
            _ = try await executor.execute {
                attempts += 1
                throw ProviderError.networkError("Connection failed")
            }
            XCTFail("Should have thrown")
        } catch {
            // Expected - should have tried 3 times (initial + 2 retries)
            XCTAssertEqual(attempts, 3)
        }
    }

    func testExecute_doesNotRetryNonRetryableErrors() async {
        let executor = RetryExecutor(policy: .default)
        var attempts = 0

        do {
            _ = try await executor.execute {
                attempts += 1
                throw ProviderError.authenticationFailed("Invalid key")
            }
            XCTFail("Should have thrown")
        } catch {
            // Should not retry auth failures
            XCTAssertEqual(attempts, 1)
        }
    }

    func testExecute_callsOnRetryCallback() async throws {
        let executor = RetryExecutor(policy: .immediate)
        var retryCallbacks: [(Error, Int, Duration)] = []
        var attempts = 0

        _ = try await executor.execute {
            attempts += 1
            if attempts < 3 {
                throw ProviderError.networkError("Connection failed")
            }
            return "success"
        } onRetry: { error, attempt, delay in
            retryCallbacks.append((error, attempt, delay))
        }

        XCTAssertEqual(retryCallbacks.count, 2)
        XCTAssertEqual(retryCallbacks[0].1, 0) // First retry, attempt 0
        XCTAssertEqual(retryCallbacks[1].1, 1) // Second retry, attempt 1
    }

    func testExecute_withCircuitBreaker() async throws {
        let breaker = AdaptiveCircuitBreaker(
            configuration: .init(failureThreshold: 10)
        )
        let executor = RetryExecutor(policy: .immediate, circuitBreaker: breaker)

        let result = try await executor.execute {
            return "success"
        }

        XCTAssertEqual(result, "success")

        // Verify circuit breaker recorded the success
        let metrics = await breaker.metrics
        XCTAssertEqual(metrics.totalSuccesses, 1)
    }

    func testExecute_stopsWhenCircuitOpens() async {
        let breaker = AdaptiveCircuitBreaker(
            configuration: .init(failureThreshold: 2)
        )
        let executor = RetryExecutor(policy: .immediate, circuitBreaker: breaker)
        var attempts = 0

        do {
            _ = try await executor.execute {
                attempts += 1
                throw ProviderError.networkError("Connection failed")
            }
            XCTFail("Should have thrown")
        } catch {
            // Should stop after circuit opens (2 failures)
            // First attempt fails (failure 1)
            // First retry fails (failure 2) - circuit opens
            // No more retries because circuit is open
            XCTAssertLessThanOrEqual(attempts, 3)
        }
    }
}

// MARK: - ProviderError RetryableError Conformance Tests

final class ProviderErrorRetryableTests: XCTestCase {

    func testProviderError_rateLimitedIsRetryable() {
        let error = ProviderError.rateLimited(retryAfter: 30)
        XCTAssertTrue(error.isRetryable)
        XCTAssertEqual(error.suggestedRetryAfter, .seconds(30))
    }

    func testProviderError_rateLimitedWithoutRetryAfter() {
        let error = ProviderError.rateLimited(retryAfter: nil)
        XCTAssertTrue(error.isRetryable)
        XCTAssertNil(error.suggestedRetryAfter)
    }

    func testProviderError_timeoutIsRetryable() {
        let error = ProviderError.timeout(30)
        XCTAssertTrue(error.isRetryable)
    }

    func testProviderError_networkErrorIsRetryable() {
        let error = ProviderError.networkError("Connection lost")
        XCTAssertTrue(error.isRetryable)
    }

    func testProviderError_serverError5xxIsRetryable() {
        let error = ProviderError.serverError(statusCode: 503, message: "Service unavailable")
        XCTAssertTrue(error.isRetryable)
    }

    func testProviderError_serverError4xxNotRetryable() {
        let error = ProviderError.serverError(statusCode: 400, message: "Bad request")
        XCTAssertFalse(error.isRetryable)
    }

    func testProviderError_authFailedNotRetryable() {
        let error = ProviderError.authenticationFailed("Invalid API key")
        XCTAssertFalse(error.isRetryable)
    }
}

// MARK: - Equatable Tests

final class RetryPolicyEquatableTests: XCTestCase {

    func testEquatable_samePoliciesAreEqual() {
        let policy1 = RetryPolicy.default
        let policy2 = RetryPolicy.default

        XCTAssertEqual(policy1, policy2)
    }

    func testEquatable_differentPoliciesAreNotEqual() {
        let policy1 = RetryPolicy.default
        let policy2 = RetryPolicy.aggressive

        XCTAssertNotEqual(policy1, policy2)
    }

    func testEquatable_customPolicies() {
        let policy1 = RetryPolicy(maxRetries: 5, baseDelay: .seconds(2))
        let policy2 = RetryPolicy(maxRetries: 5, baseDelay: .seconds(2))
        let policy3 = RetryPolicy(maxRetries: 5, baseDelay: .seconds(3))

        XCTAssertEqual(policy1, policy2)
        XCTAssertNotEqual(policy1, policy3)
    }
}
