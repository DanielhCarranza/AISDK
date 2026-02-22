# OpenAI Responses API Integration Plan

## Context

AISDK currently routes all OpenAI calls through the Chat Completions API (`/v1/chat/completions`), even though a full Responses API implementation already exists at the `OpenAIProvider` layer. The user's chat app uses `OpenAIClientAdapter` + `ProviderLanguageModelAdapter`, which:

1. Only hits `/v1/chat/completions`
2. Explicitly **rejects** built-in tools with an error message
3. Cannot use server-side conversation chaining (`previous_response_id`)
4. Cannot use background mode, web search, file search, code interpreter, or image generation
5. Misses 40-80% cache utilization improvements the Responses API provides

The Responses API is OpenAI's recommended path for all new development. Chat Completions is not deprecated but is positioned for simple, stateless use cases. The Responses API enables agentic workflows, built-in tools, and server-managed state.

**Goal:** Create `OpenAIResponsesClientAdapter` — a new `ProviderClient` that routes through the Responses API while preserving Chat Completions as an opt-in alternative.

---

## Architecture Decision

**Create a new `OpenAIResponsesClientAdapter` actor** conforming to `ProviderClient`, rather than modifying `OpenAIClientAdapter`. Rationale:

- Single Responsibility: `OpenAIClientAdapter` stays clean for Chat Completions (also used by OpenRouter/LiteLLM-compatible endpoints)
- The Responses API has fundamentally different request/response shapes, streaming formats, and tool handling
- `OpenAIProvider` already has all Responses API HTTP logic — the new adapter wraps it
- Consumers choose which API at construction time, not per-request

---

## Data Retention & Privacy Analysis

| Concern | Chat Completions | Responses API |
|---------|-----------------|---------------|
| Default storage | Stored (new accounts) | Stored (`store: true`) |
| ZDR eligible | Yes | Yes, but with exceptions |
| ZDR + Code Interpreter | N/A | **NOT compatible** (requires MAM) |
| ZDR + Background mode | N/A | **NOT compatible** (data stored ~10min) |
| ZDR + Extended caching | Available | **NOT ZDR eligible** (GPU-local KV storage) |
| JSON schemas (structured output) | Stored as Application State | Stored as Application State |
| Encrypted reasoning items | N/A | Available for ZDR orgs |

**Decision:** Default `store: false` (privacy-first). Force `store: false` when `sensitivity == .phi`. Document ZDR incompatibilities clearly.

---

## Responses API vs Chat Completions: Key Differences

| Dimension | Chat Completions | Responses API |
|-----------|-----------------|---------------|
| Endpoint | `POST /v1/chat/completions` | `POST /v1/responses` |
| System messages | `messages[{role:"system"}]` | `instructions` field |
| Conversation state | Full message history in request | `previous_response_id` |
| Built-in tools | None (custom function calling only) | web_search, file_search, code_interpreter, computer_use, image_generation, MCP |
| Agentic loop | One round-trip per tool call | Server-side multi-tool execution |
| Streaming format | `data: {...}\n\n` + `[DONE]` | `event: <type>\ndata: {...}\n\n` |
| Token fields | `prompt_tokens` / `completion_tokens` | `input_tokens` / `output_tokens` |
| Structured output | `response_format.json_schema` | `text.format.json_schema` |
| Cache utilization | ~40% | ~80% |
| Multiple completions (`n`) | Yes | No |
| Background mode | No | Yes |
| Storage control | `store: bool` | `store: bool` |
| Reasoning items in output | No | Yes (summarized) |

---

## Implementation Phases

### Phase 1: Create `OpenAIResponsesClientAdapter`

**New file:** `Sources/AISDK/Core/Providers/OpenAIResponsesClientAdapter.swift`

A Swift 6 `actor` conforming to `ProviderClient` that wraps `OpenAIProvider` and routes through the Responses API.

```swift
public actor OpenAIResponsesClientAdapter: ProviderClient {
    public nonisolated let providerId: String = "openai-responses"
    public nonisolated let displayName: String = "OpenAI (Responses API)"
    public nonisolated let baseURL: URL

    private let provider: OpenAIProvider
    private let defaultStore: Bool  // false by default

    public init(
        apiKey: String,
        baseURL: URL? = nil,
        store: Bool = false,
        organization: String? = nil,
        retryPolicy: RetryPolicy = .default
    )
}
```

**`execute(request:)` implementation:**
1. Convert `ProviderRequest` → `AITextRequest` (reverse the `toProviderRequest()` mapping)
2. Inject `store` from `providerOptions` or `defaultStore`; force `false` for `.phi` sensitivity
3. Call `provider.sendTextRequest(aiTextRequest)` (existing bridge to Responses API)
4. Convert `AITextResult` → `ProviderResponse` (map token fields: `promptTokens` ← `inputTokens`, etc.)

