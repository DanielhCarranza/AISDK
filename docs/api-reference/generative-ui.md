# Generative UI

> Dynamic interfaces with LLM-generated components

## Overview

AISDK's Generative UI uses the **json-render pattern**: the LLM outputs JSON describing a UI tree, which is validated and rendered into native SwiftUI views.

```
LLM → JSON → UITree → SwiftUI Views
```

---

## UICatalog

Central registry defining available UI components.

```swift
public struct UICatalog: Sendable {
    /// Registered component definitions
    public private(set) var components: [String: AnyUIComponentDefinition]

    /// Registered action definitions
    public private(set) var actions: [String: UIActionDefinition]

    /// Registered validator definitions
    public private(set) var validators: [String: UIValidatorDefinition]

    /// Create empty catalog
    public init()

    /// Default Core 8 catalog
    public static let core8: UICatalog
}
```

### Core 8 Components

| Component | Description | Has Children |
|-----------|-------------|--------------|
| Text | Display text content | No |
| Button | Interactive button | No |
| Card | Container with title/subtitle | Yes |
| Input | Text input field | No |
| List | Ordered/unordered list | Yes |
| Image | Image display | No |
| Stack | Layout container | Yes |
| Spacer | Flexible space | No |

### Registration

```swift
var catalog = UICatalog()

// Register custom component
try catalog.register(MyCustomComponent.self)

// Register action
catalog.registerAction(UIActionDefinition(
    name: "submit",
    description: "Submit the form",
    parametersDescription: "{ formId?: string }"
))

// Register validator
catalog.registerValidator(UIValidatorDefinition(
    name: "email",
    description: "Validates email format"
))
```

### Prompt Generation

```swift
// Generate prompt for LLM
let prompt = catalog.generatePrompt()
// Includes all components, actions, validators, and output format spec
```

### Validation

```swift
try catalog.validate(type: "Button", propsData: propsJSON)
```

---

## UITree

Parsed representation of LLM-generated UI.

```swift
public struct UITree: Sendable, Equatable {
    /// Key of the root element
    public let rootKey: String

    /// All nodes keyed by identifier
    public let nodes: [String: UINode]

    /// The root node
    public var rootNode: UINode { get }

    /// Total node count
    public var nodeCount: Int { get }

    /// Maximum tree depth
    public var maxDepth: Int { get }
}
```

### Parsing

```swift
// Parse from JSON data
let tree = try UITree.parse(
    from: jsonData,
    validatingWith: UICatalog.core8
)

// Parse from string
let tree = try UITree.parse(
    from: jsonString,
    validatingWith: catalog
)
```

### Traversal

```swift
// Get children of a node
let children = tree.children(of: node)

// Look up node by key
if let node = tree.node(forKey: "title") {
    print(node.type)  // "Text"
}

// Depth-first traversal
tree.traverse { node, depth in
    print("\(String(repeating: "  ", count: depth))\(node.type)")
}

// Get all nodes in order
let allNodes = tree.allNodes()
```

### JSON Format

```json
{
  "root": "main",
  "elements": {
    "main": {
      "type": "Stack",
      "props": { "direction": "vertical" },
      "children": ["title", "button"]
    },
    "title": {
      "type": "Text",
      "props": { "content": "Hello, World!" }
    },
    "button": {
      "type": "Button",
      "props": { "title": "Click Me", "action": "submit" }
    }
  }
}
```

---

## UINode

A single node in the UI tree.

```swift
public struct UINode: Sendable, Equatable {
    /// Unique key in the tree
    public let key: String

    /// Component type (e.g., "Text", "Button")
    public let type: String

    /// Raw JSON props data
    public let propsData: Data

    /// Child node keys
    public let childKeys: [String]

    /// Whether children field was present
    public let hadChildrenField: Bool
}
```

---

## UIComponentDefinition Protocol

Define custom UI components.

```swift
public protocol UIComponentDefinition: Sendable {
    /// Props type for this component
    associatedtype Props: Codable & Sendable

    /// Type identifier in JSON
    static var type: String { get }

    /// Description for LLM
    static var description: String { get }

    /// Whether it supports children
    static var hasChildren: Bool { get }

    /// Props schema description for LLM
    static var propsSchemaDescription: String { get }

    /// Allowed prop keys (empty = allow all)
    static var allowedPropKeys: Set<String> { get }

    /// Validate props
    static func validate(props: Props) throws

    /// Validate with catalog context
    static func validateWithCatalog(
        props: Props,
        actions: Set<String>,
        validators: Set<String>
    ) throws
}
```

### Example Custom Component

```swift
struct RatingComponentDefinition: UIComponentDefinition {
    struct Props: Codable, Sendable {
        let maxStars: Int
        let currentRating: Int
    }

    static let type = "Rating"
    static let description = "Star rating display"
    static let hasChildren = false
    static let propsSchemaDescription = """
        maxStars (required): Maximum stars (1-10)
        currentRating (required): Current rating value
        """

    static var allowedPropKeys: Set<String> {
        ["maxStars", "currentRating"]
    }

    static func validate(props: Props) throws {
        guard props.maxStars >= 1 && props.maxStars <= 10 else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "maxStars",
                reason: "Must be between 1 and 10"
            )
        }
        guard props.currentRating >= 0,
              props.currentRating <= props.maxStars else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "currentRating",
                reason: "Must be between 0 and maxStars"
            )
        }
    }
}
```

---

## UIActionDefinition

Define actions that can be triggered by UI.

```swift
public struct UIActionDefinition: Sendable {
    /// Action identifier
    public let name: String

    /// Human-readable description
    public let description: String

    /// Parameter schema description
    public let parametersDescription: String?

    public init(
        name: String,
        description: String,
        parametersDescription: String? = nil
    )
}
```

---

## UIValidatorDefinition

Define validators for input fields.

```swift
public struct UIValidatorDefinition: Sendable {
    /// Validator identifier
    public let name: String

    /// Human-readable description
    public let description: String

    /// Parameter schema description
    public let parametersDescription: String?

    public init(
        name: String,
        description: String,
        parametersDescription: String? = nil
    )
}
```

---

## Props Types

### TextProps

```swift
struct TextProps: Codable, Sendable {
    let content: String
}
```

### ButtonProps

```swift
struct ButtonProps: Codable, Sendable {
    let title: String
    let action: String?
}
```

### StackProps

```swift
struct StackProps: Codable, Sendable {
    let direction: StackDirection?  // horizontal, vertical
    let alignment: StackAlignment?  // leading, center, trailing
    let spacing: Int?
}
```

### CardProps

```swift
struct CardProps: Codable, Sendable {
    let title: String
    let subtitle: String?
}
```

### InputProps

```swift
struct InputProps: Codable, Sendable {
    let placeholder: String?
    let inputType: InputType?  // text, email, password, number
    let validator: String?
}
```

### ImageProps

```swift
struct ImageProps: Codable, Sendable {
    let url: String
    let alt: String?
}
```

### ListProps

```swift
struct ListProps: Codable, Sendable {
    let style: UIListStyle?  // ordered, unordered, plain
}
```

---

## Error Types

### UITreeError

```swift
public enum UITreeError: Error, Sendable {
    case invalidStructure(reason: String)
    case rootNotFound(key: String)
    case childNotFound(parentKey: String, childKey: String)
    case circularReference(key: String)
    case duplicateKey(key: String)
    case invalidNodeKey(key: String)
    case unknownComponentType(key: String, type: String)
    case childrenNotAllowed(key: String, type: String)
    case validationFailed(key: String, error: UIComponentValidationError)
    case multipleParents(key: String)
    case depthExceeded(maxAllowed: Int)
    case nodeCountExceeded(maxAllowed: Int)
    case unreachableNode(key: String)
}
```

### UIComponentValidationError

```swift
public enum UIComponentValidationError: Error, Sendable {
    case missingRequiredProp(component: String, prop: String)
    case invalidPropValue(component: String, prop: String, reason: String)
    case unknownComponentType(String)
    case validationFailed(component: String, reason: String)
    case decodingFailed(component: String, reason: String)
    case unknownProp(component: String, prop: String)
    case unknownAction(component: String, action: String)
    case unknownValidator(component: String, validator: String)
    case invalidComponentTypeName(String)
    case duplicateComponentType(String)
}
```

---

## Constraints

- **Maximum tree depth**: 100 levels
- **Maximum nodes**: 10,000
- **No circular references**
- **True tree structure** (each node has exactly one parent)
- **Children only on containers**

---

## SwiftUI Rendering

```swift
struct GenerativeUIView: View {
    let tree: UITree

    var body: some View {
        renderNode(tree.rootNode)
    }

    @ViewBuilder
    private func renderNode(_ node: UINode) -> some View {
        switch node.type {
        case "Text":
            renderText(node)
        case "Button":
            renderButton(node)
        case "Stack":
            renderStack(node)
        case "Card":
            renderCard(node)
        default:
            EmptyView()
        }
    }

    private func renderText(_ node: UINode) -> some View {
        let props = try? JSONDecoder().decode(TextProps.self, from: node.propsData)
        return Text(props?.content ?? "")
    }

    private func renderStack(_ node: UINode) -> some View {
        let props = try? JSONDecoder().decode(StackProps.self, from: node.propsData)
        let children = tree.children(of: node)

        return Group {
            if props?.direction == .horizontal {
                HStack {
                    ForEach(children, id: \.key) { child in
                        renderNode(child)
                    }
                }
            } else {
                VStack {
                    ForEach(children, id: \.key) { child in
                        renderNode(child)
                    }
                }
            }
        }
    }
}
```

## See Also

- [Agents](agents.md) - Agent workflows for UI generation
- [Models](models.md) - Request/response types
- [Errors](errors.md) - Error handling
