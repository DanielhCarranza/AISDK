//
//  UITree.swift
//  AISDK
//
//  UITree model for json-render pattern
//  Represents a tree of UI components with validation against a UICatalog
//

import Foundation

// MARK: - UINode

/// Represents a single node in the UI tree
///
/// Each node corresponds to one UI component with its type, props, and optional children.
/// Nodes are keyed for reference in the tree structure.
public struct UINode: Sendable, Equatable {
    /// Unique key identifying this node in the tree
    public let key: String

    /// Component type identifier (e.g., "Text", "Button", "Stack")
    public let type: String

    /// Raw JSON props data for this component
    public let propsData: Data

    /// Keys of child nodes (only valid for container components)
    public let childKeys: [String]

    /// Creates a new UI node
    ///
    /// - Parameters:
    ///   - key: Unique identifier for this node
    ///   - type: Component type identifier
    ///   - propsData: Raw JSON data for component props
    ///   - childKeys: Array of child node keys
    public init(
        key: String,
        type: String,
        propsData: Data,
        childKeys: [String] = []
    ) {
        self.key = key
        self.type = type
        self.propsData = propsData
        self.childKeys = childKeys
    }
}

// MARK: - UITreeError

/// Errors that can occur during UITree parsing and validation
public enum UITreeError: Error, Sendable {
    /// JSON structure is malformed or missing required fields
    case invalidStructure(reason: String)

    /// Root key references a non-existent element
    case rootNotFound(key: String)

    /// Child key references a non-existent element
    case childNotFound(parentKey: String, childKey: String)

    /// Circular reference detected in tree structure
    case circularReference(key: String)

    /// Duplicate keys detected in elements
    case duplicateKey(key: String)

    /// Node key is empty or whitespace-only
    case invalidNodeKey(key: String)

    /// Component type is not registered in the catalog
    case unknownComponentType(key: String, type: String)

    /// Component does not support children but has children array
    case childrenNotAllowed(key: String, type: String)

    /// Component validation failed
    case validationFailed(key: String, error: UIComponentValidationError)
}

extension UITreeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidStructure(let reason):
            return "Invalid UITree structure: \(reason)"
        case .rootNotFound(let key):
            return "Root element '\(key)' not found in elements"
        case .childNotFound(let parentKey, let childKey):
            return "Child '\(childKey)' of element '\(parentKey)' not found in elements"
        case .circularReference(let key):
            return "Circular reference detected at element '\(key)'"
        case .duplicateKey(let key):
            return "Duplicate element key: '\(key)'"
        case .invalidNodeKey(let key):
            return "Invalid node key: '\(key)' (must be non-empty and trimmed)"
        case .unknownComponentType(let key, let type):
            return "Element '\(key)' has unknown component type: '\(type)'"
        case .childrenNotAllowed(let key, let type):
            return "Element '\(key)' of type '\(type)' does not support children"
        case .validationFailed(let key, let error):
            return "Element '\(key)' validation failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - UITree

/// Represents a complete UI tree parsed from json-render format
///
/// `UITree` is the parsed representation of LLM-generated UI in the json-render pattern.
/// It provides:
/// - Structural validation (valid keys, no cycles, children correctness)
/// - Component type validation against a `UICatalog`
/// - Props validation for each component
///
/// ## JSON Format
/// ```json
/// {
///   "root": "main",
///   "elements": {
///     "main": {
///       "type": "Stack",
///       "props": { "direction": "vertical" },
///       "children": ["title", "button"]
///     },
///     "title": {
///       "type": "Text",
///       "props": { "content": "Hello" }
///     },
///     "button": {
///       "type": "Button",
///       "props": { "title": "Click", "action": "submit" }
///     }
///   }
/// }
/// ```
///
/// ## Usage
/// ```swift
/// let catalog = UICatalog.core8
/// let tree = try UITree.parse(from: jsonData, validatingWith: catalog)
///
/// // Access nodes
/// let root = tree.rootNode
/// let children = tree.children(of: root)
/// ```
public struct UITree: Sendable, Equatable {
    /// Key of the root element
    public let rootKey: String

