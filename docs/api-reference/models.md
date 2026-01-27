# Models

> Request and response types for AISDK operations

## AIMessage

Universal message type for LLM conversations.

```swift
public struct AIMessage: Sendable, Equatable, Codable {
    /// Message role
    public let role: Role

    /// Message content
    public let content: Content

    /// Optional sender name
    public let name: String?

    /// Tool calls made by assistant
    public let toolCalls: [ToolCall]?

    /// ID of tool call this message responds to
    public let toolCallId: String?
}
```

### Role

```swift
public enum Role: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool
}
```

### Content

```swift
public enum Content: Sendable, Equatable {
    case text(String)
    case parts([ContentPart])
}
```

### ContentPart

```swift
public enum ContentPart: Sendable, Equatable {
    case text(String)
    case image(Data, mimeType: String)
    case imageURL(String)
    case audio(Data, mimeType: String)
    case file(Data, mimeType: String, name: String)
}
```

### ToolCall

```swift
public struct ToolCall: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let arguments: String  // JSON string
}
```

### Convenience Builders

```swift
extension AIMessage {
    /// Create a user message
    public static func user(_ text: String) -> AIMessage

    /// Create a user message with content parts
    public static func user(parts: [ContentPart]) -> AIMessage

    /// Create an assistant message
    public static func assistant(_ text: String) -> AIMessage

    /// Create a system message
    public static func system(_ text: String) -> AIMessage

    /// Create a tool result message
    public static func tool(callId: String, content: String) -> AIMessage
}
```

### Usage

```swift
// Simple text message
let userMsg = AIMessage.user("Hello!")

// Multimodal message
let imageMsg = AIMessage.user(parts: [
    .text("What's in this image?"),
    .imageURL("https://example.com/photo.jpg")
])

// System prompt
let systemMsg = AIMessage.system("You are a helpful assistant.")

// Tool result
let toolResult = AIMessage.tool(
    callId: "call_123",
    content: "{\"temperature\": 72, \"condition\": \"sunny\"}"
)
```

---

## AITextRequest

Request for text generation.

```swift
public struct AITextRequest: @unchecked Sendable {
    /// Conversation messages
    public let messages: [AIMessage]

    /// Model identifier (optional, uses default)
    public let model: String?

    /// Maximum tokens to generate
    public let maxTokens: Int?

    /// Sampling temperature (0.0-2.0)
    public let temperature: Double?

    /// Top-p sampling parameter
    public let topP: Double?

    /// Stop sequences
    public let stop: [String]?

    /// Tools available for the model
    public let tools: [ToolSchema]?

    /// Tool choice behavior
    public let toolChoice: ToolChoice?

    /// Response format specification
    public let responseFormat: ResponseFormat?

    /// Allowed providers for PHI protection
    public let allowedProviders: Set<String>?

    /// Allowed providers for PHI protection
    public let allowedProviders: Set<String>?

    /// Data sensitivity level
    public let sensitivity: DataSensitivity

    /// Stream buffer policy
    public let bufferPolicy: StreamBufferPolicy?

    /// Request metadata for tracing
    public let metadata: [String: String]?
}
```

### DataSensitivity

Controls PHI protection behavior:

```swift
public enum DataSensitivity: String, Sendable, Codable {
    /// Standard data, any provider allowed
    case standard

    /// Sensitive data, prefer trusted providers
    case sensitive

    /// PHI data, only HIPAA-compliant providers
    case phi
}
```

### StreamBufferPolicy

Controls streaming buffer behavior:

```swift
public enum StreamBufferPolicy: Sendable, Equatable {
    /// Unbounded buffer - no limit on events (use with caution for memory)
    case unbounded

    /// Bounded buffer that drops oldest events when full
    case dropOldest(capacity: Int)

    /// Bounded buffer that drops newest events when full
    case dropNewest(capacity: Int)
}
```

### ToolChoice

```swift
public enum ToolChoice: Codable, Equatable {
    case none
    case auto
    case required
    case function(FunctionChoice)
}
```

### Initialization

```swift
public init(
    messages: [AIMessage],
    model: String? = nil,
    maxTokens: Int? = nil,
    temperature: Double? = nil,
    topP: Double? = nil,
    stop: [String]? = nil,
    tools: [ToolSchema]? = nil,
    toolChoice: ToolChoice? = nil,
    responseFormat: ResponseFormat? = nil,
    allowedProviders: Set<String>? = nil,
    sensitivity: DataSensitivity = .standard,
    bufferPolicy: StreamBufferPolicy? = nil,
    metadata: [String: String]? = nil
)
```

---

## AITextResult

Result from non-streaming text generation.

```swift
public struct AITextResult: Sendable, Equatable {
    /// Generated text
    public let text: String

    /// Tool calls made by the model
    public let toolCalls: [AIToolCallResult]

    /// Token usage statistics
    public let usage: AIUsage

    /// Reason generation stopped
    public let finishReason: AIFinishReason

    /// Request ID for tracing
    public let requestId: String?

    /// Model that generated the response
    public let model: String?

    /// Provider that handled the request
    public let provider: String?
}
```

### AIUsage

```swift
public struct AIUsage: Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let cachedTokens: Int?
    public let reasoningTokens: Int?

    public var totalTokens: Int {
        promptTokens + completionTokens
    }

    public static let zero = AIUsage(promptTokens: 0, completionTokens: 0)
}
```

### AIFinishReason

```swift
public enum AIFinishReason: String, Sendable, Equatable {
    case stop           // Natural completion
    case length         // Token limit reached
    case toolCalls      // Tool calls required
    case contentFilter  // Content filtered
    case error          // Error occurred
    case unknown        // Unknown reason
}
```

---

## AIStreamEvent

Events emitted during streaming operations.

```swift
public enum AIStreamEvent: Sendable {
    // Text generation
    case textDelta(String)
    case textCompletion(String)

    // Reasoning (chain-of-thought)
    case reasoningStart
    case reasoningDelta(String)
    case reasoningFinish(String)

    // Tool calls
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCall(id: String, name: String, arguments: String)  // Complete tool call
    case toolCallFinish(id: String, name: String, arguments: String)
    case toolResult(id: String, result: String, metadata: ToolMetadata?)

    // Object generation
    case objectDelta(Data)

    // Citations/sources
    case source(AISource)

    // File outputs
    case file(AIFileEvent)

    // Usage statistics
    case usage(AIUsage)

    // Stream lifecycle
    case start(metadata: AIStreamMetadata?)
    case stepStart(stepIndex: Int)
    case stepFinish(stepIndex: Int, result: AIStepResult)
    case heartbeat(timestamp: Date)
    case finish(finishReason: AIFinishReason, usage: AIUsage)
    case error(Error)
}
```

### AIToolCallResult

```swift
public struct AIToolCallResult: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let arguments: String
}
```

### AISource

```swift
public struct AISource: Sendable, Codable {
    public let id: String
    public let title: String?
    public let url: String?
    public let snippet: String?
}
```

### AIFileEvent

```swift
public struct AIFileEvent: Sendable {
    public let id: String
    public let mimeType: String
    public let data: Data
}
```

---

## AIObjectRequest

Request for structured object generation.

```swift
public struct AIObjectRequest<T: Codable & Sendable>: Sendable {
    /// Conversation messages
    public let messages: [AIMessage]

    /// JSON Schema for the output type
    public let schema: [String: Any]

    /// Schema name for the model
    public let schemaName: String

    /// Model identifier
    public let model: String?

    /// Sampling temperature
    public let temperature: Double?
}
```

## AIObjectResult

Result from structured object generation.

```swift
public struct AIObjectResult<T: Codable & Sendable>: Sendable {
    /// The parsed object
    public let object: T

    /// Token usage
    public let usage: AIUsage

    /// Finish reason
    public let finishReason: AIFinishReason
}
```

---

## Type Relationships

```
AITextRequest
    │
    ├── AIMessage[]
    │       ├── Role
    │       ├── Content
    │       │       └── ContentPart[]
    │       └── ToolCall[]
    │
    └── produces ──► AITextResult
                        ├── AIUsage
                        ├── AIFinishReason
                        └── AIToolCallResult[]

AITextRequest (streaming)
    │
    └── produces ──► AsyncThrowingStream<AIStreamEvent>
                        ├── textDelta
                        ├── toolCallStart/Delta/Finish
                        ├── usage
                        └── finish
```

## See Also

- [Core Protocols](core-protocols.md) - Protocol definitions
- [Agents](agents.md) - Agent execution flow
- [Tools](tools.md) - Tool call handling
