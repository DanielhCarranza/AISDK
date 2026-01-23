# Task fn-1.22: Add AnthropicClientAdapter

## Summary
Added AnthropicClientAdapter for Phase 2 routing layer with direct Anthropic API access, full streaming support, tool calling, and health status tracking.

## Implementation Details

### Files Created
- `Sources/AISDK/Core/Providers/AnthropicClientAdapter.swift` - Direct Anthropic provider client

### Key Features
1. **Direct Anthropic API Access** - Bypasses routers for direct provider connectivity
2. **Full Streaming Support** - SSE parsing with text, tool call, and thinking deltas
3. **Tool Calling** - Proper Anthropic format conversion with input_schema
4. **Health Status Tracking** - Lightweight API call to verify connectivity
5. **Known Models** - Claude model list and capability detection

### Design Decisions
- Used ACA-prefixed private types to avoid collision with existing Anthropic types in the codebase
- Implemented system message extraction (Anthropic handles system separately)
- Support for extended thinking via thinking_delta stream events
- Proper error parsing for both nested and flat Anthropic error formats

### Testing
- Build verified successful with `swift build`
- ProviderClient test suite runs without errors
