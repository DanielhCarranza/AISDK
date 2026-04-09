# Reasoning Controls Guide

AISDK provides a unified `AIReasoningConfig` that works across OpenAI, Anthropic, and Gemini reasoning models. Configure reasoning in 3 lines regardless of provider.

## Quick Start

```swift
import AISDK

// Unified reasoning — works with any reasoning-capable model
let result = try await llm.generateText(
    messages: [.user("What is 127 * 893?")],
    reasoning: .effort(.high)
)
```

## Configure Per Provider in 3 Lines

```swift
// OpenAI (o4-mini, o3, o1)
let openai = ProviderLanguageModelAdapter.openAIResponses(apiKey: key, modelId: "o4-mini")
let result = try await openai.generateText(messages: msgs, reasoning: .effort(.medium))

// Anthropic (claude-opus-4)
let anthropic = AILanguageModelAdapter(provider: AnthropicProvider(apiKey: key), modelId: "claude-opus-4-20250514")
let result = try await anthropic.generateText(messages: msgs, reasoning: .effort(.high))

// Gemini (gemini-2.5-flash, gemini-2.5-pro)
let gemini = AILanguageModelAdapter(provider: GeminiProvider(apiKey: key), modelId: "gemini-2.5-flash")
let result = try await gemini.generateText(messages: msgs, reasoning: .effort(.low))
```

## AIReasoningConfig Options

```swift
// Effort only (provider maps to appropriate budget)
.effort(.low)
.effort(.medium)
.effort(.high)

// Explicit budget (provider-specific token count)
AIReasoningConfig(budgetTokens: 4096)

// Effort + summary (OpenAI only — summary controls reasoning output)
.effort(.high, summary: .detailed)

// Full control
AIReasoningConfig(effort: .high, budgetTokens: 8192, summary: .concise)
```

## Streaming Reasoning

```swift
for try await event in llm.streamText(messages: msgs, reasoning: .effort(.high)) {
    switch event {
    case .reasoningDelta(let thinking):
        // Show reasoning/thinking as it arrives
        print("Thinking: \(thinking)")
    case .textDelta(let text):
        print(text, terminator: "")
    default:
        break
    }
}
```

## Models That Support Reasoning

| Provider | Models | Notes |
|----------|--------|-------|
| OpenAI | `o1`, `o3`, `o4-mini` | Uses `reasoning_effort` param. Summary supported. |
| Anthropic | `claude-opus-4-*` | Uses `thinking.budget_tokens`. Min budget = 1024. |
| Gemini | `gemini-2.5-*`, `gemini-3-*`, `gemini-3.1-*` | 2.5 uses `thinkingBudget`, 3.x uses `thinkingLevel`. |

Non-reasoning models silently ignore the config (no error thrown).

## Effort-to-Budget Mapping

### Anthropic
| Effort | Budget | Formula |
|--------|--------|---------|
| `.low` | 1024 | Fixed minimum |
| `.medium` | `max(1024, maxTokens / 4)` | Quarter of output budget |
| `.high` | `max(1024, maxTokens / 2)` | Half of output budget |

### Gemini 2.5
| Effort | Budget |
|--------|--------|
| `.low` | 1024 |
| `.medium` | 8192 |
| `.high` | 24576 |

## Edge Cases

### Anthropic: maxTokens < 1024
If `maxTokens <= 1024` (the minimum thinking budget), reasoning is silently skipped and a warning is logged. The request proceeds without thinking. Set `maxTokens` above 1024 to use reasoning.

### Non-reasoning models
Sending `reasoning` config to a model that doesn't support it (e.g., `gpt-4o`, `claude-sonnet-4`) is safe — the config is ignored.

### Provider-specific overrides
Provider-specific options take precedence over unified `AIReasoningConfig`. For Anthropic, if you set `betaConfiguration.extendedThinking = true` on the adapter, it acts as a fallback when no unified config is set.

## Track Reasoning Token Usage

```swift
let result = try await llm.generateText(messages: msgs, reasoning: .effort(.high))
if let reasoningTokens = result.usage?.reasoningTokens {
    print("Used \(reasoningTokens) tokens for reasoning")
}
```
