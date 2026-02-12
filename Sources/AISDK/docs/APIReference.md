# AISDK API Reference

Complete API documentation for the AISDK Swift package.

## Table of Contents

- [Core Components](#core-components)
  - [AIAgentActor](#aiagentactor)
  - [AITool](#aitool)
  - [RenderableTool](#renderabletool)
  - [AILanguageModel Protocol](#ailanguagemodel-protocol)
- [Models](#models)
  - [AIMessage](#aimessage)
  - [AITextRequest](#aitextrequest)
  - [AITextResult](#aitextresult)
  - [AIStreamEvent](#aistreamevent)
- [Chat Module](#chat-module)
  - [AIChatManager](#aichatmanager)
  - [ChatSession](#chatsession)
  - [ChatMessage](#chatmessage)
  - [Storage Protocol](#storage-protocol)
- [Voice Module](#voice-module)
  - [AIVoiceMode](#aivoicemode)
  - [SpeechRecognizer](#speechrecognizer)
  - [SpeechSynthesizer](#speechsynthesizer)
- [Vision Module](#vision-module)
  - [VisionCameraView](#visioncameraview)
  - [ConnectionDetails](#connectiondetails)
- [Research Module](#research-module)
  - [ResearcherAgent](#researcheragent)
  - [ResearchMetadata](#researchmetadata)
- [Error Types](#error-types)
- [Type Aliases](#type-aliases)

## Core Components

### AIAgentActor

The central orchestrator for AI interactions, implemented as a Swift actor for thread safety.

```swift
public actor AIAgentActor {
    /// The language model provider
    public let model: any AILanguageModel

    /// Available tools for the agent
    public let tools: [AITool.Type]

    /// System instructions for agent behavior
    public let instructions: String?

    /// Observable state for SwiftUI binding
    public let observableState: ObservableAgentState
}
```

#### Initialization

```swift
public init(
    model: any AILanguageModel,
    tools: [AITool.Type] = [],
    instructions: String? = nil
)
```

**Parameters:**
- `model`: An `AILanguageModel` provider (e.g., `OpenRouterClient`)
- `tools`: Array of `AITool` types available to the agent
- `instructions`: System instructions for agent behavior

> Note: `AIAgentActor.init` does **not** throw. No `try` is needed.

#### Methods

##### execute(messages:)

Send messages and receive a complete response.

```swift
public func execute(messages: [AIMessage]) async throws -> AIAgentResult
```

**Parameters:**
- `messages`: Array of `AIMessage` values representing the conversation

**Returns:** An `AIAgentResult` containing the response text, tool results, and usage data

**Throws:**
- `AgentError.toolExecutionFailed`: If a tool execution fails
- Network-related errors from the provider

##### streamExecute(messages:)

Send messages and receive streaming events.

```swift
public nonisolated func streamExecute(
    messages: [AIMessage]
) -> AsyncThrowingStream<AIStreamEvent, Error>
```

**Parameters:**
- `messages`: Array of `AIMessage` values representing the conversation

**Returns:** An `AsyncThrowingStream` of `AIStreamEvent` values

### AITool

Instance-based protocol for defining executable tools.

```swift
public protocol AITool: Sendable {
    var name: String { get }
    var description: String { get }
    var returnToolResponse: Bool { get }

    init()
    static func jsonSchema() -> ToolSchema
    static func validate(arguments: [String: Any]) throws
    mutating func setParameters(from arguments: [String: Any]) throws
    mutating func validateAndSetParameters(_ argumentsData: Data) throws -> Self
    func execute() async throws -> AIToolResult
}
```

#### AIParameter Property Wrapper

```swift
@AIParameter(description: "City name")
var city: String = ""
```

**Example:**
```swift
struct WeatherTool: AITool {
    let name = "get_weather"
    let description = "Get current weather"
    
    @AIParameter(
        description: "City name",
        validation: ["minLength": 1, "maxLength": 100]
    )
    var city: String = ""
    
    @AIParameter(
        description: "Temperature unit",
        validation: ["enum": ["celsius", "fahrenheit"]]
    )
    var unit: String = "celsius"
    
    func execute() async throws -> AIToolResult {
        let weather = try await fetchWeather(city: city, unit: unit)
        return AIToolResult(content: "Temperature in \(city): \(weather.temp)°\(unit)")
    }
}
```

### RenderableTool

Protocol for tools that can render UI.

```swift
public protocol RenderableTool: AITool {
    /// Renders a SwiftUI view given the stored metadata
    func render(from data: Data) -> AnyView
}
```

**Example:**
```swift
struct ChartTool: RenderableTool {
    let name = "display_chart"
    let description = "Display data in a chart"
    
    @AIParameter(description: "Chart data as JSON")
    var data: String = ""
    
    func execute() async throws -> AIToolResult {
        let chartData = try JSONDecoder().decode(ChartData.self, from: data.data(using: .utf8)!)
        let jsonData = try JSONEncoder().encode(chartData)
        let metadata = RenderMetadata(toolName: name, jsonData: jsonData)
        
        return AIToolResult(content: "Chart created with \(chartData.points.count) data points", metadata: metadata)
    }
    
    func render(from data: Data) -> AnyView {
        guard let chartData = try? JSONDecoder().decode(ChartData.self, from: data) else {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            Chart(chartData.points) { point in
                BarMark(
                    x: .value("Label", point.label),
                    y: .value("Value", point.value)
                )
            }
            .frame(height: 200)
            .padding()
        )
    }
}
```

### AILanguageModel Protocol

Protocol for language model providers.

```swift
public protocol AILanguageModel: Sendable {
    var provider: String { get }
    var modelId: String { get }
    var capabilities: LLMCapabilities { get }

    func generateText(request: AITextRequest) async throws -> AITextResult
    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
    func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T>
    func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error>
}
```

## Models

### AIMessage

Represents a message in the conversation.

```swift
public struct AIMessage: Codable, Sendable {
    public let role: Role
    public let content: Content

    public enum Role: String, Codable, Sendable {
        case system, user, assistant, tool
    }

    public enum Content: Codable, Sendable {
        case text(String)
        case parts([AIContentPart])
    }
}
```

#### Factory Methods

```swift
// Text messages
AIMessage.user("Hello!")
AIMessage.system("You are helpful")
AIMessage.assistant("Hi there!")
AIMessage.tool("72F", toolCallId: "call_123")

// Multimodal messages
AIMessage.user(content: .parts([
    .text("What's in this image?"),
    .image(imageData, mimeType: "image/jpeg")
]))
```

### AIContentPart

Content parts for multimodal messages.

```swift
public enum AIContentPart: Codable, Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case imageURL(String)
    case audio(Data, format: AudioFormat)
    case file(Data, mimeType: String)
    case json(Data)
}
```

### AITextRequest

Request structure for text generation.

```swift
public struct AITextRequest: Sendable {
    public let messages: [AIMessage]
    public let tools: [ToolSchema]?
    public let toolChoice: ToolChoice?
    public let temperature: Double?
    public let maxTokens: Int?
    public let topP: Double?
    public let stop: [String]?
    public let responseFormat: ResponseFormat?
}
```

### ToolChoice

Tool selection preference.

```swift
public enum ToolChoice: Codable {
    case none
    case auto
    case required
    case function(FunctionChoice)

    public struct FunctionChoice: Codable {
        public let name: String
    }
}
```

### AITextResult

Result from text generation.

```swift
public struct AITextResult: Sendable {
    public let text: String
    public let toolCalls: [AIToolCall]?
    public let finishReason: FinishReason
    public let usage: TokenUsage?
}
```

### AIStreamEvent

Typed events emitted during streaming.

```swift
public enum AIStreamEvent: Sendable {
    case start
    case textDelta(String)
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCall(id: String, name: String, arguments: String)
    case toolResult(id: String, result: AIToolResult)
    case usage(TokenUsage)
    case finish(reason: FinishReason, usage: TokenUsage?)
    case error(Error)
}
```

### ToolMetadata

Base protocol for tool metadata.

```swift
public protocol ToolMetadata: Codable {}

/// Metadata for UI rendering
public struct RenderMetadata: ToolMetadata {
    public let toolName: String
    public let jsonData: Data
}
```

## Chat Module

### AIChatManager

Manages chat sessions and conversations.

```swift
@Observable
public class AIChatManager {
    /// Current chat sessions
    public var chatSessions: [ChatSession] = []
    
    /// Active session
    public var currentSession: ChatSession?
    
    /// Loading states
    public var isLoading: Bool = false
    public var isStreaming: Bool = false
    
    /// Agent instance
    public let agent: AIAgentActor
    
    /// Storage backend
    public let storage: ChatStorageProtocol?
    
    /// Suggested questions
    public var suggestedQuestions: [SuggestedQuestion] = []
}
```

#### Initialization

```swift
public init(
    agent: AIAgentActor,
    storage: ChatStorageProtocol? = nil,
    triggerEvent: TriggerEvent? = nil,
    dynamicMessage: DynamicMessage? = nil
)
```

#### Methods

##### loadChatSessions()

Load all chat sessions from storage.

```swift
public func loadChatSessions() async throws
```

##### createNewSession(title:)

Create a new chat session.

```swift
public func createNewSession(
    title: String = "New Chat",
    triggerEvent: TriggerEvent? = nil,
    dynamicMessage: DynamicMessage? = nil
) async
```

##### sendMessage(_:attachments:requiredTool:)

Send a message in the current session.

```swift
public func sendMessage(
    _ parts: [UserContent.Part],
    attachments: [Attachment] = [],
    requiredTool: String? = nil
)
```

##### deleteSession(_:)

Delete a chat session.

```swift
public func deleteSession(_ session: ChatSession) async throws
```

##### generateSuggestedQuestions()

Generate suggested follow-up questions.

```swift
public func generateSuggestedQuestions() async
```

### ChatSession

Represents a chat conversation session.

```swift
public struct ChatSession: Identifiable, Codable {
    public var id: String?
    public var title: String
    public var messages: [ChatMessage]
    public let createdAt: Date
    public var lastModified: Date
    public var metadata: [String: Any]?
}
```

### ChatMessage

A message within a chat session.

```swift
public struct ChatMessage: Identifiable, Codable {
    public let id: String
    public let message: Message
    public var attachments: [Attachment]
    public let timestamp: Date
    public var metadata: [AnyToolMetadata]?
    public var isPending: Bool
}
```

### Attachment

File or media attachment.

```swift
public struct Attachment: Identifiable, Codable {
    public let id: String
    public let type: AttachmentType
    public let data: Data?
    public let url: URL?
    public let filename: String?
    public let mimeType: String?
    
    public enum AttachmentType: String, Codable {
        case image
        case document
        case audio
        case video
    }
}
```

### Storage Protocol

Protocol for implementing storage backends.

```swift
public protocol ChatStorageProtocol {
    /// Save a chat session
    func save(session: ChatSession) async throws
    
    /// Load a specific session
    func load(id: String) async throws -> ChatSession?
    
    /// Delete a session
    func delete(id: String) async throws
    
    /// List all sessions
    func list() async throws -> [ChatSession]
    
    /// Update session title
    func updateTitle(sessionId: String, title: String) async throws
    
    /// Append a message to session
    func appendMessage(sessionId: String, message: ChatMessage) async throws
    
    /// Update a specific message
    func updateMessage(sessionId: String, messageId: String, message: ChatMessage) async throws
    
    /// Update session metadata
    func updateMetadata(sessionId: String, metadata: [String: Any]) async throws
}
```

### MemoryStorage

In-memory storage implementation.

```swift
public class MemoryStorage: ChatStorageProtocol {
    private var sessions: [String: ChatSession] = [:]
    
    public init() {}
    
    // Implementation of all protocol methods
}
```

## Voice Module

### AIVoiceMode

Manages voice interactions using native iOS APIs.

```swift
@Observable
public class AIVoiceMode {
    /// Recording state
    public var isRecording: Bool = false
    
    /// Processing state
    public var isProcessing: Bool = false
    
    /// Current transcript
    public var transcript: String = ""
    
    /// Audio level (0.0 - 1.0)
    public var audioLevel: Float = 0.0
    
    /// Voice settings
    public var settings: VoiceSettings
}
```

#### Methods

##### startRecording()

Start recording audio.

```swift
public func startRecording() async throws -> AsyncThrowingStream<AudioData, Error>
```

##### stopRecording()

Stop recording.

```swift
public func stopRecording() async throws
```

##### transcribe(_:)

Transcribe audio to text using Speech framework.

```swift
public func transcribe(_ audioData: AudioData) async throws -> String
```

##### speak(_:)

Synthesize text to speech using AVSpeechSynthesizer.

```swift
public func speak(_ text: String) async throws
```

##### startConversation(with:)

Start a full conversation loop with an agent.

```swift
public func startConversation(with agent: AIAgentActor) async throws
```

### SpeechRecognizer

Wrapper for Speech framework.

```swift
public class SpeechRecognizer {
    /// Available locales
    public static var supportedLocales: Set<Locale> { get }
    
    /// Request authorization
    public static func requestAuthorization() async throws -> Bool
    
    /// Create recognition request
    public func createRecognitionRequest(
        for audioBuffer: AVAudioPCMBuffer
    ) -> SFSpeechAudioBufferRecognitionRequest
}
```

### SpeechSynthesizer

Wrapper for AVSpeechSynthesizer.

```swift
public class SpeechSynthesizer {
    /// Available voices
    public static var availableVoices: [AVSpeechSynthesisVoice] { get }
    
    /// Speak text
    public func speak(
        _ text: String,
        voice: AVSpeechSynthesisVoice? = nil,
        rate: Float = 0.5,
        pitch: Float = 1.0
    ) async throws
}
```

### VoiceSettings

Voice configuration.

```swift
public struct VoiceSettings: Codable {
    public var locale: Locale
    public var voice: String?
    public var speechRate: Float
    public var pitchMultiplier: Float
    public var preDelay: TimeInterval
    public var postDelay: TimeInterval
}
```

## Vision Module

### VisionCameraView

LiveKit-powered camera view.

```swift
public struct VisionCameraView: View {
    @StateObject private var room: Room
    @StateObject private var participant: LocalParticipant
    
    public init(connectionDetails: ConnectionDetails)
    
    public var body: some View
}
```

### ConnectionDetails

LiveKit connection configuration.

```swift
public struct ConnectionDetails {
    public let serverUrl: String
    public let token: String
    public let roomName: String
}
```

### AgentView

Vision agent interaction view.

```swift
public struct AgentView: View {
    let agent: AIAgentActor
    @ObservedObject var chatContext: ChatContext

    public var body: some View
}
```

## Research Module

### ResearcherAgent

Specialized agent for research tasks.

```swift
public actor ResearcherAgent {
    /// The underlying agent
    private let agent: AIAgentActor

    /// Research state
    public let observableState: ObservableResearchState

    /// Current research context
    public var researchContext: ResearchContext?

    /// Initialize researcher
    public init(
        model: any AILanguageModel,
        researchTools: [AITool.Type]? = nil
    )
}
```

#### Methods

##### research(topic:sources:depth:)

Conduct research on a topic.

```swift
public func research(
    topic: String,
    sources: [String] = ["academic", "web", "news"],
    depth: ResearchDepth = .standard
) async throws -> ResearchResult
```

### ResearchMetadata

Metadata for research results.

```swift
public struct ResearchMetadata: ToolMetadata {
    public let sources: [Source]
    public let evidenceLevel: String
    public let confidence: Double
    public let citations: [Citation]
}
```

### ResearchResult

Complete research output.

```swift
public struct ResearchResult {
    public let topic: String
    public let summary: String
    public let keyFindings: [Finding]
    public let evidence: [Evidence]
    public let sources: [Source]
    public let metadata: ResearchMetadata
}
```

## Error Types

### AgentError

```swift
public enum AgentError: LocalizedError {
    case invalidModel
    case missingAPIKey
    case toolExecutionFailed(String)
    case invalidToolResponse
    case conversationLimitExceeded
    case operationCancelled
    case invalidParameterType(String)
    
    public var errorDescription: String? { get }
}
```

### AISDKError

```swift
public enum AISDKError: LocalizedError {
    case networkError(Error)
    case decodingError(Error)
    case invalidRequest(String)
    case rateLimitExceeded
    case unauthorized
    case serverError(Int, String?)
    case streamingError(String)
    
    public var errorDescription: String? { get }
}
```

### ToolError

```swift
public enum ToolError: LocalizedError {
    case invalidParameters(String)
    case executionFailed(String)
    case missingRequiredParameter(String)
    case validationFailed(String)
    
    public var errorDescription: String? { get }
}
```

## Type Aliases

```swift
/// Tool execution result
public typealias ToolResult = Result<AIToolResult, Error>

/// Suggested question
public struct SuggestedQuestion: Identifiable {
    public let id: String
    public let text: String
    public let category: String?
}

/// Dynamic message for session initialization
public struct DynamicMessage {
    public let message: String
    public let context: [String: Any]?
}

/// Trigger event for observer mode
public struct TriggerEvent {
    public let type: String
    public let context: String
    public let question: String
}
```

## Constants

```swift
public enum AISDKConstants {
    /// Default temperature for completions
    public static let defaultTemperature: Double = 0.7
    
    /// Maximum tokens per request
    public static let maxTokens: Int = 4096
    
    /// Default timeout for requests
    public static let requestTimeout: TimeInterval = 30.0
    
    /// Maximum conversation length
    public static let maxConversationLength: Int = 100
    
    /// Voice recording sample rate
    public static let audioSampleRate: Double = 44100.0
    
    /// Default speech rate
    public static let defaultSpeechRate: Float = 0.5
}
```

## Protocols

### AgentCallbacks

```swift
public protocol AgentCallbacks: Sendable {
    /// Called when a message is received
    func onMessageReceived(message: AIMessage) async -> CallbackResult

    /// Called before sending to LLM
    func onBeforeLLMRequest(messages: [AIMessage]) async -> CallbackResult

    /// Called on streaming event
    func onStreamEvent(event: AIStreamEvent) async -> CallbackResult

    /// Called on tool execution
    func onToolExecution(tool: String, args: Any) async -> CallbackResult
}
```

### CallbackResult

```swift
public enum CallbackResult {
    case `continue`
    case cancel
    case replace(AIMessage)
}
```

## UI Components (AISDKChat)

### MessageBubble

Renders chat messages with tool UI support.

```swift
public struct MessageBubble: View {
    let message: ChatMessage
    let showTimestamp: Bool
    
    public var body: some View
}
```

### AIConversationView

Complete conversation interface.

```swift
public struct AIConversationView: View {
    @Bindable var manager: AIChatManager
    
    public var body: some View
}
```

### SuggestedQuestionsView

Displays suggested follow-up questions.

```swift
public struct SuggestedQuestionsView: View {
    let questions: [SuggestedQuestion]
    let onSelect: (String) -> Void
    
    public var body: some View
} 
