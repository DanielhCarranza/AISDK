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
    func toResponseMessage() throws -> ResponseMessage {
        let responseContent = try content.map { try $0.toResponseContentItem() }
        return ResponseMessage(role: role.toResponseRole(), content: responseContent)
    }

    /// Convert to ResponseInputItem for building requests
    func toResponseInputItem() throws -> ResponseInputItem {
        return .message(try toResponseMessage())
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
    func toResponseContentItem() throws -> ResponseContentItem {
        switch self {
        case .text(let text):
            return .inputText(ResponseInputText(text: text))

        case .image(let imageContent):
            return .inputImage(imageContent.toResponseInputImage())

        case .audio:
            throw ProviderError.unsupportedModality(
                modality: "audio",
                provider: "OpenAI Responses",
                supportedProviders: ["Gemini"]
            )

        case .file:
            throw ProviderError.unsupportedModality(
                modality: "file",
                provider: "OpenAI Responses",
                supportedProviders: ["Anthropic (PDF only)", "Gemini"]
            )

        case .video:
            throw ProviderError.unsupportedModality(
                modality: "video",
                provider: "OpenAI Responses",
                supportedProviders: ["Gemini"]
            )

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
            // Use URL if available
            return ResponseInputImage(imageUrl: url.absoluteString)
        } else if let imageData = data {
            // Convert image data to base64 data URL — the Responses API accepts data URLs for input_image.image_url
            let base64String = imageData.base64EncodedString()
            let dataUrl = "data:\(mimeType);base64,\(base64String)"
            return ResponseInputImage(imageUrl: dataUrl)
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
    func toResponseInputItems() throws -> [ResponseInputItem] {
        return try map { try $0.toResponseInputItem() }
    }

    /// Convert array of universal messages to ResponseMessages
    func toResponseMessages() throws -> [ResponseMessage] {
        return try map { try $0.toResponseMessage() }
    }
}

extension Array where Element == AIContentPart {
    /// Convert array of content parts to ResponseContentItems
    func toResponseContentItems() throws -> [ResponseContentItem] {
        return try map { try $0.toResponseContentItem() }
    }

    /// Convert to ResponseInput for simple content arrays
    func toResponseInput() throws -> ResponseInput {
        if count == 1, case .text(let text) = first {
            // Single text content - use string format
            return .string(text)
        } else {
            // Multiple content parts - use items format with single message
            let message = ResponseMessage(role: "user", content: try toResponseContentItems())
            return .items([.message(message)])
        }
    }
}

// MARK: - Convenience Helpers

extension AIInputMessage {
    /// Create ResponseInput from this message (for single message requests)
    func toResponseInput() throws -> ResponseInput {
        if role == .user && content.count == 1, case .text(let text) = content.first {
            // Simple text message - use string format
            return .string(text)
        } else {
            // Complex message - use items format
            return .items([try toResponseInputItem()])
        }
    }
}

/// Helper to create ResponseInput from mixed content
public func createResponseInput(from content: [AIContentPart]) throws -> ResponseInput {
    return try content.toResponseInput()
}

/// Helper to create ResponseInput from conversation
public func createResponseInput(from conversation: [AIInputMessage]) throws -> ResponseInput {
    return .items(try conversation.toResponseInputItems())
}

/// Helper to create ResponseInput from single message
public func createResponseInput(from message: AIInputMessage) throws -> ResponseInput {
    return try message.toResponseInput()
}

/// Helper to create ResponseInput from text
public func createResponseInput(from text: String) -> ResponseInput {
    return .string(text)
} 