# Anthropic MCP (Model Context Protocol) Usage Guide

## Overview

The MCP (Model Context Protocol) feature enables connecting to remote MCP servers directly from the Anthropic Messages API without requiring a separate MCP client. This allows Claude to access tools and context from external services seamlessly.

## Prerequisites

- Anthropic API key
- MCP beta feature enabled: `"anthropic-beta": "mcp-client-2025-04-04"`
- Access to MCP servers (publicly accessible via HTTPS)

## Basic Setup

### 1. Initialize AnthropicService with MCP Support

```swift
import AISDK

// Initialize with MCP support enabled
let service = AnthropicService(
    apiKey: "your-anthropic-api-key",
    withMCPSupport: true
)

// Or enable MCP via beta configuration
let service = AnthropicService(apiKey: "your-api-key")
    .withBetaFeatures(mcpClient: true)
```

### 2. Configure MCP Servers

```swift
// Basic MCP server configuration
let mcpServer = AnthropicMCPServer(
    url: "https://example-server.modelcontextprotocol.io/sse",
    name: "example-mcp",
    authorizationToken: "your-oauth-token"
)

// MCP server with specific tools allowed
let restrictedServer = AnthropicMCPServer.withSpecificTools(
    url: "https://api.example.com/mcp",
    name: "restricted-mcp",
    allowedTools: ["search", "analyze"],
    authorizationToken: "your-token"
)

// MCP server with all tools enabled
let openServer = AnthropicMCPServer.withAllTools(
    url: "https://open-tools.example.com/mcp",
    name: "open-mcp"
)
```

## Making Requests with MCP

### Basic MCP Request

```swift
let request = AnthropicMessageRequestBody(
    maxTokens: 1000,
    messages: [
        AnthropicInputMessage(
            content: [.text("What tools do you have available?")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-20250514",
    mcpServers: [mcpServer]
)

do {
    let response = try await service.messageRequest(body: request)
    
    // Extract any MCP tool uses
    let mcpToolUses = service.extractMCPToolUses(from: response)
    
    for toolUse in mcpToolUses {
        print("MCP tool: \(toolUse.name) from \(toolUse.serverName)")
    }
    
} catch {
    print("Error: \(error)")
}
```

### Multiple MCP Servers

```swift
let servers = [
    AnthropicMCPServer(
        url: "https://search-server.example.com/mcp",
        name: "search-mcp",
        authorizationToken: "search-token"
    ),
    AnthropicMCPServer(
        url: "https://analytics-server.example.com/mcp",
        name: "analytics-mcp",
        authorizationToken: "analytics-token"
    )
]

let request = AnthropicMessageRequestBody(
    maxTokens: 1500,
    messages: [
        AnthropicInputMessage(
            content: [.text("Search for recent AI news and analyze the sentiment")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-20250514",
    mcpServers: servers
)
```

## Handling MCP Responses

### Processing MCP Tool Use Blocks

```swift
func processMCPResponse(_ response: AnthropicMessageResponseBody) {
    for content in response.content {
        switch content {
        case .text(let text):
            print("Text response: \(text)")
            
        case .mcpToolUse(let mcpToolUse):
            print("MCP Tool Use:")
            print("  - ID: \(mcpToolUse.id)")
            print("  - Tool: \(mcpToolUse.name)")
            print("  - Server: \(mcpToolUse.serverName)")
            print("  - Input: \(mcpToolUse.typedInput)")
            
        case .mcpToolResult(let mcpToolResult):
            print("MCP Tool Result:")
            print("  - Tool Use ID: \(mcpToolResult.toolUseId)")
            print("  - Is Error: \(mcpToolResult.isError)")
            print("  - Content: \(mcpToolResult.allTextContent)")
            
        case .toolUse(let toolUse):
            print("Regular Tool Use: \(toolUse.name)")
        }
    }
}
```

### Creating Tool Result Responses

```swift
// When Claude uses an MCP tool, you may need to provide results
// (This is typically handled by the MCP server, but shown for completeness)

func createMCPToolResultResponse(
    for toolUse: AnthropicMCPToolUseBlock,
    result: String,
    isError: Bool = false
) -> AnthropicMCPToolResultBlock {
    
    return AnthropicMCPToolResultBlock.textResult(
        toolUseId: toolUse.id,
        text: result,
        isError: isError
    )
}
```

## Streaming with MCP

```swift
let streamingRequest = AnthropicMessageRequestBody(
    maxTokens: 1000,
    messages: [
        AnthropicInputMessage(
            content: [.text("Use the search tool to find information about Swift programming")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-20250514",
    stream: true,
    mcpServers: [mcpServer]
)

do {
    let stream = try await service.streamingMessageRequest(body: streamingRequest)
    
    for try await chunk in stream {
        switch chunk {
        case .contentBlockStart(let start):
            if start.contentBlock.type == "mcp_tool_use" {
                print("Starting MCP tool use...")
            }
            
        case .contentBlockDelta(let delta):
            if let text = delta.delta.text {
                print("Delta text: \(text)")
            }
            
        case .messageStop:
            print("Message complete")
            
        default:
            break
        }
    }
    
} catch {
    print("Streaming error: \(error)")
}
```

## Advanced Configuration

### Tool Configuration Options

```swift
// Enable only specific tools from an MCP server
let toolConfig = AnthropicMCPToolConfiguration(
    enabled: true,
    allowedTools: ["search", "summarize", "translate"]
)

let server = AnthropicMCPServer(
    url: "https://multi-tool-server.example.com/mcp",
    name: "filtered-mcp",
    toolConfiguration: toolConfig,
    authorizationToken: "your-token"
)

// Disable all tools from a server (useful for context-only servers)
let contextOnlyServer = AnthropicMCPServer.withDisabledTools(
    url: "https://context-server.example.com/mcp",
    name: "context-mcp",
    authorizationToken: "context-token"
)
```

### Error Handling

```swift
do {
    let response = try await service.messageRequest(body: request)
    
    // Check for MCP-specific errors in tool results
    let mcpResults = service.extractMCPToolResults(from: response)
    
    for result in mcpResults {
        if result.isError {
            print("MCP tool error: \(result.allTextContent)")
        }
    }
    
} catch LLMError.networkError(let code, let message) {
    if code == 400 {
        print("Possible MCP configuration error: \(message)")
    }
} catch {
    print("Unexpected error: \(error)")
}
```

## Best Practices

### 1. Server Configuration

```swift
// Use descriptive server names to help Claude understand their purpose
let servers = [
    AnthropicMCPServer(
        url: "https://web-search.example.com/mcp",
        name: "web-search",  // Clear, descriptive name
        authorizationToken: token
    ),
    AnthropicMCPServer(
        url: "https://database.example.com/mcp", 
        name: "company-database",  // Specific context
        authorizationToken: dbToken
    )
]
```

### 2. Tool Management

```swift
// Be specific about allowed tools to improve performance
let productionServer = AnthropicMCPServer.withSpecificTools(
    url: "https://prod-api.example.com/mcp",
    name: "production-tools",
    allowedTools: ["get_user_data", "update_preferences", "send_notification"],
    authorizationToken: prodToken
)
```

### 3. Conversation Handling

```swift
func handleConversationWithMCP(
    service: AnthropicService,
    messages: [AnthropicInputMessage],
    mcpServers: [AnthropicMCPServer]
) async throws {
    
    let request = AnthropicMessageRequestBody(
        maxTokens: 2000,
        messages: messages,
        model: "claude-sonnet-4-20250514",
        mcpServers: mcpServers
    )
    
    let response = try await service.messageRequest(body: request)
    
    // Process the response and extract any tool uses
    let toolUses = service.extractMCPToolUses(from: response)
    
    if !toolUses.isEmpty {
        print("Claude wants to use \(toolUses.count) MCP tools")
        
        // In a real application, you might want to:
        // 1. Show the user what tools will be called
        // 2. Get approval if needed
        // 3. Handle the tool execution results
    }
}
```

## OAuth Authentication

When using MCP servers that require OAuth authentication:

```swift
// You need to handle OAuth flow externally and provide the access token
// Example using a theoretical OAuth helper:

func authenticateWithMCPServer() async throws -> String {
    // This is a placeholder - implement your OAuth flow
    let authHelper = MCPOAuthHelper(
        clientId: "your-client-id",
        serverUrl: "https://auth.example.com/oauth"
    )
    
    return try await authHelper.getAccessToken()
}

// Use the token in your MCP server configuration
let token = try await authenticateWithMCPServer()

let authenticatedServer = AnthropicMCPServer(
    url: "https://protected-api.example.com/mcp",
    name: "authenticated-mcp",
    authorizationToken: token
)
```

## Limitations and Considerations

1. **HTTPS Only**: MCP servers must be publicly accessible via HTTPS
2. **Tool Calls Only**: Only tool calling functionality is currently supported from the MCP spec
3. **No Local Servers**: STDIO-based local MCP servers are not supported
4. **Platform Restrictions**: Not available on Amazon Bedrock or Google Vertex
5. **Token Management**: OAuth token refresh is the client's responsibility

## Error Codes and Troubleshooting

| Error | Description | Solution |
|-------|-------------|----------|
| 400 Bad Request | Invalid MCP server configuration | Check server URL and configuration |
| 401 Unauthorized | Invalid or expired OAuth token | Refresh your OAuth token |
| 403 Forbidden | MCP server denies access | Check server permissions |
| 404 Not Found | MCP server not available | Verify server URL |
| 429 Rate Limited | Too many requests | Implement retry logic |

## Complete Example

```swift
import AISDK

class MCPExample {
    private let service: AnthropicService
    
    init() {
        self.service = AnthropicService(withMCPSupport: true)
    }
    
    func runExample() async {
        let searchServer = AnthropicMCPServer(
            url: "https://search-api.example.com/mcp",
            name: "web-search",
            authorizationToken: "your-token"
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 1000,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Search for AI news")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-20250514",
            mcpServers: [searchServer]
        )
        
        do {
            let response = try await service.messageRequest(body: request)
            print("Response received with \(response.content.count) content blocks")
        } catch {
            print("Error: \(error)")
        }
    }
}
```

This comprehensive guide covers all aspects of using MCP with the Anthropic service, from basic setup to advanced usage patterns and error handling. 