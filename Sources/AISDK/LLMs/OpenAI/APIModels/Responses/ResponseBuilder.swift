//
//  ResponseBuilder.swift
//  AISDK
//
//  Created by AISDK on 01/01/25.
//

import Foundation

/// Builder pattern for constructing ResponseRequest objects
public class ResponseBuilder {
    private var model: String
    private var input: ResponseInput
    private var instructions: String?
    private var tools: [ResponseTool]?
    private var toolChoice: ToolChoice?
    private var metadata: [String: String]?
    private var temperature: Double?
    private var topP: Double?
    private var maxOutputTokens: Int?
    private var stream: Bool?
    private var background: Bool?
    private var previousResponseId: String?
    private var include: [String]?
    private var store: Bool?
    private var reasoning: ResponseReasoning?
    private var parallelToolCalls: Bool?
    private var serviceTier: String?
    private var user: String?
    private var truncation: String?
    private var text: ResponseTextConfig?
    
    /// Initialize builder with required parameters
    public init(model: String, input: ResponseInput) {
        self.model = model
        self.input = input
    }
    
    /// Initialize builder with text input
    public convenience init(model: String, text: String) {
        self.init(model: model, input: .string(text))
    }
    
    /// Set instructions for the response
    @discardableResult
    public func instructions(_ instructions: String) -> ResponseBuilder {
        self.instructions = instructions
        return self
    }
    
    /// Add tools to the response
    @discardableResult
    public func tools(_ tools: [ResponseTool]) -> ResponseBuilder {
        self.tools = tools
        return self
    }
    
    /// Add a single tool to the response
    @discardableResult
    public func tool(_ tool: ResponseTool) -> ResponseBuilder {
        if self.tools == nil {
            self.tools = []
        }
        self.tools?.append(tool)
        return self
    }
    
    /// Add web search capability
    @discardableResult
    public func withWebSearch() -> ResponseBuilder {
        return tool(.webSearchPreview)
    }
    
    /// Add code interpreter capability
    @discardableResult
    public func withCodeInterpreter() -> ResponseBuilder {
        return tool(.codeInterpreter)
    }
    
    /// Add image generation capability
    @discardableResult
    public func withImageGeneration(partialImages: Int? = nil) -> ResponseBuilder {
        return tool(.imageGeneration(partialImages: partialImages))
    }
    
    /// Add file search capability
    @discardableResult
    public func withFileSearch(vectorStoreId: String) -> ResponseBuilder {
        return tool(.fileSearch(vectorStoreId: vectorStoreId))
    }
    
    /// Set tool choice
    @discardableResult
    public func toolChoice(_ toolChoice: ToolChoice) -> ResponseBuilder {
        self.toolChoice = toolChoice
        return self
    }
    
    /// Set metadata
    @discardableResult
    public func metadata(_ metadata: [String: String]) -> ResponseBuilder {
        self.metadata = metadata
        return self
    }
    
    /// Set temperature
    @discardableResult
    public func temperature(_ temperature: Double) -> ResponseBuilder {
        self.temperature = temperature
        return self
    }
    
    /// Set top-p
    @discardableResult
    public func topP(_ topP: Double) -> ResponseBuilder {
        self.topP = topP
        return self
    }
    
    /// Set max output tokens
    @discardableResult
    public func maxOutputTokens(_ maxOutputTokens: Int) -> ResponseBuilder {
        self.maxOutputTokens = maxOutputTokens
        return self
    }
    
    /// Enable streaming
    @discardableResult
    public func streaming(_ stream: Bool = true) -> ResponseBuilder {
        self.stream = stream
        return self
    }
    
    /// Enable background processing
    @discardableResult
    public func background(_ background: Bool = true) -> ResponseBuilder {
        self.background = background
        return self
    }
    
    /// Set previous response ID for continuation
    @discardableResult
    public func previousResponse(_ responseId: String) -> ResponseBuilder {
        self.previousResponseId = responseId
        return self
    }
    
    /// Set include fields
    @discardableResult
    public func include(_ include: [String]) -> ResponseBuilder {
        self.include = include
        return self
    }
    
    /// Enable storage
    @discardableResult
    public func store(_ store: Bool = true) -> ResponseBuilder {
        self.store = store
        return self
    }
    
    /// Set reasoning
    @discardableResult
    public func reasoning(_ reasoning: ResponseReasoning) -> ResponseBuilder {
        self.reasoning = reasoning
        return self
    }
    
    /// Set parallel tool calls
    @discardableResult
    public func parallelToolCalls(_ parallel: Bool = true) -> ResponseBuilder {
        self.parallelToolCalls = parallel
        return self
    }
    
    /// Set service tier
    @discardableResult
    public func serviceTier(_ serviceTier: String) -> ResponseBuilder {
        self.serviceTier = serviceTier
        return self
    }
    
    /// Set user
    @discardableResult
    public func user(_ user: String) -> ResponseBuilder {
        self.user = user
        return self
    }
    
    /// Set truncation
    @discardableResult
    public func truncation(_ truncation: String) -> ResponseBuilder {
        self.truncation = truncation
        return self
    }
    
    /// Set text configuration
    @discardableResult
    public func text(_ text: ResponseTextConfig) -> ResponseBuilder {
        self.text = text
        return self
    }
    
    /// Build the final ResponseRequest
    public func build() -> ResponseRequest {
        return ResponseRequest(
            model: model,
            input: input,
            instructions: instructions,
            tools: tools,
            toolChoice: toolChoice,
            metadata: metadata,
            temperature: temperature,
            topP: topP,
            maxOutputTokens: maxOutputTokens,
            stream: stream,
            background: background,
            previousResponseId: previousResponseId,
            include: include,
            store: store,
            reasoning: reasoning,
            parallelToolCalls: parallelToolCalls,
            serviceTier: serviceTier,
            user: user,
            truncation: truncation,
            text: text
        )
    }
}

// MARK: - Convenience Extensions

extension ResponseRequest {
    /// Create a builder from this request
    public func toBuilder() -> ResponseBuilder {
        let builder = ResponseBuilder(model: model, input: input)
        
        if let instructions = instructions {
            builder.instructions(instructions)
        }
        if let tools = tools {
            builder.tools(tools)
        }
        if let toolChoice = toolChoice {
            builder.toolChoice(toolChoice)
        }
        if let metadata = metadata {
            builder.metadata(metadata)
        }
        if let temperature = temperature {
            builder.temperature(temperature)
        }
        if let topP = topP {
            builder.topP(topP)
        }
        if let maxOutputTokens = maxOutputTokens {
            builder.maxOutputTokens(maxOutputTokens)
        }
        if let stream = stream {
            builder.streaming(stream)
        }
        if let background = background {
            builder.background(background)
        }
        if let previousResponseId = previousResponseId {
            builder.previousResponse(previousResponseId)
        }
        if let include = include {
            builder.include(include)
        }
        if let store = store {
            builder.store(store)
        }
        if let reasoning = reasoning {
            builder.reasoning(reasoning)
        }
        if let parallelToolCalls = parallelToolCalls {
            builder.parallelToolCalls(parallelToolCalls)
        }
        if let serviceTier = serviceTier {
            builder.serviceTier(serviceTier)
        }
        if let user = user {
            builder.user(user)
        }
        if let truncation = truncation {
            builder.truncation(truncation)
        }
        if let text = text {
            builder.text(text)
        }
        
        return builder
    }
}

// MARK: - Static Factory Methods

extension ResponseBuilder {
    /// Create a simple text request builder
    public static func text(model: String, _ text: String) -> ResponseBuilder {
        return ResponseBuilder(model: model, text: text)
    }
    
    /// Create a web search enabled request builder
    public static func webSearch(model: String, _ text: String) -> ResponseBuilder {
        return ResponseBuilder(model: model, text: text).withWebSearch()
    }
    
    /// Create a code interpreter enabled request builder
    public static func codeInterpreter(model: String, _ text: String) -> ResponseBuilder {
        return ResponseBuilder(model: model, text: text).withCodeInterpreter()
    }
    
    /// Create an image generation enabled request builder
    public static func imageGeneration(model: String, _ text: String) -> ResponseBuilder {
        return ResponseBuilder(model: model, text: text).withImageGeneration()
    }
    
    /// Create a multi-tool enabled request builder
    public static func multiTool(model: String, _ text: String) -> ResponseBuilder {
        return ResponseBuilder(model: model, text: text)
            .withWebSearch()
            .withCodeInterpreter()
            .withImageGeneration()
    }
    
    /// Create a request builder with input items (for multimodal input)
    public static func items(model: String, _ items: [ResponseInputItem]) -> ResponseBuilder {
        return ResponseBuilder(model: model, input: .items(items))
    }
} 