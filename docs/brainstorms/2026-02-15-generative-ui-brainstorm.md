# Generative UI for AISDK 2.0

**Date:** 2026-02-15
**Status:** Brainstorm
**Authors:** Joel Mushagasha + Claude

## What We're Building

A comprehensive generative UI system that makes AISDK 2.0 the definitive Swift SDK for AI-driven native interfaces. The system enables LLM agents to seamlessly mix text and rich SwiftUI components in a single streamed response — charts, forms, dashboards, and interactive controls rendered progressively as tokens arrive.

### Core Capabilities

1. **SpecStream (Progressive Rendering)** — JSONL patch-based streaming that builds UI incrementally via RFC 6902 JSON Patch operations. UI appears as patches arrive, no waiting for complete JSON.

2. **Controlled Generative UI (UITool Protocol)** — Tools that automatically render pre-built SwiftUI views with loading/executing/complete lifecycle states. The model calls a tool; the client renders the registered component.

3. **Bidirectional State Flow** — Interactive components (toggles, sliders, inputs) send state changes back to the AI agent, enabling conversational UI where the agent reacts to user interactions.

4. **Agent-to-GenerativeUI Bridge** — A seamless pipeline from `agent.streamExecute()` to rendered generative UI. Uses `AIStreamEvent` types (`.textDelta` for text, `.uiPatch` for UI) for unambiguous stream segmentation.

5. **Hybrid Text + UI Responses** — A single agent response can mix markdown prose and generative UI components. The model naturally decides when a UI element is needed. Stream events handle the separation at the protocol level, not content level.

## Why This Approach

### Inspiration Sources

- **CopilotKit Generative UI** — Three patterns: Controlled (tool-based), Declarative (JSON-UI), Open-ended (MCP Apps). We adopt the Controlled pattern and enhance our existing Declarative pattern.
- **Vercel json-render** — SpecStream JSONL patch protocol for progressive rendering. Flat element map, catalog-to-prompt generation, separated state model with `$path` bindings.

### What Already Exists in AISDK

The SDK has a substantial foundation (25+ components, UITree, UICatalog, UIComponentRegistry, GenerativeUIViewModel with 60fps batching). The architecture is already aligned with json-render's design:

| Primitive | AISDK Status | Enhancement Needed |
|-----------|-------------|-------------------|
| Flat element map (UITree) | Complete | Add SpecStream patch support |
| Component catalog + prompt generation | Complete (UICatalog) | Add `$path`/`$cond` state bindings |
| Component registry + view builders | Complete | Add UITool render lifecycle |
| Streaming ViewModel (60fps batching) | Complete | Wire to SpecStream compiler |
| Tool system with execution loop | Complete | Add UITool protocol |
| AIStreamEvent (20+ event types) | Complete | Add `.uiPatch` event type |
| Agent streaming | Complete | Bridge to GenerativeUI ViewModel |

### Why NOT MCP Apps / Open-ended Pattern

CopilotKit's Open-ended pattern uses HTML/iframes. This is web-centric and doesn't fit native iOS/macOS. Rendering arbitrary HTML via WKWebView sacrifices performance, native feel, and accessibility. Not pursuing this.

## Key Decisions

### 1. Core Primitives, Not Optional Module

Generative UI capabilities live IN the AISDK as core primitives. Developers get generative UI out of the box with minimal setup. No separate module to opt into.

**Rationale:** Generative UI is a differentiator for the SDK. Making it core ensures consistent API design and reduces friction.

### 2. Protocol-Based UITool with Convenience Extensions

The Controlled pattern uses a `UITool` protocol extending `Tool` that adds an associated `View` type and a `render()` method. Convenience extensions make the simple case trivial. Developers can override any part for full customization.

```swift
// Simple case — convenience extension handles most of the work
struct WeatherTool: UITool {
    @Parameter var location: String

    func execute() async throws -> ToolResult { /* fetch weather */ }

    var body: some View {
        WeatherCard(location: location, result: result)
    }
}

// Advanced case — full lifecycle control
struct DashboardTool: UITool {
    func render(phase: UIToolPhase) -> some View {
        switch phase {
        case .loading: ShimmerPlaceholder()
        case .executing(let progress): ProgressOverlay(progress)
        case .complete(let result): DashboardView(data: result)
        case .error(let error): ErrorCard(error)
        }
    }
}
```

**Rationale:** Protocol gives strong type safety (robust), default implementations make simple cases trivial (simple defaults), developers override any part (customizable).

### 3. Dual Mode: Complete JSON + SpecStream

Both rendering modes supported:
- **Complete JSON** — simple default for non-streaming use cases. Existing UITree parser handles this today.
- **SpecStream** — JSONL patch-based streaming for progressive rendering. New `SpecStreamCompiler` buffers chunks, splits by newline, applies RFC 6902 patches to UITree incrementally.

**Rationale:** Complete JSON is simpler for basic use cases. SpecStream is necessary for production-quality streaming. Supporting both means developers start simple and upgrade when needed.

