# Secondary Live Test Failures - Root-Cause Fix Plan (No Patchwork)

**Date:** 2026-02-13  
**Audience:** Next implementation agent  
**Mission:** Finish remaining real provider/test issues with production-quality fixes. Avoid "skip-first" behavior unless the upstream provider capability is genuinely unavailable and detected precisely.

---

## Implementation Ethos

This SDK should be trustworthy for iOS developers shipping production AI features:

- Prefer **real capability fixes** over broad skips.
- If a feature cannot work for a given account/provider policy, fail or skip with an **explicit, actionable reason**.
- Keep tests meaningful: test functionality, not policy accidents.
- Leave the codebase better than found: clear errors, deterministic behavior, and documented constraints.

---

## What Was Already Done

These were completed in the current branch:

1. **OpenAI Responses error mapping improved**  
   - File: `Sources/AISDK/LLMs/OpenAI/OpenAIProvider.swift`
   - Added parsed error-body mapping for key cases:
     - retrieval `404` guidance around `store: true`
     - code interpreter ZDR restriction messaging
     - image generation availability messaging

2. **`maxOutputTokens` preflight validation added**
   - File: `Sources/AISDK/LLMs/OpenAI/APIModels/Responses/ResponseRequest.swift`
   - `minimumMaxOutputTokens = 16` and `validate()` added.

3. **Responses tests improved for real coverage**
   - Files:
     - `Tests/AISDKTests/LLMTests/Providers/OpenAIResponsesAPITests.swift`
     - `Tests/AISDKTests/LLMTests/Providers/OpenAIResponsesToolsTests.swift`
   - `testResponseRetrieval` uses `store: true` and retries.
   - `toolChoiceAuto` and multi-tool tests no longer rely on code interpreter.
   - Custom function schema fixed (`required` alignment) and now passes live.
   - `image_generation` partial images switched to streaming path.

4. **Built-in tools live ZDR handling aligned to new error shape**
   - File: `Tests/AISDKTests/Integration/BuiltInToolsLiveTests.swift`
   - `test_openai_responses_codeExecution_live` now skips on explicit invalidRequest ZDR message.

---

## Current Remaining Issues

After running full live suite:

```bash
set -a && source .env && set +a && USE_REAL_API=true RUN_LIVE_TESTS=1 swift test
```

One hard failure remains:

1. **OpenRouter basic chat across models**
   - Failing test: `OpenRouterIntegrationTests.test_basic_chat_across_models`
   - File: `Tests/AISDKTests/Integration/OpenRouterIntegrationTests.swift`
   - Error: `invalidRequest("Not found: Resource not found")`
   - Why: default model list includes free-tier models that may not be available for this account/region/provider at runtime.

Secondary concern still not properly fixed:

2. **OpenAI file search payload mismatch**
   - Observed runtime message: expected `vector_store_ids`, got `vector_store_id`.
   - Source likely in file search tool encoding path:
     - `Sources/AISDK/LLMs/OpenAI/APIModels/Responses/ResponseTool.swift`
     - `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+AITextRequest.swift`
   - This should be fixed in payload shape, not skipped.

Capability-limited but important:

3. **`retrieveResponse` capability**
   - `testResponseRetrieval` can still skip after exhaustive retries when account returns "not found" despite `store: true`.
   - This may be account/project capability behavior rather than code bug.
   - Needs definitive provider confirmation and potentially alternative persistence strategy for SDK docs.

---

## Provider Research (Latest Docs to Use)

Use these references before changing behavior:

### OpenAI

- Responses API overview/reference:
  - https://platform.openai.com/docs/api-reference/responses
  - https://platform.openai.com/docs/api-reference/responses/create
- Conversation/state guidance:
  - https://platform.openai.com/docs/guides/conversation-state?api-mode=responses
- Tools guidance:
  - File Search: https://platform.openai.com/docs/guides/tools-file-search
  - Image Generation: https://platform.openai.com/docs/guides/tools-image-generation
  - Streaming events: https://developers.openai.com/api/docs/guides/streaming-responses

### Anthropic

- API error handling and overload behavior:
  - https://docs.anthropic.com/en/api/errors
- Ensure 529 overload handling remains a retry/failover concern, not a brittle test failure.

### OpenRouter

- Free model behavior and availability:
  - https://openrouter.ai/docs/guides/routing/model-variants/free
  - https://openrouter.ai/docs/api-reference/list-available-models/~explorer
  - https://openrouter.ai/models/?q=free

---

