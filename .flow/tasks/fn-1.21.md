# fn-1.21 Task 2.5: OpenAIClientAdapter

## Description
TBD

## Acceptance
- [ ] TBD

## Done summary
# Task fn-1.21: OpenAIClientAdapter Implementation

## Summary
Implemented OpenAIClientAdapter as a direct ProviderClient for Phase 2 (Provider & Routing Layer) of the AISDK modernization.

## Implementation Details

### Files Created

1. **Sources/AISDK/Core/Providers/OpenAIClientAdapter.swift**
   - `OpenAIClientAdapter` actor - fully Sendable provider client implementation
   - Direct OpenAI API access (bypassing routers like OpenRouter/LiteLLM)
   - Non-streaming `execute(request:)` with response parsing
   - Streaming `stream(request:)` with SSE parsing
   - Health status tracking with `refreshHealthStatus()`
   - Model availability checking with caching (5-minute TTL)
   - Full tool call support (both request and response)
   - Response format support (text, json_object, json_schema)
   - Multipart content support (text, images, image URLs)
   - Model capabilities for GPT-4o, GPT-4, GPT-3.5, o1/o3 series
   - Organization header support for multi-org accounts
   - Comprehensive error handling mapped to ProviderError types

2. **Tests/AISDKTests/Core/Providers/OpenAIClientAdapterTests.swift**
   - `OpenAIClientAdapterTests` - 14 tests for initialization, health, conformance, capabilities
   - `OpenAIResponseParsingTests` - 6 tests for response JSON parsing
   - `OpenAIRequestEncodingTests` - 7 tests for request body encoding
   - `OpenAIErrorMappingTests` - 5 tests for error handling
   - `OpenAIMultipartContentTests` - 4 tests for multipart content
   - All 36 tests passing

### Key Design Decisions

1. **Actor-based**: Using Swift actor for thread safety and Sendable conformance
2. **Direct API Access**: Bypasses routers for cost optimization and failover scenarios
3. **Streaming via SSE**: Server-Sent Events parsing for real-time token streaming
4. **Model caching**: 5-minute cache for available models list to reduce API calls
5. **Graceful error mapping**: HTTP status codes mapped to ProviderError cases
6. **Model capabilities**: Built-in capability detection for common OpenAI models

### API Types Implemented

- `OpenAIRequestBody` - Request encoding with messages, tools, options
- `OpenAIMessage` - Message with text or multipart content
- `OpenAIContent` - Text or array of content parts (text, image_url)
- `OpenAIToolCall` - Tool call representation
- `OpenAICompletionResponse` - Non-streaming response
- `OpenAIStreamChunk` - SSE stream chunk with delta
- `OpenAIUsage` - Token usage including cached and reasoning tokens

### Verification

- Build: `swift build` - Success
- Tests: `swift test --filter OpenAIClientAdapter` - 36 tests passed
## Evidence
- Commits: c275d1ed02e23cb3191b95fa08ff37e5793d297f
- Tests: swift test --filter OpenAIClientAdapter (36 tests passed)
- PRs: