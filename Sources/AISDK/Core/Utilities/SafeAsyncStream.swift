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
/// - Proper cancellation propagation (consumer cancellation cancels the producer task)
/// - Clean continuation lifecycle management with idempotent finish
/// - Integration with StreamBufferPolicy for configurable buffering
///
/// Example usage:
/// ```swift
/// let stream: AsyncThrowingStream<AIStreamEvent, Error> = SafeAsyncStream.make { continuation in
///     for event in events {
///         guard !continuation.isTerminated else { break }
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
    /// - `isTerminated` property to check if stream has ended
    /// - Idempotent finish (safe to call multiple times)
    /// - Thread-safe state tracking
    public struct Continuation<Element: Sendable>: Sendable {
        private let underlying: AsyncThrowingStream<Element, Error>.Continuation
        private let state: LockedState<ContinuationState>

        /// Whether the stream has been terminated (finished or cancelled)
        ///
        /// Check this before yielding elements in long-running producers to
        /// avoid unnecessary work after the consumer has stopped listening.
        public var isTerminated: Bool {
            state.withLock { $0.isTerminated }
        }

        internal init(
            underlying: AsyncThrowingStream<Element, Error>.Continuation,
            state: LockedState<ContinuationState>
        ) {
            self.underlying = underlying
            self.state = state
        }

        /// Yield an element to the stream
        ///
        /// - Parameter element: The element to yield
        /// - Returns: The yield result indicating if the element was consumed
        @discardableResult
        public func yield(_ element: Element) -> AsyncThrowingStream<Element, Error>.Continuation.YieldResult {
            // Check if already terminated
            if state.withLock({ $0.isTerminated }) {
                return .terminated
            }
            return underlying.yield(element)
        }

        /// Yield a sequence of elements to the stream
        ///
        /// Stops yielding if the stream is terminated.
        ///
        /// - Parameter elements: The sequence of elements to yield
        public func yield<S: Sequence>(contentsOf elements: S) where S.Element == Element {
            for element in elements {
                if state.withLock({ $0.isTerminated }) {
                    break
                }
                underlying.yield(element)
            }
        }

        /// Finish the stream successfully
        ///
        /// This method is idempotent - calling it multiple times has no effect
        /// after the first call.
        public func finish() {
            let shouldFinish = state.withLock { state -> Bool in
                if state.isTerminated { return false }
                state.isTerminated = true
                return true
            }
            if shouldFinish {
                underlying.finish()
            }
        }

        /// Finish the stream with an error
        ///
        /// This method is idempotent - calling it multiple times has no effect
        /// after the first call.
        ///
        /// - Parameter error: The error that caused the stream to terminate
        public func finish(throwing error: Error) {
            let shouldFinish = state.withLock { state -> Bool in
                if state.isTerminated { return false }
                state.isTerminated = true
                return true
            }
            if shouldFinish {
                underlying.finish(throwing: error)
            }
        }
    }

    // MARK: - Stream Creation

    /// Create a memory-safe async throwing stream
    ///
    /// This is the primary factory method for creating streams in the SDK.
    /// It sets up proper buffering, cancellation handling, and continuation management.
    ///
    /// The producer task is automatically cancelled when the consumer cancels or
    /// stops iterating. Use `Task.isCancelled` or `continuation.isTerminated` in
    /// your build closure to check for cancellation.
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
        let nativePolicy: AsyncThrowingStream<Element, Error>.Continuation.BufferingPolicy = convertBufferPolicy(bufferingPolicy)

        // Shared state between producer and consumer
        let state = LockedState(ContinuationState())
        // Producer task reference for cancellation propagation
        let producerTask = LockedState<Task<Void, Never>?>(nil)

        return AsyncThrowingStream(bufferingPolicy: nativePolicy) { continuation in
            // Set up cancellation handler - cancels producer when consumer stops
            continuation.onTermination = { @Sendable termination in
                state.withLock { $0.isTerminated = true }

                // Cancel the producer task if consumer cancels
                if case .cancelled = termination {
                    producerTask.withLock { $0?.cancel() }
                }
            }

            // Create wrapped continuation
            let safeContinuation = Continuation(
                underlying: continuation,
                state: state
            )

            // Launch the producer task and store reference for cancellation
            let task = Task {
                // Use withTaskCancellationHandler to properly handle cancellation
                await withTaskCancellationHandler {
                    do {
                        try await build(safeContinuation)
                        // Ensure we finish if build didn't
                        safeContinuation.finish()
                    } catch {
                        safeContinuation.finish(throwing: error)
                    }
                } onCancel: {
                    // When task is cancelled, finish the stream
                    safeContinuation.finish()
                }
            }

            producerTask.withLock { $0 = task }
        }
    }

    /// Create a memory-safe async throwing stream with a synchronous build closure
    ///
    /// Use this when the stream production logic is synchronous (e.g., converting a sequence).
    /// Note: Since this is synchronous, cancellation propagation is not applicable.
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
        let nativePolicy: AsyncThrowingStream<Element, Error>.Continuation.BufferingPolicy = convertBufferPolicy(bufferingPolicy)

        return AsyncThrowingStream(bufferingPolicy: nativePolicy) { continuation in
            let state = LockedState(ContinuationState())

            continuation.onTermination = { @Sendable _ in
                state.withLock { $0.isTerminated = true }
            }

            let safeContinuation = Continuation(
                underlying: continuation,
                state: state
            )

            do {
                try build(safeContinuation)
                safeContinuation.finish()
            } catch {
                safeContinuation.finish(throwing: error)
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
                guard !continuation.isTerminated else { break }
                continuation.yield(element)
            }
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

    // MARK: - Private Helpers

    /// Convert StreamBufferPolicy to native AsyncThrowingStream buffering policy
    ///
    /// Validates capacity and falls back to default bounded policy for invalid values.
    private static func convertBufferPolicy<Element>(
        _ policy: StreamBufferPolicy
    ) -> AsyncThrowingStream<Element, Error>.Continuation.BufferingPolicy {
        switch policy {
        case .unbounded:
            return .unbounded
        case .dropOldest(let capacity):
            // Validate capacity - fall back to default if invalid
            guard capacity > 0 else {
                return .bufferingOldest(1000)
            }
            return .bufferingOldest(capacity)
        case .dropNewest(let capacity):
            // Validate capacity - fall back to default if invalid
            guard capacity > 0 else {
                return .bufferingNewest(1000)
            }
            return .bufferingNewest(capacity)
        }
    }
}

// MARK: - ContinuationState

/// Internal state for tracking stream termination
internal struct ContinuationState: Sendable {
    var isTerminated: Bool = false
}

// MARK: - LockedState

/// Thread-safe state wrapper using NSLock
///
/// Provides synchronized access to mutable state. This is a simple lock-based
/// implementation suitable for short critical sections.
@available(iOS 13.0, macOS 10.15, *)
internal final class LockedState<State>: @unchecked Sendable {
    private var state: State
    private let lock = NSLock()

    init(_ initialState: State) {
        self.state = initialState
    }

    /// Execute a closure with exclusive access to the state
    ///
    /// - Parameter body: A closure that can read and modify the state
    /// - Returns: The value returned by the closure
    func withLock<T>(_ body: (inout State) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
