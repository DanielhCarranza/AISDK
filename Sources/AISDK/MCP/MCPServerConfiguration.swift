//
//  MCPServerConfiguration.swift
//  AISDK
//
//  Configuration types for Model Context Protocol (MCP) server connections.
//  Based on the MCP Specification 2025-11-25.
//
//  MCP enables AI agents to connect to external tools and data sources through
//  a standardized JSON-RPC 2.0 based protocol.
//

import Foundation

// MARK: - MCPServerConfiguration

/// Configuration for connecting to an MCP server.
///
/// MCP servers provide tools that agents can discover and invoke. This configuration
/// specifies how to connect to a server and what tools to use from it.
///
/// ## Usage
/// ```swift
/// let config = MCPServerConfiguration(
///     serverLabel: "github",
///     serverUrl: "https://api.github.com/mcp",
///     requireApproval: .never,
///     allowedTools: ["search_code", "list_repos"]
/// )
///
/// let agent = Agent(
///     model: myModel,
///     mcpServers: [config]
/// )
/// ```
///
/// ## Tool Namespacing
/// Tools from MCP servers are exposed with namespaced names: `mcp__<serverLabel>__<toolName>`.
/// This prevents collisions between tools from different servers and native tools.
///
/// ## Transports
/// Currently supports HTTP transport (simple request/response). SSE (Server-Sent Events)
/// transport for real-time streaming will be added in a future release.
///
/// - Note: This type replaces the previous `MCPServerConfiguration` in ResponseAgent.
public struct MCPServerConfiguration: Sendable, Codable, Hashable {

    /// Unique label to identify this server (e.g., "github", "filesystem", "database").
    /// This label is used in tool namespacing: `mcp__<serverLabel>__<toolName>`.
    public let serverLabel: String

    /// URL of the MCP server endpoint.
    /// For HTTP transport, this is the base URL for JSON-RPC requests.
    public let serverUrl: String

    /// Transport protocol to use for communication.
    /// Defaults to `.http` for simple request/response.
    public let transport: MCPTransport

    /// When to require user approval before executing tools from this server.
    public let requireApproval: MCPApprovalLevel

    /// Optional list of tool names to allow from this server.
    /// If `nil`, all tools are allowed (subject to `blockedTools`).
    /// If specified, only tools in this list are exposed.
    public let allowedTools: [String]?

    /// Optional list of tool names to block from this server.
    /// Applied after `allowedTools` filtering.
    /// Tools in this list are never exposed, even if in `allowedTools`.
    public let blockedTools: [String]?

    /// Optional authorization headers to include in requests.
    /// Common headers: "Authorization", "X-API-Key".
    public let headers: [String: String]?

    /// Timeout for establishing connection to the server (in seconds).
    public let connectionTimeout: TimeInterval

    /// Timeout for individual requests to the server (in seconds).
    public let requestTimeout: TimeInterval

    /// Creates a new MCP server configuration.
    ///
    /// - Parameters:
    ///   - serverLabel: Unique label to identify this server
    ///   - serverUrl: URL of the MCP server endpoint
    ///   - transport: Transport protocol (default: `.http`)
    ///   - requireApproval: When to require approval (default: `.never`)
    ///   - allowedTools: Optional list of allowed tool names
    ///   - blockedTools: Optional list of blocked tool names
    ///   - headers: Optional authorization headers
    ///   - connectionTimeout: Connection timeout in seconds (default: 30)
    ///   - requestTimeout: Request timeout in seconds (default: 120)
    public init(
        serverLabel: String,
        serverUrl: String,
        transport: MCPTransport = .http,
        requireApproval: MCPApprovalLevel = .never,
        allowedTools: [String]? = nil,
        blockedTools: [String]? = nil,
        headers: [String: String]? = nil,
        connectionTimeout: TimeInterval = 30,
        requestTimeout: TimeInterval = 120
    ) {
        self.serverLabel = serverLabel
        self.serverUrl = serverUrl
        self.transport = transport
        self.requireApproval = requireApproval
        self.allowedTools = allowedTools
        self.blockedTools = blockedTools
        self.headers = headers
        self.connectionTimeout = connectionTimeout
        self.requestTimeout = requestTimeout
    }
}

// MARK: - MCPTransport

/// Transport protocol for MCP server communication.
///
/// MCP supports multiple transport mechanisms. Currently this SDK implements
/// HTTP transport with plans to add SSE support.
///
/// ## Transport Options
/// - **HTTP**: Simple request/response using HTTP POST. Each JSON-RPC request
///   is sent as a POST and receives a synchronous response.
/// - **stdio**: For local MCP servers running as child processes. Communication
///   happens via stdin/stdout. (Future support)
///
/// ## Future: SSE (Server-Sent Events)
/// The MCP specification defines Streamable HTTP which uses SSE for server-to-client
/// streaming. This will be added in a future release for real-time tool execution
/// feedback and notifications.
public enum MCPTransport: String, Sendable, Codable, Hashable {
    /// HTTP transport using POST requests for JSON-RPC.
    /// This is the simplest transport and works with most MCP servers.
    case http

    /// Standard I/O transport for local process communication.
    /// Used when running MCP servers as local child processes.
    /// - Note: Not yet implemented. Will be added in a future release.
    case stdio
}

// MARK: - MCPApprovalLevel

/// Policy for when to require user approval before executing MCP tools.
///
/// MCP tools can perform actions that modify external systems. This policy
/// controls when the agent should pause and request user approval.
///
/// ## Approval Policies
/// - **never**: Trust all tools from this server. Use for well-tested, safe tools.
/// - **always**: Require approval for every tool invocation. Use during development
///   or for untrusted servers.
/// - **dangerous**: Only require approval for tools marked as potentially destructive.
///   This is determined by tool metadata (future feature).
public enum MCPApprovalLevel: String, Sendable, Codable, Hashable {
    /// Never require approval - trust all tools from this server.
    case never

    /// Always require approval before executing any tool.
    case always

    /// Only require approval for potentially dangerous operations.
    /// - Note: Dangerous tool detection based on tool metadata will be added in future.
    case dangerous
}

// MARK: - MCPToolSchema

/// Schema for a tool discovered from an MCP server.
///
/// MCP servers expose tools via the `tools/list` endpoint. Each tool has a name,
/// description, and JSON Schema defining its input parameters.
///
/// ## Tool Namespacing
/// When exposed to the agent, tools are namespaced as `mcp__<serverLabel>__<toolName>`
/// to prevent collisions with native tools and tools from other servers.
///
/// ## Schema Handling
/// The `inputSchema` is stored as `AIProxyJSONValue` to preserve the full JSON Schema
/// without loss. This allows for best-effort conversion to the provider's tool format.
public struct MCPToolSchema: Sendable {
    /// Name of the tool as defined by the MCP server.
    public let name: String

    /// Human-readable description of what the tool does.
    public let description: String?

    /// JSON Schema defining the tool's input parameters.
    /// Stored as `AIProxyJSONValue` for lossless JSON representation.
    public let inputSchema: [String: AIProxyJSONValue]

    /// Label of the server that provides this tool.
    /// Used for namespacing: `mcp__<serverLabel>__<name>`.
    public let serverLabel: String

    /// The namespaced tool name used when exposing to the agent.
    /// Format: `mcp__<serverLabel>__<name>`
    public var namespacedName: String {
        "mcp__\(serverLabel)__\(name)"
    }

    /// Creates a new MCP tool schema.
    ///
    /// - Parameters:
    ///   - name: Tool name from the MCP server
    ///   - description: Human-readable description
    ///   - inputSchema: JSON Schema for input parameters
    ///   - serverLabel: Label of the providing server
    public init(
        name: String,
        description: String?,
        inputSchema: [String: AIProxyJSONValue],
        serverLabel: String
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.serverLabel = serverLabel
    }
}

// MARK: - MCPApprovalContext

/// Context provided when requesting user approval for MCP tool execution.
///
/// When an MCP server is configured with `requireApproval: .always` (or `.dangerous`
/// for dangerous tools), the agent will call the approval handler with this context
/// before executing the tool.
///
/// ## Usage
/// ```swift
/// agent.mcpApprovalHandler = { context in
///     print("Tool: \(context.toolName) on server: \(context.serverLabel)")
///     print("Arguments: \(context.argumentsJSON)")
///     return true // Approve
/// }
/// ```
public struct MCPApprovalContext: Sendable {
    /// Label of the MCP server providing the tool.
    public let serverLabel: String

    /// Name of the tool being invoked (without namespace prefix).
    public let toolName: String

    /// JSON string of the arguments being passed to the tool.
    public let argumentsJSON: String

    /// Creates approval context for a tool invocation.
    ///
    /// - Parameters:
    ///   - serverLabel: Server providing the tool
    ///   - toolName: Name of the tool
    ///   - argumentsJSON: JSON-encoded arguments
    public init(serverLabel: String, toolName: String, argumentsJSON: String) {
        self.serverLabel = serverLabel
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
    }
}

// MARK: - MCPCallResult

/// Result of executing an MCP tool via `tools/call`.
///
/// MCP tool results contain an array of content blocks (text, images, etc.)
/// and an optional error flag.
public struct MCPCallResult: Sendable {
    /// Content returned by the tool.
    public let content: [MCPContent]

    /// Whether the tool execution resulted in an error.
    public let isError: Bool

    /// The text content combined from all text blocks.
    public var textContent: String {
        content.compactMap { content in
            if case .text(let text) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    /// Creates a call result.
    ///
    /// - Parameters:
    ///   - content: Content blocks from the tool
    ///   - isError: Whether this is an error result
    public init(content: [MCPContent], isError: Bool = false) {
        self.content = content
        self.isError = isError
    }
}

// MARK: - MCPContent

/// Content types that can be returned by MCP tools.
///
/// MCP tools can return various content types including text, images, and
/// resource references. Currently only text is fully supported.
public enum MCPContent: Sendable, Codable {
    /// Plain text content.
    case text(String)

    /// Image content with base64 data and MIME type.
    /// - Note: Image handling will be enhanced in future releases.
    case image(data: String, mimeType: String)

    /// Reference to an MCP resource.
    /// - Note: Resource handling will be enhanced in future releases.
    case resource(uri: String, mimeType: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case data
        case mimeType
        case uri
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "image":
            let data = try container.decode(String.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .image(data: data, mimeType: mimeType)
        case "resource", "resource_link":
            let uri = try container.decode(String.self, forKey: .uri)
            let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
            self = .resource(uri: uri, mimeType: mimeType)
        default:
            // Default to text for unknown types
            let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .text(text)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .resource(let uri, let mimeType):
            try container.encode("resource", forKey: .type)
            try container.encode(uri, forKey: .uri)
            if let mimeType = mimeType {
                try container.encode(mimeType, forKey: .mimeType)
            }
        }
    }
}
