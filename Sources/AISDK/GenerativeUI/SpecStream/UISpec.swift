//
//  UISpec.swift
//  AISDK
//
//  Complete UI specification combining elements (UITree) and state (UIState).
//  The full model that SpecStreamCompiler builds incrementally.
//

import Foundation

// MARK: - UISpec

/// A complete UI specification combining elements and state.
///
/// `UISpec` extends the concept of `UITree` (which holds element structure)
/// with a separated `UIState` dictionary. Props in elements can reference
/// state values via `$path` expressions.
///
/// ## Structure
/// ```json
/// {
///   "root": "main",
///   "elements": { ... },
///   "state": { "metrics": { "revenue": 12345 } }
/// }
/// ```
///
/// ## $path Resolution
/// Element props can reference state values:
/// ```json
/// { "value": { "$path": "/state/metrics/revenue" } }
/// ```
/// This resolves to `12345` at render time.
public struct UISpec: Sendable, Equatable {
    /// The root element key
    public let root: String

    /// UI element nodes (flat map)
    public let elements: [String: UINode]

    /// Separated state dictionary
    public let state: UIState

    /// Optional catalog version for compatibility checking
    public let catalogVersion: String?

    public init(
        root: String,
        elements: [String: UINode],
        state: UIState = UIState(),
        catalogVersion: String? = nil
    ) {
        self.root = root
        self.elements = elements
        self.state = state
        self.catalogVersion = catalogVersion
    }

    /// Create a UISpec from an existing UITree
    public init(tree: UITree, state: UIState = UIState(), catalogVersion: String? = nil) {
        self.root = tree.rootKey
        self.elements = tree.nodes
        self.state = state
        self.catalogVersion = catalogVersion
    }

    /// Convert to a UITree (drops state)
    public func toUITree() -> UITree {
        UITree(rootKey: root, nodes: elements)
    }
}
