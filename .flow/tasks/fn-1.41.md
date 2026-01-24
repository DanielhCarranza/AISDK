# fn-1.41 Task 5.3: UITree Model

## Description
Implement the UITree model for the json-render pattern used in generative UI. The model represents a tree of UI components parsed from JSON, with validation against a UICatalog.

## Acceptance
- [x] UINode struct representing individual tree nodes with key, type, propsData, childKeys
- [x] UITreeError enum for comprehensive error handling (13 error cases)
- [x] UITree struct with parsing from JSON data and string
- [x] Structural validation (valid keys, no cycles, true tree enforcement)
- [x] Security limits (max depth 100, max nodes 10,000)
- [x] Iterative traversal to prevent stack overflow
- [x] Component type validation against UICatalog
- [x] Props validation for each component
- [x] Tree traversal utilities (children, traverse, allNodes, nodeCount, maxDepth)
- [x] All tests passing (32 tests)

## Done summary
Implemented UITree model in `Sources/AISDK/GenerativeUI/Models/UITree.swift`:
- `UINode`: Sendable/Equatable struct with key, type, propsData (raw JSON), childKeys, and hadChildrenField
- `UITreeError`: Comprehensive error enum with 13 cases covering structural issues (invalidStructure, rootNotFound, childNotFound, circularReference, duplicateKey, invalidNodeKey, multipleParents, depthExceeded, nodeCountExceeded, unreachableNode) and validation issues (unknownComponentType, childrenNotAllowed, validationFailed)
- `UITree`: Main model with static `parse(from:validatingWith:)` methods that parse JSON in json-render format with:
  - Iterative DFS traversal (prevents stack overflow on deep/malicious input)
  - True tree enforcement (no DAGs - rejects diamond dependencies)
  - Security limits (max depth 100, max nodes 10,000)
  - Strict props validation (must be object if present)
  - Unreachable node pruning
  - Deterministic validation order (depth-first from root)
- Tree utilities: rootNode, children(of:), node(forKey:), traverse(_:), allNodes(), nodeCount, maxDepth

Tests: 32 tests in UITreeTests.swift covering basic parsing, catalog validation, structural errors, tree enforcement, and traversal utilities.

## Evidence
- Commits: b96a11b + subsequent impl-review fixes
- Tests: {'command': 'swift test --filter UITreeTests', 'result': '32 tests passed'}
- PRs: