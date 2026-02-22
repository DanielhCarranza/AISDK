//
//  ResponseRequest.swift
//  AISDK
//
//  Created by AISDK on 01/01/25.
//

import Foundation

/// Request structure for OpenAI Responses API
/// Matches the body for POST /v1/responses
public struct ResponseRequest: Encodable {
    public static let minimumMaxOutputTokens = 16

    // Required
    public let model: String
    public let input: ResponseInput
    
    // Optional parameters
    public var instructions: String?
    public var tools: [ResponseTool]?
    public var toolChoice: ToolChoice?
    public var metadata: [String: String]?
    public var temperature: Double?
    public var topP: Double?
    public var maxOutputTokens: Int?
    public var stream: Bool?
    public var background: Bool?
    public var previousResponseId: String?
    public var include: [String]?
    public var store: Bool?
    public var reasoning: ResponseReasoning?
    public var parallelToolCalls: Bool?
    public var serviceTier: String?
    public var user: String?
    public var truncation: String?
    public var text: ResponseTextConfig?
    
    public init(
        model: String,
        input: ResponseInput,
        instructions: String? = nil,
        tools: [ResponseTool]? = nil,
        toolChoice: ToolChoice? = nil,
        metadata: [String: String]? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxOutputTokens: Int? = nil,
        stream: Bool? = nil,
        background: Bool? = nil,
        previousResponseId: String? = nil,
        include: [String]? = nil,
        store: Bool? = nil,
        reasoning: ResponseReasoning? = nil,
        parallelToolCalls: Bool? = nil,
        serviceTier: String? = nil,
        user: String? = nil,
        truncation: String? = nil,
        text: ResponseTextConfig? = nil
    ) {
        self.model = model
        self.input = input
        self.instructions = instructions
        self.tools = tools
        self.toolChoice = toolChoice
        self.metadata = metadata
        self.temperature = temperature
        self.topP = topP
        self.maxOutputTokens = maxOutputTokens
        self.stream = stream
        self.background = background
        self.previousResponseId = previousResponseId
        self.include = include
        self.store = store
        self.reasoning = reasoning
        self.parallelToolCalls = parallelToolCalls
        self.serviceTier = serviceTier
        self.user = user
        self.truncation = truncation
        self.text = text
    }

    /// Validates known OpenAI Responses API constraints before network submission.
    public func validate() throws {
        if let maxOutputTokens, maxOutputTokens < Self.minimumMaxOutputTokens {
            throw LLMError.invalidRequest(
                "maxOutputTokens must be at least \(Self.minimumMaxOutputTokens) for OpenAI Responses API."
            )
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case model, input, instructions, tools, metadata, temperature, stream, background, include, store, reasoning, truncation, text, user
        case toolChoice = "tool_choice"
        case topP = "top_p"
        case maxOutputTokens = "max_output_tokens"
        case previousResponseId = "previous_response_id"
        case parallelToolCalls = "parallel_tool_calls"
        case serviceTier = "service_tier"
    }
    
    // Custom encoding to handle API requirements properly
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Always encode required fields
        try container.encode(model, forKey: .model)
        try container.encode(input, forKey: .input)
        
        // Encode optional fields only if they have values
        if let instructions = instructions {
            try container.encode(instructions, forKey: .instructions)
        }
        
        if let tools = tools, !tools.isEmpty {
            try container.encode(tools, forKey: .tools)
        }
        
        if let toolChoice = toolChoice {
            try container.encode(toolChoice, forKey: .toolChoice)
        }
        
        if let metadata = metadata, !metadata.isEmpty {
            try container.encode(metadata, forKey: .metadata)
        }
        
        if let temperature = temperature {
            try container.encode(temperature, forKey: .temperature)
        }
        
        if let topP = topP {
            try container.encode(topP, forKey: .topP)
        }
        
        if let maxOutputTokens = maxOutputTokens {
            try container.encode(maxOutputTokens, forKey: .maxOutputTokens)
        }
        
        if let stream = stream {
            try container.encode(stream, forKey: .stream)
        }
        
        if let background = background {
            try container.encode(background, forKey: .background)
        }
        
        if let previousResponseId = previousResponseId {
            try container.encode(previousResponseId, forKey: .previousResponseId)
        }
        
        if let include = include, !include.isEmpty {
            try container.encode(include, forKey: .include)
        }
        
        if let store = store {
            try container.encode(store, forKey: .store)
        }
        
        if let reasoning = reasoning {
            try container.encode(reasoning, forKey: .reasoning)
        }
        
        if let parallelToolCalls = parallelToolCalls {
            try container.encode(parallelToolCalls, forKey: .parallelToolCalls)
        }
        
        if let serviceTier = serviceTier {
            try container.encode(serviceTier, forKey: .serviceTier)
        }
        
        if let user = user {
            try container.encode(user, forKey: .user)
        }
        
        if let truncation = truncation {
            try container.encode(truncation, forKey: .truncation)
        }
        
        if let text = text {
            try container.encode(text, forKey: .text)
        }
    }
}

/// Flexible input structure for Responses API
public enum ResponseInput: Encodable {
    case string(String)
    case items([ResponseInputItem])
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .items(let items):
            try container.encode(items)
        }
    }
}

/// Individual input items for complex requests
public enum ResponseInputItem: Codable {
    case message(ResponseMessage)
    case functionCallOutput(ResponseFunctionCallOutput)
    case computerCallOutput(ResponseComputerCallOutput)
    case computerCall(ResponseInputComputerCall)
    case mcpApprovalResponse(ResponseMCPApprovalResponse)
    case itemReference(ResponseItemReference)

    enum CodingKeys: String, CodingKey {
        case type
    }

    enum ItemType: String, Codable {
        case message = "message"
        case functionCallOutput = "function_call_output"
        case computerCallOutput = "computer_call_output"
        case computerCall = "computer_call"
        case mcpApprovalResponse = "mcp_approval_response"
        case itemReference = "item_reference"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)

        switch type {
        case .message:
            let message = try ResponseMessage(from: decoder)
            self = .message(message)
        case .functionCallOutput:
            let output = try ResponseFunctionCallOutput(from: decoder)
            self = .functionCallOutput(output)
        case .computerCallOutput:
            let output = try ResponseComputerCallOutput(from: decoder)
            self = .computerCallOutput(output)
        case .computerCall:
            let call = try ResponseInputComputerCall(from: decoder)
            self = .computerCall(call)
        case .mcpApprovalResponse:
            let response = try ResponseMCPApprovalResponse(from: decoder)
            self = .mcpApprovalResponse(response)
        case .itemReference:
            let reference = try ResponseItemReference(from: decoder)
            self = .itemReference(reference)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let message):
            try message.encode(to: encoder)
        case .functionCallOutput(let output):
            try output.encode(to: encoder)
        case .computerCallOutput(let output):
            try output.encode(to: encoder)
        case .computerCall(let call):
            try call.encode(to: encoder)
        case .mcpApprovalResponse(let response):
            try response.encode(to: encoder)
        case .itemReference(let reference):
            try reference.encode(to: encoder)
        }
    }
}

/// Computer call input item for re-sending a previous computer_call in multi-turn conversations.
public struct ResponseInputComputerCall: Codable {
    public let type: String
    public let id: String
    public let callId: String
    public let action: ResponseOutputComputerCall.ComputerCallAction
    public let pendingSafetyChecks: [ResponseOutputComputerCall.PendingSafetyCheck]
    public let status: String

    public init(
        id: String,
        callId: String,
        action: ResponseOutputComputerCall.ComputerCallAction,
        pendingSafetyChecks: [ResponseOutputComputerCall.PendingSafetyCheck] = [],
        status: String = "completed"
    ) {
        self.type = "computer_call"
        self.id = id
        self.callId = callId
        self.action = action
        self.pendingSafetyChecks = pendingSafetyChecks
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case type, id, action, status
        case callId = "call_id"
        case pendingSafetyChecks = "pending_safety_checks"
    }
}

/// Item reference for compacted items
public struct ResponseItemReference: Codable {
    public let type: String = "item_reference"
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

/// LegacyMessage input item
public struct ResponseMessage: Codable {
    public let type: String = "message"
    public let role: String
    public let content: [ResponseContentItem]
    
    public init(role: String, content: [ResponseContentItem]) {
        self.role = role
        self.content = content
    }
}

/// Function call output item
public struct ResponseFunctionCallOutput: Codable {
    public let type: String = "function_call_output"
    public let callId: String
    public let output: String
    
    public init(callId: String, output: String) {
        self.callId = callId
        self.output = output
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case callId = "call_id"
        case output
    }
}

/// Computer call output item (result of executing a computer use action)
public struct ResponseComputerCallOutput: Codable {
    public let type: String = "computer_call_output"
    public let callId: String
    public let output: ComputerCallOutputContent
    public let acknowledgedSafetyChecks: [AcknowledgedSafetyCheck]?

    public init(callId: String, output: ComputerCallOutputContent, acknowledgedSafetyChecks: [AcknowledgedSafetyCheck]? = nil) {
        self.callId = callId
        self.output = output
        self.acknowledgedSafetyChecks = acknowledgedSafetyChecks
    }

    public struct ComputerCallOutputContent: Codable {
        public let type: String
        public let imageUrl: String?

        public init(type: String = "computer_screenshot", imageUrl: String? = nil) {
            self.type = type
            self.imageUrl = imageUrl
        }

        enum CodingKeys: String, CodingKey {
            case type
            case imageUrl = "image_url"
        }
    }

    public struct AcknowledgedSafetyCheck: Codable {
        public let id: String
        public let code: String
        public let message: String
    }

    enum CodingKeys: String, CodingKey {
        case type
        case callId = "call_id"
        case output
        case acknowledgedSafetyChecks = "acknowledged_safety_checks"
    }
}

/// MCP approval response item
public struct ResponseMCPApprovalResponse: Codable {
    public let type: String = "mcp_approval_response"
    public let approve: Bool
    public let approvalRequestId: String
    
    public init(approve: Bool, approvalRequestId: String) {
        self.approve = approve
        self.approvalRequestId = approvalRequestId
    }
    
    enum CodingKeys: String, CodingKey {
        case type, approve
        case approvalRequestId = "approval_request_id"
    }
}

/// Content items for messages
public enum ResponseContentItem: Codable {
    case inputText(ResponseInputText)
    case inputImage(ResponseInputImage)
    case inputFile(ResponseInputFile)

    enum CodingKeys: String, CodingKey {
        case type
    }

    enum ContentType: String, Codable {
        case inputText = "input_text"
        case inputImage = "input_image"
        case inputFile = "input_file"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)

        switch type {
        case .inputText:
            let text = try ResponseInputText(from: decoder)
            self = .inputText(text)
        case .inputImage:
            let image = try ResponseInputImage(from: decoder)
            self = .inputImage(image)
        case .inputFile:
            let file = try ResponseInputFile(from: decoder)
            self = .inputFile(file)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .inputText(let text):
            try text.encode(to: encoder)
        case .inputImage(let image):
            try image.encode(to: encoder)
        case .inputFile(let file):
            try file.encode(to: encoder)
        }
    }
}

/// File input content
public struct ResponseInputFile: Codable {
    public let type: String = "input_file"
    public let fileId: String

    public init(fileId: String) {
        self.fileId = fileId
    }

    enum CodingKeys: String, CodingKey {
        case type
        case fileId = "file_id"
    }
}

/// Text input content
public struct ResponseInputText: Codable {
    public let type: String = "input_text"
    public let text: String
    
    public init(text: String) {
        self.text = text
    }
}

/// Image input content
public struct ResponseInputImage: Codable {
    public let type: String = "input_image"
    public let imageUrl: String?
    public let fileId: String?
    public let detail: String?

    public init(imageUrl: String? = nil, fileId: String? = nil, detail: String? = nil) {
        self.imageUrl = imageUrl
        self.fileId = fileId
        self.detail = detail
    }

    enum CodingKeys: String, CodingKey {
        case type
        case imageUrl = "image_url"
        case fileId = "file_id"
        case detail
    }
}

/// Text configuration for response
public struct ResponseTextConfig: Codable {
    public let format: ResponseTextFormat
    
    public init(format: ResponseTextFormat) {
        self.format = format
    }
}

/// Text format configuration
public struct ResponseTextFormat: Codable {
    public let type: String
    public let jsonSchema: ResponseJSONSchema?
    
    public init(type: String, jsonSchema: ResponseJSONSchema? = nil) {
        self.type = type
        self.jsonSchema = jsonSchema
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

/// JSON schema for structured outputs
public struct ResponseJSONSchema: Codable {
    public let name: String?
    public let description: String?
    public let schema: [String: Any]?
    public let strict: Bool?
    
    public init(name: String? = nil, description: String? = nil, schema: [String: Any]? = nil, strict: Bool? = nil) {
        self.name = name
        self.description = description
        self.schema = schema
        self.strict = strict
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(strict, forKey: .strict)

        if let schema = schema {
            // Encode as a raw JSON object (not a string) using AnyCodable round-trip
            let jsonData = try JSONSerialization.data(withJSONObject: schema)
            let rawJSON = try JSONDecoder().decode(AnyCodable.self, from: jsonData)
            try container.encode(rawJSON, forKey: .schema)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        strict = try container.decodeIfPresent(Bool.self, forKey: .strict)
        
        if let schemaString = try container.decodeIfPresent(String.self, forKey: .schema),
           let schemaData = schemaString.data(using: .utf8),
           let schemaDict = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] {
            schema = schemaDict
        } else {
            schema = nil
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case name, description, schema, strict
    }
}

// MARK: - Convenience Extensions

extension ResponseReasoning {
    public static var `default`: ResponseReasoning {
        return ResponseReasoning(effort: nil, summary: nil)
    }
}

extension ResponseTextConfig {
    public static var `default`: ResponseTextConfig {
        return ResponseTextConfig(format: ResponseTextFormat(type: "text"))
    }
} 