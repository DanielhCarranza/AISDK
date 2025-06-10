//
//  ChatMessage.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 04/01/25.
//

import Foundation

class ChatMessage: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    var message: Message
    var metadata: ToolMetadata?
    var attachments: [Attachment] = []

    /// Add this property to track partial/streaming state
    /// We do *not* want it persisted in Firestore.
    var isPending: Bool = false
    
    /// Whether this message should be hidden in the UI
    var hidden: Bool = false
    
    init(message: Message, metadata: ToolMetadata? = nil, hidden: Bool = false) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
        self.metadata = metadata
        self.hidden = hidden
    }
    
    // Codable implementation
    enum CodingKeys: String, CodingKey {
        case id, timestamp, message, metadata, attachments, hidden
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        message = try container.decode(Message.self, forKey: .message)
        metadata = try container.decodeIfPresent(AnyToolMetadata.self, forKey: .metadata)?.metadata
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
    }
    
    func encode(to encoder: Encoder) throws {
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
    }
    
    // MARK: - Display Content
    
    /// Returns displayable content for the message
    var displayContent: String {
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
    var images: [ImageSource] {
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
    static func pending(role: Message) -> ChatMessage {
        let message = ChatMessage(message: role)
        message.isPending = true
        return message
    }
}

extension ChatMessage: Equatable {
    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        // Compare the unique identifiers
        lhs.id == rhs.id
    }
}
