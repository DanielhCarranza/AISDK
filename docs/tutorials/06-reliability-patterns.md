# Reliability Patterns

> Building fault-tolerant AI applications with circuit breakers and failover

## Overview

Production AI applications need to handle failures gracefully. AISDK provides a comprehensive reliability layer including circuit breakers, retry policies, failover chains, and health monitoring.

## Circuit Breaker Pattern

The circuit breaker prevents cascading failures by stopping requests to failing providers.

### States

| State | Description | Behavior |
|-------|-------------|----------|
| **Closed** | Normal operation | Requests flow through, failures counted |
| **Open** | Provider failing | Requests immediately rejected |
| **Half-Open** | Testing recovery | Limited probe requests allowed |

### Basic Usage

```swift
import AISDK

let breaker = AdaptiveCircuitBreaker(configuration: .default)

do {
    let result = try await breaker.execute {
        try await provider.makeRequest()
    }
    print("Success: \(result)")
} catch CircuitBreakerError.circuitOpen(let until) {
    print("Circuit open until \(until), using fallback")
    // Use fallback provider
} catch {
    print("Request failed: \(error)")
}
```

### Configuration Presets

```swift
// Default: 5 failures, 30s recovery
let defaultBreaker = AdaptiveCircuitBreaker(configuration: .default)

// Aggressive: 3 failures, 15s recovery (critical paths)
let aggressiveBreaker = AdaptiveCircuitBreaker(configuration: .aggressive)

// Lenient: 10 failures, 60s recovery (unstable providers)
let lenientBreaker = AdaptiveCircuitBreaker(configuration: .lenient)
```

### Custom Configuration

```swift
let config = CircuitBreakerConfiguration(
    failureThreshold: 5,        // Failures before opening
    recoveryTimeout: .seconds(30), // Time before half-open
    successThreshold: 2,        // Successes to close from half-open
    halfOpenMaxProbes: 3,       // Probe limit in half-open
    slidingWindowSize: 20,      // Window for failure rate calc
    failureRateThreshold: 0.5   // 50% failure rate triggers open
)

let breaker = AdaptiveCircuitBreaker(configuration: config)
```

### Monitoring State Changes

```swift
class CircuitMonitor: CircuitBreakerDelegate {
    func circuitBreaker(
        _ breaker: AdaptiveCircuitBreaker,
        didTransitionFrom oldState: CircuitBreakerState,
        to newState: CircuitBreakerState
    ) async {
        print("Circuit changed: \(oldState) -> \(newState)")

        if case .open = newState {
            await alertTeam("Circuit opened for provider!")
        }
    }

    func circuitBreaker(
        _ breaker: AdaptiveCircuitBreaker,
        didRejectRequest error: CircuitBreakerError
    ) async {
        incrementMetric("circuit_breaker_rejections")
    }
}

let breaker = AdaptiveCircuitBreaker(
    configuration: .default,
    delegate: CircuitMonitor()
)
```

## Retry Policy

Handle transient failures with configurable retry logic.

```swift
let retryPolicy = RetryPolicy(
    maxAttempts: 3,
    baseDelay: .milliseconds(100),
    maxDelay: .seconds(5),
    backoffMultiplier: 2.0,
    jitter: true  // Add randomness to prevent thundering herd
)

let executor = RetryExecutor(policy: retryPolicy)

let result = try await executor.execute {
    try await provider.makeRequest()
}
```

### Retry Conditions

```swift
let policy = RetryPolicy(
    maxAttempts: 3,
    baseDelay: .milliseconds(100),
    retryableErrors: { error in
        // Only retry network and rate limit errors
        switch error {
        case ProviderError.networkError:
            return true
        case ProviderError.rateLimited:
            return true
        default:
            return false
        }
    }
)
```

## Timeout Policy

Prevent requests from hanging indefinitely:

```swift
let timeoutPolicy = TimeoutPolicy(
    requestTimeout: .seconds(30),   // Non-streaming requests
    streamTimeout: .seconds(120)    // Streaming requests
)

let executor = TimeoutExecutor(policy: timeoutPolicy)

do {
    let result = try await executor.execute {
        try await provider.makeRequest()
    }
} catch TimeoutError.timeout {
    print("Request timed out")
}
```

## Failover Chains

Automatically switch to backup providers when the primary fails.

### Basic Failover

```swift
let executor = FailoverExecutorBuilder()
    .with(providers: [
        openRouterClient,   // Primary
        anthropicClient,    // First fallback
        openAIClient        // Last resort
    ])
    .build()

let result = try await executor.executeRequest(
    request: aiRequest,
    modelId: "gpt-4"
)

print("Handled by: \(result.provider)")
print("Attempts: \(result.attempts)")
```

### With Health Monitoring

```swift
let healthMonitor = ProviderHealthMonitor()

let executor = FailoverExecutorBuilder()
    .with(providers: [openRouterClient, anthropicClient])
    .with(healthMonitor: healthMonitor)
    .with(configuration: FailoverExecutorConfiguration(
        retryPolicy: .default,
        timeoutPolicy: .default,
        failoverPolicy: .default,
        recordMetrics: true
    ))
    .build()

// Check health status
let status = await healthMonitor.healthStatus(for: "openrouter")
switch status {
case .healthy:
    print("Provider is healthy")
case .degraded:
    print("Provider experiencing issues")
case .unhealthy:
    print("Provider is down")
}
```

### Capability-Aware Failover

Only failover to providers that support required capabilities:

```swift
let policy = FailoverPolicy(
    maxCostMultiplier: 5.0,       // Max 5x cost increase
    requireCapabilityMatch: true, // Must match capabilities
    minimumContextWindow: 8000    // Require 8k context
)
    .withRequiredCapabilities([.vision, .tools])

let executor = FailoverExecutorBuilder()
    .with(providers: providers)
    .with(configuration: FailoverExecutorConfiguration(
        failoverPolicy: policy
    ))
    .build()
```

### PHI-Aware Failover

Restrict failover for sensitive data:

```swift
let request = AITextRequest(
    messages: [.user("Patient data...")],
    sensitivity: .phi,
    allowedProviders: ["hipaa-provider"]  // Only HIPAA-compliant
)

// Failover executor respects allowedProviders
let result = try await executor.executeRequest(
    request: request,
    modelId: "gpt-4"
)
```

## Health Monitoring

Track provider health over time:

```swift
let monitor = ProviderHealthMonitor()

// Record metrics
await monitor.recordLatency(.milliseconds(150), for: "openrouter")
await monitor.recordSuccess(for: "openrouter")
await monitor.recordError(for: "anthropic")

// Query status
let health = await monitor.healthStatus(for: "openrouter")
let latency = await monitor.averageLatency(for: "openrouter")

// Get all metrics
let allMetrics = await monitor.allProviderMetrics()
for (provider, metrics) in allMetrics {
    print("\(provider): \(metrics.successRate)% success, \(metrics.avgLatency)ms latency")
}
```

## Complete Example: Resilient AI Service

```swift
actor ResilientAIService {
    private let failoverExecutor: FailoverExecutor
    private let healthMonitor: ProviderHealthMonitor

    init() {
        let healthMonitor = ProviderHealthMonitor()
        self.healthMonitor = healthMonitor

        // Create providers
        let openRouter = OpenRouterClient(apiKey: "...")
        let anthropic = AnthropicClient(apiKey: "...")
        let openAI = OpenAIClient(apiKey: "...")

        // Build resilient executor
        self.failoverExecutor = FailoverExecutorBuilder()
            .with(providers: [openRouter, anthropic, openAI])
            .with(healthMonitor: healthMonitor)
            .with(configuration: FailoverExecutorConfiguration(
                retryPolicy: RetryPolicy(
                    maxAttempts: 3,
                    baseDelay: .milliseconds(100),
                    backoffMultiplier: 2.0
                ),
                timeoutPolicy: TimeoutPolicy(
                    requestTimeout: .seconds(30)
                ),
                failoverPolicy: FailoverPolicy(
                    maxCostMultiplier: 3.0,
                    requireCapabilityMatch: true
                )
            ))
            .with(circuitBreakerConfig: .default)
            .build()
    }

    func chat(message: String) async throws -> String {
        let request = AITextRequest(messages: [.user(message)])

        let result = try await failoverExecutor.executeRequest(
            request: request,
            modelId: "gpt-4"
        )

        // Log which provider handled it
        print("Request handled by \(result.provider) after \(result.attempts) attempt(s)")

        return result.result.content
    }

    func getHealthReport() async -> [String: ProviderHealthStatus] {
        var report: [String: ProviderHealthStatus] = [:]
        for providerId in failoverExecutor.providerIds {
            report[providerId] = await healthMonitor.healthStatus(for: providerId)
        }
        return report
    }
}
```

## Testing Reliability

Use fault injection to test failure scenarios:

```swift
let faultInjector = FaultInjector()

// Inject specific failures
faultInjector.injectError(
    ProviderError.rateLimited(retryAfter: 60),
    forProvider: "openrouter",
    probability: 0.5  // 50% of requests fail
)

// Test with injected faults
let result = try await faultInjector.execute(
    provider: openRouter
) {
    try await openRouter.execute(request: request)
}
```

## Best Practices

1. **Use circuit breakers** - Prevent cascading failures
2. **Configure retries carefully** - Too many retries can worsen outages
3. **Monitor health** - Track metrics for all providers
4. **Respect rate limits** - Use backoff and jitter
5. **Plan for partial failures** - Some requests may succeed even during outages
6. **Test failure scenarios** - Use fault injection in tests

## Next Steps

- [Testing Strategies](07-testing-strategies.md) - Verify reliability code
- [Architecture Overview](../AISDK-ARCHITECTURE.md#11-reliability-layer) - Deep dive
