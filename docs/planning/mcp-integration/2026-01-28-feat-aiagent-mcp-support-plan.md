---
title: "feat: Add MCP Support to AIAgent"
type: feat
date: 2026-01-28
---

# feat: Add MCP Support to AIAgent

## Overview

Add Model Context Protocol (MCP) support to `AIAgentActor`, enabling agents to use tools from MCP servers alongside native `AITool` implementations. This follows the industry-standard "MCP as a tool" pattern used by Claude/Claude Code, OpenAI (Responses + Agents SDK), and Vercel AI SDK.

## Problem Statement / Motivation

Currently, MCP support exists only at the provider level:
- **ResponseAgent** supports MCP via `mcpServers: [MCPServerConfiguration]`
- **Anthropic provider** has `MCPServerConfig` and `AnthropicMCPToolUseBlock`
- **OpenAI provider** has `ResponseTool.mcp()` for the Responses API

However, **AIAgentActor** (our primary agent implementation) does NOT support MCP:
- Only accepts `tools: [AITool.Type]` - static tool types
- No MCP server configuration
- No MCP tool discovery or execution
- No MCP-specific events (approval requests, etc.)

This creates a gap where users must choose between:
1. Using `AIAgentActor` with native tools (no MCP)
2. Using `ResponseAgent` for MCP (OpenAI Responses API only)

**Goal:** Enable `AIAgentActor` to use MCP tools just like Claude Code does - MCP servers provide tools that the agent can discover and invoke seamlessly alongside native tools.

## Research Findings / Constraints (2026-01)

- MCP standard transports are **stdio** and **Streamable HTTP (SSE)**; WebSocket is legacy. Streamable HTTP uses an SSE stream for responses and POSTs for client messages, so expecting synchronous POST responses is not spec-compliant.
- MCP lifecycle requires an `initialize` → `initialized` handshake; for HTTP, subsequent requests must include the `MCP-Protocol-Version` header.
- Tools are discovered via `tools/list` (supports pagination with `cursor`/`nextCursor`) and executed via `tools/call` with `arguments` as a JSON object.
- Claude/Claude Code use namespaced tool names `mcp__<server_name>__<tool_name>`, allowlist filtering, and approval prompts; they also support **tool_search** with `defer_loading` to avoid listing all tools.
- OpenAI MCP server config includes `name`/`url`/`require_approval` and the client caches the `list_tools` result by default.
- Anthropic Messages API uses `mcp_tool_use` blocks and expects `mcp_tool_result` blocks when `mcp_servers` are enabled.

## Proposed Solution

Follow the "MCP as a tool" pattern from Claude/Claude Code and Vercel AI SDK:

1. **Add MCP configuration to AIAgentActor** - Accept optional MCP server configs at initialization
2. **Add a lightweight MCP client** - Handle initialize, list-tools, and tool-call via Streamable HTTP
3. **Expose MCP tools as namespaced function tools** - `mcp__<server>__<tool>` to avoid collisions
4. **Route tool execution to MCP client** - Use the same tool call loop, with optional approval hooks
5. **Keep it simple** - No over-engineering; MCP tools behave like any other tool

### Architecture Approach

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

## Technical Approach

### Phase 1: MCP Core Types (Extract + Extend)

Extract `MCPServerConfiguration` from `ResponseAgent.swift` into `Sources/AISDK/MCP/` and extend it for generic MCP usage (keep defaults for source compatibility).

```swift
// MCPServerConfiguration.swift

/// Configuration for connecting to an MCP server
public struct MCPServerConfiguration: Sendable, Codable {
    public let serverLabel: String
    public let serverUrl: String
    public let transport: MCPTransport
    public let requireApproval: MCPApprovalLevel
    public let allowedTools: [String]?
    public let blockedTools: [String]?
    public let headers: [String: String]?
    public let connectionTimeout: TimeInterval
    public let requestTimeout: TimeInterval
}

public enum MCPTransport: String, Sendable, Codable {
    case http    // Streamable HTTP (SSE)
    case stdio   // Local process
}

/// MCP tool schema from server discovery (store JSON as ProviderJSONValue for lossless conversion)
public struct MCPToolSchema: Sendable {
    public let name: String
    public let description: String?
    public let inputSchema: ProviderJSONValue
    public let serverLabel: String
}
```

### Phase 2: MCP Client + Transport (New)

Create a lightweight `MCPClient` (actor) that:

- Performs `initialize` → `initialized` handshake
- Supports **Streamable HTTP (SSE)** transport (GET for SSE, POST for requests)
- Correlates JSON-RPC responses by `id`
- Implements `tools/list` with pagination (`cursor` / `nextCursor`)
- Implements `tools/call` and returns structured content
- Caches tool lists (per server) to avoid repeated `tools/list`

```swift
public actor MCPClient {
    func listTools(server: MCPServerConfiguration) async throws -> [MCPToolSchema]
    func callTool(server: MCPServerConfiguration, name: String, arguments: ProviderJSONValue) async throws -> MCPCallResult
}
```

### Phase 3: Update AIAgentActor Initialization + Discovery

Modify `Sources/AISDK/Agents/AIAgentActor.swift`:

```swift
public actor AIAgentActor {
    private let mcpServers: [MCPServerConfiguration]
    private let mcpClient: MCPClient
    private var mcpToolSchemas: [MCPToolSchema] = []
    private var mcpToolsDiscovered = false

    // Init adds optional mcpServers
}

/// Discover tools once per agent instance (with pagination + cache)
private func discoverMCPTools() async throws {
    guard !mcpToolsDiscovered, !mcpServers.isEmpty else { return }

    var discovered: [MCPToolSchema] = []
    for server in mcpServers {
        do {
            let tools = try await mcpClient.listTools(server: server)
            let filtered = tools
                .filter { server.allowedTools == nil || server.allowedTools!.contains($0.name) }
                .filter { server.blockedTools == nil || !server.blockedTools!.contains($0.name) }
            discovered.append(contentsOf: filtered)
        } catch {
            print("[AIAgentActor] Failed MCP tool discovery for \(server.serverLabel): \(error)")
        }
    }
    mcpToolSchemas = discovered
    mcpToolsDiscovered = true
}
```

### Phase 4: Combined Tool Schema Generation

Update the agent loop to combine native and MCP tool schemas:

```swift
/// Build combined tool schemas for the request
private func buildCombinedToolSchemas() async throws -> [ToolSchema]? {
    // Discover MCP tools if not done yet
    try await discoverMCPTools()

    // Native tool schemas
    var allSchemas = tools.map { $0.jsonSchema() }

    // MCP tool schemas (converted to ToolSchema format - best-effort)
    for mcpTool in mcpToolSchemas {
        let schema = ToolSchema(
            type: .function,
            function: ToolFunction(
                name: "mcp__\(mcpTool.serverLabel)__\(mcpTool.name)",  // Namespaced
                description: mcpTool.description,
                parameters: convertToToolParameters(mcpTool.inputSchema) // lossy fallback
            )
        )
        allSchemas.append(schema)
    }

    return allSchemas.isEmpty ? nil : allSchemas
}
```

### Phase 5: MCP Tool Execution

Add MCP tool execution to the agent:

```swift
/// Execute a tool call (native or MCP)
private func executeToolCall(_ toolCall: AIToolCallResult) async throws -> AIToolResult {
    // Check if this is an MCP tool (namespaced with mcp__serverLabel__toolName)
    if toolCall.name.hasPrefix("mcp__") {
        return try await executeMCPToolCall(toolCall)
    }

    // Existing native tool execution
    return try await executeNativeToolCall(toolCall)
}

/// Execute an MCP tool call
private func executeMCPToolCall(_ toolCall: AIToolCallResult) async throws -> AIToolResult {
    // Parse the namespaced tool name: mcp__serverLabel__toolName
    let parts = toolCall.name.split(separator: "__")
    guard parts.count >= 3,
          parts[0] == "mcp",
          let serverLabel = parts[1].isEmpty ? nil : String(parts[1]),
          let toolName = parts.dropFirst(2).joined(separator: "__").isEmpty ? nil : parts.dropFirst(2).joined(separator: "__")
    else {
        throw AISDKErrorV2.toolNotFound(toolCall.name)
    }

    // Find the server config
    guard let server = mcpServers.first(where: { $0.serverLabel == serverLabel }) else {
        throw AISDKErrorV2.toolExecutionFailed(tool: toolCall.name, reason: "MCP server '\(serverLabel)' not configured")
    }

    // Check approval policy (emit event if needed)
    if server.requireApproval == .always {
        // TODO: Emit approval request event and wait for user response
        // For now, auto-approve
    }

    // Execute via MCP client (tools/call)
    let arguments = parseToolArguments(toolCall.arguments)
    let result = try await mcpClient.callTool(server: server, name: toolName, arguments: arguments)

    return MCPResultMapper.toAIToolResult(result, serverLabel: serverLabel)
}
```

### Phase 6: Approval Hook + Optional Stream Events

Rather than new event types, add an optional approval hook:

```swift
public struct MCPApprovalContext: Sendable {
    public let serverLabel: String
    public let toolName: String
    public let argumentsJSON: String
}

/// Optional callback to request approval before executing MCP tools
public var mcpApprovalHandler: (@Sendable (MCPApprovalContext) async -> Bool)?
```

## Acceptance Criteria

### Functional Requirements

- [x] `AIAgentActor` accepts optional `mcpServers: [MCPServerConfiguration]` parameter ✅ *Implemented in AIAgentActor.swift*
- [x] MCP tools are discovered via `tools/list` (with pagination) on first agent execution ✅ *`discoverMCPTools()` with pagination via `cursor`/`nextCursor`*
- [x] MCP tools appear alongside native tools in requests to the LLM ✅ *`buildCombinedToolSchemas()` merges native + MCP tools*
- [x] MCP tool names are namespaced as `mcp__<serverLabel>__<toolName>` to avoid collisions ✅ *`MCPToolSchema.namespacedName` property*
- [x] MCP tool calls are executed via `tools/call` JSON-RPC ✅ *`MCPClient.callTool()` implementation*
- [x] `allowedTools` / `blockedTools` filters restrict which MCP tools are exposed to the agent ✅ *Filtering in `discoverMCPTools()`*
- [x] Tool discovery failures for one server don't block other servers ✅ *Try/catch per server with warning log*
- [x] Existing native-only usage (`mcpServers` omitted) works unchanged ✅ *Default empty array, no breaking changes*
- [x] MCP initialize/initialized handshake is performed and HTTP requests include `MCP-Protocol-Version` ✅ *`MCPClient.initializeIfNeeded()` + header injection*

### Non-Functional Requirements

- [x] MCP tool discovery is lazy (only on first execute/streamExecute) ✅ *`mcpToolsDiscovered` flag, called at start of agent loops*
- [x] MCP server configs are immutable after initialization ✅ *`let mcpServers: [MCPServerConfiguration]`*
- [x] All MCP operations respect timeout policies ✅ *`TimeoutExecutor` with `server.requestTimeout`*
- [x] MCP-related types are `Sendable` for actor isolation ✅ *All MCP types conform to `Sendable`*
- [ ] Streamable HTTP transport (SSE) supported; stdio optional/future ⏳ *Currently HTTP POST only - SSE planned for future*

### Quality Gates

