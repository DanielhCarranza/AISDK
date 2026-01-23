# fn-1.5 Task 1.2: AIStreamEvent (10+ Events)

## Description
Define comprehensive streaming event types for unified AI SDK streaming operations. The AIStreamEvent enum provides 17 distinct event types matching Vercel AI SDK 6.x semantics, covering text generation, reasoning, tool execution, structured output, file handling, usage tracking, and lifecycle events.

## Acceptance
- [x] AIStreamEvent enum with 10+ distinct event types
- [x] textDelta and textCompletion for text streaming
- [x] reasoningStart, reasoningDelta, reasoningFinish for o1/o3 reasoning models
- [x] toolCallStart, toolCallDelta, toolCall, toolCallFinish, toolResult for tool execution
- [x] objectDelta for structured output streaming
- [x] source for citations/sources
- [x] file for generated file content (images, etc.)
- [x] usage for token usage tracking
- [x] start, stepStart, stepFinish for lifecycle events
- [x] heartbeat for connection keepalive (new per spec)
- [x] finish with finishReason and final usage
- [x] error for error handling
- [x] All event types are Sendable-conforming
- [x] Build passes without errors

## Done summary
Enhanced the AIStreamEvent enum in `Sources/AISDK/Core/Models/AIStreamEvent.swift` to include 17 distinct event types as specified:

1. **Text Events**: textDelta, textCompletion
2. **Reasoning Events**: reasoningStart, reasoningDelta, reasoningFinish (for o1/o3 models)
3. **Tool Events**: toolCallStart, toolCallDelta, toolCall, toolCallFinish, toolResult
4. **Structured Output**: objectDelta
5. **Source Events**: source (for citations)
6. **File Events**: file (for generated images, etc.)
7. **Usage Events**: usage (token counts)
8. **Lifecycle Events**: start, stepStart, stepFinish, finish, error
9. **Connection Events**: heartbeat (new - for connection keepalive during long operations)

Supporting types already present and verified:
- AIFinishReason enum with stop, length, toolCalls, contentFilter, error, cancelled, unknown
- AIUsage struct with promptTokens, completionTokens, totalTokens, reasoningTokens
- AISource, AIFileEvent, AIStreamMetadata, AIStepResult, AIToolCallResult, AIToolResultData

Note: ToolMetadata Sendable warnings are pre-existing and will be addressed in Task 4.4 (AITool Protocol Redesigned) per the spec.
## Evidence
- Commits: 1ab7cc0e22064cfb339ef2361008fa4b859a41b9
- Tests: swift build
- PRs: