//
//  AITraceContextTests.swift
//  AISDKTests
//
//  Tests for AITraceContext distributed tracing
//

import XCTest
@testable import AISDK

final class AITraceContextTests: XCTestCase {

    // MARK: - Trace ID Generation

    func test_trace_id_generation() {
        let trace1 = AITraceContext()
        let trace2 = AITraceContext()

        // Trace IDs should be unique
        XCTAssertNotEqual(trace1.traceId, trace2.traceId)

        // Trace ID should be 32 hex characters
        XCTAssertEqual(trace1.traceId.count, 32)
        XCTAssertTrue(trace1.traceId.allSatisfy { $0.isHexDigit })
    }

    func test_span_id_generation() {
        let trace1 = AITraceContext()
        let trace2 = AITraceContext()

        // Span IDs should be unique
        XCTAssertNotEqual(trace1.spanId, trace2.spanId)

        // Span ID should be 16 hex characters
        XCTAssertEqual(trace1.spanId.count, 16)
        XCTAssertTrue(trace1.spanId.allSatisfy { $0.isHexDigit })
    }

    func test_root_trace_has_no_parent() {
        let trace = AITraceContext()

        XCTAssertNil(trace.parentSpanId)
        XCTAssertTrue(trace.isRoot)
    }

    // MARK: - Parent Span Linking

    func test_parent_span_linking() {
        let parent = AITraceContext(operation: "request")
        let child = parent.childSpan(operation: "tool_execution")

        // Child should have same trace ID
        XCTAssertEqual(child.traceId, parent.traceId)

        // Child should have parent's span ID as parentSpanId
        XCTAssertEqual(child.parentSpanId, parent.spanId)

        // Child should have different span ID
        XCTAssertNotEqual(child.spanId, parent.spanId)

        // Child should not be root
        XCTAssertFalse(child.isRoot)

        // Child should have the operation
        XCTAssertEqual(child.operation, "tool_execution")
    }

    func test_nested_child_spans() {
        let root = AITraceContext(operation: "request")
        let child1 = root.childSpan(operation: "llm_call")
        let child2 = child1.childSpan(operation: "stream_processing")

        // All should have same trace ID
        XCTAssertEqual(child1.traceId, root.traceId)
        XCTAssertEqual(child2.traceId, root.traceId)

        // Proper parent chain
        XCTAssertEqual(child1.parentSpanId, root.spanId)
        XCTAssertEqual(child2.parentSpanId, child1.spanId)

        // All different span IDs
        XCTAssertNotEqual(root.spanId, child1.spanId)
        XCTAssertNotEqual(child1.spanId, child2.spanId)
        XCTAssertNotEqual(root.spanId, child2.spanId)
    }

    // MARK: - Context Propagation

    func test_context_propagation_via_baggage() {
        let root = AITraceContext(
            operation: "request",
            baggage: ["request_type": "streaming"]
        )
        let child = root.childSpan(operation: "tool_execution")

        // Baggage should propagate to child
        XCTAssertEqual(child.baggage["request_type"], "streaming")
    }

    func test_child_span_with_additional_baggage() {
        let root = AITraceContext(baggage: ["key1": "value1"])
        let child = root.childSpan(
            operation: "tool",
            additionalBaggage: ["key2": "value2"]
        )

        // Both baggage items should be present
        XCTAssertEqual(child.baggage["key1"], "value1")
        XCTAssertEqual(child.baggage["key2"], "value2")
    }

    func test_additional_baggage_overwrites_existing() {
        let root = AITraceContext(baggage: ["key": "original"])
        let child = root.childSpan(
            operation: "tool",
            additionalBaggage: ["key": "overwritten"]
        )

        XCTAssertEqual(child.baggage["key"], "overwritten")
    }

    func test_sampling_propagates_to_children() {
        let sampledRoot = AITraceContext(sampled: true)
        let sampledChild = sampledRoot.childSpan(operation: "op")

        XCTAssertTrue(sampledChild.sampled)

        let unsampledRoot = AITraceContext(sampled: false)
        let unsampledChild = unsampledRoot.childSpan(operation: "op")

        XCTAssertFalse(unsampledChild.sampled)
    }

    // MARK: - W3C Trace Context

    func test_traceparent_format() {
        let trace = AITraceContext(sampled: true)
        let traceparent = trace.traceparent

        // Format: {version}-{trace-id}-{span-id}-{flags}
        let parts = traceparent.split(separator: "-")
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(String(parts[0]), "00")  // Version
        XCTAssertEqual(String(parts[1]), trace.traceId)
        XCTAssertEqual(String(parts[2]), trace.spanId)
        XCTAssertEqual(String(parts[3]), "01")  // Sampled flag
    }

    func test_traceparent_unsampled_flag() {
        let trace = AITraceContext(sampled: false)

        XCTAssertTrue(trace.traceparent.hasSuffix("-00"))
    }

    func test_tracestate_with_baggage() {
        let trace = AITraceContext(baggage: ["provider": "openai", "version": "1"])

        guard let tracestate = trace.tracestate else {
            XCTFail("tracestate should be present when baggage is set")
            return
        }

        // Should contain both key=value pairs
        XCTAssertTrue(tracestate.contains("provider=openai"))
        XCTAssertTrue(tracestate.contains("version=1"))
    }

    func test_tracestate_nil_when_no_baggage() {
        let trace = AITraceContext()

        XCTAssertNil(trace.tracestate)
    }

    func test_parse_traceparent() {
        let original = AITraceContext()
        let traceparent = original.traceparent

        guard let parsed = AITraceContext.from(traceparent: traceparent) else {
            XCTFail("Should parse valid traceparent")
            return
        }

        // Trace ID should match
        XCTAssertEqual(parsed.traceId, original.traceId)

        // Parent span ID should be the original's span ID
        XCTAssertEqual(parsed.parentSpanId, original.spanId)

        // Sampling should be preserved
        XCTAssertEqual(parsed.sampled, original.sampled)
    }

    func test_parse_traceparent_invalid_version() {
        let invalid = "99-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"

        XCTAssertNil(AITraceContext.from(traceparent: invalid))
    }

    func test_parse_traceparent_invalid_trace_id_length() {
        let invalid = "00-4bf92f3577b34da6-00f067aa0ba902b7-01"

        XCTAssertNil(AITraceContext.from(traceparent: invalid))
    }

    func test_parse_traceparent_invalid_format() {
        let invalid = "not-a-valid-traceparent"

        XCTAssertNil(AITraceContext.from(traceparent: invalid))
    }

    // MARK: - Codable

    func test_encoding_decoding_roundtrip() throws {
        let original = AITraceContext(
            operation: "test_operation",
            sampled: true,
            baggage: ["key": "value"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AITraceContext.self, from: data)

        XCTAssertEqual(decoded.traceId, original.traceId)
        XCTAssertEqual(decoded.spanId, original.spanId)
        XCTAssertEqual(decoded.parentSpanId, original.parentSpanId)
        XCTAssertEqual(decoded.operation, original.operation)
        XCTAssertEqual(decoded.sampled, original.sampled)
        XCTAssertEqual(decoded.baggage, original.baggage)
    }

    func test_decoding_with_missing_optional_fields() throws {
        let json = """
        {
            "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
            "span_id": "00f067aa0ba902b7"
        }
        """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AITraceContext.self, from: data)

        XCTAssertEqual(decoded.traceId, "4bf92f3577b34da6a3ce929d0e0e4736")
        XCTAssertEqual(decoded.spanId, "00f067aa0ba902b7")
        XCTAssertNil(decoded.parentSpanId)
        XCTAssertNil(decoded.operation)
        XCTAssertTrue(decoded.sampled)  // Default
        XCTAssertTrue(decoded.baggage.isEmpty)  // Default
    }

    func test_encoding_with_child_span() throws {
        let parent = AITraceContext(operation: "parent")
        let child = parent.childSpan(operation: "child")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(child)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AITraceContext.self, from: data)

        XCTAssertEqual(decoded.parentSpanId, parent.spanId)
        XCTAssertEqual(decoded.operation, "child")
    }

    // MARK: - Equatable / Hashable

    func test_equatable() {
        let trace1 = AITraceContext(
            traceId: "abc123",
            spanId: "def456",
            operation: "test"
        )

        let trace2 = AITraceContext(
            traceId: "abc123",
            spanId: "def456",
            operation: "test"
        )

        // Note: startTime will differ, so they won't be equal
        // This is intentional - each trace context is unique
        XCTAssertNotEqual(trace1, trace2)

        // Same instance should equal itself
        XCTAssertEqual(trace1, trace1)
    }

    func test_hashable() {
        let trace = AITraceContext()
        var set: Set<AITraceContext> = []

        set.insert(trace)
        XCTAssertTrue(set.contains(trace))
        XCTAssertEqual(set.count, 1)

        // Same trace inserted again shouldn't increase count
        set.insert(trace)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - Utilities

    func test_elapsed_time() throws {
        let trace = AITraceContext()

        // Wait a bit
        Thread.sleep(forTimeInterval: 0.01)

        XCTAssertGreaterThan(trace.elapsed, 0)
        XCTAssertLessThan(trace.elapsed, 1)  // Should be less than 1 second
    }

    func test_to_log_dictionary() {
        let trace = AITraceContext(
            traceId: "traceid123",
            spanId: "spanid456",
            parentSpanId: "parentid789",
            operation: "test_op",
            sampled: true,
            baggage: ["key": "value"]
        )

        let dict = trace.toLogDictionary()

        XCTAssertEqual(dict["trace_id"] as? String, "traceid123")
        XCTAssertEqual(dict["span_id"] as? String, "spanid456")
        XCTAssertEqual(dict["parent_span_id"] as? String, "parentid789")
        XCTAssertEqual(dict["operation"] as? String, "test_op")
        XCTAssertEqual(dict["sampled"] as? Bool, true)
        XCTAssertEqual(dict["baggage"] as? [String: String], ["key": "value"])
    }

    func test_description() {
        let root = AITraceContext(operation: "request")

        XCTAssertTrue(root.description.contains("AITraceContext"))
        XCTAssertTrue(root.description.contains("trace="))
        XCTAssertTrue(root.description.contains("span="))
        XCTAssertTrue(root.description.contains("op=request"))
    }

    func test_description_with_parent() {
        let parent = AITraceContext()
        let child = parent.childSpan(operation: "child_op")

        XCTAssertTrue(child.description.contains("parent="))
    }

    func test_description_with_unsampled() {
        let trace = AITraceContext(sampled: false)

        XCTAssertTrue(trace.description.contains("sampled=false"))
    }

    // MARK: - Sendable

    func test_sendable_across_actors() async {
        let trace = AITraceContext(operation: "test")

        actor TestActor {
            func process(_ context: AITraceContext) -> String {
                context.traceId
            }
        }

        let actor = TestActor()
        let traceId = await actor.process(trace)

        XCTAssertEqual(traceId, trace.traceId)
    }
}
