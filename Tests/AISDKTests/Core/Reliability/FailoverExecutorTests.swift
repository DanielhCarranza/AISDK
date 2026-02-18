//
//  FailoverExecutorTests.swift
//  AISDK
//
//  Tests for FailoverExecutor.
//

import Foundation
import Testing
import XCTest
@testable import AISDK

// MARK: - ExecutionResult Tests

@Suite("ExecutionResult Tests")
struct ExecutionResultTests {
    @Test("ExecutionResult creates with all properties")
    func testCreation() {
        let result = ExecutionResult(
            result: "test",
            provider: "openai",
            attempts: 2,
            latency: .milliseconds(150)
        )

        #expect(result.result == "test")
        #expect(result.provider == "openai")
        #expect(result.attempts == 2)
        #expect(result.latency == .milliseconds(150))
    }

    @Test("ExecutionResult handles nil latency")
    func testNilLatency() {
        let result = ExecutionResult(
            result: 42,
            provider: "anthropic",
            attempts: 1,
            latency: nil
        )

        #expect(result.latency == nil)
    }
}

// MARK: - FailoverExecutorConfiguration Tests

@Suite("FailoverExecutorConfiguration Tests")
struct FailoverExecutorConfigurationTests {
    @Test("Default configuration has expected values")
    func testDefaultConfiguration() {
        let config = FailoverExecutorConfiguration.default

        #expect(config.retryPolicy == .default)
        #expect(config.timeoutPolicy == .default)
        #expect(config.failoverPolicy == .default)
        #expect(config.recordMetrics == true)
    }

    @Test("Custom configuration preserves values")
    func testCustomConfiguration() {
        let config = FailoverExecutorConfiguration(
            retryPolicy: .aggressive,
            timeoutPolicy: .lenient,
            failoverPolicy: .strict,
            recordMetrics: false
        )

        #expect(config.retryPolicy == .aggressive)
        #expect(config.timeoutPolicy == .lenient)
        #expect(config.failoverPolicy == .strict)
        #expect(config.recordMetrics == false)
    }
}

// MARK: - FailoverError Tests

@Suite("FailoverError Tests")
struct FailoverErrorTests {
    @Test("noProvidersAvailable has correct description")
    func testNoProvidersAvailable() {
        let error = FailoverError.noProvidersAvailable
        #expect(error.errorDescription?.contains("No providers available") == true)
    }

    @Test("allProvidersFailed includes last error")
    func testAllProvidersFailed() {
        let error = FailoverError.allProvidersFailed(lastError: "Connection refused")
        #expect(error.errorDescription?.contains("All providers failed") == true)
        #expect(error.errorDescription?.contains("Connection refused") == true)
    }

    @Test("providerNotAllowed includes provider name")
    func testProviderNotAllowed() {
        let error = FailoverError.providerNotAllowed(provider: "restricted-provider")
        #expect(error.errorDescription?.contains("restricted-provider") == true)
    }

    @Test("circuitBreakerOpen includes provider name")
    func testCircuitBreakerOpen() {
        let error = FailoverError.circuitBreakerOpen(provider: "openai")
        #expect(error.errorDescription?.contains("openai") == true)
        #expect(error.errorDescription?.contains("Circuit breaker") == true)
    }

    @Test("timeout includes provider name")
    func testTimeout() {
        let error = FailoverError.timeout(provider: "anthropic")
        #expect(error.errorDescription?.contains("anthropic") == true)
        #expect(error.errorDescription?.contains("timed out") == true)
    }

    @Test("FailoverError is Equatable")
    func testEquatable() {
        #expect(FailoverError.noProvidersAvailable == FailoverError.noProvidersAvailable)
        #expect(FailoverError.allProvidersFailed(lastError: "err") == FailoverError.allProvidersFailed(lastError: "err"))
        #expect(FailoverError.allProvidersFailed(lastError: "a") != FailoverError.allProvidersFailed(lastError: "b"))
        #expect(FailoverError.circuitBreakerOpen(provider: "x") == FailoverError.circuitBreakerOpen(provider: "x"))
    }
}

// MARK: - Failover Mock ProviderClient for Testing

final class FailoverMockProviderClient: ProviderClient, @unchecked Sendable {
    let providerId: String
    var displayName: String { providerId }
    var baseURL: URL { URL(string: "https://api.example.com")! }

    var shouldFail: Bool
    var failureError: Error
    var executeCount: Int = 0
    var latency: Duration

    init(
        providerId: String,
        shouldFail: Bool = false,
        failureError: Error = ProviderError.networkError("Connection failed"),
        latency: Duration = .milliseconds(10)
    ) {
        self.providerId = providerId
        self.shouldFail = shouldFail
        self.failureError = failureError
        self.latency = latency
    }

    var healthStatus: ProviderHealthStatus {
        get async {
            shouldFail ? .unhealthy(reason: "Mock failure") : .healthy
        }
    }

    var isAvailable: Bool {
        get async {
            !shouldFail
        }
    }

    func execute(request: ProviderRequest) async throws -> ProviderResponse {
        executeCount += 1
        try await Task.sleep(for: latency)

        if shouldFail {
            throw failureError
        }

        return ProviderResponse(
            id: "response-\(executeCount)",
            model: request.modelId,
            provider: providerId,
            content: "Mock response",
            usage: ProviderUsage(promptTokens: 10, completionTokens: 20),
            finishReason: .stop
        )
    }

    func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                if shouldFail {
                    continuation.finish(throwing: failureError)
                } else {
                    continuation.yield(.start(id: "stream-1", model: request.modelId))
                    continuation.yield(.textDelta("Hello"))
                    continuation.yield(.finish(reason: .stop, usage: ProviderUsage(promptTokens: 10, completionTokens: 5)))
                    continuation.finish()
                }
            }
        }
    }

    var availableModels: [String] {
        get async throws {
            ["gpt-4", "gpt-3.5-turbo"]
        }
    }
}

// MARK: - Mock Delegate for Testing

final class MockFailoverDelegate: FailoverExecutorDelegate, @unchecked Sendable {
    var selectedProviders: [(provider: String, reason: String)] = []
    var failovers: [(from: String, to: String?, error: Error)] = []
    var completions: [(provider: String, attempts: Int, latency: Duration?)] = []
    var exhaustedErrors: [String: Error]?

    func didSelectProvider(_ provider: String, reason: String) {
        selectedProviders.append((provider, reason))
    }

    func didFailover(from provider: String, to: String?, error: Error) {
        failovers.append((from: provider, to: to, error: error))
    }

    func didComplete(provider: String, attempts: Int, latency: Duration?) {
        completions.append((provider, attempts, latency))
    }

    func didExhaustAllProviders(errors: [String: Error]) {
        exhaustedErrors = errors
    }
}

// MARK: - FailoverExecutor XCTest Tests

final class FailoverExecutorTests: XCTestCase {
    func test_execute_succeedsWithFirstProvider() async throws {
        let provider = FailoverMockProviderClient(providerId: "openai")
        let executor = FailoverExecutor(providers: [provider])

        let request = AITextRequest(messages: [.user("Hello")])
        let result = try await executor.executeRequest(request: request, modelId: "gpt-4")

        XCTAssertEqual(result.provider, "openai")
        XCTAssertEqual(result.attempts, 1)
        XCTAssertNotNil(result.latency)
    }

    func test_execute_failsOverToSecondProvider() async throws {
        let failingProvider = FailoverMockProviderClient(providerId: "openai", shouldFail: true)
        let workingProvider = FailoverMockProviderClient(providerId: "anthropic")
        // Disable retries to ensure clean failover behavior
        let config = FailoverExecutorConfiguration(retryPolicy: .none)
        let executor = FailoverExecutor(
            providers: [failingProvider, workingProvider],
            configuration: config
        )

        let request = AITextRequest(messages: [.user("Hello")])
        let result = try await executor.executeRequest(request: request, modelId: "model")

        XCTAssertEqual(result.provider, "anthropic")
        XCTAssertEqual(result.attempts, 2)
        XCTAssertEqual(failingProvider.executeCount, 1)
        XCTAssertEqual(workingProvider.executeCount, 1)
    }

    func test_execute_throwsWhenAllProvidersFail() async throws {
        let provider1 = FailoverMockProviderClient(providerId: "openai", shouldFail: true)
        let provider2 = FailoverMockProviderClient(providerId: "anthropic", shouldFail: true)
        let executor = FailoverExecutor(providers: [provider1, provider2])

        let request = AITextRequest(messages: [.user("Hello")])

        do {
            _ = try await executor.executeRequest(request: request, modelId: "model")
            XCTFail("Expected error to be thrown")
        } catch let error as FailoverError {
            if case .allProvidersFailed = error {
                // Expected
            } else {
                XCTFail("Expected allProvidersFailed error")
            }
        }
    }

    func test_execute_throwsWhenNoProviders() async throws {
        let executor = FailoverExecutor(providers: [])

        let request = AITextRequest(messages: [.user("Hello")])

        do {
            _ = try await executor.executeRequest(request: request, modelId: "model")
            XCTFail("Expected error to be thrown")
        } catch let error as FailoverError {
            XCTAssertEqual(error, .noProvidersAvailable)
        }
    }

    func test_execute_respectsAllowlist() async throws {
        let provider1 = FailoverMockProviderClient(providerId: "openai")
        let provider2 = FailoverMockProviderClient(providerId: "anthropic")
        let executor = FailoverExecutor(providers: [provider1, provider2])

        // Only allow anthropic
        let request = AITextRequest(
            messages: [.user("Hello")],
            allowedProviders: ["anthropic"]
        )
        let result = try await executor.executeRequest(request: request, modelId: "model")

        XCTAssertEqual(result.provider, "anthropic")
        XCTAssertEqual(provider1.executeCount, 0)  // Should be skipped
        XCTAssertEqual(provider2.executeCount, 1)
    }

    func test_execute_callsDelegateOnSuccess() async throws {
        let provider = FailoverMockProviderClient(providerId: "openai")
        let executor = FailoverExecutor(providers: [provider])
        let delegate = MockFailoverDelegate()
        await executor.setDelegate(delegate)

        let request = AITextRequest(messages: [.user("Hello")])
        _ = try await executor.executeRequest(request: request, modelId: "model")

        XCTAssertEqual(delegate.selectedProviders.count, 1)
        XCTAssertEqual(delegate.selectedProviders.first?.provider, "openai")
        XCTAssertEqual(delegate.completions.count, 1)
        XCTAssertEqual(delegate.completions.first?.provider, "openai")
    }

    func test_execute_callsDelegateOnFailover() async throws {
        let failingProvider = FailoverMockProviderClient(providerId: "openai", shouldFail: true)
        let workingProvider = FailoverMockProviderClient(providerId: "anthropic")
        let executor = FailoverExecutor(providers: [failingProvider, workingProvider])
        let delegate = MockFailoverDelegate()
        await executor.setDelegate(delegate)

        let request = AITextRequest(messages: [.user("Hello")])
        _ = try await executor.executeRequest(request: request, modelId: "model")

        XCTAssertEqual(delegate.failovers.count, 1)
        XCTAssertEqual(delegate.failovers.first?.from, "openai")
        XCTAssertEqual(delegate.failovers.first?.to, "anthropic")
    }

    func test_execute_callsDelegateWhenExhausted() async throws {
        let provider1 = FailoverMockProviderClient(providerId: "openai", shouldFail: true)
        let provider2 = FailoverMockProviderClient(providerId: "anthropic", shouldFail: true)
        let executor = FailoverExecutor(providers: [provider1, provider2])
        let delegate = MockFailoverDelegate()
        await executor.setDelegate(delegate)

        let request = AITextRequest(messages: [.user("Hello")])
        _ = try? await executor.executeRequest(request: request, modelId: "model")

        XCTAssertNotNil(delegate.exhaustedErrors)
        XCTAssertEqual(delegate.exhaustedErrors?.count, 2)
    }

    func test_providerIds_returnsAllProviderIds() async throws {
        let provider1 = FailoverMockProviderClient(providerId: "openai")
        let provider2 = FailoverMockProviderClient(providerId: "anthropic")
        let executor = FailoverExecutor(providers: [provider1, provider2])

        let ids = await executor.providerIds
        XCTAssertEqual(ids, ["openai", "anthropic"])
    }

    func test_providerCount_returnsCorrectCount() async throws {
        let provider1 = FailoverMockProviderClient(providerId: "openai")
        let provider2 = FailoverMockProviderClient(providerId: "anthropic")
        let executor = FailoverExecutor(providers: [provider1, provider2])

        let count = await executor.providerCount
        XCTAssertEqual(count, 2)
    }

    func test_circuitBreakerState_returnsState() async throws {
        let provider = FailoverMockProviderClient(providerId: "openai")
        let executor = FailoverExecutor(providers: [provider])

        let state = await executor.circuitBreakerState(for: "openai")
        XCTAssertNotNil(state)
        if case .closed = state {
            // Expected
        } else {
            XCTFail("Expected closed state")
        }
    }

    func test_circuitBreakerState_returnsNilForUnknown() async throws {
        let provider = FailoverMockProviderClient(providerId: "openai")
        let executor = FailoverExecutor(providers: [provider])

        let state = await executor.circuitBreakerState(for: "unknown")
        XCTAssertNil(state)
    }

    func test_resetCircuitBreaker_resetsState() async throws {
        let failingProvider = FailoverMockProviderClient(providerId: "openai", shouldFail: true)
        let config = CircuitBreakerConfiguration(failureThreshold: 1)
        let executor = FailoverExecutor(
            providers: [failingProvider],
            circuitBreakerConfig: config
        )

        // Trigger a failure to open the circuit breaker
        let request = AITextRequest(messages: [.user("Hello")])
        _ = try? await executor.executeRequest(request: request, modelId: "model")

        // Reset the circuit breaker
        await executor.resetCircuitBreaker(for: "openai")

        // Verify it's back to closed
        let state = await executor.circuitBreakerState(for: "openai")
        XCTAssertNotNil(state)
        if case .closed = state {
            // Expected
        } else {
            XCTFail("Expected closed state after reset")
        }
    }

    func test_resetAllCircuitBreakers_resetsAll() async throws {
        let provider1 = FailoverMockProviderClient(providerId: "openai", shouldFail: true)
        let provider2 = FailoverMockProviderClient(providerId: "anthropic", shouldFail: true)
        let config = CircuitBreakerConfiguration(failureThreshold: 1)
        let executor = FailoverExecutor(
            providers: [provider1, provider2],
            circuitBreakerConfig: config
        )

        // Trigger failures
        let request = AITextRequest(messages: [.user("Hello")])
        _ = try? await executor.executeRequest(request: request, modelId: "model")

        // Reset all
        await executor.resetAllCircuitBreakers()

        let state1 = await executor.circuitBreakerState(for: "openai")
        let state2 = await executor.circuitBreakerState(for: "anthropic")

        if case .closed = state1 {
            // Expected
        } else {
            XCTFail("Expected closed state for openai after reset")
        }

        if case .closed = state2 {
            // Expected
        } else {
            XCTFail("Expected closed state for anthropic after reset")
        }
    }

