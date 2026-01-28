//
//  MCPMessages.swift
//  AISDK
//
//  JSON-RPC message types for the Model Context Protocol.
//  Based on the MCP Specification 2025-11-25.
//
//  MCP uses JSON-RPC 2.0 for all communication between clients and servers.
//

import Foundation

// MARK: - JSON-RPC Base Types

/// JSON-RPC 2.0 request envelope for MCP messages.
public struct MCPRequest<P: Encodable>: Encodable, Sendable where P: Sendable {
    /// JSON-RPC version (always "2.0").
    public let jsonrpc: String = "2.0"

    /// Request identifier for correlating responses.
    public let id: String

    /// Method name to invoke on the server.
    public let method: String

    /// Optional parameters for the method.
    public let params: P?

    /// Creates a JSON-RPC request.
    ///
    /// - Parameters:
    ///   - id: Request identifier
    ///   - method: Method name
    ///   - params: Optional parameters
    public init(id: String, method: String, params: P? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 2.0 response envelope for MCP messages.
public struct MCPResponse<R: Decodable>: Decodable, Sendable where R: Sendable {
    /// JSON-RPC version (always "2.0").
    public let jsonrpc: String

    /// Request identifier this response correlates to.
    public let id: String?

    /// Result of the method call (if successful).
    public let result: R?

    /// Error information (if failed).
    public let error: MCPError?

    /// Whether this response indicates success.
    public var isSuccess: Bool {
        error == nil && result != nil
    }
}

/// JSON-RPC 2.0 error object.
public struct MCPError: Decodable, Sendable, Error {
    /// Error code (standard JSON-RPC codes or MCP-specific).
    public let code: Int

    /// Human-readable error message.
    public let message: String

    /// Optional additional error data.
    public let data: AIProxyJSONValue?

    public var localizedDescription: String {
        "MCP Error \(code): \(message)"
    }
}

// MARK: - Initialize Messages

/// Parameters for the MCP `initialize` request.
public struct MCPInitializeParams: Codable, Sendable {
    /// Protocol version the client supports.
    public let protocolVersion: String

    /// Client capabilities.
    public let capabilities: MCPClientCapabilities

    /// Client information.
    public let clientInfo: MCPClientInfo

    /// Creates initialize parameters.
    ///
    /// - Parameters:
    ///   - protocolVersion: MCP protocol version (default: "2025-11-25")
    ///   - capabilities: Client capabilities
    ///   - clientInfo: Client identification
    public init(
        protocolVersion: String = "2025-11-25",
        capabilities: MCPClientCapabilities = MCPClientCapabilities(),
        clientInfo: MCPClientInfo = MCPClientInfo()
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.clientInfo = clientInfo
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocolVersion"
        case capabilities
        case clientInfo
    }
}

/// Client capabilities for MCP handshake.
public struct MCPClientCapabilities: Codable, Sendable {
    /// Whether the client supports sampling.
    public let sampling: [String: AIProxyJSONValue]?

    /// Creates client capabilities.
    public init(sampling: [String: AIProxyJSONValue]? = nil) {
        self.sampling = sampling
    }
}

/// Client identification for MCP handshake.
public struct MCPClientInfo: Codable, Sendable {
    /// Client name.
    public let name: String

    /// Client version.
    public let version: String

    /// Creates client info.
    ///
    /// - Parameters:
    ///   - name: Client name (default: "AISDK")
    ///   - version: Client version (default: "1.0.0")
    public init(name: String = "AISDK", version: String = "1.0.0") {
        self.name = name
        self.version = version
    }
}

/// Result of the MCP `initialize` request.
public struct MCPInitializeResult: Decodable, Sendable {
    /// Protocol version the server supports.
    public let protocolVersion: String

    /// Server capabilities.
    public let capabilities: MCPServerCapabilities

    /// Server information.
    public let serverInfo: MCPServerInfo?
}

/// Server capabilities returned from initialize.
public struct MCPServerCapabilities: Decodable, Sendable {
    /// Whether the server supports tools.
    public let tools: MCPToolsCapability?

    /// Whether the server supports resources.
    public let resources: MCPResourcesCapability?

    /// Whether the server supports prompts.
    public let prompts: MCPPromptsCapability?
}

/// Tools capability details.
public struct MCPToolsCapability: Decodable, Sendable {
    /// Whether tools list can change dynamically.
    public let listChanged: Bool?
}

/// Resources capability details.
public struct MCPResourcesCapability: Decodable, Sendable {
    /// Whether resources list can change dynamically.
    public let listChanged: Bool?

    /// Whether resources support subscriptions.
    public let subscribe: Bool?
}

/// Prompts capability details.
public struct MCPPromptsCapability: Decodable, Sendable {
    /// Whether prompts list can change dynamically.
    public let listChanged: Bool?
}

/// Server information from initialize.
public struct MCPServerInfo: Decodable, Sendable {
    /// Server name.
    public let name: String

    /// Server version.
    public let version: String?
}

// MARK: - Tools List Messages

/// Parameters for the MCP `tools/list` request.
public struct MCPListToolsParams: Codable, Sendable {
    /// Cursor for pagination (from previous response's `nextCursor`).
    public let cursor: String?

    /// Creates list tools parameters.
    ///
    /// - Parameter cursor: Pagination cursor (optional)
    public init(cursor: String? = nil) {
        self.cursor = cursor
    }
}

/// Result of the MCP `tools/list` request.
public struct MCPListToolsResult: Decodable, Sendable {
    /// List of available tools.
    public let tools: [MCPToolDefinition]

    /// Cursor for fetching the next page (if more tools available).
    public let nextCursor: String?
}

/// Definition of a single MCP tool.
public struct MCPToolDefinition: Decodable, Sendable {
    /// Tool name (unique identifier).
    public let name: String

    /// Human-readable description of what the tool does.
    public let description: String?

    /// JSON Schema defining the tool's input parameters.
    public let inputSchema: [String: AIProxyJSONValue]

    /// Optional annotations with hints about tool behavior.
    public let annotations: MCPToolAnnotations?
}

/// Annotations providing hints about tool behavior.
public struct MCPToolAnnotations: Decodable, Sendable {
    /// Human-readable title for display.
    public let title: String?

    /// Whether the tool only reads data (no side effects).
    public let readOnlyHint: Bool?

    /// Whether the tool may perform destructive operations.
    public let destructiveHint: Bool?

    /// Whether the tool is idempotent.
    public let idempotentHint: Bool?

    /// Whether the tool interacts with the open world (internet, etc.).
    public let openWorldHint: Bool?
}

// MARK: - Tools Call Messages

/// Parameters for the MCP `tools/call` request.
public struct MCPCallToolParams: Encodable, Sendable {
    /// Name of the tool to invoke.
    public let name: String

    /// Arguments to pass to the tool.
    public let arguments: [String: AIProxyJSONValue]

    /// Creates tool call parameters.
    ///
    /// - Parameters:
    ///   - name: Tool name
    ///   - arguments: Arguments as key-value pairs
    public init(name: String, arguments: [String: AIProxyJSONValue]) {
        self.name = name
        self.arguments = arguments
    }
}

/// Result of the MCP `tools/call` request.
public struct MCPCallToolResultRaw: Decodable, Sendable {
    /// Content returned by the tool.
    public let content: [MCPContent]

    /// Whether the tool execution resulted in an error.
    public let isError: Bool?

    /// Converts to the higher-level MCPCallResult type.
    public func toCallResult() -> MCPCallResult {
        MCPCallResult(content: content, isError: isError ?? false)
    }
}

// MARK: - Notification Messages

/// MCP notification (no response expected).
public struct MCPNotification<P: Encodable>: Encodable, Sendable where P: Sendable {
    /// JSON-RPC version.
    public let jsonrpc: String = "2.0"

    /// Notification method name.
    public let method: String

    /// Optional notification parameters.
    public let params: P?

    /// Creates a notification.
    ///
    /// - Parameters:
    ///   - method: Notification method name
    ///   - params: Optional parameters
    public init(method: String, params: P? = nil) {
        self.method = method
        self.params = params
    }
}

/// Empty params for notifications that don't require parameters.
public struct MCPEmptyParams: Codable, Sendable {
    public init() {}
}

// MARK: - Convenience Type Aliases

/// Request type for tools/list.
public typealias MCPListToolsRequest = MCPRequest<MCPListToolsParams>

/// Response type for tools/list.
public typealias MCPListToolsResponse = MCPResponse<MCPListToolsResult>

/// Request type for tools/call.
public typealias MCPCallToolRequest = MCPRequest<MCPCallToolParams>

/// Response type for tools/call.
public typealias MCPCallToolResponse = MCPResponse<MCPCallToolResultRaw>

/// Request type for initialize.
public typealias MCPInitializeRequest = MCPRequest<MCPInitializeParams>

/// Response type for initialize.
public typealias MCPInitializeResponse = MCPResponse<MCPInitializeResult>

/// Notification type for initialized.
public typealias MCPInitializedNotification = MCPNotification<MCPEmptyParams>
