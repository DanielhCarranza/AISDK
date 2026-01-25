# Tools

> Tool system for extending AI agent capabilities

## AITool Protocol

The immutable, Sendable-compliant tool protocol.

```swift
public protocol AITool: Sendable {
    /// Type for tool arguments
    associatedtype Arguments: Codable & Sendable

    /// Type for execution metadata
    associatedtype Metadata: Sendable = EmptyMetadata

    /// Unique tool name (snake_case)
    static var name: String { get }

    /// Human-readable description
    static var description: String { get }

    /// JSON Schema for arguments
    static var argumentsSchema: [String: Any] { get }

    /// Execution timeout
    static var timeout: Duration { get }

    /// Execute the tool
    static func execute(
        arguments: Arguments,
        metadata: Metadata
    ) async throws -> AIToolResult
}
```

### Default Implementations

```swift
extension AITool {
    // Default 30-second timeout
    public static var timeout: Duration { .seconds(30) }
}

extension AITool where Metadata == EmptyMetadata {
    // Simplified execute without metadata
    public static func execute(arguments: Arguments) async throws -> AIToolResult {
        try await execute(arguments: arguments, metadata: EmptyMetadata())
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

    static var argumentsSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "expression": [
                    "type": "string",
                    "description": "Math expression to evaluate"
                ]
            ],
            "required": ["expression"]
        ]
    }

    static func execute(
        arguments: Arguments,
        metadata: EmptyMetadata
    ) async throws -> AIToolResult {
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

    static var argumentsSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Search query"
                ],
                "maxResults": [
                    "type": "integer",
                    "description": "Maximum results (default: 10)"
                ],
                "language": [
                    "type": "string",
                    "description": "Language code (default: en)"
                ]
            ],
            "required": ["query"]
        ]
    }

    static func execute(
        arguments: Arguments,
        metadata: EmptyMetadata
    ) async throws -> AIToolResult {
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
    struct Arguments: Codable, Sendable {
        let query: String
    }

    struct Metadata: Sendable {
        let connection: DatabaseConnection
        let userId: String
    }

    static let name = "database_query"
    static let description = "Execute a database query"

    static var argumentsSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "query": ["type": "string"]
            ],
            "required": ["query"]
        ]
    }

    static func execute(
        arguments: Arguments,
        metadata: Metadata
    ) async throws -> AIToolResult {
        let results = try await metadata.connection.execute(
            arguments.query,
            userId: metadata.userId
        )
        return AIToolResult(content: results.description)
    }
}
```

---

## AIToolResult

Result returned from tool execution.

```swift
public struct AIToolResult: Sendable, Equatable {
    /// Text content
    public let content: String

    /// Whether this is an error
    public let isError: Bool

    /// Optional artifacts
    public let artifacts: [AIToolArtifact]

    // Initializers
    public init(
        content: String,
        isError: Bool = false,
        artifacts: [AIToolArtifact] = []
    )

    // Convenience methods
    public static func error(_ message: String) -> AIToolResult
    public static func success(_ content: String) -> AIToolResult
}
```

### AIToolArtifact

```swift
public struct AIToolArtifact: Sendable, Equatable {
    public let name: String
    public let mimeType: String
    public let data: Data

    public init(name: String, mimeType: String, data: Data)
}
```

### Usage

```swift
// Simple result
return AIToolResult(content: "Temperature: 72F")

// Error result
return AIToolResult.error("City not found")

// Result with artifact
let imageData = try await generateChart(data)
return AIToolResult(
    content: "Chart generated successfully",
    artifacts: [
        AIToolArtifact(
            name: "chart.png",
            mimeType: "image/png",
            data: imageData
        )
    ]
)
```

---

## AIToolRegistry

Thread-safe registry for tool management.

```swift
public actor AIToolRegistry {
    /// Register a tool type
    public func register<T: AITool>(_ toolType: T.Type)

    /// Get tool by name
    public func tool(named name: String) -> AnyAITool?

    /// Get all registered tool names
    public var registeredNames: [String]

    /// Check if tool is registered
    public func isRegistered(_ name: String) -> Bool

    /// Unregister a tool
    public func unregister(_ name: String)

    /// Clear all tools
    public func clear()
}
```

### Usage

```swift
let registry = AIToolRegistry()

// Register tools
await registry.register(WeatherTool.self)
await registry.register(SearchTool.self)

// Look up tool
if let tool = await registry.tool(named: "weather") {
    let result = try await tool.execute(
        arguments: Data(#"{"city":"Tokyo"}"#.utf8)
    )
}

// List all tools
let names = await registry.registeredNames
// ["weather", "search"]
```

---

## AnyAITool

Type-erased wrapper for AITool types.

```swift
public struct AnyAITool: Sendable {
    /// Tool name
    public let name: String

    /// Tool description
    public let description: String

    /// Arguments schema
    public let argumentsSchema: [String: Any]

    /// Timeout duration
    public let timeout: Duration

    /// Execute with raw JSON arguments
    public func execute(arguments: Data) async throws -> AIToolResult

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

// Use with agent
let agent = AIAgentActor(
    model: model,
    tools: tools
)
```

---

## AIToolExecutor

Utility for executing tools with timeout and argument parsing.

```swift
public struct AIToolExecutor: Sendable {
    /// Execute a tool by name
    public static func execute<T: AITool>(
        _ toolType: T.Type,
        arguments: Data,
        metadata: T.Metadata
    ) async throws -> AIToolResult

    /// Execute with timeout
    public static func executeWithTimeout<T: AITool>(
        _ toolType: T.Type,
        arguments: Data,
        metadata: T.Metadata,
        timeout: Duration
    ) async throws -> AIToolResult
}
```

### Error Types

```swift
public enum AIToolError: Error, Sendable {
    /// Arguments failed to decode
    case invalidArguments(String)

    /// Tool execution timed out
    case timeout(Duration)

    /// Tool not found
    case notFound(String)

    /// Execution failed
    case executionFailed(Error)
}
```

---

## Tool Schema Generation

### JSON Schema Format

```swift
static var argumentsSchema: [String: Any] {
    [
        "type": "object",
        "properties": [
            "paramName": [
                "type": "string",        // string, number, integer, boolean, array, object
                "description": "...",
                "enum": ["a", "b"],       // Optional: allowed values
                "default": "a"            // Optional: default value
            ]
        ],
        "required": ["paramName"]         // Required parameters
    ]
}
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
static func execute(arguments: Arguments, metadata: EmptyMetadata) async throws -> AIToolResult {
    do {
        let result = try await fetchData(arguments.query)
        return AIToolResult(content: result)
    } catch {
        // Return error as content so agent can adapt
        return AIToolResult.error("Failed to fetch data: \(error.localizedDescription)")
    }
}
```

### 4. Use Appropriate Timeouts

```swift
struct SlowAPITool: AITool {
    // Override for slow operations
    static var timeout: Duration { .seconds(60) }
}
```

### 5. Validate Arguments

```swift
static func execute(arguments: Arguments, metadata: EmptyMetadata) async throws -> AIToolResult {
    guard !arguments.query.isEmpty else {
        return AIToolResult.error("Query cannot be empty")
    }
    // ...
}
```

## See Also

- [Core Protocols](core-protocols.md) - AITool protocol
- [Agents](agents.md) - Using tools with agents
- [Errors](errors.md) - AIToolError details