    /// All nodes in the tree, keyed by their identifier
    public let nodes: [String: UINode]

    /// The root node of the tree
    public var rootNode: UINode {
        // Safe to force unwrap - validated during construction
        nodes[rootKey]!
    }

    // MARK: - Initialization

    /// Creates a UITree directly (internal, for testing)
    init(rootKey: String, nodes: [String: UINode]) {
        self.rootKey = rootKey
        self.nodes = nodes
    }

    // MARK: - Parsing

    /// Parse a UITree from JSON data
    ///
    /// - Parameters:
    ///   - data: JSON data in json-render format
    ///   - catalog: Optional catalog for component validation
    /// - Returns: A validated UITree
    /// - Throws: `UITreeError` for structural issues, `UIComponentValidationError` for props issues
    public static func parse(
        from data: Data,
        validatingWith catalog: UICatalog? = nil
    ) throws -> UITree {
        // Parse JSON
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw UITreeError.invalidStructure(reason: "Root must be a JSON object")
            }
            json = parsed
        } catch let error as UITreeError {
            throw error
        } catch {
            throw UITreeError.invalidStructure(reason: "Failed to parse JSON: \(error.localizedDescription)")
        }

        // Extract root key
        guard let rootKey = json["root"] as? String else {
            throw UITreeError.invalidStructure(reason: "Missing or invalid 'root' field")
        }

        let trimmedRootKey = rootKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedRootKey.isEmpty {
            throw UITreeError.invalidNodeKey(key: rootKey)
        }
        if rootKey != trimmedRootKey {
            throw UITreeError.invalidNodeKey(key: rootKey)
        }

        // Extract elements
        guard let elements = json["elements"] as? [String: [String: Any]] else {
            throw UITreeError.invalidStructure(reason: "Missing or invalid 'elements' field")
        }

        // Parse all nodes
        var nodes: [String: UINode] = [:]

        for (key, element) in elements {
            // Validate key
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.isEmpty {
                throw UITreeError.invalidNodeKey(key: key)
            }
            if key != trimmedKey {
                throw UITreeError.invalidNodeKey(key: key)
            }
            if nodes[key] != nil {
                throw UITreeError.duplicateKey(key: key)
            }

            // Extract type
            guard let type = element["type"] as? String else {
                throw UITreeError.invalidStructure(reason: "Element '\(key)' missing 'type' field")
            }

            // Extract props (default to empty object)
            let props = element["props"] as? [String: Any] ?? [:]
            let propsData: Data
            do {
                propsData = try JSONSerialization.data(withJSONObject: props)
            } catch {
                throw UITreeError.invalidStructure(
                    reason: "Element '\(key)' has invalid props: \(error.localizedDescription)"
                )
            }

            // Extract children (default to empty array)
            let childKeys: [String]
            if let children = element["children"] {
                guard let childArray = children as? [String] else {
                    throw UITreeError.invalidStructure(
                        reason: "Element '\(key)' has invalid 'children' field (must be array of strings)"
                    )
                }
                childKeys = childArray
            } else {
                childKeys = []
            }

            nodes[key] = UINode(
                key: key,
                type: type,
                propsData: propsData,
                childKeys: childKeys
            )
        }

        // Validate root exists
        guard nodes[rootKey] != nil else {
            throw UITreeError.rootNotFound(key: rootKey)
        }

        // Validate all child references and check for cycles
        try validateReferences(rootKey: rootKey, nodes: nodes)

        // Create tree
        let tree = UITree(rootKey: rootKey, nodes: nodes)

        // Validate against catalog if provided
        if let catalog {
            try tree.validate(with: catalog)
        }

        return tree
    }

    /// Validate all node references and detect cycles
    private static func validateReferences(
        rootKey: String,
        nodes: [String: UINode]
    ) throws {
        // Track visited nodes to detect cycles
        var visited: Set<String> = []
        var inStack: Set<String> = []

        func visit(_ key: String, parentKey: String?) throws {
            // Check if node exists
            guard let node = nodes[key] else {
                if let parent = parentKey {
                    throw UITreeError.childNotFound(parentKey: parent, childKey: key)
                } else {
                    throw UITreeError.rootNotFound(key: key)
                }
            }

            // Check for cycle
            if inStack.contains(key) {
                throw UITreeError.circularReference(key: key)
            }

            // Skip if already fully visited
            if visited.contains(key) {
                return
            }

            inStack.insert(key)

            // Visit children
            for childKey in node.childKeys {
                try visit(childKey, parentKey: key)
            }

            inStack.remove(key)
            visited.insert(key)
        }

        try visit(rootKey, parentKey: nil)
    }

    // MARK: - Validation

    /// Validate all nodes against a catalog
    ///
    /// - Parameter catalog: The catalog to validate against
    /// - Throws: `UITreeError` if any node fails validation
    public func validate(with catalog: UICatalog) throws {
        for (key, node) in nodes {
            // Check component type exists
            guard let definition = catalog.component(forType: node.type) else {
                throw UITreeError.unknownComponentType(key: key, type: node.type)
            }

            // Check children are allowed
            if !node.childKeys.isEmpty && !definition.hasChildren {
                throw UITreeError.childrenNotAllowed(key: key, type: node.type)
            }

            // Validate props
            do {
                try catalog.validate(type: node.type, propsData: node.propsData)
            } catch let error as UIComponentValidationError {
                throw UITreeError.validationFailed(key: key, error: error)
            }
        }
    }

    // MARK: - Tree Traversal

    /// Get the children of a node
    ///
    /// - Parameter node: The parent node
    /// - Returns: Array of child nodes in order
    public func children(of node: UINode) -> [UINode] {
        node.childKeys.compactMap { nodes[$0] }
    }

    /// Get a node by key
    ///
    /// - Parameter key: The node key
    /// - Returns: The node, or nil if not found
    public func node(forKey key: String) -> UINode? {
        nodes[key]
    }

    /// Traverse the tree depth-first, calling the visitor for each node
    ///
    /// - Parameters:
    ///   - visitor: Closure called for each node with the node and its depth
    public func traverse(_ visitor: (UINode, Int) -> Void) {
        func visit(_ node: UINode, depth: Int) {
            visitor(node, depth)
            for child in children(of: node) {
                visit(child, depth: depth + 1)
            }
        }
        visit(rootNode, depth: 0)
    }

    /// Get all nodes in depth-first order
    ///
    /// - Returns: Array of all nodes starting from root
    public func allNodes() -> [UINode] {
        var result: [UINode] = []
        traverse { node, _ in
            result.append(node)
        }
        return result
    }

    /// Get the total number of nodes in the tree
    public var nodeCount: Int {
        nodes.count
    }

    /// Get the maximum depth of the tree
    public var maxDepth: Int {
        var max = 0
        traverse { _, depth in
            if depth > max {
                max = depth
            }
        }
        return max
    }
}

// MARK: - Convenience Decoding

extension UITree {
    /// Parse a UITree from a JSON string
    ///
    /// - Parameters:
    ///   - jsonString: JSON string in json-render format
    ///   - catalog: Optional catalog for component validation
    /// - Returns: A validated UITree
    /// - Throws: `UITreeError` for structural issues
    public static func parse(
        from jsonString: String,
        validatingWith catalog: UICatalog? = nil
    ) throws -> UITree {
        guard let data = jsonString.data(using: .utf8) else {
            throw UITreeError.invalidStructure(reason: "Failed to encode string as UTF-8")
        }
        return try parse(from: data, validatingWith: catalog)
    }
}
