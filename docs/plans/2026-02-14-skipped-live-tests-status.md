# Skipped Live Tests Status (7 Remaining)

**Date:** 2026-02-14  
**Context:** Re-ran previously skipped suites with `USE_REAL_API=true RUN_LIVE_TESTS=1`.

## Summary

- Remaining skips after targeted rerun: **7**
- All are **capability/availability/runtime** constraints, not payload-shape bugs.
- No functional test failures were observed in these reruns.

## Skip Matrix

| Test | Current skip reason | Likely root cause | What to do |
| --- | --- | --- | --- |
| `AnthropicServiceToolsTests.testRealAPIToolStreaming` | Anthropic overloaded or returned corrupted data | Transient provider reliability (`529`/overload) | Keep retry+skip behavior for live tests; consider retry/backoff wrapper in test harness if stricter stability is needed. |
| `BuiltInToolsLiveTests.test_openai_responses_codeExecution_live` | `code_interpreter` unavailable for this key (ZDR restriction) | OpenAI policy: code interpreter requires container/storage; ZDR keys block it | Use non-ZDR OpenAI project for this test, or de-scope code interpreter tests if product direction is to avoid this tool. |
| `ComputerUseLiveTests.test_anthropic_computerUseZoom_accepted` | `computer_20251124` not supported by selected model | Anthropic model/tool-version mismatch for zoom-enabled computer use | Use a model/tool combination that explicitly supports `computer_20251124`, or run non-zoom `computer_20250124` path only. |
| `OpenRouterIntegrationTests.test_json_response_default_model` | Free model unavailable (`Resource not found`) | OpenRouter free-model availability drift by account/region/provider | Pin to stable paid model for deterministic CI/live validation, or keep per-model skip with at-least-one-success rule. |
| `OpenRouterIntegrationTests.test_reasoning_prompt_default_model` | Same as above | Same as above | Same as above. |
| `OpenRouterStressTests.test_long_response_streaming` | Rate limited | OpenRouter quota/rate limits on stress traffic | Increase quota or run stress tests against paid/non-free model set. |
| `OpenRouterStressTests.test_multiple_free_models` | All free models rate limited | Free-tier throttling | Same as above; prefer paid stable model set for reliability gates. |

## Notes On The Two Items You Called Out

### 1) OpenAI code interpreter + ZDR

- In code, `codeExecution` is implemented as a first-class built-in tool (`BuiltInTool.codeExecution`), mapped to OpenAI `code_interpreter`.
- Live skip is account-policy driven (ZDR), not an SDK serialization issue.
- If current product direction is to **not rely on code interpreter yet**, best practice is:
  - keep feature support in API surface,
  - keep explicit error messaging for ZDR/unsupported cases,
  - move strict pass requirements to function-tools/web-search paths.

### 2) Anthropic zoom computer-use availability

- Current adapter intentionally emits:
  - `computer_20251124` when `enableZoom == true`,
  - `computer_20250124` otherwise.
- The skip indicates the selected model (`claude-sonnet-4-20250514`) did not accept the zoom tool version in this environment.
- Action should be model/version pairing validation, not a blind test hard-fail.

## Recommended Policy

- For implementation confidence, require **zero failures** and allow skips only for:
  - provider overload/rate limits,
  - account policy restrictions (e.g., ZDR),
  - explicit model capability mismatch.
- For release-grade deterministic runs, maintain a separate profile that uses:
  - non-ZDR OpenAI key (if code interpreter is required),
  - Anthropic model confirmed for zoom computer use,
  - paid OpenRouter models with sufficient quota.

