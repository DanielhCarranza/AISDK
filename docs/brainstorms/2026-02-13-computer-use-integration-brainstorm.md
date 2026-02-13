# Computer Use Tool Integration Brainstorm

**Date:** 2026-02-13
**Issue:** #18 — Task 10: Add Computer Use tool integration (OpenAI/Anthropic)
**Status:** Ready for planning

---

## What We're Building

A unified Computer Use tool integration as a first-class `BuiltInTool` case that enables screen interaction actions (screenshot, click, type, scroll, keypress, drag, move, wait) across Anthropic and OpenAI providers. The SDK provides typed, provider-agnostic actions and results while each provider adapter handles wire-format translation.

**Scope:** Computer/screen actions only. Anthropic's `text_editor` and `bash` tools are separate concerns for future work.

---

## Why This Approach

### BuiltInTool Extension (Approach A)

Adding `computerUse(ComputerUseConfig)` to the existing `BuiltInTool` enum follows the exact pattern established by `webSearch`, `codeExecution`, `fileSearch`, and `imageGeneration`. This is the natural fit because:

- Computer use is a **provider-native capability** (server-side), not a client-side function
- The `BuiltInTool` → provider adapter mapping pattern is proven and well-tested
- Config structs already handle provider-specific fields gracefully (shared + optional provider-specific properties)
- No new abstractions or parallel plumbing needed

**Rejected alternatives:**
- **Separate Tool protocol implementation** — Wrong abstraction. Computer use is provider-native, not client-side executable.
- **Raw provider passthrough** — Defeats the SDK's unified purpose. Would force provider-specific consumer code.

---

## Key Decisions

### 1. Scope: Computer tool only (screen actions)

Both Anthropic and OpenAI share the concept of screen-level computer interaction. Anthropic's `text_editor` and `bash` are separate tool types and would be added as distinct `BuiltInTool` cases later if needed. This keeps the initial implementation focused and shippable.

### 2. Configuration: Single `ComputerUseConfig` with provider-specific optional fields

```
ComputerUseConfig:
  - displayWidth: Int          (required, shared)
  - displayHeight: Int         (required, shared)
  - environment: String?       (OpenAI-specific: "browser", "mac", "windows", "ubuntu", "linux")
  - displayNumber: Int?        (Anthropic-specific: X11 display number)
  - enableZoom: Bool?          (Anthropic-specific: computer_20251124 only)
```

Each provider adapter uses the fields it supports, ignores the rest. This matches how `WebSearchConfig` and `CodeExecutionConfig` already work.

### 3. Unified action types: `ComputerUseAction` enum

A single Swift enum covering the union of both providers' action sets:

```
ComputerUseAction:
  - .screenshot
  - .click(x: Int, y: Int, button: ClickButton?)
  - .doubleClick(x: Int, y: Int)
  - .tripleClick(x: Int, y: Int)
  - .type(text: String)
  - .keypress(keys: [String])
  - .scroll(x: Int, y: Int, scrollX: Int?, scrollY: Int?, direction: ScrollDirection?, amount: Int?)
  - .move(x: Int, y: Int)
  - .drag(path: [Coordinate])
  - .wait(durationMs: Int?)
  - .cursorPosition
  - .zoom(region: [Int])
```

Provider adapters translate between this enum and their wire format. Actions unsupported by a provider return a deterministic error.

### 4. Result format: Base64 string + media type

```
ComputerUseResult:
  - screenshot: String?         (base64-encoded image data)
  - mediaType: ImageMediaType?  (png, jpeg, gif, webp)
  - text: String?               (optional text output)
  - isError: Bool
```

Matches what both APIs expect directly — no unnecessary Data ↔ base64 conversion.

### 5. Safety: Optional safety checks on action, SDK handles protocol

OpenAI's `pending_safety_checks` are surfaced as an optional `safetyChecks` property on `ComputerUseAction`. Consumers can inspect and decide. The SDK handles the acknowledgment wire protocol transparently when sending results back. Anthropic actions have `safetyChecks = nil`.

No SDK-level approval gates — consumers implement their own approval logic. This is the industry standard pattern.

### 6. Agent integration: Handler closure

```swift
Agent(
    computerUseHandler: { (action: ComputerUseAction) async throws -> ComputerUseResult in
        // Consumer executes the action (screenshot, click, etc.)
        // Returns result with screenshot
    }
)
```

The Agent's tool loop calls this closure when it encounters a computer use tool call. Simple, composable, no protocol boilerplate.

### 7. Stream events: New `.computerUseAction` event

Computer use actions are surfaced as typed `AIStreamEvent` cases so consumers can observe/log/approve actions even outside the Agent's agentic loop.

---

## Provider Mapping Summary

| SDK Concept | Anthropic Wire Format | OpenAI Wire Format |
|---|---|---|
| `BuiltInTool.computerUse(config)` | `{"type": "computer_20250124", "name": "computer", "display_width_px": ..., "display_height_px": ...}` | `{"type": "computer_use_preview", "display_width": ..., "display_height": ..., "environment": ...}` |
| Beta header | `computer-use-2025-01-24` or `computer-use-2025-11-24` | N/A |
| Action output | `tool_use` content block with `name: "computer"` | `computer_call` output item |
| Result input | `tool_result` with base64 image content | `computer_call_output` with `input_image` |
| Safety checks | N/A | `pending_safety_checks` / `acknowledged_safety_checks` |

---

## Files to Create/Modify

### New files
- `Sources/AISDK/Core/Models/ComputerUse/ComputerUseConfig.swift` — Config struct
- `Sources/AISDK/Core/Models/ComputerUse/ComputerUseAction.swift` — Unified action enum
- `Sources/AISDK/Core/Models/ComputerUse/ComputerUseResult.swift` — Result type
- `Tests/AISDKTests/Core/ComputerUseTests.swift` — Core type tests
- `Tests/AISDKTests/LLMTests/Providers/ComputerUseMappingTests.swift` — Provider mapping tests

### Modified files
- `Sources/AISDK/Core/Models/BuiltInTool.swift` — Add `.computerUse(ComputerUseConfig)` case
- `Sources/AISDK/Core/Models/AIStreamEvent.swift` — Add computer use event cases
- `Sources/AISDK/Core/Providers/AnthropicClientAdapter.swift` — Map to Anthropic wire format
- `Sources/AISDK/Core/Providers/OpenAIClientAdapter.swift` — Reject (Chat Completions doesn't support)
- `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+AITextRequest.swift` — Map to Responses API format
- `Sources/AISDK/LLMs/OpenAI/APIModels/Responses/ResponseTool.swift` — Add computer use case
- `Sources/AISDK/LLMs/Anthropic/AnthropicService.swift` — Auto-add beta header
- `Sources/AISDK/Agents/Agent.swift` — Add handler closure, integrate with tool loop
- `Sources/AISDK/Core/Providers/GeminiClientAdapter.swift` — Reject with deterministic error

---

## Open Questions

_None — all key decisions resolved during brainstorming._

---

## Resolved Questions

1. **Scope?** Computer tool only (screen actions). Text editor and bash are future work.
2. **Provider-specific fields?** Single config struct with optional fields per provider.
3. **Safety gates?** Event-based, no SDK-level approval. Consumers decide.
4. **Agent integration?** Handler closure on Agent.
5. **Action types?** Unified enum covering both providers' action sets.
6. **Result format?** Base64 string + media type.
7. **Safety checks?** Optional field on action, SDK handles acknowledgment protocol.
