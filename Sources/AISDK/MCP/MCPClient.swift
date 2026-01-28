//
//  MCPClient.swift
//  AISDK
//
//  Lightweight MCP client for communicating with MCP servers.
//  Based on the MCP Specification 2025-11-25.
//
//  This client handles the MCP protocol lifecycle including initialization,
//  tool discovery, and tool execution.
//

import Foundation

// MARK: - MCPClient

/// Actor-based MCP client for communicating with MCP servers.
///
/// MCPClient handles the full MCP protocol lifecycle:
/// 1. **Initialize** - Performs the `initialize` → `initialized` handshake
/// 2. **List Tools** - Discovers available tools with pagination support
/// 3. **Call Tools** - Executes tools and returns results
///
/// ## Usage
/// ```swift
/// let client = MCPClient()
///
/// let config = MCPServerConfiguration(
///     serverLabel: "github",
///     serverUrl: "https://api.github.com/mcp"
/// )
///
/// // Discover tools
/// let tools = try await client.listTools(server: config)
///
/// // Execute a tool
/// let result = try await client.callTool(
///     server: config,
///     name: "search_code",
///     arguments: ["query": "hello world"]
/// )
/// ```
///
/// ## Transport
/// Currently uses simple HTTP POST for all requests. SSE (Server-Sent Events)
/// transport will be added in a future release for real-time streaming.
///
/// ## Caching
/// Tool lists are cached per server to avoid repeated `tools/list` calls.
/// Call `clearCache(for:)` to force re-discovery.
///
/// ## Thread Safety
/// MCPClient is an actor, ensuring all operations are thread-safe.
public actor MCPClient {

    // MARK: - Types

    /// Connection state for an MCP server.
    private struct ServerConnection: Sendable {
        /// Whether the server has been initialized.
        var isInitialized: Bool = false

        /// Protocol version negotiated with the server.
        var protocolVersion: String?

        /// Cached tool definitions.
        var cachedTools: [MCPToolDefinition]?

        /// Server capabilities from initialization.
        var capabilities: MCPServerCapabilities?
    }

    // MARK: - Properties

    /// URLSession for HTTP requests.
    private let session: URLSession

    /// Connection state per server (keyed by serverLabel).
    private var connections: [String: ServerConnection] = [:]

    /// Request ID counter for JSON-RPC correlation.
    private var requestIdCounter: Int = 0

    /// MCP protocol version header value.
    private let mcpProtocolVersion = "2025-11-25"

    // MARK: - Initialization

    /// Creates a new MCP client.
    ///
    /// - Parameter session: URLSession to use for HTTP requests (default: shared)
    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Lists all tools available from an MCP server.
    ///
    /// This method:
    /// 1. Initializes the connection if not already done
    /// 2. Returns cached tools if available
    /// 3. Fetches all tools with pagination support
    /// 4. Caches the result for future calls
    ///
    /// - Parameter server: Server configuration
    /// - Returns: Array of tool definitions from the server
    /// - Throws: `MCPClientError` if the request fails
    public func listTools(server: MCPServerConfiguration) async throws -> [MCPToolSchema] {
        // Ensure initialized
        try await initializeIfNeeded(server: server)

        // Check cache
        if let cachedTools = connections[server.serverLabel]?.cachedTools {
            return cachedTools.map { $0.toToolSchema(serverLabel: server.serverLabel) }
        }

        // Fetch all tools with pagination
        var allTools: [MCPToolDefinition] = []
        var cursor: String? = nil

        repeat {
            let params = MCPListToolsParams(cursor: cursor)
            let response: MCPListToolsResponse = try await sendRequest(
                server: server,
                method: "tools/list",
                params: params
            )

            guard let result = response.result else {
                if let error = response.error {
                    throw MCPClientError.serverError(error)
                }
                throw MCPClientError.invalidResponse("No result in tools/list response")
            }

            allTools.append(contentsOf: result.tools)
            cursor = result.nextCursor
        } while cursor != nil

        // Cache the results
        connections[server.serverLabel]?.cachedTools = allTools

        return allTools.map { $0.toToolSchema(serverLabel: server.serverLabel) }
    }

    /// Calls a tool on an MCP server.
    ///
    /// - Parameters:
    ///   - server: Server configuration
    ///   - name: Tool name to invoke
    ///   - arguments: Arguments to pass to the tool
    /// - Returns: Result of the tool execution
    /// - Throws: `MCPClientError` if the request fails
    public func callTool(
        server: MCPServerConfiguration,
        name: String,
        arguments: [String: AIProxyJSONValue]
    ) async throws -> MCPCallResult {
        // Ensure initialized
        try await initializeIfNeeded(server: server)

        let params = MCPCallToolParams(name: name, arguments: arguments)
        let response: MCPCallToolResponse = try await sendRequest(
            server: server,
            method: "tools/call",
            params: params
        )

        guard let result = response.result else {
            if let error = response.error {
                throw MCPClientError.serverError(error)
            }
            throw MCPClientError.invalidResponse("No result in tools/call response")
        }

        return result.toCallResult()
    }

    /// Clears the cached tools for a server.
    ///
    /// Call this to force re-discovery of tools on the next `listTools` call.
    ///
    /// - Parameter server: Server to clear cache for
    public func clearCache(for server: MCPServerConfiguration) {
        connections[server.serverLabel]?.cachedTools = nil
    }

    /// Clears all cached connections and tool lists.
    public func clearAllCaches() {
        connections.removeAll()
    }

    /// Checks if a server has been initialized.
    ///
    /// - Parameter server: Server to check
    /// - Returns: `true` if the server has been initialized
    public func isInitialized(server: MCPServerConfiguration) -> Bool {
        connections[server.serverLabel]?.isInitialized ?? false
    }

    // MARK: - Internal Methods

    /// Performs the MCP initialize handshake if not already done.
    private func initializeIfNeeded(server: MCPServerConfiguration) async throws {
        if connections[server.serverLabel]?.isInitialized == true {
            return
        }

        // Create or get connection state
        if connections[server.serverLabel] == nil {
            connections[server.serverLabel] = ServerConnection()
        }

        // Send initialize request
        let params = MCPInitializeParams()
        let response: MCPInitializeResponse = try await sendRequest(
            server: server,
            method: "initialize",
            params: params,
            skipVersionHeader: true // Don't send version header on first request
        )

        guard let result = response.result else {
            if let error = response.error {
                throw MCPClientError.serverError(error)
            }
            throw MCPClientError.initializationFailed("No result in initialize response")
        }

        // Store connection info
        connections[server.serverLabel]?.protocolVersion = result.protocolVersion
        connections[server.serverLabel]?.capabilities = result.capabilities

        // Send initialized notification
        try await sendNotification(server: server, method: "notifications/initialized")

        connections[server.serverLabel]?.isInitialized = true
    }

    /// Generates the next request ID.
    private func nextRequestId() -> String {
        requestIdCounter += 1
        return String(requestIdCounter)
    }

    /// Sends a JSON-RPC request and waits for response.
    private func sendRequest<P: Encodable & Sendable, R: Decodable & Sendable>(
        server: MCPServerConfiguration,
        method: String,
        params: P,
        skipVersionHeader: Bool = false
    ) async throws -> MCPResponse<R> {
        let requestId = nextRequestId()
        let request = MCPRequest(id: requestId, method: method, params: params)

        let data = try await executeHTTPRequest(
            server: server,
            body: request,
            skipVersionHeader: skipVersionHeader
        )

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(MCPResponse<R>.self, from: data)
        } catch {
            throw MCPClientError.decodingFailed(error)
        }
    }

    /// Sends a JSON-RPC notification (no response expected).
    private func sendNotification<P: Encodable & Sendable>(
        server: MCPServerConfiguration,
        method: String,
        params: P? = nil as MCPEmptyParams?
    ) async throws {
        let notification = MCPNotification(method: method, params: params)

        // Fire and forget - notifications don't expect responses
        _ = try await executeHTTPRequest(
            server: server,
            body: notification,
            skipVersionHeader: false
        )
    }

    /// Executes an HTTP POST request to the MCP server.
    private func executeHTTPRequest<Body: Encodable>(
        server: MCPServerConfiguration,
        body: Body,
        skipVersionHeader: Bool
    ) async throws -> Data {
        guard let url = URL(string: server.serverUrl) else {
            throw MCPClientError.invalidURL(server.serverUrl)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add MCP protocol version header (after initialization)
        if !skipVersionHeader {
            request.setValue(mcpProtocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        }

        // Add custom headers from configuration
        if let headers = server.headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Set timeouts
        request.timeoutInterval = server.requestTimeout

        // Encode body
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        // Execute request
        let (data, response) = try await session.data(for: request)

        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw MCPClientError.httpError(statusCode: httpResponse.statusCode, data: data)
            }
        }

        return data
    }
}

