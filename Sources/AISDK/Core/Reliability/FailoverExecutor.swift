//
//  FailoverExecutor.swift
//  AISDK
//
//  Execute requests across a failover chain of providers with
//  circuit breakers, retry policies, and health monitoring.
//

import Foundation

// MARK: - ExecutionResult

/// Result of executing a request through the failover executor.
public struct ExecutionResult<T: Sendable>: Sendable {
    /// The result of the operation.
    public let result: T

    /// The provider that handled the request.
    public let provider: String

    /// Number of providers attempted before success.
    public let attempts: Int

    /// Latency of the successful request.
    public let latency: Duration?

    /// Creates an execution result.
    public init(
        result: T,
        provider: String,
        attempts: Int,
        latency: Duration? = nil
    ) {
        self.result = result
        self.provider = provider
        self.attempts = attempts
        self.latency = latency
    }
}

// MARK: - FailoverExecutorConfiguration

/// Configuration for the failover executor.
public struct FailoverExecutorConfiguration: Sendable {
    /// Retry policy for transient failures.
    public let retryPolicy: RetryPolicy

    /// Timeout policy for requests.
    public let timeoutPolicy: TimeoutPolicy

    /// Failover policy for provider selection.
    public let failoverPolicy: FailoverPolicy

    /// Whether to record metrics to health monitor.
    public let recordMetrics: Bool

    /// Default configuration.
    public static let `default` = FailoverExecutorConfiguration()

    /// Creates a configuration.
    public init(
        retryPolicy: RetryPolicy = .default,
        timeoutPolicy: TimeoutPolicy = .default,
        failoverPolicy: FailoverPolicy = .default,
        recordMetrics: Bool = true
    ) {
        self.retryPolicy = retryPolicy
        self.timeoutPolicy = timeoutPolicy
        self.failoverPolicy = failoverPolicy
        self.recordMetrics = recordMetrics
    }
}

// MARK: - FailoverExecutorDelegate

/// Delegate for failover executor events.
public protocol FailoverExecutorDelegate: AnyObject, Sendable {
    /// Called when a provider is selected.
    func didSelectProvider(_ provider: String, reason: String)

    /// Called when a provider fails and failover occurs.
    func didFailover(from provider: String, to: String?, error: Error)

    /// Called when execution completes successfully.
    func didComplete(provider: String, attempts: Int, latency: Duration?)

    /// Called when all providers are exhausted.
    func didExhaustAllProviders(errors: [String: Error])
}

/// Default implementations for delegate.
public extension FailoverExecutorDelegate {
    func didSelectProvider(_ provider: String, reason: String) {}
    func didFailover(from provider: String, to: String?, error: Error) {}
    func didComplete(provider: String, attempts: Int, latency: Duration?) {}
    func didExhaustAllProviders(errors: [String: Error]) {}
}

// MARK: - FailoverError

/// Errors that can occur during failover execution.
public enum FailoverError: Error, Sendable, Equatable {
    /// No providers available in the chain.
    case noProvidersAvailable

    /// All providers in the chain failed.
    case allProvidersFailed(lastError: String)

    /// Provider not in allowlist.
    case providerNotAllowed(provider: String)

    /// Circuit breaker rejected the request.
    case circuitBreakerOpen(provider: String)

    /// Request timed out.
    case timeout(provider: String)
}

extension FailoverError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noProvidersAvailable:
            return "No providers available in the failover chain"
        case .allProvidersFailed(let lastError):
            return "All providers failed. Last error: \(lastError)"
        case .providerNotAllowed(let provider):
            return "Provider '\(provider)' is not in the allowed providers list"
        case .circuitBreakerOpen(let provider):
            return "Circuit breaker is open for provider '\(provider)'"
        case .timeout(let provider):
            return "Request to provider '\(provider)' timed out"
        }
    }
}

// MARK: - FailoverExecutor