    func test_healthMonitor_recordsMetrics() async throws {
        let provider = FailoverMockProviderClient(providerId: "openai")
        let healthMonitor = ProviderHealthMonitor()
        let executor = FailoverExecutor(
            providers: [provider],
            healthMonitor: healthMonitor
        )

        let request = AITextRequest(messages: [.user("Hello")])
        _ = try await executor.executeRequest(request: request, modelId: "model")

        let status = await healthMonitor.healthStatus(for: "openai")
        XCTAssertEqual(status.requestCount, 1)
        XCTAssertTrue(status.latencyP50 > .zero)
    }

    func test_healthMonitor_recordsErrors() async throws {
        let failingProvider = FailoverMockProviderClient(providerId: "openai", shouldFail: true)
        let healthMonitor = ProviderHealthMonitor()
        let executor = FailoverExecutor(
            providers: [failingProvider],
            healthMonitor: healthMonitor
        )

        let request = AITextRequest(messages: [.user("Hello")])
        _ = try? await executor.executeRequest(request: request, modelId: "model")

        let status = await healthMonitor.healthStatus(for: "openai")
        XCTAssertEqual(status.errorCount, 1)
    }
}

// MARK: - FailoverExecutorBuilder Tests

@Suite("FailoverExecutorBuilder Tests")
struct FailoverExecutorBuilderTests {
    @Test("Builder creates executor with providers")
    func testBuilderWithProviders() async {
        let provider = FailoverMockProviderClient(providerId: "openai")
        let executor = FailoverExecutorBuilder()
            .with(provider: provider)
            .build()

        let count = await executor.providerCount
        #expect(count == 1)
    }

    @Test("Builder adds multiple providers")
    func testBuilderWithMultipleProviders() async {
        let provider1 = FailoverMockProviderClient(providerId: "openai")
        let provider2 = FailoverMockProviderClient(providerId: "anthropic")
        let executor = FailoverExecutorBuilder()
            .with(providers: [provider1, provider2])
            .build()

        let count = await executor.providerCount
        #expect(count == 2)
    }

    @Test("Builder sets health monitor")
    func testBuilderWithHealthMonitor() async throws {
        let provider = FailoverMockProviderClient(providerId: "openai")
        let healthMonitor = ProviderHealthMonitor()
        let executor = FailoverExecutorBuilder()
            .with(provider: provider)
            .with(healthMonitor: healthMonitor)
            .build()

        let request = AITextRequest(messages: [.user("Test")])
        _ = try await executor.executeRequest(request: request, modelId: "model")

        let status = await healthMonitor.healthStatus(for: "openai")
        #expect(status.requestCount == 1)
    }

    @Test("Builder sets configuration")
    func testBuilderWithConfiguration() async {
        let provider = FailoverMockProviderClient(providerId: "openai")
        let config = FailoverExecutorConfiguration(recordMetrics: false)
        let executor = FailoverExecutorBuilder()
            .with(provider: provider)
            .with(configuration: config)
            .build()

        let actualConfig = await executor.configuration
        #expect(actualConfig.recordMetrics == false)
    }

    @Test("Builder chains methods fluently")
    func testBuilderChaining() async {
        let provider = FailoverMockProviderClient(providerId: "openai")
        let healthMonitor = ProviderHealthMonitor()
        let config = FailoverExecutorConfiguration(recordMetrics: false)
        let cbConfig = CircuitBreakerConfiguration(failureThreshold: 5)

        let executor = FailoverExecutorBuilder()
            .with(provider: provider)
            .with(healthMonitor: healthMonitor)
            .with(configuration: config)
            .with(circuitBreakerConfig: cbConfig)
            .build()

        let count = await executor.providerCount
        #expect(count == 1)
    }
}

// MARK: - Helper extension for tests

extension FailoverExecutor {
    func setDelegate(_ delegate: any FailoverExecutorDelegate) async {
        self.delegate = delegate
    }
}
