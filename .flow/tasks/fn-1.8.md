# fn-1.8 Task 1.5: AIStepResult

## Description
Define AIStepResult model for multi-step agent execution. AIStepResult captures the outcome of each iteration in an agent loop, including text generated, tool calls made, tool results received, and token usage for the step.

## Acceptance
- [x] AIStepResult extracted to dedicated file at `Sources/AISDK/Core/Models/AIStepResult.swift`
- [x] Step index tracked correctly with `stepIndex` property
- [x] Tool calls preserved with `toolCalls: [AIToolCallResult]` array
- [x] Tool results included with `toolResults: [AIToolResultData]` array
- [x] Usage aggregated per step with `usage: AIUsage` property
- [x] Finish reason tracked with `finishReason: AIFinishReason`
- [x] Sendable conformance for thread safety
- [x] Codable conformance for serialization
- [x] Equatable conformance for testing
- [x] Helper properties: hasToolCalls, hasToolResults, completedNormally, wasTruncated, totalTokens
- [x] Empty result static property for testing/placeholder
- [x] Comprehensive test suite at `Tests/AISDKTests/Models/AIStepResultTests.swift`
- [x] Build passes without errors
- [x] All 19 tests pass

## Done summary
Extracted and enhanced AIStepResult from AIStreamEvent.swift to its own dedicated file following the pattern established by AITextResult and AIObjectResult.

**Implementation**:
- Created `Sources/AISDK/Core/Models/AIStepResult.swift` with:
  - Full documentation with usage examples
  - Sendable, Codable, and Equatable conformances
  - Helper properties for common checks (hasToolCalls, hasToolResults, completedNormally, wasTruncated, totalTokens)
  - Static `empty` property for testing
- Added Codable and Equatable conformances to AIToolResultData (metadata intentionally excluded from encoding/comparison)
- Updated `Sources/AISDK/Core/Models/AIStreamEvent.swift` to reference the extracted type

**Tests**:
- Created `Tests/AISDKTests/Models/AIStepResultTests.swift` with 19 comprehensive tests:
  - Basic initialization (minimal and full)
  - Step index tracking
  - Tool calls and results preservation
  - Usage aggregation per step
  - Helper properties validation
  - Encoding/decoding round-trip
  - Equatable conformance
  - Finish reason handling
  - Empty result validation

## Evidence
- Commits: (pending)
- Tests: swift test --filter AIStepResultTests (19 tests pass)
- PRs:
