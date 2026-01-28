//
//  ResponseTool.swift
//  AISDK
//
//  Created by AISDK on 01/01/25.
//

import Foundation

/// Built-in tools available in the Responses API
public enum ResponseTool: Codable {
    case webSearchPreview
    case fileSearch(vectorStoreId: String)
    case imageGeneration(partialImages: Int? = nil)
    case codeInterpreter
    case mcp(serverLabel: String, serverUrl: String, requireApproval: String? = nil, headers: [String: String]? = nil)
    case function(ToolFunction)
    
    enum CodingKeys: String, CodingKey {
        case type
    }
    
    enum ToolType: String, Codable {
        case webSearchPreview = "web_search_preview"
        case fileSearch = "file_search"
        case imageGeneration = "image_generation"
        case codeInterpreter = "code_interpreter"
        case mcp = "mcp"
        case function = "function"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ToolType.self, forKey: .type)
        
        switch type {
        case .webSearchPreview:
            self = .webSearchPreview
        case .fileSearch:
            let fileSearchTool = try ResponseFileSearchTool(from: decoder)
            self = .fileSearch(vectorStoreId: fileSearchTool.vectorStoreId)
        case .imageGeneration:
            let imageGenTool = try ResponseImageGenerationTool(from: decoder)
            self = .imageGeneration(partialImages: imageGenTool.partialImages)
        case .codeInterpreter:
            self = .codeInterpreter
        case .mcp:
            let mcpTool = try ResponseMCPTool(from: decoder)
            self = .mcp(
                serverLabel: mcpTool.serverLabel,
                serverUrl: mcpTool.serverUrl,
                requireApproval: mcpTool.requireApproval,
                headers: mcpTool.headers
            )
        case .function:
            let functionTool = try ResponseFunctionTool(from: decoder)
            self = .function(functionTool.function)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .webSearchPreview:
            let tool = ResponseWebSearchTool()
            try tool.encode(to: encoder)
        case .fileSearch(let vectorStoreId):
            let tool = ResponseFileSearchTool(vectorStoreId: vectorStoreId)
            try tool.encode(to: encoder)
        case .imageGeneration(let partialImages):
            let tool = ResponseImageGenerationTool(partialImages: partialImages)
            try tool.encode(to: encoder)
        case .codeInterpreter:
            let tool = ResponseCodeInterpreterTool()
            try tool.encode(to: encoder)
        case .mcp(let serverLabel, let serverUrl, let requireApproval, let headers):
            let tool = ResponseMCPTool(
                serverLabel: serverLabel,
                serverUrl: serverUrl,
                requireApproval: requireApproval,
                headers: headers
            )
            try tool.encode(to: encoder)
        case .function(let function):
            let tool = ResponseFunctionTool(function: function)
            try tool.encode(to: encoder)
        }
    }
}

// MARK: - Individual Tool Structures

/// Web search preview tool
public struct ResponseWebSearchTool: Codable {
    public let type: String = "web_search_preview"
    
    public init() {}
}

/// File search tool
public struct ResponseFileSearchTool: Codable {
    public let type: String = "file_search"
    public let vectorStoreId: String
    
    public init(vectorStoreId: String) {
        self.vectorStoreId = vectorStoreId
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case vectorStoreId = "vector_store_id"
    }
}

/// Image generation tool
public struct ResponseImageGenerationTool: Codable {
    public let type: String = "image_generation"
    public let partialImages: Int?
    
    public init(partialImages: Int? = nil) {
        self.partialImages = partialImages
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case partialImages = "partial_images"
    }
}

/// Code interpreter tool
public struct ResponseCodeInterpreterTool: Codable {
    public let type: String = "code_interpreter"
    
    public init() {}
}

/// MCP (Model Context Protocol) tool
public struct ResponseMCPTool: Codable {
    public let type: String = "mcp"
    public let serverLabel: String
    public let serverUrl: String
    public let requireApproval: String?
    public let headers: [String: String]?
    
    public init(
        serverLabel: String,
        serverUrl: String,
        requireApproval: String? = nil,
        headers: [String: String]? = nil
    ) {
        self.serverLabel = serverLabel
        self.serverUrl = serverUrl
        self.requireApproval = requireApproval
        self.headers = headers
    }
    
    enum CodingKeys: String, CodingKey {
        case type
        case serverLabel = "server_label"
        case serverUrl = "server_url"
        case requireApproval = "require_approval"
        case headers
    }
}

/// Function tool (custom functions)
/// Note: The Responses API uses a flat structure where function properties
/// are at the top level, unlike Chat Completions which nests them in "function"
public struct ResponseFunctionTool: Codable {
    public let type: String = "function"
    public let name: String
    public let description: String?
    public let parameters: Parameters
    public let strict: Bool

    public init(function: ToolFunction) {
        self.name = function.name
        self.description = function.description
        self.parameters = function.parameters
        self.strict = function.strict
    }

    public init(name: String, description: String? = nil, parameters: Parameters, strict: Bool = true) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
    }

    /// For decoding, reconstruct the ToolFunction
    public var function: ToolFunction {
        ToolFunction(name: name, description: description, parameters: parameters, strict: strict)
    }
}

 