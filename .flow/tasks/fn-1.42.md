# fn-1.42 Task 5.4: UIComponentRegistry

## Description
Implement `UIComponentRegistry` - a registry mapping element types to SwiftUI views with action allowlisting for security. This provides the runtime mapping between component type names (from `UITree` nodes) and their SwiftUI view implementations.

Key features:
- Type-erased view builders for custom component registration
- Action allowlisting to prevent LLM-generated UI from triggering unauthorized actions
- Default registry pre-populated with Core 8 SwiftUI views
- Sendable conformance for concurrency safety

## Acceptance
- [x] `UIComponentRegistry` struct with `Sendable` conformance
- [x] `register(_:builder:)` method for custom component registration
- [x] `allowAction(_:)` and `allowActions(_:)` for security configuration
- [x] `disallowAction(_:)` and `clearAllowedActions()` for allowlist management
- [x] `build(node:tree:actionHandler:)` method that wraps handlers with security checks
- [x] `buildChildren(of:tree:actionHandler:)` helper for container components
- [x] `hasComponent(_:)` and `registeredTypes` for introspection
- [x] Default registry with all Core 8 component views (Text, Button, Card, Input, List, Image, Stack, Spacer)
- [x] `defaultPropsDecoder` with snake_case conversion
- [x] Unknown component type handling (graceful fallback view)
- [x] Tests for registration, allowlisting, security blocking, and integration

## Done summary
Implemented `UIComponentRegistry` in `Sources/AISDK/GenerativeUI/Registry/UIComponentRegistry.swift` with:
- Full action allowlisting security (empty = pass-through, non-empty = strict)
- Default registry with 8 Core SwiftUI views pre-registered
- Type-erased view builders for flexibility
- Sendable conformance throughout
- Comprehensive test suite with 23 passing tests

## Evidence
- Commits: (pending)
- Tests: UIComponentRegistryTests (23 tests, all passing)
- PRs: (pending)
