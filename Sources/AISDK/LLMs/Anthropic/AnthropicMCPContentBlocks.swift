//
//  AnthropicMCPContentBlocks.swift
//  
//
//  Created by AI Assistant on 01/20/25.
//

import Foundation

/// MCP Tool Use content block for Anthropic responses
/// 
/// This represents when Claude wants to use a tool from an MCP server.
/// The content block includes the MCP server name to identify which server
/// should handle the tool execution.
///
/// Example JSON structure:
/// ```json
/// {
///   "type": "mcp_tool_use",
///   "id": "mcptoolu_014Q35RayjACSWkSj4X2yov1",
///   "name": "echo",
///   "server_name": "example-mcp",
///   "input": { "param1": "value1", "param2": "value2" }
/// }
/// ```
public struct AnthropicMCPToolUseBlock: Codable {
    /// Content block type (always "mcp_tool_use")
    public let type: String = "mcp_tool_use"
    
    /// Unique identifier for this MCP tool use
    public let id: String
    
    /// Name of the tool to execute
    public let name: String
    
    /// Name of the MCP server that provides this tool
    public let serverName: String
    
    /// Input parameters for the tool as raw JSON values
    public let input: [String: AIProxyJSONValue]
    
    /// Initialize an MCP tool use block
    /// 
    /// - Parameters:
    ///   - id: Unique identifier for this tool use
    ///   - name: Name of the tool to execute
    ///   - serverName: Name of the MCP server
    ///   - input: Input parameters for the tool
    public init(
        id: String,
        name: String,
        serverName: String,
        input: [String: AIProxyJSONValue]
    ) {
        self.id = id
        self.name = name
        self.serverName = serverName
        self.input = input
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case serverName = "server_name"
        case input
    }
    
    /// Decoded input parameters as Swift types
    public var typedInput: [String: Any] {
        return input.mapValues { $0.anyValue }
    }
    
    /// Create a success result block for this MCP tool use
    /// 
    /// - Parameter result: The successful result content
    /// - Returns: An MCP tool result block
    public func createSuccessResult(_ result: [AnthropicMCPResultContent]) -> AnthropicMCPToolResultBlock {
        return AnthropicMCPToolResultBlock(
            toolUseId: id,
            isError: false,
            content: result
        )
    }
    
    /// Create an error result block for this MCP tool use
    /// 
    /// - Parameter error: The error message
    /// - Returns: An MCP tool result block indicating error
    public func createErrorResult(_ error: String) -> AnthropicMCPToolResultBlock {
        return AnthropicMCPToolResultBlock(
            toolUseId: id,
            isError: true,
            content: [.text(error)]
        )
    }
}

/// MCP Tool Result content block for Anthropic responses
/// 
/// This represents the result of executing an MCP tool, which can be
/// either successful content or an error state.
///
/// Example JSON structure:
/// ```json
/// {
///   "type": "mcp_tool_result",
///   "tool_use_id": "mcptoolu_014Q35RayjACSWkSj4X2yov1",
///   "is_error": false,
///   "content": [
///     {
///       "type": "text",
///       "text": "Hello"
///     }
///   ]
/// }
/// ```
public struct AnthropicMCPToolResultBlock: Codable {
    /// Content block type (always "mcp_tool_result")
    public let type: String = "mcp_tool_result"
    
    /// The ID of the MCP tool use that this result corresponds to
    public let toolUseId: String
    
    /// Whether this result represents an error
    public let isError: Bool
    
    /// The content of the tool result
    public let content: [AnthropicMCPResultContent]
    
    /// Initialize an MCP tool result block
    /// 
    /// - Parameters:
    ///   - toolUseId: ID of the corresponding tool use
    ///   - isError: Whether this is an error result
    ///   - content: The result content
    public init(
        toolUseId: String,
        isError: Bool,
        content: [AnthropicMCPResultContent]
    ) {
        self.toolUseId = toolUseId
        self.isError = isError
        self.content = content
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case isError = "is_error"
        case content
    }
}

/// Content types that can be included in MCP tool results
/// 
/// Currently supports text content, with potential for future expansion
/// to include images, documents, or other content types.
public enum AnthropicMCPResultContent: Codable {
    case text(String)
    
    private enum CodingKeys: String, CodingKey {
        case type
        case text
    }
    
    private enum ContentType: String, Codable {
        case text
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)
        
        switch type {
        case .text:
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let text):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

// MARK: - Convenience Extensions

public extension AnthropicMCPResultContent {
    /// Extract text content if this is a text block
    var textValue: String? {
        switch self {
        case .text(let text):
            return text
        }
    }
}

public extension AnthropicMCPToolResultBlock {
    /// Create a simple text result
    /// 
    /// - Parameters:
    ///   - toolUseId: ID of the corresponding tool use
    ///   - text: The result text
    ///   - isError: Whether this is an error result
    /// - Returns: A tool result block with text content
    static func textResult(
        toolUseId: String,
        text: String,
        isError: Bool = false
    ) -> AnthropicMCPToolResultBlock {
        return AnthropicMCPToolResultBlock(
            toolUseId: toolUseId,
            isError: isError,
            content: [.text(text)]
        )
    }
    
    /// Get the first text content if available
    var firstTextContent: String? {
        return content.first?.textValue
    }
    
    /// Get all text content concatenated
    var allTextContent: String {
        return content.compactMap { $0.textValue }.joined(separator: "\n")
    }
} 