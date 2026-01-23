//
//  AITraceContext.swift
//  AISDK
//
//  Request tracing context for debugging and observability
//  Based on W3C Trace Context and OpenTelemetry patterns
//

import Foundation

/// Request tracing context for debugging and observability
///
/// AITraceContext provides distributed tracing capabilities following
/// W3C Trace Context semantics. Each request generates a unique trace ID,
/// and operations within that request create spans that can be linked
/// in parent-child relationships.
///
/// **PHI Safety**: Trace IDs are generated UUIDs, never derived from
/// user data, patient IDs, or other PII. Safe to include in logs.
///
/// Example:
/// ```swift
/// // Create a new trace for a request
/// let trace = AITraceContext()
///
/// // Create child span for a specific operation
/// let childTrace = trace.childSpan(operation: "tool_execution")
///
/// // Access trace info for logging
/// print("Trace: \(trace.traceId), Span: \(trace.spanId)")
/// ```
public struct AITraceContext: Sendable, Equatable, Hashable {
    /// Unique identifier for the entire trace (request chain)
    /// Format: 32 hex characters (128 bits) per W3C Trace Context
    public let traceId: String

    /// Unique identifier for this specific span (operation)
    /// Format: 16 hex characters (64 bits) per W3C Trace Context
    public let spanId: String

    /// Parent span ID if this is a child span
    public let parentSpanId: String?

    /// The operation name for this span
    public let operation: String?

    /// Timestamp when this span was created
    public let startTime: Date

    /// Additional baggage items for context propagation
    /// Note: Should only contain operational metadata, never PHI
    public let baggage: [String: String]

    /// Sampling decision for this trace
    public let sampled: Bool

    // MARK: - Initialization

    /// Create a new root trace context
    ///
    /// - Parameters:
    ///   - operation: Optional operation name for the root span
    ///   - sampled: Whether this trace should be sampled (default: true)
    ///   - baggage: Optional baggage items for context propagation
    public init(
        operation: String? = nil,
        sampled: Bool = true,
        baggage: [String: String] = [:]
    ) {
        self.traceId = Self.generateTraceId()
        self.spanId = Self.generateSpanId()
        self.parentSpanId = nil
        self.operation = operation
        self.startTime = Date()
        self.baggage = baggage
        self.sampled = sampled
    }

    /// Create a trace context with explicit IDs (for deserialization or testing)
    ///
    /// - Parameters:
    ///   - traceId: The trace ID (must be 32 hex characters)
    ///   - spanId: The span ID (must be 16 hex characters)
    ///   - parentSpanId: Optional parent span ID
    ///   - operation: Optional operation name
    ///   - startTime: Span start time
    ///   - sampled: Sampling decision
    ///   - baggage: Baggage items
    public init(
        traceId: String,
        spanId: String,
        parentSpanId: String? = nil,
        operation: String? = nil,
        startTime: Date = Date(),
        sampled: Bool = true,
        baggage: [String: String] = [:]
    ) {
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.operation = operation
        self.startTime = startTime
        self.sampled = sampled
        self.baggage = baggage
    }

    // MARK: - Child Span Creation

    /// Create a child span within this trace
    ///
    /// The child span inherits the trace ID and baggage from this context,
    /// with this span's ID becoming the parent span ID.
    ///
    /// - Parameter operation: Name of the operation for the child span
    /// - Returns: A new trace context for the child span
    public func childSpan(operation: String) -> AITraceContext {
        AITraceContext(
            traceId: traceId,
            spanId: Self.generateSpanId(),
            parentSpanId: spanId,
            operation: operation,
            startTime: Date(),
            sampled: sampled,
            baggage: baggage
        )
    }

    /// Create a child span with additional baggage
    ///
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - additionalBaggage: Additional baggage to merge (never include PHI)
    /// - Returns: A new trace context for the child span
    public func childSpan(
        operation: String,
        additionalBaggage: [String: String]
    ) -> AITraceContext {
        var mergedBaggage = baggage
        for (key, value) in additionalBaggage {
            mergedBaggage[key] = value
        }

        return AITraceContext(
            traceId: traceId,
            spanId: Self.generateSpanId(),
            parentSpanId: spanId,
            operation: operation,
            startTime: Date(),
            sampled: sampled,
            baggage: mergedBaggage
        )
    }

    // MARK: - W3C Trace Context Headers

    /// Generate W3C traceparent header value
    ///
    /// Format: `{version}-{trace-id}-{parent-id}-{flags}`
    /// Example: `00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`
    public var traceparent: String {
        let flags = sampled ? "01" : "00"
        return "00-\(traceId)-\(spanId)-\(flags)"
    }

    /// Generate W3C tracestate header value (baggage as key=value pairs)
    ///
    /// Note: Only includes safe operational data, never PHI
    public var tracestate: String? {
        guard !baggage.isEmpty else { return nil }
        return baggage.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// Parse a W3C traceparent header
    ///
    /// - Parameter traceparent: The traceparent header value
    /// - Returns: A trace context if parsing succeeds
    public static func from(traceparent: String) -> AITraceContext? {
        let parts = traceparent.split(separator: "-")
        guard parts.count == 4 else { return nil }

        let version = String(parts[0])
        let traceId = String(parts[1])
        let parentId = String(parts[2])
        let flags = String(parts[3])

        // Validate version
        guard version == "00" else { return nil }

        // Validate trace ID (32 hex chars)
        guard traceId.count == 32,
              traceId.allSatisfy({ $0.isHexDigit }) else { return nil }

        // Validate parent ID (16 hex chars)
        guard parentId.count == 16,
              parentId.allSatisfy({ $0.isHexDigit }) else { return nil }

        // Parse sampled flag
        let sampled = flags.hasSuffix("1")

        return AITraceContext(
            traceId: traceId,
            spanId: Self.generateSpanId(),
            parentSpanId: parentId,
            operation: nil,
            startTime: Date(),
            sampled: sampled,
            baggage: [:]
        )
    }

    // MARK: - ID Generation

    /// Generate a trace ID (32 hex characters, 128 bits)
    private static func generateTraceId() -> String {
        let uuid = UUID()
        return uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Generate a span ID (16 hex characters, 64 bits)
    private static func generateSpanId() -> String {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Utilities

    /// Whether this is a root span (no parent)
    public var isRoot: Bool {
        parentSpanId == nil
    }

    /// Elapsed time since span started
    public var elapsed: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    /// Create a dictionary for logging (PHI-safe)
    public func toLogDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "trace_id": traceId,
            "span_id": spanId,
            "sampled": sampled
        ]

        if let parentSpanId = parentSpanId {
            dict["parent_span_id"] = parentSpanId
        }

        if let operation = operation {
            dict["operation"] = operation
        }

        if !baggage.isEmpty {
            dict["baggage"] = baggage
        }

        return dict
    }
}

// MARK: - Codable

extension AITraceContext: Codable {
    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case spanId = "span_id"
        case parentSpanId = "parent_span_id"
        case operation
        case startTime = "start_time"
        case sampled
        case baggage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        traceId = try container.decode(String.self, forKey: .traceId)
        spanId = try container.decode(String.self, forKey: .spanId)
        parentSpanId = try container.decodeIfPresent(String.self, forKey: .parentSpanId)
        operation = try container.decodeIfPresent(String.self, forKey: .operation)
        startTime = try container.decodeIfPresent(Date.self, forKey: .startTime) ?? Date()
        sampled = try container.decodeIfPresent(Bool.self, forKey: .sampled) ?? true
        baggage = try container.decodeIfPresent([String: String].self, forKey: .baggage) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(traceId, forKey: .traceId)
        try container.encode(spanId, forKey: .spanId)
        try container.encodeIfPresent(parentSpanId, forKey: .parentSpanId)
        try container.encodeIfPresent(operation, forKey: .operation)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(sampled, forKey: .sampled)
        if !baggage.isEmpty {
            try container.encode(baggage, forKey: .baggage)
        }
    }
}

// MARK: - CustomStringConvertible

extension AITraceContext: CustomStringConvertible {
    public var description: String {
        var parts = ["trace=\(traceId)", "span=\(spanId)"]

        if let parentSpanId = parentSpanId {
            parts.append("parent=\(parentSpanId)")
        }

        if let operation = operation {
            parts.append("op=\(operation)")
        }

        if !sampled {
            parts.append("sampled=false")
        }

        return "AITraceContext(\(parts.joined(separator: ", ")))"
    }
}
