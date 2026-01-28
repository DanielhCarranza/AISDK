# Anthropic API Modernization Plan

## Executive Summary

This plan outlines the implementation of modern Anthropic API features to bring the AISDK up to date with the latest Claude 4.5 models and API capabilities. The goal is to ensure feature parity with the official Anthropic API while maintaining the SDK's clean, Swift-native design.

---

## Current State Analysis

### What We Have

**AnthropicService.swift** (Native API):
- ✅ Basic message request/response flow
- ✅ Streaming support via `AnthropicAsyncChunks`
- ✅ Beta configuration system (token-efficient-tools, extended-thinking, interleaved-thinking, mcp-client, search-results)
- ✅ Retry logic with configurable delays
- ✅ MCP server support
- ✅ Basic thinking configuration (`AnthropicThinkingConfig`)
- ✅ Structured output support

**AnthropicModels.swift**:
- ✅ Claude 4 models (Opus 4, Sonnet 4)
- ✅ Claude 3.7 Sonnet
- ✅ Claude 3.5 models
- ⚠️ **Missing**: Claude 4.5 models (Opus 4.5, Sonnet 4.5, Haiku 4.5)
- ⚠️ **Missing**: Updated model IDs per latest docs

### Gaps Identified

1. **Model Registry Outdated**: Missing Claude 4.5 family
2. **Thinking Configuration**: Needs proper enabled/disabled union type
3. **Streaming Events**: Missing proper `thinking_delta` and `signature_delta` handling
4. **Batch API**: Not implemented
5. **Files API**: Not implemented
6. **Beta Headers**: Need updates for latest features

---

## API Documentation Analysis (from platform.claude.com)

### Current Model IDs (Latest)

| Model | ID | Context | Max Output | Extended Thinking |
|-------|-----|---------|------------|-------------------|
| Claude Sonnet 4.5 | `claude-sonnet-4-5-20250929` | 200K (1M beta) | 64K | ✓ |
| Claude Opus 4.5 | `claude-opus-4-5-20251101` | 200K | 64K | ✓ (preserves history) |
| Claude Haiku 4.5 | `claude-haiku-4-5-20251001` | 200K | 64K | ✓ |
| Claude Sonnet 4 | `claude-sonnet-4-20250514` | 200K | 64K | ✓ |
| Claude Opus 4 | `claude-opus-4-20250514` | 200K | 64K | ✓ |
| Claude Opus 4.1 | `claude-opus-4-1-20250805` | 200K | 64K | ✓ |

### Beta Headers (Current)

| Feature | Header |
|---------|--------|
| Files API | `files-api-2025-04-14` |
| 1M context | `context-1m-2025-08-07` |
| Computer use | `computer-use-2025-01-24` |
| Interleaved thinking | `interleaved-thinking-2025-05-14` |
| Code execution | `code-execution-2025-05-22` |
| Structured outputs | `structured-outputs-2025-11-13` |

### Extended Thinking Configuration

```swift
// ThinkingConfigParam is a union type:
// - ThinkingConfigEnabled: { type: "enabled", budget_tokens: Int }
// - ThinkingConfigDisabled: { type: "disabled" }

// Key constraints:
// - Minimum budget: 1,024 tokens
// - budget_tokens must be < max_tokens
// - With interleaved thinking + tools, can exceed this (uses entire 200K context)
```

### Streaming Event Types

```
message_start → content_block_start → content_block_delta → content_block_stop → message_delta → message_stop

Delta types:
- text_delta: { type: "text_delta", text: String }
- thinking_delta: { type: "thinking_delta", thinking: String }
- signature_delta: { type: "signature_delta", signature: String }
- input_json_delta: { type: "input_json_delta", partial_json: String }
```

---

## Implementation Plan

### Phase 1: Model Registry Update (Priority: High)

**File**: `Sources/AISDK/LLMs/Anthropic/AnthropicModels.swift`

**Tasks**:
1. Add Claude 4.5 models with correct IDs
2. Update knowledge cutoff dates
3. Add model capabilities (1M context beta for Sonnet 4.5)
4. Fix any deprecated model references

**Changes**:
```swift
// Add to allModels array:
LLMModelAdapter(
    name: "claude-sonnet-4-5-20250929",
    displayName: "Claude Sonnet 4.5",
    description: "Balanced performance and practicality with 1M context beta",
    provider: .anthropic,
    category: .chat,
    capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools],
    tier: .pro,
    latency: .fast,
    inputTokenLimit: 200_000, // 1M with beta
    outputTokenLimit: 64_000,
    aliases: ["claude-sonnet-4-5-latest"],
    knowledgeCutoff: "Apr 2025"
),

LLMModelAdapter(
    name: "claude-opus-4-5-20251101",
    displayName: "Claude Opus 4.5",
    description: "Most intelligent model, preserves thinking history",
    provider: .anthropic,
    category: .chat,
    capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools],
    tier: .flagship,
    latency: .moderate,
    inputTokenLimit: 200_000,
    outputTokenLimit: 64_000,
    aliases: ["claude-opus-4-5-latest"],
    knowledgeCutoff: "Apr 2025"
),

LLMModelAdapter(
    name: "claude-haiku-4-5-20251001",
    displayName: "Claude Haiku 4.5",
    description: "Fastest model with near-frontier intelligence",
    provider: .anthropic,
    category: .chat,
    capabilities: [.text, .vision, .thinking, .longContext, .multilingual, .tools],
    tier: .mini,
    latency: .ultraFast,
    inputTokenLimit: 200_000,
    outputTokenLimit: 64_000,
    aliases: ["claude-haiku-4-5-latest"],
    knowledgeCutoff: "Apr 2025"
)
```

### Phase 2: Thinking Configuration Enhancement (Priority: High)

**File**: Create `Sources/AISDK/LLMs/Anthropic/AnthropicThinkingTypes.swift`

**Tasks**:
1. Create proper union type for ThinkingConfigParam
2. Add ThinkingBlock for response content
3. Add signature verification support

**New Types**:
```swift
/// Configuration for Claude's extended thinking feature
public enum AnthropicThinkingConfigParam: Codable {
    case enabled(budgetTokens: Int)
    case disabled

    private enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .enabled(let budget):
            try container.encode("enabled", forKey: .type)
            try container.encode(budget, forKey: .budgetTokens)
        case .disabled:
            try container.encode("disabled", forKey: .type)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "enabled":
            let budget = try container.decode(Int.self, forKey: .budgetTokens)
            self = .enabled(budgetTokens: budget)
        case "disabled":
            self = .disabled
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown thinking type: \(type)"
            )
        }
    }

    /// Validate budget tokens (minimum 1024, must be < maxTokens)
    public static func validate(budgetTokens: Int, maxTokens: Int) throws {
        guard budgetTokens >= 1024 else {
            throw LLMError.invalidRequest("Thinking budget must be at least 1,024 tokens")
        }
        guard budgetTokens < maxTokens else {
            throw LLMError.invalidRequest("Thinking budget must be less than max_tokens")
        }
    }
}

/// Thinking content block in responses
public struct AnthropicThinkingBlock: Codable {
    public let type: String // "thinking"
    public let thinking: String // Summarized in Claude 4 (billed for full)
    public let signature: String // Verification signature
}
```

### Phase 3: Streaming Delta Types (Priority: High)

**File**: `Sources/AISDK/LLMs/Anthropic/AnthropicMessageStreamingDeltaBlock.swift`

**Tasks**:
1. Add `thinking_delta` type
2. Add `signature_delta` type
3. Update delta parsing logic

**Changes**:
```swift
public enum AnthropicStreamingDelta: Codable {
    case textDelta(text: String)
    case thinkingDelta(thinking: String)
    case signatureDelta(signature: String)
    case inputJsonDelta(partialJson: String)

    // ... encoding/decoding implementation
}
```

### Phase 4: Beta Header Updates (Priority: Medium)

**File**: `Sources/AISDK/LLMs/Anthropic/AnthropicService.swift`

**Tasks**:
1. Add new beta headers
2. Update BetaConfiguration struct

