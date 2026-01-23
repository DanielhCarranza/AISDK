# fn-1.4 Task 1.1: AILanguageModel Protocol

## Description
Define the core AILanguageModel protocol with unified API surface for all AI language model providers. This protocol provides generateText, streamText, generateObject, and streamObject methods with proper type safety and Sendable conformance.

## Acceptance
- [x] AILanguageModel protocol defined with generateText, streamText, generateObject, streamObject methods
- [x] Protocol requires provider, modelId, capabilities properties
- [x] Protocol conforms to Sendable for concurrency safety
- [x] AITextRequest/AITextResult types defined with all required fields
- [x] AIObjectRequest/AIObjectResult types defined with generic type parameter
- [x] DataSensitivity enum for PHI protection (standard, sensitive, phi)
- [x] StreamBufferPolicy for memory control with bounded capacity
- [x] Default implementation for generateObject using streamObject
- [x] Build passes without errors

## Done summary
Verified the AILanguageModel protocol implementation in `Sources/AISDK/Core/Protocols/AILanguageModel.swift`. The protocol was already implemented as part of fn-1.1 (AILanguageModelAdapter) since the adapter required the protocol to exist. The implementation includes:

1. **AILanguageModel Protocol** (`Sources/AISDK/Core/Protocols/AILanguageModel.swift`)
   - Sendable conformance for thread safety
   - provider, modelId, capabilities properties
   - generateText, streamText methods for text generation
   - generateObject, streamObject methods for structured output
   - Default implementation for generateObject using streamObject

2. **Request/Result Types**
   - AITextRequest with messages, model, maxTokens, temperature, tools, allowedProviders, sensitivity, bufferPolicy
   - AITextResult with text, toolCalls, usage, finishReason, requestId, model, provider
   - AIObjectRequest<T> with generic schema support
   - AIObjectResult<T> with generic object, usage, finishReason

3. **Supporting Types**
   - DataSensitivity enum (standard, sensitive, phi) for PHI protection
   - StreamBufferPolicy with capacity and overflow behavior
   - AIMessage unified message type with roles, content parts, tool calls

Note: The spec suggested `Actor` conformance, but this was intentionally kept as `Sendable` only to maintain compatibility with the Phase 0 adapter layer (fn-1.1) which wraps non-actor LLM implementations. New native implementations are encouraged to use actors internally.

## Evidence
- Commits: Already implemented in 27b11abb47461d373d196eb3ac880c7f1bce2e5e (fn-1.1)
- Tests: swift build passes
- PRs:
