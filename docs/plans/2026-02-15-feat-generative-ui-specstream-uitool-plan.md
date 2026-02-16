---
title: "Generative UI: SpecStream, UITool Protocol & Bidirectional State"
type: feat
status: completed
date: 2026-02-15
branch: aisdk-2.0-modernization
spec: "docs/brainstorms/2026-02-15-generative-ui-brainstorm.md"
---

# Generative UI: SpecStream, UITool Protocol & Bidirectional State

## Overview

Implement a comprehensive generative UI system that enables LLM agents to seamlessly mix text and rich SwiftUI components in a single streamed response. The system builds on AISDK's existing GenerativeUI foundation (UITree, UICatalog, UIComponentRegistry, GenerativeUIViewModel) by adding three capabilities:

1. **SpecStream** — JSONL patch-based progressive rendering via RFC 6902 JSON Patch
2. **UITool Protocol** — Tools that auto-render SwiftUI views with lifecycle states
3. **Bidirectional State** — Interactive components send state changes back to the agent

## Problem Statement

The SDK has a complete generative UI rendering pipeline (25+ components, flat element map, 60fps ViewModel batching), but it only supports **complete JSON replacement** — the entire UI spec must arrive before rendering. This creates three gaps:

1. **No progressive rendering** — Users wait for the complete JSON before seeing anything. For complex UIs (dashboards, multi-section forms), this means seconds of blank screen.
2. **No tool-to-view bridge** — Tool execution produces `ToolResult` (text), but there's no standard way to render a rich SwiftUI view from a tool call. The existing `RenderableTool` protocol (`Parameter.swift:294`) is minimal (just `render(from: Data) -> AnyView`) with no lifecycle support.
3. **No bidirectional flow** — Interactive components (Toggle, Slider, Picker) maintain local `@State` but never communicate changes back to the agent. The agent can't react to user interactions.

## Proposed Solution

### Architecture

```
Agent.streamExecute()
    │
    ▼
AsyncThrowingStream<AIStreamEvent>
    │
    ├── .textDelta(String)  ──────────► Text/Markdown renderer
    │
    ├── .uiPatch(SpecPatch) ──────────► SpecStreamCompiler
    │                                       │
    │                                       ▼
    │                                   UITree (incremental)
    │                                       │
    │                                       ▼
    │                                   GenerativeUIViewModel
    │                                       │
    │                                       ▼
    │                                   UIComponentRegistry → SwiftUI
    │
    └── .toolCall (UITool)  ──────────► UIToolPhase lifecycle
                                            │
                                            ▼
                                        UITool.body / render(phase:)
```

### Key Design Decisions

**1. `.uiPatch(SpecPatch)` event type (not content parsing)**
The provider adapter maps structured output to `.uiPatch` events at the protocol level. No content-level parsing or delimiter detection. This is unambiguous — markdown containing `{` or code blocks won't break it.

**2. SpecStreamCompiler as a separate type**
The compiler buffers JSONL chunks, splits by newline, applies RFC 6902 patches to UITree. It's distinct from `GenerativeUIViewModel` (which handles 60fps throttling). Separation of concerns: compiler transforms data, ViewModel manages rendering cadence.

**3. UITool extends Tool + RenderableTool evolution**
`UITool` replaces the minimal `RenderableTool` with a richer protocol: associated `View` type, `UIToolPhase` lifecycle (loading/executing/complete/error), convenience defaults for simple cases.

**4. Separated state model with $path bindings**
Following json-render's pattern: state dictionary is separate from elements. Props reference state via `{ "$path": "/metrics/revenue" }`. This enables the agent to update data without re-specifying the entire UI structure.

**5. Scoped state (security by default)**
LLM-generated state cannot reach app-level state, user defaults, or keychain. Developers explicitly inject app data via callback — auditable and debuggable.

---

## Implementation Phases

### Phase 1: SpecStream + Agent Bridge

**Goal:** Progressive rendering — UI appears incrementally as JSONL patches arrive.

#### 1.1 SpecPatch Model

```swift
// Sources/AISDK/GenerativeUI/SpecStream/SpecPatch.swift

/// RFC 6902 JSON Patch operation for UITree
public struct SpecPatch: Sendable, Codable, Equatable {
    /// The patch operation type
    public let op: Operation
    /// JSON Pointer path (e.g., "/elements/metric", "/state/revenue")
    public let path: String
    /// Value for add/replace operations
    public let value: AnyCodable?
    /// Source path for move/copy operations
    public let from: String?

    public enum Operation: String, Sendable, Codable {
        case add
        case remove
        case replace
        case move
        case copy
        case test
    }
}

/// A batch of patches from a single JSONL line
public struct SpecPatchBatch: Sendable, Codable, Equatable {
    public let patches: [SpecPatch]
    public let version: String?  // Catalog semver for compat check
}
```

**Files to create:**
- `Sources/AISDK/GenerativeUI/SpecStream/SpecPatch.swift`
- `Sources/AISDK/GenerativeUI/SpecStream/AnyCodable.swift` (type-erased Codable for patch values)

**Tests:**
- `Tests/AISDKTests/GenerativeUI/SpecPatchTests.swift` — encoding/decoding, RFC 6902 compliance

#### 1.2 Add `.uiPatch` to AIStreamEvent

```swift
// Sources/AISDK/Core/Models/AIStreamEvent.swift (line ~93, before .error)

/// UI specification patch for progressive generative UI rendering
case uiPatch(SpecPatchBatch)
```

**Files to modify:**
- `Sources/AISDK/Core/Models/AIStreamEvent.swift:93` — add case

**Tests:**
- Update `Tests/AISDKTests/Core/AIStreamEventTests.swift` if event tests exist

#### 1.3 SpecStreamCompiler

```swift
// Sources/AISDK/GenerativeUI/SpecStream/SpecStreamCompiler.swift

/// Buffers JSONL chunks, splits by newline, applies RFC 6902 patches to UITree
public final class SpecStreamCompiler: Sendable {
    /// Apply a batch of patches to the current tree state
    public func apply(_ batch: SpecPatchBatch, to tree: UITree) throws -> UITree

    /// Process a raw JSONL chunk (may contain partial lines)
    public func processChunk(_ chunk: String) -> [SpecPatchBatch]

    /// Reset compiler state (clear buffer)
    public func reset()
}
```

Key behaviors:
- Buffers incomplete JSONL lines across chunks
- Splits by `\n`, decodes each line as `SpecPatchBatch`
- Malformed lines are logged and skipped (fault-tolerant)
- Path validation: patches can only target `/elements/*`, `/state/*`, `/root`
- Applies operations to a mutable copy of UITree's element map

**Files to create:**
- `Sources/AISDK/GenerativeUI/SpecStream/SpecStreamCompiler.swift`

**Tests:**
- `Tests/AISDKTests/GenerativeUI/SpecStreamCompilerTests.swift` — complete patches, partial chunks, malformed lines, path validation, all RFC 6902 operations

#### 1.4 State Model with $path Resolution

```swift
// Sources/AISDK/GenerativeUI/SpecStream/UIState.swift

/// Separated state dictionary for generative UI specs
public struct UIState: Sendable, Equatable {
    /// State values keyed by path segments
    public var values: [String: Any]  // JSON-compatible values

    /// Resolve a $path expression against the state
    public func resolve(path: String) -> Any?

    /// Resolve $cond expressions: { "$cond": "/flag", "then": X, "else": Y }
    public func resolveConditional(_ cond: [String: Any]) -> Any?
}

// Sources/AISDK/GenerativeUI/SpecStream/UISpec.swift

/// Complete UI specification with elements + state
public struct UISpec: Sendable {
    public let root: String
    public let elements: [String: UINode]
    public let state: UIState
    public let catalogVersion: String?
}
```

**Files to create:**
- `Sources/AISDK/GenerativeUI/SpecStream/UIState.swift`
- `Sources/AISDK/GenerativeUI/SpecStream/UISpec.swift`

**Tests:**
- `Tests/AISDKTests/GenerativeUI/UIStateTests.swift` — path resolution, nested paths, conditionals, missing keys

#### 1.5 GenerativeUIViewModel Enhancement

Add a new `subscribe` overload that handles mixed `AIStreamEvent` streams:

```swift
// Sources/AISDK/GenerativeUI/ViewModels/GenerativeUIViewModel.swift

/// Subscribe to a mixed text+UI stream from an agent
public func subscribe(
    to stream: AsyncThrowingStream<AIStreamEvent, Error>,
    compiler: SpecStreamCompiler = SpecStreamCompiler(),
    onText: @escaping (String) -> Void = { _ in }
) async {
    // Route .textDelta to onText callback
    // Route .uiPatch to compiler, apply patches to tree
    // Use existing 60fps batching for tree updates
}
```

**Files to modify:**
- `Sources/AISDK/GenerativeUI/ViewModels/GenerativeUIViewModel.swift` — add new subscribe overload, add `UITreeUpdate.applyPatch(SpecPatchBatch)` case

**Tests:**
- `Tests/AISDKTests/GenerativeUI/GenerativeUIViewModelTests.swift` — mixed stream subscription, text routing, patch application, error recovery

#### 1.6 StreamSimulation Extension

```swift
// Tests/AISDKTests/Helpers/StreamSimulation.swift

extension StreamSimulation {
    /// Simulates a mixed text + UI patch stream
    static func textAndUIStream(
        textDeltas: [String],
        patches: [SpecPatchBatch]
    ) -> [AIStreamEvent]

    /// Simulates progressive UI building via patches
    static func progressiveUIStream(
        patches: [SpecPatchBatch],
        delayMs: Int = 50
    ) -> [AIStreamEvent]
}
```

**Files to modify:**
- `Tests/AISDKTests/Helpers/StreamSimulation.swift` — add UI stream factories

---

### Phase 2: UITool Protocol

**Goal:** Tools that automatically render SwiftUI views with lifecycle states.

#### 2.1 UITool Protocol

```swift
// Sources/AISDK/Tools/UITool.swift

#if canImport(SwiftUI)
import SwiftUI

/// A tool that renders a SwiftUI view alongside its execution
public protocol UITool: Tool {
    /// The SwiftUI view type for rendering
    associatedtype Body: View

    /// Render the tool's view (simple case — uses result after completion)
    @ViewBuilder var body: Body { get }
}

/// Lifecycle phase for UITool rendering
public enum UIToolPhase: Sendable {
    case loading
    case executing(progress: Double?)
    case complete(result: ToolResult)
    case error(Error)
}

/// Protocol for tools that need full lifecycle control
public protocol LifecycleUITool: UITool {
    associatedtype PhaseView: View

    /// Render based on execution phase
    @ViewBuilder func render(phase: UIToolPhase) -> PhaseView
}
```

Default implementations:
- `UITool.body` default: renders a generic card with tool name and result text
- `LifecycleUITool` gets shimmer placeholder for `.loading`, progress overlay for `.executing`

**Files to create:**
- `Sources/AISDK/Tools/UITool.swift`

**Tests:**
- `Tests/AISDKTests/Tools/UIToolTests.swift` — protocol conformance, phase rendering, default views

#### 2.2 UIToolRenderer

```swift
// Sources/AISDK/GenerativeUI/Views/UIToolRenderer.swift

/// SwiftUI view that manages UITool lifecycle and rendering
@MainActor
struct UIToolRenderer<T: UITool>: View {
    let tool: T
    @State private var phase: UIToolPhase = .loading

    var body: some View {
        // Render current phase, execute tool in .task
    }
}
```

**Files to create:**
- `Sources/AISDK/GenerativeUI/Views/UIToolRenderer.swift`

#### 2.3 Agent Integration

When the Agent executes a tool that conforms to `UITool`, emit a `.toolResult` with metadata indicating the view should be rendered. The consumer can detect UITool results and render the appropriate view.

```swift
// Sources/AISDK/Agents/Agent.swift — in executeNativeToolCall

// After tool execution, check if tool conforms to UITool
// If so, attach rendering metadata to ToolResult
```

**Files to modify:**
- `Sources/AISDK/Agents/Agent.swift` — UITool detection in tool execution path

**Tests:**
- `Tests/AISDKTests/Agents/AgentUIToolTests.swift` — agent executes UITool, metadata attached

---

### Phase 3: Bidirectional State

**Goal:** Interactive components send state changes back to the agent.

#### 3.1 UIStateChangeEvent

```swift
// Sources/AISDK/GenerativeUI/SpecStream/UIStateChangeEvent.swift

/// Event emitted when a user interacts with a generative UI component
public struct UIStateChangeEvent: Sendable {
    /// The component name (from interactive component's `name` prop)
    public let componentName: String
    /// The new value (type-erased)
    public let value: AnyCodable
    /// Timestamp of the change
    public let timestamp: Date
}
```

**Files to create:**
- `Sources/AISDK/GenerativeUI/SpecStream/UIStateChangeEvent.swift`

#### 3.2 UIComponentRegistry State Callbacks

Enhance the registry to propagate state changes from interactive components (Toggle, Slider, Input, etc.) via a new callback:

```swift
// Sources/AISDK/GenerativeUI/Registry/UIComponentRegistry.swift

/// Handler for state changes from interactive components
public typealias UIStateChangeHandler = @Sendable (UIStateChangeEvent) -> Void

// Add to build() method signature
public func build(
    node: UINode,
    tree: UITree,
    propsDecoder: JSONDecoder = Self.defaultPropsDecoder,
    actionHandler: @escaping UIActionHandler,
    stateChangeHandler: @escaping UIStateChangeHandler = { _ in }
) -> AnyView
```

Update interactive component views (GenerativeToggleView, GenerativeSliderView, etc.) to call `stateChangeHandler` when their `@State` values change.

**Files to modify:**
- `Sources/AISDK/GenerativeUI/Registry/UIComponentRegistry.swift` — add state change handler plumbing
- Interactive view implementations in same file — wire `onChange` to handler

**Tests:**
- `Tests/AISDKTests/GenerativeUI/UIComponentRegistryTests.swift` — state change callback invocation

#### 3.3 Agent State Injection

```swift
// Sources/AISDK/Agents/Agent.swift

/// Inject a UI state change into the agent's context
public func injectStateChange(_ event: UIStateChangeEvent) async {
    // Append a system message describing the state change
    // Agent can respond with new patches or text
}
```

**Files to modify:**
- `Sources/AISDK/Agents/Agent.swift` — add state injection method

**Tests:**
- `Tests/AISDKTests/Agents/AgentBidirectionalStateTests.swift`

---

### Phase 4: Polish + Examples

**Goal:** Example apps and documentation.

#### 4.1 Dashboard Example

Demonstrates SpecStream with charts and metrics. Agent streams a dashboard progressively — metrics appear first, then charts fill in, then interactive controls.

#### 4.2 Conversational Form Example

Demonstrates UITool with bidirectional state. Agent renders a multi-step form; user fills in fields; agent validates and responds.

#### 4.3 GenerativeUIView Enhancement

Update `GenerativeUIView` to support the new `UISpec` (with state) and `$path` resolution during rendering.

**Files to modify:**
- `Sources/AISDK/GenerativeUI/Views/GenerativeUIView.swift`

---

## File Structure Summary

### New Files (Phase 1)
```
Sources/AISDK/GenerativeUI/SpecStream/
  SpecPatch.swift                    # RFC 6902 patch model
  SpecStreamCompiler.swift           # JSONL buffer + patch application
  UIState.swift                      # Separated state with $path resolution
  UISpec.swift                       # Combined elements + state spec
  AnyCodable.swift                   # Type-erased Codable for patch values

Tests/AISDKTests/GenerativeUI/
  SpecPatchTests.swift
  SpecStreamCompilerTests.swift
  UIStateTests.swift
```

### New Files (Phase 2)
```
Sources/AISDK/Tools/
  UITool.swift                       # UITool + LifecycleUITool protocols

Sources/AISDK/GenerativeUI/Views/
  UIToolRenderer.swift               # SwiftUI lifecycle view

Tests/AISDKTests/
  Tools/UIToolTests.swift
  Agents/AgentUIToolTests.swift
```

### New Files (Phase 3)
```
Sources/AISDK/GenerativeUI/SpecStream/
  UIStateChangeEvent.swift           # Bidirectional state event

Tests/AISDKTests/
  Agents/AgentBidirectionalStateTests.swift
```

### Modified Files
```
Sources/AISDK/Core/Models/AIStreamEvent.swift           # Add .uiPatch case
Sources/AISDK/GenerativeUI/ViewModels/GenerativeUIViewModel.swift  # Mixed stream subscription
Sources/AISDK/GenerativeUI/Registry/UIComponentRegistry.swift      # State change callbacks
Sources/AISDK/GenerativeUI/Views/GenerativeUIView.swift            # UISpec + $path support
Sources/AISDK/Agents/Agent.swift                                    # UITool detection + state injection
Tests/AISDKTests/Helpers/StreamSimulation.swift                     # UI stream factories
```

---

## Acceptance Criteria

### Phase 1: SpecStream + Agent Bridge
- [x] `SpecPatch` correctly encodes/decodes all 6 RFC 6902 operations
- [x] `SpecStreamCompiler` handles partial JSONL chunks across boundaries
- [x] Malformed JSONL lines are logged and skipped (no halt)
- [x] `.uiPatch(SpecPatchBatch)` event integrates with existing AIStreamEvent enum
- [x] `GenerativeUIViewModel` subscribes to mixed `AIStreamEvent` streams
- [x] Text deltas and UI patches are correctly routed
- [x] 60fps batching continues to work with patch-based updates
- [x] `UIState` resolves `$path` expressions against nested state dictionaries
- [x] `$cond` conditional expressions evaluate correctly
- [x] Path validation prevents patches targeting outside `/elements`, `/state`, `/root`
- [x] `swift build` passes, `swift test` passes

### Phase 2: UITool Protocol
- [x] Simple `UITool` conformance works with just `body` property
- [x] `LifecycleUITool` renders correct view for each phase
- [x] `UIToolRenderer` manages lifecycle (loading -> executing -> complete/error)
- [x] Agent detects `UITool` conformance and attaches rendering metadata
- [x] Default views provide reasonable UX without customization
- [x] Existing `RenderableTool` continues to work (backward compatible)

### Phase 3: Bidirectional State
- [x] Interactive components emit `UIStateChangeEvent` on value change
- [x] State changes propagate through `UIStateChangeHandler` callback
- [x] Agent receives state changes and can respond with new patches
- [x] State change events include component name, value, and timestamp
- [x] Action allowlisting still works alongside state changes

### Phase 4: Polish
- [ ] Dashboard example demonstrates progressive SpecStream rendering
- [ ] Form example demonstrates UITool with bidirectional state
- [x] `GenerativeUIView` renders `UISpec` with `$path` resolution

---

## SpecFlow Analysis: Critical Gaps & Resolutions

The following gaps were identified through flow analysis and must be addressed during implementation.

### Resolved Gaps

**Gap: Tier 1 text-vs-patch demarcation (Critical)**
The brainstorm says "no content-level parsing" but Tier 1 models produce JSONL patches as raw text. Resolution: **Tier 1 uses structured output channels** (tool calls or JSON mode), not raw text interleaving. The model is instructed via system prompt to call a `render_ui` tool with JSONL patch content. The agent loop detects this tool call and emits `.uiPatch` events. No text content parsing needed — the demarcation happens at the tool call boundary. For Tier 2, `streamObject` maps naturally. For Tier 3, UITool handles it.

**Gap: UITree immutability vs incremental patches**
`UITree` has `let nodes: [String: UINode]`. Resolution: **SpecStreamCompiler maintains a mutable internal working copy** (a `[String: UINode]` dictionary). It accumulates patches within a 16ms frame window, then produces a new immutable `UITree` snapshot per frame tick. The existing 60fps batching in GenerativeUIViewModel handles the rest. No changes to UITree's public API.

**Gap: RenderableTool vs UITool coexistence**
`RenderableTool` already exists at `Parameter.swift:294`. Resolution: **UITool supersedes RenderableTool**. Mark `RenderableTool` as `@available(*, deprecated, message: "Use UITool instead")`. Add a bridge extension so existing `RenderableTool` conformances continue to work by wrapping `render(from:)` as a `UITool` with `.complete` phase only.

**Gap: $path security — injected data exfiltration**
If a developer injects `state["apiKey"] = token`, the LLM could generate `{ "$path": "/apiKey" }`. Resolution: **Namespace isolation**. Developer-injected data goes into `/app/*` namespace. LLM-generated `$path` expressions are restricted to `/state/*` namespace only. The `UIState.resolve(path:)` method enforces this prefix check. Paths targeting `/app/*` from LLM-generated specs are rejected and logged.

**Gap: Mixed text+UI subscriber API**
The brainstorm says `GenerativeUIViewModel.subscribe(to: AsyncThrowingStream<AIStreamEvent>)` but doesn't define where text accumulates. Resolution: **The subscribe method takes an `onText` callback**. Text goes to the caller's text renderer; UI patches go to the ViewModel's tree. This keeps the ViewModel focused on UI and lets the consumer decide how to render text (markdown, attributed string, etc.).

### Deferred Gaps (Address in Phase 3)

**Bidirectional state race conditions** — When a user's state change and an agent's patch race, use **last-write-wins with 500ms debounce** on outgoing state changes. The agent's patches take priority once they arrive. Immediate local UI update for responsiveness. Design doc needed before Phase 3 implementation.

**State change throttling** — Continuous controls (sliders, text inputs) debounce at 500ms before sending to agent. Immediate local `@State` update for smooth UX. Only the final committed value reaches the agent.

**`$cond` conditional rendering** — Deferred to Phase 3. Phase 1 implements `$path` only. `$cond` semantics: `{ "$cond": "/flag", "then": X, "else": Y }` where the path resolves to a boolean.

### Edge Cases to Handle

| Edge Case | Phase | Handling |
|-----------|-------|----------|
| Malformed JSONL line mid-stream | 1 | Log and skip, continue rendering |
| Stream terminates mid-patch-sequence | 1 | Render last good tree state, set error flag |
| Patch references nonexistent element | 1 | Skip patch, log warning |
| Patch 3 depends on skipped patch 2 | 1 | Skip cascading failures silently — each patch is applied independently |
| `$path` resolves to wrong type | 1 | Log warning, use prop default value |
| Catalog version mismatch | 1 | Unknown types render as `UnknownComponentView`, unknown props ignored |
| UITool throws during execution | 2 | Transition to `.error(error)` phase, render error card |
| State dict exceeds size limit | 3 | Reject patch, log warning (1MB limit) |
| Slider generates hundreds of changes/sec | 3 | 500ms debounce before agent notification |

---

## Dependencies & Risks

### Dependencies
- None external. All work builds on existing AISDK infrastructure.

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| UITree immutability makes incremental patches complex | Medium | Medium | SpecStreamCompiler creates new UITree instances from patched element maps (functional approach) |
| $path resolution performance on deep state trees | Low | Low | JSON Pointer paths are simple string splits; state trees are typically shallow |
| Bidirectional state race conditions | Medium | High | Agent processes state changes sequentially via operation queue (existing pattern) |
| AnyCodable type erasure complexity | Medium | Medium | Keep minimal — only needs JSON-compatible types (String, Number, Bool, Array, Dict, null) |

---

## References

### Internal
- Brainstorm: `docs/brainstorms/2026-02-15-generative-ui-brainstorm.md`
- UITree: `Sources/AISDK/GenerativeUI/Models/UITree.swift`
- UICatalog: `Sources/AISDK/GenerativeUI/Catalog/UICatalog.swift`
- UIComponentRegistry: `Sources/AISDK/GenerativeUI/Registry/UIComponentRegistry.swift`
- GenerativeUIViewModel: `Sources/AISDK/GenerativeUI/ViewModels/GenerativeUIViewModel.swift`
- AIStreamEvent: `Sources/AISDK/Core/Models/AIStreamEvent.swift`
- Tool protocol: `Sources/AISDK/Tools/Tool.swift`
- RenderableTool: `Sources/AISDK/Tools/Parameter.swift:294`
- Agent: `Sources/AISDK/Agents/Agent.swift`
- StreamSimulation: `Tests/AISDKTests/Helpers/StreamSimulation.swift`

### External
- [RFC 6902 JSON Patch](https://datatracker.ietf.org/doc/html/rfc6902)
- [Vercel json-render](https://github.com/vercel-labs/json-render)
- [CopilotKit Generative UI](https://github.com/CopilotKit/generative-ui)