### 4. Stream Events for Text+UI Segmentation

Mixed text and UI in a single response uses distinct `AIStreamEvent` types:
- `.textDelta(String)` — markdown/prose content
- `.uiPatch(SpecPatch)` — UI specification patch

No content-level parsing, no delimiter detection. The provider adapter maps structured output/tool calls to `.uiPatch` events. Text stays as `.textDelta`.

**Rationale:** Most robust approach. No ambiguity from markdown containing `{` characters or code blocks. Works at the protocol level. Leverages existing 20+ event type infrastructure.

### 5. Separated State Model with Dynamic Bindings

Following json-render's pattern, the UI spec has a separate `state` dictionary. Props can reference state values via `$path` expressions and conditionals via `$cond`.

```json
{
  "state": { "metrics": { "revenue": 12345 } },
  "elements": {
    "metric": {
      "type": "Metric",
      "props": { "value": { "$path": "/metrics/revenue" } }
    }
  }
}
```

**Rationale:** Separating state from elements enables the agent to update data without re-specifying the entire UI structure. Critical for bidirectional state flow.

### 6. Capability-Based Model Strategy

Instead of hardcoding provider-specific prompts, the SDK auto-detects model capabilities and selects the best rendering strategy. Developers override with one line for custom models.

```swift
// Auto-detect for known models
let agent = Agent(model: .anthropic(.claude4))  // auto: Tier 1 (SpecStream)

// One-line override for any model
let agent = Agent(model: .custom(kimi2), specStreamStrategy: .jsonlPatches)
```

**Rationale:** Model-agnostic by default. Works with big 3 providers and any custom model (Kimi 2, DeepSeek, Mistral, etc.). Developers don't need deep knowledge of model capabilities — SDK handles known models, one-line override for everything else.

### 7. Scoped State with Explicit Data Injection

Generative UI state is self-contained — the LLM creates it and references it. It cannot reach app-level state. Developers explicitly inject app data via a callback for security by default with opt-in bridging.

**Rationale:** Prevents LLM-generated UI from accessing sensitive app data. Explicit injection makes the data flow auditable and debuggable.

## Implementation Scope

### Phase 1: SpecStream + Agent Bridge
- `SpecStreamCompiler` — buffers, splits, applies RFC 6902 patches to UITree
- `SpecPatch` model (add/remove/replace/move operations)
- `.uiPatch(SpecPatch)` event type added to `AIStreamEvent`
- `GenerativeUIViewModel.subscribe(to: AsyncThrowingStream<AIStreamEvent>)` — handles mixed text+UI events
- State model with `$path` resolution in props

### Phase 2: UITool Protocol
- `UITool` protocol extending `Tool` with associated View type
- `UIToolPhase` enum (loading/executing/complete/error)
- `Agent` integration — auto-renders UITool results as generative UI
- Convenience extensions for simple tool→view mapping

### Phase 3: Bidirectional State
- Action callbacks from interactive components → agent context
- State update events from UI → agent (user changed a toggle, filled an input)
- Agent can respond to state changes with new UI patches or text

### Phase 4: Polish + Examples
- Example apps demonstrating each pattern
- Dashboard example (SpecStream with charts + metrics)
- Conversational form example (UITool with bidirectional state)
- Documentation and developer guide

## Resolved Questions

1. **Catalog versioning** — Specs include a catalog semver. The renderer validates compatibility and can gracefully degrade for minor mismatches. Breaking changes require a major version bump.

2. **Error recovery in SpecStream** — Skip and continue. Malformed JSONL patch lines are logged and skipped; the compiler keeps rendering what it has. No halt, no user-facing error for a single bad patch.

3. **Provider support / Model agnosticism** — Capability-based tier system, not provider-specific:
   - **Tier 1:** Model supports reliable text formatting → SpecStream JSONL patches via system prompt
   - **Tier 2:** Model supports structured output → Complete JSON via `streamObject`, progressively decoded
   - **Tier 3:** Model supports basic tool calls → UITool pattern (Controlled, no SpecStream)
   - SDK auto-detects for known models; developers override with one line for custom/new models (Kimi 2, DeepSeek, etc.)

4. **Security model for `$path` bindings** — Scoped, self-contained state. The `state` dictionary in a UI spec is created by the LLM and cannot reach app-level state, user defaults, keychain, or anything external. Developers explicitly inject app data via a callback:
   ```swift
   GenerativeUIView(spec: spec) { state in
       state["userName"] = currentUser.name  // explicit opt-in
   }
   ```

## References

- [CopilotKit Generative UI](https://github.com/CopilotKit/generative-ui)
- [Vercel json-render](https://github.com/vercel-labs/json-render)
- [AG-UI Protocol](https://docs.copilotkit.ai/generative-ui/specs/a2ui)
- [Open-JSON-UI Spec](https://docs.copilotkit.ai/generative-ui/specs/open-json-ui)
- [RFC 6902 JSON Patch](https://datatracker.ietf.org/doc/html/rfc6902)