**`stream(request:)` implementation:**
1. Convert `ProviderRequest` → `AITextRequest`
2. Call `provider.streamTextRequest(aiTextRequest)` which returns `AsyncThrowingStream<ResponseChunk, Error>`
3. Map `ResponseChunk` → `ProviderStreamEvent`:
   - `status == .inProgress` (first) → `.start(id:, model:)`
   - `delta.outputText != nil` → `.textDelta(text)`
   - `status == .completed` + `usage` → `.usage(...)` + `.finish(...)`
4. Phase 1 limitation: Function call streaming deferred to Phase 3 (non-streaming `execute()` handles tool calls via Agent loop)

**Key reuse:** The existing `OpenAIProvider+AITextRequest.swift` has `convertToResponseRequest()` and `convertToAITextResult()` — these are the authoritative conversion logic. The adapter builds an `AITextRequest` from `ProviderRequest` and delegates to these methods.

**Critical files to reference:**
- `Sources/AISDK/Core/Providers/OpenAIClientAdapter.swift` — pattern for `ProviderClient` conformance, retry, health
- `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+AITextRequest.swift` — `convertToResponseRequest()`, `convertToAITextResult()`
- `Sources/AISDK/Core/Providers/ProviderClient.swift` — `ProviderClient` protocol, `ProviderRequest`, `ProviderResponse`, `ProviderStreamEvent`

### Phase 2: Factory Methods on `ProviderLanguageModelAdapter`

**File to modify:** `Sources/AISDK/Core/Adapters/Provider/ProviderLanguageModelAdapter.swift`

Add convenience factory methods:

```swift
extension ProviderLanguageModelAdapter {
    /// OpenAI via Responses API (recommended for new projects)
    static func openAIResponses(
        apiKey: String,
        modelId: String = "gpt-4o",
        store: Bool = false
    ) -> ProviderLanguageModelAdapter

    /// OpenAI via Chat Completions (for ZDR, OpenRouter compatibility)
    static func openAIChatCompletions(
        apiKey: String,
        modelId: String = "gpt-4o"
    ) -> ProviderLanguageModelAdapter
}
```

The `openAIResponses` factory adds `.webSearch`, `.reasoning`, `.computerUse` to capabilities since the Responses API supports these natively.

### Phase 3: Full Streaming with Tool Calls

**File to modify:** `Sources/AISDK/Core/Providers/OpenAIResponsesClientAdapter.swift`

Enhance `stream(request:)` to parse Responses API SSE events for function calls:

- `response.function_call_arguments.delta` → `.toolCallDelta(id:, argumentsDelta:)`
- `response.output_item.done` (type: `function_call`) → `.toolCallFinish(id:, name:, arguments:)`
- `response.output_item.added` (type: `function_call`) → `.toolCallStart(id:, name:)`

This requires either:
- Working with the raw SSE stream from `OpenAIProvider.createResponseStream()` which yields `ResponseChunk`
- Or adding a lower-level streaming method that yields `ResponseStreamEvent` directly

The existing `ResponseChunk.from(event:accumulatedResponse:)` factory already handles these event types — the adapter maps the resulting chunk fields to `ProviderStreamEvent`.

### Phase 4: Structured Output via Responses API

**Files to modify:**
- `Sources/AISDK/Core/Providers/OpenAIResponsesClientAdapter.swift`
- `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+AITextRequest.swift` (line 222, currently passes `text: nil`)

Wire `ProviderResponseFormat.jsonSchema` → `ResponseRequest.text`:

```swift
// In convertToResponseRequest, replace text: nil with:
let textConfig: ResponseTextConfig?
if let format = request.responseFormat {
    // Map to ResponseTextFormat with json_schema
    textConfig = ResponseTextConfig(format: convertResponseFormat(format))
} else {
    textConfig = nil
}
```

This enables `generateObject<T>()` to work through the Responses API path.

### Phase 5: Conversation Chaining Mode (Opt-in)

**File to modify:** `Sources/AISDK/Core/Providers/OpenAIResponsesClientAdapter.swift`

Add opt-in server-side chaining mode:

- **Mode A (default):** Full message history sent as `input` items. Stateless. Compatible with Agent's existing architecture.
- **Mode B (opt-in):** Adapter tracks `lastResponseId`, injects `previousResponseId`, sends only latest user message. Saves tokens. Enabled via `useServerSideChaining: true` in init.

Mode B is for advanced consumers. The Agent actor always uses Mode A since it manages its own message history.

### Phase 6: Tests

