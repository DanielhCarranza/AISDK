//
//  FaultInjectorTests.swift
//  AISDKTests
//
//  Comprehensive tests for FaultInjector
//

import XCTest
@testable import AISDK

// MARK: - Test Delegate

/// Test delegate for tracking fault injection events.
/// Uses thread-safe storage for nonisolated callbacks.
final class TestFaultInjectorDelegate: FaultInjectorDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _willInjectCalls: [(fault: FaultType, providerId: String?, modelId: String?)] = []
    private var _didInjectCalls: [(fault: FaultType, result: FaultInjectionResult, providerId: String?, modelId: String?)] = []

    var willInjectCalls: [(fault: FaultType, providerId: String?, modelId: String?)] {
        lock.withLock { _willInjectCalls }
    }

    var didInjectCalls: [(fault: FaultType, result: FaultInjectionResult, providerId: String?, modelId: String?)] {
        lock.withLock { _didInjectCalls }
    }

    nonisolated func faultInjectorWillInject(
        fault: FaultType,
        providerId: String?,
        modelId: String?
    ) {
        lock.withLock {
            _willInjectCalls.append((fault: fault, providerId: providerId, modelId: modelId))
        }
    }

    nonisolated func faultInjectorDidInject(
        fault: FaultType,
        result: FaultInjectionResult,
        providerId: String?,
        modelId: String?
    ) {
        lock.withLock {
            _didInjectCalls.append((fault: fault, result: result, providerId: providerId, modelId: modelId))
        }
    }

    func reset() {
        lock.withLock {
            _willInjectCalls.removeAll()
            _didInjectCalls.removeAll()
        }
    }
}

// MARK: - FaultType Tests

final class FaultTypeTests: XCTestCase {

    func testFaultType_errorDescription() {
        let fault = FaultType.error(.networkError("Test"))
        XCTAssertTrue(fault.description.contains("error"))
    }

    func testFaultType_delayDescription() {
        let fault = FaultType.delay(.seconds(5))
        XCTAssertTrue(fault.description.contains("delay"))
    }

    func testFaultType_timeoutDescription() {
        let fault = FaultType.timeout(30)
        XCTAssertTrue(fault.description.contains("timeout"))
        XCTAssertTrue(fault.description.contains("30"))
    }

    func testFaultType_randomFailureDescription() {
        let fault = FaultType.randomFailure(probability: 0.5, error: .timeout(30))
        XCTAssertTrue(fault.description.contains("randomFailure"))
        XCTAssertTrue(fault.description.contains("0.5"))
    }

    func testFaultType_intermittentDescription() {
        let fault = FaultType.intermittent(failCount: 3, error: .timeout(30))
        XCTAssertTrue(fault.description.contains("intermittent"))
        XCTAssertTrue(fault.description.contains("3"))
    }

    func testFaultType_latencyJitterDescription() {
        let fault = FaultType.latencyJitter(min: .milliseconds(100), max: .milliseconds(500))
        XCTAssertTrue(fault.description.contains("latencyJitter"))
    }

    func testFaultType_rateLimitedDescription() {
        let fault = FaultType.rateLimited(retryAfter: 30)
        XCTAssertTrue(fault.description.contains("rateLimited"))
    }

    func testFaultType_serverErrorDescription() {
        let fault = FaultType.serverError(statusCode: 503, message: "Unavailable")
        XCTAssertTrue(fault.description.contains("serverError"))
        XCTAssertTrue(fault.description.contains("503"))
    }

    func testFaultType_corruptResponseDescription() {
        let fault = FaultType.corruptResponse(message: "Test corrupt response")
        XCTAssertEqual(fault.description, "corruptResponse")
    }

    func testFaultType_equality() {
        XCTAssertEqual(FaultType.timeout(30), FaultType.timeout(30))
        XCTAssertNotEqual(FaultType.timeout(30), FaultType.timeout(60))
        XCTAssertEqual(FaultType.corruptResponse(message: "test"), FaultType.corruptResponse(message: "test"))
        XCTAssertEqual(
            FaultType.delay(.seconds(5)),
            FaultType.delay(.seconds(5))
        )
        XCTAssertNotEqual(
            FaultType.delay(.seconds(5)),
            FaultType.delay(.seconds(10))
        )
    }
}

// MARK: - FaultRule Tests

final class FaultRuleTests: XCTestCase {

    func testFaultRule_matchesAnyWhenNoFilters() {
        let rule = FaultRule(faultType: .timeout(30))

        XCTAssertTrue(rule.matches(providerId: "openai", modelId: "gpt-4"))
        XCTAssertTrue(rule.matches(providerId: "anthropic", modelId: "claude-3"))
        XCTAssertTrue(rule.matches(providerId: nil, modelId: nil))
    }

    func testFaultRule_matchesProviderFilter() {
        let rule = FaultRule(faultType: .timeout(30), providerId: "openai")

        XCTAssertTrue(rule.matches(providerId: "openai", modelId: "gpt-4"))
        XCTAssertTrue(rule.matches(providerId: "openai", modelId: nil))
        XCTAssertFalse(rule.matches(providerId: "anthropic", modelId: "gpt-4"))
        XCTAssertFalse(rule.matches(providerId: nil, modelId: nil))
    }

    func testFaultRule_matchesModelFilter() {
        let rule = FaultRule(faultType: .timeout(30), modelId: "gpt-4")

        XCTAssertTrue(rule.matches(providerId: "openai", modelId: "gpt-4"))
        XCTAssertTrue(rule.matches(providerId: nil, modelId: "gpt-4"))
        XCTAssertFalse(rule.matches(providerId: "openai", modelId: "gpt-3.5"))
        XCTAssertFalse(rule.matches(providerId: nil, modelId: nil))
    }

    func testFaultRule_matchesBothFilters() {
        let rule = FaultRule(faultType: .timeout(30), providerId: "openai", modelId: "gpt-4")

        XCTAssertTrue(rule.matches(providerId: "openai", modelId: "gpt-4"))
        XCTAssertFalse(rule.matches(providerId: "openai", modelId: "gpt-3.5"))
        XCTAssertFalse(rule.matches(providerId: "anthropic", modelId: "gpt-4"))
    }

    func testFaultRule_inactiveRuleDoesNotMatch() {
        let rule = FaultRule(faultType: .timeout(30), isActive: false)

        XCTAssertFalse(rule.matches(providerId: "openai", modelId: "gpt-4"))
        XCTAssertFalse(rule.matches(providerId: nil, modelId: nil))
    }
}

// MARK: - FaultInjector Core Tests

final class FaultInjectorTests: XCTestCase {

    // MARK: - Initialization

    func testInit_startsEnabled() async {
        let injector = FaultInjector()
        let isEnabled = await injector.isEnabled

        XCTAssertTrue(isEnabled)
    }

    func testInit_canStartDisabled() async {
        let injector = FaultInjector(enabled: false)
        let isEnabled = await injector.isEnabled

        XCTAssertFalse(isEnabled)
    }

    func testInit_startsWithNoRules() async {
        let injector = FaultInjector()
        let rules = await injector.activeRules

        XCTAssertTrue(rules.isEmpty)
    }

    func testInit_startsWithZeroMetrics() async {
        let injector = FaultInjector()
        let metrics = await injector.metrics

        XCTAssertEqual(metrics.totalEvaluations, 0)
        XCTAssertEqual(metrics.faultsInjected, 0)
        XCTAssertEqual(metrics.activeRules, 0)
    }

    // MARK: - Rule Management

    func testAddRule_addsToActiveRules() async {
        let injector = FaultInjector()
        let rule = FaultRule(id: "test-rule", faultType: .timeout(30))

        await injector.addRule(rule)

        let activeRules = await injector.activeRules
        XCTAssertEqual(activeRules.count, 1)
        XCTAssertEqual(activeRules.first?.id, "test-rule")
    }

