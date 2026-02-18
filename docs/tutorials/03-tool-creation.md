# Tool Creation

> Adding custom tools to your AI agents

## Overview

Tools let AI agents interact with external systems - fetching data, performing calculations, or executing actions.

AISDK provides a single, unified tool system:
- **`AITool`** - Instance-based, parameterized with `@AIParameter` (or `@Parameter`).

## Creating a Simple AITool

```swift
import AISDK

struct WeatherTool: AITool {
    let name = "get_weather"
    let description = "Get current weather for a city"

    enum TemperatureUnit: String, Codable, CaseIterable {
        case celsius
        case fahrenheit
    }

    @AIParameter(description: "City name")
    var city: String = ""

    @AIParameter(description: "Temperature unit")
    var unit: TemperatureUnit = .fahrenheit

    init() {}

    func execute() async throws -> AIToolResult {
        // In real code, call a weather API here
        let temp = unit == .celsius ? "22C" : "72F"
        return AIToolResult(content: "Weather in \(city): \(temp), sunny")
    }
}
```

## Tool with Input Validation

```swift
struct CalculatorTool: AITool {
    let name = "calculate"
    let description = "Perform math calculations"

    @AIParameter(description: "First number", .range(-1000...1000))
    var a: Double = 0

    @AIParameter(description: "Second number", .range(-1000...1000))
    var b: Double = 0

    enum Operation: String, Codable, CaseIterable {
        case plus = "+"
        case minus = "-"
        case multiply = "*"
        case divide = "/"
    }

    @AIParameter(description: "Operation")
    var operation: Operation = .plus

    init() {}

    func execute() async throws -> AIToolResult {
        let result: Double
        switch operation {
        case .plus: result = a + b
        case .minus: result = a - b
        case .multiply: result = a * b
        case .divide:
            guard b != 0 else { throw ToolError.executionFailed("Division by zero") }
            result = a / b
        }
        return AIToolResult(content: "\(a) \(operation.rawValue) \(b) = \(result)")
    }
}
```

## Tool Returning Metadata

```swift
struct SearchTool: AITool {
    struct SearchMetadata: ToolMetadata {
        let resultCount: Int
        let sources: [String]
    }

    let name = "search"
    let description = "Search the web"

    @AIParameter(description: "Search query")
    var query: String = ""

    init() {}

    func execute() async throws -> AIToolResult {
        let results = await performSearch(query)
        let metadata = SearchMetadata(
            resultCount: results.count,
            sources: results.map(\.url)
        )
        return AIToolResult(
            content: results.map(\.title).joined(separator: "\n"),
            metadata: metadata
        )
    }
}
```

## Renderable Tool (UI)

```swift
import SwiftUI

struct WeatherRenderArgs: Codable {
    let city: String
    let temperature: Double
    let condition: String
}

struct WeatherToolUI: RenderableTool {
    let name = "get_weather"
    let description = "Get the current weather in a given city"

    @AIParameter(description: "City name")
    var city: String = ""

    init() {}

    func execute() async throws -> AIToolResult {
        let args = WeatherRenderArgs(city: city, temperature: 72, condition: "Sunny")
        let jsonData = try JSONEncoder().encode(args)
        let metadata = RenderMetadata(toolName: name, jsonData: jsonData)
        return AIToolResult(content: "Weather in \(city): 72°F, Sunny", metadata: metadata)
    }

    func render(from data: Data) -> AnyView {
        guard let args = try? JSONDecoder().decode(WeatherRenderArgs.self, from: data) else {
            return AnyView(Text("Unable to render"))
        }
        return AnyView(Text("\(args.city): \(Int(args.temperature))°"))
    }
}
```

## Using Tools with Agent

```swift
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

## Best Practices

1. **Clear descriptions** - Help the LLM understand when to use the tool
2. **Validate inputs** - Check arguments before execution, return errors as content
3. **Handle errors gracefully** - Return meaningful error messages in content
4. **Keep tools focused** - One tool, one purpose
5. **Use snake_case names** - e.g., `get_weather` not `getWeather`
6. **Don’t duplicate wrappers** - When using `@Parameter`/`@AIParameter`, do not re-initialize in `init()`

## Notes on @Parameter vs @AIParameter

- They are equivalent. Prefer `@AIParameter` for new code.
- Both support validation and enum inference.

## Next Steps

- [Multi-Step Agents](04-multi-step-agents.md) - Complex tool workflows
- [Reliability Patterns](06-reliability-patterns.md) - Error handling
