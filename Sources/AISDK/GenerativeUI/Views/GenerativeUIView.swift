//
//  GenerativeUIView.swift
//  AISDK
//
//  Main SwiftUI view for rendering generative UI from UITree data
//  Implements the json-render pattern for LLM-generated interfaces
//

#if canImport(SwiftUI)
import Foundation
import SwiftUI

// MARK: - GenerativeUIView

/// Main SwiftUI view for rendering LLM-generated UI from a UITree
///
/// `GenerativeUIView` is the top-level view that renders a complete `UITree`
/// structure into native SwiftUI views. It connects the json-render pattern
/// to the SwiftUI view hierarchy.
///
/// ## Features
/// - Renders UITree nodes using a UIComponentRegistry
/// - Provides action handling for interactive components
/// - Supports custom registries for extended component sets
/// - Handles loading and error states gracefully
/// - Accessibility-first design with VoiceOver support
///
/// ## Basic Usage
/// ```swift
/// let tree = try UITree.parse(from: jsonData)
/// GenerativeUIView(tree: tree) { action in
///     print("Action triggered: \(action)")
/// }
/// ```
///
/// ## With Custom Registry
/// ```swift
/// var registry = UIComponentRegistry.secureDefault
/// registry.register("CustomWidget") { node, tree, decoder, handler, buildChild in
///     MyCustomWidget(node: node)
/// }
///
/// GenerativeUIView(tree: tree, registry: registry) { action in
///     handleAction(action)
/// }
/// ```
///
/// ## Security
/// For production use with LLM-generated UI, use `UIComponentRegistry.secureDefault`
/// or configure explicit action allowlists to prevent unauthorized actions.
public struct GenerativeUIView: View {
    /// The UITree to render
    private let tree: UITree

    /// The registry to use for component lookup
    private let registry: UIComponentRegistry

    /// Handler for actions triggered by interactive components
    private let onAction: UIActionHandler

    /// JSONDecoder for props decoding
    private let propsDecoder: JSONDecoder

    // MARK: - Initialization

    /// Creates a GenerativeUIView with the default registry
    ///
    /// - Parameters:
    ///   - tree: The UITree to render
    ///   - onAction: Handler called when interactive components trigger actions
    public init(
        tree: UITree,
        onAction: @escaping UIActionHandler
    ) {
        self.tree = tree
        self.registry = .default
        self.onAction = onAction
        self.propsDecoder = UIComponentRegistry.defaultPropsDecoder
    }

    /// Creates a GenerativeUIView with a custom registry
    ///
    /// - Parameters:
    ///   - tree: The UITree to render
    ///   - registry: Custom registry for component lookup
    ///   - onAction: Handler called when interactive components trigger actions
    public init(
        tree: UITree,
        registry: UIComponentRegistry,
        onAction: @escaping UIActionHandler
    ) {
        self.tree = tree
        self.registry = registry
        self.onAction = onAction
        self.propsDecoder = UIComponentRegistry.defaultPropsDecoder
    }

    /// Creates a GenerativeUIView with a custom registry and decoder
    ///
    /// - Parameters:
    ///   - tree: The UITree to render
    ///   - registry: Custom registry for component lookup
    ///   - propsDecoder: JSONDecoder for props decoding
    ///   - onAction: Handler called when interactive components trigger actions
    public init(
        tree: UITree,
        registry: UIComponentRegistry,
        propsDecoder: JSONDecoder,
        onAction: @escaping UIActionHandler
    ) {
        self.tree = tree
        self.registry = registry
        self.onAction = onAction
        self.propsDecoder = propsDecoder
    }

    // MARK: - Body

