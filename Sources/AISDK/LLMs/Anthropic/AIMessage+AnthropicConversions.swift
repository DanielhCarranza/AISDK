//
//  AIMessage+AnthropicConversions.swift
//  AISDK
//
//  Conversion extensions from Universal Message System to Anthropic API
//

import Foundation

// MARK: - Anthropic API Conversions

extension AIInputMessage {
    /// Convert universal message to Anthropic Message
    func toAnthropicMessage() -> AnthropicInputMessage {
        let anthropicContent = content.map { $0.toAnthropicContent() }
        return AnthropicInputMessage(
            content: anthropicContent,
            role: role.toAnthropicRole()
        )
    }
}

extension AIMessageRole {
    /// Convert universal role to Anthropic role
    func toAnthropicRole() -> AnthropicInputMessageRole {
        switch self {
        case .user, .system, .tool:
            return .user  // Anthropic only has user/assistant, system goes to top-level system param
        case .assistant:
            return .assistant
        }
    }
}

extension AIContentPart {
    /// Convert universal content part to Anthropic content
    func toAnthropicContent() -> AnthropicInputContent {
        switch self {
        case .text(let text):
            return .text(text)
            
        case .image(let imageContent):
            if let data = imageContent.data {
                let mediaType = AnthropicImageMediaType.fromMimeType(imageContent.mimeType)
                return .image(mediaType: mediaType, data: data.base64EncodedString())
            } else if let url = imageContent.url {
                // Anthropic doesn't support image URLs directly, convert to text description
                return .text("[Image URL not supported in Anthropic API: \(url.absoluteString)]")
            } else {
                fatalError("Image content must have either data or URL")
            }
            
        case .audio(let audioContent):
            // Anthropic doesn't support audio directly
            if let transcript = audioContent.transcript {
                return .text("[Audio transcript: \(transcript)]")
            } else {
                return .text("[Audio content - not supported in Anthropic API]")
            }
            
        case .file(let fileContent):
            if fileContent.type == .pdf, let data = fileContent.data {
                return .pdf(data: data.base64EncodedString())
            } else {
                // Other file types not supported, convert to text description
                return .text("[File: \(fileContent.filename) - type not supported in Anthropic API]")
            }
            
        case .video:
            return .text("[Video content - not supported in Anthropic API]")
            
        case .json(let data):
            return .text(String(data: data, encoding: .utf8) ?? "[Invalid JSON]")
            
        case .html(let html):
            return .text(html)
            
        case .markdown(let markdown):
            return .text(markdown)
        }
    }
}

extension AIToolCall {
    /// Convert to Anthropic tool use format
    func toAnthropicToolUse() -> AnthropicInputContent {
        // Convert arguments to AIProxyJSONValue format
        let jsonValues = arguments.compactMapValues { value in
            AIProxyJSONValue.from(value)
        }
        
        return .toolUse(id: id, name: name, input: jsonValues)
    }
}

// MARK: - Helper Extensions

extension AnthropicImageMediaType {
    static func fromMimeType(_ mimeType: String) -> AnthropicImageMediaType {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg":
            return .jpeg
        case "image/png":
            return .png
        case "image/gif":
            return .gif
        case "image/webp":
            return .webp
        default:
            return .jpeg // Default fallback
        }
    }
}

extension AIProxyJSONValue {
    static func from(_ value: Any) -> AIProxyJSONValue? {
        switch value {
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFNumberIsFloatType(number) {
                return .double(number.doubleValue)
            } else {
                return .int(number.intValue)
            }
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            let jsonArray = array.compactMap { AIProxyJSONValue.from($0) }
            return .array(jsonArray)
        case let dict as [String: Any]:
            let jsonDict = dict.compactMapValues { AIProxyJSONValue.from($0) }
            return .object(jsonDict)
        default:
            return nil
        }
    }
}

// MARK: - Array Conversions

extension Array where Element == AIInputMessage {
    /// Convert array of universal messages to Anthropic Messages
    /// Note: System messages will be filtered out and should be passed separately
    func toAnthropicMessages() -> [AnthropicInputMessage] {
        return compactMap { message in
            // Filter out system messages - they go to top-level system parameter
            if message.role == .system {
                return nil
            }
            return message.toAnthropicMessage()
        }
    }
    
    /// Extract system message content for Anthropic's top-level system parameter
    func extractSystemPrompt() -> String? {
        let systemMessages = filter { $0.role == .system }
        guard !systemMessages.isEmpty else { return nil }
        
        return systemMessages.map { $0.textContent }.joined(separator: "\n")
    }
}

// MARK: - Convenience Helpers

/// Helper to create AnthropicMessageRequestBody from universal messages
public func createAnthropicRequest(
    model: String,
    messages: [AIInputMessage],
    maxTokens: Int = 1000,
    temperature: Double? = nil,
    tools: [AnthropicTool]? = nil
) -> AnthropicMessageRequestBody {
    let anthropicMessages = messages.toAnthropicMessages()
    let systemPrompt = messages.extractSystemPrompt()
    
    return AnthropicMessageRequestBody(
        maxTokens: maxTokens,
        messages: anthropicMessages,
        model: model,
        metadata: nil,
        stopSequences: nil,
        stream: nil,
        system: systemPrompt,
        temperature: temperature,
        toolChoice: nil,
        tools: tools,
        topK: nil,
        topP: nil,
        thinking: nil,
        mcpServers: nil,
        responseFormat: nil
    )
}

/// Helper to create AnthropicMessageRequestBody from single universal message
public func createAnthropicRequest(
    model: String,
    message: AIInputMessage,
    maxTokens: Int = 1000,
    temperature: Double? = nil
) -> AnthropicMessageRequestBody {
    return createAnthropicRequest(
        model: model,
        messages: [message],
        maxTokens: maxTokens,
        temperature: temperature
    )
} 