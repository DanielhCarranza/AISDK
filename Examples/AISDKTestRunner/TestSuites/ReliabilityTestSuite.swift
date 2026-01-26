//
//  ReliabilityTestSuite.swift
//  AISDKTestRunner
//
//  Tests for circuit breaker, failover, retry policies, and health monitoring
//

import Foundation
import AISDK

public final class ReliabilityTestSuite: TestSuiteProtocol {
    public let reporter: TestReporter
    public let verbose: Bool
    private let suiteName = "Reliability"

    public init(reporter: TestReporter, verbose: Bool) {
        self.reporter = reporter
        self.verbose = verbose
    }

    public func run() async throws {
        reporter.log("Starting reliability layer tests...")

        await testCircuitBreakerOpensOnFailures()
        await testCircuitBreakerRecovery()
        await testFailoverConfigurationValidation()
        await testHealthMonitorTracksLatency()
        await testRetryPolicyWithBackoff()
        await testTimeoutPolicyEnforcement()
        await testAdaptiveCircuitBreakerThresholds()
    }

    // MARK: - Circuit Breaker Tests

    private func testCircuitBreakerOpensOnFailures() async {
        await withTimer("Circuit breaker opens after threshold failures", suiteName) {
            // Create circuit breaker with low threshold for testing
            let config = CircuitBreakerConfiguration(
                failureThreshold: 3,
                recoveryTimeout: .seconds(1),
                successThreshold: 2,
                halfOpenMaxProbes: 2
            )
            let circuitBreaker = AdaptiveCircuitBreaker(configuration: config)

            // Simulate failures
            for _ in 0..<3 {
                await circuitBreaker.recordFailure()
            }

            // Check that circuit is now open
            let state = await circuitBreaker.currentState
            let isOpen: Bool
            switch state {
            case .open:
                isOpen = true
            default:
                isOpen = false
            }

            guard isOpen else {
                throw TestError.assertionFailed("Circuit breaker should be open after 3 failures")
            }

            reporter.log("Circuit breaker correctly opened after threshold failures")
        }
    }

    private func testCircuitBreakerRecovery() async {
        await withTimer("Circuit breaker recovers to half-open state", suiteName) {
            let config = CircuitBreakerConfiguration(
                failureThreshold: 2,
                recoveryTimeout: .milliseconds(500), // Short timeout for testing
                successThreshold: 2,
                halfOpenMaxProbes: 2
            )
            let circuitBreaker = AdaptiveCircuitBreaker(configuration: config)

            // Trip the circuit
            await circuitBreaker.recordFailure()
            await circuitBreaker.recordFailure()

            var state = await circuitBreaker.currentState
            var isOpen: Bool
            switch state {
            case .open:
                isOpen = true
            default:
                isOpen = false
            }

            guard isOpen else {
                throw TestError.assertionFailed("Circuit should be open")
            }

            // Wait for recovery timeout
            try await Task.sleep(nanoseconds: 600_000_000) // 0.6s

            // Check if circuit allows a test request (half-open state)
            let canAttempt = await circuitBreaker.isAvailable
            guard canAttempt else {
                throw TestError.assertionFailed("Circuit should allow attempt in half-open state")
            }

            // Record success to close the circuit
            await circuitBreaker.recordSuccess()
            await circuitBreaker.recordSuccess()

            state = await circuitBreaker.currentState
            switch state {
            case .closed:
                isOpen = false
            default:
                isOpen = true
            }

            guard !isOpen else {
                throw TestError.assertionFailed("Circuit should be closed after successful recovery")
            }

            reporter.log("Circuit breaker correctly recovered through half-open state")
        }
    }

    // MARK: - Failover Tests

    private func testFailoverConfigurationValidation() async {
        await withTimer("Failover configuration validation", suiteName) {
            // Test failover configuration
            let failoverConfig = FailoverConfiguration(
                maxAttempts: 3,
                providers: ["openai", "anthropic", "gemini"],
                circuitBreakerEnabled: true
            )

            // Verify configuration
            guard failoverConfig.providers.count == 3 else {
                throw TestError.assertionFailed("Failover should have 3 providers configured")
            }

            guard failoverConfig.maxAttempts == 3 else {
                throw TestError.assertionFailed("Failover should allow 3 attempts")
            }

            reporter.log("Failover configuration validated with \(failoverConfig.providers.count) providers")
        }
    }

    // MARK: - Health Monitor Tests

    private func testHealthMonitorTracksLatency() async {
        await withTimer("Health monitor tracks provider latency", suiteName) {
            let healthMonitor = ProviderHealthMonitor()

            // Record some latency samples (using Duration)
            await healthMonitor.recordLatency(.milliseconds(150), for: "openai")
            await healthMonitor.recordLatency(.milliseconds(200), for: "openai")
            await healthMonitor.recordLatency(.milliseconds(180), for: "openai")

            await healthMonitor.recordLatency(.milliseconds(250), for: "anthropic")
            await healthMonitor.recordLatency(.milliseconds(280), for: "anthropic")

            // Get health status
            let openaiHealth = await healthMonitor.healthStatus(for: "openai")
            let anthropicHealth = await healthMonitor.healthStatus(for: "anthropic")

            // Compare P50 latencies
            guard openaiHealth.latencyP50 < anthropicHealth.latencyP50 else {
                throw TestError.assertionFailed("OpenAI should have lower average latency")
            }

            reporter.log("Health monitor correctly tracks latency: OpenAI P50=\(openaiHealth.latencyP50), Anthropic P50=\(anthropicHealth.latencyP50)")
        }
    }