**New file:** `Tests/AISDKTests/Core/Providers/OpenAIResponsesClientAdapterTests.swift`

Test coverage:
- [ ] `execute()` builds correct `ResponseRequest` with `store: false` default
- [ ] `execute()` forces `store: false` for `.phi` sensitivity
- [ ] `execute()` maps token fields correctly (`inputTokens` → `promptTokens`)
- [ ] `execute()` passes `previousResponseId` from `conversationId`
- [ ] `execute()` translates `jsonSchema` response format to `ResponseTextConfig`
- [ ] `stream()` emits correct `ProviderStreamEvent` sequence
- [ ] Built-in tools are correctly forwarded (no more "not supported" error)
- [ ] Factory methods create correct adapter configurations

---

## Migration Path

### Before (current — Chat Completions only)
```swift
let client = OpenAIClientAdapter(apiKey: key)
let model = ProviderLanguageModelAdapter(client: client, modelId: "gpt-4o")
let agent = Agent(model: model, builtInTools: [.webSearchDefault])
// FAILS: "Built-in tools are not supported via OpenAI Chat Completions API"
```

### After (Responses API)
```swift
// Option A: Factory method (recommended)
let model = ProviderLanguageModelAdapter.openAIResponses(apiKey: key, modelId: "gpt-4o")
let agent = Agent(model: model, builtInTools: [.webSearchDefault])
// Works: routes through /v1/responses

// Option B: Explicit construction
let client = OpenAIResponsesClientAdapter(apiKey: key)
let model = ProviderLanguageModelAdapter(client: client, modelId: "gpt-4o")

// Option C: Keep Chat Completions (explicit opt-in)
let model = ProviderLanguageModelAdapter.openAIChatCompletions(apiKey: key, modelId: "gpt-4o")
```

### Multi-provider (no changes needed)
```swift
// OpenRouter — unchanged, still Chat Completions format
let client = OpenRouterClient(apiKey: key)
let model = ProviderLanguageModelAdapter(client: client, modelId: "openai/gpt-4o")

// LiteLLM — unchanged
let client = LiteLLMClient(apiKey: key, baseURL: localURL)
let model = ProviderLanguageModelAdapter(client: client, modelId: "gpt-4o")
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `Sources/AISDK/Core/Providers/OpenAIResponsesClientAdapter.swift` | New `ProviderClient` wrapping Responses API |
| `Tests/AISDKTests/Core/Providers/OpenAIResponsesClientAdapterTests.swift` | Unit tests |

## Files to Modify

| File | Change |
|------|--------|
| `Sources/AISDK/Core/Adapters/Provider/ProviderLanguageModelAdapter.swift` | Add `openAIResponses()` and `openAIChatCompletions()` factory methods |
| `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+AITextRequest.swift` | Wire structured output `text` field (line 222) |

## Files Unchanged

- `Sources/AISDK/Core/Providers/OpenAIClientAdapter.swift` — Chat Completions path stays as-is
- `Sources/AISDK/Core/Providers/OpenRouterClient.swift` — unaffected
- `Sources/AISDK/Core/Providers/LiteLLMClient.swift` — unaffected
- `Sources/AISDK/Agents/Agent.swift` — no changes, works through LLM protocol
- All Anthropic/Gemini providers — unaffected

---

## Verification Plan

1. **Build:** `swift build` — no compiler errors
2. **Unit tests:** `swift test --filter OpenAIResponsesClientAdapterTests`
3. **Full test suite:** `swift test` — all 2,397 tests pass
4. **Integration test:** `RUN_LIVE_TESTS=1 swift test --filter OpenAI` — verify real API calls hit `/v1/responses`
5. **Manual verification:** Run `BasicChatDemo` or chat app with the new adapter, confirm runtime logs show `/v1/responses` instead of `/v1/chat/completions`
6. **Built-in tools:** Test `builtInTools: [.webSearchDefault]` with the new adapter — should work (currently throws error)
7. **Backward compatibility:** Verify `OpenAIClientAdapter` path still works unchanged for consumers who need Chat Completions

---

## Drawbacks & Risks

1. **No `n > 1` in Responses API** — consumers needing multiple parallel completions must stay on Chat Completions
2. **ZDR incompatibilities** — background mode, code interpreter, extended caching not ZDR-eligible. Documented, not blocked.
3. **`previous_response_id` + `background` bug** — known OpenAI issue where conversation context isn't appended in background mode. Documented.
4. **Server-side state dependency** — `previous_response_id` chaining relies on OpenAI retaining state. Full-history mode (default) avoids this.
5. **Streaming tool calls** — Phase 1 defers full streaming tool call support. Non-streaming tool execution via Agent loop still works.
