//
//  AIMessage.swift
//  AISDK
//
//  Universal LegacyMessage System for AI
//  Provider-agnostic message format that converts to specific LegacyLLM provider formats
//

import Foundation

// MARK: - Universal LegacyMessage

/// Universal message that works across all LegacyLLM providers
public struct AIInputMessage {
    public let role: AIMessageRole
    public let content: [AIContentPart]
    public let name: String?
    public let toolCalls: [AIToolCall]?
    public let toolCallId: String? // For tool response messages
    
    public init(role: AIMessageRole, content: [AIContentPart], name: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCalls = nil
        self.toolCallId = nil
    }
    
    // Internal initializer for tool responses
    internal init(role: AIMessageRole, content: [AIContentPart], name: String? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCalls = nil
        self.toolCallId = toolCallId
    }
    
    // Internal initializer for assistant messages with tool calls
    internal init(role: AIMessageRole, content: [AIContentPart], name: String? = nil, toolCalls: [AIToolCall]? = nil) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCalls = toolCalls
        self.toolCallId = nil
    }
}

// MARK: - Universal Role System

/// Universal role system that maps to all provider role systems
public enum AIMessageRole {
    case user
    case assistant  
    case system
    case tool
}

// MARK: - Universal Content Part System

/// Universal content part system supporting all modalities
public enum AIContentPart {
    case text(String)
    case image(AIImageContent)
    case audio(AIAudioContent)
    case file(AIFileContent)
    case video(AIVideoContent) // Future extension
    
    // Structured content
    case json(Data)
    case html(String)
    case markdown(String)
}

// MARK: - Structured Content Types

/// Universal image content with support for data, URLs, and quality settings
public struct AIImageContent {
    public let data: Data?
    public let url: URL?
    public let detail: AIImageDetail
    public let mimeType: String
    
    public init(data: Data? = nil, url: URL? = nil, detail: AIImageDetail = .auto, mimeType: String = "image/jpeg") {
        guard data != nil || url != nil else {
            fatalError("AIImageContent must have either data or URL")
        }
        self.data = data
        self.url = url
        self.detail = detail
        self.mimeType = mimeType
    }
    
    public enum AIImageDetail {
        case auto
        case low
        case high
    }
}

/// Universal audio content with format and optional transcript
public struct AIAudioContent {
    public let data: Data?
    public let url: URL?
    public let format: AIAudioFormat
    public let transcript: String? // Optional transcript
    
    public init(data: Data? = nil, url: URL? = nil, format: AIAudioFormat = .auto, transcript: String? = nil) {
        guard data != nil || url != nil else {
            fatalError("AIAudioContent must have either data or URL")
        }
        self.data = data
        self.url = url
        self.format = format
        self.transcript = transcript
    }
    
    public enum AIAudioFormat {
        case auto
        case mp3
        case wav
        case m4a
        case opus
        case flac
    }
}

/// Universal file content with type detection and metadata
public struct AIFileContent {
    public let data: Data?
    public let url: URL?
    public let filename: String
    public let mimeType: String
    public let type: AIFileType
    
    public init(data: Data? = nil, url: URL? = nil, filename: String, type: AIFileType) {
        guard data != nil || url != nil else {
            fatalError("AIFileContent must have either data or URL")
        }
        self.data = data
        self.url = url
        self.filename = filename
        self.type = type
        self.mimeType = type.mimeType
    }
    
    public enum AIFileType: Equatable {
        case pdf
        case doc
        case docx
        case txt
        case csv
        case json
        case xml
        case image(AIImageContent.AIImageDetail)
        case audio(AIAudioContent.AIAudioFormat)
        case other(String)
        
        /// Get MIME type for the file type
        public var mimeType: String {
            switch self {
            case .pdf: return "application/pdf"
            case .doc: return "application/msword"
            case .docx: return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            case .txt: return "text/plain"
            case .csv: return "text/csv"
            case .json: return "application/json"
            case .xml: return "application/xml"
            case .image: return "image/jpeg" // Default, can be overridden
            case .audio: return "audio/mpeg" // Default, can be overridden
            case .other(let mimeType): return mimeType
            }
        }
    }
}

/// Universal video content (future extension)
public struct AIVideoContent {
    public let data: Data?
    public let url: URL?
    public let format: AIVideoFormat
    public let thumbnail: Data? // Optional thumbnail
    
    public init(data: Data? = nil, url: URL? = nil, format: AIVideoFormat = .auto, thumbnail: Data? = nil) {
        guard data != nil || url != nil else {
            fatalError("AIVideoContent must have either data or URL")
        }
        self.data = data
        self.url = url
        self.format = format
        self.thumbnail = thumbnail
    }
    
    public enum AIVideoFormat {
        case auto
        case mp4
        case mov
        case avi
        case webm
    }
}

// MARK: - Universal Tool Call System

/// Universal tool call representation
public struct AIToolCall {
    public let id: String
    public let name: String
    public let arguments: [String: Any]
    
    public init(id: String, name: String, arguments: [String: Any]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

// MARK: - Convenience Builders

extension AIInputMessage {
    /// Create a user message with text content
    public static func user(_ text: String) -> AIInputMessage {
        return AIInputMessage(role: .user, content: [.text(text)])
    }
    
    /// Create a user message with multiple content parts
    public static func user(_ content: [AIContentPart]) -> AIInputMessage {
        return AIInputMessage(role: .user, content: content)
    }
    
    /// Create an assistant message with text content
    public static func assistant(_ text: String) -> AIInputMessage {
        return AIInputMessage(role: .assistant, content: [.text(text)])
    }
    
    /// Create an assistant message with multiple content parts
    public static func assistant(_ content: [AIContentPart]) -> AIInputMessage {
        return AIInputMessage(role: .assistant, content: content)
    }
    
    /// Create an assistant message with tool calls
    public static func assistant(_ text: String, toolCalls: [AIToolCall]) -> AIInputMessage {
        let content: [AIContentPart] = text.isEmpty ? [] : [.text(text)]
        return AIInputMessage(role: .assistant, content: content, name: nil, toolCalls: toolCalls)
    }
    
    /// Create a system message
    public static func system(_ text: String) -> AIInputMessage {
        return AIInputMessage(role: .system, content: [.text(text)])
    }
    
    /// Create a tool response message
    public static func tool(_ result: String, callId: String, name: String = "") -> AIInputMessage {
        return AIInputMessage(role: .tool, content: [.text(result)], name: name, toolCallId: callId)
    }
}

// MARK: - Content Part Builders

extension AIContentPart {
    /// Create image content from data
    public static func image(_ data: Data, detail: AIImageContent.AIImageDetail = .auto, mimeType: String = "image/jpeg") -> AIContentPart {
        return .image(AIImageContent(data: data, detail: detail, mimeType: mimeType))
    }
    
    /// Create image content from URL
    public static func imageURL(_ url: URL, detail: AIImageContent.AIImageDetail = .auto, mimeType: String = "image/jpeg") -> AIContentPart {
        return .image(AIImageContent(url: url, detail: detail, mimeType: mimeType))
    }
    
    /// Create audio content from data
    public static func audio(_ data: Data, format: AIAudioContent.AIAudioFormat = .auto, transcript: String? = nil) -> AIContentPart {
        return .audio(AIAudioContent(data: data, format: format, transcript: transcript))
    }
    
    /// Create audio content from URL
    public static func audioURL(_ url: URL, format: AIAudioContent.AIAudioFormat = .auto, transcript: String? = nil) -> AIContentPart {
        return .audio(AIAudioContent(url: url, format: format, transcript: transcript))
    }
    
    /// Create file content from data
    public static func file(_ data: Data, filename: String, type: AIFileContent.AIFileType) -> AIContentPart {
        return .file(AIFileContent(data: data, filename: filename, type: type))
    }
    
    /// Create file content from URL
    public static func fileURL(_ url: URL, filename: String, type: AIFileContent.AIFileType) -> AIContentPart {
        return .file(AIFileContent(url: url, filename: filename, type: type))
    }
    
    /// Create video content from data (future extension)
    public static func video(_ data: Data, format: AIVideoContent.AIVideoFormat = .auto, thumbnail: Data? = nil) -> AIContentPart {
        return .video(AIVideoContent(data: data, format: format, thumbnail: thumbnail))
    }
    
    /// Create video content from URL (future extension)
    public static func videoURL(_ url: URL, format: AIVideoContent.AIVideoFormat = .auto, thumbnail: Data? = nil) -> AIContentPart {
        return .video(AIVideoContent(url: url, format: format, thumbnail: thumbnail))
    }
    
    /// Create JSON content from object
    public static func jsonObject<T: Encodable>(_ object: T) throws -> AIContentPart {
        let data = try JSONEncoder().encode(object)
        return .json(data)
    }
}

// MARK: - Utility Extensions

extension AIInputMessage {
    /// Get the text content from this message (concatenated if multiple text parts)
    public var textContent: String {
        return content.compactMap { contentPart in
            if case .text(let text) = contentPart {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }
    
    /// Check if this message contains any images
    public var hasImages: Bool {
        return content.contains { contentPart in
            if case .image = contentPart { return true }
            return false
        }
    }
    
    /// Check if this message contains any audio
    public var hasAudio: Bool {
        return content.contains { contentPart in
            if case .audio = contentPart { return true }
            return false
        }
    }
    
    /// Check if this message contains any files
    public var hasFiles: Bool {
        return content.contains { contentPart in
            if case .file = contentPart { return true }
            return false
        }
    }

    /// Check if this message contains any video
    public var hasVideo: Bool {
        return content.contains { contentPart in
            if case .video = contentPart { return true }
            return false
        }
    }
    
    /// Get all images from this message
    public var images: [AIImageContent] {
        return content.compactMap { contentPart in
            if case .image(let imageContent) = contentPart {
                return imageContent
            }
            return nil
        }
    }
    
    /// Get all audio from this message
    public var audio: [AIAudioContent] {
        return content.compactMap { contentPart in
            if case .audio(let audioContent) = contentPart {
                return audioContent
            }
            return nil
        }
    }
    
    /// Get all files from this message
    public var files: [AIFileContent] {
        return content.compactMap { contentPart in
            if case .file(let fileContent) = contentPart {
                return fileContent
            }
            return nil
        }
    }

    /// Get all videos from this message
    public var videos: [AIVideoContent] {
        return content.compactMap { contentPart in
            if case .video(let videoContent) = contentPart {
                return videoContent
            }
            return nil
        }
    }
}

// MARK: - Codable Support

extension AIInputMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case role, content, name, toolCalls, toolCallId
    }
}

extension AIMessageRole: Codable {}

extension AIContentPart: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, value
    }
    
    private enum ContentType: String, Codable {
        case text, image, audio, file, video, json, html, markdown
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)
        
        switch type {
        case .text:
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value)
        case .image:
            let value = try container.decode(AIImageContent.self, forKey: .value)
            self = .image(value)
        case .audio:
            let value = try container.decode(AIAudioContent.self, forKey: .value)
            self = .audio(value)
        case .file:
            let value = try container.decode(AIFileContent.self, forKey: .value)
            self = .file(value)
        case .video:
            let value = try container.decode(AIVideoContent.self, forKey: .value)
            self = .video(value)
        case .json:
            let value = try container.decode(Data.self, forKey: .value)
            self = .json(value)
        case .html:
            let value = try container.decode(String.self, forKey: .value)
            self = .html(value)
        case .markdown:
            let value = try container.decode(String.self, forKey: .value)
            self = .markdown(value)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let value):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(value, forKey: .value)
        case .image(let value):
            try container.encode(ContentType.image, forKey: .type)
            try container.encode(value, forKey: .value)
        case .audio(let value):
            try container.encode(ContentType.audio, forKey: .type)
            try container.encode(value, forKey: .value)
        case .file(let value):
            try container.encode(ContentType.file, forKey: .type)
            try container.encode(value, forKey: .value)
        case .video(let value):
            try container.encode(ContentType.video, forKey: .type)
            try container.encode(value, forKey: .value)
        case .json(let value):
            try container.encode(ContentType.json, forKey: .type)
            try container.encode(value, forKey: .value)
        case .html(let value):
            try container.encode(ContentType.html, forKey: .type)
            try container.encode(value, forKey: .value)
        case .markdown(let value):
            try container.encode(ContentType.markdown, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

extension AIImageContent: Codable {}
extension AIImageContent.AIImageDetail: Codable {}

extension AIAudioContent: Codable {}
extension AIAudioContent.AIAudioFormat: Codable {}

extension AIFileContent: Codable {}
extension AIFileContent.AIFileType: Codable {}

extension AIVideoContent: Codable {}
extension AIVideoContent.AIVideoFormat: Codable {}

extension AIToolCall: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, arguments
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        
        // Handle [String: Any] decoding
        let argumentsData = try container.decode(Data.self, forKey: .arguments)
        arguments = try JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] ?? [:]
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        
        // Handle [String: Any] encoding
        let argumentsData = try JSONSerialization.data(withJSONObject: arguments)
        try container.encode(argumentsData, forKey: .arguments)
    }
} 
