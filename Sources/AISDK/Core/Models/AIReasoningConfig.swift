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

    public enum AIReasoningEffort: String, Sendable, Codable, Equatable {
        case low
        case medium
        case high
    }

    public init(
        effort: AIReasoningEffort? = nil,
        budgetTokens: Int? = nil
    ) {
        self.effort = effort
        self.budgetTokens = budgetTokens
    }
}

public extension AIReasoningConfig {
    /// Convenience factory for effort-only configuration.
    static func effort(_ effort: AIReasoningEffort) -> AIReasoningConfig {
        AIReasoningConfig(effort: effort)
    }
}
