# Tools

> Tool system for extending AI agent capabilities

## Tool Protocol

The unified, instance-based tool protocol.

```swift
public protocol Tool: Sendable {
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
    func execute() async throws -> ToolResult
}
```

### Default Implementations

`Tool` provides defaults for `returnToolResponse`, `jsonSchema()`, `validate(arguments:)`, and parameter binding when you use `@Parameter` or `@Parameter`.

---

## Creating Tools

### Basic Tool

```swift
struct WeatherTool: Tool {
    let name = "get_weather"
    let description = "Get current weather for a city"

    enum TemperatureUnit: String, Codable, CaseIterable {
        case celsius
        case fahrenheit
    }

    @Parameter(description: "City name")
    var city: String = ""

    @Parameter(description: "Temperature unit")
    var unit: TemperatureUnit = .celsius

    init() {}

    func execute() async throws -> ToolResult {
        let temp = unit == .celsius ? "22C" : "72F"
        return ToolResult(content: "Weather in \(city): \(temp), sunny")
    }
}
```

### Tool with Validation

```swift
struct CalculatorTool: Tool {
    let name = "calculate"
    let description = "Perform basic arithmetic"

    @Parameter(description: "First number", .range(-1000...1000))
    var a: Double = 0

    @Parameter(description: "Second number", .range(-1000...1000))
    var b: Double = 0

    enum Operation: String, Codable, CaseIterable {
        case plus = "+"
        case minus = "-"
        case multiply = "*"
        case divide = "/"
    }

    @Parameter(description: "Operation")
    var operation: Operation = .plus

    init() {}

    func execute() async throws -> ToolResult {
        let result: Double
        switch operation {
        case .plus: result = a + b
        case .minus: result = a - b
        case .multiply: result = a * b
        case .divide:
            guard b != 0 else { throw ToolError.executionFailed("Division by zero") }
            result = a / b
        }
        return ToolResult(content: "\(a) \(operation.rawValue) \(b) = \(result)")
    }
}
```

### Tool with Metadata

```swift
struct SearchTool: Tool {
    struct SearchMetadata: ToolMetadata {
        let resultCount: Int
        let sources: [String]
    }

    let name = "search"
    let description = "Search the web"

    @Parameter(description: "Search query")
    var query: String = ""

    init() {}

    func execute() async throws -> ToolResult {
        let results = await performSearch(query)
        let metadata = SearchMetadata(
            resultCount: results.count,
            sources: results.map(\.url)
        )
        return ToolResult(
            content: results.map(\.title).joined(separator: "\n"),
            metadata: metadata
        )
    }
}
```

---

## ToolResult

```swift
public struct ToolResult: Sendable {
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

    @Parameter(description: "City name")
    var city: String = ""

    func execute() async throws -> ToolResult {
        let args = WeatherRenderArgs(city: city, temperature: 72, condition: "Sunny")
        let jsonData = try JSONEncoder().encode(args)
        let metadata = RenderMetadata(toolName: name, jsonData: jsonData)
        return ToolResult(content: "Weather in \(city): 72°F, Sunny", metadata: metadata)
    }

    func render(from data: Data) -> AnyView {
        // Decode and render
        // ...
        AnyView(Text("Rendered UI"))
    }
}
```

---

## ToolRegistry

Thread-safe registry for tool management.

```swift
let registry = ToolRegistry()

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
ToolRegistry.registerAll(tools: [WeatherTool.self, CalculatorTool.self])
let toolType = ToolRegistry.toolType(forName: "get_weather")
```

---

## Built-In Tools

Provider-native tools that execute server-side. Add via `builtInTools` on requests or agents.

```swift
let request = AITextRequest(
    messages: [.user("Search the web for Swift concurrency")],
    model: "gpt-4o",
    builtInTools: [.webSearchDefault, .codeExecutionDefault]
)
```

| Tool | Description | Providers |
|------|-------------|-----------|
| `.webSearch` / `.webSearchDefault` | Web search grounding | OpenAI, Anthropic, Gemini |
| `.codeExecution` / `.codeExecutionDefault` | Server-side code execution | OpenAI, Anthropic, Gemini |
| `.fileSearch(config)` | Vector store search | OpenAI |
| `.imageGeneration` / `.imageGenerationDefault` | Image generation | OpenAI |
| `.urlContext` | URL content fetching | Gemini |
| `.computerUse` / `.computerUseDefault` | Screen interaction | OpenAI, Anthropic |

For computer use details, see [Computer Use](computer-use.md).

---

## Notes on Parameters

- `@Parameter` and `@Parameter` are equivalent. Prefer `@Parameter` for new tools.
- Do **not** re-initialize parameter wrappers inside `init()`. The property wrapper declaration is the single source of truth.
- Enums are supported (recommended: `Codable & CaseIterable`), and enum values are emitted in JSON schema.

## See Also

- [Computer Use](computer-use.md) - Screen interaction tools
- [Agents](agents.md) - Using tools with agents
- [Core Protocols](core-protocols.md)
