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
/// Use `AITraceContext.toLogDictionary()` for PHI-safe logging. Never log
/// raw text content, arguments, or error messages without proper redaction.
///
/// **Performance**: Observer methods are called synchronously on the request path.
/// Keep implementations fast (<1ms). Use async dispatch for heavy operations.
///
/// **Integration Note**: This protocol defines the observer interface. Wiring into
/// SDK request paths (generateText, streamText, etc.) is handled by the SDK's
/// internal orchestration layer, which calls these methods at appropriate lifecycle points.
///
/// Example:
/// ```swift
/// final class MetricsObserver: AISDKObserver {
///     func didStartRequest(_ context: AITraceContext) {
///         MetricsClient.shared.increment("ai.requests.started")
///     }
///
///     func didReceiveEvent(_ event: AIStreamEvent, context: AITraceContext) {
///         // Track event types for stream analysis (PHI-safe: only log type, not content)
///         MetricsClient.shared.increment("ai.stream.events",
///             tags: ["type": event.eventType])
///     }
///
///     func didCompleteTextRequest(_ result: AITextResult, context: AITraceContext) {
///         MetricsClient.shared.recordDuration(
///             "ai.requests.duration",
///             seconds: context.elapsed
///         )
///     }
///
///     func didFailRequest(_ error: AISDKErrorV2, context: AITraceContext) {
///         // PHI-safe: only log error code, not message
///         MetricsClient.shared.increment("ai.requests.failed",
///             tags: ["error_code": error.code.rawValue]
///         )
///     }
/// }
/// ```
public protocol AISDKObserver: Sendable {
    /// Called when a request begins
    ///
    /// This is called at the start of text and object generation operations.
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

    /// Called when a text generation request completes successfully
    ///
    /// For streaming operations, this is called after the stream finishes.
    /// The result contains the accumulated response data.
    ///
    /// - Parameters:
    ///   - result: The successful text result
    ///   - context: The trace context for this request
    func didCompleteTextRequest(_ result: AITextResult, context: AITraceContext)

    /// Called when an object generation request completes successfully
    ///
    /// The object is type-erased to `Any` for observer flexibility.
    /// Use this for metrics/logging; avoid type-specific processing.
    ///
    /// - Parameters:
    ///   - object: The generated object (type-erased)
    ///   - context: The trace context for this request
    func didCompleteObjectRequest(_ object: Any, context: AITraceContext)

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
    func didCompleteTextRequest(_ result: AITextResult, context: AITraceContext) {}
    func didCompleteObjectRequest(_ object: Any, context: AITraceContext) {}
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
/// **Note**: Duplicate observers are allowed. Use `remove(_:)` or `removeAll()`
/// to manage the observer list. Reference identity is used for removal.
///
/// Example:
/// ```swift
/// let composite = CompositeAISDKObserver()
/// composite.add(MetricsObserver())
/// composite.add(LoggingObserver())
/// // Register composite with SDK configuration
/// ```
public final class CompositeAISDKObserver: AISDKObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var observers: [any AISDKObserver] = []

    public init() {}

    /// Add an observer to the composite
    ///
    /// Duplicate observers are allowed. Each addition will receive events.
    ///
    /// - Parameter observer: The observer to add
    public func add(_ observer: any AISDKObserver) {
        lock.lock()
        defer { lock.unlock() }
        observers.append(observer)
    }

    /// Remove a specific observer by reference identity
    ///
    /// For class-based observers, removes the first matching instance.
    /// For struct observers, this may not work as expected due to value semantics.
    ///
    /// - Parameter observer: The observer to remove
    /// - Returns: True if an observer was removed
    @discardableResult
    public func remove(_ observer: any AISDKObserver) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let index = observers.firstIndex(where: { ($0 as AnyObject) === (observer as AnyObject) }) {
            observers.remove(at: index)
            return true
        }
        return false
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

    public func didCompleteTextRequest(_ result: AITextResult, context: AITraceContext) {
        let current = withLock { observers }
        for observer in current {
            observer.didCompleteTextRequest(result, context: context)
        }
    }

    public func didCompleteObjectRequest(_ object: Any, context: AITraceContext) {
        let current = withLock { observers }
        for observer in current {
            observer.didCompleteObjectRequest(object, context: context)
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

/// A PHI-safe logging observer for debugging
///
/// Logs observer events to the console with trace context.
/// **PHI Safety**: This observer only logs metadata (event types, IDs, counts).
/// It never logs text content, arguments, or error messages.
///
/// Useful for development and debugging, not recommended for production.
///
/// Example:
/// ```swift
/// #if DEBUG
/// let observer = LoggingAISDKObserver()
/// // Register with SDK configuration
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
        // PHI-safe: only log event type, never content
        print("\(prefix) Event: \(phiSafeEventDescription(event)) trace=\(context.traceId)")
    }

    public func didCompleteTextRequest(_ result: AITextResult, context: AITraceContext) {
        // PHI-safe: only log metadata, never text content
        print("\(prefix) Text request completed: trace=\(context.traceId) duration=\(String(format: "%.3f", context.elapsed))s tokens=\(result.usage.totalTokens)")
    }

    public func didCompleteObjectRequest(_ object: Any, context: AITraceContext) {
        // PHI-safe: only log type, never object content
        print("\(prefix) Object request completed: trace=\(context.traceId) duration=\(String(format: "%.3f", context.elapsed))s type=\(type(of: object))")
    }

    public func didFailRequest(_ error: AISDKErrorV2, context: AITraceContext) {
        // PHI-safe: only log error code, never message (may contain PHI)
        print("\(prefix) Request failed: trace=\(context.traceId) error_code=\(error.code.rawValue) duration=\(String(format: "%.3f", context.elapsed))s")
    }

    /// PHI-safe event description - only logs event type and metadata IDs, never content
    private func phiSafeEventDescription(_ event: AIStreamEvent) -> String {
        switch event {
        case .textDelta:
            return "textDelta"
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
        case .webSearchStarted:
            return "webSearchStarted"
        case .webSearchCompleted:
            return "webSearchCompleted"
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
        case .uiPatch(let batch):
            return "uiPatch(count=\(batch.patches.count))"
        case .computerUseAction(let action):
            return "computerUseAction(id=\(action.id))"
        case .error:
            // PHI-safe: don't log error description
            return "error"
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

// MARK: - AIStreamEvent Extension

extension AIStreamEvent {
    /// PHI-safe event type string for logging/metrics
    public var eventType: String {
        switch self {
        case .textDelta: return "textDelta"
        case .textCompletion: return "textCompletion"
        case .reasoningStart: return "reasoningStart"
        case .reasoningDelta: return "reasoningDelta"
        case .reasoningFinish: return "reasoningFinish"
        case .toolCallStart: return "toolCallStart"
        case .toolCallDelta: return "toolCallDelta"
        case .toolCall: return "toolCall"
        case .toolCallFinish: return "toolCallFinish"
        case .toolResult: return "toolResult"
        case .objectDelta: return "objectDelta"
        case .source: return "source"
        case .webSearchStarted: return "webSearchStarted"
        case .webSearchCompleted: return "webSearchCompleted"
        case .file: return "file"
        case .usage: return "usage"
        case .start: return "start"
        case .stepStart: return "stepStart"
        case .stepFinish: return "stepFinish"
        case .heartbeat: return "heartbeat"
        case .finish: return "finish"
        case .uiPatch: return "uiPatch"
        case .computerUseAction: return "computerUseAction"
        case .error: return "error"
        }
    }
}
