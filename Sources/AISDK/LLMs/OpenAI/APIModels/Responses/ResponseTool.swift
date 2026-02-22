//
//  ResponseTool.swift
//  AISDK
//
//  Created by AISDK on 01/01/25.
//

import Foundation

/// Built-in tools available in the Responses API
public enum ResponseTool: Codable {
    case webSearchPreview(ResponseWebSearchTool = ResponseWebSearchTool())
    case fileSearch(ResponseFileSearchTool)
    case imageGeneration(ResponseImageGenerationTool = ResponseImageGenerationTool())
    case codeInterpreter(ResponseCodeInterpreterTool = ResponseCodeInterpreterTool())
    case mcp(ResponseMCPTool)
    case computerUsePreview(ResponseComputerUseTool)
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
        case computerUsePreview = "computer_use_preview"
        case function = "function"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ToolType.self, forKey: .type)

        switch type {
        case .webSearchPreview:
            let tool = try ResponseWebSearchTool(from: decoder)
            self = .webSearchPreview(tool)
        case .fileSearch:
            let tool = try ResponseFileSearchTool(from: decoder)
            self = .fileSearch(tool)
        case .imageGeneration:
            let tool = try ResponseImageGenerationTool(from: decoder)
            self = .imageGeneration(tool)
        case .codeInterpreter:
            let tool = try ResponseCodeInterpreterTool(from: decoder)
            self = .codeInterpreter(tool)
        case .mcp:
            let tool = try ResponseMCPTool(from: decoder)
            self = .mcp(tool)
        case .computerUsePreview:
            let tool = try ResponseComputerUseTool(from: decoder)
            self = .computerUsePreview(tool)
        case .function:
            let functionTool = try ResponseFunctionTool(from: decoder)
            self = .function(functionTool.function)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .webSearchPreview(let tool):
            try tool.encode(to: encoder)
        case .fileSearch(let tool):
            try tool.encode(to: encoder)
        case .imageGeneration(let tool):
            try tool.encode(to: encoder)
        case .codeInterpreter(let tool):
            try tool.encode(to: encoder)
        case .mcp(let tool):
            try tool.encode(to: encoder)
        case .computerUsePreview(let tool):
            try tool.encode(to: encoder)
        case .function(let function):
            let tool = ResponseFunctionTool(function: function)
            try tool.encode(to: encoder)
        }
    }
}

// MARK: - Individual Tool Structures

/// Web search preview tool with optional configuration
public struct ResponseWebSearchTool: Codable {
    public let type: String = "web_search_preview"
    public let searchContextSize: String?
    public let userLocation: WebSearchUserLocation?
    public let filters: WebSearchFilters?

    public init(
        searchContextSize: String? = nil,
        userLocation: WebSearchUserLocation? = nil,
        filters: WebSearchFilters? = nil
    ) {
        self.searchContextSize = searchContextSize
        self.userLocation = userLocation
        self.filters = filters
    }

    enum CodingKeys: String, CodingKey {
        case type
        case searchContextSize = "search_context_size"
        case userLocation = "user_location"
        case filters
    }
}

/// Approximate user location for web search
public struct WebSearchUserLocation: Codable {
    public let type: String
    public let city: String?
    public let country: String?
    public let region: String?
    public let timezone: String?

    public init(city: String? = nil, country: String? = nil, region: String? = nil, timezone: String? = nil) {
        self.type = "approximate"
        self.city = city
        self.country = country
        self.region = region
        self.timezone = timezone
    }
}

/// Domain filters for web search
public struct WebSearchFilters: Codable {
    public let allowedDomains: [String]?

    public init(allowedDomains: [String]? = nil) {
        self.allowedDomains = allowedDomains
    }

    enum CodingKeys: String, CodingKey {
        case allowedDomains = "allowed_domains"
    }
}

/// File search tool with ranking options
public struct ResponseFileSearchTool: Codable {
    public let type: String = "file_search"
    public let vectorStoreIds: [String]
    public let maxNumResults: Int?
    public let rankingOptions: ResponseFileSearchRankingOptions?

    public init(
        vectorStoreIds: [String],
        maxNumResults: Int? = nil,
        rankingOptions: ResponseFileSearchRankingOptions? = nil
    ) {
        self.vectorStoreIds = vectorStoreIds
        self.maxNumResults = maxNumResults
        self.rankingOptions = rankingOptions
    }

    enum CodingKeys: String, CodingKey {
        case type
        case vectorStoreIds = "vector_store_ids"
        case maxNumResults = "max_num_results"
        case rankingOptions = "ranking_options"
    }
}

/// Ranking options for file search (Response API tool config)
public struct ResponseFileSearchRankingOptions: Codable {
    public let ranker: String?
    public let scoreThreshold: Double?

    public init(ranker: String? = nil, scoreThreshold: Double? = nil) {
        self.ranker = ranker
        self.scoreThreshold = scoreThreshold
    }

    enum CodingKeys: String, CodingKey {
        case ranker
        case scoreThreshold = "score_threshold"
    }
}

/// Image generation tool with full configuration
public struct ResponseImageGenerationTool: Codable {
    public let type: String = "image_generation"
    public let partialImages: Int?
    public let background: String?
    public let inputFidelity: String?
    public let model: String?
    public let moderation: String?
    public let outputCompression: Int?
    public let outputFormat: String?
    public let quality: String?
    public let size: String?

    public init(
        partialImages: Int? = nil,
        background: String? = nil,
        inputFidelity: String? = nil,
        model: String? = nil,
        moderation: String? = nil,
        outputCompression: Int? = nil,
        outputFormat: String? = nil,
        quality: String? = nil,
        size: String? = nil
    ) {
        self.partialImages = partialImages
        self.background = background
        self.inputFidelity = inputFidelity
        self.model = model
        self.moderation = moderation
        self.outputCompression = outputCompression
        self.outputFormat = outputFormat
        self.quality = quality
        self.size = size
    }

    enum CodingKeys: String, CodingKey {
        case type, background, model, moderation, quality, size
        case partialImages = "partial_images"
        case inputFidelity = "input_fidelity"
        case outputCompression = "output_compression"
        case outputFormat = "output_format"
    }
}

/// Code interpreter tool with container config
public struct ResponseCodeInterpreterTool: Codable {
    public let type: String = "code_interpreter"
    public let container: CodeInterpreterContainerConfig

    public init(container: CodeInterpreterContainerConfig = .auto()) {
        self.container = container
    }
}

/// Code interpreter container configuration
public enum CodeInterpreterContainerConfig: Codable {
    /// Auto-provision a new container with optional file IDs
    case auto(fileIds: [String]? = nil)
    /// Use an existing container by ID
    case id(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            // A plain string is an existing container ID (unless it's "auto" from old format)
            if stringValue == "auto" {
                self = .auto()
            } else {
                self = .id(stringValue)
            }
        } else {
            // Object form: {"type": "auto", "file_ids": [...]}
            let obj = try AutoContainer(from: decoder)
            self = .auto(fileIds: obj.fileIds)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .id(let containerId):
            var container = encoder.singleValueContainer()
            try container.encode(containerId)
        case .auto(let fileIds):
            let obj = AutoContainer(fileIds: fileIds)
            try obj.encode(to: encoder)
        }
    }

    private struct AutoContainer: Codable {
        let type: String
        let fileIds: [String]?

        init(fileIds: [String]? = nil) {
            self.type = "auto"
            self.fileIds = fileIds
        }

        enum CodingKeys: String, CodingKey {
            case type
            case fileIds = "file_ids"
        }
    }
}

/// MCP (Model Context Protocol) tool
public struct ResponseMCPTool: Codable {
    public let type: String = "mcp"
    public let serverLabel: String
    public let serverUrl: String?
    public let requireApproval: String?
    public let headers: [String: String]?
    public let allowedTools: [String]?
    public let connectorId: String?
    public let serverDescription: String?

    public init(
        serverLabel: String,
        serverUrl: String? = nil,
        requireApproval: String? = nil,
        headers: [String: String]? = nil,
        allowedTools: [String]? = nil,
        connectorId: String? = nil,
        serverDescription: String? = nil
    ) {
        self.serverLabel = serverLabel
        self.serverUrl = serverUrl
        self.requireApproval = requireApproval
        self.headers = headers
        self.allowedTools = allowedTools
        self.connectorId = connectorId
        self.serverDescription = serverDescription
    }

    enum CodingKeys: String, CodingKey {
        case type, headers
        case serverLabel = "server_label"
        case serverUrl = "server_url"
        case requireApproval = "require_approval"
        case allowedTools = "allowed_tools"
        case connectorId = "connector_id"
        case serverDescription = "server_description"
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

/// Computer use preview tool
public struct ResponseComputerUseTool: Codable {
    public let type: String = "computer_use_preview"
    public let displayWidth: Int
    public let displayHeight: Int
    public let environment: String?

    public init(displayWidth: Int, displayHeight: Int, environment: String? = nil) {
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.environment = environment
    }

    enum CodingKeys: String, CodingKey {
        case type
        case displayWidth = "display_width"
        case displayHeight = "display_height"
        case environment
    }
}
