//
//  AIMessage+ChatConversions.swift
//  AISDK
//
//  Conversion extensions from Universal LegacyMessage System to OpenAI Chat Completions API
//

import Foundation

// MARK: - OpenAI Chat Completions API Conversions

extension AIInputMessage {
    /// Convert universal message to Chat Completions LegacyMessage
    func toChatCompletionMessage() throws -> LegacyMessage {
        switch role {
        case .user:
            if content.count == 1, case .text(let text) = content.first {
                return .user(content: .text(text), name: name)
            } else {
                let parts = try content.map { try $0.toUserContentPart() }
                return .user(content: .parts(parts), name: name)
            }
        case .assistant:
            if content.count == 1, case .text(let text) = content.first {
                return .assistant(content: .text(text), name: name, toolCalls: toolCalls?.map { $0.toChatToolCall() })
            } else {
                let texts = content.compactMap { if case .text(let text) = $0 { return text } else { return nil } }
                return .assistant(content: .parts(texts), name: name, toolCalls: toolCalls?.map { $0.toChatToolCall() })
            }
        case .system:
            let text = content.compactMap { if case .text(let text) = $0 { return text } else { return nil } }.joined(separator: "\n")
            return .system(content: .text(text), name: name)
        case .tool:
            let text = content.compactMap { if case .text(let text) = $0 { return text } else { return nil } }.joined(separator: "\n")
            return .tool(content: text, name: name ?? "", toolCallId: toolCallId ?? "")
        }
    }
}

extension AIContentPart {
    /// Convert universal content part to UserContent.Part
    func toUserContentPart() throws -> UserContent.Part {
        switch self {
        case .text(let text):
            return .text(text)
        case .image(let imageContent):
            return imageContent.toUserContentImagePart()
        case .video:
            throw ProviderError.unsupportedModality(
                modality: "video",
                provider: "OpenAI Chat Completions",
                supportedProviders: ["Gemini"]
            )
        case .audio:
            throw ProviderError.unsupportedModality(
                modality: "audio",
                provider: "OpenAI Chat Completions",
                supportedProviders: ["Gemini"]
            )
        case .file:
            throw ProviderError.unsupportedModality(
                modality: "file",
                provider: "OpenAI Chat Completions",
                supportedProviders: ["Anthropic (PDF only)", "Gemini"]
            )
        case .json(let data):
            return .text(String(data: data, encoding: .utf8) ?? "[Invalid JSON]")
        case .html(let html):
            return .text(html)
        case .markdown(let markdown):
            return .text(markdown)
        }
    }
}

extension AIImageContent {
    /// Convert to UserContent.Part for images
    func toUserContentImagePart() -> UserContent.Part {
        if let data = data {
            return .imageURL(.base64(data), detail: detail.toChatImageDetail())
        } else if let url = url {
            return .imageURL(.url(url), detail: detail.toChatImageDetail())
        } else {
            fatalError("AIImageContent must have either data or URL")
        }
    }
}

extension AIImageContent.AIImageDetail {
    /// Convert to Chat Completions ImageDetail
    func toChatImageDetail() -> UserContent.ImageDetail {
        switch self {
        case .auto: return .auto
        case .low: return .low
        case .high: return .high
        }
    }
}

extension AIToolCall {
    /// Convert to Chat Completions tool call format
    func toChatToolCall() -> ChatCompletionResponse.ToolCall {
        let argumentsString = (try? JSONSerialization.data(withJSONObject: arguments))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        
        return ChatCompletionResponse.ToolCall(
            id: id,
            type: "function",
            function: ChatCompletionResponse.ToolFunctionCall(
                name: name,
                arguments: argumentsString
            )
        )
    }
}

// MARK: - Array Conversions

extension Array where Element == AIInputMessage {
    /// Convert array of universal messages to Chat Completions Messages
    func toChatCompletionMessages() throws -> [LegacyMessage] {
        return try map { try $0.toChatCompletionMessage() }
    }
}

// MARK: - Convenience Helpers

/// Helper to create ChatCompletionRequest from universal messages
public func createChatCompletionRequest(
    model: String,
    messages: [AIInputMessage],
    maxTokens: Int? = nil,
    temperature: Double? = nil,
    tools: [ToolSchema]? = nil
) throws -> ChatCompletionRequest {
    return ChatCompletionRequest(
        model: model,
        messages: try messages.toChatCompletionMessages(),
        maxTokens: maxTokens,
        temperature: temperature,
        tools: tools
    )
}

/// Helper to create ChatCompletionRequest from single universal message
public func createChatCompletionRequest(
    model: String,
    message: AIInputMessage,
    maxTokens: Int? = nil,
    temperature: Double? = nil
) throws -> ChatCompletionRequest {
    return ChatCompletionRequest(
        model: model,
        messages: [try message.toChatCompletionMessage()],
        maxTokens: maxTokens,
        temperature: temperature
    )
} 