//
//  RetryPolicy.swift
//  AISDK
//
//  Configurable retry policy with exponential backoff and jitter for provider resilience.
//  Designed to integrate with AdaptiveCircuitBreaker for comprehensive reliability.
//

import Foundation

// MARK: - RetryableError Protocol

/// Protocol for errors that can indicate whether they should be retried.
public protocol RetryableError: Error {
    /// Whether this error is retryable.
    var isRetryable: Bool { get }

    /// Suggested retry delay, if any.
    var suggestedRetryAfter: Duration? { get }
}

/// Default implementation for standard errors.
public extension RetryableError {
    var suggestedRetryAfter: Duration? { nil }
}

// MARK: - RetryPolicy

/// A configurable policy for retrying failed operations with exponential backoff and jitter.
///
/// ## Features
/// - Exponential backoff with configurable base and max delay
/// - Random jitter to prevent thundering herd
/// - Retryable error classification
/// - Integration with rate limit headers (retry-after)
///
/// ## Usage
/// ```swift
/// let policy = RetryPolicy.default
///
/// var attempt = 0
/// while policy.shouldRetry(error: error, attempt: attempt) {
///     try await Task.sleep(for: policy.delay(forAttempt: attempt))
///     attempt += 1
///     // retry operation
/// }
/// ```
public struct RetryPolicy: Sendable, Equatable {
    // MARK: - Properties

    /// Maximum number of retry attempts (0 = no retries, 1 = one retry, etc.).
    public let maxRetries: Int

    /// Base delay between retries (before exponential calculation).
    public let baseDelay: Duration

    /// Maximum delay cap regardless of exponential growth.
    public let maxDelay: Duration

    /// Jitter factor (0.0 = no jitter, 1.0 = up to 100% jitter).
    public let jitterFactor: Double

    /// Exponential base for backoff calculation (default: 2.0 for doubling).
    public let exponentialBase: Double

    /// Whether to respect retry-after headers from rate limit errors.
    public let respectRetryAfter: Bool

    /// Custom error classifier (optional override for default behavior).
    private let errorClassifier: @Sendable (Error) -> Bool

    // MARK: - Initialization

    /// Creates a new retry policy.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum retry attempts (default: 3)
    ///   - baseDelay: Base delay before exponential calculation (default: 1 second)
    ///   - maxDelay: Maximum delay cap (default: 30 seconds)
    ///   - jitterFactor: Random jitter factor 0.0-1.0 (default: 0.2)
    ///   - exponentialBase: Base for exponential backoff (default: 2.0)
    ///   - respectRetryAfter: Honor retry-after headers (default: true)
    ///   - errorClassifier: Custom function to determine if error is retryable
    public init(
        maxRetries: Int = 3,
        baseDelay: Duration = .seconds(1),
        maxDelay: Duration = .seconds(30),
        jitterFactor: Double = 0.2,
        exponentialBase: Double = 2.0,
        respectRetryAfter: Bool = true,
        errorClassifier: (@Sendable (Error) -> Bool)? = nil
    ) {
        self.maxRetries = max(0, maxRetries)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitterFactor = min(1.0, max(0.0, jitterFactor))
        self.exponentialBase = max(1.0, exponentialBase)
        self.respectRetryAfter = respectRetryAfter
        self.errorClassifier = errorClassifier ?? Self.defaultErrorClassifier
    }

    // MARK: - Preset Policies

    /// Default retry policy: 3 retries, 1s base, exponential backoff with 20% jitter.
    public static let `default` = RetryPolicy()

    /// No retries - fail immediately.
    public static let none = RetryPolicy(maxRetries: 0)

    /// Aggressive retry policy for critical operations.
    public static let aggressive = RetryPolicy(
        maxRetries: 5,
        baseDelay: .milliseconds(500),
        maxDelay: .seconds(60),
        jitterFactor: 0.3,
        exponentialBase: 2.0
    )

    /// Conservative retry policy for non-critical operations.
    public static let conservative = RetryPolicy(
        maxRetries: 2,
        baseDelay: .seconds(2),
        maxDelay: .seconds(10),
        jitterFactor: 0.1,
        exponentialBase: 1.5
    )

    /// Immediate retry policy (minimal delay, useful for testing).
    public static let immediate = RetryPolicy(
        maxRetries: 3,
        baseDelay: .milliseconds(10),
        maxDelay: .milliseconds(100),
        jitterFactor: 0.0,
        exponentialBase: 1.0
    )

    // MARK: - Public Methods

    /// Calculate the delay for a given retry attempt.
    ///
    /// Uses exponential backoff with optional jitter:
    /// `delay = min(baseDelay * (exponentialBase ^ attempt), maxDelay) * (1 + random_jitter)`
    ///
    /// - Parameter attempt: The attempt number (0 = first retry)
    /// - Returns: The delay duration before the next retry
    public func delay(forAttempt attempt: Int) -> Duration {
        guard attempt >= 0 else { return baseDelay }

        // Calculate exponential delay
        let multiplier = pow(exponentialBase, Double(attempt))
        let baseNanos = Double(baseDelay.components.seconds) * 1_000_000_000 +
                        Double(baseDelay.components.attoseconds) / 1_000_000_000
        var delayNanos = baseNanos * multiplier

        // Apply max delay cap
        let maxNanos = Double(maxDelay.components.seconds) * 1_000_000_000 +
                       Double(maxDelay.components.attoseconds) / 1_000_000_000
        delayNanos = min(delayNanos, maxNanos)

        // Apply jitter
        if jitterFactor > 0 {
            let jitter = Double.random(in: 0...jitterFactor)
            delayNanos *= (1 + jitter)
        }

        // Convert back to Duration
        let seconds = Int64(delayNanos / 1_000_000_000)
        let attoseconds = Int64((delayNanos.truncatingRemainder(dividingBy: 1_000_000_000)) * 1_000_000_000)
        return Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
    }

    /// Calculate the delay for a given error, respecting retry-after if applicable.
    ///
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - attempt: The attempt number
    /// - Returns: The delay duration before the next retry
    public func delay(for error: Error, attempt: Int) -> Duration {
        // Check for suggested retry-after from error
        if respectRetryAfter, let retryable = error as? RetryableError,
           let suggestedDelay = retryable.suggestedRetryAfter {
            return suggestedDelay
        }

        // Check for ProviderError rate limiting
        if respectRetryAfter, let providerError = error as? ProviderError {
            if case .rateLimited(let retryAfter) = providerError,
               let seconds = retryAfter {
                return .seconds(seconds)
            }
        }

        return delay(forAttempt: attempt)
    }

    /// Determine if an operation should be retried after an error.
    ///
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - attempt: The current attempt number (0 = first attempt, not a retry)
    /// - Returns: True if the operation should be retried
    public func shouldRetry(error: Error, attempt: Int) -> Bool {
        // Check attempt limit
        guard attempt < maxRetries else { return false }

        // Check if error is retryable
        return isRetryable(error)
    }

    /// Check if an error is retryable according to this policy.
    ///
    /// - Parameter error: The error to check
    /// - Returns: True if the error is considered retryable
    public func isRetryable(_ error: Error) -> Bool {
        // Check custom classifier first
        if errorClassifier(error) {
            return true
        }

        // Check RetryableError protocol
        if let retryable = error as? RetryableError {
            return retryable.isRetryable
        }

        return false
    }

    // MARK: - Error Classification

    /// Default error classifier for common error types.
    private static let defaultErrorClassifier: @Sendable (Error) -> Bool = { error in
        // ProviderError classification
        if let providerError = error as? ProviderError {
            switch providerError {
            case .rateLimited:
                return true
            case .timeout:
                return true
            case .serverError(let statusCode, _):
                // 5xx errors are generally retryable
                return (500...599).contains(statusCode)
            case .networkError:
                return true
            case .authenticationFailed, .invalidRequest, .modelNotFound,
                 .parseError, .contentFiltered, .providerSpecific, .unknown:
                return false
            }
        }

        // CircuitBreakerError classification
        if let cbError = error as? CircuitBreakerError {
            switch cbError {
            case .circuitOpen:
                // Should not retry when circuit is open
                return false
            case .halfOpenLimitExceeded:
                // Can retry after a delay
                return true
            case .rejected:
                return false
            }
        }

        // URLError classification
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        // NSError classification (for legacy errors)
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            // Network-related errors are generally retryable
            return true
        }

        return false
    }

    // MARK: - Equatable

    public static func == (lhs: RetryPolicy, rhs: RetryPolicy) -> Bool {
        lhs.maxRetries == rhs.maxRetries &&
        lhs.baseDelay == rhs.baseDelay &&
        lhs.maxDelay == rhs.maxDelay &&
        lhs.jitterFactor == rhs.jitterFactor &&
        lhs.exponentialBase == rhs.exponentialBase &&
        lhs.respectRetryAfter == rhs.respectRetryAfter
    }
}

// MARK: - RetryExecutor

/// Utility for executing operations with retry policy.
public struct RetryExecutor: Sendable {
    /// The retry policy to use.
    public let policy: RetryPolicy

    /// Optional circuit breaker to check before retrying.
    public let circuitBreaker: AdaptiveCircuitBreaker?

    /// Creates a new retry executor.
    ///
    /// - Parameters:
    ///   - policy: The retry policy
    ///   - circuitBreaker: Optional circuit breaker for integration
    public init(
        policy: RetryPolicy = .default,
        circuitBreaker: AdaptiveCircuitBreaker? = nil
    ) {
        self.policy = policy
        self.circuitBreaker = circuitBreaker
    }

    /// Execute an operation with automatic retries according to the policy.
    ///
    /// - Parameters:
    ///   - operation: The operation to execute
    ///   - onRetry: Optional callback for each retry attempt
    /// - Returns: The result of the operation
    /// - Throws: The last error if all retries are exhausted
    public func execute<T: Sendable>(
        _ operation: @Sendable () async throws -> T,
        onRetry: (@Sendable (Error, Int, Duration) async -> Void)? = nil
    ) async throws -> T {
        var attempt = 0

        while true {
            do {
                // Check circuit breaker if available
                if let breaker = circuitBreaker {
                    return try await breaker.execute(operation)
                } else {
                    return try await operation()
                }
            } catch {
                // Check if we should retry
                guard policy.shouldRetry(error: error, attempt: attempt) else {
                    throw error
                }

                // Check circuit breaker state (don't retry if circuit is open)
                if let breaker = circuitBreaker {
                    let isAvailable = await breaker.isAvailable
                    if !isAvailable {
                        throw error
                    }
                }

                // Calculate and apply delay
                let delay = policy.delay(for: error, attempt: attempt)

                // Notify retry callback
                await onRetry?(error, attempt, delay)

                // Wait before retry
                try await Task.sleep(for: delay)

                attempt += 1
            }
        }
    }
}

// MARK: - ProviderError RetryableError Conformance

extension ProviderError: RetryableError {
    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .timeout, .networkError:
            return true
        case .serverError(let statusCode, _):
            return (500...599).contains(statusCode)
        case .authenticationFailed, .invalidRequest, .modelNotFound,
             .parseError, .contentFiltered, .providerSpecific, .unknown:
            return false
        }
    }

    public var suggestedRetryAfter: Duration? {
        if case .rateLimited(let retryAfter) = self,
           let seconds = retryAfter {
            return .seconds(seconds)
        }
        return nil
    }
}

// MARK: - CircuitBreakerError RetryableError Conformance

extension CircuitBreakerError: RetryableError {
    public var isRetryable: Bool {
        switch self {
        case .circuitOpen:
            return false
        case .halfOpenLimitExceeded:
            return true
        case .rejected:
            return false
        }
    }
}
