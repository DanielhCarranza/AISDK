//
//  UITree.swift
//  AISDK
//
//  UITree model for json-render pattern
//  Represents a tree of UI components with validation against a UICatalog
//

import Foundation

// MARK: - Constants

private enum TreeLimits {
    /// Maximum tree depth to prevent stack overflow from malicious input
    static let maxDepth = 100
    /// Maximum number of nodes to prevent resource exhaustion
    static let maxNodes = 10_000
}

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

    /// Whether the "children" field was present in the JSON (even if empty)
    public let hadChildrenField: Bool

    /// Creates a new UI node
    ///
    /// - Parameters:
    ///   - key: Unique identifier for this node
    ///   - type: Component type identifier
    ///   - propsData: Raw JSON data for component props
    ///   - childKeys: Array of child node keys
    ///   - hadChildrenField: Whether the children field was present in JSON
    public init(
        key: String,
        type: String,
        propsData: Data,
        childKeys: [String] = [],
        hadChildrenField: Bool = false
    ) {
        self.key = key
        self.type = type
        self.propsData = propsData
        self.childKeys = childKeys
        self.hadChildrenField = hadChildrenField
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

    /// Component does not support children but has children field
    case childrenNotAllowed(key: String, type: String)

    /// Component validation failed
    case validationFailed(key: String, error: UIComponentValidationError)

    /// Node is referenced by multiple parents (not a tree)
    case multipleParents(key: String)

    /// Tree exceeds maximum depth limit
    case depthExceeded(maxAllowed: Int)

    /// Tree exceeds maximum node count
    case nodeCountExceeded(maxAllowed: Int)

    /// Node is not reachable from root
    case unreachableNode(key: String)
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
        case .multipleParents(let key):
            return "Element '\(key)' is referenced by multiple parents (must be a tree, not a DAG)"
        case .depthExceeded(let maxAllowed):
            return "Tree depth exceeds maximum allowed (\(maxAllowed))"
        case .nodeCountExceeded(let maxAllowed):
            return "Tree node count exceeds maximum allowed (\(maxAllowed))"
        case .unreachableNode(let key):
            return "Element '\(key)' is not reachable from the root"
        }
    }
}

// MARK: - UITree

