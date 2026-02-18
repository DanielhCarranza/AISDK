# Providers

> Provider implementations and the ProviderClient protocol

## OpenRouterClient

Primary production provider with access to 200+ models.

```swift
public actor OpenRouterClient: ProviderClient {
    // MARK: - Identity
    public nonisolated let providerId: String  // "openrouter"
    public nonisolated let displayName: String // "OpenRouter"
    public nonisolated let baseURL: URL

    // MARK: - Initialization
    public init(
        apiKey: String,
        baseURL: URL? = nil,
        session: URLSession? = nil,
        appName: String? = nil,
        siteURL: String? = nil
    )
}
```

### Features

- **Single API key** for 200+ models from OpenAI, Anthropic, Google, Meta
- **Automatic fallback** and load balancing
- **Consistent format** (OpenAI-compatible API)
- **Cost-effective routing** options

### Usage

```swift
// Initialize client
let client = OpenRouterClient(
    apiKey: "sk-or-v1-...",
    appName: "MyApp",          // For analytics
    siteURL: "https://myapp.com"
)

// Execute request
let request = ProviderRequest(
    modelId: "anthropic/claude-3-opus",
    messages: [AIMessage.user("Hello!")],
    maxTokens: 1000
)
let response = try await client.execute(request: request)

// Stream response
for try await event in client.stream(request: request) {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .finish(let reason, let usage):
        print("\nDone: \(reason)")
    default:
        break
    }
}
```

### Model Selection

```swift
// List available models
let models = try await client.availableModels

// Check model availability
let available = await client.isModelAvailable("anthropic/claude-3-opus")

// Get model capabilities
let caps = await client.capabilities(for: "openai/gpt-4-turbo")
```

### Health Monitoring

```swift
// Check current status
let status = await client.healthStatus

// Refresh health status
await client.refreshHealthStatus()

// Check availability
if await client.isAvailable {
    // Safe to make requests
}
```

---

## ProviderRequest

Request structure for provider-level API calls.

```swift
public struct ProviderRequest: Sendable {
    /// Model identifier
    public let modelId: String

    /// Conversation messages
    public let messages: [AIMessage]

    /// Maximum tokens to generate
    public let maxTokens: Int?

    /// Sampling temperature
    public let temperature: Double?

    /// Top-p sampling
    public let topP: Double?

    /// Stop sequences
    public let stop: [String]?

    /// Tools in provider format
    public let tools: [ProviderJSONValue]?

    /// Tool choice behavior
    public let toolChoice: ProviderToolChoice?

    /// Response format
    public let responseFormat: ProviderResponseFormat?

    /// Request timeout
    public let timeout: TimeInterval
}
```

### ProviderToolChoice

```swift
public enum ProviderToolChoice: Sendable {
    case auto
    case none
    case required
    case tool(String)
}
```

### ProviderResponseFormat

```swift
public enum ProviderResponseFormat: Sendable {
    case text
    case json
    case jsonSchema(name: String, schema: String)
}
```

---

## ProviderResponse

Response from a provider API call.

```swift
public struct ProviderResponse: Sendable {
    /// Response ID
    public let id: String

    /// Model used
    public let model: String

    /// Provider ID
    public let provider: String

    /// Generated text content
    public let content: String

    /// Tool calls (if any)
    public let toolCalls: [ProviderToolCall]

    /// Token usage
    public let usage: ProviderUsage?

    /// Finish reason
    public let finishReason: ProviderFinishReason

    /// Request latency in milliseconds
    public let latencyMs: Int
}
```

### ProviderToolCall

```swift
public struct ProviderToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let arguments: String
}
```

### ProviderUsage

```swift
public struct ProviderUsage: Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let cachedTokens: Int?
    public let reasoningTokens: Int?
}
```

### ProviderFinishReason

```swift
public enum ProviderFinishReason: Sendable, Equatable {
    case stop
    case length
    case toolCalls
    case contentFilter
    case error
    case unknown

    public init(providerReason: String?)
}
```

---

## ProviderStreamEvent

Events from streaming provider requests.

```swift
public enum ProviderStreamEvent: Sendable {
    /// Stream started
    case start(id: String, model: String)

    /// Text content delta
    case textDelta(String)

    /// Tool call started
    case toolCallStart(id: String, name: String)

    /// Tool call arguments delta
    case toolCallDelta(id: String, argumentsDelta: String)

    /// Tool call finished
    case toolCallFinish(id: String, name: String, arguments: String)

    /// Usage statistics
    case usage(ProviderUsage)

    /// Stream finished
    case finish(reason: ProviderFinishReason, usage: ProviderUsage?)
}
```

---

## ProviderError

Errors from provider operations.

```swift
public enum ProviderError: Error, Sendable {
    /// Authentication failed
    case authenticationFailed(String)

    /// Rate limit exceeded
    case rateLimited(retryAfter: TimeInterval?)

    /// Invalid request
    case invalidRequest(String)

    /// Model not found
    case modelNotFound(String)

    /// Server error
    case serverError(statusCode: Int, message: String)

    /// Network error
    case networkError(String)

    /// Request timeout
    case timeout(TimeInterval)

    /// Response parsing error
    case parseError(String)

    /// Unknown error
    case unknown(String)
}
```

### Error Handling

```swift
do {
    let response = try await client.execute(request: request)
} catch ProviderError.rateLimited(let retryAfter) {
    if let delay = retryAfter {
        try await Task.sleep(for: .seconds(delay))
        // Retry
    }
} catch ProviderError.authenticationFailed(let message) {
    print("Check API key: \(message)")
} catch ProviderError.serverError(let code, let message) {
    print("Server error \(code): \(message)")
}
```

---

## Converting Between Layers

### AITextRequest to ProviderRequest

```swift
let aiRequest = AITextRequest(
    messages: [.user("Hello")],
    model: "claude-3-opus"
)

let providerRequest = try aiRequest.toProviderRequest(
    modelId: "anthropic/claude-3-opus"
)
```

### ProviderResponse to AITextResult

```swift
let providerResponse = try await client.execute(request: providerRequest)

let aiResult = AITextResult(
    text: providerResponse.content,
    usage: AIUsage(
        promptTokens: providerResponse.usage?.promptTokens ?? 0,
        completionTokens: providerResponse.usage?.completionTokens ?? 0
    ),
    finishReason: AIFinishReason(from: providerResponse.finishReason),
    toolCalls: providerResponse.toolCalls.map { ... }
)
```

---

## Provider Comparison

| Feature | OpenRouter | LiteLLM |
|---------|------------|---------|
| Models | 200+ | 100+ |
| Streaming | Yes | Yes |
| Tool Calling | Yes | Yes |
| Vision | Yes (model-dependent) | Yes |
| Pricing | Pay-per-use | Self-hosted |

## See Also

- [Core Protocols](core-protocols.md) - ProviderClient protocol
- [Reliability](reliability.md) - Failover and circuit breakers
- [Errors](errors.md) - Error handling
