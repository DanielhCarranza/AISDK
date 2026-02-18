# MCP Implementation Summary

**Date:** 2026-01-28
**Status:** Core Implementation Complete
**Plan Reference:** [2026-01-28-feat-aiagent-mcp-support-plan.md](2026-01-28-feat-aiagent-mcp-support-plan.md)

---

## Overview

This document summarizes the Model Context Protocol (MCP) implementation for `AIAgentActor` in AISDK. The implementation follows the "MCP as a tool" pattern used by Claude Code, OpenAI, and Vercel AI SDK, enabling agents to discover and invoke tools from MCP servers alongside native `AITool` implementations.

---

## Implementation Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        AIAgentActor                             │
│  ┌─────────────────┐     ┌─────────────────────────────────┐   │
│  │  Native Tools   │     │        MCP Integration          │   │
│  │  [AITool.Type]  │     │  ┌───────────────────────────┐  │   │
│  │                 │     │  │   MCPServerConfiguration  │  │   │
│  │  - SearchTool   │     │  │   - serverUrl             │  │   │
│  │  - Calculator   │     │  │   - serverLabel           │  │   │
│  │  - ...          │     │  │   - requireApproval       │  │   │
│  └─────────────────┘     │  └───────────────────────────┘  │   │
│           │              │              │                   │   │
│           ▼              │              ▼                   │   │
│  ┌─────────────────────────────────────────────────────┐   │   │
│  │            Combined Tool Registry                    │   │   │
│  │  [ToolSchema] = nativeSchemas + mcpToolSchemas      │   │   │
│  └─────────────────────────────────────────────────────┘   │   │
│                          │                                  │   │
│                          ▼                                  │   │
│  ┌─────────────────────────────────────────────────────┐   │   │
│  │              Tool Execution Router                   │   │   │
│  │  if (isMCPTool) → MCPClient.callTool()              │   │   │
│  │  else           → AITool.execute()                   │   │   │
│  └─────────────────────────────────────────────────────┘   │   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Implemented Files

### Source Files

| File | Description |
|------|-------------|
| `Sources/AISDK/MCP/MCPServerConfiguration.swift` | Core MCP configuration types including `MCPServerConfiguration`, `MCPTransport`, `MCPApprovalLevel`, `MCPToolSchema`, `MCPApprovalContext`, `MCPCallResult`, and `MCPContent` |
| `Sources/AISDK/MCP/MCPMessages.swift` | JSON-RPC 2.0 message types for MCP protocol: `MCPRequest`, `MCPResponse`, `MCPNotification`, `MCPError`, initialization params, tool list params, and tool call params |
| `Sources/AISDK/MCP/MCPClient.swift` | Actor-based MCP client handling `initialize` handshake, `tools/list` with pagination, `tools/call` execution, and response correlation |
| `Sources/AISDK/Agents/AIAgentActor.swift` | Modified to accept `mcpServers` parameter, discover MCP tools lazily, build combined tool schemas, and route MCP tool execution |

### Test Files

| File | Test Count | Description |
|------|------------|-------------|
| `Tests/AISDKTests/MCPTests.swift` | 46 tests | Unit tests for all MCP types, configurations, and client operations |
| `Tests/AISDKTests/MCPIntegrationTests.swift` | 11 tests | Integration tests with URLProtocol-based HTTP mocking for full MCP flow |

**Total MCP Tests: 57**

---

## Key Components

### 1. MCPServerConfiguration

Configuration for connecting to an MCP server:

```swift
public struct MCPServerConfiguration: Sendable, Codable {
    public let serverLabel: String           // Unique identifier for namespacing
    public let serverUrl: String             // Server endpoint URL
    public let transport: MCPTransport       // .http or .stdio
    public let requireApproval: MCPApprovalLevel  // .never, .always, .onSensitive
    public let allowedTools: [String]?       // Whitelist filter
    public let blockedTools: [String]?       // Blacklist filter
    public let headers: [String: String]?    // Custom HTTP headers
    public let connectionTimeout: TimeInterval
    public let requestTimeout: TimeInterval
}
```

### 2. MCPClient (Actor)

Handles MCP protocol communication:

```swift
public actor MCPClient {
    // Discover tools with pagination support
    func listTools(server: MCPServerConfiguration) async throws -> [MCPToolSchema]

    // Execute a tool and return result
    func callTool(server: MCPServerConfiguration, name: String, arguments: [String: AIProxyJSONValue]) async throws -> MCPCallResult

    // Clear cached tools for re-discovery
    func clearCache(for server: MCPServerConfiguration)
}
```

### 3. Tool Namespacing

MCP tools are namespaced as `mcp__<serverLabel>__<toolName>` to prevent collisions:

```swift
// Example: GitHub MCP server with "search_code" tool
// Namespaced name: mcp__github__search_code
```

### 4. AIAgentActor MCP Integration

New methods added to `AIAgentActor`:

```swift
// Lazy discovery on first execution
private func discoverMCPTools() async throws

// Merge native + MCP tool schemas
private func buildCombinedToolSchemas() async throws -> [ToolSchema]?

// Route execution to MCP client
private func executeMCPToolCall(_ toolCall: AIToolCallResult) async throws -> AIToolResult

// Convert MCP JSON Schema to ToolParameters
private func convertMCPSchemaToParameters(_ schema: AIProxyJSONValue) -> ToolParameters
```

### 5. Approval Handler

Optional callback for tool execution approval:

```swift
public struct MCPApprovalContext: Sendable {
    public let serverLabel: String
    public let toolName: String
    public let argumentsJSON: String
}

public var mcpApprovalHandler: (@Sendable (MCPApprovalContext) async -> Bool)?
```

---

## Test Coverage

### Unit Tests (MCPTests.swift - 46 tests)

- **MCPServerConfiguration Tests**
  - Default values initialization
  - Custom values initialization
  - JSON encoding/decoding round-trip

- **MCPTransport Tests**
  - HTTP transport encoding
  - Stdio transport encoding

- **MCPApprovalLevel Tests**
  - Never level encoding
  - Always level encoding
  - OnSensitive level encoding

- **MCPToolSchema Tests**
  - Basic initialization
  - Namespaced name generation
  - With all optional fields

- **MCPApprovalContext Tests**
  - Initialization with all fields

- **MCPCallResult Tests**
  - Success result
  - Error result
  - Result with multiple content items
  - Text content helper
  - Image content helper
  - Error helper

- **MCPContent Tests**
  - Text content
  - Image content
  - Resource content

- **MCPMessages Tests**
  - Request encoding
  - Response decoding (success)
  - Response decoding (error)
  - Notification encoding
  - Initialize params encoding
  - Initialize result decoding
  - List tools params encoding
  - List tools result decoding
  - Call tool params encoding
  - Call tool result decoding

- **MCPClient Tests**
  - Initialization
  - List tools (basic)
  - List tools (with pagination)
  - List tools (cached)
  - Call tool
  - Clear cache
  - HTTP error handling
  - Server error handling

- **AIAgentActor MCP Integration Tests**
  - Initialization with MCP servers
  - Tool schema building
  - MCP tool execution
  - Native tool execution
  - Approval handler

### Integration Tests (MCPIntegrationTests.swift - 11 tests)

- `testMCPInitializeHandshake` - Verifies initialize → initialized flow
- `testMCPToolDiscovery` - Full tool discovery with schema conversion
- `testMCPToolExecution` - Tool call with argument passing
- `testMCPToolFiltering_AllowedTools` - Whitelist filtering
- `testMCPToolFiltering_BlockedTools` - Blacklist filtering
- `testMCPToolNamespacing` - Namespace parsing and routing
- `testMCPApprovalFlow_Approved` - Approval handler allows execution
- `testMCPApprovalFlow_Denied` - Approval handler blocks execution
- `testMCPCombinedWithNativeTools` - Native + MCP tools together
- `testMCPMultipleServers` - Multiple MCP servers discovery
- `testMCPServerFailureIsolation` - One server failure doesn't block others

---

## Protocol Compliance

### MCP Specification 2025-11-25

| Feature | Status | Notes |
|---------|--------|-------|
| JSON-RPC 2.0 | ✅ Complete | Request/response correlation |
| `initialize` handshake | ✅ Complete | Capabilities exchange |
| `initialized` notification | ✅ Complete | Sent after initialize |
| `MCP-Protocol-Version` header | ✅ Complete | Added to all post-init requests |
| `tools/list` | ✅ Complete | With pagination support |
| `tools/call` | ✅ Complete | Returns structured content |
| HTTP transport | ✅ Complete | POST-based |
| SSE transport | ⏳ Planned | For streaming responses |
| stdio transport | ⏳ Planned | For local MCP servers |

---

## External References

### MCP Specification
- [MCP Specification 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25)
- [MCP Transports (Streamable HTTP / stdio)](https://modelcontextprotocol.io/docs/learn/transports)

### Industry Implementations
- [Claude Agent SDK MCP](https://docs.anthropic.com/en/docs/agents)
- [Claude MCP Connector (Messages API)](https://docs.anthropic.com/en/docs/agents-and-tools/mcp-connector)
- [OpenAI MCP Tool Guide](https://cookbook.openai.com/examples/mcp/mcp_tool_guide)
- [OpenAI Responses API - MCP](https://platform.openai.com/docs/api-reference/responses/create#responses-create-tools)
- [Vercel AI SDK MCP](https://ai-sdk.dev/docs/ai-sdk-core/mcp-tools)

---

## Usage Example

```swift
import AISDK

// Configure MCP servers
let githubMCP = MCPServerConfiguration(
    serverLabel: "github",
    serverUrl: "https://api.github.com/mcp",
    headers: ["Authorization": "Bearer \(token)"]
)

let filesystemMCP = MCPServerConfiguration(
    serverLabel: "filesystem",
    serverUrl: "http://localhost:8080/mcp",
    requireApproval: .always
)

// Create agent with MCP support
let agent = AIAgentActor(
    model: myModel,
    tools: [SearchTool.self, CalculatorTool.self],  // Native tools
    mcpServers: [githubMCP, filesystemMCP]           // MCP servers
)

// Optional: Add approval handler
agent.mcpApprovalHandler = { context in
    print("Tool \(context.toolName) from \(context.serverLabel) wants to execute")
    print("Arguments: \(context.argumentsJSON)")
    return true  // or prompt user
}

// Execute - MCP tools discovered automatically on first run
let result = try await agent.execute(prompt: "Search for Swift repositories")
```

---

## Future Considerations

1. **SSE Transport** - Add Server-Sent Events for streaming MCP responses
2. **Stdio Transport** - Support local MCP servers via stdin/stdout
3. **Tool Search** - Implement Claude Code's "Tool Search" pattern for large tool sets
4. **Dynamic Updates** - Support MCP `list_changed` notifications
5. **Resource Support** - Add MCP `resources/list` and `resources/read` methods
6. **Prompt Support** - Add MCP `prompts/list` and `prompts/get` methods
