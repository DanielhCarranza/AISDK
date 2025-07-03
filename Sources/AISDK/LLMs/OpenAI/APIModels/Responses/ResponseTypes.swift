//
//  ResponseTypes.swift
//  AISDK
//
//  Simplified Response wrappers for clean API surface
//  Wraps existing ResponseObject and ResponseStreamEvent with developer-friendly interface
//

import Foundation

// MARK: - Simplified Response

/// Clean, simplified response wrapper around ResponseObject
public struct Response {
    /// Most common access - main response text
    public let text: String?
    
    /// Multimodal content parts (text, images, audio, files)
    public let content: [AIContentPart]
    
    /// Citations and annotations (using existing ResponseAnnotation)
    public let annotations: [ResponseAnnotation]
    
    /// Response metadata
    public let id: String
    public let model: String
    public let status: ResponseStatus
    public let usage: ResponseUsage?
    
    /// Advanced Response API features
    public let isBackground: Bool
    public let reasoning: ResponseReasoning?
    public let previousResponseId: String?
    
    /// For agent integration - convert back to conversation format
    public let conversationMessage: AIInputMessage
    
    /// Full access to original response for advanced usage
    public let raw: ResponseObject
    
    /// Initialize from existing ResponseObject
    public init(from responseObject: ResponseObject) {
        self.raw = responseObject
        self.id = responseObject.id
        self.model = responseObject.model
        self.status = responseObject.status
        self.usage = responseObject.usage
        self.isBackground = responseObject.status == .inProgress || responseObject.status == .queued
        self.reasoning = responseObject.reasoning
        self.previousResponseId = responseObject.previousResponseId
        
        // Extract main text using existing outputText computed property
        self.text = responseObject.outputText
        
        // Extract multimodal content parts and convert back to universal types
        self.content = Self.extractContentParts(from: responseObject.output)
        
        // Extract annotations using existing structure
        self.annotations = Self.extractAnnotations(from: responseObject.output)
        
        // Create conversation message for agent integration
        self.conversationMessage = AIInputMessage.assistant(self.content)
    }
    
    // MARK: - Content Extraction Helpers
    
    /// Extract multimodal content parts from ResponseOutputItems
    private static func extractContentParts(from output: [ResponseOutputItem]) -> [AIContentPart] {
        var contentParts: [AIContentPart] = []
        
        for outputItem in output {
            switch outputItem {
            case .message(let message):
                for content in message.content {
                    switch content {
                    case .outputText(let textOutput):
                        if !textOutput.text.isEmpty {
                            contentParts.append(.text(textOutput.text))
                        }
                    case .outputImage(let imageOutput):
                        if let imageUrl = imageOutput.imageUrl {
                            contentParts.append(.image(AIImageContent(url: URL(string: imageUrl))))
                        } else if let fileId = imageOutput.fileId {
                            // Handle file ID case - could be converted to URL or handled differently
                            contentParts.append(.text("[Generated image file: \(fileId)]"))
                        }
                    }
                }
            case .functionCall, .functionCallOutput, .webSearchCall, .imageGenerationCall, .codeInterpreterCall:
                // Tool calls are metadata, not content - could be exposed separately if needed
                break
            case .mcpApprovalRequest:
                // MCP approval requests are metadata, not content
                break
            }
        }
        
        return contentParts
    }
    
    /// Extract annotations from ResponseOutputItems
    private static func extractAnnotations(from output: [ResponseOutputItem]) -> [ResponseAnnotation] {
        var annotations: [ResponseAnnotation] = []
        
        for outputItem in output {
            if case .message(let message) = outputItem {
                for content in message.content {
                    if case .outputText(let textOutput) = content,
                       let textAnnotations = textOutput.annotations {
                        annotations.append(contentsOf: textAnnotations)
                    }
                }
            }
        }
        
        return annotations
    }
}

// MARK: - Simplified Streaming Response

/// Clean, simplified streaming chunk wrapper around existing ResponseChunk
public struct SimpleResponseChunk {
    /// Text delta for streaming text generation
    public let text: String?
    
    /// Event type for different streaming events
    public let eventType: String
    
    /// Whether this chunk indicates completion
    public let isComplete: Bool
    
    /// Tool call information (if applicable)
    public let toolCall: ToolCallInfo?
    
    /// Reasoning step information (if applicable) 
    public let reasoning: String?
    
    /// Error information (if applicable)
    public let error: ErrorInfo?
    
    /// Response ID
    public let id: String
    
    /// Response status
    public let status: ResponseStatus?
    
    /// Full access to original chunk
    public let raw: ResponseChunk
    
    /// Initialize from existing ResponseChunk (from provider streaming)
    public init(from chunk: ResponseChunk) {
        self.raw = chunk
        self.id = chunk.id
        self.eventType = chunk.object
        self.status = chunk.status
        
        // Extract text delta
        self.text = chunk.delta?.outputText ?? chunk.delta?.text
        
        // Determine if complete based on status
        self.isComplete = chunk.status?.isFinal == true
        
        // Tool call info would be extracted from output items if present
        self.toolCall = nil // Could be enhanced based on actual chunk structure
        
        // Extract reasoning
        self.reasoning = chunk.delta?.reasoning?.summary
        
        // Extract error info
        if let error = chunk.error {
            self.error = ErrorInfo(code: error.code ?? "unknown", message: error.message ?? "Unknown error")
        } else {
            self.error = nil
        }
    }
}

// MARK: - Supporting Types

/// Simplified tool call information
public struct ToolCallInfo {
    public let name: String
    public let arguments: String?
    public let result: String?
    
    /// Extract tool call info from ResponseOutputItem
    static func extractFrom(_ item: ResponseOutputItem) -> ToolCallInfo? {
        switch item {
        case .functionCall(let functionCall):
            return ToolCallInfo(name: functionCall.name, arguments: functionCall.arguments, result: nil)
        case .functionCallOutput(let output):
            return ToolCallInfo(name: "function", arguments: nil, result: output.output)
        case .webSearchCall(let webSearch):
            return ToolCallInfo(name: "web_search", arguments: webSearch.query, result: webSearch.result)
        case .imageGenerationCall(let imageGen):
            return ToolCallInfo(name: "image_generation", arguments: imageGen.prompt, result: imageGen.result)
        case .codeInterpreterCall(let codeCall):
            return ToolCallInfo(name: "code_interpreter", arguments: codeCall.code, result: codeCall.result)
        default:
            return nil
        }
    }
}

/// Simplified error information
public struct ErrorInfo {
    public let code: String
    public let message: String
} 