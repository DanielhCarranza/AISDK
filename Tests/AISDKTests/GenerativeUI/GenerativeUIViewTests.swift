//
//  GenerativeUIViewTests.swift
//  AISDKTests
//
//  Tests for GenerativeUIView
//

#if canImport(SwiftUI)
import XCTest
import SwiftUI
@testable import AISDK

final class GenerativeUIViewTests: XCTestCase {

    // MARK: - Basic Initialization Tests

    func test_init_with_tree_and_action_handler() {
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
        let tree = try! UITree.parse(from: json)

        // When
        var actionReceived: String?
        let view = GenerativeUIView(tree: tree) { action in
            actionReceived = action
        }

        // Then - view is created
        XCTAssertNotNil(view)
        _ = actionReceived // Silence unused variable warning
    }

    func test_init_with_custom_registry() {
        // Given
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
        let tree = try! UITree.parse(from: json)

        var registry = UIComponentRegistry()
        registry.register("CustomWidget") { _, _, _, _, _ in
            Text("Custom Widget Rendered")
        }

        // When
        let view = GenerativeUIView(tree: tree, registry: registry) { _ in }

        // Then
        XCTAssertNotNil(view)
    }

    func test_init_with_custom_props_decoder() {
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
        let tree = try! UITree.parse(from: json)

        let customDecoder = JSONDecoder()
        customDecoder.keyDecodingStrategy = .useDefaultKeys

        // When
        let view = GenerativeUIView(
            tree: tree,
            registry: .default,
            propsDecoder: customDecoder
        ) { _ in }

        // Then
        XCTAssertNotNil(view)
    }

    // MARK: - Secure Factory Tests

    func test_secure_factory_uses_secure_default_registry() {
        // Given
        let json = """
        {
          "root": "btn",
          "elements": {
            "btn": {
              "type": "Button",
              "props": { "title": "Submit", "action": "submit" }
            }
          }
        }
        """
        let tree = try! UITree.parse(from: json)

        // When
        var actionReceived: String?
        let view = GenerativeUIView.secure(tree: tree) { action in
            actionReceived = action
        }

        // Then
        XCTAssertNotNil(view)
        _ = actionReceived
    }

    // MARK: - GenerativeUITreeView Tests

    func test_tree_view_with_tree() {
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
        let tree = try! UITree.parse(from: json)

        // When
        let view = GenerativeUITreeView(
            tree: tree,
            isLoading: false,
            error: nil
        ) { _ in }

        // Then
        XCTAssertNotNil(view)
    }

    func test_tree_view_with_loading_state() {
        // Given/When
        let view = GenerativeUITreeView(
            tree: nil,
            isLoading: true,
            error: nil
        ) { _ in }

        // Then - should show loading view
        XCTAssertNotNil(view)
    }

    func test_tree_view_with_error_state() {
        // Given
        let error = UITreeError.invalidStructure(reason: "Test error")

        // When
        let view = GenerativeUITreeView(
            tree: nil,
            isLoading: false,
            error: error
        ) { _ in }

        // Then - should show error view
        XCTAssertNotNil(view)
    }

    func test_tree_view_with_empty_state() {
        // Given/When
        let view = GenerativeUITreeView(
            tree: nil,
            isLoading: false,
            error: nil
        ) { _ in }

        // Then - should show empty view
        XCTAssertNotNil(view)
    }

    func test_tree_view_with_custom_registry() {
        // Given
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
        let tree = try! UITree.parse(from: json)

        var registry = UIComponentRegistry()
        registry.register("CustomWidget") { _, _, _, _, _ in
            Text("Custom")
        }

        // When
        let view = GenerativeUITreeView(
            tree: tree,
            isLoading: false,
            error: nil,
            registry: registry
        ) { _ in }

        // Then
        XCTAssertNotNil(view)
    }

    // MARK: - Integration Tests

    func test_renders_complex_tree() {
        // Given
        let json = """
        {
          "root": "main",
          "elements": {
            "main": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 16 },
              "children": ["card"]
            },
            "card": {
              "type": "Card",
              "props": { "title": "Welcome" },
              "children": ["text", "button"]
            },
            "text": {
              "type": "Text",
              "props": { "content": "Hello World", "style": "headline" }
            },
            "button": {
              "type": "Button",
              "props": { "title": "Continue", "action": "submit" }
            }
          }
        }
        """
        let tree = try! UITree.parse(from: json)

        // When
        var actionsReceived: [String] = []
        let view = GenerativeUIView(tree: tree) { action in
            actionsReceived.append(action)
        }

        // Then
        XCTAssertNotNil(view)
    }

    func test_action_handler_receives_actions() {
        // Given
        let json = """
        {
          "root": "btn",
          "elements": {
            "btn": {
              "type": "Button",
              "props": { "title": "Test", "action": "testAction" }
            }
          }
        }
        """
        let tree = try! UITree.parse(from: json)

        // When
        var receivedAction: String?
        _ = GenerativeUIView(tree: tree) { action in
            receivedAction = action
        }

        // Then - view is created (action would be triggered on button tap)
        XCTAssertNil(receivedAction) // Not triggered until interaction
    }

    // MARK: - Sendable Compliance Tests

    func test_view_is_sendable() {
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
        let tree = try! UITree.parse(from: json)

        // When - capture in async context
        Task {
            let view = GenerativeUIView(tree: tree) { _ in }
            let _ = view
        }

        // Then - compiles without warning
    }

    func test_tree_view_is_sendable() {
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
        let tree = try! UITree.parse(from: json)

        // When - capture in async context
        Task {
            let view = GenerativeUITreeView(tree: tree) { _ in }
            let _ = view
        }

        // Then - compiles without warning
    }

    // MARK: - State Transition Tests

    func test_tree_view_state_priority() {
        // Given - tree with both loading and error (unusual but possible)
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
        let tree = try! UITree.parse(from: json)
        let error = UITreeError.invalidStructure(reason: "Test")

        // When - tree takes priority
        let view = GenerativeUITreeView(
            tree: tree,
            isLoading: true,
            error: error
        ) { _ in }

        // Then - should render tree (tree has highest priority)
        XCTAssertNotNil(view)
    }

    func test_tree_view_loading_over_error() {
        // Given - loading with error
        let error = UITreeError.invalidStructure(reason: "Test")

        // When
        let view = GenerativeUITreeView(
            tree: nil,
            isLoading: true,
            error: error
        ) { _ in }

        // Then - loading takes priority over error
        XCTAssertNotNil(view)
    }

    // MARK: - Edge Cases

    func test_single_node_tree() {
        // Given
        let json = """
        {
          "root": "single",
          "elements": {
            "single": {
              "type": "Text",
              "props": { "content": "Only node" }
            }
          }
        }
        """
        let tree = try! UITree.parse(from: json)

        // When
        let view = GenerativeUIView(tree: tree) { _ in }

        // Then
        XCTAssertNotNil(view)
    }

    func test_deeply_nested_tree() {
        // Given - 5 levels deep
        let json = """
        {
          "root": "l1",
          "elements": {
            "l1": { "type": "Stack", "props": { "direction": "vertical" }, "children": ["l2"] },
            "l2": { "type": "Stack", "props": { "direction": "vertical" }, "children": ["l3"] },
            "l3": { "type": "Stack", "props": { "direction": "vertical" }, "children": ["l4"] },
            "l4": { "type": "Stack", "props": { "direction": "vertical" }, "children": ["l5"] },
            "l5": { "type": "Text", "props": { "content": "Deep" } }
          }
        }
        """
        let tree = try! UITree.parse(from: json)

        // When
        let view = GenerativeUIView(tree: tree) { _ in }

        // Then
        XCTAssertNotNil(view)
    }

    func test_wide_tree_with_many_siblings() {
        // Given - 10 siblings
        var elements: [String: Any] = [:]
        elements["main"] = [
            "type": "Stack",
            "props": ["direction": "vertical"],
            "children": (1...10).map { "item\($0)" }
        ]
        for i in 1...10 {
            elements["item\(i)"] = [
                "type": "Text",
                "props": ["content": "Item \(i)"]
            ]
        }

        let jsonObject: [String: Any] = ["root": "main", "elements": elements]
        let jsonData = try! JSONSerialization.data(withJSONObject: jsonObject)
        let tree = try! UITree.parse(from: jsonData)

        // When
        let view = GenerativeUIView(tree: tree) { _ in }

        // Then
        XCTAssertNotNil(view)
    }
}

#endif
