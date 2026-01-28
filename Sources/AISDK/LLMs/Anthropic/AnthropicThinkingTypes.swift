//
//  AnthropicThinkingTypes.swift
//  AISDK
//
//  Created by AI Assistant on 01/28/26.
//

import Foundation

// MARK: - Configuration

/// Configuration for Claude's extended thinking feature
///
/// Extended thinking enables chain-of-thought reasoning with configurable token budgets.
/// Use `.enabled(budgetTokens:)` to enable with a specific budget, or `.disabled` to turn off.
public enum AnthropicThinkingConfigParam: Codable, Sendable, Equatable {
    /// Enable extended thinking with a token budget
    /// - Parameter budgetTokens: Number of tokens for thinking (minimum 1024)
    case enabled(budgetTokens: Int)

    /// Disable extended thinking
    case disabled

    private enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .enabled(let budget):
            try container.encode("enabled", forKey: .type)
            try container.encode(budget, forKey: .budgetTokens)
        case .disabled:
            try container.encode("disabled", forKey: .type)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "enabled":
            let budget = try container.decode(Int.self, forKey: .budgetTokens)
            self = .enabled(budgetTokens: budget)
        case "disabled":
            self = .disabled
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown thinking type: \(type)"
            )
        }
    }

    // MARK: - Validation

    /// Minimum allowed thinking budget
    public static let minimumBudget = 1024

    /// Validate the thinking configuration against max_tokens
    /// - Parameter maxTokens: The max_tokens value for the request
    /// - Throws: `LLMError.invalidRequest` if validation fails
    public func validate(maxTokens: Int) throws {
        guard case .enabled(let budget) = self else { return }

        guard budget >= Self.minimumBudget else {
            throw LLMError.invalidRequest(
                "Thinking budget must be at least \(Self.minimumBudget) tokens (got \(budget))"
            )
        }

        guard budget < maxTokens else {
            throw LLMError.invalidRequest(
                "Thinking budget (\(budget)) must be less than max_tokens (\(maxTokens))"
            )
        }
    }

    /// Check if thinking is enabled
    public var isEnabled: Bool {
        if case .enabled = self { return true }
        return false
    }

    /// Get the budget tokens if enabled, nil otherwise
    public var budgetTokens: Int? {
        if case .enabled(let budget) = self { return budget }
        return nil
    }
}

// MARK: - Response Content Blocks

/// Thinking content block in responses
///
/// Contains Claude's reasoning process and a signature for verification.
/// Note: Claude 4 models return summarized thinking (billed for full internal tokens).
public struct AnthropicThinkingBlock: Codable, Sendable, Equatable {
    /// Content type identifier
    public let type: String

    /// The thinking content (may be summarized in Claude 4 models)
    public let thinking: String

    /// Verification signature for the thinking block
    public let signature: String

    public init(thinking: String, signature: String) {
        self.type = "thinking"
        self.thinking = thinking
        self.signature = signature
    }
}

/// Redacted thinking block for safety-flagged content
///
/// When Claude's thinking contains content that was flagged by safety systems,
/// it's returned as encrypted data that cannot be read.
public struct AnthropicRedactedThinkingBlock: Codable, Sendable, Equatable {
    /// Content type identifier
    public let type: String

    /// Encrypted content that cannot be decrypted
    public let data: String

    public init(data: String) {
        self.type = "redacted_thinking"
        self.data = data
    }
}

// MARK: - Convenience Extensions

public extension AnthropicThinkingConfigParam {
    /// Create an enabled config with default budget (10,000 tokens)
    static var defaultEnabled: Self {
        .enabled(budgetTokens: 10_000)
    }

    /// Create an enabled config with minimum budget (1,024 tokens)
    static var minimalEnabled: Self {
        .enabled(budgetTokens: minimumBudget)
    }
}

// MARK: - Backward Compatibility

@available(*, deprecated, renamed: "AnthropicThinkingConfigParam")
public typealias AnthropicThinkingConfig = AnthropicThinkingConfigParam
