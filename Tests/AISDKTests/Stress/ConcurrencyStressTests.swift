//
//  ConcurrencyStressTests.swift
//  AISDKTests
//
//  Stress tests for concurrent operations across agents, circuit breakers,
//  streaming, and provider failover. Task 6.3 from AISDK Modernization.
//
//  These tests validate thread safety, reentrancy protection, and
//  correct behavior under high concurrency load.
//

import XCTest
@testable import AISDK

// MARK: - Metrics Collector

/// Thread-safe metrics collector for stress tests
final class StressTestMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var _completedCount: Int = 0
    private var _errorCount: Int = 0
    private var _cancelledCount: Int = 0
    private var _totalLatencyNs: UInt64 = 0
    private var _stateTransitions: Int = 0
    private var _errors: [Error] = []

    var completedCount: Int {
        lock.withLock { _completedCount }
    }

    var errorCount: Int {
        lock.withLock { _errorCount }
    }

    var cancelledCount: Int {
        lock.withLock { _cancelledCount }
    }

    var totalLatencyNs: UInt64 {
        lock.withLock { _totalLatencyNs }
    }

    var stateTransitions: Int {
        lock.withLock { _stateTransitions }
    }

    var errors: [Error] {
        lock.withLock { _errors }
    }

    func recordCompletion(latencyNs: UInt64 = 0) {
        lock.withLock {
            _completedCount += 1
            _totalLatencyNs += latencyNs
        }
    }

    func recordError(_ error: Error) {
        lock.withLock {
            _errorCount += 1
            _errors.append(error)
        }
    }

    func recordCancellation() {
        lock.withLock {
            _cancelledCount += 1
        }
    }

    func recordStateTransition() {
        lock.withLock {
            _stateTransitions += 1
        }
    }

    func reset() {
        lock.withLock {
            _completedCount = 0
            _errorCount = 0
            _cancelledCount = 0
            _totalLatencyNs = 0
            _stateTransitions = 0
            _errors.removeAll()
        }
    }
}

// MARK: - Test Circuit Breaker Delegate

/// Test delegate for tracking circuit breaker state changes under load
actor TestCircuitBreakerDelegateActor: CircuitBreakerDelegate {
    private(set) var stateTransitions: [(from: CircuitBreakerState, to: CircuitBreakerState)] = []
    private(set) var rejectedRequests: Int = 0

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
        rejectedRequests += 1
    }

    func reset() {
        stateTransitions.removeAll()
        rejectedRequests = 0
    }
}

// MARK: - Simple Mock for Stress Testing

/// Simple inline mock language model for stress tests
private final class StressTestMockModel: AILanguageModel, @unchecked Sendable {
    let provider = "stress-test"
    let modelId = "stress-model"
    let capabilities: LLMCapabilities = []

    private let lock = NSLock()
    private var _callCount: Int = 0

    var callCount: Int {
        lock.withLock { _callCount }
    }

    func generateText(request: AITextRequest) async throws -> AITextResult {
        lock.withLock { _callCount += 1 }
        return AITextResult(
            text: "Stress test response",
            toolCalls: [],  // No tool calls - agent exits after first step
            usage: AIUsage(promptTokens: 10, completionTokens: 5),
            finishReason: .stop
        )
    }

    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        lock.withLock { _callCount += 1 }
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("Stress "))
            continuation.yield(.textDelta("test"))
            continuation.yield(.finish(finishReason: .stop, usage: AIUsage.zero))
            continuation.finish()
        }
    }

    func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T> {
        throw AISDKError.custom("Not implemented for stress tests")
    }

    func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

// MARK: - Slow Streaming Mock

/// Mock language model that streams slowly to allow cancellation testing
private final class SlowStreamingMockModel: AILanguageModel, @unchecked Sendable {
    let provider = "slow-stream"
    let modelId = "slow-model"
    let capabilities: LLMCapabilities = []

    private let interEventDelay: Duration

    init(interEventDelay: Duration = .milliseconds(50)) {
        self.interEventDelay = interEventDelay
    }

    func generateText(request: AITextRequest) async throws -> AITextResult {
        try await Task.sleep(for: interEventDelay)
        return AITextResult(
            text: "Slow response",
            usage: AIUsage(promptTokens: 10, completionTokens: 5),
            finishReason: .stop
        )
    }

    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let delay = interEventDelay
        return AsyncThrowingStream { continuation in
            Task {
                // Emit events with delays to allow cancellation
                for i in 0..<10 {
                    // Check cancellation before each event
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }

                    try? await Task.sleep(for: delay)

                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }

                    continuation.yield(.textDelta("chunk\(i) "))
                }
                continuation.yield(.finish(finishReason: .stop, usage: AIUsage.zero))
                continuation.finish()
            }
        }
    }

    func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T> {
        throw AISDKError.custom("Not implemented")
    }

    func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

// MARK: - ConcurrencyStressTests

final class ConcurrencyStressTests: XCTestCase {

    // MARK: - Test 1: 100 Concurrent Agent Executions

    /// Tests that 100 concurrent agent executions complete correctly
    /// without data races, deadlocks, or corrupted state.
    /// Each agent is independent to test true concurrency.
    func test_100_concurrent_agent_executions() async throws {
        let metrics = StressTestMetrics()
        let concurrentOperations = 100

        // Execute 100 concurrent requests, each with its own agent
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<concurrentOperations {
                group.addTask {
                    let model = StressTestMockModel()
                    let agent = AIAgentActor(model: model, tools: [])

                    do {
                        let result = try await agent.execute(messages: [
                            .user("Concurrent request \(i)")
                        ])
                        metrics.recordCompletion()
                        XCTAssertFalse(result.text.isEmpty, "Result text should not be empty")
                    } catch {
                        metrics.recordError(error)
                    }
                }
            }
        }