/// Actor for executing requests across a failover chain of providers.
///
/// ## Features
/// - Circuit breaker integration per provider
/// - Retry policy for transient failures
/// - Timeout enforcement
/// - Health monitoring
/// - PHI allowlist enforcement
///
/// ## Usage
/// ```swift
/// let executor = FailoverExecutor(
///     providers: [openaiClient, anthropicClient],
///     healthMonitor: monitor
/// )
///
/// let result = try await executor.execute(request: request) { provider, req in
///     try await provider.execute(request: req.toProviderRequest(modelId: "gpt-4"))
/// }
/// ```
public actor FailoverExecutor {
    // MARK: - Properties

    /// The chain of providers to try in order.
    private let providers: [any ProviderClient]

    /// Circuit breakers per provider.
    private var circuitBreakers: [String: AdaptiveCircuitBreaker] = [:]

    /// Health monitor for metrics.
    private let healthMonitor: ProviderHealthMonitor?

    /// Configuration.
    public let configuration: FailoverExecutorConfiguration

    /// Delegate for events.
    public var delegate: (any FailoverExecutorDelegate)?

    /// Clock for timing.
    private let clock: ContinuousClock

    // MARK: - Initialization

    /// Creates a failover executor.
    ///
    /// - Parameters:
    ///   - providers: The chain of providers to try
    ///   - healthMonitor: Optional health monitor for metrics
    ///   - configuration: Executor configuration
    ///   - circuitBreakerConfig: Configuration for circuit breakers
    public init(
        providers: [any ProviderClient],
        healthMonitor: ProviderHealthMonitor? = nil,
        configuration: FailoverExecutorConfiguration = .default,
        circuitBreakerConfig: CircuitBreakerConfiguration = .default
    ) {
        self.providers = providers
        self.healthMonitor = healthMonitor
        self.configuration = configuration
        self.clock = ContinuousClock()

        // Create circuit breaker for each provider
        for provider in providers {
            circuitBreakers[provider.providerId] = AdaptiveCircuitBreaker(
                configuration: circuitBreakerConfig
            )
        }
    }

    // MARK: - Execution Methods

    /// Execute a request across the failover chain.
    ///
    /// - Parameters:
    ///   - request: The request to execute
    ///   - modelId: The model ID to use
    ///   - operation: The operation to perform with the provider
    /// - Returns: The execution result
    /// - Throws: `FailoverError` if all providers fail
    public func execute<T: Sendable>(
        request: AITextRequest,
        modelId: String,
        operation: @escaping @Sendable (any ProviderClient, ProviderRequest) async throws -> T
    ) async throws -> ExecutionResult<T> {
        guard !providers.isEmpty else {
            throw FailoverError.noProvidersAvailable
        }

        var lastError: Error = FailoverError.noProvidersAvailable
        var attempts = 0
        var errors: [String: Error] = [:]

        for provider in providers {
            let providerId = provider.providerId

            // Check PHI allowlist
            if !configuration.failoverPolicy.isProviderAllowed(request: request, providerId: providerId) {
                continue
            }

            // Check circuit breaker
            guard let breaker = circuitBreakers[providerId] else { continue }

            let isAvailable = await breaker.isAvailable
            if !isAvailable {
                delegate?.didFailover(
                    from: providerId,
                    to: nil,
                    error: FailoverError.circuitBreakerOpen(provider: providerId)
                )
                continue
            }

            attempts += 1
            delegate?.didSelectProvider(providerId, reason: "next in chain")

            // Try to execute with retry
            do {
                let (result, latency) = try await executeWithRetry(
                    provider: provider,
                    request: request,
                    modelId: modelId,
                    operation: operation
                )

                // Record success
                await breaker.recordSuccess()
                if configuration.recordMetrics, let monitor = healthMonitor {
                    await monitor.recordLatency(latency, for: providerId)
                }

                delegate?.didComplete(provider: providerId, attempts: attempts, latency: latency)

                return ExecutionResult(
                    result: result,
                    provider: providerId,
                    attempts: attempts,
                    latency: latency
                )
            } catch {
                lastError = error
                errors[providerId] = error

                // Record failure
                await breaker.recordFailure()
                if configuration.recordMetrics, let monitor = healthMonitor {
                    await monitor.recordError(for: providerId)
                }

                // Determine next provider
                let nextProvider = nextAvailableProvider(after: providerId, request: request)
                delegate?.didFailover(from: providerId, to: nextProvider, error: error)

                // Continue to next provider
            }
        }

        delegate?.didExhaustAllProviders(errors: errors)
        throw FailoverError.allProvidersFailed(lastError: lastError.localizedDescription)
    }

    /// Execute with a simplified interface for ProviderResponse.
    ///
    /// - Parameters:
    ///   - request: The request to execute
    ///   - modelId: The model ID to use
    /// - Returns: The execution result with ProviderResponse
    public func executeRequest(
        request: AITextRequest,
        modelId: String
    ) async throws -> ExecutionResult<ProviderResponse> {
        try await execute(request: request, modelId: modelId) { provider, providerRequest in
            try await provider.execute(request: providerRequest)
        }
    }

    // MARK: - Provider Information

    /// Get the list of provider IDs in the chain.
    public var providerIds: [String] {
        providers.map { $0.providerId }
    }

    /// Get the number of providers in the chain.
    public var providerCount: Int {
        providers.count
    }

    /// Check if a provider's circuit breaker is open.
    ///
    /// - Parameter providerId: The provider to check
    /// - Returns: True if the circuit breaker is open
    public func isCircuitBreakerOpen(for providerId: String) async -> Bool {
        guard let breaker = circuitBreakers[providerId] else { return false }
        return !(await breaker.isAvailable)
    }

    /// Get the current state of a provider's circuit breaker.
    ///
    /// - Parameter providerId: The provider to check
    /// - Returns: The circuit breaker state, or nil if not found
    public func circuitBreakerState(for providerId: String) async -> CircuitBreakerState? {
        guard let breaker = circuitBreakers[providerId] else { return nil }
        return await breaker.currentState
    }

    /// Reset a provider's circuit breaker.
    ///
    /// - Parameter providerId: The provider to reset
    public func resetCircuitBreaker(for providerId: String) async {
        guard let breaker = circuitBreakers[providerId] else { return }
        await breaker.reset()
    }

    /// Reset all circuit breakers.
    public func resetAllCircuitBreakers() async {
        for breaker in circuitBreakers.values {
            await breaker.reset()
        }
    }

    // MARK: - Private Helpers

    private func executeWithRetry<T: Sendable>(
        provider: any ProviderClient,
        request: AITextRequest,
        modelId: String,
        operation: @escaping @Sendable (any ProviderClient, ProviderRequest) async throws -> T
    ) async throws -> (T, Duration) {
        let retryExecutor = RetryExecutor(policy: configuration.retryPolicy)
        let timeoutExecutor = TimeoutExecutor(policy: configuration.timeoutPolicy)
        let providerRequest = try request.toProviderRequest(modelId: modelId)

        let startTime = clock.now

        let result = try await retryExecutor.execute {
            try await timeoutExecutor.execute {
                try await operation(provider, providerRequest)
            }
        }

        let latency = clock.now - startTime
        return (result, latency)
    }

    private func nextAvailableProvider(after providerId: String, request: AITextRequest) -> String? {
        var foundCurrent = false
        for provider in providers {
            if provider.providerId == providerId {
                foundCurrent = true
                continue
            }
            if foundCurrent && configuration.failoverPolicy.isProviderAllowed(request: request, providerId: provider.providerId) {
                return provider.providerId
            }
        }
        return nil
    }
}

// MARK: - FailoverExecutor Builder

/// Builder for creating FailoverExecutor with fluent API.
public struct FailoverExecutorBuilder: Sendable {
    private var providers: [any ProviderClient] = []
    private var healthMonitor: ProviderHealthMonitor?
    private var configuration: FailoverExecutorConfiguration = .default
    private var circuitBreakerConfig: CircuitBreakerConfiguration = .default

    /// Creates a new builder.
    public init() {}

    /// Add a provider to the chain.
    public func with(provider: any ProviderClient) -> FailoverExecutorBuilder {
        var copy = self
        copy.providers.append(provider)
        return copy
    }

    /// Add multiple providers to the chain.
    public func with(providers: [any ProviderClient]) -> FailoverExecutorBuilder {
        var copy = self
        copy.providers.append(contentsOf: providers)
        return copy
    }

    /// Set the health monitor.
    public func with(healthMonitor: ProviderHealthMonitor) -> FailoverExecutorBuilder {
        var copy = self
        copy.healthMonitor = healthMonitor
        return copy
    }

    /// Set the configuration.
    public func with(configuration: FailoverExecutorConfiguration) -> FailoverExecutorBuilder {
        var copy = self
        copy.configuration = configuration
        return copy
    }

    /// Set the circuit breaker configuration.
    public func with(circuitBreakerConfig: CircuitBreakerConfiguration) -> FailoverExecutorBuilder {
        var copy = self
        copy.circuitBreakerConfig = circuitBreakerConfig
        return copy
    }

    /// Build the FailoverExecutor.
    public func build() -> FailoverExecutor {
        FailoverExecutor(
            providers: providers,
            healthMonitor: healthMonitor,
            configuration: configuration,
            circuitBreakerConfig: circuitBreakerConfig
        )
    }
}