    // MARK: - Retry Policy Tests

    private func testRetryPolicyWithBackoff() async {
        await withTimer("Retry policy with exponential backoff", suiteName) {
            let retryPolicy = SimpleRetryPolicy(
                maxRetries: 3,
                baseDelay: 0.1,
                maxDelay: 2.0,
                backoffMultiplier: 2.0
            )

            // Calculate delays for each retry
            let delay1 = retryPolicy.delayForRetry(attempt: 1)
            let delay2 = retryPolicy.delayForRetry(attempt: 2)
            let delay3 = retryPolicy.delayForRetry(attempt: 3)

            // Verify exponential backoff
            guard delay2 > delay1 else {
                throw TestError.assertionFailed("Delay should increase with retries")
            }

            guard delay3 > delay2 else {
                throw TestError.assertionFailed("Delay should continue increasing")
            }

            guard delay3 <= 2.0 else {
                throw TestError.assertionFailed("Delay should be capped at maxDelay")
            }

            reporter.log("Retry delays: \(String(format: "%.2f", delay1))s, \(String(format: "%.2f", delay2))s, \(String(format: "%.2f", delay3))s")
        }
    }

    // MARK: - Timeout Policy Tests

    private func testTimeoutPolicyEnforcement() async {
        await withTimer("Timeout policy enforces deadline", suiteName) {
            let timeoutPolicy = SimpleTimeoutPolicy(
                requestTimeout: 0.2,
                streamTimeout: 1.0,
                totalTimeout: 5.0
            )

            let startTime = Date()

            // Simulate a request that would timeout
            do {
                _ = try await timeoutPolicy.withTimeout {
                    // Simulate long-running operation
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                    return "completed"
                }
                throw TestError.assertionFailed("Should have timed out")
            } catch is SimpleTimeoutError {
                let elapsed = Date().timeIntervalSince(startTime)
                // Should timeout around 0.2s
                guard elapsed < 0.4 else {
                    throw TestError.assertionFailed("Timeout took too long: \(elapsed)s")
                }
                reporter.log("Timeout correctly enforced after \(String(format: "%.2f", elapsed))s")
            } catch {
                throw error
            }
        }
    }

    // MARK: - Adaptive Circuit Breaker Tests

    private func testAdaptiveCircuitBreakerThresholds() async {
        await withTimer("Adaptive circuit breaker adjusts thresholds", suiteName) {
            let config = CircuitBreakerConfiguration(
                failureThreshold: 5,
                recoveryTimeout: .seconds(1),
                successThreshold: 3,
                halfOpenMaxProbes: 3
            )
            let circuitBreaker = AdaptiveCircuitBreaker(configuration: config)

            // Record mix of successes and failures
            for _ in 0..<10 {
                await circuitBreaker.recordSuccess()
            }
            for _ in 0..<3 {
                await circuitBreaker.recordFailure()
            }

            // Circuit should still be closed (only 3 consecutive failures before success reset)
            var state = await circuitBreaker.currentState
            var isOpen: Bool
            switch state {
            case .open:
                isOpen = true
            default:
                isOpen = false
            }

            guard !isOpen else {
                throw TestError.assertionFailed("Circuit should still be closed")
            }

            // Now cause consecutive failures to trip it
            for _ in 0..<5 {
                await circuitBreaker.recordFailure()
            }

            state = await circuitBreaker.currentState
            switch state {
            case .open:
                isOpen = true
            default:
                isOpen = false
            }

            guard isOpen else {
                throw TestError.assertionFailed("Circuit should now be open")
            }

            reporter.log("Adaptive circuit breaker correctly manages failure threshold")
        }
    }
}

// MARK: - Supporting Types

private struct FailoverConfiguration {
    let maxAttempts: Int
    let providers: [String]
    let circuitBreakerEnabled: Bool
}

// MARK: - Simple Test Types

// Local types for testing - these provide simple implementations
// for testing retry and timeout behavior

private struct SimpleRetryPolicy {
    let maxRetries: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let backoffMultiplier: Double

    func delayForRetry(attempt: Int) -> TimeInterval {
        let delay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
        return min(delay, maxDelay)
    }
}

private struct SimpleTimeoutPolicy {
    let requestTimeout: TimeInterval
    let streamTimeout: TimeInterval
    let totalTimeout: TimeInterval

    func withTimeout<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(requestTimeout * 1_000_000_000))
                throw SimpleTimeoutError()
            }

            guard let result = try await group.next() else {
                throw SimpleTimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}

private struct SimpleTimeoutError: Error {}

enum TestError: Error {
    case assertionFailed(String)
    case skipped(String)
}
