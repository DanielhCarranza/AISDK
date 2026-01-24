# fn-1.44 Task 5.6: GenerativeUIView

## Description
Implement the main SwiftUI view for rendering LLM-generated UI from UITree data using the json-render pattern.

## Acceptance
- [x] GenerativeUIView renders UITree root node using UIComponentRegistry
- [x] Supports default registry (UIComponentRegistry.default) initialization
- [x] Supports custom registry initialization for extended component sets
- [x] Supports custom JSONDecoder for props decoding
- [x] GenerativeUIView.secure() factory uses secureDefault registry
- [x] Action handler callback receives actions from interactive components
- [x] GenerativeUITreeView handles loading state with ProgressView
- [x] GenerativeUITreeView handles error state with descriptive error display
- [x] GenerativeUITreeView handles empty state gracefully
- [x] Tree takes priority over loading/error states in GenerativeUITreeView
- [x] Loading takes priority over error in GenerativeUITreeView
- [x] Both views implement accessibility with .accessibilityElement(children: .contain)
- [x] Both views are Sendable-compliant for async contexts
- [x] Preview support for SwiftUI previews in DEBUG mode
- [x] All 18 tests pass (swift test --filter GenerativeUIViewTests)

## Done summary
- Implemented GenerativeUIView: main SwiftUI view that renders UITree nodes using UIComponentRegistry
- Implemented GenerativeUITreeView: wrapper view with loading/error/empty state handling
- Added GenerativeUIView.secure() factory using secureDefault registry for production use
- Full accessibility support with .accessibilityElement(children: .contain)
- Preview support for SwiftUI previews in DEBUG mode

**Why:**
- Provides the top-level entry point for rendering LLM-generated UI
- Enables the json-render pattern to work end-to-end with SwiftUI
- Separates concerns: GenerativeUIView for simple use, GenerativeUITreeView for async loading

**Verification:**
- swift build (passed)
- swift test --filter GenerativeUIViewTests (18 tests pass)
- swift test --filter UIComponentRegistryTests (29 tests pass)

**Follow-ups:**
- GenerativeUIViewModel (fn-1.45) will add reactive streaming updates
## Evidence
- Commits: d7e5d02c1e44f8ad663564fd7106a58246fb8c23
- Tests: swift test --filter GenerativeUIViewTests (18 tests pass)
- PRs: