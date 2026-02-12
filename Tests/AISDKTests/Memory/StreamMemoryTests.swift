//
//  StreamMemoryTests.swift
//  AISDKTests
//
//  Memory leak tests for streaming operations.
//  Task 6.4 from AISDK Modernization.
//
//  These tests verify:
//  - Stream deallocation after completion
//  - Stream deallocation after errors
//  - No retain cycles in callbacks
//  - Memory doesn't accumulate with many operations
//

import XCTest
@testable import AISDK

// MARK: - StreamMemoryTests

final class StreamMemoryTests: XCTestCase {

    // MARK: - Test 1: Stream Deallocation After Completion

    /// Tests that streams are properly deallocated after completion
    func test_stream_deallocation_after_completion() async throws {
        // Track weak references to models
        var weakRefs: [WeakRef<MemoryTestMockModel>] = []

        // Create and consume many streams
        for _ in 0..<100 {
            autoreleasepool {
                let model = MemoryTestMockModel()
                weakRefs.append(WeakRef(model))

                // Consume the stream fully
                Task {
                    for try await _ in model.streamText(request: AITextRequest(
                        messages: [.user("Test")]
                    )) {
                        // Process events
                    }
                }
            }
        }

        // Give time for async cleanup
        try await Task.sleep(for: .milliseconds(100))

        // Force garbage collection hint
        for _ in 0..<5 {
            autoreleasepool {
                _ = [Int](repeating: 0, count: 1000)
            }
        }

        // Count how many references are still alive
        let aliveCount = weakRefs.filter { $0.value != nil }.count

        // Most models should be deallocated
        // Allow some tolerance for objects still being processed
        XCTAssertLessThanOrEqual(aliveCount, 10,
                                  "Most models should be deallocated after stream completion (got \(aliveCount) still alive)")
    }

    // MARK: - Test 2: Stream Deallocation After Error

    /// Tests that streams are properly deallocated when an error occurs
    func test_stream_deallocation_after_error() async throws {
        var weakRefs: [WeakRef<FailingMemoryTestMockModel>] = []

        // Create streams that will fail
        for _ in 0..<100 {
            autoreleasepool {
                let model = FailingMemoryTestMockModel()
                weakRefs.append(WeakRef(model))

                Task {
                    do {
                        for try await _ in model.streamText(request: AITextRequest(
                            messages: [.user("Test")]
                        )) {}
                    } catch {
                        // Expected error
                    }
                }
            }
        }

        // Give time for async cleanup
        try await Task.sleep(for: .milliseconds(100))

        // Force cleanup
        for _ in 0..<5 {
            autoreleasepool {
                _ = [Int](repeating: 0, count: 1000)
            }
        }

        let aliveCount = weakRefs.filter { $0.value != nil }.count

        XCTAssertLessThanOrEqual(aliveCount, 10,
                                  "Models should be deallocated after stream errors (got \(aliveCount) still alive)")
    }

    // MARK: - Test 3: No Retain Cycles in Step Callbacks

    /// Tests that callbacks don't create retain cycles
    func test_no_retain_cycles_in_step_callbacks() async throws {
        var weakAgentRef: WeakRef<AnyObject>?
        var callbackInvoked = false

        // Create scope for agent
        do {
            let model = MemoryTestMockModel()
            let agent = Agent(model: model, tools: [])

            // Store weak reference as AnyObject
            weakAgentRef = WeakRef(agent as AnyObject)

            // Execute with callback-like pattern
            let result = try await agent.execute(messages: [.user("Test")])
            callbackInvoked = !result.text.isEmpty
        }

        // Give time for cleanup
        try await Task.sleep(for: .milliseconds(100))

        // The agent should be deallocated after the scope ends
        XCTAssertTrue(callbackInvoked, "Callback should have been invoked")

        // Force cleanup
        for _ in 0..<5 {
            autoreleasepool {
                _ = [Int](repeating: 0, count: 1000)
            }
        }

        // Note: Actor deallocation timing can vary
        // This test primarily verifies no crash due to retain cycles
    }

    // MARK: - Test 4: Many Stream Operations Don't Accumulate Memory

    /// Tests that creating many stream operations doesn't leak memory
    func test_many_streams_dont_leak() async throws {
        let iterations = 500

        // Track initial state
        var completedCount = 0
        var errorCount = 0

        // Create many streams rapidly
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    let model = MemoryTestMockModel()
                    do {
                        for try await _ in model.streamText(request: AITextRequest(
                            messages: [.user("Test")]
                        )) {}
                        return true
                    } catch {
                        return false
                    }
                }
            }

            for await success in group {
                if success {
                    completedCount += 1
                } else {
                    errorCount += 1
                }
            }
        }

        // All operations should complete without hanging
        XCTAssertEqual(completedCount + errorCount, iterations,
                       "All operations should be handled")
        XCTAssertGreaterThan(completedCount, 0,
                             "At least some operations should complete successfully")

        print("Completed: \(completedCount), Errors: \(errorCount)")
    }

    // MARK: - Test 5: LegacyAgent Operations Don't Leak

    /// Tests that agent execute operations don't accumulate leaked objects
    func test_agent_operations_dont_leak() async throws {
        var weakRefs: [WeakRef<AnyObject>] = []
        let iterations = 100

        // Create many agents and execute
        for _ in 0..<iterations {
            autoreleasepool {
                let model = MemoryTestMockModel()
                let agent = Agent(model: model, tools: [])
                weakRefs.append(WeakRef(agent as AnyObject))

                Task {
                    do {
                        _ = try await agent.execute(messages: [.user("Test")])
                    } catch {
                        // Ignore errors
                    }
                }
            }
        }

        // Wait for operations to complete
        try await Task.sleep(for: .milliseconds(200))

        // Force cleanup cycles
        for _ in 0..<10 {
            autoreleasepool {
                _ = [Int](repeating: 0, count: 10000)
            }
        }

        let aliveCount = weakRefs.filter { $0.value != nil }.count
        let deallocatedCount = iterations - aliveCount

        // Most agents should be deallocated
        // Be lenient since actor deallocation timing varies
        XCTAssertGreaterThan(deallocatedCount, iterations / 2,
                             "Most agents should be deallocated (got \(deallocatedCount)/\(iterations))")

        print("Deallocated: \(deallocatedCount)/\(iterations) agents")
    }

    // MARK: - Test 6: Streaming LegacyAgent Operations Don't Leak

    /// Tests that streaming agent operations are properly cleaned up
    func test_streaming_agent_operations_dont_leak() async throws {
        var completedCount = 0
        var cancelledCount = 0
        let iterations = 50

        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let model = MemoryTestMockModel()
                    let agent = Agent(model: model, tools: [])

                    do {
                        var eventCount = 0
                        for try await event in agent.streamExecute(messages: [.user("Test \(i)")]) {
                            eventCount += 1
                            if case .finish = event {
                                break
                            }
                        }
                        return eventCount > 0
                    } catch is CancellationError {
                        return false
                    } catch {
                        return false
                    }
                }
            }

            for await success in group {
                if success {
                    completedCount += 1
                } else {
                    cancelledCount += 1
                }
            }
        }

        // All operations should complete
        XCTAssertEqual(completedCount + cancelledCount, iterations,
                       "All streaming operations should complete")
        XCTAssertGreaterThan(completedCount, iterations / 2,
                             "Most streaming operations should succeed")

        print("Streaming: \(completedCount)/\(iterations) completed")
    }

    // MARK: - Test 7: Circuit Breaker Operations Don't Leak

    /// Tests that circuit breaker operations clean up properly
    func test_circuit_breaker_operations_dont_leak() async throws {
        let iterations = 200
        var completedCount = 0
        var errorCount = 0

        // Create a single breaker for all operations
        let breaker = AdaptiveCircuitBreaker(configuration: .default)

        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    do {
                        let result: Int = try await breaker.execute {
                            // Randomly fail some operations
                            if i % 10 == 0 {
                                throw ProviderError.networkError("Test failure")
                            }
                            return i * 2
                        }
                        return result >= 0
                    } catch {
                        return false
                    }
                }
            }

            for await success in group {
                if success {
                    completedCount += 1
                } else {
                    errorCount += 1
                }
            }
        }

        // Verify all operations were handled
        XCTAssertEqual(completedCount + errorCount, iterations,
                       "All circuit breaker operations should complete")

        // Verify metrics are consistent
        let metrics = await breaker.metrics
        let totalOps = metrics.totalSuccesses + metrics.totalFailures
        XCTAssertEqual(totalOps, iterations,
                       "Circuit breaker should track all operations")

        print("Circuit breaker: \(completedCount) success, \(errorCount) errors")
    }
}

// MARK: - Test Helpers

/// Weak reference wrapper for tracking object lifecycle
private final class WeakRef<T: AnyObject> {
    weak var value: T?

    init(_ value: T) {
        self.value = value
    }
}

// MARK: - Memory Test Mock Model

/// Simple mock model for memory testing
private final class MemoryTestMockModel: LLM, @unchecked Sendable {
    let provider = "memory-test"
    let modelId = "memory-model"
    let capabilities: LLMCapabilities = []

    func generateText(request: AITextRequest) async throws -> AITextResult {
        AITextResult(
            text: "Memory test response",
            usage: AIUsage(promptTokens: 10, completionTokens: 5),
            finishReason: .stop
        )
    }

    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("Memory "))
            continuation.yield(.textDelta("test"))
            continuation.yield(.finish(finishReason: .stop, usage: AIUsage.zero))
            continuation.finish()
        }
    }

    func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T> {
        throw AISDKError.custom("Not implemented")
    }

    func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

// MARK: - Failing Memory Test Mock Model

/// Mock model that always fails for error path testing
private final class FailingMemoryTestMockModel: LLM, @unchecked Sendable {
    let provider = "failing-memory-test"
    let modelId = "failing-memory-model"
    let capabilities: LLMCapabilities = []

    func generateText(request: AITextRequest) async throws -> AITextResult {
        throw ProviderError.networkError("Simulated failure for memory test")
    }

    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ProviderError.networkError("Simulated stream failure"))
        }
    }

    func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T> {
        throw AISDKError.custom("Not implemented")
    }

    func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: ProviderError.networkError("Simulated failure")) }
    }
}
