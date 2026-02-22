//
//  AIReasoningConfig.swift
//  AISDK
//
//  Unified reasoning/thinking configuration for AITextRequest
//

import Foundation

/// Provider-agnostic reasoning configuration.
public struct AIReasoningConfig: Sendable, Equatable, Codable {
    /// Reasoning effort level (maps to provider-specific effort/thinking levels).
    public let effort: AIReasoningEffort?

    /// Explicit token budget for reasoning/thinking.
    public let budgetTokens: Int?

    /// Summary mode for reasoning output (OpenAI-specific; ignored by Anthropic/Gemini).
    public let summary: AIReasoningSummary?

    public enum AIReasoningEffort: String, Sendable, Codable, Equatable {
        case low
        case medium
        case high
    }

    /// Controls whether and how reasoning summaries are emitted.
    public enum AIReasoningSummary: String, Sendable, Codable, Equatable {
        case auto
        case concise
        case detailed
    }

    public init(
        effort: AIReasoningEffort? = nil,
        budgetTokens: Int? = nil,
        summary: AIReasoningSummary? = nil
    ) {
        self.effort = effort
        self.budgetTokens = budgetTokens
        self.summary = summary
    }
}

public extension AIReasoningConfig {
    /// Convenience factory for effort-only configuration.
    static func effort(_ effort: AIReasoningEffort) -> AIReasoningConfig {
        AIReasoningConfig(effort: effort)
    }

    /// Convenience factory for effort with summary mode.
    static func effort(_ effort: AIReasoningEffort, summary: AIReasoningSummary) -> AIReasoningConfig {
        AIReasoningConfig(effort: effort, summary: summary)
    }
}
