# fn-1.6 Task 1.3: AITextRequest/AITextResult

## Description
Create AITextRequest and AITextResult models with PHI protection fields and memory control.

## Acceptance
- [x] AITextRequest with allowedProviders, sensitivity, and bufferPolicy fields
- [x] DataSensitivity enum (standard/sensitive/phi)
- [x] StreamBufferPolicy enum matching Swift's implementable semantics
- [x] AITextResult with helper properties
- [x] Provider access validation in AILanguageModelAdapter
- [x] AIProviderAccessError for validation failures
- [x] Comprehensive tests (33 tests passing)

## Done summary

### Implementation Summary (v2 - Post Review)

Created `AITextRequest` and `AITextResult` model files in `Sources/AISDK/Core/Models/` with PHI protection, memory control, and provider access validation.

### Changes from Review Feedback

1. **Added Provider Access Validation** (Critical fix)
   - Added `validateProviderAccess()` method in `AILanguageModelAdapter`
   - Enforces `allowedProviders` and `sensitivity` checks before any API call
   - Added `AIProviderAccessError` enum with descriptive error messages

2. **Redesigned StreamBufferPolicy** (Major fix)
   - Changed from struct with enum to pure enum matching Swift's implementable semantics
   - Cases: `.unbounded`, `.dropOldest(capacity:)`, `.dropNewest(capacity:)`
   - Removed `.suspendProducer` as it cannot be implemented with Swift's AsyncStream
   - Added factory method with capacity validation

3. **Fixed Documentation** (Minor fix)
   - Updated `canUseProvider` docstring to accurately describe behavior
   - Added note about sensitivity validation happening at adapter/router layer

### New Files Created
- `Sources/AISDK/Core/Models/AITextRequest.swift` - Request model with PHI protection
- `Sources/AISDK/Core/Models/AITextResult.swift` - Result model with helpers
- `Tests/AISDKTests/Models/AITextRequestTests.swift` - 18 tests
- `Tests/AISDKTests/Models/AITextResultTests.swift` - 7 tests
- `Tests/AISDKTests/Models/AIProviderAccessTests.swift` - 8 tests

### Files Modified
- `Sources/AISDK/Core/Protocols/AILanguageModel.swift` - Removed duplicate types
- `Sources/AISDK/Core/Models/AIStreamEvent.swift` - Added Equatable to AIToolCallResult
- `Sources/AISDK/Core/Adapters/Legacy/AILanguageModelAdapter.swift` - Added provider validation
- `Sources/AISDK/Errors/AISDKError.swift` - Added AIProviderAccessError

## Evidence
- Commits: (pending)
- Tests: 33 tests passing (AITextRequest, AITextResult, DataSensitivity, StreamBufferPolicy, AIProviderAccessError, Provider Validation Integration)
- PRs: N/A
