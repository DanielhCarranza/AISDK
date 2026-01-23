//
//  AISDKObserverTests.swift
//  AISDKTests
//
//  Tests for AISDKObserver protocol and implementations
//

import XCTest
@testable import AISDK

final class AISDKObserverTests: XCTestCase {

    // MARK: - Protocol Conformance Tests

    func test_protocolIsSendable() {
        // Verify the protocol has Sendable requirement
        func acceptSendable<T: Sendable>(_: T.Type) {}
        acceptSendable((any AISDKObserver).self)
    }

    func test_defaultImplementations_doNothing() {
        // A minimal conforming type using default implementations
        struct MinimalObserver: AISDKObserver {}

        let observer = MinimalObserver()
        let context = AITraceContext()
        let result = AITextResult(text: "test")
        let error = AISDKErrorV2(code: .unknown, message: "test")
        let event = AIStreamEvent.textDelta("test")

        // These should not crash - they use default no-op implementations
        observer.didStartRequest(context)
        observer.didReceiveEvent(event, context: context)
        observer.didCompleteRequest(result, context: context)
        observer.didFailRequest(error, context: context)
    }

    // MARK: - CompositeAISDKObserver Tests

    func test_compositeObserver_broadcastsToAllChildren() {
        let composite = CompositeAISDKObserver()
        let recorder1 = RecordingObserver()
        let recorder2 = RecordingObserver()

        composite.add(recorder1)
        composite.add(recorder2)

        let context = AITraceContext()

        composite.didStartRequest(context)

        XCTAssertEqual(recorder1.startCount, 1)
        XCTAssertEqual(recorder2.startCount, 1)
    }

    func test_compositeObserver_broadcastsEvents() {
        let composite = CompositeAISDKObserver()
        let recorder = RecordingObserver()

        composite.add(recorder)

        let context = AITraceContext()
        let event = AIStreamEvent.textDelta("hello")

        composite.didReceiveEvent(event, context: context)

        XCTAssertEqual(recorder.eventCount, 1)
    }

    func test_compositeObserver_broadcastsCompletion() {
        let composite = CompositeAISDKObserver()
        let recorder = RecordingObserver()

        composite.add(recorder)

        let context = AITraceContext()
        let result = AITextResult(text: "done", usage: AIUsage(promptTokens: 10, completionTokens: 20))

        composite.didCompleteRequest(result, context: context)

        XCTAssertEqual(recorder.completeCount, 1)
        XCTAssertEqual(recorder.lastResult?.usage.totalTokens, 30)
    }

    func test_compositeObserver_broadcastsFailure() {
        let composite = CompositeAISDKObserver()
        let recorder = RecordingObserver()

        composite.add(recorder)

        let context = AITraceContext()
        let error = AISDKErrorV2(code: .timeout, message: "Request timed out")

        composite.didFailRequest(error, context: context)

        XCTAssertEqual(recorder.failCount, 1)
        XCTAssertEqual(recorder.lastError?.code, .timeout)
    }

    func test_compositeObserver_count() {
        let composite = CompositeAISDKObserver()

        XCTAssertEqual(composite.count, 0)

        composite.add(RecordingObserver())
        XCTAssertEqual(composite.count, 1)

        composite.add(RecordingObserver())
        XCTAssertEqual(composite.count, 2)
    }

    func test_compositeObserver_removeAll() {
        let composite = CompositeAISDKObserver()
        composite.add(RecordingObserver())
        composite.add(RecordingObserver())

        XCTAssertEqual(composite.count, 2)

        composite.removeAll()

        XCTAssertEqual(composite.count, 0)
    }

    func test_compositeObserver_threadSafety() async {
        let composite = CompositeAISDKObserver()
        let recorder = RecordingObserver()
        composite.add(recorder)

        let context = AITraceContext()

        // Fire many concurrent requests
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    composite.didStartRequest(context)
                }
            }
        }

        XCTAssertEqual(recorder.startCount, 100)
    }

    // MARK: - LoggingAISDKObserver Tests

    func test_loggingObserver_defaultPrefix() {
        let observer = LoggingAISDKObserver()
        // Just verify it can be created with defaults
        XCTAssertNotNil(observer)
    }

    func test_loggingObserver_customPrefix() {
        let observer = LoggingAISDKObserver(prefix: "[Custom]")
        XCTAssertNotNil(observer)
    }

    func test_loggingObserver_logEventsFlag() {
        let observer = LoggingAISDKObserver(logEvents: true)
        XCTAssertNotNil(observer)
    }

    func test_loggingObserver_isSendable() {
        // Verify LoggingAISDKObserver is Sendable
        func acceptSendable<T: Sendable>(_: T) {}
        let observer = LoggingAISDKObserver()
        acceptSendable(observer)
    }

    // MARK: - NoOpAISDKObserver Tests

    func test_noOpObserver_doesNothing() {
        let observer = NoOpAISDKObserver()
        let context = AITraceContext()

        // These should complete without issue
        observer.didStartRequest(context)
        observer.didReceiveEvent(.textDelta("test"), context: context)
        observer.didCompleteRequest(AITextResult(text: "test"), context: context)
        observer.didFailRequest(AISDKErrorV2(code: .unknown, message: "test"), context: context)
    }

    func test_noOpObserver_isSendable() {
        func acceptSendable<T: Sendable>(_: T) {}
        let observer = NoOpAISDKObserver()
        acceptSendable(observer)
    }

    // MARK: - Observer Lifecycle Integration Tests

    func test_observerReceivesFullLifecycle() {
        let recorder = RecordingObserver()
        let context = AITraceContext(operation: "test_request")

        // Simulate full request lifecycle
        recorder.didStartRequest(context)
        recorder.didReceiveEvent(.start(metadata: nil), context: context)
        recorder.didReceiveEvent(.textDelta("Hello"), context: context)
        recorder.didReceiveEvent(.textDelta(" World"), context: context)
        recorder.didReceiveEvent(.finish(finishReason: .stop, usage: .zero), context: context)
        recorder.didCompleteRequest(AITextResult(text: "Hello World"), context: context)

        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.eventCount, 4)
        XCTAssertEqual(recorder.completeCount, 1)
        XCTAssertEqual(recorder.failCount, 0)
    }

    func test_observerReceivesFailureLifecycle() {
        let recorder = RecordingObserver()
        let context = AITraceContext(operation: "failing_request")

        // Simulate failing request lifecycle
        recorder.didStartRequest(context)
        recorder.didReceiveEvent(.start(metadata: nil), context: context)
        recorder.didReceiveEvent(.textDelta("Partial"), context: context)
        recorder.didReceiveEvent(.error(NSError(domain: "test", code: 500)), context: context)
        recorder.didFailRequest(AISDKErrorV2(code: .streamInterrupted, message: "Connection lost"), context: context)

        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.eventCount, 3)
        XCTAssertEqual(recorder.completeCount, 0)
        XCTAssertEqual(recorder.failCount, 1)
    }

    // MARK: - Context Propagation Tests

    func test_observerReceivesCorrectTraceContext() {
        let recorder = RecordingObserver()
        let context = AITraceContext(operation: "my_operation", sampled: true, baggage: ["env": "test"])

        recorder.didStartRequest(context)

        XCTAssertEqual(recorder.lastContext?.operation, "my_operation")
        XCTAssertEqual(recorder.lastContext?.sampled, true)
        XCTAssertEqual(recorder.lastContext?.baggage["env"], "test")
    }

    func test_observerReceivesChildSpanContext() {
        let recorder = RecordingObserver()
        let parentContext = AITraceContext(operation: "parent")
        let childContext = parentContext.childSpan(operation: "child")

        recorder.didStartRequest(childContext)

        XCTAssertEqual(recorder.lastContext?.traceId, parentContext.traceId)
        XCTAssertEqual(recorder.lastContext?.parentSpanId, parentContext.spanId)
        XCTAssertEqual(recorder.lastContext?.operation, "child")
    }
}

// MARK: - Test Helpers

/// A recording observer for testing
private final class RecordingObserver: AISDKObserver, @unchecked Sendable {
    private let lock = NSLock()

    private var _startCount = 0
    private var _eventCount = 0
    private var _completeCount = 0
    private var _failCount = 0
    private var _lastContext: AITraceContext?
    private var _lastResult: AITextResult?
    private var _lastError: AISDKErrorV2?
    private var _events: [AIStreamEvent] = []

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _startCount
    }

    var eventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _eventCount
    }

    var completeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _completeCount
    }

    var failCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _failCount
    }

    var lastContext: AITraceContext? {
        lock.lock()
        defer { lock.unlock() }
        return _lastContext
    }

    var lastResult: AITextResult? {
        lock.lock()
        defer { lock.unlock() }
        return _lastResult
    }

    var lastError: AISDKErrorV2? {
        lock.lock()
        defer { lock.unlock() }
        return _lastError
    }

    var events: [AIStreamEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    func didStartRequest(_ context: AITraceContext) {
        lock.lock()
        defer { lock.unlock() }
        _startCount += 1
        _lastContext = context
    }

    func didReceiveEvent(_ event: AIStreamEvent, context: AITraceContext) {
        lock.lock()
        defer { lock.unlock() }
        _eventCount += 1
        _events.append(event)
        _lastContext = context
    }

    func didCompleteRequest(_ result: AITextResult, context: AITraceContext) {
        lock.lock()
        defer { lock.unlock() }
        _completeCount += 1
        _lastResult = result
        _lastContext = context
    }

    func didFailRequest(_ error: AISDKErrorV2, context: AITraceContext) {
        lock.lock()
        defer { lock.unlock() }
        _failCount += 1
        _lastError = error
        _lastContext = context
    }
}
