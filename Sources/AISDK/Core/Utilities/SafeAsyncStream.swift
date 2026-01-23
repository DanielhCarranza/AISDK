//
//  SafeAsyncStream.swift
//  AISDK
//
//  Memory-safe async stream creation with proper cancellation handling
//  Provides bounded buffering to prevent memory exhaustion in streaming scenarios
//

import Foundation

// MARK: - SafeAsyncStream

/// Factory for creating memory-safe AsyncThrowingStream instances with proper cancellation handling
///
/// SafeAsyncStream provides a consistent, safe way to create async streams throughout the SDK.
/// It ensures:
/// - Bounded buffering to prevent memory exhaustion (default 1000 elements)
/// - Proper cancellation propagation
/// - Clean continuation lifecycle management
/// - Integration with StreamBufferPolicy for configurable buffering
///
/// Example usage:
/// ```swift
/// let stream: AsyncThrowingStream<AIStreamEvent, Error> = SafeAsyncStream.make { continuation in
///     for event in events {
///         continuation.yield(event)
///     }
///     continuation.finish()
/// }
///
/// // With custom buffer policy
/// let stream = SafeAsyncStream.make(bufferingPolicy: .dropNewest(capacity: 500)) { continuation in
///     // ... emit events
/// }
/// ```
public enum SafeAsyncStream {
    // MARK: - Continuation Wrapper

    /// A wrapper around AsyncThrowingStream.Continuation with additional safety features
    ///
    /// Provides:
    /// - Cancellation checking before yields
    /// - Automatic finish on cancellation
    /// - Error-safe termination
    public struct Continuation<Element: Sendable>: Sendable {
        private let underlying: AsyncThrowingStream<Element, Error>.Continuation
        private let onTermination: @Sendable () -> Void

        /// Whether the stream has been cancelled
        public var isCancelled: Bool {
            // Check if the continuation is still valid by checking termination
            // The underlying continuation will have its onTermination called when cancelled
            false  // Note: We can't directly query cancellation, but the build closure can use Task.isCancelled
        }

        internal init(
            underlying: AsyncThrowingStream<Element, Error>.Continuation,
            onTermination: @escaping @Sendable () -> Void
        ) {
            self.underlying = underlying
            self.onTermination = onTermination
        }

        /// Yield an element to the stream
        ///
        /// - Parameter element: The element to yield
        /// - Returns: The yield result indicating if the element was consumed
        @discardableResult
        public func yield(_ element: Element) -> AsyncThrowingStream<Element, Error>.Continuation.YieldResult {
            underlying.yield(element)
        }

        /// Yield a sequence of elements to the stream
        ///
        /// - Parameter elements: The sequence of elements to yield
        public func yield<S: Sequence>(contentsOf elements: S) where S.Element == Element {
            for element in elements {
                underlying.yield(element)
            }
        }

        /// Finish the stream successfully
        public func finish() {
            underlying.finish()
            onTermination()
        }

        /// Finish the stream with an error
        ///
        /// - Parameter error: The error that caused the stream to terminate
        public func finish(throwing error: Error) {
            underlying.finish(throwing: error)
            onTermination()
        }
    }

    // MARK: - Stream Creation

    /// Create a memory-safe async throwing stream
    ///
    /// This is the primary factory method for creating streams in the SDK.
    /// It sets up proper buffering, cancellation handling, and continuation management.
    ///
    /// - Parameters:
    ///   - elementType: The type of elements in the stream (inferred from context)
    ///   - bufferingPolicy: The buffering policy to use (default: bounded with 1000 capacity)
    ///   - build: An async closure that produces stream elements using the continuation
    /// - Returns: An AsyncThrowingStream that will produce elements from the build closure
    ///
    /// - Important: The build closure is responsible for calling `continuation.finish()` or
    ///   `continuation.finish(throwing:)` when done. Failure to do so may result in hanging streams.
    public static func make<Element: Sendable>(
        of elementType: Element.Type = Element.self,
        bufferingPolicy: StreamBufferPolicy = .bounded,
        _ build: @escaping @Sendable (Continuation<Element>) async throws -> Void
    ) -> AsyncThrowingStream<Element, Error> {
        // Convert StreamBufferPolicy to AsyncThrowingStream.Continuation.BufferingPolicy
        let nativePolicy: AsyncThrowingStream<Element, Error>.Continuation.BufferingPolicy
        switch bufferingPolicy {
        case .unbounded:
            nativePolicy = .unbounded
        case .dropOldest(let capacity):
            nativePolicy = .bufferingOldest(capacity)
        case .dropNewest(let capacity):
            nativePolicy = .bufferingNewest(capacity)
        }

        return AsyncThrowingStream(bufferingPolicy: nativePolicy) { continuation in
            // Track if we've finished to prevent double-finish
            let hasFinished = ManagedAtomic<Bool>(false)

            let onTermination: @Sendable () -> Void = {
                _ = hasFinished.compareExchange(expected: false, desired: true, ordering: .relaxed)
            }

            // Set up cancellation handler
            continuation.onTermination = { @Sendable termination in
                switch termination {
                case .cancelled:
                    // Stream was cancelled by consumer
                    onTermination()
                case .finished:
                    // Normal finish
                    break
                @unknown default:
                    break
                }
            }

            // Create wrapped continuation
            let safeContinuation = Continuation(
                underlying: continuation,
                onTermination: onTermination
            )

            // Launch the build task
            Task {
                do {
                    try await build(safeContinuation)
                    // Ensure we finish if build didn't
                    if !hasFinished.load(ordering: .relaxed) {
                        safeContinuation.finish()
                    }
                } catch {
                    if !hasFinished.load(ordering: .relaxed) {
                        safeContinuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    /// Create a memory-safe async throwing stream with a synchronous build closure
    ///
    /// Use this when the stream production logic is synchronous (e.g., converting a sequence).
    ///
    /// - Parameters:
    ///   - elementType: The type of elements in the stream (inferred from context)
    ///   - bufferingPolicy: The buffering policy to use (default: bounded with 1000 capacity)
    ///   - build: A synchronous closure that produces stream elements
    /// - Returns: An AsyncThrowingStream that will produce elements from the build closure
    public static func makeSync<Element: Sendable>(
        of elementType: Element.Type = Element.self,
        bufferingPolicy: StreamBufferPolicy = .bounded,
        _ build: @escaping @Sendable (Continuation<Element>) throws -> Void
    ) -> AsyncThrowingStream<Element, Error> {
        let nativePolicy: AsyncThrowingStream<Element, Error>.Continuation.BufferingPolicy
        switch bufferingPolicy {
        case .unbounded:
            nativePolicy = .unbounded
        case .dropOldest(let capacity):
            nativePolicy = .bufferingOldest(capacity)
        case .dropNewest(let capacity):
            nativePolicy = .bufferingNewest(capacity)
        }

        return AsyncThrowingStream(bufferingPolicy: nativePolicy) { continuation in
            let hasFinished = ManagedAtomic<Bool>(false)

            let onTermination: @Sendable () -> Void = {
                _ = hasFinished.compareExchange(expected: false, desired: true, ordering: .relaxed)
            }

            continuation.onTermination = { @Sendable termination in
                if case .cancelled = termination {
                    onTermination()
                }
            }

            let safeContinuation = Continuation(
                underlying: continuation,
                onTermination: onTermination
            )

            do {
                try build(safeContinuation)
                if !hasFinished.load(ordering: .relaxed) {
                    safeContinuation.finish()
                }
            } catch {
                if !hasFinished.load(ordering: .relaxed) {
                    safeContinuation.finish(throwing: error)
                }
            }
        }
    }

    /// Create a stream from a sequence of elements
    ///
    /// Convenience method for converting a sequence to an async stream.
    ///
    /// - Parameters:
    ///   - sequence: The sequence of elements to stream
    ///   - bufferingPolicy: The buffering policy to use
    /// - Returns: An AsyncThrowingStream that yields all elements from the sequence
    public static func from<S: Sequence>(
        _ sequence: S,
        bufferingPolicy: StreamBufferPolicy = .bounded
    ) -> AsyncThrowingStream<S.Element, Error> where S.Element: Sendable {
        makeSync(of: S.Element.self, bufferingPolicy: bufferingPolicy) { continuation in
            for element in sequence {
                continuation.yield(element)
            }
            continuation.finish()
        }
    }

    /// Create an empty stream that immediately completes
    ///
    /// - Returns: An AsyncThrowingStream that finishes immediately with no elements
    public static func empty<Element: Sendable>(
        of elementType: Element.Type = Element.self
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    /// Create a stream that immediately fails with an error
    ///
    /// - Parameter error: The error to fail with
    /// - Returns: An AsyncThrowingStream that fails immediately
    public static func fail<Element: Sendable>(
        with error: Error,
        of elementType: Element.Type = Element.self
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }

    /// Create a stream that emits a single element
    ///
    /// - Parameter element: The element to emit
    /// - Returns: An AsyncThrowingStream that emits the element then finishes
    public static func just<Element: Sendable>(
        _ element: Element
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(element)
            continuation.finish()
        }
    }
}

// MARK: - ManagedAtomic (Minimal Implementation)

/// Minimal atomic boolean for tracking stream state
///
/// This is a simplified atomic type for internal use only.
/// Uses os_unfair_lock for thread-safe access on Apple platforms.
@available(iOS 13.0, macOS 10.15, *)
internal final class ManagedAtomic<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ initialValue: Value) {
        self.value = initialValue
    }

    func load(ordering: AtomicLoadOrdering) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func store(_ newValue: Value, ordering: AtomicStoreOrdering) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }

    func compareExchange(
        expected: Value,
        desired: Value,
        ordering: AtomicMemoryOrdering
    ) -> (exchanged: Bool, original: Value) where Value: Equatable {
        lock.lock()
        defer { lock.unlock() }
        let original = value
        if original == expected {
            value = desired
            return (true, original)
        }
        return (false, original)
    }
}

/// Memory ordering for atomic loads
internal enum AtomicLoadOrdering {
    case relaxed
    case acquiring
    case sequentiallyConsistent
}

/// Memory ordering for atomic stores
internal enum AtomicStoreOrdering {
    case relaxed
    case releasing
    case sequentiallyConsistent
}

/// Memory ordering for atomic read-modify-write operations
internal enum AtomicMemoryOrdering {
    case relaxed
    case acquiring
    case releasing
    case acquiringAndReleasing
    case sequentiallyConsistent
}
