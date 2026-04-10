# JSON Render Implementation (AISDK)

This document describes the current json-render implementation in this codebase.
It covers how UI JSON is generated, validated, parsed, and rendered across the
SDK, AIAgents, and the CLI. Reference implementation docs are intentionally
excluded.

## Scope and key files

- `Sources/AISDK/GenerativeUI/Models/UITree.swift`
- `Sources/AISDK/GenerativeUI/Catalog/UICatalog.swift`
- `Sources/AISDK/GenerativeUI/Catalog/Core8Components.swift`
- `Sources/AISDK/GenerativeUI/Registry/UIComponentRegistry.swift`
- `Sources/AISDK/GenerativeUI/Views/GenerativeUIView.swift`
- `Sources/AISDK/GenerativeUI/ViewModels/GenerativeUIViewModel.swift`
- `Examples/AISDKCLI/CLIController.swift`
- `Examples/AISDKCLI/Renderers/TerminalUIRenderer.swift`
- Tests under `Tests/AISDKTests/GenerativeUI/`

## High-level data flow

LLM -> JSON -> UITree.parse(...) -> validation -> rendering

Detailed flow:

1. A catalog prompt is generated from `UICatalog`.
2. An agent (or any LLM call) is instructed to return JSON in json-render format.
3. The response is parsed into a `UITree` and validated against a `UICatalog`.
4. The resulting `UITree` is rendered:
   - SwiftUI: `GenerativeUIView` + `UIComponentRegistry`
   - CLI: `TerminalUIRenderer`

ASCII diagram:

LLM
  | (JSON)
  v
UITree.parse
  | (structure + catalog validation)
  v
UITree
  |                     \
  v                      v
GenerativeUIView     TerminalUIRenderer

## JSON format (json-render pattern as implemented here)

The implementation expects a single JSON object with a root key and a flat
`elements` dictionary. Example:

```json
{
  "root": "main",
  "elements": {
    "main": {
      "type": "Stack",
      "props": { "direction": "vertical", "spacing": 12 },
      "children": ["title", "cta"]
    },
    "title": {
      "type": "Text",
      "props": { "content": "Hello" }
    },
    "cta": {
      "type": "Button",
      "props": { "title": "Continue", "action": "submit" }
    }
  }
}
```

Rules enforced by `UITree.parse` and catalog validation:

- `root` must be a non-empty string and match a key in `elements`.
- Each element key must be unique, non-empty, and trimmed.
- `elements` must be a JSON object mapping keys to element objects.
- Each element must include a `type` string.
- `props`, if present, must be a JSON object. If omitted, it is treated as `{}`.
- `children`, if present, must be an array of strings.
- Tree structure must be a true tree (no cycles, no multiple parents).
- Max depth: 100. Max nodes: 10,000.
- Nodes that are not reachable from `root` are silently pruned.
- If a component does NOT allow children, the `children` field must be omitted
  (even an empty array is invalid).

Note: The implementation uses a single JSON object. There is no JSONL patch
streaming format in the current Swift code.

## Core types and responsibilities

### UINode

Defined in `Sources/AISDK/GenerativeUI/Models/UITree.swift`.

- `key`: unique node id.
- `type`: component type string (example: "Text").
- `propsData`: raw JSON `Data` for props.
- `childKeys`: ordered list of child node keys.
- `hadChildrenField`: tracks whether `children` was present in JSON.

### UITree

Also in `UITree.swift`.

Key behaviors:

- `parse(from:validatingWith:)`:
  - Parses with `JSONSerialization`.
  - Validates structural constraints.
  - Uses iterative DFS for cycle detection, multiple parents, and depth limits.
  - Returns a tree with only reachable nodes from `root`.
  - Optionally validates component types and props via `UICatalog`.

- `validate(with:)`:
  - Ensures component type exists in catalog.
  - Ensures `children` is omitted for leaf-only components.
  - Validates props via `UICatalog` (including action/validator references).

Traversal helpers:

- `children(of:)`, `node(forKey:)`, `traverse`, `allNodes`, `nodeCount`,
  `maxDepth`.

### UICatalog

Defined in `Sources/AISDK/GenerativeUI/Catalog/UICatalog.swift`.

Responsibilities:

- Holds component definitions (`UIComponentDefinition`).
- Holds action definitions (`UIActionDefinition`).
- Holds validator definitions (`UIValidatorDefinition`).
- Generates the LLM system prompt via `generatePrompt()`.
- Validates a component `type` + `propsData` through the registered definition.

Prompt generation:

`generatePrompt()` outputs:

- Per-component descriptions and prop schema.
- Available actions and validators.
- Output format rules (root/elements/children constraints).

### UIComponentDefinition + AnyUIComponentDefinition

Defined in `UICatalog.swift` and implemented for Core 8 in
`Core8Components.swift`.

Key points:

- Each component specifies:
  - `type`, `description`, `hasChildren`, `propsSchemaDescription`.
  - Optional strict prop keys via `allowedPropKeys`.
- `AnyUIComponentDefinition` wraps a concrete component and:
  - Validates unknown keys when `allowedPropKeys` is non-empty.
  - Decodes props with `JSONDecoder` using `convertFromSnakeCase`.
  - Enforces component-specific validation and catalog-aware checks.

### UIComponentRegistry

Defined in `Sources/AISDK/GenerativeUI/Registry/UIComponentRegistry.swift`.

Responsibilities:

- Runtime mapping from component `type` -> SwiftUI view builder.
- Action allowlist for security:
  - Empty allowlist means pass-through (all actions allowed).
  - `secureDefault` allows only `submit`, `navigate`, `dismiss`.
- Default registry includes Core 8 components.
- Unknown component types render as a fallback `UnknownComponentView`.

Props decoding:

- Uses `JSONDecoder` with `convertFromSnakeCase` by default.
- `GenerativeUIView` exposes `PropsDecoderConfiguration` to override strategy.

### GenerativeUIView and GenerativeUITreeView

Defined in `Sources/AISDK/GenerativeUI/Views/GenerativeUIView.swift`.

- `GenerativeUIView` renders a `UITree` via a `UIComponentRegistry`.
- `GenerativeUIView.secure(...)` uses `UIComponentRegistry.secureDefault`.
- `GenerativeUITreeView` wraps loading and error states for async UI loading.

### GenerativeUIViewModel

Defined in `Sources/AISDK/GenerativeUI/ViewModels/GenerativeUIViewModel.swift`.

- `@Observable` and `@MainActor` for SwiftUI state updates.
- `loadTree(from:catalog:)` parses JSON off-main-thread and sets state.
- Update batching throttles to ~60fps via a 16ms timer.
- Streaming support consumes `AsyncStream<UITree>` or
  `AsyncThrowingStream<UITree, Error>`.
- No built-in JSONL patch parsing. Streams must emit full `UITree` objects.

## Core 8 components (catalog + renderer behavior)

Defined in `Sources/AISDK/GenerativeUI/Catalog/Core8Components.swift` and
rendered in `UIComponentRegistry` / `TerminalUIRenderer`.

- Text
  - Required: `content`
  - Optional: `style` (body/headline/subheadline/caption/title)
- Button
  - Required: `title`, `action`
  - Optional: `style` (primary/secondary/destructive/plain), `disabled`
  - `action` must match a catalog action
- Card
  - Optional: `title`, `subtitle`, `style` (elevated/outlined/filled)
- Input
  - Required: `label`, `name`
  - Optional: `placeholder`, `type` (text/email/password/number),
    `required`, `validation`
  - `validation` must match a catalog validator if present
- List
  - Optional: `style` (ordered/unordered/plain)
- Image
  - Required: `url`
  - Optional: `alt`, `width`, `height`, `contentMode` (fit/fill/stretch)
- Stack
  - Required: `direction` (horizontal/vertical)
  - Optional: `spacing`, `alignment` (leading/center/trailing)
- Spacer
  - Optional: `size`

Accessibility fields are supported across components via
`accessibilityLabel`, `accessibilityHint`, `accessibilityTraits`.

## Rendering layers

### SwiftUI (SDK)

Flow:

- `GenerativeUIView` -> `UIComponentRegistry.build(...)` -> SwiftUI view
- `UIComponentRegistry` handles:
  - props decoding
  - action allowlist filtering
  - child rendering through `ChildViewBuilder`

Notes:

- `GenerativeUIView` defaults to `UIComponentRegistry.default` (pass-through
  actions). Use `.secure` or `UIComponentRegistry.secureDefault` for safety.
- Unknown types are rendered as a text placeholder view.

### CLI (AISDKCLI)

Flow in `Examples/AISDKCLI/CLIController.swift`:

1. `buildSystemPrompt()` appends `UICatalog.core8.generatePrompt()` and
   strict instructions to return JSON only.
2. `buildResponseFormat()` sets `.jsonObject` when `--format ui` is used.
3. The response is post-processed by `extractJSONPayload` (strips fences).
4. The JSON is parsed using `UITree.parse(..., validatingWith: .core8)`.
5. `TerminalUIRenderer` renders the tree to ANSI styled text.

`TerminalUIRenderer` specifics:

- Decodes props with a default `JSONDecoder` (no snake_case conversion).
- Only supports the Core 8 component set.
- Unknown types render as a warning text line.

## AIAgents integration

There is no dedicated json-render mode inside `Agent` or `Agent`.
Integration is done by:

1. Including `UICatalog.generatePrompt()` in the system message.
2. Setting `Agent.RequestOptions.responseFormat = .jsonObject`
   (or equivalent in a provider request) to bias the model toward JSON.
3. Parsing the resulting text into a `UITree` using `UITree.parse(...)`.
4. Rendering via `GenerativeUIView` or a custom renderer.

Example flow:

```swift
let catalog = UICatalog.core8
let agent = Agent(
    model: myModel,
    instructions: catalog.generatePrompt(),
    requestOptions: .init(responseFormat: .jsonObject)
)

let result = try await agent.execute(messages: [.user("Build a settings form")])
let tree = try UITree.parse(from: result.text, validatingWith: catalog)
```

Streaming note:

- `Agent.streamExecute` streams text deltas, not `UITree` objects.
- To get incremental UI updates, you must accumulate JSON yourself and emit
  `UITree` values to `GenerativeUIViewModel.scheduleUpdate` or
  `GenerativeUIViewModel.subscribe`.
- No JSONL patch application exists in the current Swift code.

## Validation details and security

- `UICatalog` validation checks:
  - component exists
  - props schema and required fields
  - action references (Button)
  - validator references (Input)

- `UIComponentRegistry` action allowlist:
  - empty allowlist = pass-through
  - `secureDefault` allows only: submit, navigate, dismiss

- `UITree` enforces:
  - a true tree (no DAG, no cycles)
  - node count and depth limits
  - invalid `children` on leaf-only components

## Tests

Relevant tests in `Tests/AISDKTests/GenerativeUI/`:

- `UICatalogTests.swift`
- `UITreeTests.swift`
- `GenerativeUIViewModelTests.swift`
- `UISnapshotTests.swift`

These cover parsing, validation, update batching, and core component props.

## Extension points

### Add custom components

1. Create a `UIComponentDefinition` with props and validation.
2. Register it in a `UICatalog` for prompt + validation.
3. Register a SwiftUI view builder in `UIComponentRegistry` for rendering.

### Add new actions or validators

1. Register via `UICatalog.registerAction(...)` or
   `UICatalog.registerValidator(...)`.
2. Update UI component validation (if needed).
3. Add handler logic in your app for the action names.

## Known gaps and constraints

- No JSONL patch streaming or partial tree patching.
- Input fields are rendered but not bound to a form state or submit pipeline.
- Action handling is string-based; the SDK does not define action payloads.
- CLI decoding uses default `JSONDecoder`, so snake_case props may fail in CLI
  even though SwiftUI decoding accepts them.
- Validation is opt-in: you must pass a catalog to `UITree.parse` to enforce
  component and prop validation.
- `UITreeError.unreachableNode` exists but is not thrown in the current parser.

## Quick usage checklist

- Use `UICatalog.core8.generatePrompt()` in system instructions.
- Set response format to JSON (`.jsonObject`).
- Parse with `UITree.parse(..., validatingWith: catalog)`.
- Render with `GenerativeUIView.secure` (SwiftUI) or `TerminalUIRenderer` (CLI).
- Handle actions via the `UIActionHandler` callback and allowlist.
