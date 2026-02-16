# SDK Explorer Model Selection Guide

> Last updated: 2026-02-14

## Default Models (Cost-Effective, Full Feature Coverage)

| Provider | Model ID | Input/MTok | Output/MTok | All Features? |
|----------|----------|-----------|------------|---------------|
| Google | `gemini-2.5-flash` | $0.15 | $0.60 | Yes (all 7) |
| OpenAI | `gpt-4.1-mini` | $0.40 | $1.60 | 6/7 (no reasoning) |
| Anthropic | `claude-haiku-4-5-20251001` | $1.00 | $5.00 | Yes (all 7) |

## Feature-Model Matrix

| Feature | OpenAI | Anthropic | Google | Notes |
|---------|--------|-----------|--------|-------|
| Text generation | `gpt-4.1-mini` | `claude-haiku-4-5-20251001` | `gemini-2.5-flash` | All defaults work |
| Streaming (SSE) | `gpt-4.1-mini` | `claude-haiku-4-5-20251001` | `gemini-2.5-flash` | All defaults work |
| Tool/function calling | `gpt-4.1-mini` | `claude-haiku-4-5-20251001` | `gemini-2.5-flash` | All defaults work |
| Generative UI (structured JSON) | `gpt-4.1-mini` | `claude-haiku-4-5-20251001` | `gemini-2.5-flash` | Via tool use / JSON mode |
| Multi-turn conversation | `gpt-4.1-mini` | `claude-haiku-4-5-20251001` | `gemini-2.5-flash` | All defaults work |
| Reasoning/extended thinking | **`o4-mini`** | `claude-haiku-4-5-20251001` | `gemini-2.5-flash` | OpenAI requires o-series model |
| Structured output (JSON schema) | `gpt-4.1-mini` | `claude-haiku-4-5-20251001` | `gemini-2.5-flash` | All defaults work |

## Features Requiring Non-Default Models

### OpenAI Reasoning Tokens
- Default `gpt-4.1-mini` does NOT support reasoning/thinking tokens
- Use `o4-mini` for reasoning-specific tests
- Different API shape: reasoning tokens appear in response alongside completion tokens

### Anthropic Extended Thinking (Higher Capability)
- `claude-haiku-4-5-20251001` supports extended thinking (new in Haiku 4.5)
- For higher-quality reasoning: upgrade to `claude-sonnet-4-5-20250929` ($3/$15 per MTok)
- Adaptive thinking: only available on `claude-opus-4-6` (not recommended for cost)

### Google Thinking Mode
- `gemini-2.5-flash` supports thinking natively
- Thinking tokens priced separately at higher rate
- For higher capability: `gemini-2.5-pro`

## Deprecated Models (Do Not Use)

| Old Model | Status | Replacement |
|-----------|--------|-------------|
| `claude-3-5-sonnet-20241022` | Retired, returns "model not found" | `claude-haiku-4-5-20251001` or `claude-sonnet-4-5-20250929` |
| `claude-3-haiku-20240307` | Legacy | `claude-haiku-4-5-20251001` |
| `gpt-4o-mini` | Retiring (removed from ChatGPT 2026-02-13) | `gpt-4.1-mini` |
| `gemini-2.0-flash` | Deprecating 2026-03-31 | `gemini-2.5-flash` |

## Upgrade Path Models (When Defaults Aren't Enough)

| Provider | Default | Upgrade | When to Use |
|----------|---------|---------|-------------|
| OpenAI | `gpt-4.1-mini` | `gpt-4.1` | Complex tool chains, better structured output |
| OpenAI | `gpt-4.1-mini` | `o4-mini` | Reasoning token tests only |
| Anthropic | `claude-haiku-4-5-20251001` | `claude-sonnet-4-5-20250929` | Higher quality reasoning, 1M context (beta) |
| Google | `gemini-2.5-flash` | `gemini-2.5-pro` | Complex reasoning, higher accuracy |

## Estimated Test Cost Per Full Run

Assuming ~50 API calls per provider at ~100 tokens each:

| Provider | Model | Est. Cost/Run |
|----------|-------|--------------|
| Google | `gemini-2.5-flash` | ~$0.004 |
| OpenAI | `gpt-4.1-mini` | ~$0.01 |
| Anthropic | `claude-haiku-4-5-20251001` | ~$0.03 |
| **Total** | | **~$0.05/run** |
