//
//  AdaptiveCircuitBreakerTests.swift
//  AISDKTests
//
//  Comprehensive tests for AdaptiveCircuitBreaker
//

import XCTest
@testable import AISDK

// MARK: - Test Delegate

/// Test delegate for tracking circuit breaker state changes.
actor TestCircuitBreakerDelegate: CircuitBreakerDelegate {
    var stateTransitions: [(from: CircuitBreakerState, to: CircuitBreakerState)] = []
    var rejectedErrors: [CircuitBreakerError] = []

    func circuitBreaker(
        _ breaker: AdaptiveCircuitBreaker,
        didTransitionFrom oldState: CircuitBreakerState,
        to newState: CircuitBreakerState
    ) async {
        stateTransitions.append((from: oldState, to: newState))
    }

    func circuitBreaker(
        _ breaker: AdaptiveCircuitBreaker,
        didRejectRequest error: CircuitBreakerError
    ) async {
        rejectedErrors.append(error)
    }

    func reset() {
        stateTransitions.removeAll()
        rejectedErrors.removeAll()
    }
}

// MARK: - CircuitBreakerState Tests

final class CircuitBreakerStateTests: XCTestCase {

    func testState_closedAcceptsTraffic() {
        let state = CircuitBreakerState.closed
        XCTAssertTrue(state.acceptsTraffic)
    }

    func testState_openRejectsTraffic() {
        let state = CircuitBreakerState.open(until: ContinuousClock().now)
        XCTAssertFalse(state.acceptsTraffic)
    }

    func testState_halfOpenAcceptsTraffic() {
        let state = CircuitBreakerState.halfOpen
        XCTAssertTrue(state.acceptsTraffic)
    }

    func testState_descriptions() {
        XCTAssertEqual(CircuitBreakerState.closed.description, "closed")
        XCTAssertEqual(CircuitBreakerState.halfOpen.description, "halfOpen")

        let openState = CircuitBreakerState.open(until: ContinuousClock().now)
        XCTAssertTrue(openState.description.hasPrefix("open(until:"))
    }

    func testState_equality() {
        XCTAssertEqual(CircuitBreakerState.closed, CircuitBreakerState.closed)
        XCTAssertEqual(CircuitBreakerState.halfOpen, CircuitBreakerState.halfOpen)
        XCTAssertNotEqual(CircuitBreakerState.closed, CircuitBreakerState.halfOpen)
    }
}

// MARK: - CircuitBreakerConfiguration Tests

final class CircuitBreakerConfigurationTests: XCTestCase {

    func testConfiguration_defaultValues() {
        let config = CircuitBreakerConfiguration.default
        XCTAssertEqual(config.failureThreshold, 5)
        XCTAssertEqual(config.recoveryTimeout, .seconds(30))
        XCTAssertEqual(config.successThreshold, 2)
        XCTAssertEqual(config.halfOpenMaxProbes, 3)
        XCTAssertEqual(config.slidingWindowSize, 0)
        XCTAssertEqual(config.failureRateThreshold, 0.5)
        XCTAssertNil(config.identifier)
    }

    func testConfiguration_aggressivePreset() {
        let config = CircuitBreakerConfiguration.aggressive
        XCTAssertEqual(config.failureThreshold, 3)
        XCTAssertEqual(config.recoveryTimeout, .seconds(15))
        XCTAssertEqual(config.successThreshold, 1)
        XCTAssertEqual(config.halfOpenMaxProbes, 1)
    }

    func testConfiguration_lenientPreset() {
        let config = CircuitBreakerConfiguration.lenient
        XCTAssertEqual(config.failureThreshold, 10)
        XCTAssertEqual(config.recoveryTimeout, .seconds(60))
        XCTAssertEqual(config.successThreshold, 3)
        XCTAssertEqual(config.halfOpenMaxProbes, 5)
    }

    func testConfiguration_customValues() {
        let config = CircuitBreakerConfiguration(
            failureThreshold: 3,
            recoveryTimeout: .seconds(10),
            successThreshold: 1,
            halfOpenMaxProbes: 2,
            slidingWindowSize: 10,
            failureRateThreshold: 0.6,
            identifier: "test-breaker"
        )

        XCTAssertEqual(config.failureThreshold, 3)
        XCTAssertEqual(config.recoveryTimeout, .seconds(10))
        XCTAssertEqual(config.successThreshold, 1)
        XCTAssertEqual(config.halfOpenMaxProbes, 2)
        XCTAssertEqual(config.slidingWindowSize, 10)
        XCTAssertEqual(config.failureRateThreshold, 0.6)
        XCTAssertEqual(config.identifier, "test-breaker")
    }

