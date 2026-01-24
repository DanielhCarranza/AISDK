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

// MARK: - ChildViewBuilder

/// Closure for building child views within container components
///
/// Container components receive this closure to build their children,
/// ensuring the full registry is used (not an early snapshot).
public typealias ChildViewBuilder = @Sendable (UINode) -> AnyView

// MARK: - Accessibility Traits Helper

/// Maps string trait names to SwiftUI AccessibilityTraits
private func accessibilityTraits(from traits: [String]?) -> AccessibilityTraits {
    guard let traits else { return [] }
    var result: AccessibilityTraits = []
    for trait in traits {
        let normalized = trait.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "header":
            result.formUnion(.isHeader)
        case "link":
            result.formUnion(.isLink)
        case "button":
            result.formUnion(.isButton)
        case "image":
            result.formUnion(.isImage)
        case "statictext":
            result.formUnion(.isStaticText)
        case "selected":
            result.formUnion(.isSelected)
        case "summary":
            result.formUnion(.isSummaryElement)
        default:
            break
        }
    }
    return result
}

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
/// **Important**: For production use with LLM-generated UI, always configure
/// an explicit allowlist using `allowAction(_:)` or use `secureDefault` which
/// pre-populates the allowlist with standard actions.
///
/// ## Usage
/// ```swift
/// // Use secure default registry (recommended for production)
/// var registry = UIComponentRegistry.secureDefault
///
/// // Or use default registry and configure allowlist manually
/// var registry = UIComponentRegistry.default
/// registry.allowAction("submit")
/// registry.allowAction("navigate")
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
/// registry.register("CustomCard") { node, tree, _, handler, buildChild in
///     MyCustomCard(node: node, buildChild: buildChild)
/// }
///
/// // Allow specific actions
/// registry.allowAction("submit")
/// registry.allowAction("navigate")
/// ```
public struct UIComponentRegistry: @unchecked Sendable {
    /// Type-erased view builder that creates SwiftUI views from UINode data
    ///
    /// - Parameters:
    ///   - node: The UINode containing component type, key, and raw props data
    ///   - tree: The full UITree for accessing child nodes
    ///   - propsDecoder: JSONDecoder configured for props decoding
    ///   - handler: Action handler (already filtered through allowlist)
    ///   - buildChild: Closure to build child views (uses full registry)
    /// - Returns: Type-erased SwiftUI view
    public typealias ViewBuilder = @Sendable (
        UINode,
        UITree,
        JSONDecoder,
        @escaping UIActionHandler,
        @escaping ChildViewBuilder
    ) -> AnyView

    /// Registered view builders by component type name
    private var builders: [String: ViewBuilder]

    /// Set of allowed action names (empty = allow all in pass-through mode)
    private var allowedActions: Set<String>

    // MARK: - Initialization

    /// Creates an empty registry
    ///
    /// Use `register(_:builder:)` to add component view builders and
    /// `allowAction(_:)` to configure the action allowlist.
    ///
    /// - Note: By default, an empty allowlist means all actions pass through.
    ///   For production use with LLM-generated UI, always configure explicit
    ///   allowed actions or use `secureDefault`.
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
            @escaping UIActionHandler,
            @escaping ChildViewBuilder
        ) -> V
    ) {
        builders[type] = { node, tree, decoder, handler, buildChild in
            AnyView(builder(node, tree, decoder, handler, buildChild))
        }
    }

    /// Allow an action to be triggered by components
    ///
    /// When any actions are registered, only those actions will be passed
    /// through to the action handler. If no actions are registered (empty set),
    /// all actions are allowed (pass-through mode).
    ///
    /// - Parameter action: The action name to allow (trimmed of whitespace)
    public mutating func allowAction(_ action: String) {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        allowedActions.insert(trimmed)
    }

    /// Allow multiple actions to be triggered by components
    ///
    /// - Parameter actions: Collection of action names to allow
    public mutating func allowActions<C: Collection>(_ actions: C) where C.Element == String {
        for action in actions {
            allowAction(action)
        }
    }

    /// Remove an action from the allowlist
    ///
    /// - Parameter action: The action name to remove
    public mutating func disallowAction(_ action: String) {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        allowedActions.remove(trimmed)
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
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        return allowedActions.isEmpty || allowedActions.contains(trimmed)
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

        // Wrap action handler with security check (normalizes action names)
        let secureHandler: UIActionHandler = { action in
            let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                #if DEBUG
                print("[UIComponentRegistry] Ignored empty action")
                #endif
                return
            }
            let isAllowed = allowedActionsCopy.isEmpty || allowedActionsCopy.contains(trimmed)
            guard isAllowed else {
                #if DEBUG
                print("[UIComponentRegistry] Blocked action: \(trimmed)")
                #endif
                return
            }
            actionHandler(trimmed)
        }

        // Create child builder that uses THIS registry (not a snapshot)
        let childBuilder: ChildViewBuilder = { childNode in
            self.build(
                node: childNode,
                tree: tree,
                propsDecoder: propsDecoder,
                actionHandler: actionHandler
            )
        }

        return builder(node, tree, propsDecoder, secureHandler, childBuilder)
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
    ///
    /// - Note: For production use with LLM-generated UI, use `secureDefault`
    ///   or explicitly configure allowed actions.
    public static var `default`: UIComponentRegistry {
        var registry = UIComponentRegistry()
        registerCore8Components(in: &registry)
        return registry
    }

    /// Secure default registry with Core 8 component views and standard actions allowed
    ///
    /// This registry is pre-configured with the standard action allowlist:
    /// - submit
    /// - navigate
    /// - dismiss
    ///
    /// Use this for production deployments with LLM-generated UI.
    public static var secureDefault: UIComponentRegistry {
        var registry = UIComponentRegistry()
        registerCore8Components(in: &registry)
        registry.allowActions(["submit", "navigate", "dismiss"])
        return registry
    }

    /// Register all Core 8 component views in the registry
    private static func registerCore8Components(in registry: inout UIComponentRegistry) {
        // Container views receive buildChild closure to render children
        // using the full registry (avoiding early snapshot issues)

        registry.register("Text") { node, _, decoder, _, _ in
            GenerativeTextView(node: node, decoder: decoder)
        }

        registry.register("Button") { node, _, decoder, handler, _ in
            GenerativeButtonView(node: node, decoder: decoder, onAction: handler)
        }

        registry.register("Card") { node, tree, decoder, _, buildChild in
            GenerativeCardView(
                node: node,
                tree: tree,
                decoder: decoder,
                buildChild: buildChild
            )
        }

        registry.register("Input") { node, _, decoder, _, _ in
            GenerativeInputView(node: node, decoder: decoder)
        }

        registry.register("List") { node, tree, decoder, _, buildChild in
            GenerativeListView(
                node: node,
                tree: tree,
                decoder: decoder,
                buildChild: buildChild
            )
        }

        registry.register("Image") { node, _, decoder, _, _ in
            GenerativeImageView(node: node, decoder: decoder)
        }

        registry.register("Stack") { node, tree, decoder, _, buildChild in
            GenerativeStackView(
                node: node,
                tree: tree,
                decoder: decoder,
                buildChild: buildChild
            )
        }

        registry.register("Spacer") { node, _, decoder, _, _ in
            GenerativeSpacerView(node: node, decoder: decoder)
        }
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
            .accessibilityAddTraits(accessibilityTraits(from: props?.accessibilityTraits))
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
        let style = props?.style

        buttonView(title: title, action: action, style: style, disabled: disabled)
            .accessibilityLabel(props?.accessibilityLabel ?? title)
            .accessibilityHint(props?.accessibilityHint ?? "")
            .accessibilityAddTraits(accessibilityTraits(from: props?.accessibilityTraits))
    }

    @ViewBuilder
    private func buttonView(title: String, action: String, style: String?, disabled: Bool) -> some View {
        let button = Button(title) {
            onAction(action)
        }
        .disabled(disabled)

        // Apply style-specific modifiers
        switch style {
        case "primary":
            button.buttonStyle(.borderedProminent)
        case "destructive":
            button.foregroundColor(.red)
        case "secondary":
            button.foregroundColor(.secondary)
        case "plain":
            button.buttonStyle(.plain)
        default:
            button
        }
    }
}

/// Helper struct to make UINode usable as ForEach ID
private struct IdentifiedNode: Identifiable {
    let node: UINode
    var id: String { node.key }
}

/// Internal view for Card component
private struct GenerativeCardView: View {
    let node: UINode
    let tree: UITree
    let decoder: JSONDecoder
    let buildChild: ChildViewBuilder

