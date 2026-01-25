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
public struct AITextRequest: Sendable {
    /// Conversation messages
    public let messages: [AIMessage]

    /// Model identifier (optional, uses default)
    public let model: String?

    /// Sampling temperature (0.0-2.0)
    public let temperature: Double?

    /// Maximum tokens to generate
    public let maxTokens: Int?

    /// Top-p sampling parameter
    public let topP: Double?

    /// Stop sequences
    public let stop: [String]?

    /// Tools available for the model
    public let tools: [AnyAITool]?

    /// Tool choice behavior
    public let toolChoice: ToolChoice?

    /// Data sensitivity level
    public let sensitivity: DataSensitivity

    /// Allowed providers for PHI protection
    public let allowedProviders: Set<String>?

    /// Stream buffer policy
    public let bufferPolicy: StreamBufferPolicy
}
```

### DataSensitivity

Controls PHI protection behavior:

```swift
public enum DataSensitivity: Sendable {
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
public enum StreamBufferPolicy: Sendable {
    /// Buffer until complete
    case complete

    /// Unbounded buffer
    case unbounded

    /// Buffer up to N elements
    case bufferingOldest(Int)

    /// Drop oldest when full
    case bufferingNewest(Int)
}
```

### ToolChoice

```swift
public enum ToolChoice: Sendable {
    case auto      // Model decides
    case none      // Disable tools
    case required  // Must use a tool
    case tool(String)  // Use specific tool
}
```

### Initialization

```swift
public init(
    messages: [AIMessage],
    model: String? = nil,
    temperature: Double? = nil,
    maxTokens: Int? = nil,
    topP: Double? = nil,
    stop: [String]? = nil,
    tools: [AnyAITool]? = nil,
    toolChoice: ToolChoice? = nil,
    sensitivity: DataSensitivity = .standard,
    allowedProviders: Set<String>? = nil,
    bufferPolicy: StreamBufferPolicy = .unbounded
)
```

---

## AITextResult

Result from non-streaming text generation.

```swift
public struct AITextResult: Sendable {
    /// Generated text
    public let text: String

    /// Token usage statistics
    public let usage: AIUsage

    /// Reason generation stopped
    public let finishReason: AIFinishReason

    /// Tool calls made (if any)
    public let toolCalls: [AIToolCall]?

    /// Model that generated the response
    public let model: String?
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

    // Reasoning (chain-of-thought)
    case reasoningStart
    case reasoningDelta(String)
    case reasoningFinish

    // Tool calls
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCall(AIToolCall)  // Complete tool call
    case toolCallFinish(id: String, name: String, arguments: String)
    case toolResult(id: String, result: AIToolResultData)

    // Object generation
    case objectDelta(Data)

    // Citations/sources
    case source(AISource)

    // File outputs
    case file(AIFileEvent)

    // Usage statistics
    case usage(AIUsage)

    // Stream lifecycle
    case start(id: String, model: String)
    case stepStart(Int)
    case stepFinish(Int)
    case heartbeat
    case finish(finishReason: AIFinishReason, usage: AIUsage?)
    case error(Error)
}
```

### AIToolCall

```swift
public struct AIToolCall: Sendable, Equatable, Codable {
    public let id: String
    public let name: String
    public let arguments: String

    /// Parse arguments as a specific type
    public func parseArguments<T: Codable>() throws -> T
}
```

### AISource

```swift
public struct AISource: Sendable, Equatable {
    public let title: String?
    public let url: String?
    public let snippet: String?
}
```

### AIFileEvent

```swift
public struct AIFileEvent: Sendable, Equatable {
    public let name: String
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
                        └── AIToolCall[]

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