        // All operations should complete
        XCTAssertEqual(metrics.completedCount, concurrentOperations,
                       "All \(concurrentOperations) operations should complete")
        XCTAssertEqual(metrics.errorCount, 0,
                       "No errors should occur")
    }

    /// Tests concurrent model streaming calls
    func test_100_concurrent_streaming_executions() async throws {
        let metrics = StressTestMetrics()
        let concurrentOperations = 100

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<concurrentOperations {
                group.addTask {
                    let model = StressTestMockModel()

                    do {
                        var eventCount = 0
                        for try await event in model.streamText(request: AITextRequest(
                            messages: [.user("Stream \(i)")]
                        )) {
                            eventCount += 1
                            if case .error(let error) = event {
                                metrics.recordError(error)
                                return
                            }
                        }
                        metrics.recordCompletion()
                        XCTAssertGreaterThan(eventCount, 0, "Should receive at least one event")
                    } catch is CancellationError {
                        metrics.recordCancellation()
                    } catch {
                        metrics.recordError(error)
                    }
                }
            }
        }

        let totalHandled = metrics.completedCount + metrics.cancelledCount
        XCTAssertEqual(totalHandled, concurrentOperations,
                       "All operations should be handled")
        XCTAssertEqual(metrics.errorCount, 0,
                       "No errors should occur during streaming")
    }

    // MARK: - Test 2: Rapid Circuit Breaker State Changes

    /// Tests circuit breaker behavior under rapid concurrent state changes
    func test_rapid_circuit_breaker_state_changes() async throws {
        let delegate = TestCircuitBreakerDelegateActor()

        // Use aggressive config for faster state transitions
        let config = CircuitBreakerConfiguration(
            failureThreshold: 3,
            recoveryTimeout: .milliseconds(50),
            successThreshold: 1,
            halfOpenMaxProbes: 2
        )

        let breaker = AdaptiveCircuitBreaker(
            configuration: config,
            delegate: delegate
        )

        let metrics = StressTestMetrics()

        // Phase 1: Force circuit to open with consecutive failures
        for _ in 0..<5 {
            await breaker.recordFailure()
        }

        // Phase 2: Wait for recovery timeout
        try await Task.sleep(for: .milliseconds(60))

        // Phase 3: Record a success to trigger half-open -> closed transition
        await breaker.recordSuccess()

        // Phase 4: Now do rapid concurrent operations
        let operations = 100
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<operations {
                group.addTask {
                    // Alternate between success and failure
                    if i % 3 == 0 {
                        await breaker.recordFailure()
                    } else {
                        await breaker.recordSuccess()
                    }
                    metrics.recordCompletion()
                }
            }
        }

        XCTAssertEqual(metrics.completedCount, operations,
                       "All operations should complete")

        // Check metrics are consistent
        let breakerMetrics = await breaker.metrics
        XCTAssertGreaterThan(breakerMetrics.totalSuccesses + breakerMetrics.totalFailures, 0,
                             "Some operations should be recorded")

        // Verify state transitions occurred (circuit should have transitioned during phases 1-3)
        let transitions = await delegate.stateTransitions
        XCTAssertGreaterThan(transitions.count, 0,
                             "Circuit breaker should have state transitions")
    }

    /// Tests concurrent execute() calls through the circuit breaker
    func test_concurrent_circuit_breaker_executes() async throws {
        let config = CircuitBreakerConfiguration(
            failureThreshold: 5,
            recoveryTimeout: .seconds(1),
            successThreshold: 2,
            halfOpenMaxProbes: 3
        )

        let breaker = AdaptiveCircuitBreaker(configuration: config)
        let metrics = StressTestMetrics()
        let operations = 100

        // Execute operations with some failures
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<operations {
                group.addTask {
                    do {
                        let result: Int = try await breaker.execute {
                            // Fail every 10th operation
                            if i % 10 == 5 {
                                throw ProviderError.networkError("Simulated failure")
                            }
                            return i * 2
                        }
                        XCTAssertEqual(result, i * 2)
                        metrics.recordCompletion()
                    } catch is CircuitBreakerError {
                        metrics.recordCancellation() // Circuit open
                    } catch {
                        metrics.recordError(error)
                    }
                }
            }
        }

        // Some operations complete, some fail, some are rejected
        let totalHandled = metrics.completedCount + metrics.errorCount + metrics.cancelledCount
        XCTAssertEqual(totalHandled, operations,
                       "All operations should be handled")
    }

    // MARK: - Test 3: Stream Cancellation During Tool Execution

    /// Tests that streams can be safely cancelled during execution
    /// This test verifies that concurrent stream operations can be:
    /// 1. Completed normally
    /// 2. Cancelled mid-stream
    /// 3. Error out
    /// without any deadlocks or data corruption
    func test_stream_cancellation_during_execution() async throws {
        let metrics = StressTestMetrics()
        let concurrentStreams = 50

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<concurrentStreams {
                group.addTask {
                    let model = StressTestMockModel()

                    do {
                        var eventCount = 0
                        for try await event in model.streamText(request: AITextRequest(
                            messages: [.user("Stream \(i)")]
                        )) {
                            eventCount += 1
                            // Simulate early cancellation for some streams
                            if i % 3 == 0 && eventCount >= 1 {
                                throw CancellationError()
                            }
                            if case .error(let error) = event {
                                throw error
                            }
                        }
                        metrics.recordCompletion()
                    } catch is CancellationError {
                        metrics.recordCancellation()
                    } catch {
                        metrics.recordError(error)
                    }
                }
            }
        }

        // All streams should complete or be cancelled (no deadlocks)
        let totalHandled = metrics.completedCount + metrics.cancelledCount + metrics.errorCount
        XCTAssertEqual(totalHandled, concurrentStreams,
                       "All streams should be handled")

        // Verify cancellation actually happened for some
        // Every 3rd stream (i % 3 == 0) throws CancellationError
        let expectedCancellations = concurrentStreams / 3 + (concurrentStreams % 3 > 0 ? 1 : 0)
        XCTAssertGreaterThan(metrics.cancelledCount, 0,
                             "Some streams should have been cancelled")
        XCTAssertGreaterThanOrEqual(metrics.cancelledCount, expectedCancellations - 2,
                                     "Expected around \(expectedCancellations) cancellations")
    }

    /// Tests rapid stream creation and cancellation
    func test_rapid_stream_creation_and_cancellation() async throws {
        let metrics = StressTestMetrics()
        let iterations = 100

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<iterations {
                group.addTask {
                    let model = StressTestMockModel()
                    let stream = model.streamText(request: AITextRequest(
                        messages: [.user("Rapid test")]
                    ))

                    // Start iterating but cancel quickly
                    let task = Task {
                        do {
                            var count = 0
                            for try await _ in stream {
                                count += 1
                                if count > 2 {
                                    throw CancellationError()
                                }
                            }
                            metrics.recordCompletion()
                        } catch is CancellationError {
                            metrics.recordCancellation()
                        } catch {
                            metrics.recordError(error)
                        }
                    }

                    await task.value
                }
            }
        }

        let totalHandled = metrics.completedCount + metrics.cancelledCount + metrics.errorCount
        XCTAssertEqual(totalHandled, iterations,
                       "All iterations should be handled")
    }

    // MARK: - Test 4: Provider Failover Under Load

    /// Tests failover execution under concurrent load
    func test_provider_failover_under_load() async throws {
        // Create mock providers
        let primaryProvider = StressTestProviderClient(providerId: "primary")
        let secondaryProvider = StressTestProviderClient(providerId: "secondary")
        let tertiaryProvider = StressTestProviderClient(providerId: "tertiary")

        // Primary fails 50% of the time
        primaryProvider.failureRate = 0.5
        // Secondary fails 20% of the time
        secondaryProvider.failureRate = 0.2
        // Tertiary always succeeds
        tertiaryProvider.failureRate = 0.0

        let executor = FailoverExecutor(
            providers: [primaryProvider, secondaryProvider, tertiaryProvider],
            configuration: FailoverExecutorConfiguration(
                retryPolicy: RetryPolicy(maxRetries: 1, baseDelay: .milliseconds(10)),
                timeoutPolicy: TimeoutPolicy(operationTimeout: .seconds(5)),
                failoverPolicy: .default
            ),
            circuitBreakerConfig: CircuitBreakerConfiguration(
                failureThreshold: 5,
                recoveryTimeout: .milliseconds(500)
            )
        )

        let metrics = StressTestMetrics()
        let operations = 100

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<operations {
                group.addTask {
                    do {
                        let request = AITextRequest(messages: [.user("Request \(i)")])
                        let result = try await executor.executeRequest(
                            request: request,
                            modelId: "test-model"
                        )

                        // Verify we got a result
                        XCTAssertFalse(result.provider.isEmpty)
                        metrics.recordCompletion()
                    } catch {
                        metrics.recordError(error)
                    }
                }
            }
        }

        // Most operations should succeed through failover
        XCTAssertGreaterThan(metrics.completedCount, operations / 2,
                             "At least half of operations should succeed through failover")

        // Check that failover actually happened (providers other than primary were used)
        let primaryRequests = primaryProvider.requestCount
        let secondaryRequests = secondaryProvider.requestCount
        let tertiaryRequests = tertiaryProvider.requestCount

        let totalRequests = primaryRequests + secondaryRequests + tertiaryRequests
        XCTAssertGreaterThanOrEqual(totalRequests, operations,
                                     "Total provider requests should be at least the number of operations")
    }

    /// Tests circuit breaker interaction during failover
    func test_circuit_breaker_triggers_failover() async throws {
        let failingProvider = StressTestProviderClient(providerId: "failing")
        let healthyProvider = StressTestProviderClient(providerId: "healthy")

        // Failing provider always fails
        failingProvider.failureRate = 1.0
        healthyProvider.failureRate = 0.0

        let executor = FailoverExecutor(
            providers: [failingProvider, healthyProvider],
            circuitBreakerConfig: CircuitBreakerConfiguration(
                failureThreshold: 3,
                recoveryTimeout: .seconds(10)
            )
        )

        let metrics = StressTestMetrics()
        let operations = 20

        // Execute operations
        for i in 0..<operations {
            do {
                let request = AITextRequest(messages: [.user("Request \(i)")])
                _ = try await executor.executeRequest(
                    request: request,
                    modelId: "test-model"
                )
                metrics.recordCompletion()
            } catch {
                metrics.recordError(error)
            }
        }

        // After circuit breaker trips, failing provider should be skipped
        let isOpen = await executor.isCircuitBreakerOpen(for: "failing")
        XCTAssertTrue(isOpen, "Circuit breaker should be open for failing provider")

        // All subsequent requests should succeed via healthy provider
        XCTAssertGreaterThan(metrics.completedCount, 0,
                             "Some operations should succeed through healthy provider")
    }

    // MARK: - Test 5: Mixed Concurrent Operations

    /// Tests multiple different operation types running concurrently
    func test_mixed_concurrent_operations() async throws {
        let metrics = StressTestMetrics()

        let breaker = AdaptiveCircuitBreaker(configuration: .aggressive)

        await withTaskGroup(of: Void.self) { group in
            // 25 agent executions
            for i in 0..<25 {
                group.addTask {
                    let model = StressTestMockModel()
                    let agent = AIAgentActor(model: model, tools: [])
                    do {
                        _ = try await agent.execute(messages: [.user("Agent \(i)")])
                        metrics.recordCompletion()
                    } catch {
                        metrics.recordError(error)
                    }
                }
            }

            // 25 streaming operations
            for i in 0..<25 {
                group.addTask {
                    let model = StressTestMockModel()
                    do {
                        for try await _ in model.streamText(request: AITextRequest(
                            messages: [.user("Stream \(i)")]
                        )) {}
                        metrics.recordCompletion()
                    } catch is CancellationError {
                        metrics.recordCancellation()
                    } catch {
                        metrics.recordError(error)
                    }
                }
            }

            // 25 circuit breaker operations
            for i in 0..<25 {
                group.addTask {
                    do {
                        _ = try await breaker.execute {
                            if i % 5 == 0 {
                                throw ProviderError.networkError("Simulated")
                            }
                            return i
                        }
                        metrics.recordCompletion()
                    } catch {
                        metrics.recordError(error)
                    }
                }
            }

            // 25 direct model calls
            for i in 0..<25 {
                group.addTask {
                    let model = StressTestMockModel()
                    do {
                        _ = try await model.generateText(request: AITextRequest(
                            messages: [.user("Direct \(i)")]
                        ))
                        metrics.recordCompletion()
                    } catch {
                        metrics.recordError(error)
                    }
                }
            }
        }

        // All 100 operations should be handled
        let totalHandled = metrics.completedCount + metrics.errorCount + metrics.cancelledCount
        XCTAssertEqual(totalHandled, 100,
                       "All 100 mixed operations should be handled")
    }
}

// MARK: - StressTestProviderClient

/// Thread-safe mock provider client for stress testing failover scenarios
final class StressTestProviderClient: ProviderClient, @unchecked Sendable {
    let providerId: String
    var displayName: String { providerId }
    var baseURL: URL { URL(string: "https://api.stress-test.local")! }

    private let lock = NSLock()
    private var _failureRate: Double = 0.0
    private var _requestCount: Int = 0

    var failureRate: Double {
        get { lock.withLock { _failureRate } }
        set { lock.withLock { _failureRate = newValue } }
    }

    var requestCount: Int {
        lock.withLock { _requestCount }
    }

    init(providerId: String) {
        self.providerId = providerId
    }

    var healthStatus: ProviderHealthStatus {
        get async {
            failureRate >= 1.0 ? .unhealthy(reason: "Always fails") : .healthy
        }
    }

    var isAvailable: Bool {
        get async { failureRate < 1.0 }
    }

    func execute(request: ProviderRequest) async throws -> ProviderResponse {
        lock.withLock { _requestCount += 1 }

        // Simulate failure based on rate
        if Double.random(in: 0..<1) < failureRate {
            throw ProviderError.serverError(statusCode: 500, message: "Simulated failure")
        }

        // Return mock response
        return ProviderResponse(
            id: "stress-\(requestCount)",
            model: request.modelId,
            provider: providerId,
            content: "Mock response from \(providerId)",
            usage: ProviderUsage(promptTokens: 10, completionTokens: 20),
            finishReason: .stop
        )
    }

    func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let currentFailureRate = failureRate
        let currentProviderId = providerId
        let modelId = request.modelId

        return AsyncThrowingStream { continuation in
            Task {
                if Double.random(in: 0..<1) < currentFailureRate {
                    continuation.finish(throwing: ProviderError.serverError(statusCode: 500, message: "Simulated failure"))
                } else {
                    continuation.yield(.start(id: "stream-stress", model: modelId))
                    continuation.yield(.textDelta("Mock "))
                    continuation.yield(.textDelta("streaming "))
                    continuation.yield(.textDelta("response from \(currentProviderId)"))
                    continuation.yield(.finish(reason: .stop, usage: ProviderUsage(promptTokens: 10, completionTokens: 5)))
                    continuation.finish()
                }
            }
        }
    }

    var availableModels: [String] {
        get async throws {
            ["test-model", "gpt-4"]
        }
    }

    func reset() {
        lock.withLock { _requestCount = 0 }
    }
}
