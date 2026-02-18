# Phase 3: Reliability Layer

**Duration**: 2 weeks
**Tasks**: 7
**Dependencies**: Phase 2

---

## Goal

Implement 99.99% uptime with adaptive circuit breakers, capability-aware failover chains, and comprehensive health monitoring.

---

## Context Files (Read First)

```
docs/planning/external-review-feedback.md       # Reliability recommendations
docs/planning/interview-transcript.md           # 99.99% uptime requirement
Sources/AISDK/Errors/AISDKError.swift          # Current error types
```

---

## Tasks

### Task 3.1: AdaptiveCircuitBreaker

**Location**: `Sources/AISDK/Core/Reliability/AdaptiveCircuitBreaker.swift`
**Complexity**: 8/10
**Dependencies**: Phase 1

```swift
/// Adaptive circuit breaker with error-type awareness
public actor AdaptiveCircuitBreaker {
    public enum State: Sendable, Equatable {
        case closed
        case open(until: ContinuousClock.Instant)  // Monotonic time
        case halfOpen(successCount: Int, requiredSuccesses: Int)
    }

    public struct Configuration: Sendable {
        // Thresholds by error type
        public let authErrorThreshold: Int
        public let rateLimitThreshold: Int
        public let timeoutThreshold: Int
        public let genericErrorThreshold: Int

        // Time windows
        public let windowDuration: Duration
        public let openDuration: Duration
        public let halfOpenTestCount: Int

        // Backoff
        public let initialBackoff: Duration
        public let maxBackoff: Duration
        public let backoffMultiplier: Double
        public let jitterFactor: Double

        public static let `default` = Configuration(
            authErrorThreshold: 1,      // Immediate open
            rateLimitThreshold: 3,      // Quick open
            timeoutThreshold: 5,
            genericErrorThreshold: 5,
            windowDuration: .seconds(60),
            openDuration: .seconds(30),
            halfOpenTestCount: 3,
            initialBackoff: .seconds(1),
            maxBackoff: .seconds(60),
            backoffMultiplier: 2.0,
            jitterFactor: 0.1
        )
    }

    private var state: State = .closed
    private var failuresByType: [AIErrorType: Int] = [:]
    private var openCount: Int = 0
    private let config: Configuration
    private let clock: ContinuousClock

    public init(config: Configuration = .default) {
        self.config = config
        self.clock = ContinuousClock()
    }

    public func shouldAllow() -> Bool {
        switch state {
        case .closed:
            return true

        case .open(let until):
            if clock.now >= until {
                state = .halfOpen(successCount: 0, requiredSuccesses: config.halfOpenTestCount)
                return true
            }
            return false

        case .halfOpen:
            return true
        }
    }

    public func recordSuccess() {
        switch state {
        case .closed:
            // Decay failure counts
            failuresByType = failuresByType.mapValues { max(0, $0 - 1) }

        case .halfOpen(var successCount, let required):
            successCount += 1
            if successCount >= required {
                state = .closed
                failuresByType = [:]
                openCount = 0
            } else {
                state = .halfOpen(successCount: successCount, requiredSuccesses: required)
            }

        case .open:
            break
        }
    }

    public func recordFailure(error: AIError) {
        let errorType = error.errorType
        failuresByType[errorType, default: 0] += 1

        let threshold = threshold(for: errorType)
        if failuresByType[errorType, default: 0] >= threshold {
            openCount += 1
            let backoff = calculateBackoff()
            state = .open(until: clock.now.advanced(by: backoff))
        }
    }

    private func threshold(for errorType: AIErrorType) -> Int {
        switch errorType {
        case .authentication: return config.authErrorThreshold
        case .rateLimit: return config.rateLimitThreshold
        case .timeout: return config.timeoutThreshold
        default: return config.genericErrorThreshold
        }
    }

    private func calculateBackoff() -> Duration {
        let base = config.initialBackoff.components.seconds
        let exponential = base * pow(config.backoffMultiplier, Double(openCount - 1))
        let capped = min(exponential, config.maxBackoff.components.seconds)
        let jitter = capped * config.jitterFactor * Double.random(in: -1...1)
        return .seconds(capped + jitter)
    }
}
```

**Test-First**:
```
Tests/AISDKTests/Reliability/AdaptiveCircuitBreakerTests.swift
- test_opens_after_threshold
- test_auth_error_opens_immediately
- test_rate_limit_has_lower_threshold
- test_half_open_probing_works
- test_exponential_backoff_with_jitter
- test_success_decays_failures
- test_monotonic_time_not_wall_clock
```

---

### Task 3.2: RetryPolicy

**Location**: `Sources/AISDK/Core/Reliability/RetryPolicy.swift`
**Complexity**: 3/10
**Dependencies**: Task 3.1

```swift
public struct RetryPolicy: Sendable {
    public let maxRetries: Int
    public let initialDelay: Duration
    public let maxDelay: Duration
    public let jitterFactor: Double
    public let retryableErrors: Set<AIErrorType>

    public static let `default` = RetryPolicy(
        maxRetries: 3,
        initialDelay: .milliseconds(500),
        maxDelay: .seconds(10),
        jitterFactor: 0.2,
        retryableErrors: [.network, .timeout, .rateLimit]
    )

    public func shouldRetry(error: AIError, attempt: Int) -> (retry: Bool, delay: Duration?) {
        guard attempt < maxRetries,
              retryableErrors.contains(error.errorType) else {
            return (false, nil)
        }

        let delay = calculateDelay(attempt: attempt)
        return (true, delay)
    }
}
```

---

### Task 3.3: TimeoutPolicy

**Location**: `Sources/AISDK/Core/Reliability/TimeoutPolicy.swift`
**Complexity**: 4/10
**Dependencies**: None

```swift
public struct TimeoutPolicy: Sendable {
    public let connectionTimeout: Duration
    public let requestTimeout: Duration
    public let streamTimeout: Duration  // Time between chunks

    public static let `default` = TimeoutPolicy(
        connectionTimeout: .seconds(10),
        requestTimeout: .seconds(60),
        streamTimeout: .seconds(30)
    )
}
```

---

### Task 3.4: FailoverExecutor

**Location**: `Sources/AISDK/Core/Reliability/FailoverExecutor.swift`
**Complexity**: 8/10
**Dependencies**: Tasks 3.1-3.3, Task 3.6

```swift
/// Execute requests across fallback chain
public actor FailoverExecutor {
    private let chain: [any ProviderClient]
    private var circuitBreakers: [String: AdaptiveCircuitBreaker] = [:]
    private let failoverPolicy: FailoverPolicy
    private let observers: [any AISDKObserver]

    public init(
        chain: [any ProviderClient],
        failoverPolicy: FailoverPolicy = .default,
        observers: [any AISDKObserver] = []
    ) {
        self.chain = chain
        self.failoverPolicy = failoverPolicy
        self.observers = observers

        for provider in chain {
            circuitBreakers[provider.providerId] = AdaptiveCircuitBreaker()
        }
    }

    public func execute(
        request: AITextRequest,
        operation: @Sendable (any ProviderClient, AITextRequest) async throws -> AITextResult
    ) async throws -> ExecutionResult {
        var lastError: AIError?
        var attempts = 0

        for provider in chain {
            // Check PHI allowlist
            if let allowed = request.allowedProviders,
               !allowed.contains(provider.providerId) {
                continue
            }

            // Check circuit breaker
            guard let breaker = circuitBreakers[provider.providerId],
                  await breaker.shouldAllow() else {
                continue
            }

            // Check capability compatibility
            guard failoverPolicy.isCompatible(request: request, provider: provider) else {
                continue
            }

            attempts += 1

            do {
                let result = try await operation(provider, request)
                await breaker.recordSuccess()

                notifyProviderSelected(provider.providerId, reason: "success", context: request.traceContext)

                return ExecutionResult(
                    result: result,
                    provider: provider.providerId,
                    attempts: attempts
                )
            } catch let error as AIError {
                lastError = error
                await breaker.recordFailure(error: error)
                // Continue to next provider
            }
        }

        throw lastError ?? AIError.providerUnavailable(
            provider: "all",
            reason: "All providers in failover chain exhausted"
        )
    }

    private func notifyProviderSelected(_ provider: String, reason: String, context: AITraceContext?) {
        guard let context = context else { return }
        for observer in observers {
            observer.didSelectProvider(provider, reason: reason, context: context)
        }
    }
}

public struct ExecutionResult: Sendable {
    public let result: AITextResult
    public let provider: String
    public let attempts: Int
}
```

---

### Task 3.5: ProviderHealthMonitor

**Location**: `Sources/AISDK/Core/Reliability/ProviderHealthMonitor.swift`
**Complexity**: 6/10
**Dependencies**: Task 3.1

```swift
/// Proactive health monitoring
public actor ProviderHealthMonitor {
    public struct HealthStatus: Sendable {
        public let providerId: String
        public let isHealthy: Bool
        public let latencyP50: Duration
        public let latencyP99: Duration
        public let errorRate: Double
        public let lastChecked: Date
    }

    private var latencies: [String: [Duration]] = [:]
    private var errorCounts: [String: Int] = [:]
    private var requestCounts: [String: Int] = [:]

    public func recordLatency(_ duration: Duration, for providerId: String) {
        var providerLatencies = latencies[providerId, default: []]
        providerLatencies.append(duration)
        if providerLatencies.count > 1000 {
            providerLatencies.removeFirst(500)
        }
        latencies[providerId] = providerLatencies
        requestCounts[providerId, default: 0] += 1
    }

    public func recordError(for providerId: String) {
        errorCounts[providerId, default: 0] += 1
        requestCounts[providerId, default: 0] += 1
    }

    public func healthStatus(for providerId: String) -> HealthStatus {
        let providerLatencies = latencies[providerId, default: []]
        let sorted = providerLatencies.sorted()
        let p50 = sorted.isEmpty ? .zero : sorted[sorted.count / 2]
        let p99 = sorted.isEmpty ? .zero : sorted[Int(Double(sorted.count) * 0.99)]

        let errors = Double(errorCounts[providerId, default: 0])
        let total = Double(requestCounts[providerId, default: 1])
        let errorRate = errors / total

        return HealthStatus(
            providerId: providerId,
            isHealthy: errorRate < 0.1,
            latencyP50: p50,
            latencyP99: p99,
            errorRate: errorRate,
            lastChecked: Date()
        )
    }
}
```

---

### Task 3.6: CapabilityAwareFailover (NEW)

**Location**: `Sources/AISDK/Core/Reliability/CapabilityAwareFailover.swift`
**Complexity**: 4/10
**Dependencies**: Phase 1

```swift
/// Failover policy with capability and cost awareness
public struct FailoverPolicy: Sendable {
    public let maxCostMultiplier: Double
    public let requireCapabilityMatch: Bool
    public let tokenEstimator: TokenEstimator

    public static let `default` = FailoverPolicy(
        maxCostMultiplier: 5.0,  // Allow up to 5x cost increase
        requireCapabilityMatch: true,
        tokenEstimator: .default
    )

    public func isCompatible(request: AITextRequest, provider: any ProviderClient) -> Bool {
        // Check token limits
        let estimatedTokens = tokenEstimator.estimate(request)
        // Get max from provider capabilities
        // Return false if would exceed

        // Check cost tier (if original provider known)
        // Return false if exceeds maxCostMultiplier

        return true
    }
}

public struct TokenEstimator: Sendable {
    public static let `default` = TokenEstimator()

    public func estimate(_ request: AITextRequest) -> Int {
        // Simple estimation: ~4 chars per token
        request.messages.reduce(0) { count, message in
            count + (message.content?.count ?? 0) / 4
        }
    }
}
```

---

### Task 3.7: FaultInjector

**Location**: `Tests/AISDKTests/Helpers/FaultInjector.swift`
**Complexity**: 5/10
**Dependencies**: Tasks 3.1-3.4

```swift
/// Fault injection for reliability testing
public actor FaultInjector {
    public enum Fault: Sendable {
        case latency(Duration)
        case error(AIError)
        case timeout
        case rateLimited(retryAfter: Duration?)
        case partialResponse(afterTokens: Int)
        case connectionDrop
    }

    private var faults: [String: [Fault]] = [:]

    public func inject(_ fault: Fault, for providerId: String) {
        faults[providerId, default: []].append(fault)
    }

    public func nextFault(for providerId: String) -> Fault? {
        guard var providerFaults = faults[providerId],
              !providerFaults.isEmpty else {
            return nil
        }
        let fault = providerFaults.removeFirst()
        faults[providerId] = providerFaults
        return fault
    }

    public func clearAll() {
        faults = [:]
    }
}
```

---

## Verification

```bash
swift test --filter "Reliability"
```
