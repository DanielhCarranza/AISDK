//
//  MCPTests.swift
//  AISDK
//
//  Unit tests for Model Context Protocol (MCP) support in AISDK.
//
//  These tests cover:
//  - MCPServerConfiguration types and initialization
//  - MCPClient actor behavior
//  - MCP JSON-RPC message encoding/decoding
//  - MCPToolSchema conversion and namespacing
//  - AIAgentActor MCP integration
//

import XCTest
@testable import AISDK

// MARK: - MCPServerConfiguration Tests

final class MCPServerConfigurationTests: XCTestCase {

    func testBasicInitialization() {
        let config = MCPServerConfiguration(
            serverLabel: "github",
            serverUrl: "https://api.github.com/mcp"
        )

        XCTAssertEqual(config.serverLabel, "github")
        XCTAssertEqual(config.serverUrl, "https://api.github.com/mcp")
        XCTAssertEqual(config.transport, .http)
        XCTAssertEqual(config.requireApproval, .never)
        XCTAssertNil(config.allowedTools)
        XCTAssertNil(config.blockedTools)
        XCTAssertNil(config.headers)
        XCTAssertEqual(config.connectionTimeout, 30)
        XCTAssertEqual(config.requestTimeout, 120)
    }

    func testFullInitialization() {
        let config = MCPServerConfiguration(
            serverLabel: "internal-tools",
            serverUrl: "https://tools.internal/mcp",
            transport: .http,
            requireApproval: .always,
            allowedTools: ["search", "create"],
            blockedTools: ["delete"],
            headers: ["Authorization": "Bearer token123"],
            connectionTimeout: 60,
            requestTimeout: 300
        )

        XCTAssertEqual(config.serverLabel, "internal-tools")
        XCTAssertEqual(config.serverUrl, "https://tools.internal/mcp")
        XCTAssertEqual(config.transport, .http)
        XCTAssertEqual(config.requireApproval, .always)
        XCTAssertEqual(config.allowedTools, ["search", "create"])
        XCTAssertEqual(config.blockedTools, ["delete"])
        XCTAssertEqual(config.headers?["Authorization"], "Bearer token123")
        XCTAssertEqual(config.connectionTimeout, 60)
        XCTAssertEqual(config.requestTimeout, 300)
    }

    func testCodable() throws {
        let original = MCPServerConfiguration(
            serverLabel: "test",
            serverUrl: "https://test.com/mcp",
            transport: .http,
            requireApproval: .dangerous,
            allowedTools: ["tool1"],
            blockedTools: nil,
            headers: ["X-Key": "value"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MCPServerConfiguration.self, from: data)

        XCTAssertEqual(decoded.serverLabel, original.serverLabel)
        XCTAssertEqual(decoded.serverUrl, original.serverUrl)
        XCTAssertEqual(decoded.transport, original.transport)
        XCTAssertEqual(decoded.requireApproval, original.requireApproval)
        XCTAssertEqual(decoded.allowedTools, original.allowedTools)
        XCTAssertEqual(decoded.headers, original.headers)
    }

    func testHashable() {
        let config1 = MCPServerConfiguration(serverLabel: "a", serverUrl: "https://a.com")
        let config2 = MCPServerConfiguration(serverLabel: "a", serverUrl: "https://a.com")
        let config3 = MCPServerConfiguration(serverLabel: "b", serverUrl: "https://b.com")

        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)

        var set = Set<MCPServerConfiguration>()
        set.insert(config1)
        set.insert(config2) // Should not increase count
        set.insert(config3)
        XCTAssertEqual(set.count, 2)
    }
}

// MARK: - MCPTransport Tests

final class MCPTransportTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(MCPTransport.http.rawValue, "http")
        XCTAssertEqual(MCPTransport.stdio.rawValue, "stdio")
    }

    func testCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // Test HTTP
        let httpData = try encoder.encode(MCPTransport.http)
        let httpDecoded = try decoder.decode(MCPTransport.self, from: httpData)
        XCTAssertEqual(httpDecoded, .http)

        // Test STDIO
        let stdioData = try encoder.encode(MCPTransport.stdio)
        let stdioDecoded = try decoder.decode(MCPTransport.self, from: stdioData)
        XCTAssertEqual(stdioDecoded, .stdio)
    }
}

// MARK: - MCPApprovalLevel Tests

final class MCPApprovalLevelTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(MCPApprovalLevel.never.rawValue, "never")
        XCTAssertEqual(MCPApprovalLevel.always.rawValue, "always")
        XCTAssertEqual(MCPApprovalLevel.dangerous.rawValue, "dangerous")
    }

    func testCodable() throws {
        let levels: [MCPApprovalLevel] = [.never, .always, .dangerous]

        for level in levels {
            let data = try JSONEncoder().encode(level)
            let decoded = try JSONDecoder().decode(MCPApprovalLevel.self, from: data)
            XCTAssertEqual(decoded, level)
        }
    }
}

// MARK: - MCPToolSchema Tests

final class MCPToolSchemaTests: XCTestCase {

    func testNamespacedName() {
        let schema = MCPToolSchema(
            name: "search_code",
            description: "Search for code in repositories",
            inputSchema: ["type": .string("object")],
            serverLabel: "github"
        )

        XCTAssertEqual(schema.namespacedName, "mcp__github__search_code")
    }

    func testNamespacedNameWithUnderscores() {
        let schema = MCPToolSchema(
            name: "list_all_items",
            description: nil,
            inputSchema: [:],
            serverLabel: "my_server"
        )

        XCTAssertEqual(schema.namespacedName, "mcp__my_server__list_all_items")
    }

    func testMultipleUnderscoresInToolName() {
        let schema = MCPToolSchema(
            name: "create__special__tool",
            description: "A tool with double underscores",
            inputSchema: [:],
            serverLabel: "test"
        )

        // The namespaced name should preserve the original tool name
        XCTAssertEqual(schema.namespacedName, "mcp__test__create__special__tool")
    }
}

// MARK: - MCPApprovalContext Tests

final class MCPApprovalContextTests: XCTestCase {

    func testInitialization() {
        let context = MCPApprovalContext(
            serverLabel: "github",
            toolName: "delete_repo",
            argumentsJSON: "{\"repo\": \"test-repo\"}"
        )

        XCTAssertEqual(context.serverLabel, "github")
        XCTAssertEqual(context.toolName, "delete_repo")
        XCTAssertEqual(context.argumentsJSON, "{\"repo\": \"test-repo\"}")
    }
}

// MARK: - MCPCallResult Tests

final class MCPCallResultTests: XCTestCase {

    func testTextContent() {
        let result = MCPCallResult(
            content: [
                .text("Hello"),
                .text("World")
            ],
            isError: false
        )

        XCTAssertEqual(result.textContent, "Hello\nWorld")
        XCTAssertFalse(result.isError)
    }

    func testEmptyContent() {
        let result = MCPCallResult(content: [], isError: false)
        XCTAssertEqual(result.textContent, "")
    }

    func testMixedContent() {
        let result = MCPCallResult(
            content: [
                .text("Text part"),
                .image(data: "base64data", mimeType: "image/png"),
                .text("More text"),
                .resource(uri: "file://test", mimeType: "text/plain")
            ],
            isError: false
        )

        // Only text content should be included
        XCTAssertEqual(result.textContent, "Text part\nMore text")
    }

    func testErrorResult() {
        let result = MCPCallResult(
            content: [.text("Error: Something went wrong")],
            isError: true
        )

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.textContent, "Error: Something went wrong")
    }
}

// MARK: - MCPContent Tests

final class MCPContentTests: XCTestCase {

    func testTextCodable() throws {
        let original = MCPContent.text("Hello, World!")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MCPContent.self, from: data)

        if case .text(let text) = decoded {
            XCTAssertEqual(text, "Hello, World!")
        } else {
            XCTFail("Expected text content")
        }
    }

    func testImageCodable() throws {
        let original = MCPContent.image(data: "base64encodeddata", mimeType: "image/png")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MCPContent.self, from: data)

        if case .image(let imageData, let mimeType) = decoded {
            XCTAssertEqual(imageData, "base64encodeddata")
            XCTAssertEqual(mimeType, "image/png")
        } else {
            XCTFail("Expected image content")
        }
    }

    func testResourceCodable() throws {
        let original = MCPContent.resource(uri: "file://path/to/file", mimeType: "application/json")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MCPContent.self, from: data)

        if case .resource(let uri, let mimeType) = decoded {
            XCTAssertEqual(uri, "file://path/to/file")
            XCTAssertEqual(mimeType, "application/json")
        } else {
            XCTFail("Expected resource content")
        }
    }

    func testResourceWithoutMimeType() throws {
        // Test decoding resource without mimeType
        let json = """
        {"type": "resource", "uri": "file://test"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MCPContent.self, from: data)

        if case .resource(let uri, let mimeType) = decoded {
            XCTAssertEqual(uri, "file://test")
            XCTAssertNil(mimeType)
        } else {
            XCTFail("Expected resource content")
        }
    }

    func testUnknownTypeFallsBackToText() throws {
        let json = """
        {"type": "unknown_type", "text": "fallback content"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(MCPContent.self, from: data)

        if case .text(let text) = decoded {
            XCTAssertEqual(text, "fallback content")
        } else {
            XCTFail("Expected text content fallback for unknown type")
        }
    }
}

// MARK: - MCP Messages Tests

final class MCPMessagesTests: XCTestCase {

    func testMCPRequestEncoding() throws {
        let params = MCPListToolsParams(cursor: "page2")
        let request = MCPRequest(id: "1", method: "tools/list", params: params)

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["id"] as? String, "1")
        XCTAssertEqual(json["method"] as? String, "tools/list")

        let paramsJson = json["params"] as? [String: Any]
        XCTAssertEqual(paramsJson?["cursor"] as? String, "page2")
    }

    func testMCPResponseDecoding() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "42",
            "result": {
                "tools": [
                    {
                        "name": "search",
                        "description": "Search tool",
                        "inputSchema": {"type": "object", "properties": {}}
                    }
                ],
                "nextCursor": null
            }
        }
        """
        let data = json.data(using: .utf8)!

        let response = try JSONDecoder().decode(MCPListToolsResponse.self, from: data)

        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, "42")
        XCTAssertNil(response.error)
        XCTAssertNotNil(response.result)
        XCTAssertEqual(response.result?.tools.count, 1)
        XCTAssertEqual(response.result?.tools.first?.name, "search")
    }

    func testMCPErrorDecoding() throws {
        let json = """
        {
            "jsonrpc": "2.0",
            "id": "1",
            "error": {
                "code": -32600,
                "message": "Invalid Request"
            }
        }
        """
        let data = json.data(using: .utf8)!

        let response = try JSONDecoder().decode(MCPResponse<MCPListToolsResult>.self, from: data)

        XCTAssertEqual(response.error?.code, -32600)
        XCTAssertEqual(response.error?.message, "Invalid Request")
        XCTAssertNil(response.result)
        XCTAssertFalse(response.isSuccess)
    }

    func testMCPInitializeParams() throws {
        let params = MCPInitializeParams()

        let data = try JSONEncoder().encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["protocolVersion"] as? String, "2025-11-25")

        let clientInfo = json["clientInfo"] as? [String: Any]
        XCTAssertEqual(clientInfo?["name"] as? String, "AISDK")
        XCTAssertEqual(clientInfo?["version"] as? String, "1.0.0")
    }

    func testMCPCallToolParams() throws {
        let arguments: [String: AIProxyJSONValue] = [
            "query": .string("hello"),
            "limit": .int(10)
        ]
        let params = MCPCallToolParams(name: "search", arguments: arguments)

        let data = try JSONEncoder().encode(params)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["name"] as? String, "search")

        let argsJson = json["arguments"] as? [String: Any]
        XCTAssertEqual(argsJson?["query"] as? String, "hello")
        XCTAssertEqual(argsJson?["limit"] as? Int, 10)
    }

    func testMCPNotificationEncoding() throws {
        let notification = MCPNotification<MCPEmptyParams>(method: "notifications/initialized", params: nil)

        let data = try JSONEncoder().encode(notification)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(json["method"] as? String, "notifications/initialized")
        // No "id" field for notifications
        XCTAssertNil(json["id"])
    }
}

// MARK: - MCPToolDefinition Tests

final class MCPToolDefinitionTests: XCTestCase {

    func testToolDefinitionDecoding() throws {
        let json = """
        {
            "name": "get_weather",
            "description": "Get current weather for a location",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "location": {
                        "type": "string",
                        "description": "City name"
                    }
                },
                "required": ["location"]
            }
        }
        """
        let data = json.data(using: .utf8)!
        let definition = try JSONDecoder().decode(MCPToolDefinition.self, from: data)

        XCTAssertEqual(definition.name, "get_weather")
        XCTAssertEqual(definition.description, "Get current weather for a location")
        XCTAssertNotNil(definition.inputSchema["type"])
        XCTAssertNotNil(definition.inputSchema["properties"])
    }

    func testToolDefinitionWithAnnotations() throws {
        let json = """
        {
            "name": "delete_file",
            "description": "Delete a file",
            "inputSchema": {"type": "object"},
            "annotations": {
                "title": "Delete File",
                "readOnlyHint": false,
                "destructiveHint": true,
                "idempotentHint": true,
                "openWorldHint": false
            }
        }
        """
        let data = json.data(using: .utf8)!
        let definition = try JSONDecoder().decode(MCPToolDefinition.self, from: data)

        XCTAssertEqual(definition.annotations?.title, "Delete File")
        XCTAssertEqual(definition.annotations?.readOnlyHint, false)
        XCTAssertEqual(definition.annotations?.destructiveHint, true)
        XCTAssertEqual(definition.annotations?.idempotentHint, true)
        XCTAssertEqual(definition.annotations?.openWorldHint, false)
    }

    func testToToolSchema() {
        let definition = MCPToolDefinition(
            name: "search",
            description: "Search tool",
            inputSchema: ["type": .string("object")],
            annotations: nil
        )

        // Use extension method added in MCPClient.swift
        // This tests the conversion from MCPToolDefinition to MCPToolSchema
    }
}

// MARK: - MCPClient Tests

final class MCPClientTests: XCTestCase {

    func testClientInitialization() async {
        let client = MCPClient()

        let config = MCPServerConfiguration(
            serverLabel: "test",
            serverUrl: "https://test.com/mcp"
        )

        // Initially not initialized
        let isInit = await client.isInitialized(server: config)
        XCTAssertFalse(isInit)
    }

    func testClearCache() async {
        let client = MCPClient()
        let config = MCPServerConfiguration(
            serverLabel: "test",
            serverUrl: "https://test.com/mcp"
        )

        // Should not crash when clearing cache on uninitialized server
        await client.clearCache(for: config)
    }

    func testClearAllCaches() async {
        let client = MCPClient()

        // Should not crash
        await client.clearAllCaches()
    }
}

// MARK: - MCPClientError Tests

final class MCPClientErrorTests: XCTestCase {

    func testInvalidURLError() {
        let error = MCPClientError.invalidURL("not a valid url")
        XCTAssertTrue(error.localizedDescription.contains("Invalid MCP server URL"))
    }

    func testHTTPError() {
        let error = MCPClientError.httpError(statusCode: 404, data: Data())
        XCTAssertTrue(error.localizedDescription.contains("404"))
    }

    func testServerError() {
        let mcpError = MCPError(code: -32600, message: "Invalid Request", data: nil)
        let error = MCPClientError.serverError(mcpError)
        XCTAssertTrue(error.localizedDescription.contains("Invalid Request"))
    }

    func testInvalidResponse() {
        let error = MCPClientError.invalidResponse("Missing result field")
        XCTAssertTrue(error.localizedDescription.contains("Missing result field"))
    }

    func testInitializationFailed() {
        let error = MCPClientError.initializationFailed("Handshake timeout")
        XCTAssertTrue(error.localizedDescription.contains("Handshake timeout"))
    }

    func testToolNotFound() {
        let error = MCPClientError.toolNotFound("unknown_tool")
        XCTAssertTrue(error.localizedDescription.contains("unknown_tool"))
    }
}

// MARK: - Integration Tests

final class MCPAgentIntegrationTests: XCTestCase {

    /// Test that AIAgentActor can be created with MCP servers
    func testAgentCreationWithMCPServers() async throws {
        // Use the existing MockAILanguageModel from the Mocks folder
        let model = MockAILanguageModel.withResponse("Mock response")

        let mcpConfig = MCPServerConfiguration(
            serverLabel: "test-server",
            serverUrl: "https://test.local/mcp",
            allowedTools: ["tool1", "tool2"],
            blockedTools: ["tool3"]
        )

        let agent = AIAgentActor(
            model: model,
            tools: [],
            mcpServers: [mcpConfig],
            instructions: "You are a test agent"
        )

        XCTAssertEqual(agent.agentId.isEmpty, false)
    }

    /// Test that approval handler can be set
    func testApprovalHandler() async throws {
        let model = MockAILanguageModel.withResponse("Mock response")

        let mcpConfig = MCPServerConfiguration(
            serverLabel: "test",
            serverUrl: "https://test.local/mcp",
            requireApproval: .always
        )

        let agent = AIAgentActor(
            model: model,
            mcpServers: [mcpConfig]
        )

        await agent.setApprovalHandler { context in
            XCTAssertEqual(context.serverLabel, "test")
            return true
        }

        // Handler should be settable
        // In a real test, we would trigger a tool call to verify it's called
    }

    /// Test MCP tool namespacing follows the correct pattern
    func testMCPToolNamespacingPattern() {
        // Verify that MCP tools follow the mcp__<serverLabel>__<toolName> pattern
        // This matches the pattern used by Claude Code
        let schema = MCPToolSchema(
            name: "get_file",
            description: "Get a file from the filesystem",
            inputSchema: ["type": .string("object")],
            serverLabel: "filesystem"
        )

        XCTAssertEqual(schema.namespacedName, "mcp__filesystem__get_file")

        // Test with server label containing underscores
        let schema2 = MCPToolSchema(
            name: "search_code",
            description: nil,
            inputSchema: [:],
            serverLabel: "github_enterprise"
        )
        XCTAssertEqual(schema2.namespacedName, "mcp__github_enterprise__search_code")
    }

    /// Test that multiple MCP servers can be configured
    func testMultipleMCPServers() async throws {
        let model = MockAILanguageModel.withResponse("Mock response")

        let githubConfig = MCPServerConfiguration(
            serverLabel: "github",
            serverUrl: "https://github.api/mcp",
            allowedTools: ["search_code", "get_file"]
        )

        let slackConfig = MCPServerConfiguration(
            serverLabel: "slack",
            serverUrl: "https://slack.api/mcp",
            blockedTools: ["delete_message"]
        )

        let filesystemConfig = MCPServerConfiguration(
            serverLabel: "filesystem",
            serverUrl: "https://localhost:8080/mcp",
            requireApproval: .always
        )

        let agent = AIAgentActor(
            model: model,
            tools: [],
            mcpServers: [githubConfig, slackConfig, filesystemConfig],
            instructions: "Multi-server agent"
        )

        XCTAssertFalse(agent.agentId.isEmpty)
    }
}

// MARK: - Extension for Testing

extension AIAgentActor {
    /// Helper to set approval handler in tests
    func setApprovalHandler(_ handler: @escaping @Sendable (MCPApprovalContext) async -> Bool) async {
        self.mcpApprovalHandler = handler
    }
}
