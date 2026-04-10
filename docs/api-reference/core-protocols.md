# Core Protocols

> Foundational protocols that define AISDK's architecture

## LLM

The unified interface for all language model providers.

```swift
public protocol LLM: Sendable {
    /// Provider name (e.g., "openai", "anthropic", "google")
    var provider: String { get }

    /// Model identifier (e.g., "gpt-4", "claude-3-opus")
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
public struct LLMCapabilities: OptionSet, Hashable, Sendable {
    // Input/Output Modalities
    public static let text = LLMCapabilities(rawValue: 1 << 0)
    public static let vision = LLMCapabilities(rawValue: 1 << 1)
    public static let audio = LLMCapabilities(rawValue: 1 << 2)
    public static let video = LLMCapabilities(rawValue: 1 << 3)
    public static let pdf = LLMCapabilities(rawValue: 1 << 4)

    // Functional Capabilities
    public static let tools = LLMCapabilities(rawValue: 1 << 5)
    public static let functionCalling = LLMCapabilities(rawValue: 1 << 6)
    public static let codeExecution = LLMCapabilities(rawValue: 1 << 7)
    public static let structuredOutputs = LLMCapabilities(rawValue: 1 << 8)
    public static let jsonMode = LLMCapabilities(rawValue: 1 << 9)

    // Advanced Capabilities
    public static let reasoning = LLMCapabilities(rawValue: 1 << 10)
    public static let thinking = LLMCapabilities(rawValue: 1 << 11)
    public static let search = LLMCapabilities(rawValue: 1 << 12)
    public static let webSearch = LLMCapabilities(rawValue: 1 << 13)
    public static let grounding = LLMCapabilities(rawValue: 1 << 14)

    // Generation Capabilities
    public static let imageGeneration = LLMCapabilities(rawValue: 1 << 15)
    public static let audioGeneration = LLMCapabilities(rawValue: 1 << 16)
    public static let videoGeneration = LLMCapabilities(rawValue: 1 << 17)
    public static let speechToText = LLMCapabilities(rawValue: 1 << 18)
    public static let textToSpeech = LLMCapabilities(rawValue: 1 << 19)

    // Operational Capabilities
    public static let streaming = LLMCapabilities(rawValue: 1 << 20)
    public static let realtime = LLMCapabilities(rawValue: 1 << 21)
    public static let liveAPI = LLMCapabilities(rawValue: 1 << 22)
    public static let caching = LLMCapabilities(rawValue: 1 << 23)
}
```

### Usage

```swift
// Check capabilities before using features
if model.capabilities.contains(.vision) {
    // Model supports image input
}
if model.capabilities.contains(.tools) {
    // Model supports tool calling
}
```

---

## AIAgent

The unified interface for AI agents with tool execution.

```swift
public protocol AIAgent: Sendable {
    /// The agent's unique identifier
    var agentId: String { get }

    /// The name of this agent
    var name: String? { get }

    /// Current agent state
    var state: AIAgentState { get }

    /// Current message history
    var messages: [AIMessage] { get }

    /// Available tools for this agent
    var tools: [ToolSchema] { get }

    /// The underlying language model
    var model: LLM { get }

    /// Send a message and get a response (non-streaming)
    func send(_ message: String) async throws -> AIAgentResponse

    /// Send a message with streaming response
    func sendStream(_ message: String, requiredTool: String?) -> AsyncThrowingStream<AIAgentEvent, Error>

    /// Reset agent state and message history
    func reset()

    /// Set message history directly
    func setMessages(_ messages: [AIMessage])
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
public protocol ProviderClient: Sendable {
    /// Provider identifier
    var providerId: String { get }

    /// Human-readable display name
    var displayName: String { get }

    /// Base URL for API requests
    var baseURL: URL { get }

    /// Current health status
    var healthStatus: ProviderHealthStatus { get async }

    /// Whether provider is accepting requests
    var isAvailable: Bool { get async }

    /// Execute a non-streaming request
    func execute(request: ProviderRequest) async throws -> ProviderResponse

    /// Execute a streaming request
    func stream(
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
LLM (protocol: Sendable)
├── ProviderLanguageModelAdapter (struct)
├── AILanguageModelAdapter (struct)
└── MockLLM (class, for testing)

AIAgent (protocol: Sendable)
└── Agent (actor)

Tool (protocol: Sendable)
├── WeatherTool (struct)
├── SearchTool (struct)
└── [User-defined tools]

ProviderClient (protocol: Sendable)
├── OpenRouterClient (actor)
├── LiteLLMClient (actor)
├── AnthropicClientAdapter (actor)
└── GeminiClientAdapter (actor)
```

## See Also

- [Models](models.md) - Request and response types
- [Agents](agents.md) - Agent implementation details
- [Tools](tools.md) - Tool system documentation
- [Providers](providers.md) - Provider implementations
