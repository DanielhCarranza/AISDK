# fn-1.9 Task 1.6: AIUsage/AIFinishReason

## Description
Create dedicated AIUsage and AIFinishReason types for token usage tracking and completion reason handling, following Vercel AI SDK 6.x semantics.

## Acceptance
- [x] AIUsage struct with promptTokens, completionTokens, totalTokens, reasoningTokens, cachedTokens
- [x] AIFinishReason enum with all standard finish reasons (stop, length, toolCalls, contentFilter, error, cancelled, unknown)
- [x] Legacy conversion initializers for provider compatibility
- [x] Addition operator for combining usage across multi-step operations
- [x] Helper properties (isSuccess, mayBeTruncated) on AIFinishReason
- [x] Comprehensive unit tests (40 tests covering all functionality)
- [x] Extracted from AIStreamEvent.swift to dedicated AIUsage.swift file

## Done summary
Created dedicated `Sources/AISDK/Core/Models/AIUsage.swift` containing:
- `AIUsage`: Token usage struct with prompt/completion/total/reasoning/cached tokens, legacy initializer, and addition operator for multi-step usage aggregation
- `AIFinishReason`: Finish reason enum with all standard cases, legacy conversion initializer, and helper properties (isSuccess, mayBeTruncated)

Added `Tests/AISDKTests/Models/AIUsageTests.swift` with 40 comprehensive tests covering initialization, arithmetic, equality, hashing, codable conformance, and all finish reason conversions.

Updated `AIStreamEvent.swift` to reference the new file instead of embedding the types.
## Evidence
- Commits:
- Tests: swift test --filter AIUsageTests|AIFinishReasonTests
- PRs: