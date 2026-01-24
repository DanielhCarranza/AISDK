//
//  UIComponentRegistry.swift
//  AISDK
//
//  Registry mapping element types to SwiftUI views
//  Provides action allowlisting for security
//

#if canImport(SwiftUI)
import Foundation
import SwiftUI

// MARK: - UIActionHandler

/// Handler for UI actions triggered by components
///
/// Actions are identified by name (e.g., "submit", "navigate", "dismiss").
/// The registry can filter actions through an allowlist for security.
public typealias UIActionHandler = @Sendable (String) -> Void

// MARK: - UIComponentRegistry

/// Registry mapping element types to SwiftUI views
///
/// `UIComponentRegistry` is the runtime mapping between component type names
/// (from `UITree` nodes) and their SwiftUI view implementations. It provides:
/// - Component registration with type-erased view builders
/// - Action allowlisting for security
/// - Default registry with Core 8 component views
///
/// ## Security
/// The registry includes action allowlisting to prevent LLM-generated UI from
/// triggering unauthorized actions. When actions are registered via `allowAction`,
/// only those actions will be passed through to the handler.
///
/// ## Usage
/// ```swift
/// // Use default registry
/// let registry = UIComponentRegistry.default
///
/// // Build a view for a UINode
/// let view = registry.build(
///     node: node,
///     tree: tree,
///     propsDecoder: decoder,
///     actionHandler: { action in print("Action: \(action)") }
/// )
/// ```
///
/// ## Custom Registry
/// ```swift
/// var registry = UIComponentRegistry()
///
/// // Register a custom component
/// registry.register("CustomCard") { node, tree, _, handler in
///     MyCustomCard(node: node, onAction: handler)
/// }
///
/// // Allow specific actions
/// registry.allowAction("submit")
/// registry.allowAction("navigate")
/// ```
public struct UIComponentRegistry: Sendable {
    /// Type-erased view builder that creates SwiftUI views from UINode data
    ///
    /// - Parameters:
    ///   - node: The UINode containing component type, key, and raw props data
    ///   - tree: The full UITree for accessing child nodes
    ///   - propsDecoder: JSONDecoder configured for props decoding
    ///   - handler: Action handler (already filtered through allowlist)
    /// - Returns: Type-erased SwiftUI view
    public typealias ViewBuilder = @Sendable (
        UINode,
        UITree,
        JSONDecoder,
        @escaping UIActionHandler
    ) -> AnyView

    /// Registered view builders by component type name
    private var builders: [String: ViewBuilder]

    /// Set of allowed action names (empty = allow all)
    private var allowedActions: Set<String>

    // MARK: - Initialization

    /// Creates an empty registry
    ///
    /// Use `register(_:builder:)` to add component view builders and
    /// `allowAction(_:)` to configure the action allowlist.
    public init() {
        self.builders = [:]
        self.allowedActions = []
    }

    // MARK: - Registration

    /// Register a view builder for a component type
    ///
    /// - Parameters:
    ///   - type: The component type identifier (e.g., "Text", "Button")
    ///   - builder: Closure that creates a SwiftUI view from node data
    public mutating func register<V: View>(
        _ type: String,
        builder: @escaping @Sendable (
            UINode,
            UITree,
            JSONDecoder,
            @escaping UIActionHandler
        ) -> V
    ) {
        builders[type] = { node, tree, decoder, handler in
            AnyView(builder(node, tree, decoder, handler))
        }
    }

    /// Allow an action to be triggered by components
    ///
    /// When any actions are registered, only those actions will be passed
    /// through to the action handler. If no actions are registered (empty set),
    /// all actions are allowed (pass-through mode).
    ///
    /// - Parameter action: The action name to allow
    public mutating func allowAction(_ action: String) {
        allowedActions.insert(action)
    }

    /// Allow multiple actions to be triggered by components
    ///
    /// - Parameter actions: Collection of action names to allow
    public mutating func allowActions<C: Collection>(_ actions: C) where C.Element == String {
        for action in actions {
            allowedActions.insert(action)
        }
    }

    /// Remove an action from the allowlist
    ///
    /// - Parameter action: The action name to remove
    public mutating func disallowAction(_ action: String) {
        allowedActions.remove(action)
    }

    /// Clear all allowed actions (reverts to pass-through mode)
    public mutating func clearAllowedActions() {
        allowedActions.removeAll()
    }

    /// Check if an action is allowed
    ///
    /// - Parameter action: The action name to check
    /// - Returns: True if the action is allowed (or if allowlist is empty)
    public func isActionAllowed(_ action: String) -> Bool {
        allowedActions.isEmpty || allowedActions.contains(action)
    }

    /// Get the set of currently allowed actions
    ///
    /// - Returns: Set of allowed action names (empty = all allowed)
    public var currentAllowedActions: Set<String> {
        allowedActions
    }

    // MARK: - View Building

    /// Build a SwiftUI view for a UINode
    ///
    /// - Parameters:
    ///   - node: The UINode to render
    ///   - tree: The UITree containing the node
    ///   - propsDecoder: JSONDecoder for decoding node props (defaults to snake_case)
    ///   - actionHandler: Handler for actions triggered by the component
    /// - Returns: A SwiftUI view for the node
    public func build(
        node: UINode,
        tree: UITree,
        propsDecoder: JSONDecoder = Self.defaultPropsDecoder,
        actionHandler: @escaping UIActionHandler
    ) -> AnyView {
        guard let builder = builders[node.type] else {
            return AnyView(UnknownComponentView(type: node.type))
        }

        // Capture allowedActions as value to avoid capturing self
        let allowedActionsCopy = allowedActions

        // Wrap action handler with security check
        let secureHandler: UIActionHandler = { action in
            let isAllowed = allowedActionsCopy.isEmpty || allowedActionsCopy.contains(action)
            guard isAllowed else {
                // Silently block disallowed actions in production
                return
            }
            actionHandler(action)
        }

        return builder(node, tree, propsDecoder, secureHandler)
    }

    /// Build views for all children of a node
    ///
    /// - Parameters:
    ///   - node: The parent node
    ///   - tree: The UITree containing the nodes
    ///   - propsDecoder: JSONDecoder for decoding node props
    ///   - actionHandler: Handler for actions triggered by children
    /// - Returns: Array of SwiftUI views for each child
    public func buildChildren(
        of node: UINode,
        tree: UITree,
        propsDecoder: JSONDecoder = Self.defaultPropsDecoder,
        actionHandler: @escaping UIActionHandler
    ) -> [AnyView] {
        tree.children(of: node).map { childNode in
            build(
                node: childNode,
                tree: tree,
                propsDecoder: propsDecoder,
                actionHandler: actionHandler
            )
        }
    }

    // MARK: - Lookup

    /// Check if a component type is registered
    ///
    /// - Parameter type: The component type identifier
    /// - Returns: True if a view builder is registered for this type
    public func hasComponent(_ type: String) -> Bool {
        builders[type] != nil
    }

    /// Get all registered component types
    ///
    /// - Returns: Sorted array of registered component type names
    public var registeredTypes: [String] {
        builders.keys.sorted()
    }

    // MARK: - Default Decoder

    /// Default JSONDecoder for props (snake_case conversion)
    public static var defaultPropsDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

// MARK: - Unknown Component View

/// View shown for unknown component types
private struct UnknownComponentView: View {
    let type: String

    var body: some View {
        Text("Unknown component: \(type)")
            .foregroundColor(.secondary)
            .italic()
    }
}

// MARK: - Default Registry

extension UIComponentRegistry {
    /// Default registry with Core 8 component views
    ///
    /// Includes view builders for:
    /// - **Text**: Display text content with optional styling
    /// - **Button**: Interactive button with action handling
    /// - **Card**: Container with optional title/subtitle
    /// - **Input**: Text input field (placeholder view)
    /// - **List**: Ordered/unordered list container
    /// - **Image**: Image display with async loading
    /// - **Stack**: Horizontal/vertical layout container
    /// - **Spacer**: Flexible space element
    ///
    /// The default registry starts with an empty action allowlist,
    /// meaning all actions are passed through. Configure security
    /// by calling `allowAction(_:)` after obtaining the registry.
    public static var `default`: UIComponentRegistry {
        var registry = UIComponentRegistry()

        // Register Core 8 component views
        registry.register("Text") { node, _, decoder, _ in
            GenerativeTextView(node: node, decoder: decoder)
        }

        registry.register("Button") { node, _, decoder, handler in
            GenerativeButtonView(node: node, decoder: decoder, onAction: handler)
        }

        // Capture registry as value for child-rendering components
        let registryCopy = registry

        registry.register("Card") { node, tree, decoder, handler in
            GenerativeCardView(
                node: node,
                tree: tree,
                registry: registryCopy,
                decoder: decoder,
                onAction: handler
            )
        }

        registry.register("Input") { node, _, decoder, _ in
            GenerativeInputView(node: node, decoder: decoder)
        }

        registry.register("List") { node, tree, decoder, handler in
            GenerativeListView(
                node: node,
                tree: tree,
                registry: registryCopy,
                decoder: decoder,
                onAction: handler
            )
        }

        registry.register("Image") { node, _, decoder, _ in
            GenerativeImageView(node: node, decoder: decoder)
        }

        registry.register("Stack") { node, tree, decoder, handler in
            GenerativeStackView(
                node: node,
                tree: tree,
                registry: registryCopy,
                decoder: decoder,
                onAction: handler
            )
        }

        registry.register("Spacer") { node, _, decoder, _ in
            GenerativeSpacerView(node: node, decoder: decoder)
        }

        return registry
    }
}

// MARK: - Core 8 SwiftUI Views

/// Internal view for Text component
private struct GenerativeTextView: View {
    let node: UINode
    let decoder: JSONDecoder

    var body: some View {
        let props = try? decoder.decode(TextComponentDefinition.Props.self, from: node.propsData)
        let content = props?.content ?? ""
        let style = props?.style

        textView(content: content, style: style)
            .accessibilityLabel(props?.accessibilityLabel ?? content)
            .accessibilityHint(props?.accessibilityHint ?? "")
    }

    @ViewBuilder
    private func textView(content: String, style: String?) -> some View {
        switch style {
        case "headline":
            Text(content).font(.headline)
        case "subheadline":
            Text(content).font(.subheadline)
        case "caption":
            Text(content).font(.caption)
        case "title":
            Text(content).font(.title)
        default:
            Text(content).font(.body)
        }
    }
}

/// Internal view for Button component
private struct GenerativeButtonView: View {
    let node: UINode
    let decoder: JSONDecoder
    let onAction: UIActionHandler

    var body: some View {
        let props = try? decoder.decode(ButtonComponentDefinition.Props.self, from: node.propsData)
        let title = props?.title ?? "Button"
        let action = props?.action ?? ""
        let disabled = props?.disabled ?? false

        Button(title) {
            onAction(action)
        }
        .disabled(disabled)
        .accessibilityLabel(props?.accessibilityLabel ?? title)
        .accessibilityHint(props?.accessibilityHint ?? "")
    }
}

/// Internal view for Card component
private struct GenerativeCardView: View {
    let node: UINode
    let tree: UITree
    let registry: UIComponentRegistry
    let decoder: JSONDecoder
    let onAction: UIActionHandler

    var body: some View {
        let props = try? decoder.decode(CardComponentDefinition.Props.self, from: node.propsData)
        let children = registry.buildChildren(of: node, tree: tree, propsDecoder: decoder, actionHandler: onAction)

        VStack(alignment: .leading, spacing: 8) {
            if let title = props?.title {
                Text(title)
                    .font(.headline)
            }

            if let subtitle = props?.subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ForEach(Array(children.enumerated()), id: \.offset) { _, childView in
                childView
            }
        }
        .padding()
        .background(cardBackground(style: props?.style))
        .cornerRadius(12)
        .accessibilityLabel(props?.accessibilityLabel ?? props?.title ?? "Card")
        .accessibilityHint(props?.accessibilityHint ?? "")
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func cardBackground(style: String?) -> some View {
        switch style {
        case "elevated":
            Color.white
                .shadow(radius: 4)
        case "outlined":
            Color.clear
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        case "filled":
            Color.secondary.opacity(0.1)
        default:
            Color.white
        }
    }
}

/// Internal view for Input component
private struct GenerativeInputView: View {
    let node: UINode
    let decoder: JSONDecoder

    @State private var text: String = ""

    var body: some View {
        let props = try? decoder.decode(InputComponentDefinition.Props.self, from: node.propsData)
        let label = props?.label ?? "Input"
        let placeholder = props?.placeholder ?? ""

        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
        .accessibilityLabel(props?.accessibilityLabel ?? label)
        .accessibilityHint(props?.accessibilityHint ?? "")
    }
}

/// Internal view for List component
private struct GenerativeListView: View {
    let node: UINode
    let tree: UITree
    let registry: UIComponentRegistry
    let decoder: JSONDecoder
    let onAction: UIActionHandler

    var body: some View {
        let props = try? decoder.decode(ListComponentDefinition.Props.self, from: node.propsData)
        let style = props?.style ?? .unordered
        let children = registry.buildChildren(of: node, tree: tree, propsDecoder: decoder, actionHandler: onAction)

        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(children.enumerated()), id: \.offset) { index, childView in
                HStack(alignment: .top, spacing: 8) {
                    listMarker(style: style, index: index)
                    childView
                }
            }
        }
        .accessibilityLabel(props?.accessibilityLabel ?? "List")
        .accessibilityHint(props?.accessibilityHint ?? "")
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func listMarker(style: UIListStyle, index: Int) -> some View {
        switch style {
        case .ordered:
            Text("\(index + 1).")
                .foregroundColor(.secondary)
        case .unordered:
            Text("\u{2022}")
                .foregroundColor(.secondary)
        case .plain:
            EmptyView()
        }
    }
}

/// Internal view for Image component
private struct GenerativeImageView: View {
    let node: UINode
    let decoder: JSONDecoder

    var body: some View {
        let props = try? decoder.decode(ImageComponentDefinition.Props.self, from: node.propsData)
        let urlString = props?.url ?? ""
        let alt = props?.alt ?? "Image"
        let width = props?.width
        let height = props?.height
        let contentMode = props?.contentMode

        AsyncImage(url: URL(string: urlString)) { phase in
            switch phase {
            case .empty:
                ProgressView()
            case .success(let image):
                imageView(image: image, contentMode: contentMode)
            case .failure:
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: width.map { CGFloat($0) }, height: height.map { CGFloat($0) })
        .accessibilityLabel(props?.accessibilityLabel ?? alt)
        .accessibilityHint(props?.accessibilityHint ?? "")
    }

    @ViewBuilder
    private func imageView(image: Image, contentMode: String?) -> some View {
        switch contentMode {
        case "fill":
            image.resizable().scaledToFill()
        case "stretch":
            image.resizable()
        default:
            image.resizable().scaledToFit()
        }
    }
}

/// Internal view for Stack component
private struct GenerativeStackView: View {
    let node: UINode
    let tree: UITree
    let registry: UIComponentRegistry
    let decoder: JSONDecoder
    let onAction: UIActionHandler

    var body: some View {
        let props = try? decoder.decode(StackComponentDefinition.Props.self, from: node.propsData)
        let direction = props?.direction ?? .vertical
        let spacing = props?.spacing ?? 8
        let alignment = props?.alignment ?? .center
        let children = registry.buildChildren(of: node, tree: tree, propsDecoder: decoder, actionHandler: onAction)

        Group {
            switch direction {
            case .horizontal:
                HStack(alignment: verticalAlignment(from: alignment), spacing: CGFloat(spacing)) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, childView in
                        childView
                    }
                }
            case .vertical:
                VStack(alignment: horizontalAlignment(from: alignment), spacing: CGFloat(spacing)) {
                    ForEach(Array(children.enumerated()), id: \.offset) { _, childView in
                        childView
                    }
                }
            }
        }
        .accessibilityLabel(props?.accessibilityLabel ?? (direction == .horizontal ? "Horizontal stack" : "Vertical stack"))
        .accessibilityHint(props?.accessibilityHint ?? "")
        .accessibilityElement(children: .contain)
    }

    private func horizontalAlignment(from alignment: StackAlignment) -> HorizontalAlignment {
        switch alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private func verticalAlignment(from alignment: StackAlignment) -> VerticalAlignment {
        switch alignment {
        case .leading:
            return .top
        case .center:
            return .center
        case .trailing:
            return .bottom
        }
    }
}

/// Internal view for Spacer component
private struct GenerativeSpacerView: View {
    let node: UINode
    let decoder: JSONDecoder

    var body: some View {
        let props = try? decoder.decode(SpacerComponentDefinition.Props.self, from: node.propsData)

        if let size = props?.size {
            Spacer()
                .frame(width: CGFloat(size), height: CGFloat(size))
        } else {
            Spacer()
        }
    }
}

#endif
