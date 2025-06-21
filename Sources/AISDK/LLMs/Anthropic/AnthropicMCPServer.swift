//
//  AnthropicMCPServer.swift
//  
//
//  Created by AI Assistant on 01/20/25.
//

import Foundation

/// Configuration for an MCP (Model Context Protocol) server connection
/// 
/// MCP enables connecting to remote servers that provide tools and context
/// directly through the Anthropic Messages API without requiring a separate MCP client.
///
/// Example usage:
/// ```swift
/// let mcpServer = AnthropicMCPServer(
///     url: "https://example-server.modelcontextprotocol.io/sse",
///     name: "example-mcp",
///     authorizationToken: "your-oauth-token"
/// )
/// ```
public struct AnthropicMCPServer: Codable, Equatable {
    /// Server type - currently only "url" is supported
    public let type: String
    
    /// The URL of the MCP server (must start with https://)
    public let url: String
    
    /// Unique identifier for this MCP server
    /// Used to identify the server in mcp_tool_call blocks
    public let name: String
    
    /// Tool configuration for this server
    public let toolConfiguration: AnthropicMCPToolConfiguration?
    
    /// OAuth authorization token if required by the MCP server
    public let authorizationToken: String?
    
    /// Initialize an MCP server configuration
    /// 
    /// - Parameters:
    ///   - url: The HTTPS URL of the MCP server
    ///   - name: Unique identifier for this server
    ///   - toolConfiguration: Optional tool filtering configuration
    ///   - authorizationToken: Optional OAuth Bearer token
    public init(
        url: String,
        name: String,
        toolConfiguration: AnthropicMCPToolConfiguration? = nil,
        authorizationToken: String? = nil
    ) {
        self.type = "url"
        self.url = url
        self.name = name
        self.toolConfiguration = toolConfiguration
        self.authorizationToken = authorizationToken
    }
    
    private enum CodingKeys: String, CodingKey {
        case type
        case url
        case name
        case toolConfiguration = "tool_configuration"
        case authorizationToken = "authorization_token"
    }
}

/// Tool configuration for MCP servers
/// 
/// Allows filtering and controlling which tools from the MCP server are available
public struct AnthropicMCPToolConfiguration: Codable, Equatable {
    /// Whether to enable tools from this server (default: true)
    public let enabled: Bool
    
    /// List of specific tools to allow (if nil, all tools are allowed)
    public let allowedTools: [String]?
    
    /// Initialize tool configuration
    /// 
    /// - Parameters:
    ///   - enabled: Whether tools from this server are enabled
    ///   - allowedTools: Optional list of specific tools to allow
    public init(
        enabled: Bool = true,
        allowedTools: [String]? = nil
    ) {
        self.enabled = enabled
        self.allowedTools = allowedTools
    }
    
    private enum CodingKeys: String, CodingKey {
        case enabled
        case allowedTools = "allowed_tools"
    }
}

// MARK: - Convenience Extensions

public extension AnthropicMCPServer {
    /// Create an MCP server with all tools enabled
    static func withAllTools(
        url: String,
        name: String,
        authorizationToken: String? = nil
    ) -> AnthropicMCPServer {
        return AnthropicMCPServer(
            url: url,
            name: name,
            toolConfiguration: AnthropicMCPToolConfiguration(enabled: true),
            authorizationToken: authorizationToken
        )
    }
    
    /// Create an MCP server with specific tools allowed
    static func withSpecificTools(
        url: String,
        name: String,
        allowedTools: [String],
        authorizationToken: String? = nil
    ) -> AnthropicMCPServer {
        return AnthropicMCPServer(
            url: url,
            name: name,
            toolConfiguration: AnthropicMCPToolConfiguration(
                enabled: true,
                allowedTools: allowedTools
            ),
            authorizationToken: authorizationToken
        )
    }
    
    /// Create an MCP server with tools disabled
    static func withDisabledTools(
        url: String,
        name: String,
        authorizationToken: String? = nil
    ) -> AnthropicMCPServer {
        return AnthropicMCPServer(
            url: url,
            name: name,
            toolConfiguration: AnthropicMCPToolConfiguration(enabled: false),
            authorizationToken: authorizationToken
        )
    }
} 