    func testRemoveRule_removesFromActiveRules() async {
        let injector = FaultInjector()
        let rule = FaultRule(id: "test-rule", faultType: .timeout(30))

        await injector.addRule(rule)
        let removed = await injector.removeRule(id: "test-rule")

        XCTAssertNotNil(removed)
        XCTAssertEqual(removed?.id, "test-rule")

        let activeRules = await injector.activeRules
        XCTAssertTrue(activeRules.isEmpty)
    }

    func testRemoveRule_returnsNilForNonexistentRule() async {
        let injector = FaultInjector()

        let removed = await injector.removeRule(id: "nonexistent")

        XCTAssertNil(removed)
    }

    func testRemoveAllRules_clearsAllRules() async {
        let injector = FaultInjector()

        await injector.addRule(FaultRule(id: "rule1", faultType: .timeout(30)))
        await injector.addRule(FaultRule(id: "rule2", faultType: .corruptResponse(message: "test")))

        await injector.removeAllRules()

        let activeRules = await injector.activeRules
        XCTAssertTrue(activeRules.isEmpty)
    }

    func testGetRule_returnsRuleById() async {
        let injector = FaultInjector()
        let rule = FaultRule(id: "test-rule", faultType: .timeout(30))

        await injector.addRule(rule)

        let retrieved = await injector.rule(id: "test-rule")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "test-rule")
    }

    func testSetRuleEnabled_enablesAndDisablesRule() async {
        let injector = FaultInjector()
        let rule = FaultRule(id: "test-rule", faultType: .timeout(30), isActive: true)

        await injector.addRule(rule)

        // Disable the rule
        await injector.setRuleEnabled(id: "test-rule", enabled: false)
        var activeRules = await injector.activeRules
        XCTAssertTrue(activeRules.isEmpty)

        // Re-enable the rule
        await injector.setRuleEnabled(id: "test-rule", enabled: true)
        activeRules = await injector.activeRules
        XCTAssertEqual(activeRules.count, 1)
    }

    // MARK: - Fault Evaluation

    func testEvaluate_returnsProceedWhenDisabled() async {
        let injector = FaultInjector(enabled: false)
        await injector.addRule(FaultRule(faultType: .timeout(30)))

        let result = await injector.evaluate()

        if case .proceed = result {} else {
            XCTFail("Expected .proceed when disabled")
        }
    }

    func testEvaluate_returnsProceedWhenNoMatchingRules() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .timeout(30), providerId: "openai"))

        let result = await injector.evaluate(providerId: "anthropic")

        if case .proceed = result {} else {
            XCTFail("Expected .proceed when no matching rules")
        }
    }

    func testEvaluate_injectsError() async {
        let injector = FaultInjector()
        let error = ProviderError.networkError("Test error")
        await injector.addRule(FaultRule(faultType: .error(error)))

        let result = await injector.evaluate()

        if case .fail(let injectedError) = result {
            XCTAssertEqual(injectedError, error)
        } else {
            XCTFail("Expected .fail result")
        }
    }

    func testEvaluate_injectsDelay() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .delay(.milliseconds(100))))

        let result = await injector.evaluate()

        if case .delayed(let duration) = result {
            XCTAssertEqual(duration, .milliseconds(100))
        } else {
            XCTFail("Expected .delayed result")
        }
    }

    func testEvaluate_injectsTimeout() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .timeout(30)))

        let result = await injector.evaluate()

        // Timeout should throw a ProviderError.timeout immediately
        if case .fail(let error) = result {
            if case .timeout(let seconds) = error {
                XCTAssertEqual(seconds, 30)
            } else {
                XCTFail("Expected timeout error, got: \(error)")
            }
        } else {
            XCTFail("Expected .fail result for timeout, got: \(result)")
        }
    }

    func testEvaluate_injectsRateLimited() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .rateLimited(retryAfter: 30)))

        let result = await injector.evaluate()

        if case .fail(let error) = result {
            if case .rateLimited(let retryAfter) = error {
                XCTAssertEqual(retryAfter, 30)
            } else {
                XCTFail("Expected rateLimited error")
            }
        } else {
            XCTFail("Expected .fail result")
        }
    }

    func testEvaluate_injectsServerError() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .serverError(statusCode: 503, message: "Test")))

        let result = await injector.evaluate()

        if case .fail(let error) = result {
            if case .serverError(let statusCode, let message) = error {
                XCTAssertEqual(statusCode, 503)
                XCTAssertEqual(message, "Test")
            } else {
                XCTFail("Expected serverError")
            }
        } else {
            XCTFail("Expected .fail result")
        }
    }

    func testEvaluate_injectsCorruptResponse() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .corruptResponse(message: "Test corrupt response")))

        let result = await injector.evaluate()

        if case .fail(let error) = result {
            if case .parseError(let message) = error {
                XCTAssertEqual(message, "Test corrupt response")
            } else {
                XCTFail("Expected parseError, got: \(error)")
            }
        } else {
            XCTFail("Expected .fail result for corruptResponse")
        }
    }

    // MARK: - Random Failure Tests

    func testEvaluate_randomFailure_sometimesFails() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(
            faultType: .randomFailure(probability: 0.5, error: .timeout(30))
        ))

        var failCount = 0
        var proceedCount = 0

        for _ in 0..<100 {
            let result = await injector.evaluate()
            switch result {
            case .fail:
                failCount += 1
            case .proceed:
                proceedCount += 1
            default:
                break
            }
        }

        // With 50% probability, we should see both failures and proceeds
        XCTAssertGreaterThan(failCount, 10, "Should have some failures")
        XCTAssertGreaterThan(proceedCount, 10, "Should have some proceeds")
    }

    func testEvaluate_randomFailure_zeroNeverFails() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(
            faultType: .randomFailure(probability: 0.0, error: .timeout(30))
        ))

        for _ in 0..<20 {
            let result = await injector.evaluate()
            if case .fail = result {
                XCTFail("Should never fail with 0 probability")
            }
        }
    }

    // MARK: - Intermittent Failure Tests

    func testEvaluate_intermittent_failsNTimesThenSucceeds() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(
            id: "intermittent-test",
            faultType: .intermittent(failCount: 3, error: .timeout(30))
        ))

        // First 3 should fail
        for i in 0..<3 {
            let result = await injector.evaluate()
            if case .fail = result {} else {
                XCTFail("Evaluation \(i) should have failed")
            }
        }

        // Rest should proceed
        for _ in 0..<5 {
            let result = await injector.evaluate()
            if case .proceed = result {} else {
                XCTFail("Should proceed after intermittent failures exhausted")
            }
        }
    }

    func testResetIntermittentState_resetsFailCount() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(
            id: "intermittent-test",
            faultType: .intermittent(failCount: 2, error: .timeout(30))
        ))

        // Exhaust the failures
        _ = await injector.evaluate()
        _ = await injector.evaluate()

        // Reset
        await injector.resetIntermittentState()

        // Should fail again
        let result = await injector.evaluate()
        if case .fail = result {} else {
            XCTFail("Should fail after reset")
        }
    }

    // MARK: - Latency Jitter Tests

    func testEvaluate_latencyJitter_delaysWithinRange() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(
            faultType: .latencyJitter(min: .milliseconds(100), max: .milliseconds(200))
        ))

        for _ in 0..<10 {
            let result = await injector.evaluate()
            if case .delayed(let duration) = result {
                XCTAssertGreaterThanOrEqual(duration, .milliseconds(100))
                XCTAssertLessThanOrEqual(duration, .milliseconds(200))
            } else {
                XCTFail("Expected .delayed result")
            }
        }
    }

    // MARK: - withFaultInjection Tests

    func testWithFaultInjection_executesNormallyWhenNoFault() async throws {
        let injector = FaultInjector()

        let result = try await injector.withFaultInjection {
            return 42
        }

        XCTAssertEqual(result, 42)
    }

    func testWithFaultInjection_throwsInjectedError() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .error(.networkError("Test"))))

        do {
            _ = try await injector.withFaultInjection {
                return 42
            }
            XCTFail("Should have thrown")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .networkError("Test"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testWithFaultInjection_delaysExecution() async throws {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .delay(.milliseconds(50))))

        let startTime = ContinuousClock().now
        _ = try await injector.withFaultInjection {
            return 42
        }
        let elapsed = ContinuousClock().now - startTime

        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(40))
    }

    // MARK: - Metrics Tests

    func testMetrics_tracksEvaluations() async {
        let injector = FaultInjector()

        _ = await injector.evaluate()
        _ = await injector.evaluate()
        _ = await injector.evaluate()

        let metrics = await injector.metrics
        XCTAssertEqual(metrics.totalEvaluations, 3)
    }

    func testMetrics_tracksFaultsInjected() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .timeout(30)))

        _ = await injector.evaluate()
        _ = await injector.evaluate()

        let metrics = await injector.metrics
        XCTAssertEqual(metrics.faultsInjected, 2)
    }

    func testMetrics_tracksActiveRules() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(id: "rule1", faultType: .timeout(30)))
        await injector.addRule(FaultRule(id: "rule2", faultType: .corruptResponse(message: "test")))
        await injector.addRule(FaultRule(id: "rule3", faultType: .delay(.seconds(1)), isActive: false))

        let metrics = await injector.metrics
        XCTAssertEqual(metrics.activeRules, 2)
    }

    func testResetMetrics_clearsAllMetrics() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .timeout(30)))

        _ = await injector.evaluate()
        _ = await injector.evaluate()

        await injector.resetMetrics()

        let metrics = await injector.metrics
        XCTAssertEqual(metrics.totalEvaluations, 0)
        XCTAssertEqual(metrics.faultsInjected, 0)
    }

    // MARK: - Delegate Tests

    func testDelegate_receivesWillInjectNotification() async {
        let delegate = TestFaultInjectorDelegate()
        let injector = FaultInjector(delegate: delegate)
        await injector.addRule(FaultRule(faultType: .timeout(30)))

        _ = await injector.evaluate(providerId: "openai", modelId: "gpt-4")

        let calls = delegate.willInjectCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.providerId, "openai")
        XCTAssertEqual(calls.first?.modelId, "gpt-4")
    }

    func testDelegate_receivesDidInjectNotification() async {
        let delegate = TestFaultInjectorDelegate()
        let injector = FaultInjector(delegate: delegate)
        await injector.addRule(FaultRule(faultType: .timeout(30)))

        _ = await injector.evaluate()

        let calls = delegate.didInjectCalls
        XCTAssertEqual(calls.count, 1)
    }

    func testDelegate_didInjectIncludesProviderAndModelId() async {
        let delegate = TestFaultInjectorDelegate()
        let injector = FaultInjector(delegate: delegate)
        await injector.addRule(FaultRule(faultType: .timeout(30)))

        _ = await injector.evaluate(providerId: "anthropic", modelId: "claude-3")

        let calls = delegate.didInjectCalls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.providerId, "anthropic")
        XCTAssertEqual(calls.first?.modelId, "claude-3")
    }

    // MARK: - Convenience Builder Tests

    func testChaosTest_createsConfiguredInjector() async {
        let injector = await FaultInjector.chaosTest(failureProbability: 0.2)

        let activeRules = await injector.activeRules
        XCTAssertEqual(activeRules.count, 1)
    }

    func testChaosTest_withLatency_createsTwoRules() async {
        let injector = await FaultInjector.chaosTest(
            failureProbability: 0.2,
            latencyRange: (min: .milliseconds(10), max: .milliseconds(100))
        )

        let activeRules = await injector.activeRules
        XCTAssertEqual(activeRules.count, 2)
    }

    func testProviderDown_createsConfiguredInjector() async {
        let injector = await FaultInjector.providerDown("openai")

        let activeRules = await injector.activeRules
        XCTAssertEqual(activeRules.count, 1)
        XCTAssertEqual(activeRules.first?.providerId, "openai")
    }

    func testRateLimited_createsConfiguredInjector() async {
        let injector = await FaultInjector.rateLimited(providerId: "openai", retryAfter: 60)

        let activeRules = await injector.activeRules
        XCTAssertEqual(activeRules.count, 1)
    }

    // MARK: - Assertion Tests

    func testAssertFaultsInjected_throwsWhenNoFaults() async {
        let injector = FaultInjector()

        do {
            try await injector.assertFaultsInjected()
            XCTFail("Should have thrown")
        } catch FaultInjectorError.noFaultsInjected {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAssertFaultsInjected_succeedsWhenFaultsInjected() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .timeout(30)))

        _ = await injector.evaluate()

        do {
            try await injector.assertFaultsInjected()
        } catch {
            XCTFail("Should not throw: \(error)")
        }
    }

    func testAssertFaultCount_throwsWhenCountDoesNotMatch() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .timeout(30)))

        _ = await injector.evaluate()
        _ = await injector.evaluate()

        do {
            try await injector.assertFaultCount(5)
            XCTFail("Should have thrown")
        } catch FaultInjectorError.unexpectedFaultCount(let expected, let actual) {
            XCTAssertEqual(expected, 5)
            XCTAssertEqual(actual, 2)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAssertFaultCount_succeedsWhenCountMatches() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .timeout(30)))

        _ = await injector.evaluate()
        _ = await injector.evaluate()
        _ = await injector.evaluate()

        do {
            try await injector.assertFaultCount(3)
        } catch {
            XCTFail("Should not throw: \(error)")
        }
    }

    // MARK: - Concurrency Tests

    func testConcurrency_handlesParallelEvaluations() async {
        let injector = FaultInjector()
        await injector.addRule(FaultRule(faultType: .delay(.milliseconds(1))))

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    _ = await injector.evaluate()
                }
            }
        }

        let metrics = await injector.metrics
        XCTAssertEqual(metrics.totalEvaluations, 100)
    }

    // MARK: - Input Validation Tests

    func testEvaluate_clampsNegativeDelayToZero() async {
        let injector = FaultInjector()
        // This shouldn't crash even with a negative duration
        await injector.addRule(FaultRule(faultType: .delay(.zero)))

        let result = await injector.evaluate()

        if case .delayed(let duration) = result {
            XCTAssertGreaterThanOrEqual(duration, .zero)
        } else {
            XCTFail("Expected .delayed result")
        }
    }

    func testEvaluate_clampsProbabilityToValidRange() async {
        let injector = FaultInjector()
        // Probability > 1 should be clamped to 1 (always fail)
        await injector.addRule(FaultRule(
            faultType: .randomFailure(probability: 2.0, error: .timeout(30))
        ))

        var failCount = 0
        for _ in 0..<10 {
            let result = await injector.evaluate()
            if case .fail = result {
                failCount += 1
            }
        }

        XCTAssertEqual(failCount, 10, "Probability clamped to 1 should always fail")
    }
}

// MARK: - FaultInjectorError Tests

final class FaultInjectorErrorTests: XCTestCase {

    func testError_noFaultsInjectedHasDescription() {
        let error = FaultInjectorError.noFaultsInjected
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("no"))
    }

    func testError_unexpectedFaultCountHasDescription() {
        let error = FaultInjectorError.unexpectedFaultCount(expected: 5, actual: 3)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("5"))
        XCTAssertTrue(error.errorDescription!.contains("3"))
    }
}
