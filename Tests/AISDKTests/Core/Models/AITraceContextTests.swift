//
//  AITraceContextTests.swift
//  AISDKTests
//
//  Tests for AITraceContext distributed tracing
//

import XCTest
@testable import AISDK

final class AITraceContextTests: XCTestCase {

    // MARK: - Test Helper Constants

    /// Valid 32-char hex trace ID for testing
    private let validTraceId = "4bf92f3577b34da6a3ce929d0e0e4736"

    /// Valid 16-char hex span ID for testing
    private let validSpanId = "00f067aa0ba902b7"

    /// Another valid span ID for parent testing
    private let validParentSpanId = "b7ad6b7169203331"

    // MARK: - Trace ID Generation

    func test_trace_id_generation() {
        let trace1 = AITraceContext()
        let trace2 = AITraceContext()

        // Trace IDs should be unique
        XCTAssertNotEqual(trace1.traceId, trace2.traceId)

        // Trace ID should be 32 hex characters
        XCTAssertEqual(trace1.traceId.count, 32)
        XCTAssertTrue(trace1.traceId.allSatisfy { $0.isHexDigit })

        // Trace ID should be lowercase
        XCTAssertEqual(trace1.traceId, trace1.traceId.lowercased())
    }

    func test_span_id_generation() {
        let trace1 = AITraceContext()
        let trace2 = AITraceContext()

        // Span IDs should be unique
        XCTAssertNotEqual(trace1.spanId, trace2.spanId)

        // Span ID should be 16 hex characters
        XCTAssertEqual(trace1.spanId.count, 16)
        XCTAssertTrue(trace1.spanId.allSatisfy { $0.isHexDigit })

        // Span ID should be lowercase
        XCTAssertEqual(trace1.spanId, trace1.spanId.lowercased())
    }

    func test_span_id_not_all_zeros() {
        // Generate many span IDs and verify none are all-zeros
        for _ in 0..<100 {
            let trace = AITraceContext()
            XCTAssertNotEqual(trace.spanId, String(repeating: "0", count: 16))
        }
    }

    func test_root_trace_has_no_parent() {
        let trace = AITraceContext()

        XCTAssertNil(trace.parentSpanId)
        XCTAssertTrue(trace.isRoot)
    }

    // MARK: - Validated Factory

    func test_validated_factory_with_valid_ids() {
        let trace = AITraceContext.validated(
            traceId: validTraceId,
            spanId: validSpanId,
            operation: "test"
        )

        XCTAssertNotNil(trace)
        XCTAssertEqual(trace?.traceId, validTraceId)
        XCTAssertEqual(trace?.spanId, validSpanId)
    }

    func test_validated_factory_normalizes_to_lowercase() {
        let uppercase = AITraceContext.validated(
            traceId: validTraceId.uppercased(),
            spanId: validSpanId.uppercased()
        )

        XCTAssertNotNil(uppercase)
        XCTAssertEqual(uppercase?.traceId, validTraceId.lowercased())
        XCTAssertEqual(uppercase?.spanId, validSpanId.lowercased())
    }

    func test_validated_factory_rejects_invalid_trace_id_length() {
        let shortTraceId = AITraceContext.validated(
            traceId: "4bf92f3577b34da6",  // 16 chars instead of 32
            spanId: validSpanId
        )
        XCTAssertNil(shortTraceId)

        let longTraceId = AITraceContext.validated(
            traceId: validTraceId + "extra",
            spanId: validSpanId
        )
        XCTAssertNil(longTraceId)
    }

    func test_validated_factory_rejects_invalid_span_id_length() {
        let shortSpanId = AITraceContext.validated(
            traceId: validTraceId,
            spanId: "00f067aa"  // 8 chars instead of 16
        )
        XCTAssertNil(shortSpanId)
    }

    func test_validated_factory_rejects_non_hex_characters() {
        let nonHexTraceId = AITraceContext.validated(
            traceId: "4bf92f3577b34da6a3ce929d0e0e473g",  // 'g' is not hex
            spanId: validSpanId
        )
        XCTAssertNil(nonHexTraceId)

        let nonHexSpanId = AITraceContext.validated(
            traceId: validTraceId,
            spanId: "00f067aa0ba902bz"  // 'z' is not hex
        )
        XCTAssertNil(nonHexSpanId)
    }

    func test_validated_factory_rejects_all_zeros_trace_id() {
        let allZerosTraceId = AITraceContext.validated(
            traceId: String(repeating: "0", count: 32),
            spanId: validSpanId
        )
        XCTAssertNil(allZerosTraceId)
    }

    func test_validated_factory_rejects_all_zeros_span_id() {
        let allZerosSpanId = AITraceContext.validated(
            traceId: validTraceId,
            spanId: String(repeating: "0", count: 16)
        )
        XCTAssertNil(allZerosSpanId)
    }

