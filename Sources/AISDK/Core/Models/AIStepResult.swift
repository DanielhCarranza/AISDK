//
//  AIStepResult.swift
//  AISDK
//
//  Result model for a single step in multi-step agent execution
//  Based on Vercel AI SDK 6.x patterns
//

import Foundation

/// Result of a single step in multi-step agent execution
///
/// AIStepResult captures the outcome of each iteration in an agent loop,
/// including any text generated, tool calls made, tool results received,
/// and token usage for the step.
///
/// ## Usage
///
/// ```swift
/// // Create a step result after processing
/// let stepResult = AIStepResult(
///     stepIndex: 0,
///     text: "Let me search for that information.",
///     toolCalls: [ToolCallResult(id: "call-1", name: "search", arguments: "{}")],
///     usage: AIUsage(promptTokens: 100, completionTokens: 50)
/// )
///
/// // Use in agent streaming callbacks
/// for await event in agent.executeStream(messages: messages) {
///     if case .stepFinish(let stepIndex, let result) = event {
///         print("Step \(result.stepIndex) completed with: \(result.text)")
///     }
/// }
/// ```
public struct AIStepResult: Sendable, Codable, Equatable {
    /// The zero-based index of this step in the agent loop
    public let stepIndex: Int

    /// The text content generated during this step
    public let text: String

    /// Tool calls made by the model during this step
    public let toolCalls: [ToolCallResult]

    /// Results from executing tools during this step
    public let toolResults: [AIToolResultData]

    /// Token usage for this step
    public let usage: AIUsage

    /// Reason for completion of this step
    public let finishReason: AIFinishReason

    public init(
        stepIndex: Int,
        text: String,
        toolCalls: [ToolCallResult] = [],
        toolResults: [AIToolResultData] = [],
        usage: AIUsage = .zero,
        finishReason: AIFinishReason = .stop
    ) {
        self.stepIndex = stepIndex
        self.text = text
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.usage = usage
        self.finishReason = finishReason
    }
}

// MARK: - AIStepResult Extensions

public extension AIStepResult {
    /// Check if the step has any tool calls
    var hasToolCalls: Bool {
        !toolCalls.isEmpty
    }

    /// Check if the step has any tool results
    var hasToolResults: Bool {
        !toolResults.isEmpty
    }

    /// Check if step completed normally (not due to length or error)
    var completedNormally: Bool {
        finishReason == .stop || finishReason == .toolCalls
    }

    /// Check if step was truncated due to token limit
    var wasTruncated: Bool {
        finishReason == .length
    }

    /// Total tokens consumed in this step (prompt + completion)
    var totalTokens: Int {
        usage.totalTokens
    }
}

// MARK: - Empty Result

public extension AIStepResult {
    /// An empty step result for testing or placeholder purposes
    static let empty = AIStepResult(stepIndex: 0, text: "")
}

// MARK: - Custom Codable for schema evolution

extension AIStepResult {
    enum CodingKeys: String, CodingKey {
        case stepIndex
        case text
        case toolCalls
        case toolResults
        case usage
        case finishReason
    }

    /// Custom decoder that handles missing/optional keys for backwards compatibility
    /// - Missing keys use sensible defaults (empty arrays, .zero usage, .stop finishReason)
    /// - Unknown finishReason values map to .unknown
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.stepIndex = try container.decode(Int.self, forKey: .stepIndex)
        self.text = try container.decode(String.self, forKey: .text)
        self.toolCalls = try container.decodeIfPresent([ToolCallResult].self, forKey: .toolCalls) ?? []
        self.toolResults = try container.decodeIfPresent([AIToolResultData].self, forKey: .toolResults) ?? []
        self.usage = try container.decodeIfPresent(AIUsage.self, forKey: .usage) ?? .zero

        // Handle unknown finish reasons gracefully
        if let rawReason = try container.decodeIfPresent(String.self, forKey: .finishReason) {
            self.finishReason = AIFinishReason(rawValue: rawReason) ?? .unknown
        } else {
            self.finishReason = .stop
        }
    }
}
