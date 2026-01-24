//
//  UITreeTests.swift
//  AISDKTests
//
//  Tests for UITree model
//

import XCTest
@testable import AISDK

final class UITreeTests: XCTestCase {

    // MARK: - Basic Parsing Tests

    func testParseSimpleTree() throws {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Text",
                    "props": { "content": "Hello, World!" }
                }
            }
        }
        """

        let tree = try UITree.parse(from: json)

        XCTAssertEqual(tree.rootKey, "main")
        XCTAssertEqual(tree.nodeCount, 1)
        XCTAssertEqual(tree.rootNode.type, "Text")
        XCTAssertTrue(tree.rootNode.childKeys.isEmpty)
    }

    func testParseTreeWithChildren() throws {
        let json = """
        {
            "root": "stack",
            "elements": {
                "stack": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["title", "button"]
                },
                "title": {
                    "type": "Text",
                    "props": { "content": "Welcome" }
                },
                "button": {
                    "type": "Button",
                    "props": { "title": "Click", "action": "submit" }
                }
            }
        }
        """

        let tree = try UITree.parse(from: json)

        XCTAssertEqual(tree.rootKey, "stack")
        XCTAssertEqual(tree.nodeCount, 3)
        XCTAssertEqual(tree.rootNode.childKeys, ["title", "button"])

        let children = tree.children(of: tree.rootNode)
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(children[0].type, "Text")
        XCTAssertEqual(children[1].type, "Button")
    }

    func testParseNestedTree() throws {
        let json = """
        {
            "root": "card",
            "elements": {
                "card": {
                    "type": "Card",
                    "props": { "title": "Form" },
                    "children": ["form-stack"]
                },
                "form-stack": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["input", "submit"]
                },
                "input": {
                    "type": "Input",
                    "props": { "label": "Name", "name": "name" }
                },
                "submit": {
                    "type": "Button",
                    "props": { "title": "Submit", "action": "submit" }
                }
            }
        }
        """

        let tree = try UITree.parse(from: json)

        XCTAssertEqual(tree.nodeCount, 4)
        XCTAssertEqual(tree.maxDepth, 2)

        let allNodes = tree.allNodes()
        XCTAssertEqual(allNodes.count, 4)
        XCTAssertEqual(allNodes[0].key, "card")
        XCTAssertEqual(allNodes[1].key, "form-stack")
        XCTAssertEqual(allNodes[2].key, "input")
        XCTAssertEqual(allNodes[3].key, "submit")
    }

    func testParseEmptyProps() throws {
        let json = """
        {
            "root": "spacer",
            "elements": {
                "spacer": {
                    "type": "Spacer"
                }
            }
        }
        """

        let tree = try UITree.parse(from: json)
        XCTAssertEqual(tree.rootNode.type, "Spacer")

        // Props should be empty JSON object
        let propsString = String(data: tree.rootNode.propsData, encoding: .utf8)
        XCTAssertEqual(propsString, "{}")
    }

    // MARK: - Validation with Catalog Tests

    func testParseWithCatalogValidation() throws {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Text",
                    "props": { "content": "Hello" }
                }
            }
        }
        """

        let catalog = UICatalog.core8
        let tree = try UITree.parse(from: json, validatingWith: catalog)

        XCTAssertEqual(tree.nodeCount, 1)
    }

    func testParseWithCatalogUnknownTypeThrows() {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "CustomWidget",
                    "props": {}
                }
            }
        }
        """

        let catalog = UICatalog.core8

        XCTAssertThrowsError(try UITree.parse(from: json, validatingWith: catalog)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .unknownComponentType(let key, let type) = treeError {
                XCTAssertEqual(key, "main")
                XCTAssertEqual(type, "CustomWidget")
            } else {
                XCTFail("Expected unknownComponentType error, got \(treeError)")
            }
        }
    }

    func testParseWithCatalogChildrenNotAllowedThrows() {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Text",
                    "props": { "content": "Hello" },
                    "children": ["child"]
                },
                "child": {
                    "type": "Text",
                    "props": { "content": "World" }
                }
            }
        }
        """

        let catalog = UICatalog.core8

        XCTAssertThrowsError(try UITree.parse(from: json, validatingWith: catalog)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .childrenNotAllowed(let key, let type) = treeError {
                XCTAssertEqual(key, "main")
                XCTAssertEqual(type, "Text")
            } else {
                XCTFail("Expected childrenNotAllowed error, got \(treeError)")
            }
        }
    }

    func testParseWithCatalogEmptyChildrenArrayOnLeafThrows() {
        // Even an empty children array should be rejected for leaf components
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Text",
                    "props": { "content": "Hello" },
                    "children": []
                }
            }
        }
        """

        let catalog = UICatalog.core8

        XCTAssertThrowsError(try UITree.parse(from: json, validatingWith: catalog)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .childrenNotAllowed(let key, let type) = treeError {
                XCTAssertEqual(key, "main")
                XCTAssertEqual(type, "Text")
            } else {
                XCTFail("Expected childrenNotAllowed error, got \(treeError)")
            }
        }
    }

    func testParseWithCatalogPropsValidation() {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Text",
                    "props": { "content": "" }
                }
            }
        }
        """

        let catalog = UICatalog.core8

        XCTAssertThrowsError(try UITree.parse(from: json, validatingWith: catalog)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .validationFailed(let key, _) = treeError {
                XCTAssertEqual(key, "main")
            } else {
                XCTFail("Expected validationFailed error, got \(treeError)")
            }
        }
    }

    // MARK: - Structural Error Tests

    func testParseMissingRootThrows() {
        let json = """
        {
            "elements": {
                "main": {
                    "type": "Text",
                    "props": { "content": "Hello" }
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .invalidStructure(let reason) = treeError {
                XCTAssertTrue(reason.contains("root"))
            } else {
                XCTFail("Expected invalidStructure error, got \(treeError)")
            }
        }
    }

    func testParseMissingElementsThrows() {
        let json = """
        {
            "root": "main"
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .invalidStructure(let reason) = treeError {
                XCTAssertTrue(reason.contains("elements"))
            } else {
                XCTFail("Expected invalidStructure error, got \(treeError)")
            }
        }
    }

    func testParseRootNotFoundThrows() {
        let json = """
        {
            "root": "nonexistent",
            "elements": {
                "main": {
                    "type": "Text",
                    "props": { "content": "Hello" }
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .rootNotFound(let key) = treeError {
                XCTAssertEqual(key, "nonexistent")
            } else {
                XCTFail("Expected rootNotFound error, got \(treeError)")
            }
        }
    }

    func testParseChildNotFoundThrows() {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["missing"]
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .childNotFound(let parentKey, let childKey) = treeError {
                XCTAssertEqual(parentKey, "main")
                XCTAssertEqual(childKey, "missing")
            } else {
                XCTFail("Expected childNotFound error, got \(treeError)")
            }
        }
    }

    func testParseCircularReferenceThrows() {
        let json = """
        {
            "root": "a",
            "elements": {
                "a": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["b"]
                },
                "b": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["a"]
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .circularReference(_) = treeError {
                // Expected
            } else {
                XCTFail("Expected circularReference error, got \(treeError)")
            }
        }
    }

    func testParseSelfReferenceThrows() {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["main"]
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .circularReference(let key) = treeError {
                XCTAssertEqual(key, "main")
            } else {
                XCTFail("Expected circularReference error, got \(treeError)")
            }
        }
    }

    func testParseEmptyKeyThrows() {
        let json = """
        {
            "root": "",
            "elements": {
                "": {
                    "type": "Text",
                    "props": { "content": "Hello" }
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .invalidNodeKey(_) = treeError {
                // Expected
            } else {
                XCTFail("Expected invalidNodeKey error, got \(treeError)")
            }
        }
    }

    func testParseWhitespaceKeyThrows() {
        let json = """
        {
            "root": "   ",
            "elements": {
                "   ": {
                    "type": "Text",
                    "props": { "content": "Hello" }
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .invalidNodeKey(_) = treeError {
                // Expected
            } else {
                XCTFail("Expected invalidNodeKey error, got \(treeError)")
            }
        }
    }

    func testParseMissingTypeThrows() {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "props": { "content": "Hello" }
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .invalidStructure(let reason) = treeError {
                XCTAssertTrue(reason.contains("type"))
            } else {
                XCTFail("Expected invalidStructure error, got \(treeError)")
            }
        }
    }

    func testParseInvalidChildrenTypeThrows() {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": "not-an-array"
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .invalidStructure(let reason) = treeError {
                XCTAssertTrue(reason.contains("children"))
            } else {
                XCTFail("Expected invalidStructure error, got \(treeError)")
            }
        }
    }

    func testParseInvalidJSONThrows() {
        let json = "{ not valid json }"

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .invalidStructure(_) = treeError {
                // Expected
            } else {
                XCTFail("Expected invalidStructure error, got \(treeError)")
            }
        }
    }

    func testParseInvalidPropsTypeThrows() {
        // Props must be an object, not an array or string
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Text",
                    "props": ["content", "Hello"]
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .invalidStructure(let reason) = treeError {
                XCTAssertTrue(reason.contains("props"))
            } else {
                XCTFail("Expected invalidStructure error, got \(treeError)")
            }
        }
    }

    func testParsePropsAsStringThrows() {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Text",
                    "props": "not an object"
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .invalidStructure(let reason) = treeError {
                XCTAssertTrue(reason.contains("props"))
            } else {
                XCTFail("Expected invalidStructure error, got \(treeError)")
            }
        }
    }

    // MARK: - Traversal Tests

    func testTraverse() throws {
        let json = """
        {
            "root": "a",
            "elements": {
                "a": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["b", "c"]
                },
                "b": {
                    "type": "Text",
                    "props": { "content": "B" }
                },
                "c": {
                    "type": "Stack",
                    "props": { "direction": "horizontal" },
                    "children": ["d"]
                },
                "d": {
                    "type": "Text",
                    "props": { "content": "D" }
                }
            }
        }
        """

        let tree = try UITree.parse(from: json)

        var visitedKeys: [String] = []
        var visitedDepths: [Int] = []
        tree.traverse { node, depth in
            visitedKeys.append(node.key)
            visitedDepths.append(depth)
        }

        XCTAssertEqual(visitedKeys.count, 4)
        XCTAssertEqual(visitedKeys[0], "a")
        XCTAssertEqual(visitedDepths[0], 0)
        XCTAssertEqual(visitedKeys[1], "b")
        XCTAssertEqual(visitedDepths[1], 1)
        XCTAssertEqual(visitedKeys[2], "c")
        XCTAssertEqual(visitedDepths[2], 1)
        XCTAssertEqual(visitedKeys[3], "d")
        XCTAssertEqual(visitedDepths[3], 2)
    }

    func testNodeForKey() throws {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["child"]
                },
                "child": {
                    "type": "Text",
                    "props": { "content": "Hello" }
                }
            }
        }
        """

        let tree = try UITree.parse(from: json)

        let mainNode = tree.node(forKey: "main")
        XCTAssertNotNil(mainNode)
        XCTAssertEqual(mainNode?.type, "Stack")

        let childNode = tree.node(forKey: "child")
        XCTAssertNotNil(childNode)
        XCTAssertEqual(childNode?.type, "Text")

        let missingNode = tree.node(forKey: "missing")
        XCTAssertNil(missingNode)
    }

    func testMaxDepth() throws {
        // Depth 0 (single node)
        let json1 = """
        {
            "root": "main",
            "elements": {
                "main": { "type": "Text", "props": { "content": "Hello" } }
            }
        }
        """
        let tree1 = try UITree.parse(from: json1)
        XCTAssertEqual(tree1.maxDepth, 0)

        // Depth 2
        let json2 = """
        {
            "root": "a",
            "elements": {
                "a": { "type": "Stack", "props": { "direction": "vertical" }, "children": ["b"] },
                "b": { "type": "Stack", "props": { "direction": "vertical" }, "children": ["c"] },
                "c": { "type": "Text", "props": { "content": "Deep" } }
            }
        }
        """
        let tree2 = try UITree.parse(from: json2)
        XCTAssertEqual(tree2.maxDepth, 2)
    }

    // MARK: - UINode Tests

    func testUINodeEquality() {
        let node1 = UINode(
            key: "test",
            type: "Text",
            propsData: Data("{}".utf8),
            childKeys: []
        )
        let node2 = UINode(
            key: "test",
            type: "Text",
            propsData: Data("{}".utf8),
            childKeys: []
        )
        let node3 = UINode(
            key: "other",
            type: "Text",
            propsData: Data("{}".utf8),
            childKeys: []
        )

        XCTAssertEqual(node1, node2)
        XCTAssertNotEqual(node1, node3)
    }

    // MARK: - Error Description Tests

    func testErrorDescriptions() {
        let invalidStructure = UITreeError.invalidStructure(reason: "test reason")
        XCTAssertTrue(invalidStructure.errorDescription?.contains("test reason") ?? false)

        let rootNotFound = UITreeError.rootNotFound(key: "missing")
        XCTAssertTrue(rootNotFound.errorDescription?.contains("missing") ?? false)

        let childNotFound = UITreeError.childNotFound(parentKey: "parent", childKey: "child")
        XCTAssertTrue(childNotFound.errorDescription?.contains("parent") ?? false)
        XCTAssertTrue(childNotFound.errorDescription?.contains("child") ?? false)

        let circularRef = UITreeError.circularReference(key: "loop")
        XCTAssertTrue(circularRef.errorDescription?.contains("loop") ?? false)

        let duplicateKey = UITreeError.duplicateKey(key: "dup")
        XCTAssertTrue(duplicateKey.errorDescription?.contains("dup") ?? false)

        let invalidKey = UITreeError.invalidNodeKey(key: "bad")
        XCTAssertTrue(invalidKey.errorDescription?.contains("bad") ?? false)

        let unknownType = UITreeError.unknownComponentType(key: "node", type: "Custom")
        XCTAssertTrue(unknownType.errorDescription?.contains("node") ?? false)
        XCTAssertTrue(unknownType.errorDescription?.contains("Custom") ?? false)

        let childrenNotAllowed = UITreeError.childrenNotAllowed(key: "leaf", type: "Text")
        XCTAssertTrue(childrenNotAllowed.errorDescription?.contains("leaf") ?? false)
        XCTAssertTrue(childrenNotAllowed.errorDescription?.contains("Text") ?? false)

        let validationFailed = UITreeError.validationFailed(
            key: "node",
            error: .invalidPropValue(component: "Text", prop: "content", reason: "empty")
        )
        XCTAssertTrue(validationFailed.errorDescription?.contains("node") ?? false)

        let multipleParents = UITreeError.multipleParents(key: "shared")
        XCTAssertTrue(multipleParents.errorDescription?.contains("shared") ?? false)
        XCTAssertTrue(multipleParents.errorDescription?.contains("multiple parents") ?? false)

        let depthExceeded = UITreeError.depthExceeded(maxAllowed: 100)
        XCTAssertTrue(depthExceeded.errorDescription?.contains("100") ?? false)

        let nodeCountExceeded = UITreeError.nodeCountExceeded(maxAllowed: 10000)
        XCTAssertTrue(nodeCountExceeded.errorDescription?.contains("10000") ?? false)

        let unreachableNode = UITreeError.unreachableNode(key: "orphan")
        XCTAssertTrue(unreachableNode.errorDescription?.contains("orphan") ?? false)
    }

    // MARK: - Data Parsing Tests

    func testParseFromData() throws {
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Text",
                    "props": { "content": "Hello" }
                }
            }
        }
        """
        let data = Data(json.utf8)

        let tree = try UITree.parse(from: data)
        XCTAssertEqual(tree.nodeCount, 1)
    }

    // MARK: - Complex Validation Tests

    func testValidateCompleteFormTree() throws {
        let json = """
        {
            "root": "card",
            "elements": {
                "card": {
                    "type": "Card",
                    "props": { "title": "Login Form", "style": "elevated" },
                    "children": ["form"]
                },
                "form": {
                    "type": "Stack",
                    "props": { "direction": "vertical", "spacing": 16 },
                    "children": ["email-input", "password-input", "submit-button"]
                },
                "email-input": {
                    "type": "Input",
                    "props": {
                        "label": "Email",
                        "name": "email",
                        "type": "email",
                        "validation": "email",
                        "accessibilityLabel": "Email input"
                    }
                },
                "password-input": {
                    "type": "Input",
                    "props": {
                        "label": "Password",
                        "name": "password",
                        "type": "password",
                        "validation": "required"
                    }
                },
                "submit-button": {
                    "type": "Button",
                    "props": {
                        "title": "Sign In",
                        "action": "submit",
                        "style": "primary"
                    }
                }
            }
        }
        """

        let catalog = UICatalog.core8
        let tree = try UITree.parse(from: json, validatingWith: catalog)

        XCTAssertEqual(tree.nodeCount, 5)
        XCTAssertEqual(tree.maxDepth, 2)
    }

    // MARK: - Tree Structure Enforcement Tests

    func testDiamondDependencyThrowsMultipleParents() {
        // A -> B, A -> C, B -> D, C -> D (diamond pattern)
        // This should fail because D has multiple parents (B and C)
        let json = """
        {
            "root": "a",
            "elements": {
                "a": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["b", "c"]
                },
                "b": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["d"]
                },
                "c": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["d"]
                },
                "d": {
                    "type": "Text",
                    "props": { "content": "Shared" }
                }
            }
        }
        """

        XCTAssertThrowsError(try UITree.parse(from: json)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(error)")
                return
            }
            if case .multipleParents(let key) = treeError {
                XCTAssertEqual(key, "d")
            } else {
                XCTFail("Expected multipleParents error, got \(treeError)")
            }
        }
    }

    func testUnreachableNodesArePruned() throws {
        // main -> child, but "orphan" is not connected
        let json = """
        {
            "root": "main",
            "elements": {
                "main": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["child"]
                },
                "child": {
                    "type": "Text",
                    "props": { "content": "Connected" }
                },
                "orphan": {
                    "type": "Text",
                    "props": { "content": "Not connected" }
                }
            }
        }
        """

        let tree = try UITree.parse(from: json)

        // Only reachable nodes should be in the tree
        XCTAssertEqual(tree.nodeCount, 2)
        XCTAssertNotNil(tree.node(forKey: "main"))
        XCTAssertNotNil(tree.node(forKey: "child"))
        XCTAssertNil(tree.node(forKey: "orphan"))
    }

    func testHadChildrenFieldTracking() throws {
        let json = """
        {
            "root": "stack",
            "elements": {
                "stack": {
                    "type": "Stack",
                    "props": { "direction": "vertical" },
                    "children": ["text"]
                },
                "text": {
                    "type": "Text",
                    "props": { "content": "Hello" }
                }
            }
        }
        """

        let tree = try UITree.parse(from: json)

        XCTAssertTrue(tree.node(forKey: "stack")?.hadChildrenField ?? false)
        XCTAssertFalse(tree.node(forKey: "text")?.hadChildrenField ?? true)
    }
}
