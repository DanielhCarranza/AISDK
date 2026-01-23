//
//  TimeoutPolicyTests.swift
//  AISDK
//
//  Tests for TimeoutPolicy and TimeoutExecutor.
//

import Foundation
import Testing
import XCTest
@testable import AISDK

// MARK: - TimeoutPolicy Configuration Tests

@Suite("TimeoutPolicy Configuration Tests")
struct TimeoutPolicyConfigurationTests {
    @Test("Default policy has expected values")
    func testDefaultValues() {
        let policy = TimeoutPolicy.default

        #expect(policy.connectionTimeout == .seconds(10))
        #expect(policy.requestTimeout == .seconds(60))
        #expect(policy.streamTimeout == .seconds(30))
        #expect(policy.operationTimeout == .seconds(120))
    }

    @Test("Custom policy accepts all values")
    func testCustomValues() {
        let policy = TimeoutPolicy(
            connectionTimeout: .seconds(5),
            requestTimeout: .seconds(30),
            streamTimeout: .seconds(15),
            operationTimeout: .seconds(60)
        )

        #expect(policy.connectionTimeout == .seconds(5))
        #expect(policy.requestTimeout == .seconds(30))
        #expect(policy.streamTimeout == .seconds(15))
        #expect(policy.operationTimeout == .seconds(60))
    }

    @Test("Aggressive preset has shorter timeouts")
    func testAggressivePreset() {
        let policy = TimeoutPolicy.aggressive

        #expect(policy.connectionTimeout == .seconds(5))
        #expect(policy.requestTimeout == .seconds(30))
        #expect(policy.streamTimeout == .seconds(10))
        #expect(policy.operationTimeout == .seconds(60))
    }

    @Test("Lenient preset has longer timeouts")
    func testLenientPreset() {
        let policy = TimeoutPolicy.lenient

        #expect(policy.connectionTimeout == .seconds(30))
        #expect(policy.requestTimeout == .seconds(300))
        #expect(policy.streamTimeout == .seconds(120))
        #expect(policy.operationTimeout == .seconds(600))
    }

    @Test("Streaming preset optimized for streams")
    func testStreamingPreset() {
        let policy = TimeoutPolicy.streaming

        #expect(policy.connectionTimeout == .seconds(10))
        #expect(policy.requestTimeout == .seconds(300))
        #expect(policy.streamTimeout == .seconds(60))
        #expect(policy.operationTimeout == .seconds(300))
    }
}

// MARK: - TimeoutPolicy Modifier Tests

@Suite("TimeoutPolicy Modifier Tests")
struct TimeoutPolicyModifierTests {
    @Test("withConnectionTimeout creates modified copy")
    func testWithConnectionTimeout() {
        let original = TimeoutPolicy.default
        let modified = original.withConnectionTimeout(.seconds(20))

        #expect(modified.connectionTimeout == .seconds(20))
        #expect(modified.requestTimeout == original.requestTimeout)
        #expect(modified.streamTimeout == original.streamTimeout)
        #expect(modified.operationTimeout == original.operationTimeout)
    }

    @Test("withRequestTimeout creates modified copy")
    func testWithRequestTimeout() {
        let original = TimeoutPolicy.default
        let modified = original.withRequestTimeout(.seconds(120))

        #expect(modified.connectionTimeout == original.connectionTimeout)
        #expect(modified.requestTimeout == .seconds(120))
        #expect(modified.streamTimeout == original.streamTimeout)
        #expect(modified.operationTimeout == original.operationTimeout)
    }

    @Test("withStreamTimeout creates modified copy")
    func testWithStreamTimeout() {
        let original = TimeoutPolicy.default
        let modified = original.withStreamTimeout(.seconds(45))

        #expect(modified.connectionTimeout == original.connectionTimeout)
        #expect(modified.requestTimeout == original.requestTimeout)
        #expect(modified.streamTimeout == .seconds(45))
        #expect(modified.operationTimeout == original.operationTimeout)
    }

    @Test("withOperationTimeout creates modified copy")
    func testWithOperationTimeout() {
        let original = TimeoutPolicy.default
        let modified = original.withOperationTimeout(.seconds(180))

        #expect(modified.connectionTimeout == original.connectionTimeout)
        #expect(modified.requestTimeout == original.requestTimeout)
        #expect(modified.streamTimeout == original.streamTimeout)
        #expect(modified.operationTimeout == .seconds(180))
    }

    @Test("Modifiers can be chained")
    func testChainedModifiers() {
        let policy = TimeoutPolicy.default
            .withConnectionTimeout(.seconds(5))
            .withRequestTimeout(.seconds(30))
            .withStreamTimeout(.seconds(15))
            .withOperationTimeout(.seconds(60))

        #expect(policy.connectionTimeout == .seconds(5))
        #expect(policy.requestTimeout == .seconds(30))
        #expect(policy.streamTimeout == .seconds(15))
        #expect(policy.operationTimeout == .seconds(60))
    }
}

// MARK: - TimeoutError Tests

@Suite("TimeoutError Tests")
struct TimeoutErrorTests {
    @Test("connectionTimedOut has correct description")
    func testConnectionTimedOutDescription() {
        let error = TimeoutError.connectionTimedOut
        #expect(error.errorDescription?.contains("Connection") == true)
        #expect(error.errorDescription?.contains("timed out") == true)
    }

    @Test("requestTimedOut has correct description")
    func testRequestTimedOutDescription() {
        let error = TimeoutError.requestTimedOut
        #expect(error.errorDescription?.contains("Request") == true)
        #expect(error.errorDescription?.contains("timed out") == true)
    }

