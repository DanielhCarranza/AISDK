# Tool Creation

> Adding custom tools to your AI agents

## Overview

Tools let AI agents interact with external systems - fetching data, performing calculations, or executing actions.

## Creating a Simple Tool

```swift
import AISDK

struct WeatherTool: AITool {
    static let name = "get_weather"
    static let description = "Get current weather for a city"

    struct Parameters: Codable, Sendable {
        let city: String
        let unit: TemperatureUnit?

        enum TemperatureUnit: String, Codable {
            case celsius, fahrenheit
        }
    }

    static func execute(parameters: Parameters) async throws -> AIToolResult {
        // In real code, call a weather API here
        let unit = parameters.unit ?? .fahrenheit
        let temp = unit == .celsius ? "22C" : "72F"

        return AIToolResult(
            content: "Weather in \(parameters.city): \(temp), sunny"
        )
    }
}
```

## Using Tools with Agent

```swift
let agent = AIAgentActor(
    model: client,
    tools: [WeatherTool.self],
    systemPrompt: "You can check the weather."
)

let result = try await agent.execute(
    messages: [.user("What's the weather in Tokyo?")]
)

// Agent calls WeatherTool automatically
print(result.text)
// "The weather in Tokyo is 72F and sunny."
```

## Tool with Validation

```swift
struct CalculatorTool: AITool {
    static let name = "calculator"
    static let description = "Perform math calculations"

    struct Parameters: Codable, Sendable {
        let expression: String
    }

    static func validate(parameters: Parameters) throws {
        // Only allow safe characters
        let allowed = CharacterSet(charactersIn: "0123456789+-*/.()")
        guard parameters.expression.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw AIToolError.invalidParameters("Invalid expression")
        }
    }

    static func execute(parameters: Parameters) async throws -> AIToolResult {
        try validate(parameters: parameters)

        // Use NSExpression for safe evaluation
        let expression = NSExpression(format: parameters.expression)
        guard let result = expression.expressionValue(with: nil, context: nil) as? NSNumber else {
            throw AIToolError.executionFailed("Could not evaluate")
        }

        return AIToolResult(content: "Result: \(result)")
    }
}
```

## Tool Returning Metadata

```swift
struct SearchTool: AITool {
    static let name = "search"
    static let description = "Search the web"

    struct Parameters: Codable, Sendable {
        let query: String
    }

    static func execute(parameters: Parameters) async throws -> AIToolResult {
        let results = await performSearch(parameters.query)

        return AIToolResult(
            content: results.map(\.title).joined(separator: "\n"),
            metadata: SearchMetadata(resultCount: results.count)
        )
    }
}

struct SearchMetadata: Codable, Sendable {
    let resultCount: Int
}
```

## Best Practices

1. **Clear descriptions** - Help the LLM understand when to use the tool
2. **Validate inputs** - Check parameters before execution
3. **Handle errors gracefully** - Return meaningful error messages
4. **Keep tools focused** - One tool, one purpose

## Next Steps

- [Multi-Step Agents](04-multi-step-agents.md) - Complex tool workflows
- [Reliability Patterns](06-reliability-patterns.md) - Error handling
