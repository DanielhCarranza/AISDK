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
        observer.didCompleteTextRequest(result, context: context)
        observer.didCompleteObjectRequest("test object", context: context)
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

    func test_compositeObserver_broadcastsTextCompletion() {
        let composite = CompositeAISDKObserver()
        let recorder = RecordingObserver()

        composite.add(recorder)

        let context = AITraceContext()
        let result = AITextResult(text: "done", usage: AIUsage(promptTokens: 10, completionTokens: 20))

        composite.didCompleteTextRequest(result, context: context)

        XCTAssertEqual(recorder.completeTextCount, 1)
        XCTAssertEqual(recorder.lastTextResult?.usage.totalTokens, 30)
    }

    func test_compositeObserver_broadcastsObjectCompletion() {
        let composite = CompositeAISDKObserver()
        let recorder = RecordingObserver()

        composite.add(recorder)

        let context = AITraceContext()
        let object = ["key": "value"]

        composite.didCompleteObjectRequest(object, context: context)

        XCTAssertEqual(recorder.completeObjectCount, 1)
        XCTAssertNotNil(recorder.lastObject)
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

    func test_compositeObserver_removeSpecific() {
        let composite = CompositeAISDKObserver()
        let recorder1 = RecordingObserver()
        let recorder2 = RecordingObserver()

        composite.add(recorder1)
        composite.add(recorder2)
        XCTAssertEqual(composite.count, 2)

        let removed = composite.remove(recorder1)
        XCTAssertTrue(removed)
        XCTAssertEqual(composite.count, 1)

        // Verify recorder2 still receives events
        composite.didStartRequest(AITraceContext())
        XCTAssertEqual(recorder1.startCount, 0)
        XCTAssertEqual(recorder2.startCount, 1)
    }

    func test_compositeObserver_removeNonExistent() {
        let composite = CompositeAISDKObserver()
        let recorder1 = RecordingObserver()
        let recorder2 = RecordingObserver()

        composite.add(recorder1)

        let removed = composite.remove(recorder2)
        XCTAssertFalse(removed)
        XCTAssertEqual(composite.count, 1)
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

    func test_compositeObserver_concurrentAddRemove() async {
        let composite = CompositeAISDKObserver()
        let context = AITraceContext()

        // Stress test concurrent add/remove while broadcasting
        await withTaskGroup(of: Void.self) { group in
            // Add observers
            for _ in 0..<50 {
                group.addTask {
                    let observer = RecordingObserver()
                    composite.add(observer)
                }
            }
            // Broadcast events
            for _ in 0..<50 {
                group.addTask {
                    composite.didStartRequest(context)
                }
            }
            // Remove all periodically
            for i in 0..<10 {
                group.addTask {
                    if i % 2 == 0 {
                        composite.removeAll()
                    }
                }
            }
        }

        // Should not crash - count may vary due to concurrent operations
        _ = composite.count
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
        observer.didCompleteTextRequest(AITextResult(text: "test"), context: context)
        observer.didCompleteObjectRequest("test", context: context)
        observer.didFailRequest(AISDKErrorV2(code: .unknown, message: "test"), context: context)
    }

    func test_noOpObserver_isSendable() {
        func acceptSendable<T: Sendable>(_: T) {}
        let observer = NoOpAISDKObserver()
        acceptSendable(observer)
    }

    // MARK: - AIStreamEvent Extension Tests

    func test_eventType_returnsCorrectStrings() {
        XCTAssertEqual(AIStreamEvent.textDelta("test").eventType, "textDelta")
        XCTAssertEqual(AIStreamEvent.textCompletion("test").eventType, "textCompletion")
        XCTAssertEqual(AIStreamEvent.reasoningStart.eventType, "reasoningStart")
        XCTAssertEqual(AIStreamEvent.toolCallStart(id: "1", name: "test").eventType, "toolCallStart")
        XCTAssertEqual(AIStreamEvent.finish(finishReason: .stop, usage: .zero).eventType, "finish")
        XCTAssertEqual(AIStreamEvent.error(NSError(domain: "test", code: 1)).eventType, "error")
    }

    // MARK: - Observer Lifecycle Tests

    func test_observerReceivesFullTextLifecycle() {
        let recorder = RecordingObserver()
        let context = AITraceContext(operation: "test_request")

        // Simulate full text request lifecycle
        recorder.didStartRequest(context)
        recorder.didReceiveEvent(.start(metadata: nil), context: context)
        recorder.didReceiveEvent(.textDelta("Hello"), context: context)
        recorder.didReceiveEvent(.textDelta(" World"), context: context)
        recorder.didReceiveEvent(.finish(finishReason: .stop, usage: .zero), context: context)
        recorder.didCompleteTextRequest(AITextResult(text: "Hello World"), context: context)

        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.eventCount, 4)
        XCTAssertEqual(recorder.completeTextCount, 1)
        XCTAssertEqual(recorder.completeObjectCount, 0)
        XCTAssertEqual(recorder.failCount, 0)
    }

    func test_observerReceivesFullObjectLifecycle() {
        let recorder = RecordingObserver()
        let context = AITraceContext(operation: "object_request")

        // Simulate full object request lifecycle
        recorder.didStartRequest(context)
        recorder.didReceiveEvent(.start(metadata: nil), context: context)
        recorder.didReceiveEvent(.objectDelta(Data()), context: context)
        recorder.didReceiveEvent(.finish(finishReason: .stop, usage: .zero), context: context)
        recorder.didCompleteObjectRequest(["result": "data"], context: context)

        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.eventCount, 3)
        XCTAssertEqual(recorder.completeTextCount, 0)
        XCTAssertEqual(recorder.completeObjectCount, 1)
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
        XCTAssertEqual(recorder.completeTextCount, 0)
        XCTAssertEqual(recorder.completeObjectCount, 0)
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
    private var _completeTextCount = 0
    private var _completeObjectCount = 0
    private var _failCount = 0
    private var _lastContext: AITraceContext?
    private var _lastTextResult: AITextResult?
    private var _lastObject: Any?
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

    var completeTextCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _completeTextCount
    }

    var completeObjectCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _completeObjectCount
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

    var lastTextResult: AITextResult? {
        lock.lock()
        defer { lock.unlock() }
        return _lastTextResult
    }

    var lastObject: Any? {
        lock.lock()
        defer { lock.unlock() }
        return _lastObject
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

    func didCompleteTextRequest(_ result: AITextResult, context: AITraceContext) {
        lock.lock()
        defer { lock.unlock() }
        _completeTextCount += 1
        _lastTextResult = result
        _lastContext = context
    }

    func didCompleteObjectRequest(_ object: Any, context: AITraceContext) {
        lock.lock()
        defer { lock.unlock() }
        _completeObjectCount += 1
        _lastObject = object
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
