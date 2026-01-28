# Cross-provider patterns and healthcare implications

### Conversation and context management

| Provider | Pattern | Server-side State | Max Context |
|----------|---------|-------------------|-------------|
| OpenAI | `previous_response_id` or `conversation` | ✓ (30 days) | 1M (gpt-4.1) |
| Anthropic | Client manages message array | ✗ | 1M (beta) |
| Gemini | Client manages contents array | Via caching | 1M+ |

**AISDK recommendation**: Abstract conversation management with provider-specific adapters. For OpenAI, leverage server-side state; for others, implement client-side history with optional persistence layer.

### Tool calling schema comparison

**OpenAI** (internally tagged, strict by default):
```json
{"type": "function", "name": "...", "parameters": {...}, "strict": true}
```

**Anthropic** (custom type, explicit schema):
```json
{"name": "...", "description": "...", "input_schema": {"type": "object", ...}}
```

**Gemini** (function declarations):
```json
{"functionDeclarations": [{"name": "...", "parameters": {...}}]}
```

**AISDK AITool protocol** should normalize these into a common format with provider-specific serialization.

### File handling patterns

| Feature | OpenAI | Anthropic | Gemini |
|---------|--------|-----------|--------|
| Upload endpoint | `/v1/files` | `/v1/files` (beta) | `/upload/v1beta/files` |
| Max size | 512 MB (8 GB via Uploads API) | 4.5 MB (PDF) | Video: hours of content |
| Video support | ✗ | ✗ | ✓ |
| Audio support | ✓ (transcription) | ✗ | ✓ (native) |
| PDF support | ✓ (via file_search) | ✓ (native) | ✓ (native) |
| Expiration | Manual or custom | Unknown | 48 hours |
| Purpose field | Required | Not required | Not applicable |

### Multimodal format support

| Format | OpenAI | Anthropic | Gemini |
|--------|--------|-----------|--------|
| JPEG/PNG/WebP | ✓ | ✓ | ✓ |
| GIF | ✓ | ✓ | ✓ |
| HEIC | ✗ | ✗ | ✓ |
| PDF | ✓ (file_search) | ✓ (native) | ✓ (native) |
| MP4/Video | ✗ | ✗ | ✓ |
| MP3/WAV | ✓ (transcription) | ✗ | ✓ (native) |

### Healthcare-relevant considerations

**Data retention and compliance**:
- **OpenAI**: Zero Data Retention (ZDR) available for enterprise; 30-day default retention for stored responses
- **Anthropic**: No specific HIPAA documentation in API; enterprise agreements available
- **Gemini**: Data processed per Google Cloud terms; Vertex AI offers HIPAA BAA

**Recommended approach for PHI**:
1. Use enterprise tiers with BAAs where available
2. Implement client-side encryption for stored context
3. Avoid storing PHI in conversation history—use de-identified references
4. Log `response_id`/`batch_id` for audit trails without storing content

**Batch processing for analytics**:
- Anthropic Batches API offers **50% cost savings** for non-urgent processing
- Suitable for: chart summarization, coding assistance, quality metrics
- Not suitable for: real-time clinical decision support

---

## Gap analysis: AISDK 2.0 vs native APIs

### Features requiring implementation

| Feature | OpenAI | Anthropic | Gemini | AISDK Priority |
|---------|--------|-----------|--------|----------------|
| Server-side conversation state | `previous_response_id` | N/A | Caching | High |
| Built-in web search | ✓ | ✓ (beta) | ✓ (Google Search) | High |
| Built-in file search/RAG | ✓ (vector stores) | ✗ | ✗ | High |
| Code execution | ✓ (code_interpreter) | ✓ (beta) | ✓ | Medium |
| Extended thinking | ✓ (o-series reasoning) | ✓ (thinking blocks) | ✓ (Gemini 3) | High |
| Video processing | ✗ | ✗ | ✓ | High |
| Batch processing | ✓ | ✓ (50% discount) | ✗ | Medium |
| Context caching | N/A (server state) | ✓ (prompt caching) | ✓ (explicit + implicit) | Medium |
| Computer use | ✓ (preview) | ✓ | ✗ | Low |

### Streaming event abstraction

AISDK should provide a unified streaming event model:

```swift
enum AIStreamEvent {
    case started(responseId: String)
    case textDelta(String)
    case toolCallStarted(id: String, name: String)
    case toolCallDelta(id: String, argumentsChunk: String)
    case toolCallCompleted(id: String, arguments: [String: Any])
    case thinkingDelta(String)
    case thinkingCompleted(summary: String)
    case completed(finishReason: FinishReason, usage: Usage)
    case error(AIError)
}
```

Each provider adapter translates native events to this common model.

## Conclusion

The three providers have diverged significantly in their architectural approaches. **OpenAI** pushes toward server-managed state and integrated tools, **Anthropic** maintains a cleaner API surface with powerful opt-in features, and **Gemini** leads in multimodal processing and context length.

For AISDK 2.0, the critical implementation priorities are:

1. **Abstract conversation management** to handle OpenAI's server state vs client-managed approaches
2. **Implement unified tool protocol** that maps AITool to each provider's schema
3. **Add Gemini video support** as a unique capability for healthcare imaging use cases
4. **Support extended thinking** across all providers for complex clinical reasoning
5. **Integrate batch processing** for cost-optimized analytics workflows

The SDK architecture should use protocol-oriented design with provider-specific adapters, enabling healthcare applications to leverage each provider's strengths while maintaining a consistent API surface.
