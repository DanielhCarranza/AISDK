//
//  GenerativeUIView.swift
//  AISDK
//
//  Main SwiftUI view for rendering generative UI from UITree data
//  Implements the json-render pattern for LegacyLLM-generated interfaces
//

#if canImport(SwiftUI)
import Foundation
import SwiftUI

// MARK: - PropsDecoderConfiguration

/// Configuration for props decoding to avoid storing non-Sendable JSONDecoder
public struct PropsDecoderConfiguration: Sendable {
    /// Key decoding strategy
    public enum KeyStrategy: Sendable {
        case useDefaultKeys
        case convertFromSnakeCase
    }

    /// The key decoding strategy to use
    public let keyStrategy: KeyStrategy

    /// Default configuration using snake_case conversion
    public static let `default` = PropsDecoderConfiguration(keyStrategy: .convertFromSnakeCase)

    public init(keyStrategy: KeyStrategy) {
        self.keyStrategy = keyStrategy
    }

    /// Creates a JSONDecoder with this configuration
    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        switch keyStrategy {
        case .useDefaultKeys:
            decoder.keyDecodingStrategy = .useDefaultKeys
        case .convertFromSnakeCase:
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        return decoder
    }
}

// MARK: - GenerativeUIView

/// Main SwiftUI view for rendering LegacyLLM-generated UI from a UITree
///
/// `GenerativeUIView` is the top-level view that renders a complete `UITree`
/// structure into native SwiftUI views. It connects the json-render pattern
/// to the SwiftUI view hierarchy.
///
/// ## Features
/// - Renders UITree nodes using a UIComponentRegistry
/// - Provides action handling for interactive components
/// - Supports custom registries for extended component sets
/// - Accessibility-first design with VoiceOver support
///
/// ## Basic Usage
/// ```swift
/// let tree = try UITree.parse(from: jsonData)
/// GenerativeUIView.secure(tree: tree) { action in
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
/// The default initializer uses `UIComponentRegistry.default` which allows all
/// actions (pass-through mode). For production use with LegacyLLM-generated UI, use
/// `GenerativeUIView.secure(tree:onAction:)` or pass `UIComponentRegistry.secureDefault`
/// to prevent unauthorized actions.
///
/// - Note: For async loading with loading/error states, use `GenerativeUITreeView` instead.
public struct GenerativeUIView: View, Sendable {
    /// The UITree to render
    private let tree: UITree

    /// The registry to use for component lookup
    private let registry: UIComponentRegistry

    /// Handler for actions triggered by interactive components
    private let onAction: UIActionHandler

    /// Props decoder configuration (Sendable-safe)
    private let decoderConfig: PropsDecoderConfiguration

    // MARK: - Initialization

    /// Creates a GenerativeUIView with the default registry
    ///
    /// - Warning: The default registry allows all actions (pass-through mode).
    ///   For production use with LegacyLLM-generated UI, use `GenerativeUIView.secure(tree:onAction:)`
    ///   or pass `UIComponentRegistry.secureDefault` to prevent unauthorized actions.
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
        self.decoderConfig = .default
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
        self.decoderConfig = .default
    }

    /// Creates a GenerativeUIView with a custom registry and decoder configuration
    ///
    /// - Parameters:
    ///   - tree: The UITree to render
    ///   - registry: Custom registry for component lookup
    ///   - decoderConfig: Configuration for props decoding
    ///   - onAction: Handler called when interactive components trigger actions
    public init(
        tree: UITree,
        registry: UIComponentRegistry,
        decoderConfig: PropsDecoderConfiguration,
        onAction: @escaping UIActionHandler
    ) {
        self.tree = tree
        self.registry = registry
        self.onAction = onAction
        self.decoderConfig = decoderConfig
    }

    // MARK: - Body

    public var body: some View {
        registry.build(
            node: tree.rootNode,
            tree: tree,
            propsDecoder: decoderConfig.makeDecoder(),
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
    /// This is the recommended initializer for production use with LegacyLLM-generated UI.
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
public struct GenerativeUITreeView: View, Sendable {
    /// The UITree to render (nil if not yet loaded)
    private let tree: UITree?

    /// Whether the tree is currently loading
    private let isLoading: Bool

    /// Error that occurred during loading
    private let error: (any Error)?

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
        error: (any Error)? = nil,
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
            } else if error != nil {
                errorView
            } else {
                emptyView
            }
        }
        .accessibilityElement(children: .contain)
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
    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Failed to load UI")
                .font(.headline)

            #if DEBUG
            if let error {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Error loading generative UI")
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
                GenerativeUIView.secure(tree: tree) { action in
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
