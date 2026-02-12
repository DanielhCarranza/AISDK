//
//  ResponseObject.swift
//  AISDK
//
//  Created by AISDK on 01/01/25.
//

import Foundation

/// Main response object from OpenAI Responses API
public struct ResponseObject: Codable {
    public let id: String
    public let object: String
    public let createdAt: TimeInterval
    public let model: String
    public let status: ResponseStatus
    public let output: [ResponseOutputItem]
    public let usage: ResponseUsage?
    public let previousResponseId: String?
    public let metadata: [String: String]?
    public let incompleteDetails: ResponseIncompleteDetails?
    public let error: ResponseError?
    public let instructions: String?
    public let temperature: Double?
    public let topP: Double?
    public let maxOutputTokens: Int?
    public let toolChoice: ToolChoice?
    public let tools: [ResponseTool]?
    public let parallelToolCalls: Bool?
    public let reasoning: ResponseReasoning?
    public let truncation: String?
    public let text: ResponseTextConfig?
    public let user: String?
    public let store: Bool?
    public let serviceTier: String?
    
    /// Computed property to extract text from the first message output
    public var outputText: String? {
        for outputItem in output {
            if case let .message(message) = outputItem {
                for content in message.content {
                    if case let .outputText(textContent) = content {
                        return textContent.text
                    }
                }
            }
        }
        return nil
    }
    
    enum CodingKeys: String, CodingKey {
        case id, object, model, status, output, usage, metadata, error, instructions, temperature, tools, user, store, reasoning, truncation, text
        case createdAt = "created_at"
        case previousResponseId = "previous_response_id"
        case incompleteDetails = "incomplete_details"
        case topP = "top_p"
        case maxOutputTokens = "max_output_tokens"
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case serviceTier = "service_tier"
    }
}

/// Response status enumeration
public enum ResponseStatus: String, Codable {
    case completed = "completed"
    case inProgress = "in_progress"
    case queued = "queued"
    case failed = "failed"
    case cancelled = "cancelled"
    case incomplete = "incomplete"

    /// Check if the response is still processing
    public var isProcessing: Bool {
        return self == .inProgress || self == .queued
    }

    /// Check if the response is in a final state
    public var isFinal: Bool {
        return self == .completed || self == .failed || self == .cancelled || self == .incomplete
    }
}

/// Usage statistics for the response
public struct ResponseUsage: Codable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int
    public let inputTokensDetails: ResponseInputTokensDetails?
    public let outputTokensDetails: ResponseOutputTokensDetails?
    
    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case inputTokensDetails = "input_tokens_details"
        case outputTokensDetails = "output_tokens_details"
    }
}

/// Input tokens details
public struct ResponseInputTokensDetails: Codable {
    public let cachedTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }
}

/// Output tokens details
public struct ResponseOutputTokensDetails: Codable {
    public let reasoningTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens"
    }
}

/// Incomplete details when response is not complete
public struct ResponseIncompleteDetails: Codable {
    public let reason: String?
    public let type: String?
}

/// Response error information
public struct ResponseError: Codable {
    public let code: String?
    public let message: String?
    public let type: String?
}

/// Reasoning information
public struct ResponseReasoning: Codable {
    public let effort: String?
    public let summary: String?
    
    enum CodingKeys: String, CodingKey {
        case effort, summary
    }
}

/// Output items from the response
public enum ResponseOutputItem: Codable {
    case message(ResponseOutputMessage)
    case functionCall(ResponseOutputFunctionCall)
    case functionCallOutput(ResponseOutputFunctionCallOutput)
    case webSearchCall(ResponseOutputWebSearchCall)
    case imageGenerationCall(ResponseOutputImageGenerationCall)
    case codeInterpreterCall(ResponseOutputCodeInterpreterCall)
    case mcpApprovalRequest(ResponseOutputMCPApprovalRequest)
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    enum OutputType: String, Codable {
        case message = "message"
        case functionCall = "function_call"
        case functionCallOutput = "function_call_output"
        case webSearchCall = "web_search_call"
        case imageGenerationCall = "image_generation_call"
        case codeInterpreterCall = "code_interpreter_call"
        case mcpApprovalRequest = "mcp_approval_request"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(OutputType.self, forKey: .type)
        
        switch type {
        case .message:
            let message = try ResponseOutputMessage(from: decoder)
            self = .message(message)
        case .functionCall:
            let functionCall = try ResponseOutputFunctionCall(from: decoder)
            self = .functionCall(functionCall)
        case .functionCallOutput:
            let output = try ResponseOutputFunctionCallOutput(from: decoder)
            self = .functionCallOutput(output)
        case .webSearchCall:
            let webSearch = try ResponseOutputWebSearchCall(from: decoder)
            self = .webSearchCall(webSearch)
        case .imageGenerationCall:
            let imageGen = try ResponseOutputImageGenerationCall(from: decoder)
            self = .imageGenerationCall(imageGen)
        case .codeInterpreterCall:
            let codeInterpreter = try ResponseOutputCodeInterpreterCall(from: decoder)
            self = .codeInterpreterCall(codeInterpreter)
        case .mcpApprovalRequest:
            let mcpRequest = try ResponseOutputMCPApprovalRequest(from: decoder)
            self = .mcpApprovalRequest(mcpRequest)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let message):
            try message.encode(to: encoder)
        case .functionCall(let functionCall):
            try functionCall.encode(to: encoder)
        case .functionCallOutput(let output):
            try output.encode(to: encoder)
        case .webSearchCall(let webSearch):
            try webSearch.encode(to: encoder)
        case .imageGenerationCall(let imageGen):
            try imageGen.encode(to: encoder)
        case .codeInterpreterCall(let codeInterpreter):
            try codeInterpreter.encode(to: encoder)
        case .mcpApprovalRequest(let mcpRequest):
            try mcpRequest.encode(to: encoder)
        }
    }
}

// MARK: - Output Item Types

/// LegacyMessage output item
public struct ResponseOutputMessage: Codable {
    public let id: String
    public let type: String = "message"
    public let role: String
    public let content: [ResponseOutputContent]
    public let status: String?
    
    public init(id: String, role: String, content: [ResponseOutputContent], status: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.status = status
    }
}

/// Function call output item
public struct ResponseOutputFunctionCall: Codable {
    public let id: String
    public let type: String = "function_call"
    public let name: String
    public let arguments: String
    public let callId: String
    public let status: String?
    
    public init(id: String, name: String, arguments: String, callId: String, status: String? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.callId = callId
        self.status = status
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, name, arguments, status
        case callId = "call_id"
    }
}

/// Function call output result
public struct ResponseOutputFunctionCallOutput: Codable {
    public let id: String
    public let type: String = "function_call_output"
    public let callId: String
    public let output: String
    public let status: String?
    
    public init(id: String, callId: String, output: String, status: String? = nil) {
        self.id = id
        self.callId = callId
        self.output = output
        self.status = status
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, output, status
        case callId = "call_id"
    }
}

/// Web search call output
public struct ResponseOutputWebSearchCall: Codable {
    public let id: String
    public let type: String = "web_search_call"
    public let query: String?
    public let result: String?
    public let status: String?
    
    public init(id: String, query: String? = nil, result: String? = nil, status: String? = nil) {
        self.id = id
        self.query = query
        self.result = result
        self.status = status
    }
}

/// Image generation call output
public struct ResponseOutputImageGenerationCall: Codable {
    public let id: String
    public let type: String = "image_generation_call"
    public let prompt: String?
    public let result: String?
    public let status: String?
    
    public init(id: String, prompt: String? = nil, result: String? = nil, status: String? = nil) {
        self.id = id
        self.prompt = prompt
        self.result = result
        self.status = status
    }
}

/// Code interpreter call output
public struct ResponseOutputCodeInterpreterCall: Codable {
    public let id: String
    public let type: String = "code_interpreter_call"
    public let code: String?
    public let result: String?
    public let status: String?
    
    public init(id: String, code: String? = nil, result: String? = nil, status: String? = nil) {
        self.id = id
        self.code = code
        self.result = result
        self.status = status
    }
}

/// MCP approval request output
public struct ResponseOutputMCPApprovalRequest: Codable {
    public let id: String
    public let type: String = "mcp_approval_request"
    public let name: String
    public let arguments: [String: AnyCodable]
    public let serverLabel: String
    
    public init(id: String, name: String, arguments: [String: AnyCodable], serverLabel: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.serverLabel = serverLabel
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, name, arguments
        case serverLabel = "server_label"
    }
}

/// Output content types
public enum ResponseOutputContent: Codable {
    case outputText(ResponseOutputText)
    case outputImage(ResponseOutputImage)
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    enum ContentType: String, Codable {
        case outputText = "output_text"
        case outputImage = "output_image"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)
        
        switch type {
        case .outputText:
            let text = try ResponseOutputText(from: decoder)
            self = .outputText(text)
        case .outputImage:
            let image = try ResponseOutputImage(from: decoder)
            self = .outputImage(image)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .outputText(let text):
            try text.encode(to: encoder)
        case .outputImage(let image):
            try image.encode(to: encoder)
        }
    }
}

/// Text output content
public struct ResponseOutputText: Codable {
    public let type: String = "output_text"
    public let text: String
    public let annotations: [ResponseAnnotation]?
    
    public init(text: String, annotations: [ResponseAnnotation]? = nil) {
        self.text = text
        self.annotations = annotations
    }
}

/// Image output content
public struct ResponseOutputImage: Codable {
    public let type: String = "output_image"
    public let imageUrl: String?
    public let fileId: String?
    
    public init(imageUrl: String? = nil, fileId: String? = nil) {
        self.imageUrl = imageUrl
        self.fileId = fileId
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case imageUrl = "image_url"
        case fileId = "file_id"
    }
}

/// Response annotations
public struct ResponseAnnotation: Codable {
    public let type: String?
    public let text: String?
    public let startIndex: Int?
    public let endIndex: Int?
    
    enum CodingKeys: String, CodingKey {
        case type, text
        case startIndex = "start_index"
        case endIndex = "end_index"
    }
}

/// Helper type for encoding/decoding arbitrary JSON values
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

extension AnyCodable: Equatable {
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        switch (lhs.value, rhs.value) {
        case (is NSNull, is NSNull):
            return true
        case let (l as Bool, r as Bool):
            return l == r
        case let (l as Int, r as Int):
            return l == r
        case let (l as Double, r as Double):
            return l == r
        case let (l as String, r as String):
            return l == r
        default:
            return false
        }
    }
}

extension AnyCodable: @unchecked Sendable {}
