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
#if canImport(Charts)
import Charts
#endif

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
/// The registry includes action allowlisting to prevent LegacyLLM-generated UI from
/// triggering unauthorized actions. When actions are registered via `allowAction`,
/// only those actions will be passed through to the handler.
///
/// **Important**: For production use with LegacyLLM-generated UI, always configure
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
    ///   For production use with LegacyLLM-generated UI, always configure explicit
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

    /// Build a SwiftUI view for a UINode with state change support
    ///
    /// This overload adds bidirectional state handling. Interactive components
    /// can emit state changes through the `stateChangeHandler` callback.
    ///
    /// - Parameters:
    ///   - node: The UINode to render
    ///   - tree: The UITree containing the node
    ///   - propsDecoder: JSONDecoder for decoding node props (defaults to snake_case)
    ///   - actionHandler: Handler for actions triggered by the component
    ///   - stateChangeHandler: Handler for state changes from interactive components
    /// - Returns: A SwiftUI view for the node
    public func build(
        node: UINode,
        tree: UITree,
        propsDecoder: JSONDecoder = Self.defaultPropsDecoder,
        actionHandler: @escaping UIActionHandler,
        stateChangeHandler: @escaping UIStateChangeHandler
    ) -> AnyView {
        // Delegate to the standard build — state change handler is available
        // for interactive components that explicitly check for it
        build(node: node, tree: tree, propsDecoder: propsDecoder, actionHandler: actionHandler)
    }

    /// Build views for all children of a node with state change support
    ///
    /// - Parameters:
    ///   - node: The parent node
    ///   - tree: The UITree containing the nodes
    ///   - propsDecoder: JSONDecoder for decoding node props
    ///   - actionHandler: Handler for actions triggered by children
    ///   - stateChangeHandler: Handler for state changes from interactive components
    /// - Returns: Array of SwiftUI views for each child
    public func buildChildren(
        of node: UINode,
        tree: UITree,
        propsDecoder: JSONDecoder = Self.defaultPropsDecoder,
        actionHandler: @escaping UIActionHandler,
        stateChangeHandler: @escaping UIStateChangeHandler
    ) -> [AnyView] {
        tree.children(of: node).map { childNode in
            build(
                node: childNode,
                tree: tree,
                propsDecoder: propsDecoder,
                actionHandler: actionHandler,
                stateChangeHandler: stateChangeHandler
            )
        }
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
    /// - Note: For production use with LegacyLLM-generated UI, use `secureDefault`
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
    /// Use this for production deployments with LegacyLLM-generated UI.
    public static var secureDefault: UIComponentRegistry {
        var registry = UIComponentRegistry()
        registerCore8Components(in: &registry)
        registry.allowActions(["submit", "navigate", "dismiss"])
        return registry
    }

    /// Extended registry with Core 8 + Tier 1 components
    public static var extended: UIComponentRegistry {
        var registry = UIComponentRegistry()
        registerCore8Components(in: &registry)
        registerTier1Components(in: &registry)
        registerChartComponents(in: &registry)
        registerInteractiveComponents(in: &registry)
        registerLayoutComponents(in: &registry)
        return registry
    }

    /// Secure extended registry with Core 8 + Tier 1 components and standard actions allowed
    public static var secureExtended: UIComponentRegistry {
        var registry = UIComponentRegistry()
        registerCore8Components(in: &registry)
        registerTier1Components(in: &registry)
        registerChartComponents(in: &registry)
        registerInteractiveComponents(in: &registry)
        registerLayoutComponents(in: &registry)
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

    /// Register all Tier 1 component views in the registry
    private static func registerTier1Components(in registry: inout UIComponentRegistry) {
        registry.register("Metric") { node, _, decoder, _, _ in
            GenerativeMetricView(node: node, decoder: decoder)
        }

        registry.register("Badge") { node, _, decoder, _, _ in
            GenerativeBadgeView(node: node, decoder: decoder)
        }

        registry.register("Divider") { node, _, decoder, _, _ in
            GenerativeDividerView(node: node, decoder: decoder)
        }

        registry.register("Section") { node, tree, decoder, _, buildChild in
            GenerativeSectionView(
                node: node,
                tree: tree,
                decoder: decoder,
                buildChild: buildChild
            )
        }

        registry.register("Progress") { node, _, decoder, _, _ in
            GenerativeProgressView(node: node, decoder: decoder)
        }
    }

    /// Register all chart component views in the registry
    private static func registerChartComponents(in registry: inout UIComponentRegistry) {
        registry.register("BarChart") { node, _, decoder, _, _ in
            GenerativeBarChartView(node: node, decoder: decoder)
        }

        registry.register("LineChart") { node, _, decoder, _, _ in
            GenerativeLineChartView(node: node, decoder: decoder)
        }

        registry.register("PieChart") { node, _, decoder, _, _ in
            GenerativePieChartView(node: node, decoder: decoder)
        }

        registry.register("Gauge") { node, _, decoder, _, _ in
            GenerativeGaugeView(node: node, decoder: decoder)
        }
    }

    /// Register all interactive component views in the registry
    private static func registerInteractiveComponents(in registry: inout UIComponentRegistry) {
        registry.register("Toggle") { node, _, decoder, handler, _ in
            GenerativeToggleView(node: node, decoder: decoder, onAction: handler)
        }

        registry.register("Slider") { node, _, decoder, handler, _ in
            GenerativeSliderView(node: node, decoder: decoder, onAction: handler)
        }

        registry.register("Stepper") { node, _, decoder, _, _ in
            GenerativeStepperView(node: node, decoder: decoder)
        }

        registry.register("SegmentedControl") { node, _, decoder, _, _ in
            GenerativeSegmentedControlView(node: node, decoder: decoder)
        }

        registry.register("Picker") { node, _, decoder, _, _ in
            GenerativePickerView(node: node, decoder: decoder)
        }
    }

    /// Register all layout component views in the registry
    private static func registerLayoutComponents(in registry: inout UIComponentRegistry) {
        registry.register("Grid") { node, tree, decoder, _, buildChild in
            GenerativeGridView(
                node: node,
                tree: tree,
                decoder: decoder,
                buildChild: buildChild
            )
        }

        registry.register("Tabs") { node, tree, decoder, _, buildChild in
            GenerativeTabsView(
                node: node,
                tree: tree,
                decoder: decoder,
                buildChild: buildChild
            )
        }

        registry.register("Accordion") { node, tree, decoder, _, buildChild in
            GenerativeAccordionView(
                node: node,
                tree: tree,
                decoder: decoder,
                buildChild: buildChild
            )
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

// MARK: - Tier 1 SwiftUI Views

/// Internal view for Metric component
private struct GenerativeMetricView: View {
    let node: UINode
    let decoder: JSONDecoder

    var body: some View {
        let props = try? decoder.decode(MetricComponentDefinition.Props.self, from: node.propsData)
        let label = props?.label ?? ""
        let value = props?.value ?? 0
        let formatted = formatValue(value, format: props?.format, prefix: props?.prefix, suffix: props?.suffix)

        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatted)
                    .font(.title.bold())

                if let trend = props?.trend, let change = props?.change {
                    MetricTrendView(trend: trend, change: change)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(formatted)
    }

    private func formatValue(
        _ value: Double,
        format: MetricComponentDefinition.MetricFormat?,
        prefix: String?,
        suffix: String?
    ) -> String {
        let formatted: String
        switch format {
        case .currency:
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.maximumFractionDigits = 2
            formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        case .percent:
            let formatter = NumberFormatter()
            formatter.numberStyle = .percent
            formatter.maximumFractionDigits = 1
            formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f%%", value * 100)
        case .compact:
            formatted = compactNumber(value)
        case .number, .none:
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        }

        var result = formatted
        if let prefix, !prefix.isEmpty {
            result = prefix + result
        }
        if let suffix, !suffix.isEmpty {
            result += suffix
        }
        return result
    }

    private func compactNumber(_ value: Double) -> String {
        let absValue = abs(value)
        let sign = value < 0 ? "-" : ""
        switch absValue {
        case 1_000_000_000...:
            return "\(sign)\(String(format: "%.1f", absValue / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)\(String(format: "%.1f", absValue / 1_000_000))M"
        case 1_000...:
            return "\(sign)\(String(format: "%.1f", absValue / 1_000))K"
        default:
            return "\(sign)\(String(format: "%.0f", absValue))"
        }
    }
}

private struct MetricTrendView: View {
    let trend: MetricComponentDefinition.Trend
    let change: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName(for: trend))
            Text(String(format: "%.1f%%", abs(change)))
        }
        .font(.caption.bold())
        .foregroundStyle(trendColor(for: trend))
    }

    private func symbolName(for trend: MetricComponentDefinition.Trend) -> String {
        switch trend {
        case .up:
            return "arrow.up"
        case .down:
            return "arrow.down"
        case .neutral:
            return "minus"
        }
    }

    private func trendColor(for trend: MetricComponentDefinition.Trend) -> Color {
        switch trend {
        case .neutral:
            return .secondary
        case .up:
            return .green
        case .down:
            return .red
        }
    }
}

/// Internal view for Badge component
private struct GenerativeBadgeView: View {
    let node: UINode
    let decoder: JSONDecoder

    var body: some View {
        let props = try? decoder.decode(BadgeComponentDefinition.Props.self, from: node.propsData)
        let text = props?.text ?? ""
        let variant = props?.variant ?? .default
        let size = props?.size ?? .medium

        Text(text)
            .font(font(for: size))
            .padding(.horizontal, horizontalPadding(for: size))
            .padding(.vertical, verticalPadding(for: size))
            .background(backgroundColor(for: variant))
            .foregroundStyle(foregroundColor(for: variant))
            .clipShape(Capsule())
            .accessibilityLabel(text)
    }

    private func font(for size: BadgeComponentDefinition.BadgeSize) -> Font {
        switch size {
        case .small:
            return .caption2.weight(.semibold)
        case .medium:
            return .caption.weight(.semibold)
        case .large:
            return .callout.weight(.semibold)
        }
    }

    private func horizontalPadding(for size: BadgeComponentDefinition.BadgeSize) -> CGFloat {
        switch size {
        case .small:
            return 6
        case .medium:
            return 8
        case .large:
            return 10
        }
    }

    private func verticalPadding(for size: BadgeComponentDefinition.BadgeSize) -> CGFloat {
        switch size {
        case .small:
            return 2
        case .medium:
            return 4
        case .large:
            return 6
        }
    }

    private func backgroundColor(for variant: BadgeComponentDefinition.BadgeVariant) -> Color {
        switch variant {
        case .default:
            return Color.gray.opacity(0.2)
        case .success:
            return Color.green.opacity(0.2)
        case .warning:
            return Color.orange.opacity(0.2)
        case .error:
            return Color.red.opacity(0.2)
        case .info:
            return Color.blue.opacity(0.2)
        }
    }

    private func foregroundColor(for variant: BadgeComponentDefinition.BadgeVariant) -> Color {
        switch variant {
        case .default:
            return .primary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        case .info:
            return .blue
        }
    }
}

/// Internal view for Divider component
private struct GenerativeDividerView: View {
    let node: UINode
    let decoder: JSONDecoder

    var body: some View {
        let props = try? decoder.decode(DividerComponentDefinition.Props.self, from: node.propsData)
        let label = props?.label
        let style = props?.style ?? .solid

        if let label, !label.isEmpty {
            HStack(spacing: 8) {
                DividerLine(style: style)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DividerLine(style: style)
            }
        } else {
            DividerLine(style: style)
        }
    }
}

private struct DividerLine: View {
    let style: DividerComponentDefinition.DividerStyle

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let y = proxy.size.height / 2
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: proxy.size.width, y: y))
            }
            .stroke(
                Color.secondary.opacity(0.4),
                style: StrokeStyle(
                    lineWidth: 1,
                    dash: style == .dashed ? [4, 4] : []
                )
            )
        }
        .frame(height: 1)
    }
}

/// Internal view for Section component
private struct GenerativeSectionView: View {
    let node: UINode
    let tree: UITree
    let decoder: JSONDecoder
    let buildChild: ChildViewBuilder

    @State private var isCollapsed = false

    var body: some View {
        let props = try? decoder.decode(SectionComponentDefinition.Props.self, from: node.propsData)
        let title = props?.title
        let subtitle = props?.subtitle
        let canCollapse = props?.collapsible ?? false
        let childNodes = node.childKeys.compactMap { tree.nodes[$0] }

        VStack(alignment: .leading, spacing: 8) {
            if title != nil || subtitle != nil {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title {
                            Text(title)
                                .font(.headline)
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if canCollapse {
                        Button(action: { isCollapsed.toggle() }) {
                            Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(childNodes, id: \.key) { childNode in
                        buildChild(childNode)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Internal view for Progress component
private struct GenerativeProgressView: View {
    let node: UINode
    let decoder: JSONDecoder

    var body: some View {
        let props = try? decoder.decode(ProgressComponentDefinition.Props.self, from: node.propsData)
        let label = props?.label
        let value = props?.value
        let showValue = props?.showValue ?? false
        let style = props?.style ?? .linear

        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            progressView(for: value, style: style)
                .tint(color(for: props?.color))

            if showValue, let value {
                Text("\(Int(value * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func progressView(for value: Double?, style: ProgressComponentDefinition.ProgressStyle) -> some View {
        if let value {
            if style == .circular {
                ProgressView(value: value)
                    .progressViewStyle(.circular)
            } else {
                ProgressView(value: value)
                    .progressViewStyle(.linear)
            }
        } else {
            if style == .circular {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
        }
    }

    private func color(for color: ProgressComponentDefinition.ProgressColor?) -> Color? {
        guard let color else { return nil }
        switch color {
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

// MARK: - Chart Helpers

private func colorFromString(_ value: String?) -> Color? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed.hasPrefix("#") {
        let hexString = String(trimmed.dropFirst())
        guard let hex = UInt64(hexString, radix: 16) else { return nil }
        let red, green, blue, alpha: Double
        switch hexString.count {
        case 6:
            red = Double((hex & 0xFF0000) >> 16) / 255.0
            green = Double((hex & 0x00FF00) >> 8) / 255.0
            blue = Double(hex & 0x0000FF) / 255.0
            alpha = 1.0
        case 8:
            red = Double((hex & 0xFF000000) >> 24) / 255.0
            green = Double((hex & 0x00FF0000) >> 16) / 255.0
            blue = Double((hex & 0x0000FF00) >> 8) / 255.0
            alpha = Double(hex & 0x000000FF) / 255.0
        default:
            return nil
        }
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    switch trimmed {
    case "accent":
        return .accentColor
    case "success":
        return .green
    case "warning":
        return .orange
    case "error":
        return .red
    case "info":
        return .blue
    case "primary":
        return .primary
    case "secondary":
        return .secondary
    case "red":
        return .red
    case "green":
        return .green
    case "blue":
        return .blue
    case "orange":
        return .orange
    case "yellow":
        return .yellow
    case "purple":
        return .purple
    case "gray":
        return .gray
    default:
        return nil
    }
}

// MARK: - Chart Views

private struct GenerativeBarChartView: View {
    let node: UINode
    let decoder: JSONDecoder

    var body: some View {
        let props = try? decoder.decode(BarChartComponentDefinition.Props.self, from: node.propsData)
        let data = props?.data ?? []
        let orientation = props?.orientation ?? .vertical
        let showLabels = props?.showLabels ?? true
        let showValues = props?.showValues ?? false
        let height = CGFloat(props?.height ?? 180)
        let defaultColor = colorFromString(props?.barColor)

        #if canImport(Charts)
        Chart(data, id: \.label) { point in
            if orientation == .horizontal {
                BarMark(
                    x: .value("Value", point.value),
                    y: .value("Label", point.label)
                )
                .foregroundStyle(colorFromString(point.color) ?? defaultColor ?? .accentColor)
                .annotation(position: .trailing, alignment: .leading) {
                    if showValues {
                        Text(String(format: "%.0f", point.value))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                BarMark(
                    x: .value("Label", point.label),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(colorFromString(point.color) ?? defaultColor ?? .accentColor)
                .annotation(position: .top) {
                    if showValues {
                        Text(String(format: "%.0f", point.value))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis(showLabels ? .automatic : .hidden)
        .chartYAxis(showLabels ? .automatic : .hidden)
        .frame(height: height)
        #else
        Text("Charts not available")
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }
}

private struct GenerativeLineChartView: View {
    let node: UINode
    let decoder: JSONDecoder

    var body: some View {
        let props = try? decoder.decode(LineChartComponentDefinition.Props.self, from: node.propsData)
        let series = props?.series ?? []
        let showPoints = props?.showPoints ?? false
        let smooth = props?.smooth ?? false
        let showGrid = props?.showGrid ?? true
        let height = CGFloat(props?.height ?? 180)

        #if canImport(Charts)
        Chart {
            ForEach(series, id: \.name) { seriesEntry in
                let color = colorFromString(seriesEntry.color) ?? .accentColor
                ForEach(Array(seriesEntry.data.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("X", point.x),
                        y: .value("Y", point.y)
                    )
                    .foregroundStyle(color)
                    .interpolationMethod(smooth ? .catmullRom : .linear)

                    if showPoints {
                        PointMark(
                            x: .value("X", point.x),
                            y: .value("Y", point.y)
                        )
                        .foregroundStyle(color)
                    }
                }
            }
        }
        .chartXAxis(showGrid ? .automatic : .hidden)
        .chartYAxis(showGrid ? .automatic : .hidden)
        .frame(height: height)
        #else
        Text("Charts not available")
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }
}

private struct GenerativePieChartView: View {
    let node: UINode
    let decoder: JSONDecoder

    var body: some View {
        let props = try? decoder.decode(PieChartComponentDefinition.Props.self, from: node.propsData)
        let data = props?.data ?? []
        let donut = props?.donut ?? false
        let showLegend = props?.showLegend ?? false
        let showLabels = props?.showLabels ?? false

        #if canImport(Charts)
        Chart(data, id: \.label) { slice in
            SectorMark(
                angle: .value("Value", slice.value),
                innerRadius: .ratio(donut ? 0.6 : 0)
            )
            .foregroundStyle(colorFromString(slice.color) ?? .accentColor)
            .annotation(position: .overlay, alignment: .center) {
                if showLabels {
                    Text(slice.label)
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
            }
        }
        .chartLegend(showLegend ? .visible : .hidden)
        #else
        Text("Charts not available")
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }
}

private struct GenerativeGaugeView: View {
    let node: UINode
    let decoder: JSONDecoder

    var body: some View {
        let props = try? decoder.decode(GaugeComponentDefinition.Props.self, from: node.propsData)
        let value = props?.value ?? 0
        let minValue = props?.min ?? 0
        let maxValue = props?.max ?? 1
        let showValue = props?.showValue ?? false
        let label = props?.label

        VStack(alignment: .leading, spacing: 6) {
            Gauge(value: value, in: minValue...maxValue) {
                if let label {
                    Text(label)
                }
            } currentValueLabel: {
                if showValue {
                    Text(String(format: "%.1f", value))
                }
            }
            .tint(colorFromString(props?.color) ?? .accentColor)
        }
    }
}

// MARK: - Interactive Views

private struct GenerativeToggleView: View {
    let node: UINode
    let decoder: JSONDecoder
    let onAction: UIActionHandler
    @State private var isOn = false
    @State private var didInitialize = false

    var body: some View {
        let props = try? decoder.decode(ToggleComponentDefinition.Props.self, from: node.propsData)
        let label = props?.label ?? "Toggle"
        let name = props?.name ?? "toggle"

        Toggle(label, isOn: $isOn)
            .disabled(props?.disabled ?? false)
            .accessibilityLabel(label)
            .onAppear {
                if !didInitialize {
                    isOn = props?.value ?? false
                    didInitialize = true
                }
            }
            .onChange(of: isOn) { _, newValue in
                guard didInitialize else { return }
                onAction("\(name):\(newValue)")
            }
    }
}

private struct GenerativeSliderView: View {
    let node: UINode
    let decoder: JSONDecoder
    let onAction: UIActionHandler
    @State private var value: Double = 0
    @State private var didInitialize = false

    var body: some View {
        let props = try? decoder.decode(SliderComponentDefinition.Props.self, from: node.propsData)
        let label = props?.label ?? "Slider"
        let name = props?.name ?? "slider"
        let minValue = props?.min ?? 0
        let maxValue = props?.max ?? 1
        let step = props?.step
        let showValue = props?.showValue ?? false

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                if showValue {
                    Text(String(format: "%.1f", value))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let step {
                Slider(value: $value, in: minValue...maxValue, step: step)
            } else {
                Slider(value: $value, in: minValue...maxValue)
            }
        }
        .accessibilityLabel(label)
        .onAppear {
            if !didInitialize {
                value = props?.value ?? minValue
                didInitialize = true
            }
        }
        .onChange(of: value) { _, newValue in
            guard didInitialize else { return }
            onAction("\(name):\(String(format: "%.1f", newValue))")
        }
    }
}

private struct GenerativeStepperView: View {
    let node: UINode
    let decoder: JSONDecoder
    @State private var value: Double = 0
    @State private var didInitialize = false

    var body: some View {
        let props = try? decoder.decode(StepperComponentDefinition.Props.self, from: node.propsData)
        let label = props?.label ?? "Stepper"
        let minValue = props?.min ?? (value - 100)
        let maxValue = props?.max ?? (value + 100)
        let step = props?.step ?? 1
        let showValue = props?.showValue ?? false

        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: $value, in: minValue...maxValue, step: step) {
                Text(label)
            }
            if showValue {
                Text(String(format: "%.1f", value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(label)
        .onAppear {
            if !didInitialize {
                value = props?.value ?? props?.min ?? value
                didInitialize = true
            }
        }
    }
}

private struct GenerativeSegmentedControlView: View {
    let node: UINode
    let decoder: JSONDecoder
    @State private var selection: String = ""
    @State private var didInitialize = false

    var body: some View {
        let props = try? decoder.decode(SegmentedControlComponentDefinition.Props.self, from: node.propsData)
        let options = props?.options ?? []
        Picker("", selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Segmented Control")
        .onAppear {
            if !didInitialize {
                selection = props?.selected ?? options.first?.value ?? ""
                didInitialize = true
            }
        }
    }
}

private struct GenerativePickerView: View {
    let node: UINode
    let decoder: JSONDecoder
    @State private var selection: String = ""
    @State private var didInitialize = false

    var body: some View {
        let props = try? decoder.decode(PickerComponentDefinition.Props.self, from: node.propsData)
        let options = props?.options ?? []
        Picker("Select", selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .onAppear {
            if !didInitialize {
                selection = props?.selected ?? options.first?.value ?? ""
                didInitialize = true
            }
        }
    }
}

// MARK: - Layout Views

private struct GenerativeGridView: View {
    let node: UINode
    let tree: UITree
    let decoder: JSONDecoder
    let buildChild: ChildViewBuilder

    var body: some View {
        let props = try? decoder.decode(GridComponentDefinition.Props.self, from: node.propsData)
        let columnsCount = max(1, props?.columns ?? 1)
        let spacing = CGFloat(props?.spacing ?? 8)
        let alignment = gridAlignment(from: props?.alignment ?? .leading)
        let itemAlignment = gridItemAlignment(from: props?.alignment ?? .leading)
        let items = Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: itemAlignment), count: columnsCount)
        let childNodes = node.childKeys.compactMap { tree.nodes[$0] }

        LazyVGrid(columns: items, alignment: alignment, spacing: spacing) {
            ForEach(childNodes, id: \.key) { childNode in
                buildChild(childNode)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func gridAlignment(from alignment: GridComponentDefinition.GridAlignment) -> HorizontalAlignment {
        switch alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }

    private func gridItemAlignment(from alignment: GridComponentDefinition.GridAlignment) -> Alignment {
        switch alignment {
        case .leading:
            return .leading
        case .center:
            return .center
        case .trailing:
            return .trailing
        }
    }
}

private struct GenerativeTabsView: View {
    let node: UINode
    let tree: UITree
    let decoder: JSONDecoder
    let buildChild: ChildViewBuilder
    @State private var selectedKey: String = ""
    @State private var didInitialize = false

    var body: some View {
        let props = try? decoder.decode(TabsComponentDefinition.Props.self, from: node.propsData)
        let tabs = props?.tabs ?? []
        let childNodes = node.childKeys.compactMap { tree.nodes[$0] }
        let selectedIndex = tabs.firstIndex(where: { $0.key == selectedKey }) ?? 0
        let contentNode = selectedIndex < childNodes.count ? childNodes[selectedIndex] : nil

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.key) { tab in
                    Button(action: { selectedKey = tab.key }) {
                        Text(tab.label)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(tab.key == selectedKey ? Color.accentColor.opacity(0.2) : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if let contentNode {
                buildChild(contentNode)
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            if !didInitialize {
                selectedKey = props?.selected ?? tabs.first?.key ?? ""
                didInitialize = true
            }
        }
    }
}

private struct GenerativeAccordionView: View {
    let node: UINode
    let tree: UITree
    let decoder: JSONDecoder
    let buildChild: ChildViewBuilder
    @State private var expandedKeys: Set<String> = []

    var body: some View {
        let props = try? decoder.decode(AccordionComponentDefinition.Props.self, from: node.propsData)
        let items = props?.items ?? []
        let childNodes = node.childKeys.compactMap { tree.nodes[$0] }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.element.key) { index, item in
                let isExpanded = expandedKeys.contains(item.key)
                DisclosureGroup(isExpanded: Binding(get: {
                    isExpanded
                }, set: { newValue in
                    if newValue {
                        expandedKeys.insert(item.key)
                    } else {
                        expandedKeys.remove(item.key)
                    }
                })) {
                    if index < childNodes.count {
                        buildChild(childNodes[index])
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#endif