    @Test("streamTimedOut has correct description")
    func testStreamTimedOutDescription() {
        let error = TimeoutError.streamTimedOut
        #expect(error.errorDescription?.contains("Stream") == true)
        #expect(error.errorDescription?.contains("timed out") == true)
    }

    @Test("operationTimedOut includes operation name")
    func testOperationTimedOutDescription() {
        let error = TimeoutError.operationTimedOut(operation: "fetchData")
        #expect(error.errorDescription?.contains("fetchData") == true)
        #expect(error.errorDescription?.contains("timed out") == true)
    }

    @Test("TimeoutError is Equatable")
    func testEquatable() {
        #expect(TimeoutError.connectionTimedOut == TimeoutError.connectionTimedOut)
        #expect(TimeoutError.requestTimedOut == TimeoutError.requestTimedOut)
        #expect(TimeoutError.streamTimedOut == TimeoutError.streamTimedOut)
        #expect(TimeoutError.operationTimedOut(operation: "a") == TimeoutError.operationTimedOut(operation: "a"))
        #expect(TimeoutError.operationTimedOut(operation: "a") != TimeoutError.operationTimedOut(operation: "b"))
        #expect(TimeoutError.connectionTimedOut != TimeoutError.requestTimedOut)
    }
}

// MARK: - TimeoutPolicy Equatable Tests

@Suite("TimeoutPolicy Equatable Tests")
struct TimeoutPolicyEquatableTests {
    @Test("Same policies are equal")
    func testSamePoliciesEqual() {
        let policy1 = TimeoutPolicy.default
        let policy2 = TimeoutPolicy.default

        #expect(policy1 == policy2)
    }

    @Test("Different policies are not equal")
    func testDifferentPoliciesNotEqual() {
        let policy1 = TimeoutPolicy.default
        let policy2 = TimeoutPolicy.aggressive

        #expect(policy1 != policy2)
    }

    @Test("Custom policies with same values are equal")
    func testCustomPoliciesEqual() {
        let policy1 = TimeoutPolicy(
            connectionTimeout: .seconds(5),
            requestTimeout: .seconds(30),
            streamTimeout: .seconds(15),
            operationTimeout: .seconds(60)
        )
        let policy2 = TimeoutPolicy(
            connectionTimeout: .seconds(5),
            requestTimeout: .seconds(30),
            streamTimeout: .seconds(15),
            operationTimeout: .seconds(60)
        )

        #expect(policy1 == policy2)
    }
}

// MARK: - Duration Extension Tests

@Suite("Duration Extension Tests")
struct DurationExtensionTests {
    @Test("seconds property returns whole seconds")
    func testSecondsProperty() {
        let duration = Duration.seconds(42)
        #expect(duration.seconds == 42)
    }

    @Test("timeInterval converts to Double")
    func testTimeIntervalProperty() {
        let duration = Duration.seconds(30)
        #expect(duration.timeInterval == 30.0)
    }

    @Test("timeInterval handles milliseconds")
    func testTimeIntervalWithMilliseconds() {
        let duration = Duration.milliseconds(1500)
        #expect(duration.timeInterval >= 1.4)
        #expect(duration.timeInterval <= 1.6)
    }
}

// MARK: - TimeoutExecutor XCTest Tests

/// XCTest-based tests for async timeout behavior
final class TimeoutExecutorTests: XCTestCase {
    func test_execute_completesBeforeTimeout() async throws {
        let executor = TimeoutExecutor(policy: TimeoutPolicy(requestTimeout: .seconds(5)))

        let result = try await executor.execute {
            try await Task.sleep(for: .milliseconds(50))
            return "success"
        }

        XCTAssertEqual(result, "success")
    }

    func test_execute_throwsOnTimeout() async {
        let executor = TimeoutExecutor(policy: TimeoutPolicy(requestTimeout: .milliseconds(50)))

        do {
            _ = try await executor.execute {
                try await Task.sleep(for: .seconds(5))
                return "should not reach"
            }
            XCTFail("Expected TimeoutError.requestTimedOut")
        } catch let error as TimeoutError {
            XCTAssertEqual(error, TimeoutError.requestTimedOut)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_execute_customTimeout_completesBeforeTimeout() async throws {
        let executor = TimeoutExecutor()

        let result = try await executor.execute(
            timeout: .seconds(5),
            operationName: "testOp"
        ) {
            try await Task.sleep(for: .milliseconds(50))
            return 42
        }

        XCTAssertEqual(result, 42)
    }

    func test_execute_customTimeout_throwsOnTimeout() async {
        let executor = TimeoutExecutor()

        do {
            _ = try await executor.execute(
                timeout: .milliseconds(50),
                operationName: "slowOp"
            ) {
                try await Task.sleep(for: .seconds(5))
                return "should not reach"
            }
            XCTFail("Expected TimeoutError.operationTimedOut")
        } catch let error as TimeoutError {
            if case .operationTimedOut(let operation) = error {
                XCTAssertEqual(operation, "slowOp")
            } else {
                XCTFail("Expected operationTimedOut, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_execute_propagatesOperationError() async {
        struct TestError: Error {}
        let executor = TimeoutExecutor(policy: TimeoutPolicy(requestTimeout: .seconds(5)))

        do {
            _ = try await executor.execute {
                throw TestError()
            }
            XCTFail("Expected TestError")
        } catch is TestError {
            // Expected
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_execute_cancelsTimeoutTaskOnSuccess() async throws {
        let executor = TimeoutExecutor(policy: TimeoutPolicy(requestTimeout: .seconds(60)))

        // The timeout task should be cancelled when the operation succeeds
        let result = try await executor.execute {
            return "quick result"
        }

        XCTAssertEqual(result, "quick result")
        // If the timeout task wasn't cancelled, this test would hang for 60 seconds
    }
}
