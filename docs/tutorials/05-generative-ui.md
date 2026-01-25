# Generative UI

> Building dynamic interfaces with LLM-generated components

## Overview

Generative UI lets AI models create user interfaces dynamically. AISDK uses the **json-render pattern**: the LLM outputs JSON describing a UI tree, which is then rendered into native SwiftUI views.

## Core Concepts

### UICatalog

Defines available UI components:

```swift
import AISDK

// Use the built-in Core 8 catalog
let catalog = UICatalog.core8

// Core 8 components:
// - Text: Display text
// - Button: Interactive button
// - Card: Container with title/subtitle
// - Input: Text input field
// - List: Ordered/unordered lists
// - Image: Image display
// - Stack: Layout container
// - Spacer: Flexible space
```

### UITree

Parsed representation of LLM-generated UI:

```swift
// LLM generates JSON like this:
let json = """
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
"""

// Parse and validate
let tree = try UITree.parse(
    from: json,
    validatingWith: UICatalog.core8
)
```

## Setting Up Generative UI

### 1. Create the ViewModel

```swift
@Observable
class GenerativeUIViewModel {
    private(set) var tree: UITree?
    private(set) var error: Error?
    private(set) var isLoading = false

    private let catalog: UICatalog
    private let agent: AIAgentActor

    init(catalog: UICatalog = .core8, agent: AIAgentActor) {
        self.catalog = catalog
        self.agent = agent
    }

    func generateUI(for prompt: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Include catalog prompt in system message
            let systemPrompt = catalog.generatePrompt()

            let result = try await agent.execute(
                messages: [
                    .system(systemPrompt),
                    .user(prompt)
                ]
            )

            // Parse the JSON response
            if let jsonData = result.text.data(using: .utf8) {
                tree = try UITree.parse(from: jsonData, validatingWith: catalog)
            }
        } catch {
            self.error = error
        }
    }
}
```

### 2. Create the View

```swift
struct GenerativeUIView: View {
    let viewModel: GenerativeUIViewModel

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Generating UI...")
            } else if let tree = viewModel.tree {
                renderNode(tree.rootNode, tree: tree)
            } else if let error = viewModel.error {
                Text("Error: \(error.localizedDescription)")
            } else {
                Text("Enter a prompt to generate UI")
            }
        }
    }

    @ViewBuilder
    private func renderNode(_ node: UINode, tree: UITree) -> some View {
        switch node.type {
        case "Text":
            renderText(node)
        case "Button":
            renderButton(node)
        case "Stack":
            renderStack(node, tree: tree)
        case "Card":
            renderCard(node, tree: tree)
        case "Input":
            renderInput(node)
        case "Image":
            renderImage(node)
        case "List":
            renderList(node, tree: tree)
        case "Spacer":
            Spacer()
        default:
            EmptyView()
        }
    }

    private func renderText(_ node: UINode) -> some View {
        let props = try? JSONDecoder().decode(TextProps.self, from: node.propsData)
        return Text(props?.content ?? "")
    }

    private func renderButton(_ node: UINode) -> some View {
        let props = try? JSONDecoder().decode(ButtonProps.self, from: node.propsData)
        return Button(props?.title ?? "Button") {
            handleAction(props?.action)
        }
    }

    private func renderStack(_ node: UINode, tree: UITree) -> some View {
        let props = try? JSONDecoder().decode(StackProps.self, from: node.propsData)
        let children = tree.children(of: node)

        return Group {
            if props?.direction == "horizontal" {
                HStack(alignment: alignment(from: props?.alignment)) {
                    ForEach(children, id: \.key) { child in
                        renderNode(child, tree: tree)
                    }
                }
            } else {
                VStack(alignment: hAlignment(from: props?.alignment)) {
                    ForEach(children, id: \.key) { child in
                        renderNode(child, tree: tree)
                    }
                }
            }
        }
    }

    // Additional render methods...
}
```

### 3. Props Types

```swift
struct TextProps: Codable {
    let content: String
}

struct ButtonProps: Codable {
    let title: String
    let action: String?
}

struct StackProps: Codable {
    let direction: String?
    let alignment: String?
    let spacing: Int?
}

struct CardProps: Codable {
    let title: String
    let subtitle: String?
}

struct InputProps: Codable {
    let placeholder: String?
    let inputType: String?
    let validator: String?
}

struct ImageProps: Codable {
    let url: String
    let alt: String?
}

struct ListProps: Codable {
    let style: String?
}
```

## Custom Components

Extend the catalog with your own components:

```swift
// Define props
struct RatingProps: Codable, Sendable {
    let maxStars: Int
    let currentRating: Int
}

// Define component
struct RatingComponentDefinition: UIComponentDefinition {
    typealias Props = RatingProps

    static let type = "Rating"
    static let description = "Star rating display"
    static let hasChildren = false
    static let propsSchemaDescription = """
        maxStars (required): Maximum number of stars (1-10)
        currentRating (required): Current rating value
        """

    static func validate(props: Props) throws {
        guard props.maxStars >= 1 && props.maxStars <= 10 else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "maxStars",
                reason: "Must be between 1 and 10"
            )
        }
        guard props.currentRating >= 0 && props.currentRating <= props.maxStars else {
            throw UIComponentValidationError.invalidPropValue(
                component: type,
                prop: "currentRating",
                reason: "Must be between 0 and maxStars"
            )
        }
    }
}

// Register in catalog
var catalog = UICatalog.core8
try catalog.register(RatingComponentDefinition.self)
```

## Actions and Validators

### Registering Actions

```swift
var catalog = UICatalog.core8

// Register custom action
catalog.registerAction(UIActionDefinition(
    name: "add_to_cart",
    description: "Add an item to the shopping cart",
    parametersDescription: "{ itemId: string, quantity: number }"
))
```

### Registering Validators

```swift
catalog.registerValidator(UIValidatorDefinition(
    name: "phone_number",
    description: "Validates phone number format",
    parametersDescription: "{ countryCode: string }"
))
```

## Complete Example: Form Generator

```swift
class FormGeneratorViewModel: ObservableObject {
    @Published var tree: UITree?
    @Published var formData: [String: String] = [:]
    @Published var isSubmitting = false

    private let agent: AIAgentActor
    private let catalog: UICatalog

    init() {
        // Create catalog with form actions
        var catalog = UICatalog.core8
        catalog.registerAction(UIActionDefinition(
            name: "submit_form",
            description: "Submit the form data"
        ))
        catalog.registerAction(UIActionDefinition(
            name: "clear_form",
            description: "Clear all form fields"
        ))
        self.catalog = catalog

        // Create agent
        self.agent = AIAgentActor(
            model: OpenRouterClient(),
            tools: [],
            systemPrompt: catalog.generatePrompt()
        )
    }

    func generateForm(description: String) async {
        let prompt = """
            Create a form UI for: \(description)

            Use Input components for fields, Button for submit.
            Wrap everything in a vertical Stack.
            Add appropriate validators.
            """

        let result = try? await agent.execute(messages: [.user(prompt)])

        if let json = result?.text.data(using: .utf8) {
            await MainActor.run {
                self.tree = try? UITree.parse(from: json, validatingWith: catalog)
            }
        }
    }

    func handleAction(_ action: String) {
        switch action {
        case "submit_form":
            submitForm()
        case "clear_form":
            formData.removeAll()
        default:
            break
        }
    }
}
```

## Best Practices

1. **Validate all LLM output** - Always parse with catalog validation
2. **Handle parse errors** - Show fallback UI on invalid JSON
3. **Limit tree depth** - UITree enforces max 100 levels
4. **Cache rendered trees** - Avoid re-parsing unchanged content
5. **Use clear prompts** - Include catalog.generatePrompt() for best results

## Constraints

- Maximum tree depth: 100 levels
- Maximum nodes: 10,000
- No circular references allowed
- Children only on container components

## Next Steps

- [Reliability Patterns](06-reliability-patterns.md) - Handle failures
- [Testing Strategies](07-testing-strategies.md) - Test UI generation