    func testConfiguration_clampsNegativeValues() {
        let config = CircuitBreakerConfiguration(
            failureThreshold: -5,
            successThreshold: -1,
            halfOpenMaxProbes: 0,
            slidingWindowSize: -10,
            failureRateThreshold: 2.0
        )

        XCTAssertEqual(config.failureThreshold, 1, "Should clamp to minimum 1")
        XCTAssertEqual(config.successThreshold, 1, "Should clamp to minimum 1")
        XCTAssertEqual(config.halfOpenMaxProbes, 1, "Should clamp to minimum 1")
        XCTAssertEqual(config.slidingWindowSize, 0, "Should clamp to minimum 0")
        XCTAssertEqual(config.failureRateThreshold, 1.0, "Should clamp to maximum 1.0")
    }
}

// MARK: - CircuitBreakerError Tests

final class CircuitBreakerErrorTests: XCTestCase {

    func testError_circuitOpenHasDescription() {
        let error = CircuitBreakerError.circuitOpen(until: ContinuousClock().now)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("open"))
    }

    func testError_halfOpenLimitExceededHasDescription() {
        let error = CircuitBreakerError.halfOpenLimitExceeded
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("half-open"))
    }

    func testError_rejectedHasDescription() {
        let error = CircuitBreakerError.rejected(reason: "test reason")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("test reason"))
    }
}

// MARK: - AdaptiveCircuitBreaker Core Tests

final class AdaptiveCircuitBreakerTests: XCTestCase {

    // MARK: - Initialization

    func testInit_startsInClosedState() async {
        let breaker = AdaptiveCircuitBreaker()
        let state = await breaker.currentState

        XCTAssertEqual(state, .closed)
    }

    func testInit_isAvailableWhenClosed() async {
        let breaker = AdaptiveCircuitBreaker()
        let available = await breaker.isAvailable

        XCTAssertTrue(available)
    }

    func testInit_metricsAreZero() async {
        let breaker = AdaptiveCircuitBreaker()
        let metrics = await breaker.metrics

        XCTAssertEqual(metrics.totalSuccesses, 0)
        XCTAssertEqual(metrics.totalFailures, 0)
        XCTAssertEqual(metrics.consecutiveFailures, 0)
        XCTAssertEqual(metrics.openCount, 0)
        XCTAssertEqual(metrics.state, .closed)
    }

    // MARK: - Success Recording

    func testRecordSuccess_incrementsSuccessCount() async {
        let breaker = AdaptiveCircuitBreaker()

        await breaker.recordSuccess()
        await breaker.recordSuccess()
        await breaker.recordSuccess()

        let metrics = await breaker.metrics
        XCTAssertEqual(metrics.totalSuccesses, 3)
        XCTAssertEqual(metrics.totalFailures, 0)
    }

    func testRecordSuccess_resetsConsecutiveFailures() async {
        let breaker = AdaptiveCircuitBreaker(configuration: .init(failureThreshold: 10))

        await breaker.recordFailure()
        await breaker.recordFailure()
        await breaker.recordFailure()

        var metrics = await breaker.metrics
        XCTAssertEqual(metrics.consecutiveFailures, 3)

        await breaker.recordSuccess()

        metrics = await breaker.metrics
        XCTAssertEqual(metrics.consecutiveFailures, 0)
    }

    // MARK: - Failure Recording

    func testRecordFailure_incrementsFailureCount() async {
        let breaker = AdaptiveCircuitBreaker(configuration: .init(failureThreshold: 10))

        await breaker.recordFailure()
        await breaker.recordFailure()

        let metrics = await breaker.metrics
        XCTAssertEqual(metrics.totalFailures, 2)
        XCTAssertEqual(metrics.consecutiveFailures, 2)
    }

    func testRecordFailure_opensCircuitAtThreshold() async {
        let breaker = AdaptiveCircuitBreaker(configuration: .init(failureThreshold: 3))

        // Record failures up to threshold
        await breaker.recordFailure()
        await breaker.recordFailure()

        var state = await breaker.currentState
        XCTAssertEqual(state, .closed, "Should still be closed before threshold")

        await breaker.recordFailure() // This is the 3rd failure

        state = await breaker.currentState
        if case .open = state {
            // Expected
        } else {
            XCTFail("Expected open state, got \(state)")
        }
    }

