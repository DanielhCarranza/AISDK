# Tools

> Tool system for extending AI agent capabilities

## AITool Protocol

The unified, instance-based tool protocol.

```swift
public protocol AITool: Sendable {
    /// Tool identifier
    var name: String { get }

    /// Human-readable description
    var description: String { get }

    /// Whether to return result directly to the user without model mediation
    var returnToolResponse: Bool { get }

    /// Initialize tool with default parameter values
    init()

    /// Generate JSON schema for parameters
    static func jsonSchema() -> ToolSchema

    /// Validate parameters before execution
    static func validate(arguments: [String: Any]) throws

    /// Bind parameters to the tool instance
    mutating func setParameters(from arguments: [String: Any]) throws

    /// Validate and bind parameters from JSON data
    mutating func validateAndSetParameters(_ argumentsData: Data) throws -> Self

    /// Execute the tool
    func execute() async throws -> AIToolResult
}
```

### Default Implementations

`AITool` provides defaults for `returnToolResponse`, `jsonSchema()`, `validate(arguments:)`, and parameter binding when you use `@AIParameter` or `@Parameter`.

---

## Creating Tools

### Basic Tool

```swift
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
    var unit: TemperatureUnit = .celsius

    init() {}

    func execute() async throws -> AIToolResult {
        let temp = unit == .celsius ? "22C" : "72F"
        return AIToolResult(content: "Weather in \(city): \(temp), sunny")
    }
}
```

### Tool with Validation

```swift
struct CalculatorTool: AITool {
    let name = "calculate"
    let description = "Perform basic arithmetic"

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

### Tool with Metadata

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

---

## AIToolResult

```swift
public struct AIToolResult: Sendable {
    public let content: String
    public let metadata: ToolMetadata?
    public let artifacts: [ToolArtifact]?

    public init(content: String, metadata: ToolMetadata? = nil, artifacts: [ToolArtifact]? = nil)
}
```

### ToolArtifact

```swift
public struct ToolArtifact: Sendable, Codable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case file, image, json, text, other
    }

    public let name: String
    public let kind: Kind
    public let mimeType: String?
    public let data: Data?
    public let url: URL?
}
```

---

## RenderableTool

Tools can optionally render a SwiftUI view from metadata by conforming to `RenderableTool`.

```swift
struct WeatherToolUI: RenderableTool {
    let name = "get_weather"
    let description = "Get the current weather in a given city"

    @AIParameter(description: "City name")
    var city: String = ""

    func execute() async throws -> AIToolResult {
        let args = WeatherRenderArgs(city: city, temperature: 72, condition: "Sunny")
        let jsonData = try JSONEncoder().encode(args)
        let metadata = RenderMetadata(toolName: name, jsonData: jsonData)
        return AIToolResult(content: "Weather in \(city): 72°F, Sunny", metadata: metadata)
    }

    func render(from data: Data) -> AnyView {
        // Decode and render
        // ...
        AnyView(Text("Rendered UI"))
    }
}
```

---

## AIToolRegistry

Thread-safe registry for tool management.

```swift
let registry = AIToolRegistry()

// Register tools
registry.register(WeatherTool.self)
registry.register(CalculatorTool.self)

// Execute by name
let result = try await registry.execute(
    name: "get_weather",
    arguments: #"{"city":"Tokyo","unit":"celsius"}"#
)
print(result.content)
```

You can also use the shared registry:

```swift
AIToolRegistry.registerAll(tools: [WeatherTool.self, CalculatorTool.self])
let toolType = AIToolRegistry.toolType(forName: "get_weather")
```

---

## Notes on Parameters

- `@AIParameter` and `@Parameter` are equivalent. Prefer `@AIParameter` for new tools.
- Do **not** re-initialize parameter wrappers inside `init()`. The property wrapper declaration is the single source of truth.
- Enums are supported (recommended: `Codable & CaseIterable`), and enum values are emitted in JSON schema.

## See Also

- [Agents](agents.md) - Using tools with agents
- [Core Protocols](core-protocols.md)
