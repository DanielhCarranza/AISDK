//
//  AIStreamEvent.swift
//  AISDK
//
//  Core streaming event types for unified AI SDK
//  Based on Vercel AI SDK 6.x event semantics
//

import Foundation

/// All possible events emitted during AI streaming operations
/// Supports 20 distinct event types for comprehensive stream handling
/// Based on Vercel AI SDK 6.x event semantics
public enum AIStreamEvent: Sendable {
    // MARK: - Text Events

    /// Partial text content received during streaming
    case textDelta(String)

    /// Text generation completed with final content
    case textCompletion(String)

    // MARK: - Reasoning Events (for o1/o3 models)

    /// Reasoning/thinking phase started
    case reasoningStart

    /// Reasoning/thinking text delta (for models that support it)
    case reasoningDelta(String)

    /// Reasoning/thinking phase completed
    case reasoningFinish(String)

    // MARK: - Tool Events

    /// A tool call was requested by the model
    case toolCallStart(id: String, name: String)

    /// Partial arguments for an in-progress tool call
    case toolCallDelta(id: String, argumentsDelta: String)

    /// Tool call is complete with full arguments (alias for toolCallFinish for compatibility)
    case toolCall(id: String, name: String, arguments: String)

    /// Tool call finished (semantic alias for toolCall)
    case toolCallFinish(id: String, name: String, arguments: String)

    /// Result from executing a tool
    case toolResult(id: String, result: String, metadata: ToolMetadata?)

    // MARK: - Structured Output Events

    /// Partial JSON object during structured output generation
    case objectDelta(Data)

    // MARK: - Source Events

    /// Source/citation information
    case source(AISource)

    // MARK: - File Events

    /// File content generated (e.g., images)
    case file(AIFileEvent)

    // MARK: - Usage Events

    /// Token usage information
    case usage(AIUsage)

    // MARK: - Lifecycle Events

    /// Stream has started
    case start(metadata: AIStreamMetadata?)

    /// A step in multi-step execution is starting
    case stepStart(stepIndex: Int)

    /// A step in multi-step execution completed
    case stepFinish(stepIndex: Int, result: AIStepResult)

    // MARK: - Heartbeat Events

    /// Heartbeat for connection keepalive during long operations
    case heartbeat(timestamp: Date)

    /// Stream finished with reason and final usage
    case finish(finishReason: AIFinishReason, usage: AIUsage)

    /// An error occurred during streaming
    case error(Error)
}

// MARK: - Supporting Types

/// Reason why the model stopped generating
public enum AIFinishReason: String, Sendable, Codable {
    case stop = "stop"
    case length = "length"
    case toolCalls = "tool_calls"
    case contentFilter = "content_filter"
    case error = "error"
    case cancelled = "cancelled"
    case unknown = "unknown"

    /// Convert from legacy finish_reason strings
    public init(legacyReason: String?) {
        switch legacyReason {
        case "stop": self = .stop
        case "length": self = .length
        case "tool_calls", "function_call": self = .toolCalls
        case "content_filter": self = .contentFilter
        case "error": self = .error
        case "cancelled", "canceled": self = .cancelled
        default: self = .unknown
        }
    }
}

/// Token usage information
public struct AIUsage: Sendable, Codable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let reasoningTokens: Int?

    public init(
        promptTokens: Int,
        completionTokens: Int,
        totalTokens: Int? = nil,
        reasoningTokens: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens ?? (promptTokens + completionTokens)
        self.reasoningTokens = reasoningTokens
    }

    /// Zero usage for initialization
    public static let zero = AIUsage(promptTokens: 0, completionTokens: 0, totalTokens: 0)

    /// Create from legacy ChatCompletionResponse.Usage
    public init(legacy: ChatCompletionResponse.Usage?) {
        self.promptTokens = legacy?.promptTokens ?? 0
        self.completionTokens = legacy?.completionTokens ?? 0
        self.totalTokens = legacy?.totalTokens ?? (promptTokens + completionTokens)
        self.reasoningTokens = legacy?.completionTokensDetails?.reasoningTokens
    }
}

/// Source/citation information
public struct AISource: Sendable, Codable {
    public let id: String
    public let url: String?
    public let title: String?
    public let snippet: String?

    public init(id: String, url: String? = nil, title: String? = nil, snippet: String? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.snippet = snippet
    }
}

/// File event data
public struct AIFileEvent: Sendable {
    public let id: String
    public let mimeType: String
    public let data: Data

    public init(id: String, mimeType: String, data: Data) {
        self.id = id
        self.mimeType = mimeType
        self.data = data
    }
}

/// Metadata for stream start
public struct AIStreamMetadata: Sendable {
    public let requestId: String?
    public let model: String?
    public let provider: String?

    public init(requestId: String? = nil, model: String? = nil, provider: String? = nil) {
        self.requestId = requestId
        self.model = model
        self.provider = provider
    }
}

/// Result of a single step in multi-step execution
public struct AIStepResult: Sendable {
    public let stepIndex: Int
    public let text: String
    public let toolCalls: [AIToolCallResult]
    public let toolResults: [AIToolResultData]
    public let usage: AIUsage
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

/// Tool call result data
public struct AIToolCallResult: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Tool execution result data
public struct AIToolResultData: Sendable {
    public let id: String
    public let result: String
    public let metadata: ToolMetadata?

    public init(id: String, result: String, metadata: ToolMetadata? = nil) {
        self.id = id
        self.result = result
        self.metadata = metadata
    }
}
