---
title: "Add unified reasoning/thinking controls to AITextRequest"
type: feat
date: 2026-02-12
issue: "#15"
reviewed: true
reviewers: [simplicity-reviewer, architecture-strategist, best-practices-researcher]
---

# Add Unified Reasoning/Thinking Controls to AITextRequest

## Overview

Expose a provider-agnostic `reasoning` field on `AITextRequest` so developers can configure reasoning/thinking controls once and have them map automatically to OpenAI, Gemini, and Anthropic APIs. Today, reasoning is only accessible via provider-specific options, forcing developers to know each provider's API.

## Problem Statement

Developers must use three different mechanisms to enable reasoning:
- **OpenAI**: Set `OpenAIRequestOptions.reasoning` via type-erased `providerOptions`
- **Gemini**: Set `thinkingLevel`/`thinkingBudget` keys in a `[String: ProviderJSONValue]` dictionary
- **Anthropic**: Configure at adapter init time via `BetaConfiguration` -- no per-request control

This defeats the SDK's purpose of providing a unified API. The `toProviderRequest()` method also drops `providerOptions` entirely (passes `nil` at `ProviderClient.swift:682`), meaning reasoning config doesn't even reach adapters through the standard path.

## Proposed Solution

### New Type: `AIReasoningConfig`

```swift
// Sources/AISDK/Core/Models/AIReasoningConfig.swift

public struct AIReasoningConfig: Sendable, Equatable, Codable {
    public let effort: AIReasoningEffort?
    public let budgetTokens: Int?

    public enum AIReasoningEffort: String, Sendable, Codable, Equatable {
        case low
        case medium
        case high
    }

    public init(
        effort: AIReasoningEffort? = nil,
        budgetTokens: Int? = nil
    ) {
        self.effort = effort
        self.budgetTokens = budgetTokens
    }
}

// Convenience factories
public extension AIReasoningConfig {
    static func effort(_ effort: AIReasoningEffort) -> AIReasoningConfig {
        AIReasoningConfig(effort: effort)
    }
}
```

**Design decisions:**
- **No `includeThoughts` field.** This is only meaningful for Gemini (`includeThoughts` in thinking config). Since it's irrelevant to OpenAI and Anthropic, it belongs in Gemini-specific `providerOptions`, not the unified config. (Simplicity review finding)
- **Two fields only: `effort` and `budgetTokens`.** Effort is the primary cross-provider abstraction. Budget is a secondary knob for Anthropic/Gemini users who need precise control.
- **`AIReasoningEffort` vs `ReasoningConfig.ReasoningEffort`**: The unified `AIReasoningEffort` and OpenAI's existing `ReasoningConfig.ReasoningEffort` (`OpenAIRequestOptions.swift:270`) are structurally identical (`low/medium/high`). They remain separate types because they serve different layers -- the adapter maps between them.

### Add to AITextRequest

```swift
// Sources/AISDK/Core/Models/AITextRequest.swift
public let reasoning: AIReasoningConfig?
```

Added to `init()` with default `nil`, and a new `withReasoning(_:)` builder method. All existing `with*()` methods updated to carry `reasoning` through.

### Propagation: Typed Field on ProviderRequest

```swift
// Sources/AISDK/Core/Providers/ProviderClient.swift - ProviderRequest struct
public let reasoning: AIReasoningConfig?  // New field
```

**Why a dedicated field instead of serializing into `providerOptions`:**
- Preserves type safety end-to-end (no serialize/deserialize round-trip through `[String: ProviderJSONValue]`)
- Avoids namespace collisions with provider-specific keys in `providerOptions`
- Follows the established pattern where all standard request parameters (`maxTokens`, `temperature`, `tools`, etc.) are explicit fields on `ProviderRequest`
- Each adapter reads `request.reasoning` directly -- no dictionary parsing
- `ProviderRequest.init` already has all-optional-defaulted parameters, so adding `reasoning: AIReasoningConfig? = nil` is source-compatible

(All three reviewers converged on this recommendation)

### Provider Mapping Rules

| Unified Field | OpenAI | Gemini | Anthropic |
|---|---|---|---|
| `effort: .low` | `reasoning_effort: "low"` | `thinkingLevel: "low"` | `budgetTokens: 1024` |
| `effort: .medium` | `reasoning_effort: "medium"` | `thinkingLevel: "medium"` | `budgetTokens: max(1024, maxTokens/4)` |
| `effort: .high` | `reasoning_effort: "high"` | `thinkingLevel: "high"` | `budgetTokens: max(1024, maxTokens/2)` |
| `budgetTokens: N` | Ignored (no concept) | `thinkingBudget: N` | `budgetTokens: N` |

**When both `effort` AND `budgetTokens` are set:**
- **Anthropic**: `budgetTokens` wins (explicit budget overrides effort-derived budget)
- **Gemini**: Both are sent (`thinkingLevel` from effort + `thinkingBudget` from budget)
- **OpenAI**: `effort` is used, `budgetTokens` ignored

**Effort-to-budget mapping rationale (Anthropic):** Based on LiteLLM's production defaults (the only documented industry standard), adjusted upward since our SDK targets app developers who prioritize quality:
- `low` -> 1024 (Anthropic minimum)
- `medium` -> max(1024, maxTokens/4)
- `high` -> max(1024, maxTokens/2)

### Precedence Rule

**Provider-specific options override unified config.** If both `AITextRequest.reasoning` and provider-specific reasoning options are set, the provider-specific options win. This follows the "most specific wins" principle (consistent with Vercel AI SDK and LiteLLM) and preserves backward compatibility.

```
Precedence (highest to lowest):
  providerOptions (e.g., OpenAIRequestOptions.reasoning)  -->  wins if set
  request.reasoning (unified AIReasoningConfig)            -->  used if no provider override
  adapter defaults (e.g., Anthropic betaConfiguration)     -->  fallback
```

### Non-Reasoning Models

When `reasoning` is set on a model that doesn't support it (e.g., `gpt-4o`, `claude-3-haiku`), the adapter **silently ignores** it. This is consistent with how other optional fields like `tools` are handled -- providers skip unsupported features rather than erroring.

## Technical Approach

### Phase 1: Core Type + AITextRequest + ProviderRequest

**Files to create:**
- `Sources/AISDK/Core/Models/AIReasoningConfig.swift` -- new type

**Files to modify:**
- `Sources/AISDK/Core/Models/AITextRequest.swift`
  - Add `reasoning: AIReasoningConfig?` property
  - Add to `init()` with default `nil`
  - Add `withReasoning(_:)` builder method
  - Update ALL existing `with*()` methods to carry `reasoning` through
- `Sources/AISDK/Core/Providers/ProviderClient.swift`
  - Add `reasoning: AIReasoningConfig?` to `ProviderRequest` struct (line ~201)
  - Add to `ProviderRequest.init()` with default `nil`
  - Update `toProviderRequest()` (line ~669) to pass `reasoning: reasoning`

**Tasks:**
- [ ] Create `AIReasoningConfig` struct with `effort` and `budgetTokens`
- [ ] Create `AIReasoningEffort` enum (low, medium, high)
- [ ] Add convenience factory `.effort(_:)`
- [ ] Add `reasoning` to `AITextRequest` struct and init
- [ ] Add `withReasoning(_:)` method
- [ ] Update `withSensitivity()`, `withAllowedProviders()`, `withBufferPolicy()`, `withProviderOptions()`, `withConversationId()` to carry `reasoning`
- [ ] Add `reasoning: AIReasoningConfig?` to `ProviderRequest` struct and init
- [ ] Update `toProviderRequest()` to pass `reasoning` through

### Phase 2: Provider Adapter Updates

#### OpenAI Client Adapter (Chat Completions API)
**File:** `Sources/AISDK/Core/Providers/OpenAIClientAdapter.swift`

- [ ] Add `reasoningEffort: String?` field to `OpenAIRequestBody` struct (~line 725)
- [ ] Add `reasoning_effort` to `OpenAIRequestBody.CodingKeys`
- [ ] In `buildRequestBody()`, read `request.reasoning?.effort` and map to `reasoningEffort` string
- [ ] Only apply for models with `.reasoning` capability

#### Gemini Client Adapter
**File:** `Sources/AISDK/Core/Providers/GeminiClientAdapter.swift`

- [ ] Update `buildThinkingConfig(from:)` (~line 434) to also accept `AIReasoningConfig?` parameter
- [ ] Map `reasoning.effort` to `thinkingLevel` (low->low, medium->medium, high->high)
- [ ] Map `reasoning.budgetTokens` to `thinkingBudget`
- [ ] Preserve existing `providerOptions` keys as override (precedence rule)
- [ ] Pass reasoning from request into `buildThinkingConfig`

#### Anthropic Client Adapter
**File:** `Sources/AISDK/Core/Providers/AnthropicClientAdapter.swift`

- [ ] In `buildRequestBody()` (~line 361), check `request.reasoning` before falling back to adapter-level `betaConfiguration`
- [ ] Map `reasoning.effort` to `budgetTokens` using effort-to-budget table
- [ ] Map explicit `reasoning.budgetTokens` directly to `AnthropicThinkingConfigParam.enabled(budgetTokens:)`
- [ ] When both `effort` and `budgetTokens` are set, `budgetTokens` wins
- [ ] **Dynamically add thinking beta header** when per-request reasoning is detected, even if adapter was initialized with `betaConfiguration: .none` (architecture review finding)
- [ ] Handle edge case: if `maxTokens <= 1024`, log a warning and skip reasoning (cannot satisfy `budget >= 1024 AND budget < maxTokens`)
- [ ] Validate: budget >= 1024, budget < maxTokens (at adapter level, following existing pattern in `AnthropicThinkingConfigParam.validate()`)

#### OpenAI Provider (Responses API path)
**File:** `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+AITextRequest.swift`

- [ ] Check for unified `AITextRequest.reasoning` in addition to `OpenAIRequestOptions.reasoning`
- [ ] Apply precedence: `OpenAIRequestOptions.reasoning` overrides unified if both set
- [ ] Map unified `reasoning.effort` to `ResponseReasoning(effort:)`

### Phase 3: Tests

**Files to create:**
- `Tests/AISDKTests/Models/AIReasoningConfigTests.swift`

**Files to modify:**
- `Tests/AISDKTests/Models/AITextRequestTests.swift`
- `Tests/AISDKTests/Core/Providers/GeminiClientAdapterTests.swift`
- `Tests/AISDKTests/Core/Providers/OpenAIClientAdapterTests.swift` (or create if needed)
- `Tests/AISDKTests/Core/Providers/AnthropicClientAdapterTests.swift` (or create if needed)

**Test cases:**

#### AIReasoningConfig Unit Tests
- [ ] Init with effort only
- [ ] Init with budget only
- [ ] Init with both effort and budget
- [ ] Factory method `.effort(.high)` produces correct config
- [ ] Codable encode/decode round-trip

#### AITextRequest Integration Tests
- [ ] Init with reasoning param
- [ ] `withReasoning()` builder creates correct copy
- [ ] All existing `with*()` methods preserve reasoning field (critical regression test)
- [ ] `toProviderRequest()` passes reasoning to ProviderRequest

#### Provider Mapping Tests
- [ ] **OpenAI**: effort maps to `reasoning_effort` on request body
- [ ] **OpenAI**: budget is silently ignored
- [ ] **OpenAI**: effort + budget both set -- effort used, budget ignored
- [ ] **Gemini**: effort maps to `thinkingLevel`
- [ ] **Gemini**: budget maps to `thinkingBudget`
- [ ] **Gemini**: effort + budget both set -- both sent
- [ ] **Anthropic**: effort .low -> budgetTokens 1024
- [ ] **Anthropic**: effort .medium -> max(1024, maxTokens/4)
- [ ] **Anthropic**: effort .high -> max(1024, maxTokens/2)
- [ ] **Anthropic**: explicit budget used directly
- [ ] **Anthropic**: effort + budget both set -- budget wins
- [ ] **Anthropic**: budget validation (< 1024 rejected, >= maxTokens rejected)
- [ ] **Anthropic**: maxTokens <= 1024 edge case -- reasoning skipped

#### Precedence Tests
- [ ] Unified reasoning + no provider options -> unified used
- [ ] Unified reasoning + provider-specific options -> provider-specific wins
- [ ] No unified reasoning + provider-specific options -> provider-specific used (backward compat)

#### Anthropic Beta Header Tests
- [ ] Per-request reasoning + adapter has `betaConfiguration: .none` -> beta header dynamically added
- [ ] Per-request reasoning + adapter has `betaConfiguration.extendedThinking = true` -> works normally
- [ ] Adapter-level thinking + per-request reasoning -> per-request overrides adapter-level budget

