# Phase 5: Generative UI

**Duration**: 2 weeks
**Tasks**: 7
**Dependencies**: Phase 4

---

## Goal

Implement dynamic UI generation from LLM responses using the json-render pattern with Core 8 SwiftUI components.

---

## Context Files (Read First)

```
docs/planning/interview-transcript.md          # Core 8 components decision
docs/planning/external-review-feedback.md      # Accessibility, validation concerns
https://github.com/vercel-labs/json-render     # Reference implementation (read via DeepWiki)
```

---

## Tasks

### Task 5.1: UICatalog

**Location**: `Sources/AISDK/GenerativeUI/Catalog/UICatalog.swift`
**Complexity**: 6/10
**Dependencies**: None

```swift
/// Component catalog - defines available UI components for LLM
public struct UICatalog: Sendable {
    public let components: [String: any UIComponentDefinition.Type]
    public let actions: [String: UIActionDefinition]
    public let validators: [String: UIValidatorDefinition]

    /// Generate system prompt for LLM
    public func generatePrompt() -> String {
        var prompt = "You can generate UI using these components:\n\n"

        for (name, definition) in components {
            prompt += "## \(name)\n"
            prompt += "Description: \(definition.description)\n"
            prompt += "Props: \(definition.propsSchemaDescription)\n"
            if definition.hasChildren {
                prompt += "Can contain children: Yes\n"
            }
            prompt += "\n"
        }

        prompt += """

        Output format: JSON with structure:
        {
          "root": "<key of root element>",
          "elements": {
            "<key>": {
              "type": "<component type>",
              "props": { ... },
              "children": ["<child key>", ...]
            }
          }
        }
        """

        return prompt
    }

    /// Core 8 components catalog
    public static let core8 = UICatalog(components: [
        "Text": TextComponentDefinition.self,
        "Button": ButtonComponentDefinition.self,
        "Card": CardComponentDefinition.self,
        "Input": InputComponentDefinition.self,
        "List": ListComponentDefinition.self,
        "Image": ImageComponentDefinition.self,
        "Stack": StackComponentDefinition.self,
        "Spacer": SpacerComponentDefinition.self
    ])
}

/// Component definition protocol
public protocol UIComponentDefinition: Sendable {
    associatedtype Props: Codable & Sendable

    static var type: String { get }
    static var description: String { get }
    static var hasChildren: Bool { get }
    static var propsSchemaDescription: String { get }

    static func validate(props: Props) throws
}
```

---

### Task 5.2: Core 8 Component Definitions

**Location**: `Sources/AISDK/GenerativeUI/Components/`
**Complexity**: 5/10
**Dependencies**: Task 5.1

```swift
// TextComponentDefinition.swift
public struct TextComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let content: String
        public let style: TextStyle?
        // Accessibility (from review)
        public let accessibilityLabel: String?
    }

    public static let type = "Text"
    public static let description = "Display text content"
    public static let hasChildren = false
}

// ButtonComponentDefinition.swift
public struct ButtonComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let title: String
        public let action: String
        public let style: ButtonStyle?
        public let disabled: Bool?
        // Accessibility (from review)
        public let accessibilityLabel: String?
        public let accessibilityHint: String?
        public let accessibilityTraits: [String]?
    }

    public static let type = "Button"
    public static let description = "Interactive button"
    public static let hasChildren = false
}

// CardComponentDefinition.swift
public struct CardComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let title: String?
        public let subtitle: String?
        public let style: CardStyle?
    }

    public static let type = "Card"
    public static let description = "Container with title"
    public static let hasChildren = true
}

// InputComponentDefinition.swift
public struct InputComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let label: String
        public let placeholder: String?
        public let name: String
        public let type: InputType?
        public let required: Bool?
        public let validation: ValidationRule?
    }

    public static let type = "Input"
    public static let description = "Text input field"
    public static let hasChildren = false
}

// ListComponentDefinition.swift
public struct ListComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let style: ListStyle?
    }

    public static let type = "List"
    public static let description = "Ordered or unordered list"
    public static let hasChildren = true
}

// ImageComponentDefinition.swift
public struct ImageComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let url: String
        public let alt: String?
        public let width: Double?
        public let height: Double?
    }

    public static let type = "Image"
    public static let description = "Image display"
    public static let hasChildren = false
}

// StackComponentDefinition.swift
public struct StackComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let direction: StackDirection
        public let spacing: Double?
        public let alignment: StackAlignment?
    }

    public enum StackDirection: String, Codable, Sendable {
        case horizontal, vertical
    }

    public static let type = "Stack"
    public static let description = "Layout container"
    public static let hasChildren = true
}

// SpacerComponentDefinition.swift
public struct SpacerComponentDefinition: UIComponentDefinition {
    public struct Props: Codable, Sendable {
        public let size: Double?
    }

    public static let type = "Spacer"
    public static let description = "Flexible space"
    public static let hasChildren = false
}
```

---

### Task 5.3: UITree Model

**Location**: `Sources/AISDK/GenerativeUI/Models/UITree.swift`
**Complexity**: 6/10
**Dependencies**: Task 5.2

```swift
/// UI tree - flat element map (json-render pattern)
public struct UITree: Codable, Sendable, Equatable {
    public let root: String
    public let elements: [String: UIElement]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.root = try container.decode(String.self, forKey: .root)
        self.elements = try container.decode([String: UIElement].self, forKey: .elements)

        // Schema validation (from review)
        try validateSchema()
    }

    private func validateSchema() throws {
        guard elements[root] != nil else {
            throw UITreeError.missingRootElement(root)
        }

        for (key, element) in elements {
            // Validate children exist
            for childKey in element.children ?? [] {
                guard elements[childKey] != nil else {
                    throw UITreeError.missingChildElement(parent: key, child: childKey)
                }
            }
        }
    }

    /// Get element by key
    public func element(_ key: String) -> UIElement? {
        elements[key]
    }

    /// Get children of element
    public func children(of key: String) -> [UIElement] {
        guard let element = elements[key],
              let childKeys = element.children else {
            return []
        }
        return childKeys.compactMap { elements[$0] }
    }
}

public struct UIElement: Codable, Sendable, Equatable {
    public let key: String
    public let type: String
    public let props: [String: AnyCodable]
    public let children: [String]?
    public let visible: UIVisibilityCondition?
}

public struct UIVisibilityCondition: Codable, Sendable, Equatable {
    public let field: String
    public let operator: VisibilityOperator
    public let value: AnyCodable

    public enum VisibilityOperator: String, Codable, Sendable {
        case equals, notEquals, contains, greaterThan, lessThan
    }
}

public enum UITreeError: Error {
    case missingRootElement(String)
    case missingChildElement(parent: String, child: String)
    case invalidComponentType(String)
}
```

---

### Task 5.4: UIComponentRegistry

**Location**: `Sources/AISDK/GenerativeUI/Registry/UIComponentRegistry.swift`
**Complexity**: 6/10
**Dependencies**: Tasks 5.2, 5.3

```swift
/// Registry mapping element types to SwiftUI views
public struct UIComponentRegistry: Sendable {
    public typealias ViewBuilder = @Sendable (UIElement, UITree, UIActionHandler) -> AnyView

    private var builders: [String: ViewBuilder]
    private var allowedActions: Set<String>  // Security (from review)

    public init() {
        self.builders = [:]
        self.allowedActions = []
    }

    public mutating func register<V: View>(
        _ type: String,
        builder: @escaping @Sendable (UIElement, UITree, UIActionHandler) -> V
    ) {
        builders[type] = { element, tree, handler in
            AnyView(builder(element, tree, handler))
        }
    }

    public mutating func allowAction(_ action: String) {
        allowedActions.insert(action)
    }

    public func build(
        element: UIElement,
        tree: UITree,
        actionHandler: UIActionHandler
    ) -> AnyView {
        guard let builder = builders[element.type] else {
            return AnyView(Text("Unknown component: \(element.type)"))
        }

        // Wrap action handler with security check
        let secureHandler: UIActionHandler = { action in
            guard allowedActions.contains(action) || allowedActions.isEmpty else {
                print("Blocked action: \(action)")
                return
            }
            actionHandler(action)
        }

        return builder(element, tree, secureHandler)
    }

    /// Default registry with Core 8 components
    public static var `default`: UIComponentRegistry {
        var registry = UIComponentRegistry()

        registry.register("Text") { element, _, _ in
            GenerativeText(element: element)
        }

        registry.register("Button") { element, _, handler in
            GenerativeButton(element: element, onAction: handler)
        }

        registry.register("Card") { element, tree, handler in
            GenerativeCard(element: element, tree: tree, registry: registry, onAction: handler)
        }

        // ... other components

        return registry
    }
}

public typealias UIActionHandler = @Sendable (String) -> Void
```

---

### Task 5.5: Core 8 SwiftUI Views

**Location**: `Sources/AISDK/GenerativeUI/Views/`
**Complexity**: 6/10
**Dependencies**: Task 5.4

```swift
// GenerativeText.swift
public struct GenerativeText: View {
    let element: UIElement

    public var body: some View {
        let content = element.props["content"]?.stringValue ?? ""
        Text(content)
            .accessibilityLabel(element.props["accessibilityLabel"]?.stringValue ?? content)
    }
}

// GenerativeButton.swift
public struct GenerativeButton: View {
    let element: UIElement
    let onAction: UIActionHandler

    public var body: some View {
        let title = element.props["title"]?.stringValue ?? "Button"
        let action = element.props["action"]?.stringValue ?? ""
        let disabled = element.props["disabled"]?.boolValue ?? false

        Button(title) {
            onAction(action)
        }
        .disabled(disabled)
        .accessibilityLabel(element.props["accessibilityLabel"]?.stringValue ?? title)
        .accessibilityHint(element.props["accessibilityHint"]?.stringValue ?? "")
    }
}

// GenerativeCard.swift
public struct GenerativeCard: View {
    let element: UIElement
    let tree: UITree
    let registry: UIComponentRegistry
    let onAction: UIActionHandler

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = element.props["title"]?.stringValue {
                Text(title).font(.headline)
            }

            if let subtitle = element.props["subtitle"]?.stringValue {
                Text(subtitle).font(.subheadline)
            }

            // Render children
            ForEach(tree.children(of: element.key), id: \.key) { child in
                registry.build(element: child, tree: tree, actionHandler: onAction)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// GenerativeStack.swift
public struct GenerativeStack: View {
    let element: UIElement
    let tree: UITree
    let registry: UIComponentRegistry
    let onAction: UIActionHandler

    public var body: some View {
        let direction = element.props["direction"]?.stringValue ?? "vertical"
        let spacing = element.props["spacing"]?.doubleValue ?? 8

        if direction == "horizontal" {
            HStack(spacing: spacing) {
                childViews
            }
        } else {
            VStack(spacing: spacing) {
                childViews
            }
        }
    }

    @ViewBuilder
    private var childViews: some View {
        ForEach(tree.children(of: element.key), id: \.key) { child in
            registry.build(element: child, tree: tree, actionHandler: onAction)
        }
    }
}

// ... Image, Input, List, Spacer
```

---

### Task 5.6: GenerativeUIView

**Location**: `Sources/AISDK/GenerativeUI/Views/GenerativeUIView.swift`
**Complexity**: 7/10
**Dependencies**: Tasks 5.3-5.5

```swift
/// SwiftUI view for streaming generative UI
public struct GenerativeUIView: View {
    @StateObject private var viewModel: GenerativeUIViewModel

    private let catalog: UICatalog
    private let registry: UIComponentRegistry
    private let onAction: UIActionHandler

    public init(
        stream: AsyncThrowingStream<AIStreamEvent, Error>,
        catalog: UICatalog = .core8,
        registry: UIComponentRegistry = .default,
        onAction: @escaping UIActionHandler = { _ in }
    ) {
        self._viewModel = StateObject(wrappedValue: GenerativeUIViewModel(stream: stream))
        self.catalog = catalog
        self.registry = registry
        self.onAction = onAction
    }

    public var body: some View {
        Group {
            if viewModel.isLoading && viewModel.tree == nil {
                ProgressView()
            } else if let error = viewModel.error {
                ErrorView(error: error)
            } else if let tree = viewModel.tree {
                renderTree(tree)
            }
        }
        .task {
            await viewModel.startProcessing()
        }
    }

    @ViewBuilder
    private func renderTree(_ tree: UITree) -> some View {
        if let rootElement = tree.element(tree.root) {
            registry.build(
                element: rootElement,
                tree: tree,
                actionHandler: onAction
            )
        }
    }
}

struct ErrorView: View {
    let error: AIError

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Error loading UI")
                .font(.headline)
            Text(error.safeDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
```

---

### Task 5.7: GenerativeUIViewModel

**Location**: `Sources/AISDK/GenerativeUI/ViewModels/GenerativeUIViewModel.swift`
**Complexity**: 7/10
**Dependencies**: Task 5.6

```swift
/// View model for streaming UI state management
@MainActor
public class GenerativeUIViewModel: ObservableObject {
    @Published public var tree: UITree?
    @Published public var isLoading: Bool = true
    @Published public var error: AIError?

    private let stream: AsyncThrowingStream<AIStreamEvent, Error>
    private var jsonBuffer: String = ""

    // Batching for jank prevention (from review)
    private var pendingUpdates: [UITreeUpdate] = []
    private var updateTask: Task<Void, Never>?

    public init(stream: AsyncThrowingStream<AIStreamEvent, Error>) {
        self.stream = stream
    }

    public func startProcessing() async {
        do {
            for try await event in stream {
                process(event: event)
            }
            isLoading = false
        } catch let error as AIError {
            self.error = error
            isLoading = false
        } catch {
            self.error = AIError.streamError(message: error.localizedDescription)
            isLoading = false
        }
    }

    private func process(event: AIStreamEvent) {
        switch event {
        case .textDelta(let delta):
            jsonBuffer += delta
            scheduleTreeUpdate()

        case .finish:
            applyFinalTree()

        case .error(let error):
            self.error = error

        default:
            break
        }
    }

    /// Batch updates for 60fps rendering
    private func scheduleTreeUpdate() {
        updateTask?.cancel()
        updateTask = Task {
            try? await Task.sleep(for: .milliseconds(16))
            applyPartialTree()
        }
    }

    private func applyPartialTree() {
        // Try to parse partial JSON
        if let tree = parseTree(from: jsonBuffer) {
            self.tree = tree
        }
    }

    private func applyFinalTree() {
        updateTask?.cancel()
        if let tree = parseTree(from: jsonBuffer) {
            self.tree = tree
        }
    }

    private func parseTree(from json: String) -> UITree? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(UITree.self, from: data)
    }
}

struct UITreeUpdate {
    let key: String
    let element: UIElement
}
```

---

## Verification

```bash
swift test --filter "GenerativeUI"
```
