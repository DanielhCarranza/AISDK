//
//  LegacyChatMessage.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 04/01/25.
//

import Foundation

public class LegacyChatMessage: Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public var message: LegacyMessage
    public var metadata: ToolMetadata?
    public var attachments: [Attachment] = []

    /// Add this property to track partial/streaming state
    /// We do *not* want it persisted in Firestore.
    public var isPending: Bool = false
    
    /// Whether this message should be hidden in the UI
    public var hidden: Bool = false

    /// User feedback on an AI (assistant) message. Nil when no feedback provided.
    public var feedback: Feedback?

    // MARK: - Feedback Type

    public enum Feedback: Codable, Equatable {
        case upvote
        case downvote(context: String)

        private enum CodingKeys: String, CodingKey {
            case type, context
        }

        private enum FeedbackType: String, Codable {
            case upvote
            case downvote
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(FeedbackType.self, forKey: .type)
            switch type {
            case .upvote:
                self = .upvote
            case .downvote:
                let context = try container.decode(String.self, forKey: .context)
                self = .downvote(context: context)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .upvote:
                try container.encode(FeedbackType.upvote, forKey: .type)
            case .downvote(let context):
                try container.encode(FeedbackType.downvote, forKey: .type)
                try container.encode(context, forKey: .context)
            }
        }
    }
    
    public init(message: LegacyMessage, metadata: ToolMetadata? = nil, hidden: Bool = false, feedback: Feedback? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
        self.metadata = metadata
        self.hidden = hidden
        self.feedback = feedback
    }
    
    // Codable implementation
    enum CodingKeys: String, CodingKey {
        case id, timestamp, message, metadata, attachments, hidden, feedback
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        message = try container.decode(LegacyMessage.self, forKey: .message)
        metadata = try container.decodeIfPresent(AnyToolMetadata.self, forKey: .metadata)?.metadata
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        feedback = try container.decodeIfPresent(Feedback.self, forKey: .feedback)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(message, forKey: .message)
        if let metadata = metadata {
            try container.encode(AnyToolMetadata(metadata), forKey: .metadata)
        }
        if !attachments.isEmpty {
            try container.encode(attachments, forKey: .attachments)
        }
        if hidden {
            try container.encode(hidden, forKey: .hidden)
        }
        if let feedback = feedback {
            try container.encode(feedback, forKey: .feedback)
        }
    }
    
    // MARK: - Display Content
    
    /// Returns displayable content for the message
    public var displayContent: String {
        switch message {
        case .user(let content, _):
            switch content {
            case .text(let text): return text
            case .parts(let parts):
                // Filter out text-only parts
                return parts.compactMap { part in
                    if case .text(let text) = part { return text }
                    return nil
                }.joined(separator: "\n")
            }
            
        case .assistant(let content, _, _):
            switch content {
            case .text(let text): return text
            case .parts(let parts): return parts.joined(separator: "\n")
            }
            
        case .system(let content, _):
            switch content {
            case .text(let text): return text
            case .parts(let parts): return parts.joined(separator: "\n")
            }
            
        case .tool(let content, _, _):
            return content
            
        case .developer(let content, _):
            switch content {
            case .text(let text): return text
            case .parts(let parts): return parts.joined(separator: "\n")
            }
        }
    }
    
    // MARK: - Media Content
    
    /// Returns any images associated with the message
    public var images: [ImageSource] {
        switch message {
        case .user(let content, _):
            switch content {
            case .parts(let parts):
                return parts.compactMap { part in
                    if case .imageURL(let source, _) = part { return source }
                    return nil
                }
            default: return []
            }
        default: return []
        }
    }
    
    /// Creates a pending message for the given role
    public static func pending(role: LegacyMessage) -> LegacyChatMessage {
        let message = LegacyChatMessage(message: role)
        message.isPending = true
        return message
    }
}

extension LegacyChatMessage: Equatable {
    public static func == (lhs: LegacyChatMessage, rhs: LegacyChatMessage) -> Bool {
        // Compare the unique identifiers
        lhs.id == rhs.id
    }
}
