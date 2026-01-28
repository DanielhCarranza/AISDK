# Anthropic Messages API: Extended thinking and batch processing

Anthropic's API maintains a cleaner, more opinionated design than OpenAI but introduces powerful new capabilities through beta features. The **Claude 4 family** (Sonnet 4.5, Opus 4.5, Haiku 4.5) represents the current generation, with Claude 3.5 models now deprecated.

### Endpoint inventory

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/v1/messages` | Create message |
| POST | `/v1/messages/count_tokens` | Pre-count tokens |
| POST | `/v1/messages/batches` | Create batch |
| GET | `/v1/messages/batches/{id}` | Get batch status |
| GET | `/v1/messages/batches/{id}/results` | Stream batch results |
| POST | `/v1/files` | Upload file (beta) |
| GET | `/v1/models` | List available models |

### Request schema with all parameters

```swift
struct MessagesRequest: Codable {
    let model: String                           // Required
    let messages: [MessageParam]                // Required
    let maxTokens: Int                          // Required (minimum: 1)
    var system: SystemPromptUnion?              // String or [TextBlockParam]
    var metadata: Metadata?                     // {user_id?: String}
    var stopSequences: [String]?
    var temperature: Double?                    // 0.0-1.0, default 1.0
    var topP: Double?                           // default 0.99
    var topK: Int?
    var stream: Bool?
    var tools: [ToolUnion]?
    var toolChoice: ToolChoice?
    var thinking: ThinkingConfig?               // Extended thinking
    var serviceTier: ServiceTier?               // "auto" | "standard_only"
}
```

### Content block types

Anthropic uses a discriminated union pattern for content:

**Input types** (in messages):
- `TextBlockParam`: `{type: "text", text: String, cache_control?, citations?}`
- `ImageBlockParam`: `{type: "image", source: Base64ImageSource | URLImageSource}`
- `DocumentBlockParam`: `{type: "document", source: Base64PDFSource | URLPDFSource | FileSource}`
- `ToolUseBlockParam`: `{type: "tool_use", id, name, input}` (from assistant)
- `ToolResultBlockParam`: `{type: "tool_result", tool_use_id, content, is_error?}`
- `ThinkingBlockParam`: `{type: "thinking", thinking, signature}` (from assistant)

**Image limits**: Max 20 images/request, 3.75 MB each, 8000px max dimension
**PDF limits**: Max 5 documents, 4.5 MB each

### Extended thinking implementation

Extended thinking enables chain-of-thought reasoning with configurable token budgets:

```swift
thinking: ThinkingConfig(
    type: .enabled,
    budgetTokens: 8192  // Minimum 1024, must be < maxTokens
)
```

Response includes `ThinkingBlock`:
```swift
struct ThinkingBlock: Codable {
    let type: String = "thinking"
    let thinking: String      // Summarized in Claude 4 (billed for full)
    let signature: String     // Verification signature
}
```

**Critical notes**:
- Claude 4 models return **summarized** thinking (billed for full internal tokens)
- Cannot use with response prefill
- Thinking blocks from previous turns are stripped (except Opus 4.5)
- For tool use with thinking, add beta header: `interleaved-thinking-2025-05-14`

### Streaming event schema

Anthropic uses a straightforward SSE event model:

```
event: message_start
data: {"type": "message_start", "message": {...}}

event: content_block_start
data: {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}}

event: content_block_delta
data: {"type": "content_block_delta", "index": 0, "delta": {"type": "text_delta", "text": "Hello"}}

event: content_block_stop
data: {"type": "content_block_stop", "index": 0}

event: message_delta
data: {"type": "message_delta", "delta": {"stop_reason": "end_turn"}, "usage": {"output_tokens": 15}}

event: message_stop
data: {"type": "message_stop"}
```

**Delta types**:
- `text_delta`: Incremental text content
- `input_json_delta`: Tool use arguments (accumulate partial JSON until `content_block_stop`)
- `thinking_delta`: Extended thinking content
- `signature_delta`: Thinking signature (just before block stop)

**Tool use streaming behavior**: Arguments stream as `partial_json` strings that must be accumulated and parsed only after `content_block_stop`.

### Batches API for cost optimization

Batch processing provides **50% cost savings** for non-time-sensitive workloads:

```swift
struct BatchRequest: Codable {
    let requests: [BatchRequestItem]  // Up to 100,000 requests
}

struct BatchRequestItem: Codable {
    let customId: String              // 1-64 chars, unique per batch
    let params: MessagesRequest       // Standard message params
}
```

**Lifecycle**: `in_progress` → `canceling` → `ended`
**Processing time**: Up to 24 hours (often faster)
**Max batch size**: 256 MB
**Results**: JSONL stream at `/v1/messages/batches/{id}/results`

### Beta features requiring headers

| Feature | Header | Notes |
|---------|--------|-------|
| Files API | `files-api-2025-04-14` | Upload and reference files |
| 1M context | `context-1m-2025-08-07` | Claude Sonnet 4.5 only |
| Computer use | `computer-use-2025-01-24` | Screen interaction |
| Interleaved thinking | `interleaved-thinking-2025-05-14` | Thinking with tools |
| Code execution | `code-execution-2025-05-22` | Python sandbox |
| Structured outputs | `structured-outputs-2025-11-13` | Guaranteed schema conformance |

**Files API reference pattern**:
```swift
DocumentBlockParam(
    type: "document",
    source: FileSource(type: "file", fileId: "file_011CNha8iCJcU1wXNR6q4V8w")
)
```

### Current model capabilities

| Model | Context | Max Output | Vision | Extended Thinking |
|-------|---------|------------|--------|-------------------|
| claude-sonnet-4-5 | 200K (1M beta) | 64K | ✓ | ✓ |
| claude-opus-4-5 | 200K | 64K | ✓ | ✓ (preserves history) |
| claude-haiku-4-5 | 200K | 64K | ✓ | ✓ |
| claude-sonnet-4 | 200K | 64K | ✓ | ✓ |
| claude-opus-4 | 200K | 64K | ✓ | ✓ |
