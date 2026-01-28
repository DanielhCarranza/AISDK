//
//  AnthropicMCPServer.swift
//
//  Created by AI Assistant on 01/20/25.
//

import Foundation

@available(*, deprecated, renamed: "MCPServerConfig")
public typealias AnthropicMCPServer = MCPServerConfig

@available(*, deprecated, renamed: "MCPToolConfiguration")
public typealias AnthropicMCPToolConfiguration = MCPToolConfiguration

// MARK: - Convenience Extensions

public extension AnthropicMCPServer {
    /// Create an MCP server with all tools enabled
    static func withAllTools(
        url: String,
        name: String,
        authorizationToken: String? = nil
    ) -> AnthropicMCPServer {
        return AnthropicMCPServer(
            name: name,
            url: url,
            authorizationToken: authorizationToken,
            toolConfiguration: AnthropicMCPToolConfiguration(enabled: true)
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
            name: name,
            url: url,
            authorizationToken: authorizationToken,
            toolConfiguration: AnthropicMCPToolConfiguration(
                enabled: true,
                allowedTools: allowedTools
            )
        )
    }

    /// Create an MCP server with tools disabled
    static func withDisabledTools(
        url: String,
        name: String,
        authorizationToken: String? = nil
    ) -> AnthropicMCPServer {
        return AnthropicMCPServer(
            name: name,
            url: url,
            authorizationToken: authorizationToken,
            toolConfiguration: AnthropicMCPToolConfiguration(enabled: false)
        )
    }
}