## Non-Patch Fix Plan (What To Actually Implement)

### A) OpenRouter `test_basic_chat_across_models` should be robust by model capability

**Goal:** Keep this test meaningful while accounting for real-time free model availability.

1. In `OpenRouterIntegrationTests.test_basic_chat_across_models`, treat provider "not found/resource not found/model unavailable" as **model-level skip**, not suite failure.
2. Continue testing the remaining models in the loop.
3. Require at least one model to pass chat, otherwise fail with a clear aggregated message.
4. Optionally preflight models via OpenRouter model-list endpoint and filter unavailable IDs before test loop.

Why this is not patchwork:
- It validates real chat behavior on available models while explicitly modeling provider availability variance.

---

### B) OpenAI file search payload mismatch must be corrected at source

**Goal:** Build request payload accepted by current Responses API.

1. Inspect file search tool encoder:
   - `ResponseTool.fileSearch(...)` and `ResponseFileSearchTool`.
2. Verify against current OpenAI docs whether request expects:
   - `vector_store_ids` array (likely), not singular `vector_store_id`.
3. Update tool model/encoding to conform exactly.
4. Add/adjust tests in:
   - `OpenAIResponsesToolsTests.testFileSearch`
   - any request serialization tests for Responses tool payload.

Why this is not patchwork:
- Fixes real request contract mismatch for all SDK users.

---

### C) `retrieveResponse` should have a documented capability matrix

**Goal:** Determine if this is an account capability issue vs implementation bug.

1. Keep current retry behavior in test.
2. Add targeted diagnostic logging (non-secret) around:
   - create response ID
   - store flag used
   - retrieval status code/message
3. Validate behavior on:
   - at least one non-ZDR key
   - at least one known "full capability" OpenAI project/org
4. If still non-retrievable across valid configs, document:
   - retrieval prerequisites
   - fallback strategy (local persistence + previousResponseId chain)
5. If retrievable on a different key/org, keep test skip only for explicit account capability mismatch.

Why this is not patchwork:
- Turns unknown behavior into documented capability and deterministic handling.

---

### D) Code interpreter strategy for this SDK

Product direction states code interpreter can be removed.  
If that decision is final:

1. Remove or de-emphasize code execution built-in tool paths in tests/docs where not required.
2. Keep explicit error for unsupported/ZDR states if API remains exposed.
3. Favor function tools for health-assistant scenarios.

Why this is not patchwork:
- Aligns SDK feature surface with intended product scope and policy reality.

---

## Function Tool Status

Current state: function tool path now works in live tests after schema correction (`required` includes all defined required properties used by schema constraints).  
Primary touchpoint:
- `Tests/AISDKTests/LLMTests/Providers/OpenAIResponsesToolsTests.swift`

Action:
- Mark as complete unless new provider regression appears.

---

## Image Generation Status

Current state:
- Base image generation passes live.
- Partial images require streaming and now run through streaming path in test.

Action:
- Keep as complete, but ensure docs/comments explicitly note streaming requirement for partial images.

---

## Suggested Execution Checklist For Next Agent

1. Run focused suites first:
   - `OpenRouterIntegrationTests`
   - `OpenAIResponsesToolsTests`
   - `OpenAIResponsesAPITests/testResponseRetrieval`
2. Implement OpenRouter availability-aware loop handling in `test_basic_chat_across_models`.
3. Implement file search payload fix and verify with live call.
4. Re-run full live suite.
5. Update docs for any proven provider capability constraints.

---

## Success Criteria

- Full live test suite passes or only has **explicit, justified capability skips**.
- No generic "resource not found" hard failures for model-availability drift.
- File search requests match OpenAI contract and pass with valid vector store setup.
- `retrieveResponse` behavior is either truly working or explicitly documented as account-gated with clear developer guidance.

---

## Verification Notes (2026-02-13)

- OpenAI Responses `file_search` payload is now encoded as:
  - `{"type":"file_search","vector_store_ids":["..."]}`
- Live `OpenAIResponsesToolsTests/testFileSearch` now sends the corrected contract shape and reaches expected runtime behavior:
  - `404` only when the test vector store ID does not exist (not due to payload mismatch).
- OpenRouter `test_basic_chat_across_models` now treats model availability drift as model-level skip and continues:
  - Verified behavior where one free model returned `"Resource not found"` and remaining models still passed.
- `OpenAIResponsesAPITests/testResponseRetrieval` with `store: true` still skips on this account after retries:
  - Current evidence indicates account/project capability variance remains for retrieval, even with correct request setup.

