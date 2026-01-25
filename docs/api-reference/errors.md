# Errors

> Error types and handling in AISDK

## AISDKErrorV2

The unified error type with PHI-safe context.

```swift
public struct AISDKErrorV2: Error, Sendable {
    /// Error code
    public let code: AIErrorCode

    /// Human-readable message
    public let message: String

    /// Error context (PHI-redacted)
    public let context: AIErrorContext

    /// Underlying error (if any)
    public let underlyingError: Error?
}
```

### AIErrorCode

Comprehensive error classification:

```swift
public enum AIErrorCode: String, Sendable, Equatable {
    // Network errors
    case networkUnavailable
    case connectionFailed
    case timeout
    case sslError

    // Authentication errors
    case authenticationRequired
    case authenticationFailed
    case invalidAPIKey
    case accessDenied

    // Request errors
    case invalidRequest
    case invalidParameters
    case missingRequiredField
    case invalidJSON

    // Provider errors
    case providerUnavailable
    case providerError
    case modelNotFound
    case modelUnavailable

    // Rate limiting
    case rateLimited
    case quotaExceeded
    case concurrencyLimitExceeded

    // Content errors
    case contentFiltered
    case contextLengthExceeded
    case invalidContent

    // Tool errors
    case toolNotFound
    case toolExecutionFailed
    case toolTimeout
    case invalidToolArguments

    // Agent errors
    case agentMaxStepsExceeded
    case agentError

    // Parsing errors
    case parseError
    case decodingFailed
    case encodingFailed

    // Internal errors
    case internalError
    case configurationError
    case stateError

    // Unknown
    case unknown
}
```

### AIErrorContext

PHI-safe error context:

```swift
public struct AIErrorContext: Sendable {
    /// Provider ID (if applicable)
    public let providerId: String?

    /// Model ID (if applicable)
    public let modelId: String?

    /// Request ID (if applicable)
    public let requestId: String?

    /// Additional metadata (PHI-redacted)
    public let metadata: [String: String]

    /// Timestamp of the error
    public let timestamp: Date

    /// Data sensitivity level
    public let sensitivity: DataSensitivity
}
```

### Factory Methods

```swift
extension AISDKErrorV2 {
    /// Network error
    public static func network(
        _ message: String,
        providerId: String? = nil
    ) -> AISDKErrorV2

    /// Authentication error
    public static func authentication(
        _ message: String,
        providerId: String? = nil
    ) -> AISDKErrorV2

    /// Rate limit error
    public static func rateLimited(
        providerId: String,
        retryAfter: Duration? = nil
    ) -> AISDKErrorV2

    /// Tool error
    public static func toolError(
        tool: String,
        reason: String
    ) -> AISDKErrorV2

    /// Parse error
    public static func parse(
        _ message: String,
        context: [String: String] = [:]
    ) -> AISDKErrorV2
}
```

### Usage

```swift
do {
    let result = try await agent.execute(messages: messages)
} catch let error as AISDKErrorV2 {
    switch error.code {
    case .rateLimited:
        // Handle rate limiting
        if let retryAfter = error.context.metadata["retryAfter"] {
            print("Retry after \(retryAfter) seconds")
        }
    case .authenticationFailed:
        print("Check API key")
    case .toolExecutionFailed:
        print("Tool failed: \(error.message)")
    default:
        print("Error: \(error.message)")
    }
}
```

---

## ProviderError

Errors from provider operations.

```swift
public enum ProviderError: Error, Sendable {
    /// Authentication failed
    case authenticationFailed(String)

    /// Rate limit exceeded
    case rateLimited(retryAfter: TimeInterval?)

    /// Invalid request
    case invalidRequest(String)

    /// Model not found
    case modelNotFound(String)

    /// Server error
    case serverError(statusCode: Int, message: String)

    /// Network error
    case networkError(String)

    /// Request timeout
    case timeout(TimeInterval)

    /// Parse error
    case parseError(String)

    /// Unknown error
    case unknown(String)
}
```

### Converting to AISDKErrorV2

```swift
extension ProviderError {
    public var asAISDKError: AISDKErrorV2 {
        switch self {
        case .authenticationFailed(let message):
            return .authentication(message)
        case .rateLimited(let retryAfter):
            return .rateLimited(providerId: "unknown", retryAfter: retryAfter.map { .seconds($0) })
        case .timeout(let duration):
            return AISDKErrorV2(
                code: .timeout,
                message: "Request timed out after \(duration) seconds"
            )
        // ... other cases
        }
    }
}
```

---

## AIAgentError

Errors from agent operations.

```swift
public enum AIAgentError: Error, Sendable {
    /// Maximum steps exceeded
    case maxStepsExceeded(Int)

    /// Tool execution failed
    case toolExecutionFailed(tool: String, error: Error)

    /// Tool not found
    case toolNotFound(String)

    /// Invalid tool arguments
    case invalidToolArguments(tool: String, reason: String)

    /// Model error
    case modelError(Error)

    /// Operation cancelled
    case cancelled
}
```

---

## AIToolError

Errors from tool operations.

```swift
public enum AIToolError: Error, Sendable {
    /// Invalid arguments
    case invalidArguments(String)

    /// Execution timeout
    case timeout(Duration)

    /// Tool not found
    case notFound(String)

    /// Execution failed
    case executionFailed(Error)
}
```

---

## CircuitBreakerError

Errors from circuit breaker.

```swift
public enum CircuitBreakerError: Error, Sendable {
    /// Circuit is open
    case circuitOpen(until: ContinuousClock.Instant)

    /// Half-open limit exceeded
    case halfOpenLimitExceeded

    /// Request rejected
    case rejected(reason: String)
}
```

---

## FailoverError

Errors from failover operations.

```swift
public enum FailoverError: Error, Sendable {
    /// No providers available
    case noProvidersAvailable

    /// All providers failed
    case allProvidersFailed(lastError: String)

    /// Provider not allowed
    case providerNotAllowed(provider: String)

    /// Circuit breaker open
    case circuitBreakerOpen(provider: String)

    /// Timeout
    case timeout(provider: String)
}
```

---

## UITreeError

Errors from UI tree parsing.

```swift
public enum UITreeError: Error, Sendable {
    case invalidStructure(reason: String)
    case rootNotFound(key: String)
    case childNotFound(parentKey: String, childKey: String)
    case circularReference(key: String)
    case duplicateKey(key: String)
    case invalidNodeKey(key: String)
    case unknownComponentType(key: String, type: String)
    case childrenNotAllowed(key: String, type: String)
    case validationFailed(key: String, error: UIComponentValidationError)
    case multipleParents(key: String)
    case depthExceeded(maxAllowed: Int)
    case nodeCountExceeded(maxAllowed: Int)
    case unreachableNode(key: String)
}
```

---

## UIComponentValidationError

Errors from component validation.

```swift
public enum UIComponentValidationError: Error, Sendable {
    case missingRequiredProp(component: String, prop: String)
    case invalidPropValue(component: String, prop: String, reason: String)
    case unknownComponentType(String)
    case validationFailed(component: String, reason: String)
    case decodingFailed(component: String, reason: String)
    case unknownProp(component: String, prop: String)
    case unknownAction(component: String, action: String)
    case unknownValidator(component: String, validator: String)
    case invalidComponentTypeName(String)
    case duplicateComponentType(String)
}
```

---

## Error Handling Patterns

### Comprehensive Catch

```swift
do {
    let result = try await operation()
} catch let error as AISDKErrorV2 {
    handleAISDKError(error)
} catch let error as ProviderError {
    handleProviderError(error)
} catch let error as AIAgentError {
    handleAgentError(error)
} catch {
    handleUnknownError(error)
}
```

### Error Code Grouping

```swift
func handleError(_ error: AISDKErrorV2) {
    switch error.code {
    // Network issues - retry may help
    case .networkUnavailable, .connectionFailed, .timeout:
        scheduleRetry()

    // Auth issues - check credentials
    case .authenticationRequired, .authenticationFailed, .invalidAPIKey:
        promptReauthentication()

    // Rate limiting - back off
    case .rateLimited, .quotaExceeded:
        applyBackoff(error.context.metadata["retryAfter"])

    // User errors - show message
    case .invalidRequest, .invalidParameters:
        showUserError(error.message)

    // Internal errors - log and report
    default:
        logError(error)
        showGenericError()
    }
}
```

### PHI-Safe Logging

```swift
func logError(_ error: AISDKErrorV2) {
    // Context is already PHI-redacted
    logger.error("""
        Error: \(error.code.rawValue)
        Message: \(error.message)
        Provider: \(error.context.providerId ?? "unknown")
        Request: \(error.context.requestId ?? "unknown")
        """)
}
```

---

## LocalizedError Conformance

All error types conform to `LocalizedError`:

```swift
extension AISDKErrorV2: LocalizedError {
    public var errorDescription: String? {
        message
    }
}

extension ProviderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed(let msg):
            return "Authentication failed: \(msg)"
        case .rateLimited(let retryAfter):
            if let delay = retryAfter {
                return "Rate limited. Retry after \(delay) seconds"
            }
            return "Rate limited"
        // ... other cases
        }
    }
}
```

---

## Error Recovery Strategies

| Error Type | Strategy |
|------------|----------|
| Network/Timeout | Retry with backoff |
| Rate Limit | Wait for retry-after |
| Auth Failed | Re-authenticate |
| Model Not Found | Fallback to default |
| Tool Failed | Return error to LLM |
| Circuit Open | Use alternate provider |

## See Also

- [Core Protocols](core-protocols.md) - Protocol definitions
- [Providers](providers.md) - Provider error handling
- [Reliability](reliability.md) - Circuit breaker errors
