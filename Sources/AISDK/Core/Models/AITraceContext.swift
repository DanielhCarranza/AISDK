//
//  AITraceContext.swift
//  AISDK
//
//  Request tracing context for debugging and observability
//  Based on W3C Trace Context specification
//

import Foundation
import Security

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
/// **Note on baggage**: The `baggage` property is for operational metadata only.
/// Callers must ensure baggage values do not contain PHI. Baggage is excluded
/// from `toLogDictionary()` by default for safety.
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
    /// Format: 32 lowercase hex characters (128 bits) per W3C Trace Context
    public let traceId: String

    /// Unique identifier for this specific span (operation)
    /// Format: 16 lowercase hex characters (64 bits) per W3C Trace Context
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

    // MARK: - Validation Constants

    /// All-zeros trace ID (invalid per W3C)
    private static let invalidTraceId = String(repeating: "0", count: 32)

    /// All-zeros span ID (invalid per W3C)
    private static let invalidSpanId = String(repeating: "0", count: 16)

    // MARK: - Initialization

    /// Create a new root trace context
    ///
    /// - Parameters:
    ///   - operation: Optional operation name for the root span
    ///   - sampled: Whether this trace should be sampled (default: true)
    ///   - baggage: Optional baggage items for context propagation (must not contain PHI)
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

    /// Create a trace context with explicit IDs (internal, for child spans and parsing)
    ///
    /// This initializer is internal to prevent construction of invalid W3C contexts.
    /// Use `init(operation:sampled:baggage:)` for new traces, `childSpan(operation:)`
    /// for child spans, or `from(traceparent:)` for parsing.
    internal init(
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

    /// Create a trace context with explicit IDs, with validation
    ///
    /// Returns nil if IDs are invalid (wrong length, not hex, all-zeros).
    ///
    /// - Parameters:
    ///   - traceId: The trace ID (must be 32 lowercase hex characters, not all-zeros)
    ///   - spanId: The span ID (must be 16 lowercase hex characters, not all-zeros)
    ///   - parentSpanId: Optional parent span ID (must be 16 hex chars if provided)
    ///   - operation: Optional operation name
    ///   - startTime: Span start time
    ///   - sampled: Sampling decision
    ///   - baggage: Baggage items (must not contain PHI)
    public static func validated(
        traceId: String,
        spanId: String,
        parentSpanId: String? = nil,
        operation: String? = nil,
        startTime: Date = Date(),
        sampled: Bool = true,
        baggage: [String: String] = [:]
    ) -> AITraceContext? {
        // Validate trace ID
        guard Self.isValidTraceId(traceId) else { return nil }

        // Validate span ID
        guard Self.isValidSpanId(spanId) else { return nil }

        // Validate parent span ID if provided
        if let parentSpanId = parentSpanId {
            guard Self.isValidSpanId(parentSpanId) else { return nil }
        }

        return AITraceContext(
            traceId: traceId.lowercased(),
            spanId: spanId.lowercased(),
            parentSpanId: parentSpanId?.lowercased(),
            operation: operation,
            startTime: startTime,
            sampled: sampled,
            baggage: baggage
        )
    }

    // MARK: - Validation Helpers

    /// Check if a trace ID is valid per W3C spec
    private static func isValidTraceId(_ id: String) -> Bool {
        guard id.count == 32 else { return false }
        let lowercased = id.lowercased()
        guard lowercased.allSatisfy({ $0.isHexDigit }) else { return false }
        guard lowercased != invalidTraceId else { return false }
        return true
    }

    /// Check if a span ID is valid per W3C spec
    private static func isValidSpanId(_ id: String) -> Bool {
        guard id.count == 16 else { return false }
        let lowercased = id.lowercased()
        guard lowercased.allSatisfy({ $0.isHexDigit }) else { return false }
        guard lowercased != invalidSpanId else { return false }
        return true
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
    ///   - additionalBaggage: Additional baggage to merge (must not contain PHI)
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
    /// Format: `{version}-{trace-id}-{span-id}-{flags}`
    /// Example: `00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01`
    public var traceparent: String {
        let flags = sampled ? "01" : "00"
        return "00-\(traceId)-\(spanId)-\(flags)"
    }

    /// Parse a W3C traceparent header
    ///
    /// - Parameter traceparent: The traceparent header value
    /// - Returns: A trace context if parsing succeeds
    public static func from(traceparent: String) -> AITraceContext? {
        let parts = traceparent.split(separator: "-")
        guard parts.count == 4 else { return nil }

        let version = String(parts[0])
        let traceIdRaw = String(parts[1])
        let parentIdRaw = String(parts[2])
        let flagsRaw = String(parts[3])

        // Validate version (only 00 is currently supported)
        guard version == "00" else { return nil }

        // Validate and normalize trace ID
        guard isValidTraceId(traceIdRaw) else { return nil }
        let traceId = traceIdRaw.lowercased()

        // Validate and normalize parent ID (becomes our parentSpanId)
        guard isValidSpanId(parentIdRaw) else { return nil }
        let parentId = parentIdRaw.lowercased()

        // Validate flags (must be 2 hex digits)
        guard flagsRaw.count == 2,
              flagsRaw.allSatisfy({ $0.isHexDigit }),
              let flagByte = UInt8(flagsRaw, radix: 16) else {
            return nil
        }

        // Sampled is the low bit of flags
        let sampled = (flagByte & 0x01) == 0x01

        return AITraceContext(
            traceId: traceId,
            spanId: generateSpanId(),
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
    /// Retries on failure and ensures non-zero result
    private static func generateSpanId() -> String {
        var attempts = 0
        while attempts < 3 {
            var bytes = [UInt8](repeating: 0, count: 8)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)

            if status == errSecSuccess {
                let hexString = bytes.map { String(format: "%02x", $0) }.joined()
                // Ensure not all-zeros
                if hexString != invalidSpanId {
                    return hexString
                }
            }
            attempts += 1
        }

        // Fallback: use UUID-based generation if SecRandom fails
        let uuid = UUID()
        let uuidHex = uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return String(uuidHex.prefix(16))
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
    ///
    /// Note: Baggage is excluded by default as it may contain sensitive data.
    /// Use `toLogDictionary(includeBaggage:)` if you've verified baggage is safe.
    public func toLogDictionary() -> [String: Any] {
        toLogDictionary(includeBaggage: false)
    }

    /// Create a dictionary for logging with optional baggage inclusion
    ///
    /// - Parameter includeBaggage: Whether to include baggage (default: false for PHI safety)
    /// - Returns: Dictionary suitable for logging
    public func toLogDictionary(includeBaggage: Bool) -> [String: Any] {
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

        if includeBaggage && !baggage.isEmpty {
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
