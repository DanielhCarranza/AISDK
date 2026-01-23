# Task fn-1.17: ProviderClient Protocol

## Summary

Implemented the ProviderClient protocol for Phase 2 (Provider & Routing Layer) of the AISDK modernization.

## Implementation Details

### Files Created

1. **Sources/AISDK/Core/Providers/ProviderClient.swift**
   - `ProviderClient` protocol - low-level interface for AI provider HTTP clients
   - `ProviderHealthStatus` enum - health/degraded/unhealthy/unknown status
   - `ProviderRequest` struct - transport-level request with model, messages, parameters
   - `ProviderResponse` struct - response with content, tool calls, usage, finish reason
   - `ProviderToolChoice` enum - auto/none/required/tool(name)
   - `ProviderResponseFormat` enum - text/json/jsonSchema
   - `ProviderToolCall` struct - tool call with id, name, arguments
   - `ProviderUsage` struct - token usage tracking
   - `ProviderFinishReason` enum - stop/length/toolCalls/contentFilter/functionCall/unknown
   - `ProviderStreamEvent` enum - streaming events for provider communication
   - `ProviderError` enum - comprehensive error types with LocalizedError conformance

2. **Tests/AISDKTests/Core/Providers/ProviderClientTests.swift**
   - 20 tests covering all types, conversions, and a MockProviderClient implementation
   - All tests passing

### Key Design Decisions

1. **Separation of Concerns**: ProviderClient focuses on transport/HTTP mechanics, while AILanguageModel provides high-level semantics
2. **Sendable Conformance**: All types are Sendable for Swift 6 concurrency safety
3. **Conversion Extensions**: Bidirectional conversions between Provider types and unified AI types (AITextRequest, AITextResult, AIStreamEvent)
4. **Default Implementations**: Protocol extensions for common behaviors (isModelAvailable, capabilities)

### Verification

- Build: `swift build` - Success
- Tests: `swift test --filter ProviderClientTests` - 26 tests passed