    func testRecordFailure_incrementsOpenCount() async {
        let breaker = AdaptiveCircuitBreaker(configuration: .init(
            failureThreshold: 2,
            recoveryTimeout: .milliseconds(10)
        ))

        // First circuit open
        await breaker.recordFailure()
        await breaker.recordFailure()

        var metrics = await breaker.metrics
        XCTAssertEqual(metrics.openCount, 1)

        // Wait for recovery and trigger half-open
        try? await Task.sleep(for: .milliseconds(20))
        await breaker.reset()

        // Second circuit open
        await breaker.recordFailure()
        await breaker.recordFailure()

        metrics = await breaker.metrics
        XCTAssertEqual(metrics.openCount, 2)
    }

    // MARK: - State Transitions

    func testTransition_closedToOpen() async {
        let delegate = TestCircuitBreakerDelegate()
        let breaker = AdaptiveCircuitBreaker(
            configuration: .init(failureThreshold: 2),
            delegate: delegate
        )

        await breaker.recordFailure()
        await breaker.recordFailure()

        let transitions = await delegate.stateTransitions
        XCTAssertEqual(transitions.count, 1)
        XCTAssertEqual(transitions[0].from, .closed)
        if case .open = transitions[0].to {
            // Expected
        } else {
            XCTFail("Expected transition to open state")
        }
    }

    func testTransition_openToHalfOpen() async {
        let delegate = TestCircuitBreakerDelegate()
        let breaker = AdaptiveCircuitBreaker(
            configuration: .init(
                failureThreshold: 2,
                recoveryTimeout: .milliseconds(10)
            ),
            delegate: delegate
        )

        // Open the circuit
        await breaker.recordFailure()
        await breaker.recordFailure()

        // Wait for recovery timeout
        try? await Task.sleep(for: .milliseconds(20))

        // Check state triggers transition
        _ = await breaker.currentState

        let transitions = await delegate.stateTransitions
        XCTAssertGreaterThanOrEqual(transitions.count, 2)

        let lastTransition = transitions.last!
        XCTAssertEqual(lastTransition.to, .halfOpen)
    }

    func testTransition_halfOpenToClosed() async {
        let delegate = TestCircuitBreakerDelegate()
        let breaker = AdaptiveCircuitBreaker(
            configuration: .init(
                failureThreshold: 2,
                recoveryTimeout: .milliseconds(10),
                successThreshold: 2
            ),
            delegate: delegate
        )

        // Open the circuit
        await breaker.recordFailure()
        await breaker.recordFailure()

        // Wait for recovery timeout
        try? await Task.sleep(for: .milliseconds(20))

        // Trigger half-open
        _ = await breaker.currentState

        // Record successes to close
        await breaker.recordSuccess()
        await breaker.recordSuccess()

        let state = await breaker.currentState
        XCTAssertEqual(state, .closed)
    }

    func testTransition_halfOpenToOpen() async {
        let breaker = AdaptiveCircuitBreaker(
            configuration: .init(
                failureThreshold: 2,
                recoveryTimeout: .milliseconds(10)
            )
        )

        // Open the circuit
        await breaker.recordFailure()
        await breaker.recordFailure()

        // Wait for recovery timeout
        try? await Task.sleep(for: .milliseconds(20))

        // Trigger half-open
        _ = await breaker.currentState

        // Failure in half-open should re-open
        await breaker.recordFailure()

        let state = await breaker.currentState
        if case .open = state {
            // Expected
        } else {
            XCTFail("Expected open state after failure in half-open, got \(state)")
        }
    }

    // MARK: - Execute Tests

    func testExecute_succeedsWhenClosed() async throws {
        let breaker = AdaptiveCircuitBreaker()

        let result = try await breaker.execute {
            return 42
        }

        XCTAssertEqual(result, 42)
    }

    func testExecute_recordsSuccessOnCompletion() async throws {
        let breaker = AdaptiveCircuitBreaker()

        _ = try await breaker.execute {
            return "success"
        }

        let metrics = await breaker.metrics
        XCTAssertEqual(metrics.totalSuccesses, 1)
    }

    func testExecute_recordsFailureOnError() async {
        let breaker = AdaptiveCircuitBreaker(configuration: .init(failureThreshold: 10))

        do {
            _ = try await breaker.execute {
                throw NSError(domain: "test", code: 1)
            }
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }

        let metrics = await breaker.metrics
        XCTAssertEqual(metrics.totalFailures, 1)
    }

    func testExecute_throwsWhenCircuitOpen() async {
        let breaker = AdaptiveCircuitBreaker(configuration: .init(failureThreshold: 2))

        // Open the circuit
        await breaker.recordFailure()
        await breaker.recordFailure()

        do {
            _ = try await breaker.execute {
                return "should not execute"
            }
            XCTFail("Should have thrown CircuitBreakerError.circuitOpen")
        } catch let error as CircuitBreakerError {
            if case .circuitOpen = error {
                // Expected
            } else {
                XCTFail("Expected circuitOpen error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testExecute_limitsProbesInHalfOpen() async throws {
        let breaker = AdaptiveCircuitBreaker(
            configuration: .init(
                failureThreshold: 2,
                recoveryTimeout: .milliseconds(10),
                halfOpenMaxProbes: 2
            )
        )

        // Open the circuit
        await breaker.recordFailure()
        await breaker.recordFailure()

        // Wait for recovery timeout
        try await Task.sleep(for: .milliseconds(20))

        // First two probes should work
        _ = try await breaker.execute { return 1 }
        _ = try await breaker.execute { return 2 }

        // Third should be rejected (now in closed state after 2 successes)
        // Actually, with successThreshold default of 2, circuit closes after 2 successes
        // Let's reset and try again with higher threshold
        await breaker.reset()

        let breaker2 = AdaptiveCircuitBreaker(
            configuration: .init(
                failureThreshold: 2,
                recoveryTimeout: .milliseconds(10),
                successThreshold: 10, // Won't close quickly
                halfOpenMaxProbes: 2
            )
        )

        await breaker2.recordFailure()
        await breaker2.recordFailure()

        try await Task.sleep(for: .milliseconds(20))

        _ = try await breaker2.execute { return 1 }
        _ = try await breaker2.execute { return 2 }

        // Third should be rejected
        do {
            _ = try await breaker2.execute { return 3 }
            XCTFail("Should have thrown halfOpenLimitExceeded")
        } catch CircuitBreakerError.halfOpenLimitExceeded {
            // Expected
        }
    }

    // MARK: - Reset Tests

    func testReset_closesCircuit() async {
        let breaker = AdaptiveCircuitBreaker(configuration: .init(failureThreshold: 2))

        // Open the circuit
        await breaker.recordFailure()
        await breaker.recordFailure()

        var state = await breaker.currentState
        if case .open = state {} else { XCTFail("Should be open") }

        await breaker.reset()

        state = await breaker.currentState
        XCTAssertEqual(state, .closed)
    }

    func testReset_clearsCounters() async {
        let breaker = AdaptiveCircuitBreaker(configuration: .init(failureThreshold: 10))

        await breaker.recordFailure()
        await breaker.recordFailure()
        await breaker.recordFailure()

        await breaker.reset()

        let metrics = await breaker.metrics
        XCTAssertEqual(metrics.consecutiveFailures, 0)
    }

    // MARK: - Force Open Tests

    func testForceOpen_opensCircuit() async {
        let breaker = AdaptiveCircuitBreaker()

        await breaker.forceOpen(for: .seconds(10))

        let state = await breaker.currentState
        if case .open = state {
            // Expected
        } else {
            XCTFail("Expected open state, got \(state)")
        }
    }

    // MARK: - Sliding Window Tests

    func testSlidingWindow_calculatesFailureRate() async {
        let breaker = AdaptiveCircuitBreaker(
            configuration: .init(
                failureThreshold: 100, // High threshold to not trigger immediately
                slidingWindowSize: 10,
                failureRateThreshold: 0.5
            )
        )

        // Record some successes and failures
        await breaker.recordSuccess()
        await breaker.recordSuccess()
        await breaker.recordFailure()
        await breaker.recordFailure()

        let metrics = await breaker.metrics
        XCTAssertNotNil(metrics.slidingWindowFailureRate)
        XCTAssertEqual(metrics.slidingWindowFailureRate!, 0.5, accuracy: 0.01)
    }

    func testSlidingWindow_opensAtFailureRateThreshold() async {
        let breaker = AdaptiveCircuitBreaker(
            configuration: .init(
                failureThreshold: 100, // High consecutive threshold
                slidingWindowSize: 10,
                failureRateThreshold: 0.5
            )
        )

        // Fill the sliding window
        for _ in 0..<5 {
            await breaker.recordSuccess()
        }
        for _ in 0..<5 {
            await breaker.recordFailure()
        }

        // At this point, failure rate is 0.5 which equals threshold
        // Need one more failure to trigger
        await breaker.recordFailure()

        let state = await breaker.currentState
        if case .open = state {
            // Expected
        } else {
            XCTFail("Expected circuit to open at failure rate threshold, got \(state)")
        }
    }

    // MARK: - Delegate Tests

    func testDelegate_receivesStateTransitions() async {
        let delegate = TestCircuitBreakerDelegate()
        let breaker = AdaptiveCircuitBreaker(
            configuration: .init(failureThreshold: 2),
            delegate: delegate
        )

        await breaker.recordFailure()
        await breaker.recordFailure()

        let transitions = await delegate.stateTransitions
        XCTAssertEqual(transitions.count, 1)
    }

    func testDelegate_receivesRejections() async {
        let delegate = TestCircuitBreakerDelegate()
        let breaker = AdaptiveCircuitBreaker(
            configuration: .init(failureThreshold: 2),
            delegate: delegate
        )

        await breaker.recordFailure()
        await breaker.recordFailure()

        do {
            _ = try await breaker.execute { return 1 }
        } catch {}

        let rejections = await delegate.rejectedErrors
        XCTAssertEqual(rejections.count, 1)
    }

    // MARK: - Concurrency Tests

    func testConcurrency_handlesParallelRequests() async {
        let breaker = AdaptiveCircuitBreaker()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await breaker.recordSuccess()
                }
            }
        }

        let metrics = await breaker.metrics
        XCTAssertEqual(metrics.totalSuccesses, 100)
    }

