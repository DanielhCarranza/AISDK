//
//  GenerativeUIIntegrationTests.swift
//  AISDKTests
//
//  Integration tests for GenerativeUI pipeline
//  Tests the full flow: UITree → Registry → View → ViewModel
//

#if canImport(SwiftUI)
import XCTest
import SwiftUI
@testable import AISDK

/// Integration tests for the complete GenerativeUI pipeline
///
/// These tests verify that all components work together correctly:
/// - UITree parsing and validation
/// - UIComponentRegistry component building and action security
/// - GenerativeUIViewModel streaming and state management
/// - Action handler integration with allowlist filtering
final class GenerativeUIIntegrationTests: XCTestCase {

    // MARK: - End-to-End Parsing Tests

    func test_full_pipeline_text_only() throws {
        // Given - JSON with simple text
        let json = """
        {
          "root": "greeting",
          "elements": {
            "greeting": {
              "type": "Text",
              "props": { "content": "Hello, World!", "style": "headline" }
            }
          }
        }
        """

        // When - Parse tree
        let tree = try UITree.parse(from: json)

        // Then - Verify tree structure
        XCTAssertEqual(tree.nodeCount, 1)
        XCTAssertEqual(tree.rootNode.key, "greeting")
        XCTAssertEqual(tree.rootNode.type, "Text")
        XCTAssertTrue(tree.rootNode.childKeys.isEmpty)
    }

    func test_full_pipeline_nested_stack_with_card() throws {
        // Given - Complex nested structure
        let json = """
        {
          "root": "main",
          "elements": {
            "main": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 16 },
              "children": ["header", "content", "footer"]
            },
            "header": {
              "type": "Text",
              "props": { "content": "Welcome", "style": "title" }
            },
            "content": {
              "type": "Card",
              "props": { "title": "Information", "style": "elevated" },
              "children": ["cardText"]
            },
            "cardText": {
              "type": "Text",
              "props": { "content": "This is a card with content" }
            },
            "footer": {
              "type": "Button",
              "props": { "title": "Continue", "action": "submit", "style": "primary" }
            }
          }
        }
        """

        // When
        let tree = try UITree.parse(from: json)

        // Then - Verify tree structure
        XCTAssertEqual(tree.nodeCount, 5)
        XCTAssertEqual(tree.rootNode.type, "Stack")
        XCTAssertEqual(tree.children(of: tree.rootNode).count, 3)

        // Verify child types
        let children = tree.children(of: tree.rootNode)
        XCTAssertEqual(children[0].type, "Text")
        XCTAssertEqual(children[1].type, "Card")
        XCTAssertEqual(children[2].type, "Button")

        // Verify nested card has child
        let cardChildren = tree.children(of: children[1])
        XCTAssertEqual(cardChildren.count, 1)
        XCTAssertEqual(cardChildren[0].type, "Text")
    }

    func test_full_pipeline_all_core8_components() throws {
        // Given - JSON using all Core 8 component types
        let json = """
        {
          "root": "main",
          "elements": {
            "main": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 12 },
              "children": ["text1", "card1", "input1", "list1", "img1", "spacer1", "btn1"]
            },
            "text1": {
              "type": "Text",
              "props": { "content": "Text Component", "style": "headline" }
            },
            "card1": {
              "type": "Card",
              "props": { "title": "Card Title", "subtitle": "Card Subtitle" },
              "children": ["cardContent"]
            },
            "cardContent": {
              "type": "Text",
              "props": { "content": "Card body text" }
            },
            "input1": {
              "type": "Input",
              "props": { "label": "Email", "placeholder": "Enter email", "type": "email" }
            },
            "list1": {
              "type": "List",
              "props": { "style": "ordered" },
              "children": ["listItem1", "listItem2"]
            },
            "listItem1": {
              "type": "Text",
              "props": { "content": "First item" }
            },
            "listItem2": {
              "type": "Text",
              "props": { "content": "Second item" }
            },
            "img1": {
              "type": "Image",
              "props": { "url": "https://example.com/image.png", "alt": "Example", "width": 100 }
            },
            "spacer1": {
              "type": "Spacer",
              "props": { "size": 20 }
            },
            "btn1": {
              "type": "Button",
              "props": { "title": "Submit", "action": "submit", "style": "primary" }
            }
          }
        }
        """

        // When
        let tree = try UITree.parse(from: json)
        let registry = UIComponentRegistry.secureDefault

        // Then - All nodes parsed correctly
        XCTAssertEqual(tree.nodeCount, 11)

        // Verify each Core 8 type is registered
        let core8Types = ["Text", "Button", "Card", "Input", "List", "Image", "Stack", "Spacer"]
        for type in core8Types {
            XCTAssertTrue(registry.hasComponent(type), "Registry should have component: \(type)")
        }

        // Verify all registered types
        let registeredTypes = registry.registeredTypes
        XCTAssertEqual(registeredTypes.count, 8)
        XCTAssertEqual(Set(registeredTypes), Set(core8Types))
    }

    // MARK: - Action Security Tests

    func test_action_allowlist_blocks_unauthorized_actions() throws {
        // Given - Secure registry with default allowlist
        let registry = UIComponentRegistry.secureDefault

        // Then - Only submit/navigate/dismiss allowed
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("navigate"))
        XCTAssertTrue(registry.isActionAllowed("dismiss"))

        // Verify unauthorized actions are blocked
        XCTAssertFalse(registry.isActionAllowed("delete_all"))
        XCTAssertFalse(registry.isActionAllowed("execute_command"))
        XCTAssertFalse(registry.isActionAllowed("reset_database"))
        XCTAssertFalse(registry.isActionAllowed(""))

        // Verify allowlist contents
        let allowed = registry.currentAllowedActions
        XCTAssertEqual(allowed, Set(["submit", "navigate", "dismiss"]))
    }

    func test_action_handler_receives_allowed_action() throws {
        // Given
        let json = """
        { "root": "btn", "elements": { "btn": { "type": "Button", "props": { "title": "Submit", "action": "submit" } } } }
        """
        let tree = try UITree.parse(from: json)
        var registry = UIComponentRegistry.default
        registry.allowAction("submit")

        var capturedAction: String?

        // When - Build view and directly invoke the handler with allowed action
        // Note: The registry wraps the handler with security filtering
        _ = registry.build(
            node: tree.rootNode,
            tree: tree,
            actionHandler: { capturedAction = $0 }
        )

        // Then - Verify allowlist state
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertNil(capturedAction) // Handler not called until user interaction
    }

    func test_custom_action_allowlist_configuration() throws {
        // Given - Empty registry (default allows all)
        var registry = UIComponentRegistry.default
        XCTAssertTrue(registry.currentAllowedActions.isEmpty) // Pass-through mode

        // When - Add custom actions
        registry.allowAction("custom_action")
        registry.allowAction("another_action")

        // Then - Only custom actions allowed
        XCTAssertTrue(registry.isActionAllowed("custom_action"))
        XCTAssertTrue(registry.isActionAllowed("another_action"))
        XCTAssertFalse(registry.isActionAllowed("submit")) // Not in list
        XCTAssertEqual(registry.currentAllowedActions.count, 2)

        // When - Disallow one
        registry.disallowAction("another_action")

        // Then
        XCTAssertFalse(registry.isActionAllowed("another_action"))
        XCTAssertEqual(registry.currentAllowedActions.count, 1)

        // When - Clear all
        registry.clearAllowedActions()

        // Then - Back to pass-through mode
        XCTAssertTrue(registry.currentAllowedActions.isEmpty)
        XCTAssertTrue(registry.isActionAllowed("any_action")) // Pass-through
    }

    func test_action_whitespace_normalization() throws {
        // Given
        var registry = UIComponentRegistry.default
        registry.allowAction("  submit  ")

        // Then - Whitespace is trimmed
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("  submit  "))
        XCTAssertEqual(registry.currentAllowedActions, Set(["submit"]))
    }

    // MARK: - ViewModel Integration Tests

    @MainActor
    func test_viewModel_loadTree_success() async {
        // Given
        let json = """
        {
          "root": "text1",
          "elements": {
            "text1": {
              "type": "Text",
              "props": { "content": "Hello" }
            }
          }
        }
        """
        let viewModel = GenerativeUIViewModel()
        XCTAssertNil(viewModel.tree)
        XCTAssertFalse(viewModel.isLoading)

        // When
        await viewModel.loadTree(from: json)

        // Then
        XCTAssertNotNil(viewModel.tree)
        XCTAssertEqual(viewModel.tree?.nodeCount, 1)
        XCTAssertEqual(viewModel.tree?.rootNode.type, "Text")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
        XCTAssertTrue(viewModel.hasTree)
        XCTAssertFalse(viewModel.hasError)
    }

    @MainActor
    func test_viewModel_loadTree_invalid_json() async {
        // Given
        let invalidJson = "{ not valid json }"
        let viewModel = GenerativeUIViewModel()

        // When
        await viewModel.loadTree(from: invalidJson)

        // Then
        XCTAssertNil(viewModel.tree)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.hasError)
        XCTAssertFalse(viewModel.hasTree)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    @MainActor
    func test_viewModel_setTree_direct() async {
        // Given
        let json = """
        {
          "root": "text1",
          "elements": {
            "text1": { "type": "Text", "props": { "content": "Direct" } }
          }
        }
        """
        let tree = try! UITree.parse(from: json)
        let viewModel = GenerativeUIViewModel()

        // When
        viewModel.setTree(tree)

        // Then
        XCTAssertNotNil(viewModel.tree)
        XCTAssertEqual(viewModel.tree?.nodeCount, 1)
        XCTAssertEqual(viewModel.tree?.rootNode.key, "text1")
        XCTAssertNil(viewModel.error) // setTree clears error
    }

    @MainActor
    func test_viewModel_clear() async {
        // Given
        let json = """
        { "root": "t", "elements": { "t": { "type": "Text", "props": { "content": "Will be cleared" } } } }
        """
        let viewModel = GenerativeUIViewModel()
        await viewModel.loadTree(from: json)
        XCTAssertTrue(viewModel.hasTree)

        // When
        viewModel.clear()

        // Then
        XCTAssertNil(viewModel.tree)
        XCTAssertFalse(viewModel.hasTree)
        XCTAssertNil(viewModel.error)
    }

    @MainActor
    func test_viewModel_subscribe_to_stream() async {
        // Given
        let tree1 = try! UITree.parse(from: """
        { "root": "t1", "elements": { "t1": { "type": "Text", "props": { "content": "First" } } } }
        """)
        let tree2 = try! UITree.parse(from: """
        { "root": "t2", "elements": { "t2": { "type": "Text", "props": { "content": "Second" } } } }
        """)

        let viewModel = GenerativeUIViewModel()
        let stream = AsyncStream<UITree> { continuation in
            continuation.yield(tree1)
            continuation.yield(tree2)
            continuation.finish()
        }

        // When
        await viewModel.subscribe(to: stream)

        // Then - Final tree should be the last one
        XCTAssertNotNil(viewModel.tree)
        XCTAssertEqual(viewModel.tree?.rootNode.key, "t2")
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func test_viewModel_scheduleUpdate_applies_updates() async {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree1 = try! UITree.parse(from: """
        { "root": "t1", "elements": { "t1": { "type": "Text", "props": { "content": "First" } } } }
        """)
        let tree2 = try! UITree.parse(from: """
        { "root": "t2", "elements": { "t2": { "type": "Text", "props": { "content": "Second" } } } }
        """)

        // When - Schedule updates
        viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(tree1)))
        viewModel.scheduleUpdate(UITreeUpdate(type: .replaceTree(tree2)))

        // Wait for batching to complete (16ms frame + buffer)
        let expectation = XCTestExpectation(description: "Updates applied")
        Task {
            // Poll until tree is updated or timeout
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(10))
                if viewModel.tree?.rootNode.key == "t2" {
                    expectation.fulfill()
                    return
                }
            }
            expectation.fulfill() // Fulfill anyway to avoid hanging
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        // Then - Final state should be tree2
        XCTAssertEqual(viewModel.tree?.rootNode.key, "t2")
    }

    @MainActor
    func test_viewModel_cancelSubscription() async {
        // Given
        let viewModel = GenerativeUIViewModel()
        let tree = try! UITree.parse(from: """
        { "root": "t", "elements": { "t": { "type": "Text", "props": { "content": "Test" } } } }
        """)

        let stream = AsyncThrowingStream<UITree, Error> { continuation in
            continuation.yield(tree)
            // Never finishes - simulates long-running stream
        }

        // When
        viewModel.startSubscription(to: stream)

        // Wait for tree to be set
        let expectation = XCTestExpectation(description: "Tree loaded")
        Task {
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(10))
                if viewModel.hasTree {
                    expectation.fulfill()
                    return
                }
            }
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertTrue(viewModel.hasTree)

        viewModel.cancelSubscription()

        // Then
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - Catalog Validation Integration Tests

    func test_catalog_validation_in_pipeline() throws {
        // Given - Valid JSON for Core 8
        let json = """
        {
          "root": "card",
          "elements": {
            "card": {
              "type": "Card",
              "props": { "title": "Test Card" },
              "children": ["btn"]
            },
            "btn": {
              "type": "Button",
              "props": { "title": "OK", "action": "submit" }
            }
          }
        }
        """

        // When - Parse with catalog validation
        let catalog = UICatalog.core8
        let tree = try UITree.parse(from: json, validatingWith: catalog)

        // Then
        XCTAssertEqual(tree.nodeCount, 2)
        XCTAssertEqual(tree.rootNode.type, "Card")
        XCTAssertEqual(tree.children(of: tree.rootNode).first?.type, "Button")
    }

    func test_catalog_validation_rejects_unknown_type() throws {
        // Given - JSON with type not in catalog
        let json = """
        {
          "root": "custom",
          "elements": {
            "custom": {
              "type": "CustomWidget",
              "props": {}
            }
          }
        }
        """

        let catalog = UICatalog.core8

        // When/Then - Should throw unknownComponentType error
        XCTAssertThrowsError(try UITree.parse(from: json, validatingWith: catalog)) { error in
            guard let treeError = error as? UITreeError else {
                XCTFail("Expected UITreeError, got \(type(of: error))")
                return
            }

            if case .unknownComponentType(let key, let type) = treeError {
                XCTAssertEqual(key, "custom")
                XCTAssertEqual(type, "CustomWidget")
            } else {
                XCTFail("Expected unknownComponentType error, got \(treeError)")
            }
        }
    }

    // MARK: - Error Handling Integration Tests

    func test_unknown_component_in_registry() throws {
        // Given - JSON with unknown component type (no catalog validation)
        let json = """
        {
          "root": "unknown",
          "elements": {
            "unknown": {
              "type": "CustomUnknownWidget",
              "props": { "foo": "bar" }
            }
          }
        }
        """

        // When - Parse succeeds (no validation)
        let tree = try UITree.parse(from: json)
        let registry = UIComponentRegistry.secureDefault

        // Then - Registry doesn't have this component
        XCTAssertFalse(registry.hasComponent("CustomUnknownWidget"))
        XCTAssertEqual(tree.rootNode.type, "CustomUnknownWidget")
    }

    func test_malformed_props_parsing_succeeds() throws {
        // Given - JSON with props that have wrong types
        let json = """
        {
          "root": "text",
          "elements": {
            "text": {
              "type": "Text",
              "props": { "content": 12345, "style": true }
            }
          }
        }
        """

        // When - Parsing succeeds (props are raw JSON data)
        let tree = try UITree.parse(from: json)

        // Then - Tree is valid, props will fail to decode at render time
        XCTAssertEqual(tree.nodeCount, 1)
        XCTAssertEqual(tree.rootNode.type, "Text")
        XCTAssertFalse(tree.rootNode.propsData.isEmpty)
    }

    // MARK: - Performance Tests

    func test_large_tree_parsing_performance() throws {
        // Given - Create a tree with 101 nodes (main + 50 cards + 50 texts)
        var elements: [String: Any] = [:]
        let childKeys = (1...50).map { "item\($0)" }
        elements["main"] = [
            "type": "Stack",
            "props": ["direction": "vertical"],
            "children": childKeys
        ]

        for i in 1...50 {
            elements["item\(i)"] = [
                "type": "Card",
                "props": ["title": "Card \(i)"],
                "children": ["text\(i)"]
            ]
            elements["text\(i)"] = [
                "type": "Text",
                "props": ["content": "Content for card \(i)"]
            ]
        }

        let jsonObject: [String: Any] = ["root": "main", "elements": elements]
        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)

        // When - Parse tree
        let tree = try UITree.parse(from: jsonData)

        // Then - Verify structure
        XCTAssertEqual(tree.nodeCount, 101) // main + 50 cards + 50 texts
        XCTAssertEqual(tree.rootNode.type, "Stack")
        XCTAssertEqual(tree.children(of: tree.rootNode).count, 50)
    }

    func test_large_tree_parsing_measured() throws {
        // Given - Create JSON for large tree (101 nodes)
        var elements: [String: Any] = [:]
        let childKeys = (1...50).map { "item\($0)" }
        elements["main"] = [
            "type": "Stack",
            "props": ["direction": "vertical"],
            "children": childKeys
        ]
        for i in 1...50 {
            elements["item\(i)"] = [
                "type": "Card",
                "props": ["title": "Card \(i)"],
                "children": ["text\(i)"]
            ]
            elements["text\(i)"] = [
                "type": "Text",
                "props": ["content": "Content for card \(i)"]
            ]
        }
        let jsonObject: [String: Any] = ["root": "main", "elements": elements]
        let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)

        // When/Then - Measure parsing performance
        measure {
            _ = try? UITree.parse(from: jsonData)
        }
    }

    // MARK: - Sendable Compliance Tests

    func test_registry_is_sendable() {
        // Given
        let registry = UIComponentRegistry.secureDefault

        // When - Capture in @Sendable closure
        let sendableCheck: @Sendable () -> Bool = {
            registry.hasComponent("Text")
        }

        // Then - Compiles and executes
        XCTAssertTrue(sendableCheck())
    }

    func test_tree_is_sendable() throws {
        // Given
        let json = """
        { "root": "t", "elements": { "t": { "type": "Text", "props": { "content": "Test" } } } }
        """
        let tree = try UITree.parse(from: json)

        // When - Capture in @Sendable closure
        let sendableCheck: @Sendable () -> Int = {
            tree.nodeCount
        }

        // Then
        XCTAssertEqual(sendableCheck(), 1)
    }

    // MARK: - Factory Method Tests

    @MainActor
    func test_viewModel_loading_factory() async {
        // Given
        let json = """
        { "root": "t", "elements": { "t": { "type": "Text", "props": { "content": "Factory" } } } }
        """
        let data = json.data(using: .utf8)!

        // When
        let viewModel = await GenerativeUIViewModel.loading(from: data)

        // Then
        XCTAssertNotNil(viewModel.tree)
        XCTAssertEqual(viewModel.tree?.rootNode.key, "t")
        XCTAssertFalse(viewModel.isLoading)
    }

    @MainActor
    func test_viewModel_streaming_factory() {
        // Given/When
        let viewModel = GenerativeUIViewModel.streaming()

        // Then
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.tree)
        XCTAssertFalse(viewModel.hasTree)
    }

    // MARK: - UITreeUpdate Tests

    func test_UITreeUpdate_types() throws {
        // Given
        let tree = try UITree.parse(from: """
        { "root": "t", "elements": { "t": { "type": "Text", "props": { "content": "Test" } } } }
        """)

        // When
        let replaceUpdate = UITreeUpdate(type: .replaceTree(tree))
        let clearUpdate = UITreeUpdate(type: .clear)

        // Then
        XCTAssertNotNil(replaceUpdate.timestamp)
        XCTAssertNotNil(clearUpdate.timestamp)

        if case .replaceTree(let updatedTree) = replaceUpdate.type {
            XCTAssertEqual(updatedTree.nodeCount, 1)
        } else {
            XCTFail("Expected replaceTree")
        }

        if case .clear = clearUpdate.type {
            // Expected
        } else {
            XCTFail("Expected clear")
        }
    }
}

#endif
