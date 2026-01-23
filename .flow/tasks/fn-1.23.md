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
Implemented GeminiClientAdapter for direct access to Google's Gemini API as part of the Phase 2 routing layer. 

Key features:
- Actor-based implementation conforming to ProviderClient protocol  
- Support for generateContent endpoint (non-streaming)
- Support for streamGenerateContent endpoint with SSE parsing
- Function calling (tools) support with functionDeclarations format
- System instruction support (systemInstruction field)
- JSON mode and JSON schema response formats
- Health status tracking via models endpoint
- Model capabilities lookup for Gemini model families (1.5, 2.0, 2.5)
- Comprehensive test coverage (36 tests)
## Evidence
- Commits: 29e0b813ff2cc8adf9d95d0ccb3a48d1c2a78ae7
- Tests: swift test --filter Gemini
- PRs: