//
//  ChatSession.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 23/12/24.
//

import Foundation
import FirebaseFirestoreSwift 

struct ChatSession: Identifiable, Codable, Equatable {
    @DocumentID var id: String?
    var createdAt: Date
    var lastModified: Date
    var title: String
    var messages: [ChatMessage]
    
    init(title: String = "New Chat") {
        self.createdAt = Date()
        self.lastModified = Date()
        self.title = title
        self.messages = []
    }
    
    // Custom Codable implementation for ChatMessage
    enum CodingKeys: String, CodingKey {
        case createdAt, lastModified, title, messages
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode required fields
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastModified = try container.decodeIfPresent(Date.self, forKey: .lastModified) ?? createdAt
        title = try container.decode(String.self, forKey: .title)
        
        // Make messages optional with empty array as default
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(title, forKey: .title)
        try container.encode(messages, forKey: .messages)
    }
    
    // Implement Equatable
    static func == (lhs: ChatSession, rhs: ChatSession) -> Bool {
        lhs.id == rhs.id &&
        lhs.createdAt == rhs.createdAt &&
        lhs.lastModified == rhs.lastModified &&
        lhs.title == rhs.title &&
        lhs.messages == rhs.messages
    }
} 
