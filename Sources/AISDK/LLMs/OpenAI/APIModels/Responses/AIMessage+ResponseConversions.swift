//
//  AIMessage+ResponseConversions.swift
//  AISDK
//
//  Conversion extensions from Universal LegacyMessage System to OpenAI Responses API
//

import Foundation

// MARK: - OpenAI Responses API Conversions

extension AIInputMessage {
    /// Convert universal message to ResponseMessage for OpenAI Responses API
    func toResponseMessage() -> ResponseMessage {
        let responseContent = content.map { $0.toResponseContentItem() }
        return ResponseMessage(role: role.toResponseRole(), content: responseContent)
    }
    
    /// Convert to ResponseInputItem for building requests
    func toResponseInputItem() -> ResponseInputItem {
        return .message(toResponseMessage())
    }
}

extension AIMessageRole {
    /// Convert universal role to Response API role string
    func toResponseRole() -> String {
        switch self {
        case .user: return "user"
        case .assistant: return "assistant"
        case .system: return "system"
        case .tool: return "tool"
        }
    }
}

extension AIContentPart {
    /// Convert universal content part to ResponseContentItem
    func toResponseContentItem() -> ResponseContentItem {
        switch self {
        case .text(let text):
            return .inputText(ResponseInputText(text: text))
            
        case .image(let imageContent):
            return .inputImage(imageContent.toResponseInputImage())
            
        case .audio(let audioContent):
            // Audio not supported in current Response API, convert to text description
            let description = audioContent.transcript ?? "[Audio content - not supported in Response API]"
            return .inputText(ResponseInputText(text: description))
            
        case .file(let fileContent):
            // File content not directly supported, convert to text description
            return .inputText(ResponseInputText(text: "[File: \(fileContent.filename) - content not supported in Response API]"))
            
        case .video:
            // Video not supported in current Response API, convert to text description
            return .inputText(ResponseInputText(text: "[Video content - not supported in Response API]"))
            
        case .json(let data):
            let jsonString = String(data: data, encoding: .utf8) ?? "[Invalid JSON]"
            return .inputText(ResponseInputText(text: jsonString))
            
        case .html(let html):
            return .inputText(ResponseInputText(text: html))
            
        case .markdown(let markdown):
            return .inputText(ResponseInputText(text: markdown))
        }
    }
}

// MARK: - Structured Content Conversions

extension AIImageContent {
    /// Convert to ResponseInputImage
    func toResponseInputImage() -> ResponseInputImage {
        if let url = url {
            // Use URL if available (Response API only supports URLs, not direct data)
            return ResponseInputImage(imageUrl: url.absoluteString)
        } else if data != nil {
            // Response API doesn't support direct image data, need to handle differently
            // For now, return a placeholder - in real implementation, would need to upload to file service first
            return ResponseInputImage(imageUrl: nil, fileId: "[Image data needs to be uploaded to file service first]")
        } else {
            fatalError("AIImageContent must have either data or URL")
        }
    }
}

// Note: Audio, file, and tool call conversions are not implemented
// because the current Response API only supports text and image (URL) inputs
// These content types are converted to text descriptions in the main conversion function

// MARK: - Array Conversions

extension Array where Element == AIInputMessage {
    /// Convert array of universal messages to ResponseInputItems
    func toResponseInputItems() -> [ResponseInputItem] {
        return map { $0.toResponseInputItem() }
    }
    
    /// Convert array of universal messages to ResponseMessages
    func toResponseMessages() -> [ResponseMessage] {
        return map { $0.toResponseMessage() }
    }
}

extension Array where Element == AIContentPart {
    /// Convert array of content parts to ResponseContentItems
    func toResponseContentItems() -> [ResponseContentItem] {
        return map { $0.toResponseContentItem() }
    }
    
    /// Convert to ResponseInput for simple content arrays
    func toResponseInput() -> ResponseInput {
        if count == 1, case .text(let text) = first {
            // Single text content - use string format
            return .string(text)
        } else {
            // Multiple content parts - use items format with single message
            let message = ResponseMessage(role: "user", content: toResponseContentItems())
            return .items([.message(message)])
        }
    }
}

// MARK: - Convenience Helpers

extension AIInputMessage {
    /// Create ResponseInput from this message (for single message requests)
    func toResponseInput() -> ResponseInput {
        if role == .user && content.count == 1, case .text(let text) = content.first {
            // Simple text message - use string format
            return .string(text)
        } else {
            // Complex message - use items format
            return .items([toResponseInputItem()])
        }
    }
}

/// Helper to create ResponseInput from mixed content
public func createResponseInput(from content: [AIContentPart]) -> ResponseInput {
    return content.toResponseInput()
}

/// Helper to create ResponseInput from conversation
public func createResponseInput(from conversation: [AIInputMessage]) -> ResponseInput {
    return .items(conversation.toResponseInputItems())
}

/// Helper to create ResponseInput from single message
public func createResponseInput(from message: AIInputMessage) -> ResponseInput {
    return message.toResponseInput()
}

/// Helper to create ResponseInput from text
public func createResponseInput(from text: String) -> ResponseInput {
    return .string(text)
} 