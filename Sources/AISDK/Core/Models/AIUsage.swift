//
//  AIUsage.swift
//  AISDK
//
//  Token usage information for AI model responses
//  Based on Vercel AI SDK 6.x usage semantics
//

import Foundation

/// Token usage information for AI model responses
///
/// Tracks prompt tokens (input), completion tokens (output), and total tokens consumed.
/// Optionally includes reasoning tokens for models that support extended thinking (o1/o3).
///
/// Example:
/// ```swift
/// let usage = AIUsage(promptTokens: 100, completionTokens: 50)
/// print("Total tokens: \(usage.totalTokens)")  // 150
/// ```
public struct AIUsage: Sendable, Codable, Equatable, Hashable {
    /// Number of tokens in the prompt/input
    public let promptTokens: Int

    /// Number of tokens in the completion/output
    public let completionTokens: Int

    /// Total tokens consumed (computed as promptTokens + completionTokens)
    public var totalTokens: Int {
        promptTokens + completionTokens
    }

    /// Reasoning/thinking tokens for models that support extended thinking (o1/o3)
    /// This is included in completionTokens but tracked separately for billing
    public let reasoningTokens: Int?

    /// Cached tokens (for providers that support prompt caching)
    public let cachedTokens: Int?

    public init(
        promptTokens: Int,
        completionTokens: Int,
        reasoningTokens: Int? = nil,
        cachedTokens: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.cachedTokens = cachedTokens
    }

    /// Zero usage for initialization
    public static let zero = AIUsage(promptTokens: 0, completionTokens: 0)

    /// Combine two usage values (for multi-step operations)
    public static func + (lhs: AIUsage, rhs: AIUsage) -> AIUsage {
        AIUsage(
            promptTokens: lhs.promptTokens + rhs.promptTokens,
            completionTokens: lhs.completionTokens + rhs.completionTokens,
            reasoningTokens: combineOptionals(lhs.reasoningTokens, rhs.reasoningTokens),
            cachedTokens: combineOptionals(lhs.cachedTokens, rhs.cachedTokens)
        )
    }

    private static func combineOptionals(_ a: Int?, _ b: Int?) -> Int? {
        switch (a, b) {
        case let (a?, b?): return a + b
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return nil
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case reasoningTokens = "reasoning_tokens"
        case cachedTokens = "cached_tokens"
    }
}

// MARK: - AIFinishReason

/// Reason why the model stopped generating
///
/// Maps to Vercel AI SDK 6.x finish reasons and provider-specific values.
/// Uses custom Codable implementation to safely handle unknown future values.
public enum AIFinishReason: Sendable, Hashable, CaseIterable {
    /// Model completed naturally (end of response)
    case stop

    /// Hit maximum token limit
    case length

    /// Model requested tool/function calls
    case toolCalls

    /// Content was filtered by safety systems
    case contentFilter

    /// An error occurred during generation
    case error

    /// Request was cancelled
    case cancelled

    /// Unknown finish reason (preserves original string for debugging)
    case unknown

    /// The raw string value for serialization
    public var rawValue: String {
        switch self {
        case .stop: return "stop"
        case .length: return "length"
        case .toolCalls: return "tool_calls"
        case .contentFilter: return "content_filter"
        case .error: return "error"
        case .cancelled: return "cancelled"
        case .unknown: return "unknown"
        }
    }

    /// Initialize from a raw string value
    public init?(rawValue: String) {
        switch rawValue.lowercased() {
        case "stop": self = .stop
        case "length": self = .length
        case "tool_calls": self = .toolCalls
        case "content_filter": self = .contentFilter
        case "error": self = .error
        case "cancelled", "canceled": self = .cancelled
        case "unknown": self = .unknown
        default: return nil
        }
    }

    /// Convert from legacy finish_reason strings (OpenAI, Anthropic, etc.)
    /// Always succeeds - unknown values map to .unknown
    public init(legacyReason: String?) {
        guard let reason = legacyReason?.lowercased() else {
            self = .unknown
            return
        }

        switch reason {
        case "stop", "end_turn", "stop_sequence":
            self = .stop
        case "length", "max_tokens":
            self = .length
        case "tool_calls", "function_call", "tool_use":
            self = .toolCalls
        case "content_filter", "safety":
            self = .contentFilter
        case "error":
            self = .error
        case "cancelled", "canceled":
            self = .cancelled
        default:
            self = .unknown
        }
    }

    /// Whether this reason indicates successful completion
    public var isSuccess: Bool {
        switch self {
        case .stop, .length, .toolCalls:
            return true
        case .contentFilter, .error, .cancelled, .unknown:
            return false
        }
    }

    /// Whether the response may be incomplete
    public var mayBeTruncated: Bool {
        self == .length
    }
}

// MARK: - AIFinishReason Codable

extension AIFinishReason: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Use legacyReason init which handles case-insensitive matching
        // and maps unknown values to .unknown instead of throwing
        self.init(legacyReason: rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