// MARK: - MCPClientError

/// Errors that can occur during MCP client operations.
public enum MCPClientError: Error, Sendable {
    /// Invalid server URL.
    case invalidURL(String)

    /// HTTP request failed.
    case httpError(statusCode: Int, data: Data)

    /// Failed to decode response.
    case decodingFailed(Error)

    /// Server returned an error.
    case serverError(MCPError)

    /// Invalid response from server.
    case invalidResponse(String)

    /// Initialization handshake failed.
    case initializationFailed(String)

    /// Tool not found on server.
    case toolNotFound(String)

    public var localizedDescription: String {
        switch self {
        case .invalidURL(let url):
            return "Invalid MCP server URL: \(url)"
        case .httpError(let statusCode, _):
            return "HTTP error \(statusCode)"
        case .decodingFailed(let error):
            return "Failed to decode MCP response: \(error.localizedDescription)"
        case .serverError(let error):
            return error.localizedDescription
        case .invalidResponse(let message):
            return "Invalid MCP response: \(message)"
        case .initializationFailed(let message):
            return "MCP initialization failed: \(message)"
        case .toolNotFound(let name):
            return "MCP tool not found: \(name)"
        }
    }
}

// MARK: - Extensions

extension MCPToolDefinition {
    /// Converts to MCPToolSchema with server label.
    func toToolSchema(serverLabel: String) -> MCPToolSchema {
        MCPToolSchema(
            name: name,
            description: description,
            inputSchema: inputSchema,
            serverLabel: serverLabel
        )
    }
}
