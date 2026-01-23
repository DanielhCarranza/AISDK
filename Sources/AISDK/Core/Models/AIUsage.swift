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

    /// Total tokens consumed (promptTokens + completionTokens)
    public let totalTokens: Int

    /// Reasoning/thinking tokens for models that support extended thinking (o1/o3)
    /// This is included in completionTokens but tracked separately for billing
    public let reasoningTokens: Int?

    /// Cached tokens (for providers that support prompt caching)
    public let cachedTokens: Int?

    public init(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        cachedTokens: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens ?? (promptTokens + completionTokens)
        self.reasoningTokens = reasoningTokens
        self.cachedTokens = cachedTokens
    }

    /// Zero usage for initialization
    public static let zero = AIUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0)

    /// Create from legacy ChatCompletionResponse.Usage
    public init(legacy: ChatCompletionResponse.Usage?) {
        self.promptTokens = legacy?.promptTokens ?? 0
        self.completionTokens = legacy?.completionTokens ?? 0
        self.totalTokens = legacy?.totalTokens ?? (promptTokens + completionTokens)
        self.reasoningTokens = legacy?.completionTokensDetails?.reasoningTokens
        self.cachedTokens = nil  // Legacy Usage doesn't track cached tokens
    }

    /// Combine two usage values (for multi-step operations)
    public static func + (lhs: AIUsage, rhs: AIUsage) -> AIUsage {
        AIUsage(
            promptTokens: lhs.promptTokens + rhs.promptTokens,
            completionTokens: lhs.completionTokens + rhs.completionTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens,
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
}

// MARK: - AIFinishReason

/// Reason why the model stopped generating
///
/// Maps to Vercel AI SDK 6.x finish reasons and provider-specific values.
public enum AIFinishReason: String, Sendable, Codable, CaseIterable {
    /// Model completed naturally (end of response)
    case stop = "stop"

    /// Hit maximum token limit
    case length = "length"

    /// Model requested tool/function calls
    case toolCalls = "tool_calls"

    /// Content was filtered by safety systems
    case contentFilter = "content_filter"

    /// An error occurred during generation
    case error = "error"

    /// Request was cancelled
    case cancelled = "cancelled"

    /// Unknown finish reason
    case unknown = "unknown"

    /// Convert from legacy finish_reason strings (OpenAI, Anthropic, etc.)
    public init(legacyReason: String?) {
        switch legacyReason {
        case "stop", "end_turn":
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
