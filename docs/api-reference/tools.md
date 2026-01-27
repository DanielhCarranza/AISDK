# Tools

> Tool system for extending AI agent capabilities

## AITool Protocol

The immutable, Sendable-compliant tool protocol.

```swift
public protocol AITool: Sendable {
    /// Type for tool arguments
    associatedtype Arguments: Codable & Sendable

    /// Type for result metadata (use EmptyMetadata for none)
    associatedtype Metadata: AIToolMetadata = EmptyMetadata

    /// Unique tool name (snake_case)
    static var name: String { get }

    /// Human-readable description
    static var description: String { get }

    /// Execution timeout in seconds
    static var timeout: TimeInterval { get }

    /// Execute the tool
    static func execute(arguments: Arguments) async throws -> AIToolResult<Metadata>

    /// Generate JSON schema for arguments
    static func generateSchema() -> ToolSchema
}
```

### Default Implementations

```swift
extension AITool {
    // Default 60-second timeout
    public static var timeout: TimeInterval { 60.0 }

    // Default schema generation (override for detailed schemas)
    public static func generateSchema() -> ToolSchema {
        ToolSchema(
            type: "function",
            function: ToolFunction(
                name: name,
                description: description,
                parameters: Parameters(type: "object", properties: [:])
            )
        )
    }
}
```

---

## Creating Tools

### Basic Tool

```swift
struct CalculatorTool: AITool {
    struct Arguments: Codable, Sendable {
        let expression: String
    }

    static let name = "calculator"
    static let description = "Evaluate mathematical expressions"

    static func generateSchema() -> ToolSchema {
        ToolSchema(
            type: "function",
            function: ToolFunction(
                name: name,
                description: description,
                parameters: Parameters(
                    type: "object",
                    properties: [
                        "expression": PropertyDefinition(
                            type: "string",
                            description: "Math expression to evaluate"
                        )
                    ],
                    required: ["expression"]
                )
            )
        )
    }

    static func execute(arguments: Arguments) async throws -> AIToolResult<EmptyMetadata> {
        let result = try evaluate(arguments.expression)
        return AIToolResult(content: "\(result)")
    }
}
```

### Tool with Optional Arguments

```swift
struct SearchTool: AITool {
    struct Arguments: Codable, Sendable {
        let query: String
        let maxResults: Int?
        let language: String?
    }

    static let name = "web_search"
    static let description = "Search the web for information"

    static func generateSchema() -> ToolSchema {
        ToolSchema(
            type: "function",
            function: ToolFunction(
                name: name,
                description: description,
                parameters: Parameters(
                    type: "object",
                    properties: [
                        "query": PropertyDefinition(
                            type: "string",
                            description: "Search query"
                        ),
                        "max_results": PropertyDefinition(
                            type: "integer",
                            description: "Maximum results (default: 10)"
                        ),
                        "language": PropertyDefinition(
                            type: "string",
                            description: "Language code (default: en)"
                        )
                    ],
                    required: ["query"]
                )
            )
        )
    }

    static func execute(arguments: Arguments) async throws -> AIToolResult<EmptyMetadata> {
        let results = await search(
            query: arguments.query,
            limit: arguments.maxResults ?? 10,
            lang: arguments.language ?? "en"
        )
        return AIToolResult(content: formatResults(results))
    }
}
```

### Tool with Metadata

```swift
struct DatabaseQueryTool: AITool {
    typealias Metadata = QueryMetadata

    struct Arguments: Codable, Sendable {
        let query: String
    }

    struct QueryMetadata: AIToolMetadata {
        let rowCount: Int
        let executionTime: TimeInterval
    }

    static let name = "database_query"
    static let description = "Execute a database query"

    static func generateSchema() -> ToolSchema {
        ToolSchema(
            type: "function",
            function: ToolFunction(
                name: name,
                description: description,
                parameters: Parameters(
                    type: "object",
                    properties: [
                        "query": PropertyDefinition(type: "string", description: "SQL query")
                    ],
                    required: ["query"]
                )
            )
        )
    }

    static func execute(arguments: Arguments) async throws -> AIToolResult<QueryMetadata> {
        let start = Date()
        let results = try await database.execute(arguments.query)
        let elapsed = Date().timeIntervalSince(start)

        return AIToolResult(
            content: results.description,
            metadata: QueryMetadata(rowCount: results.count, executionTime: elapsed)
        )
    }
}
```

---

## AIToolResult

Result returned from tool execution.

```swift
public struct AIToolResult<M: AIToolMetadata>: Sendable {
    /// Text content returned to the LLM
    public let content: String

    /// Optional metadata for UI rendering or other purposes
    public let metadata: M?

    // Initializers
    public init(content: String) where M == EmptyMetadata
    public init(content: String, metadata: M?)
}
```

### AIToolMetadata Protocol

```swift
public protocol AIToolMetadata: Codable, Sendable {}

/// Empty metadata type for tools that don't return metadata
public struct EmptyMetadata: AIToolMetadata, Equatable {
    public init() {}
}
```

### Usage

```swift
// Simple result (no metadata)
return AIToolResult(content: "Temperature: 72F")

// Result with metadata
struct WeatherMetadata: AIToolMetadata {
    let source: String
    let timestamp: Date
}

return AIToolResult(
    content: "Temperature: 72F, sunny",
    metadata: WeatherMetadata(source: "OpenMeteo", timestamp: Date())
)
```

---

## AIToolRegistry

Thread-safe registry for tool management.

```swift
public final class AIToolRegistry: @unchecked Sendable {
    /// Register a tool type
    public func register<T: AITool>(_ toolType: T.Type)

    /// Get tool by name
    public func tool(named name: String) -> AnyAITool?

    /// Get all registered tool names (sorted)
    public var registeredNames: [String]

    /// Get all registered tools as schemas (sorted by name)
    public var schemas: [ToolSchema]

    /// Execute a tool by name
    public func execute(name: String, arguments: String) async throws -> AIToolExecutionResult
}
```

### Usage

```swift
let registry = AIToolRegistry()

// Register tools
registry.register(WeatherTool.self)
registry.register(SearchTool.self)

// Look up tool
if let tool = registry.tool(named: "get_weather") {
    let result = try await tool.execute(arguments: #"{"city":"Tokyo"}"#)
    print(result.content)
}

// List all tools
let names = registry.registeredNames
// ["get_weather", "web_search"]

// Get schemas for LLM function calling
let schemas = registry.schemas
```

---

## AnyAITool

Type-erased wrapper for AITool types.

```swift
public struct AnyAITool: @unchecked Sendable {
    /// Tool name
    public let name: String

    /// Tool description
    public let description: String

    /// Tool's JSON schema
    public let schema: ToolSchema

    /// Timeout in seconds
    public let timeout: TimeInterval

    /// Execute with raw JSON arguments string
    public func execute(arguments: String) async throws -> AIToolExecutionResult

    /// Create from a tool type
    public init<T: AITool>(_ toolType: T.Type)
}
```

### Usage

```swift
// Create type-erased tools
let tools: [AnyAITool] = [
    AnyAITool(WeatherTool.self),
    AnyAITool(SearchTool.self)
]

// Execute a tool
let result = try await tools[0].execute(arguments: #"{"city":"Tokyo"}"#)
print(result.content)
```

---

## AIToolExecutor

Utility for executing tools with timeout and argument parsing.

```swift
public struct AIToolExecutor: Sendable {
    /// Execute a tool with raw JSON arguments
    public static func execute<T: AITool>(
        _ toolType: T.Type,
        arguments: String
    ) async throws -> AIToolExecutionResult
}
```

The executor handles:
- JSON argument parsing with snake_case key support
- Timeout enforcement via the tool's static `timeout` property
- Error wrapping in `AISDKErrorV2` for consistent error handling

### AIToolExecutionResult

```swift
public struct AIToolExecutionResult: Sendable {
    /// Text content returned to the LLM
    public let content: String

    /// Optional type-erased metadata
    public let metadata: AnyAIToolMetadata?
}
```

### Error Types

Tool execution errors are represented using `AISDKErrorV2`:

```swift
// Tool argument parsing failed
AISDKErrorV2(code: .invalidToolArguments, message: "...")

// Tool execution timed out
AISDKErrorV2.toolTimeout(tool: "get_weather", after: 60.0)

// Tool not found
AISDKErrorV2.toolNotFound("unknown_tool")

// Tool execution failed
AISDKErrorV2.toolExecutionFailed(tool: "get_weather", reason: "...")
```

---

## Tool Schema Generation

### Using generateSchema()

```swift
static func generateSchema() -> ToolSchema {
    ToolSchema(
        type: "function",
        function: ToolFunction(
            name: name,
            description: description,
            parameters: Parameters(
                type: "object",
                properties: [
                    "city": PropertyDefinition(
                        type: "string",
                        description: "City name"
                    ),
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
```

### PropertyDefinition Options

```swift
PropertyDefinition(
    type: "string",           // string, number, integer, boolean, array, object
    description: "...",       // Human-readable description
    minimum: 1.0,             // For numbers
    maximum: 100.0,           // For numbers
    minLength: 1,             // For strings
    maxLength: 1000,          // For strings
    pattern: "^[a-z]+$",      // Regex for strings
    enumValues: ["a", "b"]    // Allowed values
)
```

### Supported Types

| Swift Type | JSON Schema Type |
|------------|------------------|
| String | "string" |
| Int | "integer" |
| Double | "number" |
| Bool | "boolean" |
| [T] | "array" |
| [String: T] | "object" |
| Optional<T> | (omit from required) |
| Enum | "string" with "enum" |

---

## Best Practices

### 1. Use Snake Case Names

```swift
static let name = "get_weather"  // Good
static let name = "getWeather"   // Avoid
```

### 2. Provide Clear Descriptions

```swift
static let description = """
    Search the web for current information.
    Returns titles, URLs, and snippets from top results.
    """
```

### 3. Handle Errors Gracefully

```swift
static func execute(arguments: Arguments) async throws -> AIToolResult<EmptyMetadata> {
    do {
        let result = try await fetchData(arguments.query)
        return AIToolResult(content: result)
    } catch {
        // Return error as content so agent can adapt
        return AIToolResult(content: "Error: Failed to fetch data")
    }
}
```

### 4. Use Appropriate Timeouts

```swift
struct SlowAPITool: AITool {
    // Override for slow operations (default is 60 seconds)
    static var timeout: TimeInterval { 120.0 }
}
```

### 5. Validate Arguments

```swift
static func execute(arguments: Arguments) async throws -> AIToolResult<EmptyMetadata> {
    guard !arguments.query.isEmpty else {
        return AIToolResult(content: "Error: Query cannot be empty")
    }
    // ...
}
```

---

## Legacy Tool Protocol

For backward compatibility, AISDK also provides a mutable, instance-based `Tool` protocol.

```swift
public protocol Tool {
    var name: String { get }
    var description: String { get }
    var returnToolResponse: Bool { get }

    init()
    static func jsonSchema() -> ToolSchema
    func execute() async throws -> (content: String, metadata: ToolMetadata?)
    mutating func setParameters(from arguments: [String: Any]) throws
}
```

### Using @Parameter Property Wrapper

The legacy `Tool` protocol uses `@Parameter` property wrappers:

```swift
struct WeatherTool: Tool {
    let name = "get_weather"
    let description = "Get weather for a city"

    @Parameter(description: "City name")
    var city: String = ""

    @Parameter(
        description: "Temperature unit",
        validation: ["enum": ["celsius", "fahrenheit"]]
    )
    var unit: String? = nil

    init() {}

    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Access parameters via self.city, self.unit
        return ("Weather in \(city): sunny", nil)
    }
}
```

**Note**: When using `@Parameter`, you do NOT need to re-initialize parameters in `init()`. The property wrapper declarations are sufficient.

### Bridging Legacy Tools

Use `ToolAdapter` to bridge legacy `Tool` types with the new agent system.

## See Also

- [Core Protocols](core-protocols.md) - AITool protocol
- [Agents](agents.md) - Using tools with agents
- [Errors](errors.md) - Error details
