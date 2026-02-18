//
//  AIMessage+GeminiConversions.swift
//  AISDK
//
//  Conversion extensions from Universal LegacyMessage System to Gemini API
//

import Foundation

// MARK: - Gemini API Conversions

extension AIInputMessage {
    /// Convert universal message to Gemini Content
    func toGeminiContent() -> GeminiGenerateContentRequestBody.Content {
        let geminiParts = content.map { $0.toGeminiPart() }
        return GeminiGenerateContentRequestBody.Content(
            parts: geminiParts,
            role: role.toGeminiRole()
        )
    }
}

extension AIMessageRole {
    /// Convert universal role to Gemini role string
    func toGeminiRole() -> String? {
        switch self {
        case .user, .tool:
            return "user"
        case .assistant:
            return "model"  // Gemini uses "model" for assistant
        case .system:
            return nil  // System goes to systemInstruction, not in content
        }
    }
}

extension AIContentPart {
    /// Convert universal content part to Gemini Part
    func toGeminiPart() -> GeminiGenerateContentRequestBody.Content.Part {
        switch self {
        case .text(let text):
            return .text(text)
            
        case .image(let imageContent):
            if let data = imageContent.data {
                return .inline(data: data, mimeType: imageContent.mimeType)
            } else if let url = imageContent.url {
                return .file(url: url, mimeType: imageContent.mimeType)
            } else {
                fatalError("Image content must have either data or URL")
            }
            
        case .audio(let audioContent):
            if let data = audioContent.data {
                let mimeType = audioContent.format.toGeminiMimeType()
                return .inline(data: data, mimeType: mimeType)
            } else if let url = audioContent.url {
                let mimeType = audioContent.format.toGeminiMimeType()
                return .file(url: url, mimeType: mimeType)
            } else {
                // Fallback to transcript if available
                if let transcript = audioContent.transcript {
                    return .text("[Audio transcript: \(transcript)]")
                } else {
                    return .text("[Audio content - no data or URL provided]")
                }
            }
            
        case .file(let fileContent):
            if let data = fileContent.data {
                return .inline(data: data, mimeType: fileContent.mimeType)
            } else if let url = fileContent.url {
                return .file(url: url, mimeType: fileContent.mimeType)
            } else {
                return .text("[File: \(fileContent.filename) - no data or URL provided]")
            }
            
        case .video(let videoContent):
            if let data = videoContent.data {
                let mimeType = videoContent.format.toGeminiMimeType()
                return .inline(data: data, mimeType: mimeType)
            } else if let url = videoContent.url {
                let mimeType = videoContent.format.toGeminiMimeType()
                return .file(url: url, mimeType: mimeType)
            } else {
                return .text("[Video content - no data or URL provided]")
            }
            
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
    /// Convert to Gemini function call format
    func toGeminiFunctionCall() -> String {
        // Gemini handles tool calls differently - this would need integration with their function calling system
        // For now, convert to text representation
        let argsString = (try? JSONSerialization.data(withJSONObject: arguments))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        
        return "[Function call: \(name) with arguments: \(argsString)]"
    }
}

// MARK: - Helper Extensions

extension AIAudioContent.AIAudioFormat {
    func toGeminiMimeType() -> String {
        switch self {
        case .auto, .mp3:
            return "audio/mpeg"
        case .wav:
            return "audio/wav"
        case .m4a:
            return "audio/mp4"
        case .opus:
            return "audio/opus"
        case .flac:
            return "audio/flac"
        }
    }
}

extension AIVideoContent.AIVideoFormat {
    func toGeminiMimeType() -> String {
        switch self {
        case .auto, .mp4:
            return "video/mp4"
        case .mov:
            return "video/quicktime"
        case .avi:
            return "video/x-msvideo"
        case .webm:
            return "video/webm"
        }
    }
}

// MARK: - Array Conversions

extension Array where Element == AIInputMessage {
    /// Convert array of universal messages to Gemini Contents
    /// Note: System messages will be filtered out and should be passed separately
    func toGeminiContents() -> [GeminiGenerateContentRequestBody.Content] {
        return compactMap { message in
            // Filter out system messages - they go to systemInstruction
            if message.role == .system {
                return nil
            }
            return message.toGeminiContent()
        }
    }
    
    /// Extract system message content for Gemini's systemInstruction
    func extractSystemInstruction() -> GeminiGenerateContentRequestBody.SystemInstruction? {
        let systemMessages = filter { $0.role == .system }
        guard !systemMessages.isEmpty else { return nil }
        
        let systemText = systemMessages.map { $0.textContent }.joined(separator: "\n")
        
        // Create SystemInstruction with text part
        return GeminiGenerateContentRequestBody.SystemInstruction(
            parts: [GeminiGenerateContentRequestBody.Content.Part.text(systemText)]
        )
    }
}

// MARK: - Convenience Helpers

/// Helper to create GeminiGenerateContentRequestBody from universal messages
public func createGeminiRequest(
    messages: [AIInputMessage],
    generationConfig: GeminiGenerateContentRequestBody.GenerationConfig? = nil,
    tools: [GeminiGenerateContentRequestBody.Tool]? = nil,
    cachedContent: String? = nil
) -> GeminiGenerateContentRequestBody {
    let geminiContents = messages.toGeminiContents()
    let systemInstruction = messages.extractSystemInstruction()

    return GeminiGenerateContentRequestBody(
        contents: geminiContents,
        cachedContent: cachedContent,
        generationConfig: generationConfig,
        safetySettings: nil,
        systemInstruction: systemInstruction,
        toolConfig: nil,
        tools: tools
    )
}

/// Helper to create GeminiGenerateContentRequestBody from single universal message
public func createGeminiRequest(
    message: AIInputMessage,
    generationConfig: GeminiGenerateContentRequestBody.GenerationConfig? = nil,
    cachedContent: String? = nil
) -> GeminiGenerateContentRequestBody {
    return createGeminiRequest(
        messages: [message],
        generationConfig: generationConfig,
        cachedContent: cachedContent
    )
}

// MARK: - Extended Types for Gemini

// Note: SystemInstruction is already defined in GeminiGenerateContentRequestBody 