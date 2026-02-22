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
public struct ResponseUsage: Codable, Sendable {
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
public struct ResponseInputTokensDetails: Codable, Sendable {
    public let cachedTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }
}

/// Output tokens details
public struct ResponseOutputTokensDetails: Codable, Sendable {
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
    case computerCall(ResponseOutputComputerCall)
    case reasoning(ResponseOutputReasoningItem)
    case mcpCall(ResponseOutputMCPCall)
    case mcpListTools(ResponseOutputMCPListTools)
    /// Unrecognized output type — allows forward compatibility with new API types
    case unknown(String)

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
        case computerCall = "computer_call"
        case reasoning = "reasoning"
        case mcpCall = "mcp_call"
        case mcpListTools = "mcp_list_tools"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)

        guard let type = OutputType(rawValue: typeString) else {
            self = .unknown(typeString)
            return
        }

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
        case .computerCall:
            let computerCall = try ResponseOutputComputerCall(from: decoder)
            self = .computerCall(computerCall)
        case .reasoning:
            let reasoning = try ResponseOutputReasoningItem(from: decoder)
            self = .reasoning(reasoning)
        case .mcpCall:
            let mcpCall = try ResponseOutputMCPCall(from: decoder)
            self = .mcpCall(mcpCall)
        case .mcpListTools:
            let mcpListTools = try ResponseOutputMCPListTools(from: decoder)
            self = .mcpListTools(mcpListTools)
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
        case .computerCall(let computerCall):
            try computerCall.encode(to: encoder)
        case .reasoning(let reasoning):
            try reasoning.encode(to: encoder)
        case .mcpCall(let mcpCall):
            try mcpCall.encode(to: encoder)
        case .mcpListTools(let mcpListTools):
            try mcpListTools.encode(to: encoder)
        case .unknown(let typeString):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeString, forKey: .type)
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

/// Web search call output with optional action detail
public struct ResponseOutputWebSearchCall: Codable {
    public let id: String
    public let type: String = "web_search_call"
    public let query: String?
    public let result: String?
    public let status: String?
    public let action: WebSearchAction?

    public init(id: String, query: String? = nil, result: String? = nil, status: String? = nil, action: WebSearchAction? = nil) {
        self.id = id
        self.query = query
        self.result = result
        self.status = status
        self.action = action
    }
}

/// Structured action detail for web search calls
public struct WebSearchAction: Codable {
    public let type: String
    public let query: String?
    public let queries: [String]?
    public let sources: [ResponseWebSearchSource]?
    public let url: String?
    public let pattern: String?

    public init(type: String, query: String? = nil, queries: [String]? = nil, sources: [ResponseWebSearchSource]? = nil, url: String? = nil, pattern: String? = nil) {
        self.type = type
        self.query = query
        self.queries = queries
        self.sources = sources
        self.url = url
        self.pattern = pattern
    }
}

/// Source from a web search action
public struct ResponseWebSearchSource: Codable {
    public let type: String
    public let url: String

    public init(type: String, url: String) {
        self.type = type
        self.url = url
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

/// Code interpreter call output with structured outputs
public struct ResponseOutputCodeInterpreterCall: Codable {
    public let id: String
    public let type: String = "code_interpreter_call"
    public let code: String?
    public let result: String?
    public let status: String?
    public let containerId: String?
    public let outputs: [CodeInterpreterOutput]?

    public init(id: String, code: String? = nil, result: String? = nil, status: String? = nil, containerId: String? = nil, outputs: [CodeInterpreterOutput]? = nil) {
        self.id = id
        self.code = code
        self.result = result
        self.status = status
        self.containerId = containerId
        self.outputs = outputs
    }

    enum CodingKeys: String, CodingKey {
        case id, type, code, result, status, outputs
        case containerId = "container_id"
    }
}

/// Structured output from code interpreter execution
public enum CodeInterpreterOutput: Codable {
    case logs(CodeInterpreterLogs)
    case image(CodeInterpreterImage)
    case unknown(String)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)

        switch typeString {
        case "logs":
            let logs = try CodeInterpreterLogs(from: decoder)
            self = .logs(logs)
        case "image":
            let image = try CodeInterpreterImage(from: decoder)
            self = .image(image)
        default:
            self = .unknown(typeString)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .logs(let logs):
            try logs.encode(to: encoder)
        case .image(let image):
            try image.encode(to: encoder)
        case .unknown(let typeString):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeString, forKey: .type)
        }
    }
}

/// Log output from code interpreter
public struct CodeInterpreterLogs: Codable {
    public let type: String
    public let logs: String

    public init(logs: String) {
        self.type = "logs"
        self.logs = logs
    }
}

/// Image output from code interpreter
public struct CodeInterpreterImage: Codable {
    public let type: String
    public let url: String

    public init(url: String) {
        self.type = "image"
        self.url = url
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

/// Computer call output item (OpenAI computer use)
public struct ResponseOutputComputerCall: Codable {
    public let id: String
    public let type: String
    public let callId: String
    public let action: ComputerCallAction
    public let pendingSafetyChecks: [PendingSafetyCheck]?
    public let status: String?

    public struct ComputerCallAction: Codable {
        public let type: String
        public let x: Int?
        public let y: Int?
        public let button: String?
        public let text: String?
        public let keys: [String]?
        public let scrollX: Int?
        public let scrollY: Int?
        public let path: [PathPoint]?
        public let ms: Int?

        public init(type: String, x: Int? = nil, y: Int? = nil, button: String? = nil,
                    text: String? = nil, keys: [String]? = nil,
                    scrollX: Int? = nil, scrollY: Int? = nil,
                    path: [PathPoint]? = nil, ms: Int? = nil) {
            self.type = type; self.x = x; self.y = y; self.button = button
            self.text = text; self.keys = keys
            self.scrollX = scrollX; self.scrollY = scrollY
            self.path = path; self.ms = ms
        }

        public struct PathPoint: Codable {
            public let x: Int
            public let y: Int

            public init(x: Int, y: Int) { self.x = x; self.y = y }
        }

        enum CodingKeys: String, CodingKey {
            case type, x, y, button, text, keys, ms, path
            case scrollX = "scroll_x"
            case scrollY = "scroll_y"
        }
    }

    public struct PendingSafetyCheck: Codable {
        public let id: String
        public let code: String
        public let message: String
    }

    enum CodingKeys: String, CodingKey {
        case id, type, status, action
        case callId = "call_id"
        case pendingSafetyChecks = "pending_safety_checks"
    }
}

/// Reasoning output item from o-series models
public struct ResponseOutputReasoningItem: Codable {
    public let id: String
    public let type: String
    /// The actual reasoning text content (when reasoning is visible)
    public let content: [ReasoningTextContent]?
    public let summary: [ReasoningSummaryContent]?
    public let encryptedContent: String?
    public let status: String?

    public init(id: String, content: [ReasoningTextContent]? = nil, summary: [ReasoningSummaryContent]? = nil, encryptedContent: String? = nil, status: String? = nil) {
        self.id = id
        self.type = "reasoning"
        self.content = content
        self.summary = summary
        self.encryptedContent = encryptedContent
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id, type, content, summary, status
        case encryptedContent = "encrypted_content"
    }
}

/// Reasoning text content within a reasoning output
public struct ReasoningTextContent: Codable {
    public let text: String
    public let type: String

    public init(text: String, type: String = "reasoning_text") {
        self.text = text
        self.type = type
    }
}

/// Summary content within a reasoning output
public struct ReasoningSummaryContent: Codable {
    public let text: String
    public let type: String

    public init(text: String, type: String = "summary_text") {
        self.text = text
        self.type = type
    }
}

/// MCP tool call output item
public struct ResponseOutputMCPCall: Codable {
    public let id: String
    public let type: String
    public let name: String
    public let arguments: String
    public let serverLabel: String
    public let output: String?
    public let error: String?
    public let status: String?
    public let approvalRequestId: String?

    public init(
        id: String, name: String, arguments: String, serverLabel: String,
        output: String? = nil, error: String? = nil, status: String? = nil,
        approvalRequestId: String? = nil
    ) {
        self.id = id
        self.type = "mcp_call"
        self.name = name
        self.arguments = arguments
        self.serverLabel = serverLabel
        self.output = output
        self.error = error
        self.status = status
        self.approvalRequestId = approvalRequestId
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, arguments, output, error, status
        case serverLabel = "server_label"
        case approvalRequestId = "approval_request_id"
    }
}

/// MCP list tools output item
public struct ResponseOutputMCPListTools: Codable {
    public let id: String
    public let type: String
    public let serverLabel: String
    public let tools: [MCPToolInfo]?
    public let error: String?

    public init(id: String, serverLabel: String, tools: [MCPToolInfo]? = nil, error: String? = nil) {
        self.id = id
        self.type = "mcp_list_tools"
        self.serverLabel = serverLabel
        self.tools = tools
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case id, type, tools, error
        case serverLabel = "server_label"
    }
}

/// Tool information from MCP list_tools response
public struct MCPToolInfo: Codable {
    public let name: String
    public let description: String?
    public let inputSchema: AnyCodable?

    public init(name: String, description: String? = nil, inputSchema: AnyCodable? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

/// Output content types
public enum ResponseOutputContent: Codable {
    case outputText(ResponseOutputText)
    case outputImage(ResponseOutputImage)
    case refusal(ResponseOutputRefusal)
    /// Unrecognized content type — allows forward compatibility
    case unknown(String)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)

        switch typeString {
        case "output_text":
            let text = try ResponseOutputText(from: decoder)
            self = .outputText(text)
        case "output_image":
            let image = try ResponseOutputImage(from: decoder)
            self = .outputImage(image)
        case "refusal":
            let refusal = try ResponseOutputRefusal(from: decoder)
            self = .refusal(refusal)
        default:
            self = .unknown(typeString)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .outputText(let text):
            try text.encode(to: encoder)
        case .outputImage(let image):
            try image.encode(to: encoder)
        case .refusal(let refusal):
            try refusal.encode(to: encoder)
        case .unknown(let typeString):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeString, forKey: .type)
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

/// Refusal output content (content policy refusal)
public struct ResponseOutputRefusal: Codable {
    public let type: String
    public let refusal: String

    public init(refusal: String) {
        self.type = "refusal"
        self.refusal = refusal
    }
}

/// Polymorphic response annotations
public enum ResponseAnnotation: Codable {
    case urlCitation(URLCitationAnnotation)
    case fileCitation(FileCitationAnnotation)
    case containerFileCitation(ContainerFileCitationAnnotation)
    case filePath(FilePathAnnotation)
    /// Unrecognized annotation type — forward compatibility
    case unknown(String)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)

        switch typeString {
        case "url_citation":
            let annotation = try URLCitationAnnotation(from: decoder)
            self = .urlCitation(annotation)
        case "file_citation":
            let annotation = try FileCitationAnnotation(from: decoder)
            self = .fileCitation(annotation)
        case "container_file_citation":
            let annotation = try ContainerFileCitationAnnotation(from: decoder)
            self = .containerFileCitation(annotation)
        case "file_path":
            let annotation = try FilePathAnnotation(from: decoder)
            self = .filePath(annotation)
        default:
            self = .unknown(typeString)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .urlCitation(let annotation):
            try annotation.encode(to: encoder)
        case .fileCitation(let annotation):
            try annotation.encode(to: encoder)
        case .containerFileCitation(let annotation):
            try annotation.encode(to: encoder)
        case .filePath(let annotation):
            try annotation.encode(to: encoder)
        case .unknown(let typeString):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(typeString, forKey: .type)
        }
    }

    // MARK: - Backward-compatible computed properties

    /// The annotation type string
    public var type: String {
        switch self {
        case .urlCitation(let a): return a.type
        case .fileCitation(let a): return a.type
        case .containerFileCitation(let a): return a.type
        case .filePath(let a): return a.type
        case .unknown(let t): return t
        }
    }

    /// Start index (available on url_citation, container_file_citation)
    public var startIndex: Int? {
        switch self {
        case .urlCitation(let a): return a.startIndex
        case .containerFileCitation(let a): return a.startIndex
        default: return nil
        }
    }

    /// End index (available on url_citation, container_file_citation)
    public var endIndex: Int? {
        switch self {
        case .urlCitation(let a): return a.endIndex
        case .containerFileCitation(let a): return a.endIndex
        default: return nil
        }
    }
}

/// URL citation annotation (from web search results)
public struct URLCitationAnnotation: Codable {
    public let type: String
    public let url: String
    public let title: String?
    public let startIndex: Int
    public let endIndex: Int

    public init(url: String, title: String? = nil, startIndex: Int, endIndex: Int) {
        self.type = "url_citation"
        self.url = url
        self.title = title
        self.startIndex = startIndex
        self.endIndex = endIndex
    }

    enum CodingKeys: String, CodingKey {
        case type, url, title
        case startIndex = "start_index"
        case endIndex = "end_index"
    }
}

/// File citation annotation
public struct FileCitationAnnotation: Codable {
    public let type: String
    public let fileId: String
    public let filename: String?
    public let index: Int?

    public init(fileId: String, filename: String? = nil, index: Int? = nil) {
        self.type = "file_citation"
        self.fileId = fileId
        self.filename = filename
        self.index = index
    }

    enum CodingKeys: String, CodingKey {
        case type, filename, index
        case fileId = "file_id"
    }
}

/// Container file citation annotation
public struct ContainerFileCitationAnnotation: Codable {
    public let type: String
    public let containerId: String
    public let fileId: String
    public let filename: String?
    public let startIndex: Int
    public let endIndex: Int

    public init(containerId: String, fileId: String, filename: String? = nil, startIndex: Int, endIndex: Int) {
        self.type = "container_file_citation"
        self.containerId = containerId
        self.fileId = fileId
        self.filename = filename
        self.startIndex = startIndex
        self.endIndex = endIndex
    }

    enum CodingKeys: String, CodingKey {
        case type, filename
        case containerId = "container_id"
        case fileId = "file_id"
        case startIndex = "start_index"
        case endIndex = "end_index"
    }
}

/// File path annotation
public struct FilePathAnnotation: Codable {
    public let type: String
    public let fileId: String
    public let index: Int?

    public init(fileId: String, index: Int? = nil) {
        self.type = "file_path"
        self.fileId = fileId
        self.index = index
    }

    enum CodingKeys: String, CodingKey {
        case type, index
        case fileId = "file_id"
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
