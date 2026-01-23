# fn-1.23 Task 2.7: GeminiClientAdapter

## Description
Implement GeminiClientAdapter for direct access to Google's Gemini API as part of the Phase 2 routing layer. This adapter provides direct provider access for cost optimization, specific model access, or failover scenarios.

## Acceptance
- [x] Actor-based implementation conforming to ProviderClient protocol
- [x] Support for generateContent endpoint (non-streaming)
- [x] Support for streamGenerateContent endpoint with SSE parsing
- [x] Function calling (tools) support with functionDeclarations format
- [x] System instruction support (systemInstruction field)
- [x] JSON mode and JSON schema response formats
- [x] Health status tracking via models endpoint
- [x] Model capabilities lookup for Gemini model families
- [x] Comprehensive test coverage (36 tests)

## Done summary
Implemented GeminiClientAdapter following the same actor-based pattern as OpenAIClientAdapter and AnthropicClientAdapter. Key features:

1. **Direct API Access**: Connects to `generativelanguage.googleapis.com/v1beta` with API key authentication via query parameter
2. **Request Handling**: Converts ProviderRequest to Gemini's `contents[]` format with proper role mapping (user/model)
3. **Tool Calling**: Full support for functionDeclarations with AUTO/ANY/NONE modes via toolConfig
4. **Streaming**: SSE parsing with `?alt=sse` parameter, handles incremental text and function call events
5. **Error Handling**: Maps Gemini error responses to ProviderError types including content filtering detection
6. **Model Support**: Known models list includes Gemini 1.5, 2.0, and 2.5 families with capability detection

## Evidence
- Commits: (pending)
- Tests: GeminiClientAdapterTests (16), GeminiResponseParsingTests (6), GeminiRequestEncodingTests (7), GeminiErrorMappingTests (3), GeminiMultipartContentTests (4) - 36 total
- PRs:
