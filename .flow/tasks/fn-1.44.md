# fn-1.44 Task 5.6: GenerativeUIView

## Description
Implement the main SwiftUI view for rendering LLM-generated UI from UITree data using the json-render pattern.

## Acceptance
- [x] GenerativeUIView renders UITree root node using UIComponentRegistry
- [x] Supports default registry (UIComponentRegistry.default) initialization
- [x] Supports custom registry initialization for extended component sets
- [x] PropsDecoderConfiguration replaces JSONDecoder for Sendable compliance
- [x] GenerativeUIView.secure() factory uses secureDefault registry
- [x] Default init documented with security warning about pass-through mode
- [x] Action handler callback receives actions from interactive components
- [x] GenerativeUITreeView handles loading state with ProgressView
- [x] GenerativeUITreeView handles error state (DEBUG-only details to avoid leaks)
- [x] GenerativeUITreeView handles empty state gracefully
- [x] Tree takes priority over loading/error states in GenerativeUITreeView
- [x] Loading takes priority over error in GenerativeUITreeView
- [x] Both views implement accessibility with .accessibilityElement(children: .contain)
- [x] Both views declare Sendable conformance with compile-time verification
- [x] Preview support for SwiftUI previews in DEBUG mode
- [x] All 22 tests pass (swift test --filter GenerativeUIViewTests)

## Done summary
- Implemented GenerativeUIView: main SwiftUI view that renders UITree nodes using UIComponentRegistry
- Implemented GenerativeUITreeView: wrapper view with loading/error/empty state handling
- Added GenerativeUIView.secure() factory using secureDefault registry for production use
- Added PropsDecoderConfiguration for Sendable-safe decoder configuration
- Error details shown only in DEBUG mode to prevent internal info leakage
- Full accessibility support with .accessibilityElement(children: .contain) on both views

**Codex Review Fixes:**
- Added .accessibilityElement(children: .contain) to GenerativeUITreeView root
- Replaced JSONDecoder with PropsDecoderConfiguration for Sendable compliance
- Added @Sendable closure verification in tests
- Updated doc comments to clarify security implications of default init
- Error details gated behind #if DEBUG to prevent info leakage

**Verification:**
- swift build (passed)
- swift test --filter GenerativeUIViewTests (22 tests pass)
## Evidence
- Commits: d7e5d02c1e44f8ad663564fd7106a58246fb8c23, 0b3a866f3bf537c1b3c189f9c2270d771b7fc9c3
- Tests: swift test --filter GenerativeUIViewTests (22 tests pass)
- PRs: