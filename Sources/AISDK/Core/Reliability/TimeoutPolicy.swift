//
//  TimeoutPolicy.swift
//  AISDK
//
//  Configurable timeout policy for controlling request, connection, and stream timeouts.
//

import Foundation

// MARK: - TimeoutPolicy

/// A configurable policy for controlling timeouts across different phases of a request.
///
/// ## Features
/// - Separate timeouts for connection, request, and streaming phases
/// - Per-operation timeout configuration
/// - Integration with URLSession and async/await timeout patterns
///
/// ## Usage
/// ```swift
/// let policy = TimeoutPolicy.default
///
/// // Use with URLSession configuration
/// let config = URLSessionConfiguration.default
/// config.timeoutIntervalForRequest = policy.requestTimeout.seconds
/// config.timeoutIntervalForResource = policy.connectionTimeout.seconds
///
/// // Use with async timeout
/// try await withThrowingTaskGroup(of: Data.self) { group in
///     group.addTask {
///         try await Task.sleep(for: policy.streamTimeout)
///         throw TimeoutError.streamTimedOut
///     }
///     group.addTask {
///         return try await fetchNextChunk()
///     }
///     // ...
/// }
/// ```
public struct TimeoutPolicy: Sendable, Equatable {
    // MARK: - Properties

    /// Timeout for establishing a connection to the server.
    public let connectionTimeout: Duration

    /// Timeout for the entire request (from start to response).
    public let requestTimeout: Duration

    /// Timeout between stream chunks (time to wait for next chunk).
    public let streamTimeout: Duration

    /// Timeout for individual operations (tool calls, etc.).
    public let operationTimeout: Duration

    // MARK: - Initialization

    /// Creates a new timeout policy.
    ///
    /// - Parameters:
    ///   - connectionTimeout: Max time to establish connection (default: 10 seconds)
    ///   - requestTimeout: Max time for entire request (default: 60 seconds)
    ///   - streamTimeout: Max time between stream chunks (default: 30 seconds)
    ///   - operationTimeout: Max time for individual operations (default: 120 seconds)
    public init(
        connectionTimeout: Duration = .seconds(10),
        requestTimeout: Duration = .seconds(60),
        streamTimeout: Duration = .seconds(30),
        operationTimeout: Duration = .seconds(120)
    ) {
        self.connectionTimeout = connectionTimeout
        self.requestTimeout = requestTimeout
        self.streamTimeout = streamTimeout
        self.operationTimeout = operationTimeout
    }

    // MARK: - Preset Policies

    /// Default timeout policy suitable for most use cases.
    public static let `default` = TimeoutPolicy()

    /// No timeouts - operations can run indefinitely.
    /// Use with caution as this can lead to hung operations.
    public static let none = TimeoutPolicy(
        connectionTimeout: .seconds(Int64.max / 2),
        requestTimeout: .seconds(Int64.max / 2),
        streamTimeout: .seconds(Int64.max / 2),
        operationTimeout: .seconds(Int64.max / 2)
    )

    /// Aggressive timeout policy for fast-fail scenarios.
    public static let aggressive = TimeoutPolicy(
        connectionTimeout: .seconds(5),
        requestTimeout: .seconds(30),
        streamTimeout: .seconds(10),
        operationTimeout: .seconds(60)
    )

    /// Lenient timeout policy for slow networks or complex operations.
    public static let lenient = TimeoutPolicy(
        connectionTimeout: .seconds(30),
        requestTimeout: .seconds(300),
        streamTimeout: .seconds(120),
        operationTimeout: .seconds(600)
    )

    /// Streaming-optimized policy with longer stream timeouts.
    public static let streaming = TimeoutPolicy(
        connectionTimeout: .seconds(10),
        requestTimeout: .seconds(300),
        streamTimeout: .seconds(60),
        operationTimeout: .seconds(300)
    )

    // MARK: - Convenience Methods

    /// Creates a copy with modified connection timeout.
    public func withConnectionTimeout(_ timeout: Duration) -> TimeoutPolicy {
        TimeoutPolicy(
            connectionTimeout: timeout,
            requestTimeout: requestTimeout,
            streamTimeout: streamTimeout,
            operationTimeout: operationTimeout
        )
    }

    /// Creates a copy with modified request timeout.
    public func withRequestTimeout(_ timeout: Duration) -> TimeoutPolicy {
        TimeoutPolicy(
            connectionTimeout: connectionTimeout,
            requestTimeout: timeout,
            streamTimeout: streamTimeout,
            operationTimeout: operationTimeout
        )
    }

    /// Creates a copy with modified stream timeout.
    public func withStreamTimeout(_ timeout: Duration) -> TimeoutPolicy {
        TimeoutPolicy(
            connectionTimeout: connectionTimeout,
            requestTimeout: requestTimeout,
            streamTimeout: timeout,
            operationTimeout: operationTimeout
        )
    }

    /// Creates a copy with modified operation timeout.
    public func withOperationTimeout(_ timeout: Duration) -> TimeoutPolicy {
        TimeoutPolicy(
            connectionTimeout: connectionTimeout,
            requestTimeout: requestTimeout,
            streamTimeout: streamTimeout,
            operationTimeout: timeout
        )
    }
}

// MARK: - TimeoutError

/// Errors that can occur due to timeout violations.
public enum TimeoutError: Error, Sendable, Equatable {
    /// Connection establishment timed out.
    case connectionTimedOut

    /// The entire request timed out.
    case requestTimedOut

    /// No stream chunks received within the timeout period.
    case streamTimedOut

    /// An individual operation timed out.
    case operationTimedOut(operation: String)
}

extension TimeoutError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .connectionTimedOut:
            return "Connection to server timed out"
        case .requestTimedOut:
            return "Request timed out"
        case .streamTimedOut:
            return "Stream timed out waiting for next chunk"
        case .operationTimedOut(let operation):
            return "Operation '\(operation)' timed out"
        }
    }
}

// MARK: - TimeoutExecutor

/// Utility for executing operations with timeout enforcement.
public struct TimeoutExecutor: Sendable {
    /// The timeout policy to use.
    public let policy: TimeoutPolicy

    /// Creates a new timeout executor.
    ///
    /// - Parameter policy: The timeout policy to use
    public init(policy: TimeoutPolicy = .default) {
        self.policy = policy
    }

    /// Execute an operation with the configured request timeout.
    ///
    /// - Parameters:
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Throws: TimeoutError.requestTimedOut if the operation exceeds the timeout
    public func execute<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(for: policy.requestTimeout)
                throw TimeoutError.requestTimedOut
            }

            guard let result = try await group.next() else {
                throw TimeoutError.requestTimedOut
            }
            group.cancelAll()
            return result
        }
    }

    /// Execute an operation with a custom timeout.
    ///
    /// - Parameters:
    ///   - timeout: The timeout duration
    ///   - operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Throws: TimeoutError.operationTimedOut if the operation exceeds the timeout
    public func execute<T: Sendable>(
        timeout: Duration,
        operationName: String = "unknown",
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimeoutError.operationTimedOut(operation: operationName)
            }

            guard let result = try await group.next() else {
                throw TimeoutError.operationTimedOut(operation: operationName)
            }
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Duration Extension

extension Duration {
    /// Returns the duration as a TimeInterval (seconds as Double).
    public var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1_000_000_000_000_000_000
    }

    /// Returns the duration as whole seconds (rounded down).
    public var seconds: Int64 {
        components.seconds
    }
}
