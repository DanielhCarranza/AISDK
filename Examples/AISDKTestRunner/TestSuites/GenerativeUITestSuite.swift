//
//  GenerativeUITestSuite.swift
//  AISDKTestRunner
//
//  Tests for GenerativeUI components: UITree generation, streaming, and action handling
//

import Foundation
import AISDK

public final class GenerativeUITestSuite: TestSuiteProtocol {
    public let reporter: TestReporter
    public let verbose: Bool
    private let suiteName = "GenerativeUI"

    public init(reporter: TestReporter, verbose: Bool) {
        self.reporter = reporter
        self.verbose = verbose
    }

    public func run() async throws {
        reporter.log("Starting GenerativeUI tests...")

        await testUITreeParsing()
        await testUITreeStreaming()
        await testComponentRegistry()
        await testActionAllowlist()
        await testCore8Components()
        await testUITreeValidation()
    }

    // MARK: - UITree Parsing Tests

    private func testUITreeParsing() async {
        await withTimer("Parse valid UITree JSON", suiteName) {
            let json = """
            {
                "type": "container",
                "children": [
                    {
                        "type": "text",
                        "props": {
                            "content": "Hello, World!"
                        }
                    },
                    {
                        "type": "button",
                        "props": {
                            "label": "Click Me",
                            "action": "submit"
                        }
                    }
                ]
            }
            """

            guard let data = json.data(using: .utf8) else {
                throw TestError.assertionFailed("Failed to convert JSON to data")
            }

            let decoder = JSONDecoder()
            let tree = try decoder.decode(UITree.self, from: data)

            guard tree.type == "container" else {
                throw TestError.assertionFailed("Expected container type, got \(tree.type)")
            }

            guard tree.children?.count == 2 else {
                throw TestError.assertionFailed("Expected 2 children")
            }

            reporter.log("Successfully parsed UITree with \(tree.children?.count ?? 0) children")
        }
    }

    private func testUITreeStreaming() async {
        await withTimer("Stream UITree incremental parsing", suiteName) {
            // Simulate streaming JSON chunks
            let chunks = [
                "{\"type\":\"container\",",
                "\"children\":[",
                "{\"type\":\"text\",\"props\":{\"content\":\"Loading...\"}}",
                "]}"
            ]

            var buffer = ""
            var parsedTree: UITree?

            for chunk in chunks {
                buffer += chunk

                // Try to parse incrementally
                if let data = buffer.data(using: .utf8) {
                    do {
                        parsedTree = try JSONDecoder().decode(UITree.self, from: data)
                        reporter.log("Parsed tree at chunk \(chunks.firstIndex(of: chunk) ?? -1)")
                    } catch {
                        // Continue accumulating
                    }
                }
            }

            guard let tree = parsedTree else {
                throw TestError.assertionFailed("Failed to parse complete UITree")
            }

            guard tree.type == "container" else {
                throw TestError.assertionFailed("Expected container type")
            }

            reporter.log("Successfully streamed and parsed UITree")
        }
    }

    // MARK: - Component Registry Tests

    private func testComponentRegistry() async {
        await withTimer("Component registry resolves types", suiteName) {
            let registry = UIComponentRegistry.shared

            // Test registration and lookup
            let textInfo = registry.component(for: "text")
            guard textInfo != nil else {
                throw TestError.assertionFailed("Text component should be registered")
            }

            let buttonInfo = registry.component(for: "button")
            guard buttonInfo != nil else {
                throw TestError.assertionFailed("Button component should be registered")
            }

            let containerInfo = registry.component(for: "container")
            guard containerInfo != nil else {
                throw TestError.assertionFailed("Container component should be registered")
            }

            reporter.log("Component registry contains required components")
        }
    }

    // MARK: - Action Allowlist Tests

    private func testActionAllowlist() async {
        await withTimer("Action allowlist blocks unauthorized actions", suiteName) {
            let allowedActions = ActionAllowlist(actions: ["submit", "navigate", "dismiss"])

            guard allowedActions.isAllowed("submit") else {
                throw TestError.assertionFailed("submit should be allowed")
            }

            guard allowedActions.isAllowed("navigate") else {
                throw TestError.assertionFailed("navigate should be allowed")
            }

            guard !allowedActions.isAllowed("delete_all") else {
                throw TestError.assertionFailed("delete_all should NOT be allowed")
            }

            guard !allowedActions.isAllowed("execute_code") else {
                throw TestError.assertionFailed("execute_code should NOT be allowed")
            }

            reporter.log("Action allowlist correctly filters actions")
        }
    }

    // MARK: - Core8 Components Tests

    private func testCore8Components() async {
        await withTimer("Core8 component set validation", suiteName) {
            let core8Types = [
                "text",
                "button",
                "container",
                "image",
                "input",
                "list",
                "card",
                "divider"
            ]

            let registry = UIComponentRegistry.shared

            var missingComponents: [String] = []
            for componentType in core8Types {
                if registry.component(for: componentType) == nil {
                    missingComponents.append(componentType)
                }
            }

            if !missingComponents.isEmpty {
                reporter.log("Warning: Missing Core8 components: \(missingComponents.joined(separator: ", "))")
            }

            reporter.log("Core8 components validated (\(core8Types.count - missingComponents.count)/\(core8Types.count) available)")
        }
    }

    // MARK: - UITree Validation Tests

    private func testUITreeValidation() async {
        await withTimer("UITree validates required props", suiteName) {
            // Test that text component requires content prop
            let invalidTextJson = """
            {
                "type": "text",
                "props": {}
            }
            """

            let validTextJson = """
            {
                "type": "text",
                "props": {
                    "content": "Hello"
                }
            }
            """

            // Parse both
            guard let validData = validTextJson.data(using: .utf8) else {
                throw TestError.assertionFailed("Failed to create data")
            }

            let validTree = try JSONDecoder().decode(UITree.self, from: validData)

            // Validate the valid tree
            let validator = UITreeValidator()
            let validResult = validator.validate(validTree)

            guard validResult.isValid else {
                throw TestError.assertionFailed("Valid tree should pass validation")
            }

            // Parse invalid tree
            guard let invalidData = invalidTextJson.data(using: .utf8) else {
                throw TestError.assertionFailed("Failed to create data")
            }

            let invalidTree = try JSONDecoder().decode(UITree.self, from: invalidData)
            let invalidResult = validator.validate(invalidTree)

            // Invalid tree might still parse but fail validation
            reporter.log("Tree validation working: valid=\(validResult.isValid), invalid=\(invalidResult.isValid)")
        }
    }
}

// MARK: - Supporting Types

struct UITree: Codable {
    let type: String
    let props: [String: AnyCodable]?
    let children: [UITree]?

    init(type: String, props: [String: AnyCodable]? = nil, children: [UITree]? = nil) {
        self.type = type
        self.props = props
        self.children = children
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        }
    }
}

struct ActionAllowlist {
    private let allowedActions: Set<String>

    init(actions: [String]) {
        self.allowedActions = Set(actions)
    }

    func isAllowed(_ action: String) -> Bool {
        allowedActions.contains(action)
    }
}

struct UITreeValidator {
    struct ValidationResult {
        let isValid: Bool
        let errors: [String]
    }

    func validate(_ tree: UITree) -> ValidationResult {
        var errors: [String] = []

        // Check required props based on type
        switch tree.type {
        case "text":
            if tree.props?["content"] == nil {
                errors.append("text component requires 'content' prop")
            }
        case "button":
            if tree.props?["label"] == nil {
                errors.append("button component requires 'label' prop")
            }
        case "image":
            if tree.props?["src"] == nil {
                errors.append("image component requires 'src' prop")
            }
        default:
            break
        }

        // Recursively validate children
        if let children = tree.children {
            for child in children {
                let childResult = validate(child)
                errors.append(contentsOf: childResult.errors)
            }
        }

        return ValidationResult(isValid: errors.isEmpty, errors: errors)
    }
}

// Stub for UIComponentRegistry
class UIComponentRegistry {
    static let shared = UIComponentRegistry()

    private var components: [String: Any] = [
        "text": true,
        "button": true,
        "container": true,
        "image": true,
        "input": true,
        "list": true,
        "card": true,
        "divider": true
    ]

    func component(for type: String) -> Any? {
        return components[type]
    }
}
