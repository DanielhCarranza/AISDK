# Tool Creation

> Adding custom tools to your AI agents

## Overview

Tools let AI agents interact with external systems - fetching data, performing calculations, or executing actions.

AISDK provides two tool systems:
- **`AITool`** - Modern, immutable, Sendable-compliant protocol (recommended)
- **`Tool`** - Legacy, mutable instance-based protocol (for backward compatibility)

## Creating a Simple AITool

```swift
import AISDK

struct WeatherTool: AITool {
    static let name = "get_weather"
    static let description = "Get current weather for a city"

    struct Arguments: Codable, Sendable {
        let city: String
        let unit: TemperatureUnit?

        enum TemperatureUnit: String, Codable {
            case celsius, fahrenheit
        }
    }

    static func generateSchema() -> ToolSchema {
        ToolSchema(
            type: "function",
            function: ToolFunction(
                name: name,
                description: description,
                parameters: Parameters(
                    type: "object",
                    properties: [
                        "city": PropertyDefinition(type: "string", description: "City name"),
                        "unit": PropertyDefinition(
                            type: "string",
                            description: "Temperature unit",
                            enumValues: ["celsius", "fahrenheit"]
                        )
                    ],
                    required: ["city"]
                )
            )
        )
    }

    static func execute(arguments: Arguments) async throws -> AIToolResult<EmptyMetadata> {
        // In real code, call a weather API here
        let unit = arguments.unit ?? .fahrenheit
        let temp = unit == .celsius ? "22C" : "72F"

        return AIToolResult(content: "Weather in \(arguments.city): \(temp), sunny")
    }
}
```

## Using Legacy Tool with @Parameter

For simpler tools, you can use the legacy `Tool` protocol with `@Parameter` wrappers:

```swift
struct WeatherTool: Tool {
    let name = "get_weather"
    let description = "Get current weather for a city"

    @Parameter(description: "City name")
    var city: String = ""

    @Parameter(
        description: "Temperature unit",
        validation: ["enum": ["celsius", "fahrenheit"]]
    )
    var unit: String? = nil

    // Note: Do NOT re-initialize @Parameter in init()
    init() {}

    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        let temp = unit == "celsius" ? "22C" : "72F"
        return ("Weather in \(city): \(temp), sunny", nil)
    }
}
```

## Using Tools with Agent

```swift
// Using legacy Tool types with AIAgentActor
let agent = AIAgentActor(
    model: languageModel,
    tools: [WeatherTool.self],
    instructions: "You can check the weather."
)

for try await event in agent.streamExecute(messages: [.user("What's the weather in Tokyo?")]) {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .toolResult(_, let result, _):
        print("Tool returned: \(result)")
    default:
        break
    }
}
```

## Tool with Input Validation

```swift
struct CalculatorTool: AITool {
    static let name = "calculator"
    static let description = "Perform math calculations"

    struct Arguments: Codable, Sendable {
        let expression: String
    }

    static func execute(arguments: Arguments) async throws -> AIToolResult<EmptyMetadata> {
        // Validate input
        let allowed = CharacterSet(charactersIn: "0123456789+-*/.()")
        guard arguments.expression.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return AIToolResult(content: "Error: Invalid characters in expression")
        }

        // Evaluate expression
        let expression = NSExpression(format: arguments.expression)
        guard let result = expression.expressionValue(with: nil, context: nil) as? NSNumber else {
            return AIToolResult(content: "Error: Could not evaluate expression")
        }

        return AIToolResult(content: "Result: \(result)")
    }
}
```

## Tool Returning Metadata

```swift
struct SearchTool: AITool {
    typealias Metadata = SearchMetadata

    static let name = "search"
    static let description = "Search the web"

    struct Arguments: Codable, Sendable {
        let query: String
    }

    struct SearchMetadata: AIToolMetadata {
        let resultCount: Int
        let sources: [String]
    }

    static func execute(arguments: Arguments) async throws -> AIToolResult<SearchMetadata> {
        let results = await performSearch(arguments.query)

        return AIToolResult(
            content: results.map(\.title).joined(separator: "\n"),
            metadata: SearchMetadata(
                resultCount: results.count,
                sources: results.map(\.url)
            )
        )
    }
}
```

## Best Practices

1. **Clear descriptions** - Help the LLM understand when to use the tool
2. **Validate inputs** - Check arguments before execution, return errors as content
3. **Handle errors gracefully** - Return meaningful error messages in content
4. **Keep tools focused** - One tool, one purpose
5. **Use snake_case names** - e.g., `get_weather` not `getWeather`
6. **Don't duplicate @Parameter** - When using legacy `Tool`, don't re-initialize parameters in `init()`

## Next Steps

- [Multi-Step Agents](04-multi-step-agents.md) - Complex tool workflows
- [Reliability Patterns](06-reliability-patterns.md) - Error handling
