# Core Protocols

> Foundational protocols that define AISDK's architecture

## AILanguageModel

The unified interface for all language model providers.

```swift
public protocol AILanguageModel: Actor, Sendable {
    /// Provider identifier (e.g., "openrouter", "litellm")
    var provider: String { get }

    /// Model identifier within the provider
    var modelId: String { get }

    /// Capabilities supported by this model
    var capabilities: LLMCapabilities { get }

    /// Generate text response (non-streaming)
    func generateText(request: AITextRequest) async throws -> AITextResult

    /// Stream text response
    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>

    /// Generate structured object (non-streaming)
    func generateObject<T: Codable & Sendable>(
        request: AIObjectRequest<T>
    ) async throws -> AIObjectResult<T>

    /// Stream structured object
    func streamObject<T: Codable & Sendable>(
        request: AIObjectRequest<T>
    ) -> AsyncThrowingStream<AIStreamEvent, Error>
}
```

### LLMCapabilities

Flags indicating model capabilities:

```swift
public struct LLMCapabilities: OptionSet, Sendable {
    public static let streaming = LLMCapabilities(rawValue: 1 << 0)
    public static let toolCalling = LLMCapabilities(rawValue: 1 << 1)
    public static let vision = LLMCapabilities(rawValue: 1 << 2)
    public static let audio = LLMCapabilities(rawValue: 1 << 3)
    public static let structuredOutput = LLMCapabilities(rawValue: 1 << 4)
    public static let reasoning = LLMCapabilities(rawValue: 1 << 5)
}
```

### Usage

```swift
// Check capabilities before using features
if model.capabilities.contains(.vision) {
    let request = AITextRequest(messages: [
        .user(parts: [.text("Describe this"), .imageURL(url)])
    ])
}
```

---

## AIAgent

The unified interface for AI agents with tool execution.

```swift
public protocol AIAgent: Actor {
    /// The underlying language model
    var model: any AILanguageModel { get }

    /// Current agent state
    var state: AIAgentState { get }

    /// Current message history
    var messages: [AIMessage] { get }

    /// Send a message and get a response
    func send(_ message: AIMessage) async throws -> AIAgentResponse

    /// Send a message with streaming response
    func sendStream(_ message: AIMessage) -> AsyncThrowingStream<AIAgentEvent, Error>

    /// Reset agent state and message history
    func reset() async

    /// Set message history directly
    func setMessages(_ messages: [AIMessage]) async
}
```

### AIAgentState

Represents the current state of an agent:

```swift
public enum AIAgentState: Sendable, Equatable {
    case idle
    case thinking
    case executingTool(name: String)
    case responding
    case error(String)
}
```

### AIAgentResponse

Response from a non-streaming agent execution:

```swift
public struct AIAgentResponse: Sendable {
    public let text: String
    public let toolCalls: [AIToolCall]
    public let toolResults: [AIToolResult]
    public let usage: AIUsage
    public let finishReason: AIFinishReason
}
```

### AIAgentEvent

Events emitted during streaming agent execution:

```swift
public enum AIAgentEvent: Sendable {
    case stateChanged(AIAgentState)
    case textDelta(String)
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCallFinish(id: String, name: String, arguments: String)
    case toolResult(id: String, result: AIToolResult)
    case finish(reason: AIFinishReason, usage: AIUsage)
    case error(Error)
}
```

---

## AITool

The immutable, Sendable-compliant tool protocol.

```swift
public protocol AITool: Sendable {
    /// Type for tool arguments (must be Codable)
    associatedtype Arguments: Codable & Sendable

    /// Type for execution metadata
    associatedtype Metadata: Sendable = EmptyMetadata

    /// Unique tool name (snake_case recommended)
    static var name: String { get }

    /// Human-readable description for LLM
    static var description: String { get }

    /// JSON Schema for arguments
    static var argumentsSchema: [String: Any] { get }

    /// Execution timeout (default: 30 seconds)
    static var timeout: Duration { get }

    /// Execute the tool with parsed arguments
    static func execute(
        arguments: Arguments,
        metadata: Metadata
    ) async throws -> AIToolResult
}
```

### Default Implementations

```swift
extension AITool {
    public static var timeout: Duration { .seconds(30) }
}

extension AITool where Metadata == EmptyMetadata {
    public static func execute(
        arguments: Arguments,
        metadata: EmptyMetadata = EmptyMetadata()
    ) async throws -> AIToolResult {
        // Default implementation
    }
}
```

### AIToolResult

Result returned from tool execution:

```swift
public struct AIToolResult: Sendable, Equatable {
    /// Text content of the result
    public let content: String

    /// Whether this result represents an error
    public let isError: Bool

    /// Optional artifacts (files, images, etc.)
    public let artifacts: [AIToolArtifact]

    public init(
        content: String,
        isError: Bool = false,
        artifacts: [AIToolArtifact] = []
    )

    /// Create an error result
    public static func error(_ message: String) -> AIToolResult
}
```

### Example Tool

```swift
struct WeatherTool: AITool {
    struct Arguments: Codable, Sendable {
        let city: String
        let units: String?
    }

    static let name = "get_weather"
    static let description = "Get current weather for a city"

    static var argumentsSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "city": ["type": "string", "description": "City name"],
                "units": ["type": "string", "enum": ["celsius", "fahrenheit"]]
            ],
            "required": ["city"]
        ]
    }

    static func execute(
        arguments: Arguments,
        metadata: EmptyMetadata
    ) async throws -> AIToolResult {
        let weather = await fetchWeather(city: arguments.city)
        return AIToolResult(content: "Weather in \(arguments.city): \(weather)")
    }
}
```

---

## ProviderClient

Protocol for provider-level API clients.

```swift
public protocol ProviderClient: Actor, Sendable {
    /// Provider identifier
    nonisolated var providerId: String { get }

    /// Human-readable display name
    nonisolated var displayName: String { get }

    /// Base URL for API requests
    nonisolated var baseURL: URL { get }

    /// Current health status
    var healthStatus: ProviderHealthStatus { get }

    /// Whether provider is accepting requests
    var isAvailable: Bool { get }

    /// Execute a non-streaming request
    func execute(request: ProviderRequest) async throws -> ProviderResponse

    /// Execute a streaming request
    nonisolated func stream(
        request: ProviderRequest
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error>

    /// Get available models
    var availableModels: [String] { get async throws }

    /// Check if a model is available
    func isModelAvailable(_ modelId: String) async -> Bool

    /// Get capabilities for a model
    func capabilities(for modelId: String) async -> LLMCapabilities?
}
```

### ProviderHealthStatus

```swift
public enum ProviderHealthStatus: Sendable {
    case unknown
    case healthy
    case degraded(reason: String)
    case unhealthy(reason: String)

    public var acceptsTraffic: Bool {
        switch self {
        case .unknown, .healthy, .degraded:
            return true
        case .unhealthy:
            return false
        }
    }
}
```

---

## Type Hierarchy

```
AILanguageModel (protocol)
├── OpenRouterClient (actor)
└── MockAILanguageModel (class, for testing)

AIAgent (protocol)
└── AIAgentActor (actor)

AITool (protocol)
├── WeatherTool (struct)
├── SearchTool (struct)
└── [User-defined tools]

ProviderClient (protocol)
├── OpenRouterClient (actor)
└── LiteLLMClient (actor)
```

## See Also

- [Models](models.md) - Request and response types
- [Agents](agents.md) - Agent implementation details
- [Tools](tools.md) - Tool system documentation
- [Providers](providers.md) - Provider implementations
