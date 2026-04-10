//
//  LLM.swift
//  AISDK
//
//  Core protocol for unified AI language model interface
//  Based on Vercel AI SDK 6.x patterns
//

import Foundation

// MARK: - AIMessage (Unified Message Type for LLM)

/// Unified message type for the LLM protocol
/// This bridges between the new unified interface and existing message types
public struct AIMessage: Sendable, Codable, Identifiable {
    /// Unique identifier for this message
    public var id: String

    /// The role of the message sender
    public let role: Role

    /// The content of the message (mutable for streaming text accumulation)
    public var content: Content

    /// Optional name for the sender
    public let name: String?

    /// Tool calls made by the assistant (mutable for streaming tool call accumulation)
    public var toolCalls: [ToolCall]?

    /// Tool call ID (for tool response messages)
    public let toolCallId: String?

    // MARK: - Session Properties

    /// Agent that produced this message (for multi-agent sessions)
    public var agentId: String?

    /// Agent name for display
    public var agentName: String?

    /// Whether this message represents a checkpoint
    public var isCheckpoint: Bool

    /// Checkpoint index (if this is a checkpoint)
    public var checkpointIndex: Int?

    /// Provider-specific metadata carried across turns (e.g., Gemini reasoning content).
    /// Not sent to providers that don't need it.
    public var providerMetadata: [String: String]?

    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: Content,
        name: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        agentId: String? = nil,
        agentName: String? = nil,
        isCheckpoint: Bool = false,
        checkpointIndex: Int? = nil,
        providerMetadata: [String: String]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.name = name
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.agentId = agentId
        self.agentName = agentName
        self.isCheckpoint = isCheckpoint
        self.checkpointIndex = checkpointIndex
        self.providerMetadata = providerMetadata
    }

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case id, role, content, name, toolCalls, toolCallId
        case agentId, agentName, isCheckpoint, checkpointIndex
        case providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.role = try container.decode(Role.self, forKey: .role)
        self.content = try container.decode(Content.self, forKey: .content)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        self.toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
        self.agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
        self.agentName = try container.decodeIfPresent(String.self, forKey: .agentName)
        self.isCheckpoint = try container.decodeIfPresent(Bool.self, forKey: .isCheckpoint) ?? false
        self.checkpointIndex = try container.decodeIfPresent(Int.self, forKey: .checkpointIndex)
        self.providerMetadata = try container.decodeIfPresent([String: String].self, forKey: .providerMetadata)
    }

    // MARK: - Role

    public enum Role: String, Sendable, Codable {
        case user
        case assistant
        case system
        case tool
    }

    // MARK: - Content

    public enum Content: Sendable {
        case text(String)
        case parts([ContentPart])

        /// Get the text content as a string
        public var textValue: String {
            switch self {
            case .text(let text):
                return text
            case .parts(let parts):
                return parts.compactMap { part in
                    if case .text(let text) = part {
                        return text
                    }
                    return nil
                }.joined(separator: "\n")
            }
        }
    }

    // MARK: - ContentPart

    public enum ContentPart: Sendable {
        case text(String)
        case image(Data, mimeType: String)
        case imageURL(String)
        case audio(Data, mimeType: String)
        case file(Data, filename: String, mimeType: String)
        case video(Data, mimeType: String)
        case videoURL(String)
    }

    // MARK: - ToolCall

    public struct ToolCall: Sendable, Codable, Equatable {
        public let id: String
        public let name: String
        /// Tool call arguments JSON (mutable for streaming argument accumulation)
        public var arguments: String

        public init(id: String, name: String, arguments: String) {
            self.id = id
            self.name = name
            self.arguments = arguments
        }
    }
}

// MARK: - AIMessage Codable Conformance

extension AIMessage.Content: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, value, parts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value)
        case "parts":
            let parts = try container.decode([AIMessage.ContentPart].self, forKey: .parts)
            self = .parts(parts)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .value)
        case .parts(let parts):
            try container.encode("parts", forKey: .type)
            try container.encode(parts, forKey: .parts)
        }
    }
}

extension AIMessage.ContentPart: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, url, filename
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let data = try container.decode(Data.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .image(data, mimeType: mimeType)
        case "imageURL":
            let url = try container.decode(String.self, forKey: .url)
            self = .imageURL(url)
        case "audio":
            let data = try container.decode(Data.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .audio(data, mimeType: mimeType)
        case "file":
            let data = try container.decode(Data.self, forKey: .data)
            let filename = try container.decode(String.self, forKey: .filename)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .file(data, filename: filename, mimeType: mimeType)
        case "video":
            let data = try container.decode(Data.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .video(data, mimeType: mimeType)
        case "videoURL":
            let url = try container.decode(String.self, forKey: .url)
            self = .videoURL(url)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown content part type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .imageURL(let url):
            try container.encode("imageURL", forKey: .type)
            try container.encode(url, forKey: .url)
        case .audio(let data, let mimeType):
            try container.encode("audio", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .file(let data, let filename, let mimeType):
            try container.encode("file", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(filename, forKey: .filename)
            try container.encode(mimeType, forKey: .mimeType)
        case .video(let data, let mimeType):
            try container.encode("video", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .videoURL(let url):
            try container.encode("videoURL", forKey: .type)
            try container.encode(url, forKey: .url)
        }
    }
}

// MARK: - AIMessage Convenience Initializers

public extension AIMessage {
    /// Create a user message with text content
    static func user(_ text: String) -> AIMessage {
        AIMessage(role: .user, content: .text(text))
    }

    /// Create an assistant message with text content
    static func assistant(_ text: String) -> AIMessage {
        AIMessage(role: .assistant, content: .text(text))
    }

    /// Create a system message with text content
    static func system(_ text: String) -> AIMessage {
        AIMessage(role: .system, content: .text(text))
    }

    /// Create a tool response message
    static func tool(_ result: String, toolCallId: String) -> AIMessage {
        AIMessage(role: .tool, content: .text(result), toolCallId: toolCallId)
    }

    /// Create an assistant message with tool calls
    static func assistant(_ text: String, toolCalls: [ToolCall]) -> AIMessage {
        let content: Content = text.isEmpty ? .parts([]) : .text(text)
        return AIMessage(role: .assistant, content: content, toolCalls: toolCalls)
    }

    /// Create an assistant message with agent attribution (for multi-agent sessions)
    static func assistant(
        _ text: String,
        agentId: String?,
        agentName: String?,
        toolCalls: [ToolCall]? = nil
    ) -> AIMessage {
        let content: Content = text.isEmpty ? .parts([]) : .text(text)
        return AIMessage(
            role: .assistant,
            content: content,
            toolCalls: toolCalls,
            agentId: agentId,
            agentName: agentName
        )
    }
}

// MARK: - AIMessage Session Helpers

public extension AIMessage {
    /// Get text content as a string (nil if empty)
    var textContent: String? {
        let text = content.textValue
        return text.isEmpty ? nil : text
    }

    /// Append text to a text-content message (for streaming accumulation)
    mutating func appendText(_ delta: String) {
        switch content {
        case .text(let existing):
            content = .text(existing + delta)
        case .parts(var parts):
            if case .text(let existing) = parts.last {
                parts[parts.count - 1] = .text(existing + delta)
            } else {
                parts.append(.text(delta))
            }
            content = .parts(parts)
        }
    }
}

// MARK: - LLM Protocol

/// Unified protocol for all AI language model providers
/// This protocol provides a consistent interface across different LegacyLLM providers
/// and supports both synchronous and streaming operations.
public protocol LLM: Sendable {
    /// The provider name (e.g., "openai", "anthropic", "google")
    var provider: String { get }

    /// The model identifier (e.g., "gpt-4", "claude-3-opus")
    var modelId: String { get }

    /// The capabilities supported by this model
    var capabilities: LLMCapabilities { get }

    /// Generate text from a request (non-streaming)
    /// - Parameter request: The text generation request
    /// - Returns: The text generation result
    func generateText(request: AITextRequest) async throws -> AITextResult

    /// Stream text from a request
    /// - Parameter request: The text generation request
    /// - Returns: An async stream of events
    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>

    /// Generate a structured object from a request (non-streaming)
    /// - Parameter request: The object generation request
    /// - Returns: The object generation result
    func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T>

    /// Stream a structured object from a request
    /// - Parameter request: The object generation request
    /// - Returns: An async stream of events
    func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error>
}

// MARK: - Default Implementations

public extension LLM {
    /// Default implementation for streaming object generation
    /// Collects stream events and attempts to parse the final result
    func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T> {
        var collectedData = Data()
        var usage = AIUsage.zero
        var finishReason: AIFinishReason = .unknown
        var requestId: String?
        var effectiveModel: String?
        var effectiveProvider: String?

        for try await event in streamObject(request: request) {
            switch event {
            case .start(let metadata):
                // Capture metadata from stream start
                requestId = metadata?.requestId
                effectiveModel = metadata?.model
                effectiveProvider = metadata?.provider
            case .objectDelta(let data):
                collectedData.append(data)
            case .usage(let eventUsage):
                usage = eventUsage
            case .finish(let reason, let finalUsage):
                finishReason = reason
                usage = finalUsage
            default:
                break
            }
        }

        let decoder = JSONDecoder()
        let object = try decoder.decode(T.self, from: collectedData)
        let rawJSON = String(data: collectedData, encoding: .utf8)

        return AIObjectResult(
            object: object,
            usage: usage,
            finishReason: finishReason,
            requestId: requestId,
            model: effectiveModel ?? request.model ?? modelId,
            provider: effectiveProvider ?? provider,
            rawJSON: rawJSON
        )
    }
}

// MARK: - Request & Result Types

// Note: Request and result types are defined in their respective files:
// - AITextRequest, DataSensitivity, StreamBufferPolicy: Sources/AISDK/Core/Models/AITextRequest.swift
// - AITextResult: Sources/AISDK/Core/Models/AITextResult.swift
// - AIObjectRequest: Sources/AISDK/Core/Models/AIObjectRequest.swift
// - AIObjectResult: Sources/AISDK/Core/Models/AIObjectResult.swift
