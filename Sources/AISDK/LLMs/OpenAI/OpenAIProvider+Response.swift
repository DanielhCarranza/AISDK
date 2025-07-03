//
//  OpenAIProvider+Response.swift
//  AISDK
//
//  Clean Response API extensions for OpenAIProvider
//  Provides simple entry points that wrap the existing complex API
//

import Foundation

// MARK: - Clean Response API Extensions

extension OpenAIProvider {
    
    // MARK: - Main Entry Points
    
    /// Create a response session from a complete AIInputMessage (for advanced usage)
    public func response(_ message: AIInputMessage) -> ResponseSession {
        return ResponseSession(provider: self, message: message)
    }
    
    /// Create a response session from simple text content
    public func response(_ text: String) -> ResponseSession {
        return ResponseSession(provider: self, text: text)
    }
    
    /// Create a response session from multimodal content parts
    public func response(_ contentParts: [AIContentPart]) -> ResponseSession {
        return ResponseSession(provider: self, contentParts: contentParts)
    }
    
    /// Create a response session from conversation history (for agents)
    public func response(conversation: [AIInputMessage]) -> ResponseSession {
        return ResponseSession(provider: self, conversation: conversation)
    }
}

// MARK: - Global Convenience Functions (Optional)

/// Global convenience function for quick text responses
/// Usage: `let response = try await response("Hello", using: provider).execute()`
public func response(_ text: String, using provider: OpenAIProvider) -> ResponseSession {
    return provider.response(text)
}

/// Global convenience function for multimodal responses
/// Usage: `let response = try await response([.text("Hi"), .image(data)], using: provider).execute()`
public func response(_ content: [AIContentPart], using provider: OpenAIProvider) -> ResponseSession {
    return provider.response(content)
} 