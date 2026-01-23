//
//  AISDKObserver.swift
//  AISDK
//
//  Observer protocol for SDK telemetry and monitoring hooks
//  Enables instrumentation from day one without coupling to specific implementations
//

import Foundation

// MARK: - AISDKObserver Protocol

/// Observer protocol for receiving SDK lifecycle events
///
/// `AISDKObserver` provides a unified hook point for telemetry, logging,
/// metrics collection, and debugging. Observers receive notifications about
/// request lifecycle events without modifying SDK behavior.
///
/// **Thread Safety**: All methods are called from arbitrary threads. Implementations
/// must be thread-safe. Heavy processing should be dispatched to a background queue.
///
/// **PHI Safety**: Observers receive trace context and event data. Implementations
/// are responsible for PHI-safe handling when logging or transmitting data.
/// Use `AITraceContext.toLogDictionary()` for PHI-safe logging.
///
/// **Performance**: Observer methods are called synchronously on the request path.
/// Keep implementations fast (<1ms). Use async dispatch for heavy operations.
///
/// Example:
/// ```swift
/// final class MetricsObserver: AISDKObserver {
///     func didStartRequest(_ context: AITraceContext) {
///         MetricsClient.shared.increment("ai.requests.started")
///     }
///
///     func didReceiveEvent(_ event: AIStreamEvent, context: AITraceContext) {
///         // Track event types for stream analysis
///         if case .heartbeat = event {
///             MetricsClient.shared.increment("ai.stream.heartbeats")
///         }
///     }
///
///     func didCompleteRequest(_ result: AITextResult, context: AITraceContext) {
///         MetricsClient.shared.recordDuration(
///             "ai.requests.duration",
///             seconds: context.elapsed
///         )
///     }
///
///     func didFailRequest(_ error: AISDKErrorV2, context: AITraceContext) {
///         MetricsClient.shared.increment("ai.requests.failed",
///             tags: ["error_code": error.code.rawValue]
///         )
///     }
/// }
/// ```
public protocol AISDKObserver: Sendable {
    /// Called when a request begins
    ///
    /// This is called at the start of `generateText`, `streamText`,
    /// `generateObject`, and `streamObject` operations.
    ///
    /// - Parameter context: The trace context for this request
    func didStartRequest(_ context: AITraceContext)

    /// Called when a stream event is received
    ///
    /// For streaming operations, this is called for each event in the stream.
    /// For non-streaming operations, this is not called.
    ///
    /// - Parameters:
    ///   - event: The stream event received
    ///   - context: The trace context for this request
    func didReceiveEvent(_ event: AIStreamEvent, context: AITraceContext)

    /// Called when a request completes successfully
    ///
    /// For streaming operations, this is called after the stream finishes.
    /// The result contains the accumulated response data.
    ///
    /// - Parameters:
    ///   - result: The successful result
    ///   - context: The trace context for this request
    func didCompleteRequest(_ result: AITextResult, context: AITraceContext)

    /// Called when a request fails
    ///
    /// This is called when any error occurs during request processing,
    /// including stream errors, network failures, and provider errors.
    ///
    /// - Parameters:
    ///   - error: The error that occurred (uses AISDK 2.0 unified error type)
    ///   - context: The trace context for this request
    func didFailRequest(_ error: AISDKErrorV2, context: AITraceContext)
}

// MARK: - Default Implementations

/// Default no-op implementations for optional observer methods
///
/// Conforming types can override only the methods they care about.
public extension AISDKObserver {
    func didStartRequest(_ context: AITraceContext) {}
    func didReceiveEvent(_ event: AIStreamEvent, context: AITraceContext) {}
    func didCompleteRequest(_ result: AITextResult, context: AITraceContext) {}
    func didFailRequest(_ error: AISDKErrorV2, context: AITraceContext) {}
}

// MARK: - Composite Observer

/// An observer that broadcasts events to multiple child observers
///
/// Use `CompositeAISDKObserver` to combine multiple observers without
/// modifying the SDK's observer registration. Events are delivered
/// to all child observers in registration order.
///
/// **Thread Safety**: Child observers are accessed under a lock to support
/// concurrent registration while ensuring consistent delivery.
///
/// Example:
/// ```swift
/// let composite = CompositeAISDKObserver()
/// composite.add(MetricsObserver())
/// composite.add(LoggingObserver())
/// SDKConfiguration.shared.observer = composite
/// ```
public final class CompositeAISDKObserver: AISDKObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var observers: [any AISDKObserver] = []

    public init() {}

    /// Add an observer to the composite
    ///
    /// - Parameter observer: The observer to add
    public func add(_ observer: any AISDKObserver) {
        lock.lock()
        defer { lock.unlock() }
        observers.append(observer)
    }

    /// Remove all observers
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        observers.removeAll()
    }

    /// The number of registered observers
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return observers.count
    }

    // MARK: - AISDKObserver

    public func didStartRequest(_ context: AITraceContext) {
        let current = withLock { observers }
        for observer in current {
            observer.didStartRequest(context)
        }
    }

    public func didReceiveEvent(_ event: AIStreamEvent, context: AITraceContext) {
        let current = withLock { observers }
        for observer in current {
            observer.didReceiveEvent(event, context: context)
        }
    }

    public func didCompleteRequest(_ result: AITextResult, context: AITraceContext) {
        let current = withLock { observers }
        for observer in current {
            observer.didCompleteRequest(result, context: context)
        }
    }

    public func didFailRequest(_ error: AISDKErrorV2, context: AITraceContext) {
        let current = withLock { observers }
        for observer in current {
            observer.didFailRequest(error, context: context)
        }
    }

    private func withLock<T>(_ block: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return block()
    }
}

// MARK: - Logging Observer

/// A simple logging observer for debugging
///
/// Logs all observer events to the console with trace context.
/// Useful for development and debugging, not recommended for production.
///
/// Example:
/// ```swift
/// #if DEBUG
/// SDKConfiguration.shared.observer = LoggingAISDKObserver()
/// #endif
/// ```
public final class LoggingAISDKObserver: AISDKObserver {
    private let prefix: String
    private let logEvents: Bool

    /// Create a logging observer
    ///
    /// - Parameters:
    ///   - prefix: Prefix for log messages (default: "[AISDK]")
    ///   - logEvents: Whether to log stream events (default: false for performance)
    public init(prefix: String = "[AISDK]", logEvents: Bool = false) {
        self.prefix = prefix
        self.logEvents = logEvents
    }

    public func didStartRequest(_ context: AITraceContext) {
        print("\(prefix) Request started: trace=\(context.traceId) span=\(context.spanId)")
    }

    public func didReceiveEvent(_ event: AIStreamEvent, context: AITraceContext) {
        guard logEvents else { return }
        print("\(prefix) Event: \(eventDescription(event)) trace=\(context.traceId)")
    }

    public func didCompleteRequest(_ result: AITextResult, context: AITraceContext) {
        print("\(prefix) Request completed: trace=\(context.traceId) duration=\(String(format: "%.3f", context.elapsed))s tokens=\(result.usage.totalTokens)")
    }

    public func didFailRequest(_ error: AISDKErrorV2, context: AITraceContext) {
        print("\(prefix) Request failed: trace=\(context.traceId) error=\(error.code.rawValue) duration=\(String(format: "%.3f", context.elapsed))s")
    }

    private func eventDescription(_ event: AIStreamEvent) -> String {
        switch event {
        case .textDelta(let delta):
            return "textDelta(\(delta.prefix(20))...)"
        case .textCompletion:
            return "textCompletion"
        case .reasoningStart:
            return "reasoningStart"
        case .reasoningDelta:
            return "reasoningDelta"
        case .reasoningFinish:
            return "reasoningFinish"
        case .toolCallStart(let id, let name):
            return "toolCallStart(id=\(id), name=\(name))"
        case .toolCallDelta(let id, _):
            return "toolCallDelta(id=\(id))"
        case .toolCall(let id, let name, _):
            return "toolCall(id=\(id), name=\(name))"
        case .toolCallFinish(let id, let name, _):
            return "toolCallFinish(id=\(id), name=\(name))"
        case .toolResult(let id, _, _):
            return "toolResult(id=\(id))"
        case .objectDelta:
            return "objectDelta"
        case .source:
            return "source"
        case .file:
            return "file"
        case .usage(let usage):
            return "usage(total=\(usage.totalTokens))"
        case .start:
            return "start"
        case .stepStart(let index):
            return "stepStart(\(index))"
        case .stepFinish(let index, _):
            return "stepFinish(\(index))"
        case .heartbeat:
            return "heartbeat"
        case .finish(let reason, _):
            return "finish(\(reason.rawValue))"
        case .error(let error):
            return "error(\(error.localizedDescription))"
        }
    }
}

// MARK: - No-Op Observer

/// A no-op observer that does nothing
///
/// Use as a default when no observer is configured to avoid nil checks.
public struct NoOpAISDKObserver: AISDKObserver {
    public init() {}

    // All methods use default no-op implementations
}