    func testConcurrency_safeStateTransitions() async {
        let breaker = AdaptiveCircuitBreaker(configuration: .init(failureThreshold: 5))

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    if i % 2 == 0 {
                        await breaker.recordFailure()
                    } else {
                        await breaker.recordSuccess()
                    }
                }
            }
        }

        // Should not crash and metrics should be consistent
        let metrics = await breaker.metrics
        XCTAssertEqual(metrics.totalSuccesses + metrics.totalFailures, 50)
    }
}

// MARK: - CircuitBreakerRegistry Tests

final class CircuitBreakerRegistryTests: XCTestCase {

    func testRegistry_createsNewBreakerForProvider() async {
        let registry = CircuitBreakerRegistry()

        let breaker1 = await registry.breaker(for: "openai")
        let breaker2 = await registry.breaker(for: "openai")

        // Should return the same instance
        let state1 = await breaker1.currentState
        let state2 = await breaker2.currentState
        XCTAssertEqual(state1, state2)
    }

    func testRegistry_separateBreakersForDifferentProviders() async {
        let registry = CircuitBreakerRegistry()

        let openaiBreaker = await registry.breaker(for: "openai")
        let anthropicBreaker = await registry.breaker(for: "anthropic")

        // Modify one, other should be unaffected
        await openaiBreaker.recordFailure()

        let openaiMetrics = await openaiBreaker.metrics
        let anthropicMetrics = await anthropicBreaker.metrics

        XCTAssertEqual(openaiMetrics.totalFailures, 1)
        XCTAssertEqual(anthropicMetrics.totalFailures, 0)
    }

    func testRegistry_customConfiguration() async {
        let registry = CircuitBreakerRegistry()

        let breaker = await registry.breaker(
            for: "custom",
            configuration: .init(failureThreshold: 10)
        )

        // Access configuration through the actor
        let failureThreshold = await breaker.configuration.failureThreshold
        XCTAssertEqual(failureThreshold, 10)
    }

    func testRegistry_resetAll() async {
        let registry = CircuitBreakerRegistry(
            defaultConfiguration: .init(failureThreshold: 2)
        )

        let breaker1 = await registry.breaker(for: "provider1")
        let breaker2 = await registry.breaker(for: "provider2")

        // Open both
        await breaker1.recordFailure()
        await breaker1.recordFailure()
        await breaker2.recordFailure()
        await breaker2.recordFailure()

        // Reset all
        await registry.resetAll()

        let state1 = await breaker1.currentState
        let state2 = await breaker2.currentState

        XCTAssertEqual(state1, .closed)
        XCTAssertEqual(state2, .closed)
    }

    func testRegistry_allMetrics() async {
        let registry = CircuitBreakerRegistry()

        let breaker1 = await registry.breaker(for: "provider1")
        let breaker2 = await registry.breaker(for: "provider2")

        await breaker1.recordSuccess()
        await breaker2.recordFailure()

        let allMetrics = await registry.allMetrics()

        XCTAssertEqual(allMetrics.count, 2)
        XCTAssertEqual(allMetrics["provider1"]?.totalSuccesses, 1)
        XCTAssertEqual(allMetrics["provider2"]?.totalFailures, 1)
    }

    func testRegistry_removeBreaker() async {
        let registry = CircuitBreakerRegistry()

        let breaker1 = await registry.breaker(for: "provider1")
        await breaker1.recordSuccess()

        await registry.removeBreaker(for: "provider1")

        // New breaker should have fresh state
        let breaker2 = await registry.breaker(for: "provider1")
        let metrics = await breaker2.metrics

        XCTAssertEqual(metrics.totalSuccesses, 0)
    }
}