    var body: some View {
        let props = try? decoder.decode(CardComponentDefinition.Props.self, from: node.propsData)
        let childNodes = tree.children(of: node).map { IdentifiedNode(node: $0) }

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

            ForEach(childNodes) { child in
                buildChild(child.node)
            }
        }
        .padding()
        .background(cardBackground(style: props?.style))
        .cornerRadius(12)
        .accessibilityLabel(props?.accessibilityLabel ?? props?.title ?? "Card")
        .accessibilityHint(props?.accessibilityHint ?? "")
        .accessibilityAddTraits(accessibilityTraits(from: props?.accessibilityTraits))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func cardBackground(style: String?) -> some View {
        switch style {
        case "elevated":
            Color.primary.opacity(0.05)
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
            Color.primary.opacity(0.05)
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
        let inputType = props?.type ?? .text

        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            inputField(placeholder: placeholder, inputType: inputType)
        }
        .accessibilityLabel(props?.accessibilityLabel ?? label)
        .accessibilityHint(props?.accessibilityHint ?? "")
        .accessibilityAddTraits(accessibilityTraits(from: props?.accessibilityTraits))
    }

    @ViewBuilder
    private func inputField(placeholder: String, inputType: InputType) -> some View {
        switch inputType {
        case .password:
            SecureField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .textContentType(.password)
                #endif
        case .email:
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocapitalization(.none)
                #endif
        case .number:
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        case .text:
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// Internal view for List component
private struct GenerativeListView: View {
    let node: UINode
    let tree: UITree
    let decoder: JSONDecoder
    let buildChild: ChildViewBuilder

    var body: some View {
        let props = try? decoder.decode(ListComponentDefinition.Props.self, from: node.propsData)
        let style = props?.style ?? .unordered
        let childNodes = tree.children(of: node)

        VStack(alignment: .leading, spacing: style == .plain ? 0 : 4) {
            ForEach(Array(childNodes.enumerated()), id: \.element.key) { index, childNode in
                if style == .plain {
                    buildChild(childNode)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        listMarker(style: style, index: index)
                        buildChild(childNode)
                    }
                }
            }
        }
        .accessibilityLabel(props?.accessibilityLabel ?? "List")
        .accessibilityHint(props?.accessibilityHint ?? "")
        .accessibilityAddTraits(accessibilityTraits(from: props?.accessibilityTraits))
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

        Group {
            if let url = URL(string: urlString), !urlString.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        imageView(image: image, contentMode: contentMode, hasFrame: width != nil || height != nil)
                    case .failure:
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: width.map { CGFloat($0) }, height: height.map { CGFloat($0) })
        .accessibilityLabel(props?.accessibilityLabel ?? alt)
        .accessibilityHint(props?.accessibilityHint ?? "")
        .accessibilityAddTraits(accessibilityTraits(from: props?.accessibilityTraits))
    }

    @ViewBuilder
    private func imageView(image: Image, contentMode: String?, hasFrame: Bool) -> some View {
        switch contentMode {
        case "fill":
            if hasFrame {
                image.resizable().scaledToFill().clipped()
            } else {
                image.resizable().scaledToFill()
            }
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
    let decoder: JSONDecoder
    let buildChild: ChildViewBuilder

    var body: some View {
        let props = try? decoder.decode(StackComponentDefinition.Props.self, from: node.propsData)
        let direction = props?.direction ?? .vertical
        let spacing = props?.spacing ?? 8
        let alignment = props?.alignment ?? .center
        let childNodes = tree.children(of: node)

        Group {
            switch direction {
            case .horizontal:
                HStack(alignment: verticalAlignment(from: alignment), spacing: CGFloat(spacing)) {
                    ForEach(childNodes, id: \.key) { childNode in
                        buildChild(childNode)
                    }
                }
            case .vertical:
                VStack(alignment: horizontalAlignment(from: alignment), spacing: CGFloat(spacing)) {
                    ForEach(childNodes, id: \.key) { childNode in
                        buildChild(childNode)
                    }
                }
            }
        }
        .accessibilityLabel(props?.accessibilityLabel ?? (direction == .horizontal ? "Horizontal stack" : "Vertical stack"))
        .accessibilityHint(props?.accessibilityHint ?? "")
        .accessibilityAddTraits(accessibilityTraits(from: props?.accessibilityTraits))
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
            // Fixed-size spacer using Color.clear for predictable sizing
            Color.clear
                .frame(width: CGFloat(size), height: CGFloat(size))
                .accessibilityHidden(true)
        } else {
            // Flexible spacer
            Spacer()
                .accessibilityHidden(true)
        }
    }
}

#endif
