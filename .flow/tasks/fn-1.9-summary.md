Created dedicated `Sources/AISDK/Core/Models/AIUsage.swift` containing:
- `AIUsage`: Token usage struct with prompt/completion/total/reasoning/cached tokens, legacy initializer, and addition operator for multi-step usage aggregation
- `AIFinishReason`: Finish reason enum with all standard cases, legacy conversion initializer, and helper properties (isSuccess, mayBeTruncated)

Added `Tests/AISDKTests/Models/AIUsageTests.swift` with 40 comprehensive tests covering initialization, arithmetic, equality, hashing, codable conformance, and all finish reason conversions.

Updated `AIStreamEvent.swift` to reference the new file instead of embedding the types.