/// Represents a complete UI tree parsed from json-render format
///
/// `UITree` is the parsed representation of LLM-generated UI in the json-render pattern.
/// It provides:
/// - Structural validation (valid keys, no cycles, true tree structure, children correctness)
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
///
/// ## Constraints
/// - The structure must be a true tree (each node has exactly one parent, except root)
/// - Maximum depth: 100 levels
/// - Maximum nodes: 10,000
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
    /// - Returns: A validated UITree containing only reachable nodes from root
    /// - Throws: `UITreeError` for structural or validation issues
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

        // Check node count limit
        if elements.count > TreeLimits.maxNodes {
            throw UITreeError.nodeCountExceeded(maxAllowed: TreeLimits.maxNodes)
        }

        // Parse all nodes
        var allNodes: [String: UINode] = [:]

        for (key, element) in elements {
            // Validate key
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.isEmpty {
                throw UITreeError.invalidNodeKey(key: key)
            }
            if key != trimmedKey {
                throw UITreeError.invalidNodeKey(key: key)
            }
            if allNodes[key] != nil {
                throw UITreeError.duplicateKey(key: key)
            }

            // Extract type
            guard let type = element["type"] as? String else {
                throw UITreeError.invalidStructure(reason: "Element '\(key)' missing 'type' field")
            }

            // Extract props - require it to be an object if present
            let propsData: Data
            if let propsValue = element["props"] {
                guard let props = propsValue as? [String: Any] else {
                    throw UITreeError.invalidStructure(
                        reason: "Element '\(key)' has invalid 'props' field (must be an object)"
                    )
                }
                do {
                    propsData = try JSONSerialization.data(withJSONObject: props)
                } catch {
                    throw UITreeError.invalidStructure(
                        reason: "Element '\(key)' has invalid props: \(error.localizedDescription)"
                    )
                }
            } else {
                // Default to empty object when props is absent
                propsData = Data("{}".utf8)
            }

            // Extract children - track whether field was present
            let childKeys: [String]
            let hadChildrenField: Bool
            if let children = element["children"] {
                hadChildrenField = true
                guard let childArray = children as? [String] else {
                    throw UITreeError.invalidStructure(
                        reason: "Element '\(key)' has invalid 'children' field (must be array of strings)"
                    )
                }
                childKeys = childArray
            } else {
                hadChildrenField = false
                childKeys = []
            }

            allNodes[key] = UINode(
                key: key,
                type: type,
                propsData: propsData,
                childKeys: childKeys,
                hadChildrenField: hadChildrenField
            )
        }

        // Validate root exists
        guard allNodes[rootKey] != nil else {
            throw UITreeError.rootNotFound(key: rootKey)
        }

        // Validate tree structure and get reachable nodes
        let reachableNodes = try validateAndPruneTree(rootKey: rootKey, allNodes: allNodes)

        // Create tree with only reachable nodes
        let tree = UITree(rootKey: rootKey, nodes: reachableNodes)

        // Validate against catalog if provided
        if let catalog {
            try tree.validate(with: catalog)
        }

        return tree
    }

    /// Validate tree structure and return only reachable nodes
    /// Uses iterative traversal to avoid stack overflow
    private static func validateAndPruneTree(
        rootKey: String,
        allNodes: [String: UINode]
    ) throws -> [String: UINode] {
        var reachableNodes: [String: UINode] = [:]
        var visited: Set<String> = []

        // Iterative DFS using explicit stack
        // Stack entries: (key, parentKey, depth, phase)
        // phase 0 = entering, phase 1 = exiting (after children processed)
        var stack: [(key: String, parentKey: String?, depth: Int, phase: Int)] = [(rootKey, nil, 0, 0)]
        var inStack: Set<String> = []

        while !stack.isEmpty {
            var entry = stack.removeLast()

            if entry.phase == 0 {
                // Entering phase
                let key = entry.key

                // Check if node exists
                guard let node = allNodes[key] else {
                    if let parent = entry.parentKey {
                        throw UITreeError.childNotFound(parentKey: parent, childKey: key)
                    } else {
                        throw UITreeError.rootNotFound(key: key)
                    }
                }

                // Check for cycle
                if inStack.contains(key) {
                    throw UITreeError.circularReference(key: key)
                }

                // Check for multiple parents (DAG detection)
                if visited.contains(key) {
                    throw UITreeError.multipleParents(key: key)
                }

                // Check depth limit
                if entry.depth > TreeLimits.maxDepth {
                    throw UITreeError.depthExceeded(maxAllowed: TreeLimits.maxDepth)
                }

                inStack.insert(key)
                reachableNodes[key] = node

                // Push exit phase
                entry.phase = 1
                stack.append(entry)

                // Push children in reverse order (so they're processed in order)
                for childKey in node.childKeys.reversed() {
                    stack.append((childKey, key, entry.depth + 1, 0))
                }
            } else {
                // Exiting phase
                inStack.remove(entry.key)
                visited.insert(entry.key)
            }
        }

        return reachableNodes
    }

    // MARK: - Validation

    /// Validate all nodes against a catalog
    ///
    /// Validates nodes in deterministic order (depth-first from root).
    ///
    /// - Parameter catalog: The catalog to validate against
    /// - Throws: `UITreeError` if any node fails validation
    public func validate(with catalog: UICatalog) throws {
        // Validate in deterministic order (depth-first from root)
        for node in allNodes() {
            // Check component type exists
            guard let definition = catalog.component(forType: node.type) else {
                throw UITreeError.unknownComponentType(key: node.key, type: node.type)
            }

            // Check children field is not present for leaf components
            // Per the prompt: "must omit the children field"
            if !definition.hasChildren && node.hadChildrenField {
                throw UITreeError.childrenNotAllowed(key: node.key, type: node.type)
            }

            // Validate props
            do {
                try catalog.validate(type: node.type, propsData: node.propsData)
            } catch let error as UIComponentValidationError {
                throw UITreeError.validationFailed(key: node.key, error: error)
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
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    /// Each node is visited exactly once.
    ///
    /// - Parameters:
    ///   - visitor: Closure called for each node with the node and its depth
    public func traverse(_ visitor: (UINode, Int) -> Void) {
        // Iterative DFS with explicit stack
        var stack: [(node: UINode, depth: Int)] = [(rootNode, 0)]

        while !stack.isEmpty {
            let (node, depth) = stack.removeLast()
            visitor(node, depth)

            // Push children in reverse order so they're visited in order
            let childNodes = children(of: node)
            for child in childNodes.reversed() {
                stack.append((child, depth + 1))
            }
        }
    }

    /// Get all nodes in depth-first order
    ///
    /// Each node appears exactly once (tree structure is enforced during parsing).
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
    /// - Throws: `UITreeError` for structural or validation issues
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
