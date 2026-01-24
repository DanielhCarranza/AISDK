//
//  UIComponentRegistryTests.swift
//  AISDKTests
//
//  Tests for UIComponentRegistry
//

#if canImport(SwiftUI)
import XCTest
import SwiftUI
@testable import AISDK

final class UIComponentRegistryTests: XCTestCase {

    // MARK: - Default Registry Tests

    func test_default_registry_has_core8() {
        // Given
        let registry = UIComponentRegistry.default

        // Then - all Core 8 components should be registered
        XCTAssertTrue(registry.hasComponent("Text"), "Text should be registered")
        XCTAssertTrue(registry.hasComponent("Button"), "Button should be registered")
        XCTAssertTrue(registry.hasComponent("Card"), "Card should be registered")
        XCTAssertTrue(registry.hasComponent("Input"), "Input should be registered")
        XCTAssertTrue(registry.hasComponent("List"), "List should be registered")
        XCTAssertTrue(registry.hasComponent("Image"), "Image should be registered")
        XCTAssertTrue(registry.hasComponent("Stack"), "Stack should be registered")
        XCTAssertTrue(registry.hasComponent("Spacer"), "Spacer should be registered")

        // Verify count
        XCTAssertEqual(registry.registeredTypes.count, 8, "Should have exactly 8 components")
    }

    func test_default_registry_types_sorted() {
        // Given
        let registry = UIComponentRegistry.default

        // Then - registered types should be sorted
        let types = registry.registeredTypes
        let expected = ["Button", "Card", "Image", "Input", "List", "Spacer", "Stack", "Text"]
        XCTAssertEqual(types, expected, "Types should be sorted alphabetically")
    }

    // MARK: - Custom Registration Tests

    func test_custom_component_registration() {
        // Given
        var registry = UIComponentRegistry()

        // When
        registry.register("CustomComponent") { _, _, _, _, _ in
            Text("Custom")
        }

        // Then
        XCTAssertTrue(registry.hasComponent("CustomComponent"))
        XCTAssertFalse(registry.hasComponent("Text"))
    }

    func test_multiple_custom_registrations() {
        // Given
        var registry = UIComponentRegistry()

        // When
        registry.register("Alpha") { _, _, _, _, _ in Text("A") }
        registry.register("Beta") { _, _, _, _, _ in Text("B") }
        registry.register("Gamma") { _, _, _, _, _ in Text("G") }

        // Then
        XCTAssertEqual(registry.registeredTypes, ["Alpha", "Beta", "Gamma"])
    }

    func test_registration_overwrites_existing() {
        // Given
        var registry = UIComponentRegistry()
        registry.register("Widget") { _, _, _, _, _ in Text("First") }

        // When - register same type again
        registry.register("Widget") { _, _, _, _, _ in Text("Second") }

        // Then - should still have the component
        XCTAssertTrue(registry.hasComponent("Widget"))
        XCTAssertEqual(registry.registeredTypes.count, 1)
    }

    // MARK: - Unknown Type Tests

    func test_unknown_type_handled() {
        // Given
        let registry = UIComponentRegistry.default
        let node = UINode(
            key: "test",
            type: "UnknownWidget",
            propsData: Data("{}".utf8)
        )
        let tree = UITree(rootKey: "test", nodes: ["test": node])

        // When
        var actionCalled = false
        let view = registry.build(
            node: node,
            tree: tree,
            actionHandler: { _ in actionCalled = true }
        )

        // Then - should return a view (not crash)
        XCTAssertNotNil(view)
        XCTAssertFalse(actionCalled)
    }

    func test_hasComponent_returns_false_for_unknown() {
        // Given
        let registry = UIComponentRegistry()

        // Then
        XCTAssertFalse(registry.hasComponent("Unknown"))
        XCTAssertFalse(registry.hasComponent(""))
        XCTAssertFalse(registry.hasComponent("Text"))
    }

    // MARK: - Action Allowlist Tests

    func test_empty_allowlist_allows_all_actions() {
        // Given
        let registry = UIComponentRegistry()

        // Then - empty allowlist means all actions allowed
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("navigate"))
        XCTAssertTrue(registry.isActionAllowed("anything"))
        XCTAssertTrue(registry.currentAllowedActions.isEmpty)
    }

    func test_allow_action_restricts_to_allowlist() {
        // Given
        var registry = UIComponentRegistry()

        // When
        registry.allowAction("submit")

        // Then
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertFalse(registry.isActionAllowed("navigate"))
        XCTAssertFalse(registry.isActionAllowed("other"))
    }

    func test_allow_multiple_actions() {
        // Given
        var registry = UIComponentRegistry()

        // When
        registry.allowAction("submit")
        registry.allowAction("navigate")
        registry.allowAction("dismiss")

        // Then
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("navigate"))
        XCTAssertTrue(registry.isActionAllowed("dismiss"))
        XCTAssertFalse(registry.isActionAllowed("other"))
        XCTAssertEqual(registry.currentAllowedActions.count, 3)
    }

    func test_allowActions_collection() {
        // Given
        var registry = UIComponentRegistry()

        // When
        registry.allowActions(["submit", "navigate", "dismiss"])

        // Then
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("navigate"))
        XCTAssertTrue(registry.isActionAllowed("dismiss"))
        XCTAssertFalse(registry.isActionAllowed("other"))
    }

    func test_disallow_action() {
        // Given
        var registry = UIComponentRegistry()
        registry.allowActions(["submit", "navigate"])

        // When
        registry.disallowAction("submit")

        // Then
        XCTAssertFalse(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("navigate"))
    }

    func test_clear_allowed_actions_reverts_to_passthrough() {
        // Given
        var registry = UIComponentRegistry()
        registry.allowActions(["submit", "navigate"])
        XCTAssertFalse(registry.isActionAllowed("other"))

        // When
        registry.clearAllowedActions()

        // Then - back to pass-through mode
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("navigate"))
        XCTAssertTrue(registry.isActionAllowed("other"))
        XCTAssertTrue(registry.currentAllowedActions.isEmpty)
    }

    // MARK: - Action Handler Security Tests

    func test_action_blocked_when_not_in_allowlist() {
        // Given
        var registry = UIComponentRegistry()
        registry.register("Button") { node, _, decoder, handler, _ in
            // Simulate button that triggers action
            let props = try? decoder.decode(ButtonComponentDefinition.Props.self, from: node.propsData)
            handler(props?.action ?? "")
            return Text("Button")
        }
        registry.allowAction("submit")

        let node = UINode(
            key: "btn",
            type: "Button",
            propsData: Data(#"{"title":"Test","action":"navigate"}"#.utf8)
        )
        let tree = UITree(rootKey: "btn", nodes: ["btn": node])

        // When
        var receivedAction: String?
        _ = registry.build(node: node, tree: tree) { action in
            receivedAction = action
        }

        // Then - navigate action should be blocked
        XCTAssertNil(receivedAction, "Blocked action should not reach handler")
    }

    func test_action_allowed_when_in_allowlist() {
        // Given
        var registry = UIComponentRegistry()
        registry.register("Button") { node, _, decoder, handler, _ in
            let props = try? decoder.decode(ButtonComponentDefinition.Props.self, from: node.propsData)
            handler(props?.action ?? "")
            return Text("Button")
        }
        registry.allowAction("submit")

        let node = UINode(
            key: "btn",
            type: "Button",
            propsData: Data(#"{"title":"Test","action":"submit"}"#.utf8)
        )
        let tree = UITree(rootKey: "btn", nodes: ["btn": node])

        // When
        var receivedAction: String?
        _ = registry.build(node: node, tree: tree) { action in
            receivedAction = action
        }

        // Then
        XCTAssertEqual(receivedAction, "submit")
    }

    func test_action_passthrough_with_empty_allowlist() {
        // Given
        var registry = UIComponentRegistry()
        registry.register("Button") { node, _, decoder, handler, _ in
            let props = try? decoder.decode(ButtonComponentDefinition.Props.self, from: node.propsData)
            handler(props?.action ?? "")
            return Text("Button")
        }
        // No actions allowed = pass-through mode

        let node = UINode(
            key: "btn",
            type: "Button",
            propsData: Data(#"{"title":"Test","action":"anything"}"#.utf8)
        )
        let tree = UITree(rootKey: "btn", nodes: ["btn": node])

        // When
        var receivedAction: String?
        _ = registry.build(node: node, tree: tree) { action in
            receivedAction = action
        }

        // Then
        XCTAssertEqual(receivedAction, "anything")
    }

    // MARK: - View Building Tests

    func test_build_with_valid_text_node() {
        // Given
        let registry = UIComponentRegistry.default
        let node = UINode(
            key: "text1",
            type: "Text",
            propsData: Data(#"{"content":"Hello World"}"#.utf8)
        )
        let tree = UITree(rootKey: "text1", nodes: ["text1": node])

        // When
        let view = registry.build(node: node, tree: tree) { _ in }

        // Then
        XCTAssertNotNil(view)
    }

    func test_buildChildren_returns_child_views() {
        // Given
        let registry = UIComponentRegistry.default
        let stackNode = UINode(
            key: "stack",
            type: "Stack",
            propsData: Data(#"{"direction":"vertical"}"#.utf8),
            childKeys: ["text1", "text2"],
            hadChildrenField: true
        )
        let text1Node = UINode(
            key: "text1",
            type: "Text",
            propsData: Data(#"{"content":"First"}"#.utf8)
        )
        let text2Node = UINode(
            key: "text2",
            type: "Text",
            propsData: Data(#"{"content":"Second"}"#.utf8)
        )
        let tree = UITree(rootKey: "stack", nodes: [
            "stack": stackNode,
            "text1": text1Node,
            "text2": text2Node
        ])

        // When
        let children = registry.buildChildren(of: stackNode, tree: tree) { _ in }

        // Then
        XCTAssertEqual(children.count, 2)
    }

    // MARK: - Props Decoder Tests

    func test_default_props_decoder_uses_snake_case() {
        // Given
        let decoder = UIComponentRegistry.defaultPropsDecoder

        struct TestProps: Codable {
            let accessibilityLabel: String
            let contentMode: String
        }

        let json = Data(#"{"accessibility_label":"Test","content_mode":"fit"}"#.utf8)

        // When
        let props = try? decoder.decode(TestProps.self, from: json)

        // Then
        XCTAssertEqual(props?.accessibilityLabel, "Test")
        XCTAssertEqual(props?.contentMode, "fit")
    }

    // MARK: - Sendable Compliance Tests

    func test_registry_is_sendable() {
        // Given
        let registry = UIComponentRegistry.default

        // When - capture in async context
        Task {
            let _ = registry.hasComponent("Text")
        }

        // Then - compiles without warning (Sendable)
    }

    func test_action_handler_is_sendable() {
        // Given
        var registry = UIComponentRegistry()
        registry.register("Test") { _, _, _, handler, _ in
            // Handler should be callable from any context
            Task {
                handler("async_action")
            }
            return Text("Test")
        }

        // Then - compiles without warning
    }
}

// MARK: - Integration Tests

extension UIComponentRegistryTests {

    func test_integration_render_complete_tree() {
        // Given
        let registry = UIComponentRegistry.default
        let json = """
        {
          "root": "main",
          "elements": {
            "main": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 16 },
              "children": ["title", "button"]
            },
            "title": {
              "type": "Text",
              "props": { "content": "Welcome", "style": "headline" }
            },
            "button": {
              "type": "Button",
              "props": { "title": "Continue", "action": "submit" }
            }
          }
        }
        """

        // When
        let tree = try? UITree.parse(from: json)
        XCTAssertNotNil(tree)

        var receivedAction: String?
        let view = registry.build(node: tree!.rootNode, tree: tree!) { action in
            receivedAction = action
        }

        // Then
        XCTAssertNotNil(view)
        _ = receivedAction // Silence unused variable warning
    }

    func test_integration_allowlist_with_catalog_actions() {
        // Given
        var registry = UIComponentRegistry.default

        // Allow only actions from the catalog
        let catalog = UICatalog.core8
        for actionName in catalog.actions.keys {
            registry.allowAction(actionName)
        }

        // Then
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("navigate"))
        XCTAssertTrue(registry.isActionAllowed("dismiss"))
        XCTAssertFalse(registry.isActionAllowed("malicious_action"))
    }

    // MARK: - Secure Default Tests

    func test_secureDefault_has_standard_actions() {
        // Given
        let registry = UIComponentRegistry.secureDefault

        // Then - secure default should have standard actions pre-allowed
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("navigate"))
        XCTAssertTrue(registry.isActionAllowed("dismiss"))
        XCTAssertFalse(registry.isActionAllowed("custom_action"))
        XCTAssertEqual(registry.currentAllowedActions.count, 3)
    }

    func test_secureDefault_has_core8_components() {
        // Given
        let registry = UIComponentRegistry.secureDefault

        // Then - should have all Core 8 components
        XCTAssertEqual(registry.registeredTypes.count, 8)
        XCTAssertTrue(registry.hasComponent("Text"))
        XCTAssertTrue(registry.hasComponent("Button"))
    }

    // MARK: - Action Trimming Tests

    func test_allowAction_trims_whitespace() {
        // Given
        var registry = UIComponentRegistry()

        // When - add action with whitespace
        registry.allowAction("  submit  ")

        // Then - trimmed version should be allowed
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("  submit  ")) // Also works with whitespace
        XCTAssertEqual(registry.currentAllowedActions, ["submit"])
    }

    func test_allowAction_ignores_empty() {
        // Given
        var registry = UIComponentRegistry()

        // When - try to add empty or whitespace-only
        registry.allowAction("")
        registry.allowAction("   ")

        // Then - should remain empty
        XCTAssertTrue(registry.currentAllowedActions.isEmpty)
    }

    func test_isActionAllowed_trims_input() {
        // Given
        var registry = UIComponentRegistry()
        registry.allowAction("submit")

        // Then - check with whitespace should work
        XCTAssertTrue(registry.isActionAllowed("submit"))
        XCTAssertTrue(registry.isActionAllowed("  submit  "))
        XCTAssertTrue(registry.isActionAllowed("\tsubmit\n"))
    }

    func test_action_dispatch_trims_and_normalizes() {
        // Given
        var registry = UIComponentRegistry()
        registry.register("Button") { node, _, decoder, handler, _ in
            let props = try? decoder.decode(ButtonComponentDefinition.Props.self, from: node.propsData)
            handler(props?.action ?? "")
            return Text("Button")
        }
        registry.allowAction("submit")

        // When - action has trailing whitespace
        let node = UINode(
            key: "btn",
            type: "Button",
            propsData: Data(#"{"title":"Test","action":"submit "}"#.utf8)
        )
        let tree = UITree(rootKey: "btn", nodes: ["btn": node])

        var receivedAction: String?
        _ = registry.build(node: node, tree: tree) { action in
            receivedAction = action
        }

        // Then - should receive trimmed action
        XCTAssertEqual(receivedAction, "submit")
    }
}

#endif
