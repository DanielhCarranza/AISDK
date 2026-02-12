//
//  AnthropicMessageResponseBody.swift
//
//
//  Created by Lou Zell on 7/28/24.
//

import Foundation

/// All docstrings in this file are from: https://docs.anthropic.com/en/api/messages
public struct AnthropicMessageResponseBody: Decodable {
    public var content: [AnthropicMessageResponseContent]
    public let id: String
    public let model: String
    public let role: String
    public let stopReason: String?
    public let stopSequence: String?
    public let type: String
    public let usage: AnthropicMessageUsage
    
    public init(content: [AnthropicMessageResponseContent], id: String, model: String, role: String, stopReason: String?, stopSequence: String?, type: String, usage: AnthropicMessageUsage) {
        self.content = content
        self.id = id
        self.model = model
        self.role = role
        self.stopReason = stopReason
        self.stopSequence = stopSequence
        self.type = type
        self.usage = usage
    }

    private enum CodingKeys: String, CodingKey {
        case content
        case id
        case model
        case role
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case type
        case usage
    }
}


public enum AnthropicMessageResponseContent: Decodable {
    case text(String, citations: [AnthropicSearchResultCitation]?)
    case toolUse(AnthropicToolUseBlock)
    case mcpToolUse(AnthropicMCPToolUseBlock)
    case mcpToolResult(AnthropicMCPToolResultBlock)
    case thinking(AnthropicThinkingBlock)
    case redactedThinking(AnthropicRedactedThinkingBlock)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case citations
        case id
        case name
        case input
        case serverName = "server_name"
        case toolUseId = "tool_use_id"
        case isError = "is_error"
        case content
        case thinking
        case signature
        case data
    }

    private enum ContentType: String, Decodable {
        case text
        case toolUse = "tool_use"
        case mcpToolUse = "mcp_tool_use"
        case mcpToolResult = "mcp_tool_result"
        case thinking
        case redactedThinking = "redacted_thinking"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)
        switch type {
        case .text:
            let value = try container.decode(String.self, forKey: .text)
            let citations = try container.decodeIfPresent([AnthropicSearchResultCitation].self, forKey: .citations)
            self = .text(value, citations: citations)
        case .toolUse:
            let toolUseBlock = try AnthropicToolUseBlock(from: decoder)
            self = .toolUse(toolUseBlock)
        case .mcpToolUse:
            let mcpToolUseBlock = try AnthropicMCPToolUseBlock(from: decoder)
            self = .mcpToolUse(mcpToolUseBlock)
        case .mcpToolResult:
            let mcpToolResultBlock = try AnthropicMCPToolResultBlock(from: decoder)
            self = .mcpToolResult(mcpToolResultBlock)
        case .thinking:
            let thinkingBlock = try AnthropicThinkingBlock(from: decoder)
            self = .thinking(thinkingBlock)
        case .redactedThinking:
            let redactedBlock = try AnthropicRedactedThinkingBlock(from: decoder)
            self = .redactedThinking(redactedBlock)
        }
    }
}

// MARK: - Enhanced Tool Use Block

/// Clean, type-safe tool use block for Anthropic responses
public struct AnthropicToolUseBlock: Decodable {
    /// Unique identifier for this tool use
    public let id: String
    
    /// Name of the tool to execute
    public let name: String
    
    /// Raw input parameters as received from Claude
    public let input: [String: Any]
    
    /// Decoded input parameters as a typed dictionary
    public var typedInput: [String: Any] {
        // Input is already converted to regular Swift types
        return input
    }
    
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case input
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        
        // Decode input as AIProxyJSONValue dictionary then convert
        let rawInput = try container.decode([String: AIProxyJSONValue].self, forKey: .input)
        self.input = rawInput.mapValues { $0.anyValue }
    }
    
    /// Execute this tool use block with the provided tool registry
    public func execute<T: Tool>(with toolType: T.Type) async throws -> String {
        // Create tool instance
        var tool = T()
        
        // Set parameters from input
        try tool.setParameters(from: typedInput)
        
        // Execute tool
        let result = try await tool.execute()
        return result.content
    }
    
    /// Create a tool result content block for success
    public func createSuccessResult(_ result: String) -> AnthropicInputContent {
        return .toolResult(toolUseId: id, content: result, isError: false)
    }
    
    /// Create a tool result content block for error
    public func createErrorResult(_ error: String) -> AnthropicInputContent {
        return .toolResult(toolUseId: id, content: error, isError: true)
    }
    
    /// Create a tool result content block from a thrown error
    public func createErrorResult(from error: Error) -> AnthropicInputContent {
        let errorMessage: String
        if let toolError = error as? ToolError {
            errorMessage = "Tool execution failed: \(toolError.localizedDescription)"
        } else {
            errorMessage = "Tool execution failed: \(error.localizedDescription)"
        }
        return .toolResult(toolUseId: id, content: errorMessage, isError: true)
    }
}


public struct AnthropicMessageUsage: Codable, Sendable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int

    // Note: CodingKeys not needed - the shared decoder uses convertFromSnakeCase
    // which automatically converts input_tokens → inputTokens

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

// MARK: - Search Result Citation Types

/// Citation information for search result references
public struct AnthropicSearchResultCitation: Decodable {
    /// Always "search_result_location" for search result citations
    public let type: String
    
    /// The source from the original search result
    public let source: String
    
    /// The title from the original search result
    public let title: String?
    
    /// The exact text being cited
    public let citedText: String
    
    /// Index of the search result (0-based)
    public let searchResultIndex: Int
    
    /// Starting position in the content array
    public let startBlockIndex: Int
    
    /// Ending position in the content array
    public let endBlockIndex: Int
    
    // Note: CodingKeys not needed - using shared decoder with convertFromSnakeCase
    // which automatically converts cited_text → citedText, etc.

    public init(
        type: String = "search_result_location",
        source: String,
        title: String?,
        citedText: String,
        searchResultIndex: Int,
        startBlockIndex: Int,
        endBlockIndex: Int
    ) {
        self.type = type
        self.source = source
        self.title = title
        self.citedText = citedText
        self.searchResultIndex = searchResultIndex
        self.startBlockIndex = startBlockIndex
        self.endBlockIndex = endBlockIndex
    }
}
