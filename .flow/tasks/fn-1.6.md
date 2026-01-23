# fn-1.6 Task 1.3: AITextRequest/AITextResult

## Description
TBD

## Acceptance
- [ ] TBD

## Done summary
## Implementation Summary

Created `AITextRequest` and `AITextResult` model files in `Sources/AISDK/Core/Models/` with the following new types and features:

### New Files Created
- `AITextRequest.swift` - Request model with PHI protection and memory control fields
- `AITextResult.swift` - Result model with helper properties
- `Tests/AISDKTests/Models/AITextRequestTests.swift` - 17 tests for request types
- `Tests/AISDKTests/Models/AITextResultTests.swift` - 7 tests for result type

### AITextRequest Fields (per spec Task 1.3)
- `allowedProviders: Set<String>?` - PHI protection to restrict which providers can handle requests
- `sensitivity: DataSensitivity` - Data classification (standard/sensitive/phi)
- `bufferPolicy: StreamBufferPolicy?` - Memory control for stream buffering

### DataSensitivity Enum
- `.standard` - Can use any provider
- `.sensitive` - Requires trusted providers
- `.phi` - Requires HIPAA-compliant providers

### StreamBufferPolicy Struct
- `capacity: Int` - Maximum events to buffer (default: 1000)
- `overflowBehavior` - dropOldest, dropNewest, or suspendProducer
- Static presets: `.bounded` (1000), `.unbounded`

### Helper Methods
- `canUseProvider(_:)` - Check if provider is allowed for PHI protection
- `withSensitivity(_:)` - Create copy with updated sensitivity
- `withAllowedProviders(_:)` - Create copy with provider restrictions
- `withBufferPolicy(_:)` - Create copy with custom buffer policy

### AITextResult Helpers
- `hasToolCalls` - Check if result has any tool calls
- `completedNormally` - Check if finished with stop or toolCalls
- `wasTruncated` - Check if truncated due to length
- `totalTokens` - Convenience accessor for total token count
- `AITextResult.empty` - Empty result for testing

### Changes to Existing Files
- Refactored `AILanguageModel.swift` to import types from new files
- Added `Equatable` conformance to `AIToolCallResult` in `AIStreamEvent.swift`
## Evidence
- Commits:
- Tests: AITextRequestTests - 10 tests, DataSensitivityTests - 3 tests, StreamBufferPolicyTests - 5 tests, AITextResultTests - 6 tests, All 24 tests passing
- PRs: