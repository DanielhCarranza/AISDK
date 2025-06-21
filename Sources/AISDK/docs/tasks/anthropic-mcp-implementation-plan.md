# Anthropic MCP (Model Context Protocol) Implementation Plan

## Overview

This document outlines the implementation plan for adding MCP (Model Context Protocol) support to the AnthropicService. MCP allows connecting to remote MCP servers directly from the Messages API without requiring a separate MCP client.

## Current State Analysis

### Existing Anthropic Implementation
- ✅ AnthropicService with beta feature support
- ✅ Tool calling system with AnthropicTool and AnthropicToolUseBlock
- ✅ Beta header management system
- ✅ Request/Response body structures
- ✅ Streaming support

### Current OpenAI MCP Implementation
- ✅ MCP tools in OpenAI Responses API
- ✅ ResponseMCPTool structure
- ✅ MCP approval request/response handling

## MCP Feature Requirements

### API Changes Required

#### 1. Beta Header Support
- ✅ Beta header system exists
- ⏳ Add MCP beta header: `"anthropic-beta": "mcp-client-2025-04-04"`

#### 2. Request Body Modifications
- ⏳ Add `mcp_servers` parameter to AnthropicMessageRequestBody
- ⏳ Support MCP server configuration objects

#### 3. Response Body Modifications  
- ⏳ Add MCP content block types:
  - `mcp_tool_use` content blocks
  - `mcp_tool_result` content blocks

#### 4. Streaming Support
- ⏳ Handle MCP content blocks in streaming responses

## Implementation Plan

### Phase 1: Core MCP Data Structures

#### 1.1 MCP Server Configuration
Create structures for MCP server configuration:
- `AnthropicMCPServer` - Server configuration
- `AnthropicMCPToolConfiguration` - Tool filtering configuration

#### 1.2 MCP Content Blocks
Add new content block types:
- `AnthropicMCPToolUseBlock` - MCP tool use content
- `AnthropicMCPToolResultBlock` - MCP tool result content

### Phase 2: Request/Response Integration

#### 2.1 Request Body Updates
- Add `mcpServers` property to `AnthropicMessageRequestBody`
- Update encoding to include MCP servers

#### 2.2 Response Body Updates
- Extend `AnthropicMessageResponseContent` enum with MCP cases
- Update decoding to handle MCP content blocks

#### 2.3 Streaming Updates
- Add MCP content block handling to streaming chunks
- Update `AnthropicMessageStreamingChunk` if needed

### Phase 3: Service Integration

#### 3.1 Beta Header Management
- Add MCP beta header to `BetaConfiguration`
- Update `authorizationHeaders` computation

#### 3.2 Service Methods
- Update `messageRequest` method for MCP support
- Update `streamingMessageRequest` method for MCP support

### Phase 4: Tool Integration

#### 4.1 MCP Tool Execution
- Create execution methods for MCP tools
- Handle MCP-specific tool result formatting

#### 4.2 Error Handling
- Add MCP-specific error cases
- Handle MCP server connection errors

### Phase 5: Testing & Documentation

#### 5.1 Unit Tests
- Test MCP server configuration
- Test MCP content block parsing
- Test streaming with MCP blocks

#### 5.2 Integration Tests
- Test end-to-end MCP workflows
- Test multiple MCP server scenarios

#### 5.3 Documentation
- Update usage documentation
- Add MCP examples
- Update API reference

## File Structure

### New Files to Create
```
Sources/AISDK/LLMs/Anthropic/
├── MCP/
│   ├── AnthropicMCPServer.swift
│   ├── AnthropicMCPContentBlocks.swift
│   └── AnthropicMCPConfiguration.swift
```

### Files to Modify
```
Sources/AISDK/LLMs/Anthropic/
├── AnthropicService.swift (beta headers, MCP support)
├── AnthropicMessageRequestBody.swift (mcp_servers parameter)
├── AnthropicMessageResponseBody.swift (MCP content blocks)
└── AnthropicMessageStreamingChunk.swift (MCP streaming)
```

## Implementation Details

### MCP Server Configuration Schema
```swift
public struct AnthropicMCPServer: Codable {
    public let type: String = "url"
    public let url: String
    public let name: String
    public let toolConfiguration: AnthropicMCPToolConfiguration?
    public let authorizationToken: String?
}

public struct AnthropicMCPToolConfiguration: Codable {
    public let enabled: Bool
    public let allowedTools: [String]?
}
```

### MCP Content Block Types
```swift
public enum AnthropicMessageResponseContent {
    case text(String)
    case toolUse(AnthropicToolUseBlock)
    case mcpToolUse(AnthropicMCPToolUseBlock)
    case mcpToolResult(AnthropicMCPToolResultBlock)
}
```

### Beta Configuration Update
```swift
public struct BetaConfiguration {
    public let tokenEfficientTools: Bool
    public let extendedThinking: Bool
    public let interleavedThinking: Bool 
    public let mcpClient: Bool // New
}
```

## Success Criteria

### Functional Requirements
- ✅ Connect to remote MCP servers via URL
- ✅ Support OAuth authorization tokens
- ✅ Handle multiple MCP servers per request
- ✅ Process MCP tool use blocks
- ✅ Process MCP tool result blocks
- ✅ Stream MCP content blocks
- ✅ Tool configuration filtering

### Technical Requirements
- ✅ Maintain backward compatibility
- ✅ Follow existing code patterns
- ✅ Comprehensive error handling
- ✅ Type-safe implementations
- ✅ Proper documentation

### Testing Requirements
- ✅ Unit test coverage > 90%
- ✅ Integration tests with mock MCP servers
- ✅ Streaming tests
- ✅ Error condition tests

## Timeline

### Week 1: Phase 1 & 2
- Implement core MCP data structures
- Update request/response bodies
- Basic parsing and encoding

### Week 2: Phase 3 & 4
- Integrate with AnthropicService
- Add beta header support
- Implement tool execution

### Week 3: Phase 5
- Comprehensive testing
- Documentation updates
- Integration testing

## Risk Mitigation

### Technical Risks
1. **MCP Server Compatibility**: Test with multiple MCP server implementations
2. **Streaming Complexity**: Incremental testing of streaming MCP blocks
3. **Beta API Changes**: Monitor Anthropic API changes closely

### Implementation Risks  
1. **Breaking Changes**: Maintain backward compatibility through optional parameters
2. **Performance Impact**: Benchmark MCP requests vs standard requests
3. **Error Handling**: Comprehensive error scenarios testing

## Notes

- MCP currently only supports tool calls (not full MCP spec)
- Requires HTTPS endpoints (no local STDIO servers)
- Not supported on Amazon Bedrock or Google Vertex
- OAuth token management is consumer responsibility

## Status Tracking

- [x] Phase 1: Core MCP Data Structures
  - [x] AnthropicMCPServer.swift created
  - [x] AnthropicMCPContentBlocks.swift created
- [x] Phase 2: Request/Response Integration
  - [x] Added mcpServers to AnthropicMessageRequestBody
  - [x] Extended AnthropicMessageResponseContent with MCP cases
  - [x] Updated encoding/decoding
- [x] Phase 3: Service Integration
  - [x] Added mcpClient to BetaConfiguration
  - [x] Updated beta header management
  - [x] Updated service methods to handle MCP
- [x] Phase 4: Tool Integration
  - [x] Added MCP utility methods to AnthropicService
  - [x] Added convenience initializers for MCP
  - [x] Added MCP content extraction methods
- [x] Phase 5: Testing & Documentation
  - [x] Created comprehensive usage documentation
  - [x] Added practical examples and best practices

## References

- [Anthropic MCP Documentation](https://docs.anthropic.com/en/docs/build-with-claude/mcp)
- [MCP Specification](https://modelcontextprotocol.io/introduction)
- [Existing OpenAI MCP Implementation](Sources/AISDK/LLMs/OpenAI/APIModels/Responses/) 