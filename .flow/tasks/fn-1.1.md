# fn-1.1 Task 0.1: AILanguageModelAdapter

## Description
Wrap existing `LLM` protocol to conform to new `AILanguageModel` protocol. This adapter enables gradual migration from the legacy LLM protocol to the new unified interface.

## Acceptance
- [x] AILanguageModel protocol defined with generateText, streamText, generateObject, streamObject methods
- [x] AIMessage unified message type with role, content, toolCalls support
- [x] AITextRequest/AITextResult types for text generation
- [x] AIObjectRequest/AIObjectResult types for structured output
- [x] AILanguageModelAdapter wraps legacy LLM implementations
- [x] Factory methods for OpenAI and Anthropic providers
- [x] Proper message format conversion between new and legacy types
- [x] Streaming support with proper event emission
- [x] Build passes without errors

## Done summary
Created the AILanguageModel protocol and AILanguageModelAdapter that wraps the existing LLM protocol for backward compatibility. The implementation includes:

1. **AILanguageModel.swift** (`Sources/AISDK/Core/Protocols/`)
   - AIMessage type with Role, Content, ContentPart, ToolCall
   - AILanguageModel protocol with generateText, streamText, generateObject, streamObject
   - AITextRequest/AITextResult for text generation
   - AIObjectRequest/AIObjectResult for structured output
   - DataSensitivity enum for PHI protection
   - StreamBufferPolicy for memory control

2. **AILanguageModelAdapter.swift** (`Sources/AISDK/Core/Adapters/Legacy/`)
   - Wraps any LLM implementation
   - Converts AIMessage to legacy Message enum
   - Handles streaming with proper event emission
   - Factory methods: fromOpenAI, fromAnthropic, from(generic)

## Evidence
- Commits: (pending)
- Tests: Build passes
- PRs: (pending)