- [x] Unit tests for MCP tool discovery ✅ *MCPTests.swift - 46 tests*
- [x] Unit tests for MCP tool execution ✅ *MCPClientTests, MCPCallResultTests*
- [x] Integration test with mock MCP server ✅ *MCPIntegrationTests.swift - 11 tests with URLProtocol mocking*
- [x] Existing `AIAgentActor` tests pass unchanged ✅ *No breaking changes*
- [x] Documentation in code comments ✅ *Comprehensive DocC comments throughout*

## Implementation Files

| File | Action | Description |
|------|--------|-------------|
| `Sources/AISDK/MCP/MCPServerConfiguration.swift` | Create/Move | Extract + extend config (transport, headers, allow/block lists) |
| `Sources/AISDK/MCP/MCPTransport.swift` | Create | Streamable HTTP (SSE) + stdio transport definitions |
| `Sources/AISDK/MCP/MCPClient.swift` | Create | Initialize, list-tools, call-tools, request/response correlation |
| `Sources/AISDK/MCP/MCPMessages.swift` | Create | JSON-RPC request/response + MCP types |
| `Sources/AISDK/Agents/AIAgentActor.swift` | Modify | Add mcpServers param, discovery, combined tools, MCP execution |
| `Tests/AISDKTests/AIAgentActorMCPTests.swift` | Create | Unit/integration tests for MCP support |

## MVP Implementation (Updated)

Focus on HTTP/SSE transport + `tools/list` + `tools/call`, with best-effort schema conversion:

- `MCPServerConfiguration` extracted from `ResponseAgent.swift`, with added `transport`, `headers`, `allowedTools`, `blockedTools`.
- `MCPClient` handles `initialize`, `initialized`, SSE stream, and request/response correlation.
- `tools/list` pagination + cache.
- `tools/call` returns structured content mapped into `AIToolResult` + `ToolArtifact`s.

## References

### Internal References

- Existing MCP config: `Sources/AISDK/Agents/ResponseAgent.swift:931-978`
- Anthropic MCP types: `Sources/AISDK/LLMs/Anthropic/AnthropicMCPContentBlocks.swift`
- AIAgentActor: `Sources/AISDK/Agents/AIAgentActor.swift`
- AIAgent protocol: `Sources/AISDK/Core/Protocols/AIAgent.swift`

### External References

- [MCP Specification 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25)
- [MCP Transports (Streamable HTTP / stdio)](https://modelcontextprotocol.io/docs/learn/transports)
- [Claude Agent SDK MCP](https://docs.anthropic.com/en/docs/agents)
- [Claude MCP Connector (Messages API)](https://docs.anthropic.com/en/docs/agents-and-tools/mcp-connector)
- [OpenAI MCP Tool Guide](https://cookbook.openai.com/examples/mcp/mcp_tool_guide)
- [OpenAI Responses API - MCP](https://platform.openai.com/docs/api-reference/responses/create#responses-create-tools)
- [Vercel AI SDK MCP](https://ai-sdk.dev/docs/ai-sdk-core/mcp-tools)

### Design Decisions

1. **Tool Namespacing:** Using `mcp__<serverLabel>__<toolName>` prevents collisions between MCP tools and native tools, and between tools from different MCP servers.

2. **Lazy Discovery:** MCP tools are discovered on first agent execution rather than initialization. This avoids blocking agent creation on network calls.

3. **No Wrapper Class:** MCP tools are handled at the execution routing level. This avoids needing to make dynamic MCP tools conform to the static `AITool` protocol.

4. **Reuse Existing Types:** `MCPServerConfiguration` exists in ResponseAgent; this plan proposes extracting and reusing it for consistency.

## Future Considerations

- **SSE/Stdio Transports:** Currently only HTTP transport is supported. Stdio for local MCP servers could be added later.
- **Tool Search:** For large tool sets, implement Claude Code's "Tool Search" pattern to avoid context window bloat.
- **Approval UI:** The `requireApproval` policy currently auto-approves. A callback mechanism could be added for interactive approval.
- **Dynamic Tool Updates:** Support MCP `list_changed` notifications for servers that add/remove tools at runtime.
