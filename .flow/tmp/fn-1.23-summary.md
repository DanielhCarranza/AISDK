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
