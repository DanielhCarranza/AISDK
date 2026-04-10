# Core Protocols

> Foundational protocols that define AISDK's architecture

## LLM

The unified interface for all language model providers.

```swift
public protocol LLM: Actor, Sendable {
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
    var model: any LLM { get }

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
    case stateChange(AIAgentState)
    case messageAdded(AIMessage)
    case messageUpdated(AIMessage, isPending: Bool)
    case textDelta(String)
    case text(String)
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCall(id: String, name: String, arguments: String)
    case toolResult(id: String, result: String, metadata: ToolMetadata?)
    case start
    case finish(text: String, usage: AIUsage)
    case error(Error)
}
```

---

## AITool

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

### AIToolResult

Result returned from tool execution:

```swift
public struct AIToolResult: Sendable {
    /// Text content of the result
    public let content: String

    /// Optional typed metadata
    public let metadata: ToolMetadata?

    /// Optional artifacts (files, images, etc.)
    public let artifacts: [ToolArtifact]?
}
```

### Example Tool

```swift
struct WeatherTool: AITool {
    enum TemperatureUnit: String, Codable, CaseIterable {
        case celsius
        case fahrenheit
    }

    let name = "get_weather"
    let description = "Get current weather for a city"

    @AIParameter(description: "City name")
    var city: String = ""

    @AIParameter(description: "Temperature unit")
    var unit: TemperatureUnit = .celsius

    init() {}

    func execute() async throws -> AIToolResult {
        let weather = await fetchWeather(city: city)
        return AIToolResult(content: "Weather in \(city): \(weather)")
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
LLM (protocol)
├── OpenRouterClient (actor)
└── MockLLM (class, for testing)

AIAgent (protocol)
└── Agent (actor)

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
