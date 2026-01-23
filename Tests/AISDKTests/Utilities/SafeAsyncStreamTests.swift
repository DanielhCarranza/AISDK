//
//  SafeAsyncStreamTests.swift
//  AISDKTests
//
//  Tests for SafeAsyncStream memory-safe async stream utility
//

import XCTest
@testable import AISDK

final class SafeAsyncStreamTests: XCTestCase {

    // MARK: - Basic Functionality Tests

    func testMakeEmitsElementsAndCompletes() async throws {
        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            for i in 1...5 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        var collected: [Int] = []
        for try await element in stream {
            collected.append(element)
        }

        XCTAssertEqual(collected, [1, 2, 3, 4, 5])
    }

    func testMakeSyncEmitsElementsAndCompletes() async throws {
        let stream = SafeAsyncStream.makeSync(of: Int.self) { continuation in
            for i in 1...5 {
                continuation.yield(i)
            }
        }

        var collected: [Int] = []
        for try await element in stream {
            collected.append(element)
        }

        XCTAssertEqual(collected, [1, 2, 3, 4, 5])
    }

    func testFromSequence() async throws {
        let stream = SafeAsyncStream.from([1, 2, 3, 4, 5])

        var collected: [Int] = []
        for try await element in stream {
            collected.append(element)
        }

        XCTAssertEqual(collected, [1, 2, 3, 4, 5])
    }

    func testEmpty() async throws {
        let stream = SafeAsyncStream.empty(of: Int.self)

        var count = 0
        for try await _ in stream {
            count += 1
        }

        XCTAssertEqual(count, 0)
    }

    func testJust() async throws {
        let stream = SafeAsyncStream.just(42)

        var collected: [Int] = []
        for try await element in stream {
            collected.append(element)
        }

        XCTAssertEqual(collected, [42])
    }

    func testFail() async throws {
        struct TestError: Error {}
        let stream = SafeAsyncStream.fail(with: TestError(), of: Int.self)

        var didThrow = false
        do {
            for try await _ in stream {
                XCTFail("Should not receive any elements")
            }
        } catch {
            didThrow = true
            XCTAssertTrue(error is TestError)
        }

        XCTAssertTrue(didThrow)
    }

    // MARK: - Error Handling Tests

    func testBuildThrowingError() async throws {
        struct TestError: Error {}

        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            continuation.yield(1)
            continuation.yield(2)
            throw TestError()
        }

        var collected: [Int] = []
        var didThrow = false

        do {
            for try await element in stream {
                collected.append(element)
            }
        } catch {
            didThrow = true
            XCTAssertTrue(error is TestError)
        }

        XCTAssertEqual(collected, [1, 2])
        XCTAssertTrue(didThrow)
    }

    func testFinishWithError() async throws {
        struct TestError: Error {}

        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            continuation.yield(1)
            continuation.finish(throwing: TestError())
        }

        var collected: [Int] = []
        var didThrow = false

        do {
            for try await element in stream {
                collected.append(element)
            }
        } catch {
            didThrow = true
            XCTAssertTrue(error is TestError)
        }

        XCTAssertEqual(collected, [1])
        XCTAssertTrue(didThrow)
    }

    // MARK: - Idempotent Finish Tests

    func testDoubleFinishIsIdempotent() async throws {
        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            continuation.yield(1)
            continuation.finish()
            continuation.finish()  // Should be safe
            continuation.finish()  // Should be safe
        }

        var collected: [Int] = []
        for try await element in stream {
            collected.append(element)
        }

        XCTAssertEqual(collected, [1])
    }

    func testFinishAfterErrorIsIdempotent() async throws {
        struct TestError: Error {}

        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            continuation.finish(throwing: TestError())
            continuation.finish()  // Should be safe, no effect
        }

        var didThrow = false
        do {
            for try await _ in stream {
                XCTFail("Should not receive any elements")
            }
        } catch {
            didThrow = true
        }

        XCTAssertTrue(didThrow)
    }

    // MARK: - Termination State Tests

    func testIsTerminatedReflectsState() async throws {
        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            XCTAssertFalse(continuation.isTerminated)
            continuation.yield(1)
            XCTAssertFalse(continuation.isTerminated)
            continuation.finish()
            XCTAssertTrue(continuation.isTerminated)
        }

        var collected: [Int] = []
        for try await element in stream {
            collected.append(element)
        }

        XCTAssertEqual(collected, [1])
    }

    func testYieldAfterFinishReturnsTerminated() async throws {
        var wasTerminated = false

        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            continuation.yield(1)
            continuation.finish()

            let result = continuation.yield(2)
            if case .terminated = result {
                wasTerminated = true
            }
        }

        var collected: [Int] = []
        for try await element in stream {
            collected.append(element)
        }

        XCTAssertEqual(collected, [1])
        XCTAssertTrue(wasTerminated)
    }

    // MARK: - Buffer Policy Tests

    func testDefaultBufferPolicyIsBounded() async throws {
        // Should not crash with default policy
        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            for i in 1...100 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        var count = 0
        for try await _ in stream {
            count += 1
        }

        XCTAssertEqual(count, 100)
    }

    func testUnboundedBufferPolicy() async throws {
        let stream = SafeAsyncStream.make(of: Int.self, bufferingPolicy: .unbounded) { continuation in
            for i in 1...1000 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        var count = 0
        for try await _ in stream {
            count += 1
        }

        XCTAssertEqual(count, 1000)
    }

    func testInvalidCapacityFallsBackToDefault() async throws {
        // Using invalid capacity -1 should fall back to 1000
        let policy = StreamBufferPolicy.dropOldest(capacity: -1)

        let stream = SafeAsyncStream.make(of: Int.self, bufferingPolicy: policy) { continuation in
            continuation.yield(1)
            continuation.finish()
        }

        var collected: [Int] = []
        for try await element in stream {
            collected.append(element)
        }

        XCTAssertEqual(collected, [1])
    }

    func testZeroCapacityFallsBackToDefault() async throws {
        // Using invalid capacity 0 should fall back to 1000
        let policy = StreamBufferPolicy.dropNewest(capacity: 0)

        let stream = SafeAsyncStream.make(of: Int.self, bufferingPolicy: policy) { continuation in
            continuation.yield(1)
            continuation.finish()
        }

        var collected: [Int] = []
        for try await element in stream {
            collected.append(element)
        }

        XCTAssertEqual(collected, [1])
    }

    // MARK: - Cancellation Tests

    func testConsumerCancellationSetsTerminated() async throws {
        let producerStarted = expectation(description: "Producer started")
        let producerCheckedTermination = expectation(description: "Producer checked termination")

        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            producerStarted.fulfill()

            // Wait a bit for potential cancellation
            try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

            // Check if we've been terminated
            if continuation.isTerminated {
                producerCheckedTermination.fulfill()
            }
        }

        // Start consuming then cancel
        let task = Task {
            for try await _ in stream {
                break  // Stop after first element or immediately
            }
        }

        await fulfillment(of: [producerStarted], timeout: 1.0)

        task.cancel()

        await fulfillment(of: [producerCheckedTermination], timeout: 2.0)
    }

    func testProducerTaskIsCancelledOnConsumerCancellation() async throws {
        let taskCancelledOrTerminated = expectation(description: "Task was cancelled or terminated")
        let producerStarted = expectation(description: "Producer started")

        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            producerStarted.fulfill()
            continuation.yield(1)

            // Wait and check for cancellation via Task.isCancelled (set when consumer task is cancelled)
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
                if Task.isCancelled {
                    taskCancelledOrTerminated.fulfill()
                    return
                }
            }
        }

        let consumerTask = Task {
            for try await _ in stream {
                // Keep consuming - we'll cancel the task explicitly
                try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms
            }
        }

        // Wait for producer to start
        await fulfillment(of: [producerStarted], timeout: 1.0)

        // Give time for the first yield
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        // Cancel the consumer task - this should trigger onTermination which cancels producer
        consumerTask.cancel()

        // Now the stream is terminated because consumer cancelled
        await fulfillment(of: [taskCancelledOrTerminated], timeout: 3.0)
    }

    // MARK: - Yield Sequence Tests

    func testYieldContentsOfSequence() async throws {
        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            continuation.yield(contentsOf: [1, 2, 3])
            continuation.yield(contentsOf: [4, 5])
            continuation.finish()
        }

        var collected: [Int] = []
        for try await element in stream {
            collected.append(element)
        }

        XCTAssertEqual(collected, [1, 2, 3, 4, 5])
    }

    func testYieldContentsOfStopsWhenTerminated() async throws {
        let stream = SafeAsyncStream.make(of: Int.self) { continuation in
            continuation.yield(1)
            continuation.finish()
            // This should not yield any elements since we're terminated
            continuation.yield(contentsOf: [2, 3, 4, 5])
        }

        var collected: [Int] = []
        for try await element in stream {
            collected.append(element)
        }

        XCTAssertEqual(collected, [1])
    }
}