**Changes**:
```swift
public struct BetaConfiguration {
    public let tokenEfficientTools: Bool
    public let extendedThinking: Bool // Note: Now via request body, not header
    public let interleavedThinking: Bool
    public let mcpClient: Bool
    public let searchResults: Bool
    public let filesAPI: Bool // NEW
    public let context1M: Bool // NEW (Sonnet 4.5 only)
    public let computerUse: Bool // NEW
    public let codeExecution: Bool // NEW
    public let structuredOutputs: Bool // NEW

    // Update header generation to include:
    // - files-api-2025-04-14
    // - context-1m-2025-08-07
    // - computer-use-2025-01-24
    // - code-execution-2025-05-22
    // - structured-outputs-2025-11-13
}
```

### Phase 5: Batch API Implementation (Priority: Medium)

**File**: Create `Sources/AISDK/LLMs/Anthropic/AnthropicBatchService.swift`

**Tasks**:
1. Implement batch request creation
2. Implement batch status polling
3. Implement JSONL result streaming

**New API**:
```swift
public class AnthropicBatchService {
    /// Create a batch of message requests (up to 100,000)
    /// - Returns: Batch ID for tracking
    public func createBatch(requests: [AnthropicBatchRequestItem]) async throws -> AnthropicBatch

    /// Get batch status
    public func getBatch(id: String) async throws -> AnthropicBatch

    /// Stream batch results as JSONL
    public func streamResults(batchId: String) -> AsyncThrowingStream<AnthropicBatchResult, Error>

    /// Cancel a running batch
    public func cancelBatch(id: String) async throws -> AnthropicBatch
}

public struct AnthropicBatchRequestItem: Codable {
    public let customId: String // 1-64 chars, unique per batch
    public let params: AnthropicMessageRequestBody
}

public struct AnthropicBatch: Codable {
    public let id: String
    public let status: BatchStatus // in_progress, canceling, ended
    public let createdAt: Date
    public let endedAt: Date?
    public let requestCounts: BatchRequestCounts
}
```

### Phase 6: Files API Implementation (Priority: Low)

**File**: Create `Sources/AISDK/LLMs/Anthropic/AnthropicFilesService.swift`

**Tasks**:
1. Implement file upload
2. Add file reference support in messages

---

## Testing Requirements

### Unit Tests
- [ ] Model registry validation
- [ ] Thinking configuration encoding/decoding
- [ ] Delta type parsing
- [ ] Beta header generation

### Integration Tests
- [ ] Extended thinking with Claude 4.5 models
- [ ] Streaming with thinking deltas
- [ ] Interleaved thinking with tools
- [ ] Batch API end-to-end

### Real API Tests (requires API key)
- [ ] `AnthropicServiceRealAPITests.swift` updates
- [ ] `AnthropicServiceStreamingTests.swift` updates

---

## Migration Notes

### Breaking Changes
- `AnthropicThinkingConfig` will be replaced by `AnthropicThinkingConfigParam` union type
- Beta configuration struct gains new optional properties

### Deprecations
- Claude 3.5 Sonnet (June 2024 version) - mark as deprecated
- Claude 3.7 Sonnet - mark as deprecated per docs

---

## Timeline Estimate

| Phase | Effort | Dependencies |
|-------|--------|--------------|
| Phase 1: Models | 1-2 hours | None |
| Phase 2: Thinking | 2-3 hours | None |
| Phase 3: Streaming | 2-3 hours | Phase 2 |
| Phase 4: Beta Headers | 1 hour | None |
| Phase 5: Batch API | 4-6 hours | Phase 1-4 |
| Phase 6: Files API | 3-4 hours | Phase 4 |

**Total: ~15-20 hours**

---

## Success Criteria

1. ✅ All Claude 4.5 models available in registry
2. ✅ Extended thinking works with proper configuration
3. ✅ Streaming correctly handles thinking_delta and signature_delta
4. ✅ All beta features configurable via BetaConfiguration
5. ✅ Batch API allows cost-optimized bulk processing
6. ✅ All existing tests pass
7. ✅ New tests cover added functionality
