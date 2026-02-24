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

    // MARK: - Generative UI Events

    /// UI specification patch for progressive generative UI rendering.
    /// Contains a batch of RFC 6902 JSON Patch operations to apply incrementally to a UITree.
    case uiPatch(SpecPatchBatch)

    // MARK: - Computer Use Events

    /// A computer use action requested by the model (typed version of tool call)
    case computerUseAction(ComputerUseToolCall)

    // MARK: - Web Search Events

    /// Web search initiated — includes the query the model is searching for
    case webSearchStarted(query: String)

    /// Web search completed — includes query and all consulted source URLs
    case webSearchCompleted(AIWebSearchResult)

    /// An error occurred during streaming
    case error(Error)
}

// MARK: - Supporting Types
// Note: AIUsage and AIFinishReason are defined in AIUsage.swift

/// Source/citation information with optional position data for inline citation rendering
public struct AISource: Sendable, Codable, Hashable {
    public let id: String
    public let url: String?
    public let title: String?
    public let snippet: String?
    /// UTF-16 code unit offset where the citation starts in the response text
    public let startIndex: Int?
    /// UTF-16 code unit offset where the citation ends in the response text
    public let endIndex: Int?
    /// The type of source (web, file, document, etc.)
    public let sourceType: AISourceType?

    public init(
        id: String,
        url: String? = nil,
        title: String? = nil,
        snippet: String? = nil,
        startIndex: Int? = nil,
        endIndex: Int? = nil,
        sourceType: AISourceType? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.snippet = snippet
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.sourceType = sourceType
    }
}

/// Type of citation source
public enum AISourceType: String, Sendable, Codable {
    /// URL citation from web search
    case web
    /// File citation (e.g., OpenAI file_search)
    case file
    /// Container file citation (e.g., OpenAI code interpreter)
    case containerFile
    /// Document citation (e.g., Anthropic char/page/block location)
    case document
    /// Search result citation (e.g., Anthropic search_result_location)
    case searchResult
}

/// Result of a web search performed by the model
public struct AIWebSearchResult: Sendable, Codable {
    /// The search query the model used
    public let query: String?
    /// All URLs the model consulted (superset of cited sources)
    public let sources: [AIWebSearchSource]

    public init(query: String? = nil, sources: [AIWebSearchSource] = []) {
        self.query = query
        self.sources = sources
    }
}

/// A URL consulted during web search
public struct AIWebSearchSource: Sendable, Codable {
    public let url: String
    public let title: String?
    public let type: String

    public init(url: String, title: String? = nil, type: String = "url") {
        self.url = url
        self.title = title
        self.type = type
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

// Note: AIStepResult is defined in AIStepResult.swift

/// Tool call result data
public struct ToolCallResult: Sendable, Codable, Equatable {
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
///
/// Note: The `metadata` field is intentionally excluded from Codable and Equatable
/// conformances because ToolMetadata may contain non-Codable/non-Equatable types.
/// When encoding/decoding, metadata will be nil.
public struct AIToolResultData: Sendable, Codable, Equatable {
    public let id: String
    public let result: String
    public let metadata: ToolMetadata?
    public let artifacts: [ToolArtifact]?

    public init(id: String, result: String, metadata: ToolMetadata? = nil, artifacts: [ToolArtifact]? = nil) {
        self.id = id
        self.result = result
        self.metadata = metadata
        self.artifacts = artifacts
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case result
        case artifacts
        // Note: metadata is intentionally not encoded as ToolMetadata is not Codable-safe
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.result = try container.decode(String.self, forKey: .result)
        self.metadata = nil  // Metadata cannot be decoded
        self.artifacts = try container.decodeIfPresent([ToolArtifact].self, forKey: .artifacts)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(result, forKey: .result)
        try container.encodeIfPresent(artifacts, forKey: .artifacts)
        // Note: metadata is intentionally not encoded
    }

    // MARK: - Equatable

    public static func == (lhs: AIToolResultData, rhs: AIToolResultData) -> Bool {
        // Compare id and result only; metadata excluded as it may contain non-Equatable types
        lhs.id == rhs.id && lhs.result == rhs.result && lhs.artifacts == rhs.artifacts
    }
}
