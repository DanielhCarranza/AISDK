//
//  AITextResult.swift
//  AISDK
//
//  Result model for text generation operations
//  Based on Vercel AI SDK 6.x patterns
//

import Foundation

/// Result from text generation
public struct AITextResult: Sendable, Equatable {
    /// The generated text content
    public let text: String

    /// Tool calls made by the model
    public let toolCalls: [ToolCallResult]

    /// Token usage information
    public let usage: AIUsage

    /// Reason for completion
    public let finishReason: AIFinishReason

    /// Request ID for tracing
    public let requestId: String?

    /// Model used for generation
    public let model: String?

    /// Provider that handled the request
    public let provider: String?

    /// OpenAI Response ID for conversation chaining
    /// Pass this as `conversationId` in subsequent requests to continue the conversation
    public let responseId: String?

    public init(
        text: String,
        toolCalls: [ToolCallResult] = [],
        usage: AIUsage = .zero,
        finishReason: AIFinishReason = .stop,
        requestId: String? = nil,
        model: String? = nil,
        provider: String? = nil,
        responseId: String? = nil
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.usage = usage
        self.finishReason = finishReason
        self.requestId = requestId
        self.model = model
        self.provider = provider
        self.responseId = responseId
    }
}

// MARK: - AITextResult Extensions

public extension AITextResult {
    /// Check if the result has any tool calls
    var hasToolCalls: Bool {
        !toolCalls.isEmpty
    }

    /// Check if generation completed normally (not due to length or error)
    var completedNormally: Bool {
        finishReason == .stop || finishReason == .toolCalls
    }

    /// Check if generation was truncated due to token limit
    var wasTruncated: Bool {
        finishReason == .length
    }

    /// Total tokens consumed (prompt + completion)
    var totalTokens: Int {
        usage.totalTokens
    }
}

// MARK: - Empty Result

public extension AITextResult {
    /// An empty result for testing or placeholder purposes
    static let empty = AITextResult(text: "")
}
