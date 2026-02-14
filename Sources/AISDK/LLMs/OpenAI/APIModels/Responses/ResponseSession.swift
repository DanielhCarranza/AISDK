//
//  ResponseSession.swift
//  AISDK
//
//  Simplified Response API Interface - Phase 1 Implementation
//  Provides clean wrapper around existing ResponseRequest and ResponseObject
//

import Foundation

/// Clean, fluent interface for OpenAI Responses API
/// Wraps existing ResponseRequest/ResponseObject with simplified developer experience
public class ResponseSession {
    private let provider: OpenAIProvider
    private var content: SessionContent
    
    // MARK: - Initialization
    
    /// Initialize with a complete AIInputMessage (for advanced usage)
    public init(provider: OpenAIProvider, message: AIInputMessage) {
        self.provider = provider
        self.content = SessionContent(message: message)
    }
    
    /// Initialize with simple text content
    public init(provider: OpenAIProvider, text: String) {
        self.provider = provider
        self.content = SessionContent(message: .user(text))
    }
    
    /// Initialize with multimodal content parts
    public init(provider: OpenAIProvider, contentParts: [AIContentPart]) {
        self.provider = provider
        self.content = SessionContent(message: .user(contentParts))
    }
    
    /// Initialize with conversation history (for agents)
    public init(provider: OpenAIProvider, conversation: [AIInputMessage]) {
        self.provider = provider
        self.content = SessionContent(conversation: conversation)
    }
    
    // MARK: - Fluent Configuration Methods
    
    /// Set tools for the response - supports mixed syntax
    @discardableResult
    public func tools(_ tools: [any ToolConvertible]) -> ResponseSession {
        content.tools = tools
        return self
    }
    
    /// Enable background processing for long-running tasks
    @discardableResult
    public func background(_ enabled: Bool = true) -> ResponseSession {
        content.backgroundEnabled = enabled
        return self
    }
    
    /// Configure reasoning for deep research tasks
    @discardableResult
    public func reasoning(_ reasoning: ResponseReasoning) -> ResponseSession {
        content.reasoning = reasoning
        return self
    }
    
    /// Set custom instructions
    @discardableResult
    public func instructions(_ instructions: String) -> ResponseSession {
        content.instructions = instructions
        return self
    }
    
    /// Set model to use
    @discardableResult
    public func model(_ model: String) -> ResponseSession {
        content.model = model
        return self
    }
    
    /// Set previous response ID for conversation continuation
    @discardableResult
    public func previousResponse(_ responseId: String) -> ResponseSession {
        content.previousResponseId = responseId
        return self
    }
    
    /// Set temperature for response generation
    @discardableResult
    public func temperature(_ temperature: Double) -> ResponseSession {
        content.temperature = temperature
        return self
    }
    
    /// Set max output tokens
    @discardableResult
    public func maxOutputTokens(_ tokens: Int) -> ResponseSession {
        content.maxOutputTokens = tokens
        return self
    }
    
    // MARK: - Execution Methods
    
    /// Execute the request and return a simplified response
    public func execute() async throws -> Response {
        let request = content.buildResponseRequest()
        let responseObject = try await provider.createResponse(request: request)
        return Response(from: responseObject)
    }
    
    /// Stream the response with simplified events
    public func stream() -> AsyncThrowingStream<SimpleResponseChunk, Error> {
        let request = content.buildResponseRequest(streaming: true)
        let originalStream = provider.createResponseStream(request: request)
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await chunk in originalStream {
                        let simpleChunk = SimpleResponseChunk(from: chunk)
                        continuation.yield(simpleChunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Internal Session Content Management

/// Internal class to manage session configuration and convert to ResponseRequest
internal class SessionContent {
    var message: AIInputMessage?
    var conversation: [AIInputMessage]?
    var tools: [any ToolConvertible] = []
    var backgroundEnabled = false
    var reasoning: ResponseReasoning?
    var instructions: String?
    var model = "gpt-4o"
    var previousResponseId: String?
    var temperature: Double?
    var maxOutputTokens: Int?
    
    init(message: AIInputMessage) {
        self.message = message
    }
    
    init(conversation: [AIInputMessage]) {
        self.conversation = conversation
    }
    

    func buildResponseRequest(streaming: Bool = false) -> ResponseRequest {
        // Convert content to ResponseInput
        let input: ResponseInput
        if let conversation = conversation {
            // Multiple messages for conversation
            let inputItems = conversation.map { $0.toResponseInputItem() }
            input = .items(inputItems)
        } else if let message = message {
            // Single message
            input = .items([message.toResponseInputItem()])
        } else {
            // Fallback to simple text
            input = .string("Hello")
        }
        
        // Convert tools to ResponseTool array
        let convertedTools: [ResponseTool]? = !tools.isEmpty ? tools.map { $0.toResponseTool() } : nil
        
        // Build ResponseRequest directly
        return ResponseRequest(
            model: model,
            input: input,
            instructions: instructions,
            tools: convertedTools,
            toolChoice: nil, // Could be configurable later
            metadata: nil,
            temperature: temperature,
            topP: nil,
            maxOutputTokens: maxOutputTokens,
            stream: streaming,
            background: backgroundEnabled,
            previousResponseId: previousResponseId,
            include: nil,
            store: nil,
            reasoning: reasoning,
            parallelToolCalls: nil,
            serviceTier: nil,
            user: nil,
            truncation: nil,
            text: nil
        )
    }
}

// MARK: - Tool Conversion Protocol

/// Protocol that allows both Tool instances and built-in enum cases to be mixed
public protocol ToolConvertible {
    func toResponseTool() -> ResponseTool
}

/// Make existing Tool protocol conform to ToolConvertible
extension Tool {
    public func toResponseTool() -> ResponseTool {
        // Convert Tool instance to ToolFunction and wrap in ResponseTool.function
        let schema = Self.jsonSchema()
        guard let toolFunction = schema.function else {
            fatalError("Tool \(name) failed to generate ToolFunction from schema")
        }
        return .function(toolFunction)
    }
}

// MARK: - Built-in Tool Enum Cases

/// OpenAI-specific built-in tool enum that can be mixed with custom Tool instances via ResponseSession/ResponseAgent.
/// For provider-agnostic built-in tools, use the core `BuiltInTool` enum in `AITextRequest.builtInTools`.
public enum ResponseBuiltInTool: ToolConvertible {
    case webSearchPreview
    case codeInterpreter  
    case imageGeneration(partialImages: Int? = nil)
    case fileSearch(vectorStoreId: String)
    case mcp(serverLabel: String, serverUrl: String, requireApproval: String? = nil, headers: [String: String]? = nil)
    
    public func toResponseTool() -> ResponseTool {
        switch self {
        case .webSearchPreview:
            return .webSearchPreview
        case .codeInterpreter:
            return .codeInterpreter
        case .imageGeneration(let partialImages):
            return .imageGeneration(partialImages: partialImages)
        case .fileSearch(let vectorStoreId):
            return .fileSearch(vectorStoreIds: [vectorStoreId])
        case .mcp(let serverLabel, let serverUrl, let requireApproval, let headers):
            return .mcp(serverLabel: serverLabel, serverUrl: serverUrl, requireApproval: requireApproval, headers: headers)
        }
    }
} 