#### Edge Case Tests
- [ ] Reasoning on non-reasoning model -> silently ignored
- [ ] Reasoning with nil maxTokens -> Anthropic uses default 4096 for budget calc
- [ ] AIReasoningConfig with all nil fields -> treated as no reasoning

## Acceptance Criteria

- [ ] Developers can set reasoning using `AITextRequest(reasoning: .effort(.high))` without knowing provider details
- [ ] Provider-specific options still work and take precedence for backward compatibility
- [ ] OpenAI (both Chat Completions and Responses API), Gemini, and Anthropic adapters all consume the unified reasoning config
- [ ] Anthropic thinking beta header is dynamically added when per-request reasoning is set
- [ ] Unit tests cover all mapping permutations, precedence, and edge cases
- [ ] `swift build` succeeds, `swift test` passes

## Dependencies & Risks

**Dependencies:**
- None -- this builds on existing infrastructure

**Risks:**
- **Breaking change risk: LOW** -- new optional field with nil default on both `AITextRequest` and `ProviderRequest`, all existing code unchanged
- **Anthropic budget calculation**: The effort-to-budget mapping is heuristic based on LiteLLM conventions. May need tuning based on real-world usage.
- **`with*()` method maintenance**: Every existing builder method must be updated. Missing one silently drops reasoning. Consider a private `copy(overriding:)` helper as a follow-up refactor to eliminate this class of bugs.
- **Anthropic beta header**: Dynamically adding the thinking beta header when reasoning is set per-request requires making header construction request-aware. Currently it's static from adapter init.

## Out of Scope

- Agent-level reasoning configuration (`Agent.reasoning`) -- can be added in a follow-up
- OpenAI `summary` parameter in unified config -- too provider-specific, keep in `OpenAIRequestOptions`
- `includeThoughts` in unified config -- only relevant to Gemini, keep in Gemini `providerOptions`
- `AITextResult.reasoning` field for non-streaming results -- separate enhancement
- `reasoningStart`/`reasoningFinish` stream event emission -- existing `reasoningDelta` events work
- Special Gemini budget values (`0` for disable, `-1` for dynamic) -- keep as Gemini-specific
- CLI flags (`--reasoning-effort`, `--reasoning-budget`) -- can be added in a follow-up for manual testing

## Files Summary

| Action | File |
|--------|------|
| **Create** | `Sources/AISDK/Core/Models/AIReasoningConfig.swift` |
| **Create** | `Tests/AISDKTests/Models/AIReasoningConfigTests.swift` |
| **Modify** | `Sources/AISDK/Core/Models/AITextRequest.swift` |
| **Modify** | `Sources/AISDK/Core/Providers/ProviderClient.swift` |
| **Modify** | `Sources/AISDK/Core/Providers/OpenAIClientAdapter.swift` |
| **Modify** | `Sources/AISDK/Core/Providers/GeminiClientAdapter.swift` |
| **Modify** | `Sources/AISDK/Core/Providers/AnthropicClientAdapter.swift` |
| **Modify** | `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+AITextRequest.swift` |
| **Modify** | `Tests/AISDKTests/Models/AITextRequestTests.swift` |
| **Modify** | `Tests/AISDKTests/Core/Providers/GeminiClientAdapterTests.swift` |

## References

- Issue: #15
- `AITextRequest`: `Sources/AISDK/Core/Models/AITextRequest.swift:17-99`
- `ProviderRequest`: `Sources/AISDK/Core/Providers/ProviderClient.swift:201-275`
- `toProviderRequest()`: `Sources/AISDK/Core/Providers/ProviderClient.swift:669-686`
- `OpenAIRequestOptions.ReasoningConfig`: `Sources/AISDK/LLMs/OpenAI/APIModels/Responses/OpenAIRequestOptions.swift:260-282`
- `GeminiClientAdapter.buildThinkingConfig`: `Sources/AISDK/Core/Providers/GeminiClientAdapter.swift:433-498`
- `AnthropicClientAdapter.buildRequestBody`: `Sources/AISDK/Core/Providers/AnthropicClientAdapter.swift:361-367`
- `AnthropicThinkingConfigParam`: `Sources/AISDK/LLMs/Anthropic/AnthropicThinkingTypes.swift`
- LiteLLM effort-to-budget defaults: `litellm/constants.py` (low=1024, medium=2048, high=4096)
- Vercel AI SDK precedence: provider-specific overrides unified ("most specific wins")