    public var body: some View {
        registry.build(
            node: tree.rootNode,
            tree: tree,
            propsDecoder: propsDecoder,
            actionHandler: onAction
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Convenience Initializers

extension GenerativeUIView {
    /// Creates a GenerativeUIView using the secure default registry
    ///
    /// The secure default registry includes:
    /// - All Core 8 component views
    /// - Pre-configured action allowlist (submit, navigate, dismiss)
    ///
    /// This is the recommended initializer for production use with LLM-generated UI.
    ///
    /// - Parameters:
    ///   - tree: The UITree to render
    ///   - onAction: Handler called when interactive components trigger actions
    /// - Returns: A GenerativeUIView configured with secure defaults
    public static func secure(
        tree: UITree,
        onAction: @escaping UIActionHandler
    ) -> GenerativeUIView {
        GenerativeUIView(
            tree: tree,
            registry: .secureDefault,
            onAction: onAction
        )
    }
}

// MARK: - GenerativeUITreeView

/// A view that renders a UITree with loading and error state handling
///
/// `GenerativeUITreeView` wraps `GenerativeUIView` with additional state
/// handling for async tree loading scenarios. It provides built-in views
/// for loading and error states.
///
/// ## Usage with Async Loading
/// ```swift
/// struct ContentView: View {
///     @State private var tree: UITree?
///     @State private var error: Error?
///     @State private var isLoading = false
///
///     var body: some View {
///         GenerativeUITreeView(
///             tree: tree,
///             isLoading: isLoading,
///             error: error
///         ) { action in
///             handleAction(action)
///         }
///     }
/// }
/// ```
public struct GenerativeUITreeView: View {
    /// The UITree to render (nil if not yet loaded)
    private let tree: UITree?

    /// Whether the tree is currently loading
    private let isLoading: Bool

    /// Error that occurred during loading
    private let error: Error?

    /// The registry to use for component lookup
    private let registry: UIComponentRegistry

    /// Handler for actions triggered by interactive components
    private let onAction: UIActionHandler

    // MARK: - Initialization

    /// Creates a GenerativeUITreeView with optional tree and state
    ///
    /// - Parameters:
    ///   - tree: The UITree to render (nil if not loaded)
    ///   - isLoading: Whether loading is in progress
    ///   - error: Error from loading (if any)
    ///   - registry: Registry for component lookup (defaults to secureDefault)
    ///   - onAction: Handler for component actions
    public init(
        tree: UITree?,
        isLoading: Bool = false,
        error: Error? = nil,
        registry: UIComponentRegistry = .secureDefault,
        onAction: @escaping UIActionHandler
    ) {
        self.tree = tree
        self.isLoading = isLoading
        self.error = error
        self.registry = registry
        self.onAction = onAction
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if let tree {
                GenerativeUIView(
                    tree: tree,
                    registry: registry,
                    onAction: onAction
                )
            } else if isLoading {
                loadingView
            } else if let error {
                errorView(error)
            } else {
                emptyView
            }
        }
    }

    // MARK: - State Views

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Loading UI...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Loading generative UI")
    }

    @ViewBuilder
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Failed to load UI")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Error loading generative UI: \(error.localizedDescription)")
    }

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.dashed")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("No UI to display")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("No generative UI content")
    }
}

// MARK: - Preview Support

#if DEBUG
/// Preview-friendly wrapper for GenerativeUIView
///
/// This extension provides sample data for SwiftUI previews.
extension GenerativeUIView {
    /// Creates a sample GenerativeUIView for previews
    static var preview: some View {
        let json = """
        {
          "root": "main",
          "elements": {
            "main": {
              "type": "Stack",
              "props": { "direction": "vertical", "spacing": 16 },
              "children": ["title", "description", "button"]
            },
            "title": {
              "type": "Text",
              "props": { "content": "Welcome to Generative UI", "style": "headline" }
            },
            "description": {
              "type": "Text",
              "props": { "content": "This UI was generated from JSON using the json-render pattern." }
            },
            "button": {
              "type": "Button",
              "props": { "title": "Get Started", "action": "submit", "style": "primary" }
            }
          }
        }
        """

        if let tree = try? UITree.parse(from: json) {
            return AnyView(
                GenerativeUIView(tree: tree) { action in
                    print("Preview action: \(action)")
                }
                .padding()
            )
        } else {
            return AnyView(Text("Failed to parse preview tree"))
        }
    }
}
#endif

#endif