    func test_validated_factory_validates_parent_span_id() {
        let invalidParent = AITraceContext.validated(
            traceId: validTraceId,
            spanId: validSpanId,
            parentSpanId: "invalid"
        )
        XCTAssertNil(invalidParent)

        let validParent = AITraceContext.validated(
            traceId: validTraceId,
            spanId: validSpanId,
            parentSpanId: validParentSpanId
        )
        XCTAssertNotNil(validParent)
        XCTAssertEqual(validParent?.parentSpanId, validParentSpanId)
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

    func test_parse_traceparent_sampled_flag_bit() {
        // Test that any odd flag value (low bit = 1) is treated as sampled
        let sampled01 = AITraceContext.from(traceparent: "00-\(validTraceId)-\(validSpanId)-01")
        XCTAssertTrue(sampled01?.sampled == true)

        let sampled03 = AITraceContext.from(traceparent: "00-\(validTraceId)-\(validSpanId)-03")
        XCTAssertTrue(sampled03?.sampled == true)

        let sampledFF = AITraceContext.from(traceparent: "00-\(validTraceId)-\(validSpanId)-ff")
        XCTAssertTrue(sampledFF?.sampled == true)

        // Even flag values (low bit = 0) are not sampled
        let unsampled00 = AITraceContext.from(traceparent: "00-\(validTraceId)-\(validSpanId)-00")
        XCTAssertTrue(unsampled00?.sampled == false)

        let unsampled02 = AITraceContext.from(traceparent: "00-\(validTraceId)-\(validSpanId)-02")
        XCTAssertTrue(unsampled02?.sampled == false)
    }

    func test_parse_traceparent_invalid_version() {
        let invalid = "99-\(validTraceId)-\(validSpanId)-01"
        XCTAssertNil(AITraceContext.from(traceparent: invalid))
    }

    func test_parse_traceparent_invalid_trace_id_length() {
        let invalid = "00-4bf92f3577b34da6-\(validSpanId)-01"
        XCTAssertNil(AITraceContext.from(traceparent: invalid))
    }

    func test_parse_traceparent_all_zeros_trace_id() {
        let allZerosTraceId = String(repeating: "0", count: 32)
        let invalid = "00-\(allZerosTraceId)-\(validSpanId)-01"
        XCTAssertNil(AITraceContext.from(traceparent: invalid))
    }

    func test_parse_traceparent_all_zeros_parent_id() {
        let allZerosParentId = String(repeating: "0", count: 16)
        let invalid = "00-\(validTraceId)-\(allZerosParentId)-01"
        XCTAssertNil(AITraceContext.from(traceparent: invalid))
    }

    func test_parse_traceparent_normalizes_to_lowercase() {
        let uppercase = "00-\(validTraceId.uppercased())-\(validSpanId.uppercased())-01"
        let parsed = AITraceContext.from(traceparent: uppercase)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.traceId, validTraceId.lowercased())
        XCTAssertEqual(parsed?.parentSpanId, validSpanId.lowercased())
    }

    func test_parse_traceparent_invalid_flags_length() {
        // Flags must be exactly 2 hex digits
        let oneDigit = "00-\(validTraceId)-\(validSpanId)-1"
        XCTAssertNil(AITraceContext.from(traceparent: oneDigit))

        let threeDigits = "00-\(validTraceId)-\(validSpanId)-001"
        XCTAssertNil(AITraceContext.from(traceparent: threeDigits))
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
            "trace_id": "\(validTraceId)",
            "span_id": "\(validSpanId)"
        }
        """

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AITraceContext.self, from: data)

        XCTAssertEqual(decoded.traceId, validTraceId)
        XCTAssertEqual(decoded.spanId, validSpanId)
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

    func test_equatable_with_explicit_start_times() {
        let time1 = Date(timeIntervalSince1970: 1000)
        let time2 = Date(timeIntervalSince1970: 1000)

        // Same values should be equal when using validated factory
        guard let trace1 = AITraceContext.validated(
            traceId: validTraceId,
            spanId: validSpanId,
            operation: "test",
            startTime: time1
        ),
        let trace2 = AITraceContext.validated(
            traceId: validTraceId,
            spanId: validSpanId,
            operation: "test",
            startTime: time2
        ) else {
            XCTFail("Should create valid traces")
            return
        }

        XCTAssertEqual(trace1, trace2)
    }

    func test_equatable_different_traces_not_equal() {
        let trace1 = AITraceContext()
        let trace2 = AITraceContext()

        // Different traces should not be equal
        XCTAssertNotEqual(trace1, trace2)
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

    func test_to_log_dictionary_excludes_baggage_by_default() {
        guard let trace = AITraceContext.validated(
            traceId: validTraceId,
            spanId: validSpanId,
            parentSpanId: validParentSpanId,
            operation: "test_op",
            sampled: true,
            baggage: ["key": "value"]
        ) else {
            XCTFail("Should create valid trace")
            return
        }

        let dict = trace.toLogDictionary()

        XCTAssertEqual(dict["trace_id"] as? String, validTraceId)
        XCTAssertEqual(dict["span_id"] as? String, validSpanId)
        XCTAssertEqual(dict["parent_span_id"] as? String, validParentSpanId)
        XCTAssertEqual(dict["operation"] as? String, "test_op")
        XCTAssertEqual(dict["sampled"] as? Bool, true)

        // Baggage should NOT be included by default (PHI safety)
        XCTAssertNil(dict["baggage"])
    }

    func test_to_log_dictionary_includes_baggage_when_requested() {
        guard let trace = AITraceContext.validated(
            traceId: validTraceId,
            spanId: validSpanId,
            baggage: ["key": "value"]
        ) else {
            XCTFail("Should create valid trace")
            return
        }

        let dict = trace.toLogDictionary(includeBaggage: true)

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
