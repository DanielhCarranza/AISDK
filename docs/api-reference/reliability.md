# Reliability

> Circuit breakers, failover, retry policies, and health monitoring

## AdaptiveCircuitBreaker

Actor-based circuit breaker with adaptive failure detection.

```swift
public actor AdaptiveCircuitBreaker {
    /// Configuration for this breaker
    public let configuration: CircuitBreakerConfiguration

    /// Optional delegate for notifications
    public var delegate: (any CircuitBreakerDelegate)?

    /// Current state of the circuit
    public var currentState: CircuitBreakerState { get async }

    /// Whether accepting requests
    public var isAvailable: Bool { get async }

    /// Current metrics
    public var metrics: CircuitBreakerMetrics { get }
}
```

### CircuitBreakerState

```swift
public enum CircuitBreakerState: Sendable, Equatable {
    /// Normal operation, requests flow through
    case closed

    /// Failing, requests rejected until recovery time
    case open(until: ContinuousClock.Instant)

    /// Testing recovery with limited probe requests
    case halfOpen

    /// Whether this state accepts traffic
    public var acceptsTraffic: Bool
}
```

### CircuitBreakerConfiguration

```swift
public struct CircuitBreakerConfiguration: Sendable {
    /// Failures before opening (default: 5)
    public let failureThreshold: Int

    /// Time before half-open (default: 30s)
    public let recoveryTimeout: Duration

    /// Successes needed to close (default: 2)
    public let successThreshold: Int

    /// Max probes in half-open (default: 3)
    public let halfOpenMaxProbes: Int

    /// Sliding window size (default: 0, disabled)
    public let slidingWindowSize: Int

    /// Failure rate threshold (default: 0.5)
    public let failureRateThreshold: Double

    // Presets
    public static let `default`: CircuitBreakerConfiguration
    public static let aggressive: CircuitBreakerConfiguration
    public static let lenient: CircuitBreakerConfiguration
}
```

### Usage

```swift
let breaker = AdaptiveCircuitBreaker(configuration: .default)

// Execute through circuit breaker
do {
    let result = try await breaker.execute {
        try await provider.makeRequest()
    }
} catch CircuitBreakerError.circuitOpen(let until) {
    print("Circuit open until \(until)")
    // Use fallback
}

// Manual recording
await breaker.recordSuccess()
await breaker.recordFailure()

// Reset breaker
await breaker.reset()

// Force open
await breaker.forceOpen(for: .seconds(60))
```

### CircuitBreakerMetrics

```swift
public struct CircuitBreakerMetrics: Sendable {
    public let totalSuccesses: Int
    public let totalFailures: Int
    public let consecutiveFailures: Int
    public let openCount: Int
    public let state: CircuitBreakerState
    public let lastStateChange: ContinuousClock.Instant?
    public let slidingWindowFailureRate: Double?
}
```

---

## CircuitBreakerRegistry

Manages circuit breakers for multiple providers.

```swift
public actor CircuitBreakerRegistry {
    /// Get or create a breaker for a provider
    public func breaker(
        for providerId: String,
        configuration: CircuitBreakerConfiguration? = nil
    ) -> AdaptiveCircuitBreaker

    /// Remove a breaker
    public func removeBreaker(for providerId: String)

    /// Reset all breakers
    public func resetAll() async

    /// Get all metrics
    public func allMetrics() async -> [String: CircuitBreakerMetrics]
}
```

---

## FailoverExecutor

Executes requests across a chain of providers with automatic failover.

```swift
public actor FailoverExecutor {
    /// Provider chain
    public var providerIds: [String] { get }
    public var providerCount: Int { get }

    /// Check circuit breaker status
    public func isCircuitBreakerOpen(for providerId: String) async -> Bool
    public func circuitBreakerState(for providerId: String) async -> CircuitBreakerState?

    /// Reset circuit breakers
    public func resetCircuitBreaker(for providerId: String) async
    public func resetAllCircuitBreakers() async
}
```

### Initialization

```swift
public init(
    providers: [any ProviderClient],
    healthMonitor: ProviderHealthMonitor? = nil,
    configuration: FailoverExecutorConfiguration = .default,
    circuitBreakerConfig: CircuitBreakerConfiguration = .default
)
```

### Execution

```swift
// Execute with custom operation
public func execute<T: Sendable>(
    request: AITextRequest,
    modelId: String,
    operation: @escaping @Sendable (any ProviderClient, ProviderRequest) async throws -> T
) async throws -> ExecutionResult<T>

// Execute for ProviderResponse
public func executeRequest(
    request: AITextRequest,
    modelId: String
) async throws -> ExecutionResult<ProviderResponse>
```

### ExecutionResult

```swift
public struct ExecutionResult<T: Sendable>: Sendable {
    /// The operation result
    public let result: T

    /// Provider that handled the request
    public let provider: String

    /// Number of providers attempted
    public let attempts: Int

    /// Request latency
    public let latency: Duration?
}
```

### Usage

```swift
let executor = FailoverExecutor(
    providers: [openRouterClient, liteLLMClient],
    healthMonitor: monitor,
    configuration: .default
)

let result = try await executor.executeRequest(
    request: aiRequest,
    modelId: "gpt-4"
)

print("Handled by: \(result.provider)")
print("Attempts: \(result.attempts)")
```

### FailoverExecutorBuilder

Fluent API for building executors:

```swift
let executor = FailoverExecutorBuilder()
    .with(providers: [openRouterClient, liteLLMClient])
    .with(healthMonitor: monitor)
    .with(configuration: .default)
    .with(circuitBreakerConfig: .aggressive)
    .build()
```

---

## FailoverPolicy

Controls failover behavior based on capabilities and cost.

```swift
public struct FailoverPolicy: Sendable, Equatable {
    /// Max cost multiplier (default: 5.0)
    public let maxCostMultiplier: Double

    /// Require capability match (default: true)
    public let requireCapabilityMatch: Bool

    /// Token estimator for context checks
    public let tokenEstimator: TokenEstimator

    /// Minimum context window (default: 0)
    public let minimumContextWindow: Int

    /// Allow lower performance tiers (default: true)
    public let allowLowerTier: Bool

    /// Required capabilities
    public let requiredCapabilities: LLMCapabilities

    // Presets
    public static let `default`: FailoverPolicy
    public static let strict: FailoverPolicy
    public static let lenient: FailoverPolicy
    public static let costConscious: FailoverPolicy
}
```

### Modifier Methods

```swift
let policy = FailoverPolicy.default
    .withMaxCostMultiplier(2.0)
    .withRequireCapabilityMatch(true)
    .withRequiredCapabilities(.vision)
    .withMinimumContextWindow(8000)
```

---

## RetryPolicy

Controls retry behavior for transient failures.

```swift
public struct RetryPolicy: Sendable {
    /// Maximum retry attempts
    public let maxRetries: Int

    /// Initial delay between retries
    public let initialDelay: Duration

    /// Maximum delay between retries
    public let maxDelay: Duration

    /// Backoff multiplier
    public let multiplier: Double

    /// Whether to add jitter
    public let jitter: Bool

    /// Errors that should trigger retry
    public let retryableErrors: Set<RetryableErrorType>

    // Presets
    public static let `default`: RetryPolicy
    public static let aggressive: RetryPolicy
    public static let conservative: RetryPolicy
    public static let none: RetryPolicy  // No retries
}
```

### RetryExecutor

```swift
public struct RetryExecutor: Sendable {
    public init(policy: RetryPolicy)

    public func execute<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T
}
```

### Usage

```swift
let retryExecutor = RetryExecutor(policy: .default)

let result = try await retryExecutor.execute {
    try await riskyOperation()
}
```

---

## TimeoutPolicy

Controls timeout behavior.

```swift
public struct TimeoutPolicy: Sendable {
    /// Default timeout duration
    public let timeout: Duration

    /// Whether to throw on timeout
    public let throwOnTimeout: Bool

    // Presets
    public static let `default`: TimeoutPolicy  // 30s
    public static let short: TimeoutPolicy      // 10s
    public static let long: TimeoutPolicy       // 120s
}
```

### TimeoutExecutor

```swift
public struct TimeoutExecutor: Sendable {
    public init(policy: TimeoutPolicy)

    public func execute<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T
}
```

---

## TokenEstimator

Estimates token counts for requests.

```swift
public struct TokenEstimator: Sendable, Equatable {
    /// Characters per token (default: 4)
    public let charsPerToken: Int

    // Presets
    public static let `default`: TokenEstimator      // 4 chars/token
    public static let conservative: TokenEstimator   // 3 chars/token

    /// Estimate tokens for a request
    public func estimate(_ request: AITextRequest) -> Int

    /// Estimate tokens for a message
    public func estimateMessage(_ message: AIMessage) -> Int

    /// Estimate tokens for text
    public func estimate(_ text: String) -> Int
}
```

---

## ProviderHealthMonitor

Tracks provider health metrics.

```swift
public actor ProviderHealthMonitor {
    /// Record a successful request latency
    public func recordLatency(_ latency: Duration, for providerId: String)

    /// Record an error
    public func recordError(for providerId: String)

    /// Get health metrics for a provider
    public func metrics(for providerId: String) -> ProviderMetrics?

    /// Get all provider metrics
    public var allMetrics: [String: ProviderMetrics]
}
```

---

## Error Types

### CircuitBreakerError

```swift
public enum CircuitBreakerError: Error, Sendable {
    case circuitOpen(until: ContinuousClock.Instant)
    case halfOpenLimitExceeded
    case rejected(reason: String)
}
```

### FailoverError

```swift
public enum FailoverError: Error, Sendable {
    case noProvidersAvailable
    case allProvidersFailed(lastError: String)
    case providerNotAllowed(provider: String)
    case circuitBreakerOpen(provider: String)
    case timeout(provider: String)
}
```

---

## Configuration Presets

| Preset | Failure Threshold | Recovery Timeout | Use Case |
|--------|------------------|------------------|----------|
| default | 5 | 30s | General use |
| aggressive | 3 | 15s | Critical paths |
| lenient | 10 | 60s | Unstable providers |

| Retry Preset | Max Retries | Initial Delay | Multiplier |
|--------------|-------------|---------------|------------|
| default | 3 | 1s | 2.0 |
| aggressive | 5 | 500ms | 1.5 |
| conservative | 2 | 2s | 3.0 |
| none | 0 | - | - |

## See Also

- [Providers](providers.md) - Provider implementations
- [Errors](errors.md) - Error handling
- [Core Protocols](core-protocols.md) - ProviderClient protocol
