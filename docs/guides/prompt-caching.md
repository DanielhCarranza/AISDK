# Prompt Caching Guide

Prompt caching reduces costs and latency by reusing previously processed context. The biggest impact is on Anthropic, where cache hits reduce input token costs by 90%.

## Enable Caching for Anthropic

```swift
import AISDK

let anthropic = AILanguageModelAdapter(
    provider: AnthropicProvider(apiKey: key),
    modelId: "claude-sonnet-4-20250514"
)

// Enable caching — system prompt and tools get cache_control markers
let result = try await anthropic.generateText(
    messages: [
        .system("You are a medical assistant with extensive knowledge..."),  // Cached
        .user("What causes migraines?")
    ],
    caching: .enabled
)

// Check cache usage
if let cached = result.usage?.cachedTokens {
    print("Served \(cached) tokens from cache")
}
```

## Extended Retention

By default, Anthropic caches expire after 5 minutes. Use `.extended()` for 1-hour TTL:

```swift
let result = try await anthropic.generateText(
    messages: messages,
    caching: .extended()
)
```

## Per-Provider Caching Behavior

| Provider | How It Works | Default TTL | Extended TTL | Config Needed |
|----------|-------------|-------------|-------------|---------------|
| **Anthropic** | `cache_control` markers on system prompt and tools | 5 min | 1 hour | `.enabled` or `.extended()` |
| **OpenAI** | Automatic on prefix matches >= 1024 tokens | 5-10 min | N/A | None (automatic) |
| **Gemini** | Automatic (implicit) or explicit via cached content ID | 1 hour | Custom | `.withCachedContent(id)` for explicit |

### Anthropic
- System prompts and tool definitions get `cache_control` breakpoints
- Cache hits reduce input costs by 90%
- First request with new content pays a small cache write cost
- Requires messages to share a common prefix to hit cache

### OpenAI
- Fully automatic — no SDK config needed
- Caches prefix matches of 1024+ tokens
- 50% discount on cached input tokens
- Works across all GPT-4 and o-series models

### Gemini
- **Implicit**: Automatic, no config needed
- **Explicit**: Pre-create a cache resource via Gemini API, then reference it:

```swift
let result = try await gemini.generateText(
    messages: [.user("Analyze this document")],
    caching: .withCachedContent("cachedContents/abc123xyz")
)
```

## Track Cache Usage

```swift
let request = AITextRequest(messages: msgs, caching: .enabled)
let result = try await llm.generateText(request: request)

if let usage = result.usage {
    print("Input tokens: \(usage.promptTokens ?? 0)")
    print("Cached tokens: \(usage.cachedTokens ?? 0)")
    print("Output tokens: \(usage.completionTokens ?? 0)")
}
```

`cachedTokens` is `nil` or `0` on a cache miss. There is no separate cache miss field — a miss is implicit.

## When to Use Caching

- **Long system prompts**: Medical knowledge bases, legal references, coding guidelines
- **Repeated tool schemas**: Same tools across many requests
- **Multi-turn conversations**: Shared conversation prefix gets cheaper on each turn
- **Batch processing**: Same instructions applied to many inputs

## Cost Impact (Anthropic)

| Scenario | Without Cache | With Cache |
|----------|:---:|:---:|
| 10K token system prompt, 100 requests | 1M input tokens billed | ~100K input tokens billed |
| First request | Standard price | Standard + small write cost |
| Subsequent requests (within TTL) | Standard price | 90% discount on cached portion |
