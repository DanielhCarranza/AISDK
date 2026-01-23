# Task fn-1.18: OpenRouterClient (Primary)

## Summary

Implemented OpenRouterClient as the primary ProviderClient for Phase 2 (Provider & Routing Layer) of the AISDK modernization.

## Implementation Details

### Files Created

1. **Sources/AISDK/Core/Providers/OpenRouterClient.swift**
   - `OpenRouterClient` actor - fully Sendable provider client implementation
   - OpenAI-compatible API for 200+ models through OpenRouter
   - Non-streaming `execute(request:)` with response parsing
   - Streaming `stream(request:)` with SSE parsing
   - Health status tracking with `refreshHealthStatus()`
   - Model availability checking with caching (5-minute TTL)
   - Full tool call support (both request and response)
   - Response format support (text, json_object, json_schema)
   - Comprehensive error handling mapped to ProviderError types
   - App metadata headers (X-Title, HTTP-Referer) for analytics

2. **Tests/AISDKTests/Core/Providers/OpenRouterClientTests.swift**
   - `OpenRouterClientTests` - 10 tests for initialization, health, conformance
   - `OpenRouterResponseParsingTests` - 6 tests for response JSON parsing
   - `OpenRouterRequestEncodingTests` - 6 tests for request body encoding
   - All 22 tests passing

### Key Design Decisions

1. **Actor-based**: Using Swift actor for thread safety and Sendable conformance
2. **OpenAI-compatible API**: OpenRouter uses OpenAI's API format, making integration seamless
3. **Streaming via SSE**: Server-Sent Events parsing for real-time token streaming
4. **Model caching**: 5-minute cache for available models list to reduce API calls
5. **Graceful error mapping**: HTTP status codes mapped to ProviderError cases

### API Types Implemented

- `OpenRouterRequestBody` - Request encoding with messages, tools, options
- `OpenRouterMessage` - Message with text or multipart content
- `OpenRouterContent` - Text or array of content parts (text, image_url)
- `OpenRouterToolCall` - Tool call representation
- `OpenRouterCompletionResponse` - Non-streaming response
- `OpenRouterStreamChunk` - SSE stream chunk with delta

### Verification

- Build: `swift build` - Success
- Tests: `swift test --filter OpenRouterClient` - 22 tests passed
