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
///     toolCalls: [AIToolCallResult(id: "call-1", name: "search", arguments: "{}")],
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
    public let toolCalls: [AIToolCallResult]

    /// Results from executing tools during this step
    public let toolResults: [AIToolResultData]

    /// Token usage for this step
    public let usage: AIUsage

    /// Reason for completion of this step
    public let finishReason: AIFinishReason

    public init(
        stepIndex: Int,
        text: String,
        toolCalls: [AIToolCallResult] = [],
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

// MARK: - Codable Conformance for AIToolResultData

extension AIToolResultData: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case result
        // Note: metadata is not encoded as it may contain non-Codable types
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            result: try container.decode(String.self, forKey: .result),
            metadata: nil
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(result, forKey: .result)
        // Note: metadata is intentionally not encoded
    }
}

// MARK: - Equatable Conformance for AIToolResultData

extension AIToolResultData: Equatable {
    public static func == (lhs: AIToolResultData, rhs: AIToolResultData) -> Bool {
        // Compare id and result; metadata comparison is omitted as it may contain non-Equatable types
        lhs.id == rhs.id && lhs.result == rhs.result
    }
}
