# fn-1.46 Task 6.1: Integration Test Suite

## Description
Integration test suite for GenerativeUI pipeline testing UITree parsing, UIComponentRegistry, and GenerativeUIViewModel state management.

## Acceptance
- [x] End-to-end tree parsing tests (nested structures, Core 8 components)
- [x] Action security allowlist tests (blocking, whitespace normalization, custom lists)
- [x] ViewModel integration tests (load, stream, update batching, cancellation)
- [x] Catalog validation tests (valid types, unknown type rejection)
- [x] Error handling tests (unknown components, malformed props)
- [x] Performance tests (measure parsing of 101-node tree, ~2ms average)
- [x] Sendable compliance tests (registry, tree)
- [x] Factory method tests (loading, streaming)
- [x] UITreeUpdate type tests

## Done summary
Implemented GenerativeUIIntegrationTests with 25 tests covering:
- Tree parsing and structure verification for simple and complex trees
- Action allowlist security (blocks unauthorized, whitespace normalization, custom configs)
- ViewModel lifecycle (load, setTree, clear, subscribe, scheduleUpdate, cancel)
- Catalog validation (accepts Core 8, rejects unknown types with specific error)
- Error handling (unknown components, malformed props gracefully parse)
- Measured performance test (~2ms for 101-node tree)
- Sendable compliance for UIComponentRegistry and UITree

Note: Tests follow existing codebase patterns. SwiftUI rendering tests would require UIHostingController which is not used elsewhere in this test suite.

## Evidence
- Commits:
- Tests:
- PRs:
