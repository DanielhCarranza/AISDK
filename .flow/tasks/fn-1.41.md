# fn-1.41 Task 5.3: UITree Model

## Description
Implement the UITree model for the json-render pattern used in generative UI. The model represents a tree of UI components parsed from JSON, with validation against a UICatalog.

## Acceptance
- [x] UINode struct representing individual tree nodes with key, type, propsData, childKeys
- [x] UITreeError enum for comprehensive error handling
- [x] UITree struct with parsing from JSON data and string
- [x] Structural validation (valid keys, no cycles, children correctness)
- [x] Component type validation against UICatalog
- [x] Props validation for each component
- [x] Tree traversal utilities (children, traverse, allNodes, nodeCount, maxDepth)
- [x] All tests passing (27 tests)

## Done summary
Implemented UITree model in `Sources/AISDK/GenerativeUI/Models/UITree.swift`:
- `UINode`: Sendable struct with key, type, propsData (raw JSON), and childKeys
- `UITreeError`: Comprehensive error enum covering structural issues (invalidStructure, rootNotFound, childNotFound, circularReference, duplicateKey, invalidNodeKey) and validation issues (unknownComponentType, childrenNotAllowed, validationFailed)
- `UITree`: Main model with static `parse(from:validatingWith:)` methods that:
  - Parse JSON in json-render format (`root`, `elements`)
  - Validate structural integrity (keys, cycles via DFS)
  - Optionally validate against a UICatalog
- Tree utilities: `rootNode`, `children(of:)`, `node(forKey:)`, `traverse(_:)`, `allNodes()`, `nodeCount`, `maxDepth`

Tests in `Tests/AISDKTests/GenerativeUI/UITreeTests.swift` covering:
- Basic parsing (simple, with children, nested, empty props)
- Catalog validation (type checking, children allowed, props validation)
- Structural errors (missing root/elements, root not found, child not found, circular reference, invalid keys)
- Traversal utilities
- Complex form validation

## Evidence
- Commits: See git log
- Tests: UITreeTests (27 tests passing)
- PRs: N/A
