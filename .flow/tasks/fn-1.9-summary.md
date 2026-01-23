Created dedicated `Sources/AISDK/Core/Models/AIUsage.swift` containing:
- `AIUsage`: Token usage struct with prompt/completion tokens (totalTokens is now computed), reasoning and cached tokens
- `AIFinishReason`: Finish reason enum with custom Codable implementation for forward compatibility

Key improvements after code review:
- Moved legacy `ChatCompletionResponse.Usage` initializer to `AIUsage+Legacy.swift` in adapters folder (avoids Core depending on OpenAI models)
- Made `totalTokens` a computed property to prevent inconsistencies
- Added custom Codable for AIFinishReason that safely handles unknown future values (decodes to `.unknown` instead of throwing)
- Added case-insensitive legacy reason matching
- Added `stop_sequence` (Anthropic) to finish reason mappings

Added `Tests/AISDKTests/Models/AIUsageTests.swift` with 46 comprehensive tests covering:
- Basic initialization and computed totalTokens
- Addition operator for multi-step usage aggregation
- Equatable, Hashable, Codable conformances
- Legacy initialization
- All finish reason conversions including case insensitivity
- Forward-compatible Codable (unknown values → .unknown)
