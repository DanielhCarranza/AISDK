//
//  AnthropicMessageRequestBody.swift
//
//
//  Created by Lou Zell on 7/25/24.
//

import Foundation

/// All docstrings in this file are from: https://docs.anthropic.com/en/api/messages
public struct AnthropicMessageRequestBody: Encodable {
    // Required

    /// The maximum number of tokens to generate before stopping.
    ///
    /// Note that our models may stop before reaching this maximum. This parameter only specifies the
    /// absolute maximum number of tokens to generate.
    ///
    /// Different models have different maximum values for this parameter. See the 'Max output'
    /// value for each model listed here: https://docs.anthropic.com/en/docs/models-overview
    public let maxTokens: Int

    /// Input messages.
    ///
    /// Our models are trained to operate on alternating user and assistant conversational turns.
    /// When creating a new LegacyMessage, you specify the prior conversational turns with the messages
    /// parameter, and the model then generates the next LegacyMessage in the conversation.
    ///
    /// Each input message must be an object with a role and content. You can specify a single
    /// user-role message, or you can include multiple user and assistant messages. The first
    /// message must always use the user role.
    ///
    /// If the final message uses the assistant role, the response content will continue
    /// immediately from the content in that message. This can be used to constrain part of the
    /// model's response.
    ///
    /// Example with a single user message:
    ///
    ///     [{"role": "user", "content": "Hello, Claude"}]
    ///
    /// Example with multiple conversational turns:
    ///
    ///     [
    ///       {"role": "user", "content": "Hello there."},
    ///       {"role": "assistant", "content": "Hi, I'm Claude. How can I help you?"},
    ///       {"role": "user", "content": "Can you explain LLMs in plain English?"},
    ///     ]
    ///
    /// Example with a partially-filled response from Claude:
    ///
    ///     [
    ///       {"role": "user", "content": "What's the Greek name for Sun? (A) Sol (B) Helios (C) Sun"},
    ///       {"role": "assistant", "content": "The best answer is ("},
    ///     ]
    ///
    /// Starting with Claude 3 models, you can also send image content blocks:
    ///
    ///     {"role": "user", "content": [
    ///       {
    ///         "type": "image",
    ///         "source": {
    ///           "type": "base64",
    ///           "media_type": "image/jpeg",
    ///           "data": "/9j/4AAQSkZJRg...",
    ///         }
    ///       },
    ///       {"type": "text", "text": "What is in this image?"}
    ///     ]}
    ///
    /// See this for more input examples: https://docs.anthropic.com/en/api/messages-examples#vision
    public let messages: [AnthropicInputMessage]

    /// The model that will complete your prompt.
    /// See this resource for a list of model strings you may use:
    /// https://docs.anthropic.com/en/docs/about-claude/models#model-names
    public let model: String


    // Optional
    /// An object describing metadata about the request.
    public let metadata: AnthropicRequestMetadata?

    /// Custom text sequences that will cause the model to stop generating.
    ///
    /// Our models will normally stop when they have naturally completed their turn, which will
    /// result in a response stop_reason of "end_turn".
    ///
    /// If you want the model to stop generating when it encounters custom strings of text, you can
    /// use the stop_sequences parameter. If the model encounters one of the custom sequences, the
    /// response stop_reason value will be "stop_sequence" and the response stop_sequence value
    /// will contain the matched stop sequence.
    public let stopSequences: [String]?

    /// Whether to incrementally stream the response using server-sent events.
    /// See https://docs.anthropic.com/en/api/messages-streaming
    public var stream: Bool?

    /// A system prompt is a way of providing context and instructions to Claude, such as
    /// specifying a particular goal or role. See our guide to system prompts.
    public let system: String?

    /// Amount of randomness injected into the response.
    ///
    /// Defaults to 1.0. Ranges from 0.0 to 1.0. Use temperature closer to 0.0 for analytical /
    /// multiple choice, and closer to 1.0 for creative and generative tasks.
    ///
    /// Note that even with temperature of 0.0, the results will not be fully deterministic.
    public let temperature: Double?

    /// How the model should use the provided tools. The model can use a specific tool, any available tool, or decide by itself.
    /// More information here: https://docs.anthropic.com/en/docs/build-with-claude/tool-use
    public let toolChoice: AnthropicToolChoice?

    /// Definitions of tools that the model may use.
    ///
    /// If you include tools in your API request, the model may return `tool_use` content blocks that
    /// represent the model's use of those tools. You can then run those tools using the tool input
    /// generated by the model and then optionally return results back to the model using
    /// `tool_result` content blocks.
    ///
    /// Each tool definition includes:
    ///
    /// - name: Name of the tool.
    /// - description: Optional, but strongly-recommended description of the tool.
    /// - input_schema: JSON schema for the tool input shape that the model will produce in tool_use output content blocks.
    ///
    /// For example, if you defined tools as:
    ///
    ///     [
    ///       {
    ///         "name": "get_stock_price",
    ///         "description": "Get the current stock price for a given ticker symbol.",
    ///         "input_schema": {
    ///           "type": "object",
    ///           "properties": {
    ///             "ticker": {
    ///               "type": "string",
    ///               "description": "The stock ticker symbol, e.g. AAPL for Apple Inc."
    ///             }
    ///           },
    ///           "required": ["ticker"]
    ///         }
    ///       }
    ///     ]
    ///
    /// And then asked the model "What's the S&P 500 at today?", the model might produce tool_use
    /// content blocks in the response like this:
    ///
    ///     [
    ///       {
    ///         "type": "tool_use",
    ///         "id": "toolu_01D7FLrfh4GYq7yT1ULFeyMV",
    ///         "name": "get_stock_price",
    ///         "input": { "ticker": "^GSPC" }
    ///       }
    ///     ]
    ///
    /// You might then run your get_stock_price tool with {"ticker": "^GSPC"} as an input, and
    /// return the following back to the model in a subsequent user message:
    ///
    ///     [
    ///       {
    ///         "type": "tool_result",
    ///         "tool_use_id": "toolu_01D7FLrfh4GYq7yT1ULFeyMV",
    ///         "content": "259.75 USD"
    ///       }
    ///     ]
    ///
    /// Tools can be used for workflows that include running client-side tools and functions, or
    /// more generally whenever you want the model to produce a particular JSON structure of
    /// output.
    ///
    /// See this guide for more details: https://docs.anthropic.com/en/docs/tool-use
    public var tools: [AnthropicTool]?

    /// Only sample from the top K options for each subsequent token.
    ///
    /// Used to remove "long tail" low probability responses.
    /// Learn more technical details here: https://towardsdatascience.com/how-to-sample-from-language-models-682bceb97277
    ///
    /// Recommended for advanced use cases only. You usually only need to use `temperature`.
    public let topK: Int?

    /// Use nucleus sampling.
    ///
    /// In nucleus sampling, we compute the cumulative distribution over all the options for each
    /// subsequent token in decreasing probability order and cut it off once it reaches a
    /// particular probability specified by `top_p`.
    ///
    /// You should either alter `temperature` or `top_p`, but not both.
    ///
    /// Recommended for advanced use cases only. You usually only need to use `temperature`.
    public let topP: Double?

    /// Extended thinking configuration for complex reasoning tasks
    /// When enabled, Claude will use internal reasoning before providing responses
    /// Supported by Claude Opus 4, Claude Sonnet 4, and Claude Sonnet 3.7+
    public var thinking: AnthropicThinkingConfigParam?

    /// MCP (Model Context Protocol) servers to connect to
    /// Enables connecting to remote MCP servers that provide tools and context
    /// Requires the "mcp-client-2025-11-20" beta header
    public var mcpServers: [MCPServerConfig]?

    /// Container configuration for skill execution
    /// Requires the "skills-2025-10-02" beta header
    public var container: ContainerConfig?

    /// Response format for structured outputs
    /// When specified, Claude will format its response according to the given structure
    /// Supports JSON object mode and JSON schema validation
    public let responseFormat: AnthropicResponseFormat?

    // MARK: - Beta Features
    
    /// Enable token-efficient tool use (saves 14% tokens on average)
    /// This is a beta feature for Claude Sonnet 3.7 only
    /// Requires "anthropic-beta: token-efficient-tools-2025-02-19" header
    public var enableTokenEfficientTools: Bool = false
    
    /// Disable parallel tool use - tools will be called sequentially
    /// Note: Token-efficient tools currently don't work with this disabled
    public var disableParallelToolUse: Bool = false
    
    /// Enable chain of thought reasoning for better tool usage
    /// Claude will use <thinking></thinking> tags before tool calls
    public var enableChainOfThought: Bool = true

    /// Returns true if this message request requires the pdf beta header to be applied
    public var needsPDFBeta: Bool {
        for msg in self.messages {
            for content in msg.content {
                if case .pdf(_) = content {
                    return true
                }
            }
        }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        // Required
        case maxTokens = "max_tokens"
        case messages
        case model

        // Optional
        case metadata
        case stopSequences = "stop_sequences"
        case stream
        case system
        case temperature
        case toolChoice = "tool_choice"
        case tools
        case topK = "top_k"
        case topP = "top_p"
        case thinking
        case mcpServers = "mcp_servers"
        case container
        case responseFormat = "response_format"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Required fields
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(messages, forKey: .messages)
        try container.encode(model, forKey: .model)
        
        // Optional fields
        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encodeIfPresent(stopSequences, forKey: .stopSequences)
        try container.encodeIfPresent(stream, forKey: .stream)
        try container.encodeIfPresent(system, forKey: .system)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topK, forKey: .topK)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(thinking, forKey: .thinking)
        try container.encodeIfPresent(mcpServers, forKey: .mcpServers)
        try container.encodeIfPresent(self.container, forKey: .container)
        try container.encodeIfPresent(responseFormat, forKey: .responseFormat)
        
        // Handle tool choice with conditional encoding based on beta features
        if let toolChoice = toolChoice {
            try container.encode(toolChoice, forKey: .toolChoice)
        }
        
        // Handle tools with conditional encoding
        if let tools = tools {
            try container.encode(tools, forKey: .tools)
        }
        
        // Note: Beta features (enableTokenEfficientTools, disableParallelToolUse, enableChainOfThought)
        // are handled via HTTP headers in AnthropicService, not in the request body
    }

    /// Validate the request for provider-specific constraints
    public func validate() throws {
        if let thinking {
            try thinking.validate(maxTokens: maxTokens)
        }
    }

    // This memberwise initializer is autogenerated.
    // To regenerate, use `cmd-shift-a` > Generate Memberwise Initializer
    // To format, place the cursor in the initializer's parameter list and use `ctrl-m`
    public init(
        maxTokens: Int,
        messages: [AnthropicInputMessage],
        model: String,
        metadata: AnthropicRequestMetadata? = nil,
        stopSequences: [String]? = nil,
        stream: Bool? = nil,
        system: String? = nil,
        temperature: Double? = nil,
        toolChoice: AnthropicToolChoice? = nil,
        tools: [AnthropicTool]? = nil,
        topK: Int? = nil,
        topP: Double? = nil,
        thinking: AnthropicThinkingConfigParam? = nil,
        mcpServers: [MCPServerConfig]? = nil,
        container: ContainerConfig? = nil,
        responseFormat: AnthropicResponseFormat? = nil
    ) {
        self.maxTokens = maxTokens
        self.messages = messages
        self.model = model
        self.metadata = metadata
        self.stopSequences = stopSequences
        self.stream = stream
        self.system = system
        self.temperature = temperature
        self.toolChoice = toolChoice
        self.tools = tools
        self.topK = topK
        self.topP = topP
        self.thinking = thinking
        self.mcpServers = mcpServers
        self.container = container
        self.responseFormat = responseFormat
    }
}

/// Response format options for Anthropic structured outputs
/// 
/// Anthropic doesn't natively support response_format in their API like OpenAI,
/// but we can simulate structured outputs by modifying the system prompt to
/// instruct Claude to respond in specific formats.
public enum AnthropicResponseFormat: Encodable {
    case text
    case jsonObject
    case jsonSchema(
        name: String,
        description: String? = nil,
        schemaBuilder: any SchemaBuilding,
        strict: Bool? = nil
    )
    
    /// Get the system prompt modification needed for this response format
    public var systemPromptAddition: String? {
        switch self {
        case .text:
            return nil
        case .jsonObject:
            return "You must respond with valid JSON only. Do not include any explanatory text outside the JSON structure."
        case .jsonSchema(let name, let description, let schemaBuilder, _):
            let schema = schemaBuilder.build()
            let schemaDescription = description ?? "structured data"
            
            // Convert JSONSchema to a readable format for the prompt
            var prompt = "You must respond with valid JSON that matches this exact schema for \(schemaDescription):\n\n"
            
            // Add schema information to the prompt
            if let schemaData = try? JSONSerialization.data(withJSONObject: schema.rawValue, options: .prettyPrinted),
               let schemaString = String(data: schemaData, encoding: .utf8) {
                prompt += "Schema:\n\(schemaString)\n\n"
            }
            
            prompt += "Respond ONLY with valid JSON that conforms to this schema. Do not include any explanatory text."
            return prompt
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        // For Anthropic, we don't actually send this in the request body
        // Instead, we use it to modify the system prompt
        var container = encoder.singleValueContainer()
        switch self {
        case .text:
            try container.encode("text")
        case .jsonObject:
            try container.encode("json_object")
        case .jsonSchema(let name, _, _, _):
            try container.encode("json_schema:\(name)")
        }
    }
}

public enum AnthropicImageMediaType: String {
    case jpeg = "image/jpeg"
    case png = "image/png"
    case gif = "image/gif"
    case webp = "image/webp"
}


public enum AnthropicInputContent: Encodable {
    case image(mediaType: AnthropicImageMediaType, data: String)
    case pdf(data: String)
    case text(String)
    case imageFile(source: FileImageSource)
    case documentFile(source: FileDocumentSource, title: String? = nil, context: String? = nil)
    case toolUse(id: String, name: String, input: [String: AIProxyJSONValue])
    case toolResult(toolUseId: String, content: String, isError: Bool = false)
    case searchResult(source: String, title: String, content: [AnthropicSearchResultTextBlock], citations: AnthropicSearchResultCitations?, cacheControl: AnthropicCacheControl?)

    private enum CodingKeys: String, CodingKey {
        case image
        case source
        case text
        case type
        case id
        case name
        case input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
        case title
        case context
        case citations
        case cacheControl = "cache_control"
    }

    private enum SourceCodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
        case fileId = "file_id"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .image(mediaType: let mediaType, data: let data):
            try container.encode("image", forKey: .type)
            var nested = container.nestedContainer(keyedBy: SourceCodingKeys.self, forKey: .source)
            try nested.encode("base64", forKey: .type)
            try nested.encode(mediaType.rawValue, forKey: .mediaType)
            try nested.encode(data, forKey: .data)
        case .pdf(data: let data):
            try container.encode("document", forKey: .type)
            var nested = container.nestedContainer(keyedBy: SourceCodingKeys.self, forKey: .source)
            try nested.encode("base64", forKey: .type)
            try nested.encode("application/pdf", forKey: .mediaType)
            try nested.encode(data, forKey: .data)
        case .text(let txt):
            try container.encode("text", forKey: .type)
            try container.encode(txt, forKey: .text)
        case .imageFile(let source):
            try container.encode("image", forKey: .type)
            var nested = container.nestedContainer(keyedBy: SourceCodingKeys.self, forKey: .source)
            try nested.encode("file", forKey: .type)
            try nested.encode(source.fileId, forKey: .fileId)
        case .documentFile(let source, let title, let context):
            try container.encode("document", forKey: .type)
            var nested = container.nestedContainer(keyedBy: SourceCodingKeys.self, forKey: .source)
            try nested.encode("file", forKey: .type)
            try nested.encode(source.fileId, forKey: .fileId)
            if let title {
                try container.encode(title, forKey: .title)
            }
            if let context {
                try container.encode(context, forKey: .context)
            }
        case .toolUse(id: let id, name: let name, input: let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(toolUseId: let toolUseId, content: let content, isError: let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
            if isError {
                try container.encode(true, forKey: .isError)
            }
        case .searchResult(source: let source, title: let title, content: let content, citations: let citations, cacheControl: let cacheControl):
            try container.encode("search_result", forKey: .type)
            try container.encode(source, forKey: .source)
            try container.encode(title, forKey: .title)
            try container.encode(content, forKey: .content)
            if let citations = citations {
                try container.encode(citations, forKey: .citations)
            }
            if let cacheControl = cacheControl {
                try container.encode(cacheControl, forKey: .cacheControl)
            }
        }
    }
}


public struct AnthropicInputMessage: Encodable {
    public init(
        content: [AnthropicInputContent],
        role: AnthropicInputMessageRole
    ) {
        self.content = content
        self.role = role
    }

    /// The content of the input to send to Claude.
    /// Supports text, images, and tools
    public let content: [AnthropicInputContent]

    /// One of `user` or `assistant`.
    /// Note that if you want to include a system prompt, you can use the top-level `system`
    /// parameter on `AnthropicMessageRequestBody`
    public let role: AnthropicInputMessageRole
}


public enum AnthropicInputMessageRole: String, Encodable {
    case assistant
    case user
}


public struct AnthropicRequestMetadata: Encodable {
    /// An external identifier for the user who is associated with the request.
    ///
    /// This should be a uuid, hash value, or other opaque identifier. Anthropic may use this id to
    /// help detect abuse. Do not include any identifying information such as name, email address, or
    /// phone number.
    let userID: String?
}


/// Enhanced tool choice control for Anthropic native API
public enum AnthropicToolChoice: Encodable {
    /// Let Claude decide whether to use tools (default)
    case auto
    /// Force Claude to use any available tool
    case any
    /// Force Claude to use a specific tool
    case tool(name: String)
    /// Disable tools completely for this request
    case none
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .auto:
            try container.encode("auto", forKey: .type)
        case .any:
            try container.encode("any", forKey: .type)
        case .tool(let name):
            try container.encode("tool", forKey: .type)
            try container.encode(name, forKey: .name)
        case .none:
            try container.encode("none", forKey: .type)
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case name
    }
}


// MARK: - Clean Tool Schema Types

/// Anthropic-compatible tool schema structure
public struct AnthropicToolSchema: Codable {
    public let type: String
    public let properties: [String: AnthropicPropertySchema]
    public let required: [String]
    public let additionalProperties: Bool
    
    public init(
        type: String = "object",
        properties: [String: AnthropicPropertySchema],
        required: [String] = [],
        additionalProperties: Bool = false
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.additionalProperties = additionalProperties
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case properties
        case required
        case additionalProperties = "additionalProperties"
    }
}

/// Anthropic-compatible property schema
public struct AnthropicPropertySchema: Codable {
    public let type: String
    public let description: String?
    public let `enum`: [String]?
    public let minimum: Double?
    public let maximum: Double?
    public let minLength: Int?
    public let maxLength: Int?
    public let pattern: String?
    
    public init(
        type: String,
        description: String? = nil,
        enum: [String]? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil,
        minLength: Int? = nil,
        maxLength: Int? = nil,
        pattern: String? = nil
    ) {
        self.type = type
        self.description = description
        self.`enum` = `enum`
        self.minimum = minimum
        self.maximum = maximum
        self.minLength = minLength
        self.maxLength = maxLength
        self.pattern = pattern
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case description
        case `enum` = "enum"
        case minimum
        case maximum
        case minLength = "minLength"
        case maxLength = "maxLength"
        case pattern
    }
}

// MARK: - Conversion Extensions

extension AnthropicToolSchema {
    /// Convert from AISDK ToolSchema to AnthropicToolSchema
    public init(from toolSchema: ToolSchema) {
        guard let function = toolSchema.function else {
            // Fallback for tools without function definition
            self.init(type: "object", properties: [:], required: [])
            return
        }
        
        let anthropicProperties = function.parameters.properties.mapValues { property in
            AnthropicPropertySchema(from: property)
        }
        
        self.init(
            type: "object",
            properties: anthropicProperties,
            required: function.parameters.required ?? [],
            additionalProperties: function.parameters.additionalProperties
        )
    }
}

extension AnthropicPropertySchema {
    /// Convert from AISDK PropertyDefinition to AnthropicPropertySchema
    public init(from property: PropertyDefinition) {
        self.init(
            type: property.type,
            description: property.description,
            enum: property.enumValues,
            minimum: property.minimum,
            maximum: property.maximum,
            minLength: property.minLength,
            maxLength: property.maxLength,
            pattern: property.pattern
        )
    }
}

// MARK: - AnthropicTool

/// Clean, type-safe Anthropic tool definition
public struct AnthropicTool: Encodable {
    /// The tool name
    public let name: String
    
    /// Description of what this tool does
    /// Tool descriptions should be as detailed as possible. The more information that the
    /// model has about what the tool is and how to use it, the better it will perform.
    public let description: String
    
    /// Type-safe JSON schema for this tool's input
    public let inputSchema: AnthropicToolSchema

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
    
    /// Primary initializer: Create from AISDK Tool type
    public init<T: Tool>(from toolType: T.Type) {
        let toolInstance = T()
        self.name = toolInstance.name
        self.description = toolInstance.description
        self.inputSchema = AnthropicToolSchema(from: T.jsonSchema())
    }
    
    /// Direct initializer for custom use cases
    public init(
        name: String,
        description: String,
        inputSchema: AnthropicToolSchema
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

// MARK: - Server-Side Tools Documentation

/**
 * Anthropic Server-Side Tools (Documentation Only)
 * 
 * These tools execute on Anthropic's servers and don't require client implementation.
 * They are automatically executed when Claude decides to use them.
 * 
 * ## Web Search Tool
 * 
 * ### Name: `web_search_20250305`
 * ### Description: Search the web for current information
 * ### Input Schema:
 * ```json
 * {
 *   "type": "object",
 *   "properties": {
 *     "query": {
 *       "type": "string",
 *       "description": "The search query"
 *     }
 *   },
 *   "required": ["query"]
 * }
 * ```
 * 
 * ### Usage:
 * ```swift
 * let webSearchTool = AnthropicTool(
 *     name: "web_search_20250305",
 *     description: "Search the web for current information",
 *     inputSchema: AnthropicToolSchema(
 *         properties: [
 *             "query": AnthropicPropertySchema(
 *                 type: "string",
 *                 description: "The search query"
 *             )
 *         ],
 *         required: ["query"]
 *     )
 * )
 * ```
 * 
 * ### Error Codes:
 * - `too_many_requests`: Rate limit exceeded
 * - `invalid_input`: Invalid search query parameter
 * - `max_uses_exceeded`: Maximum web search tool uses exceeded
 * - `query_too_long`: Query exceeds maximum length
 * - `unavailable`: An internal error occurred
 * 
 * ## Computer Use Tool
 * 
 * ### Name: `computer_20241022`
 * ### Description: Control a computer desktop environment
 * ### Input Schema:
 * ```json
 * {
 *   "type": "object",
 *   "properties": {
 *     "action": {
 *       "type": "string",
 *       "enum": ["screenshot", "click", "type", "key", "scroll", "cursor"]
 *     },
 *     "coordinate": {
 *       "type": "array",
 *       "items": {"type": "integer"}
 *     },
 *     "text": {
 *       "type": "string"
 *     }
 *   },
 *   "required": ["action"]
 * }
 * ```
 * 
 * Note: Computer use requires special setup and permissions.
 * 
 * ## Chain of Thought Constants
 * 
 * ### Prompt Constants for Better Tool Usage:
 * ```swift
 * public struct AnthropicChainOfThought {
 *     public static let toolUsePrompt = """
 *     Before using any tools, think through your approach step by step.
 *     Consider what information you need and which tools would be most effective.
 *     Use <thinking></thinking> tags to show your reasoning.
 *     """
 *     
 *     public static let multiToolPrompt = """
 *     You have access to multiple tools. Think about which tools to use and in what order.
 *     Some tools can be used in parallel, others should be used sequentially.
 *     Explain your reasoning before making tool calls.
 *     """
 * }
 * ```
 */

// MARK: - Search Result Types

/// Search result text block content
public struct AnthropicSearchResultTextBlock: Encodable {
    public let type: String
    public let text: String
    
    public init(text: String) {
        self.type = "text"
        self.text = text
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case text
    }
}

/// Search result citations configuration
public struct AnthropicSearchResultCitations: Encodable {
    public let enabled: Bool
    
    public init(enabled: Bool) {
        self.enabled = enabled
    }
    
    private enum CodingKeys: String, CodingKey {
        case enabled
    }
}

/// Cache control for search results
public struct AnthropicCacheControl: Encodable {
    public let type: String
    
    public init(type: String = "ephemeral") {
        self.type = type
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
    }
}
