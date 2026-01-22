# AISDK Architecture Documentation

> **Version:** 1.1.0 | **Last Updated:** January 2025 | **Swift:** 5.9+ | **Platforms:** iOS 17+, macOS 14+, watchOS 10+, tvOS 17+

---

## Quick Reference

| Component | Purpose | Key Types |
|-----------|---------|-----------|
| **Core AISDK** | Multi-provider LLM abstraction | `Agent`, `LLM`, `Tool`, `AIInputMessage` |
| **Providers** | API implementations | `OpenAIProvider`, `AnthropicProvider`, `GeminiProvider` |
| **Models** | 134+ supported models | `LLMModelProtocol`, `OpenAIModels`, `AnthropicModels`, `GeminiModels` |
| **Tools** | Function calling framework | `Tool`, `@Parameter`, `ToolMetadata` |
| **Messages** | Universal message format | `AIInputMessage`, `AIContentPart`, `ChatMessage` |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Provider System](#3-provider-system)
4. [Module Breakdown](#4-module-breakdown)
5. [Message System](#5-message-system)
6. [Tool Framework](#6-tool-framework)
7. [Agent System](#7-agent-system)
8. [Model Registry](#8-model-registry)
9. [API Surface Reference](#9-api-surface-reference)
10. [Gap Analysis](#10-gap-analysis)
11. [File Index](#11-file-index)

---

## 1. Executive Summary

AISDK is a production-grade, multi-provider AI SDK for Swift that abstracts multiple LLM providers behind unified protocols and APIs.

### Key Statistics

- **66 Swift files** in core module
- **134+ models** across 3 major providers
- **4 modules**: Core, Chat, Vision, Voice
- **31+ capability flags** for model classification

### Supported Providers

| Provider | Models | Key Features |
|----------|--------|--------------|
| **OpenAI** | 82 models | GPT-5, GPT-4o, o3/o4 reasoning, DALL-E, Whisper, Responses API |
| **Anthropic** | 10 models | Claude 4, Claude 3.7/3.5, extended thinking |
| **Google** | 42 models | Gemini 2.5/2.0, Imagen 4.0, Veo 2.0, Live API |

### Core Capabilities

- **Streaming**: Full SSE streaming with real-time chunks
- **Tools/Function Calling**: Type-safe tool framework with JSON Schema generation
- **Agents**: Orchestrated tool execution with state management
- **Multimodal**: Text, images, audio, video, files
- **Structured Output**: JSON schema validation with `generateObject<T>()`

---

## 2. Architecture Overview

### High-Level Architecture

```mermaid
graph TB
    subgraph "Application Layer"
        APP[Your Swift App]
    end

    subgraph "AISDK Feature Modules"
        CHAT[AISDKChat<br/>17 files]
        VOICE[AISDKVoice<br/>5 files]
        VISION[AISDKVision<br/>9 files]
    end

    subgraph "Core AISDK - 66 files"
        AGENT[Agent System<br/>Agent.swift]
        TOOLS[Tool Framework<br/>Tool.swift]
        MSG[Message System<br/>AIMessage.swift]
        MODELS[Model Registry<br/>LLMModelProtocol.swift]
    end

    subgraph "Provider Layer"
        OPENAI[OpenAIProvider<br/>82 models]
        ANTHROPIC[AnthropicProvider<br/>10 models]
        GEMINI[GeminiProvider<br/>42 models]
    end

    subgraph "External APIs"
        OAPI[api.openai.com]
        AAPI[api.anthropic.com]
        GAPI[generativelanguage.googleapis.com]
    end

    APP --> CHAT & VOICE & VISION
    CHAT & VOICE & VISION --> AGENT
    AGENT --> TOOLS
    AGENT --> MSG
    AGENT --> MODELS
    MSG --> OPENAI & ANTHROPIC & GEMINI
    OPENAI --> OAPI
    ANTHROPIC --> AAPI
    GEMINI --> GAPI
```

### Message Flow

```mermaid
sequenceDiagram
    participant App
    participant Agent
    participant LLM as LLM Provider
    participant Tool
    participant API as External API

    App->>Agent: send("What's the weather?")
    Agent->>Agent: setState(.thinking)
    Agent->>LLM: sendChatCompletion(request)
    LLM->>API: POST /v1/chat/completions
    API-->>LLM: Response with tool_calls
    LLM-->>Agent: ChatCompletionResponse

    Agent->>Agent: setState(.executingTool)
    Agent->>Tool: execute()
    Tool-->>Agent: (content, metadata)

    Agent->>LLM: sendChatCompletion(with tool result)
    LLM->>API: POST /v1/chat/completions
    API-->>LLM: Final response
    LLM-->>Agent: ChatCompletionResponse

    Agent->>Agent: setState(.idle)
    Agent-->>App: ChatMessage
```

### Agent State Machine

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> thinking: send() / sendStream()
    thinking --> responding: Received content
    thinking --> executingTool: Tool call detected
    executingTool --> thinking: Tool executed, get final response
    executingTool --> idle: returnToolResponse = true
    responding --> idle: Stream complete
    thinking --> error: Error occurred
    executingTool --> error: Tool failed
    error --> idle: Reset
```

---

## 3. Provider System

### 3.1 OpenAIProvider

**File:** `Sources/AISDK/LLMs/OpenAI/OpenAIProvider.swift`

The primary provider with the most comprehensive feature set.

```swift
// Model-aware initialization (recommended)
let openai = OpenAIProvider(
    model: OpenAIModels.gpt4o,
    apiKey: "sk-..."  // Falls back to OPENAI_API_KEY env var
)

// Legacy initialization
let openai = OpenAIProvider(apiKey: "sk-...")
```

**Supported Operations:**

| Method | Description |
|--------|-------------|
| `sendChatCompletion(request:)` | Non-streaming chat completion |
| `sendChatCompletionStream(request:)` | SSE streaming completion |
| `generateObject<T>(request:)` | Structured output with JSON Schema |
| `createResponse(request:)` | Responses API (non-streaming) |
| `createResponseStream(request:)` | Responses API (streaming) |
| `createResponseWithWebSearch(...)` | Web search tool |
| `createResponseWithCodeInterpreter(...)` | Code interpreter tool |

**Example: Streaming Chat**

```swift
let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [Message.user(content: .text("Hello!"))],
    stream: true
)

for try await chunk in openai.sendChatCompletionStream(request: request) {
    if let content = chunk.choices.first?.delta.content {
        print(content, terminator: "")
    }
}
```

### 3.2 AnthropicProvider

**File:** `Sources/AISDK/LLMs/Anthropic/AnthropicProvider.swift`

Uses Anthropic's OpenAI compatibility layer with automatic parameter normalization.

```swift
let claude = AnthropicProvider(
    apiKey: "sk-ant-...",
    baseUrl: "https://api.anthropic.com/v1"
)
```

**Compatibility Notes:**
- `n` must be 1 (automatically enforced)
- `temperature` capped at 1.0
- Ignored parameters: `logprobs`, `presence_penalty`, `frequency_penalty`, `seed`

**Example: Extended Thinking**

```swift
let request = claude.withExtendedThinking(
    request: baseRequest,
    budgetTokens: 2000
)
let response = try await claude.sendChatCompletion(request: request)
```

### 3.3 GeminiProvider

**File:** `Sources/AISDK/LLMs/Gemini/GeminiProvider.swift`

URLSession-based provider with retry logic and file upload support.

```swift
let gemini = GeminiProvider(
    model: GeminiModels.gemini25Flash,
    apiKey: "...",  // Falls back to GOOGLE_API_KEY or GEMINI_API_KEY
    maxRetries: 3,
    retryDelay: 1.0
)
```

**Unique Features:**

| Method | Description |
|--------|-------------|
| `generateContentRequest(...)` | Standard generation |
| `generateStreamingContentRequest(...)` | Streaming generation |
| `makeImagenRequest(...)` | Image generation with Imagen |
| `uploadFile(fileData:mimeType:)` | File upload for context |
| `deleteFile(fileURL:)` | Delete uploaded files |
| `getStatus(fileURL:)` | Check file processing status |

---

## 4. Module Breakdown

### Module Dependencies

```mermaid
graph LR
    subgraph "Swift Package"
        AISDK[AISDK<br/>Core]
        CHAT[AISDKChat]
        VOICE[AISDKVoice]
        VISION[AISDKVision]
    end

    subgraph "External Dependencies"
        AF[Alamofire]
        SJ[SwiftyJSON]
        MD[MarkdownUI]
        CH[Charts]
        LK[LiveKit]
    end

    AISDK --> AF
    AISDK --> SJ
    CHAT --> AISDK
    CHAT --> MD
    CHAT --> CH
    VOICE --> AISDK
    VISION --> AISDK
    VISION --> LK
```

### 4.1 Core AISDK (66 files)

The foundation layer providing LLM abstraction.

| Directory | Files | Purpose |
|-----------|-------|---------|
| `Agents/` | 9 | Agent orchestration, state management, callbacks |
| `LLMs/` | 52 | Provider implementations, API models, protocols |
| `Tools/` | 2 | Tool framework and registry |
| `Models/` | 3 | ChatMessage, AIMessage, Attachment |
| `Errors/` | 1 | Error types (AISDKError, LLMError, AgentError) |
| `Utilities/` | 3 | ConfigManager, JSON utilities |
| `Speech/` | 1 | SpeechRecognizer |

### 4.2 AISDKChat (17 files)

Text conversation management with SwiftUI components.

**Key Types:**
- `AIChatManager` - Session and conversation state
- `ChatSession` - Conversation container with Firestore sync
- `ChatMessage` - Message with metadata, attachments, feedback

**Features:**
- Session lifecycle management
- Real-time streaming UI updates
- Health profile integration
- Suggested questions generation
- Image/file attachments with Firebase upload

### 4.3 AISDKVoice (5 files)

Speech recognition and text-to-speech integration.

**Key Types:**
- `AIVoiceMode` - Core engine for voice conversations
- `VoiceActivityDetector` - Silence detection for auto-processing

**Modes:**
1. `.conversation` - Standard health companion interaction
2. `.questionnaire` - Structured health assessment
3. `.observer` - Context-aware triggered mode

### 4.4 AISDKVision (9 files)

Real-time video streaming with LiveKit.

**Key Types:**
- `ChatContext` - LiveKit Room connection manager
- `TokenService` - Connection token management
- `OrbAudioVisualizer` - Real-time audio visualization

---

## 5. Message System

### Universal Message Format

**File:** `Sources/AISDK/Models/AIMessage.swift`

The `AIInputMessage` provides a provider-agnostic message format that converts to specific LLM formats.

```swift
// Simple text message
let message = AIInputMessage.user("What's the weather?")

// Multimodal message with image
let imageMessage = AIInputMessage.user([
    .text("What's in this image?"),
    .image(imageData, detail: .high, mimeType: "image/jpeg")
])

// System message
let systemMessage = AIInputMessage.system("You are a helpful assistant.")

// Tool response
let toolResponse = AIInputMessage.tool(
    "72°F and sunny",
    callId: "call_123",
    name: "get_weather"
)
```

### Content Part Types

```mermaid
graph TD
    ACP[AIContentPart]

    ACP --> TEXT[.text - String]
    ACP --> IMAGE[.image - AIImageContent]
    ACP --> AUDIO[.audio - AIAudioContent]
    ACP --> FILE[.file - AIFileContent]
    ACP --> VIDEO[.video - AIVideoContent]
    ACP --> JSON[.json - Data]
    ACP --> HTML[.html - String]
    ACP --> MD[.markdown - String]

    IMAGE --> |data/url| IMGD[Data or URL]
    IMAGE --> |detail| DET[auto/low/high]

    AUDIO --> |format| FMT[mp3/wav/m4a/opus/flac]
    AUDIO --> |transcript| TR[Optional String]

    FILE --> |type| FT[pdf/doc/csv/json/...]
```

### Provider Conversions

The SDK automatically converts `AIInputMessage` to provider-specific formats:

| Provider | Conversion File | Target Format |
|----------|-----------------|---------------|
| OpenAI | `AIMessage+ChatConversions.swift` | `Message` |
| OpenAI Responses | `AIMessage+ResponseConversions.swift` | `ResponseInput` |
| Anthropic | `AIMessage+AnthropicConversions.swift` | Anthropic format |
| Gemini | `AIMessage+GeminiConversions.swift` | Gemini content parts |

---

## 6. Tool Framework

### Tool Protocol

**File:** `Sources/AISDK/Tools/Tool.swift`

```swift
public protocol Tool {
    var name: String { get }
    var description: String { get }
    var returnToolResponse: Bool { get }  // Skip LLM interpretation if true

    init()
    static func jsonSchema() -> ToolSchema
    func execute() async throws -> (content: String, metadata: ToolMetadata?)
    mutating func setParameters(from arguments: [String: Any]) throws
    mutating func validateAndSetParameters(_ argumentsData: Data) throws -> Self
}
```

### @Parameter Property Wrapper

```swift
@propertyWrapper
public class Parameter<Value> {
    public let description: String
    public var wrappedValue: Value
    public var validation: [String: Any]?

    // Type inference for JSON Schema
    internal static func inferType(from valueType: Any.Type) -> JSONType
}
```

### Complete Tool Example

```swift
class WeatherTool: Tool {
    let name = "get_weather"
    let description = "Get current weather for a city"

    @Parameter(description: "City name (e.g., San Francisco)")
    var city: String = ""

    @Parameter(
        description: "Temperature unit",
        validation: ["enum": ["celsius", "fahrenheit"]]
    )
    var unit: String = "fahrenheit"

    required init() {}

    func execute() async throws -> (String, ToolMetadata?) {
        // Fetch weather data...
        let result = "Weather in \(city): 72°F, sunny"
        return (result, nil)
    }
}

// Generated JSON Schema:
// {
//   "type": "function",
//   "function": {
//     "name": "get_weather",
//     "description": "Get current weather for a city",
//     "parameters": {
//       "type": "object",
//       "properties": {
//         "city": { "type": "string", "description": "City name (e.g., San Francisco)" },
//         "unit": { "type": "string", "description": "Temperature unit", "enum": ["celsius", "fahrenheit"] }
//       },
//       "required": ["city", "unit"]
//     }
//   }
// }
```

### Tool Metadata System

```swift
// Base protocol
public protocol ToolMetadata: Codable {}

// Render metadata for UI
public struct RenderMetadata: ToolMetadata {
    public let toolName: String
    public let jsonData: Data
}

// Fallback for unknown types
public struct RawToolMetadata: ToolMetadata {
    public let originalType: String
    public let payload: AIProxyJSONValue
}

// Register custom metadata types
ToolMetadataDecoderRegistry.register(MyCustomMetadata.self)
```

### RenderableTool Protocol

```swift
public protocol RenderableTool: Tool {
    func render(from data: Data) -> AnyView
}
```

---

## 7. Agent System

### Agent Class

**File:** `Sources/AISDK/Agents/Agent.swift`

The Agent orchestrates LLM interactions with automatic tool execution.

```swift
// Initialize with provider
let agent = Agent(
    llm: openai,
    tools: [WeatherTool.self, CalculatorTool.self],
    messages: [],
    instructions: "You are a helpful assistant."
)

// State change callback for UI
agent.onStateChange = { state in
    switch state {
    case .idle: print("Ready")
    case .thinking: print("Processing...")
    case .responding: print("Generating response...")
    case .executingTool(let name): print("Running \(name)...")
    case .error(let error): print("Error: \(error)")
    }
}
```

### Synchronous Send

```swift
// Wait for complete response
let response = try await agent.send("What's the weather in Tokyo?")
print(response.message)  // Full response with tool results
```

### Streaming Send

```swift
// Stream responses for real-time UI updates
let userMessage = ChatMessage(message: .user(content: .text("Tell me about...")))

for try await message in agent.sendStream(userMessage) {
    if message.isPending {
        // Partial response - update UI
        updateUI(message.displayContent)
    } else {
        // Final response
        showFinalMessage(message)
    }
}
```

### Agent Callbacks

**File:** `Sources/AISDK/Agents/AgentCallbacks.swift`

```swift
public enum CallbackResult {
    case cancel
    case replace(Message)
    case `continue`
}

public protocol AgentCallbacks: AnyObject {
    func onMessageReceived(message: Message) async -> CallbackResult
    func onBeforeLLMRequest(messages: [Message]) async -> CallbackResult
    func onStreamChunk(chunk: Message) async -> CallbackResult
    func onBeforeToolExecution(name: String, arguments: String) async -> CallbackResult
    func onAfterToolExecution(name: String, result: String) async -> CallbackResult
}

// Register callbacks
agent.addCallbacks(myCallbackHandler)
```

---

## 8. Model Registry

### LLMModelProtocol

**File:** `Sources/AISDK/LLMs/LLMModelProtocol.swift`

```swift
public protocol LLMModelProtocol: LLMCapable, LLMModelIdentifiable, LLMModelPerformance {
    var id: String { get }
    var name: String { get }
    var displayName: String { get }
    var description: String { get }
    var provider: LLMProvider { get }
    var category: LLMUsageCategory { get }
    var versionType: LLMVersionType { get }
    var capabilities: LLMCapabilities { get }
    var tier: LLMPerformanceTier? { get }
    var inputTokenLimit: Int? { get }
    var outputTokenLimit: Int? { get }
    var knowledgeCutoff: String? { get }
}
```

### Capability Flags (31+)

```swift
public struct LLMCapabilities: OptionSet {
    // Input/Output Modalities
    static let text              // Text generation
    static let vision            // Image understanding
    static let audio             // Audio input
    static let video             // Video understanding
    static let pdf               // PDF processing

    // Functional Capabilities
    static let tools             // Tool/function calling
    static let functionCalling   // Legacy function calling
    static let codeExecution     // Code interpreter
    static let structuredOutputs // JSON schema outputs
    static let jsonMode          // JSON response format

    // Advanced Capabilities
    static let reasoning         // Extended reasoning (o1, o3)
    static let thinking          // Visible thinking process
    static let search            // Search integration
    static let webSearch         // Web search
    static let grounding         // Grounded responses

    // Generation Capabilities
    static let imageGeneration   // DALL-E, Imagen
    static let audioGeneration   // Text-to-speech
    static let videoGeneration   // Veo
    static let speechToText      // Whisper
    static let textToSpeech      // TTS

    // Operational Capabilities
    static let streaming         // Streaming responses
    static let realtime          // Real-time API
    static let liveAPI           // Live interaction
    static let caching           // Prompt caching
    static let tuning            // Fine-tuning
    static let embedding         // Embeddings

    // Special Features
    static let moderation        // Content moderation
    static let computerUse       // Computer control
    static let multilingual      // Multi-language
    static let longContext       // Extended context
    static let deprecated        // Deprecated model
}
```

### Performance Tiers

```swift
public enum LLMPerformanceTier: Comparable {
    case nano      // Smallest, fastest, cheapest
    case mini      // Small, fast
    case small     // Balanced small
    case medium    // Balanced
    case large     // High capability
    case pro       // Professional grade
    case ultra     // Highest capability
    case flagship  // Best available
}
```

### Model Collections

```swift
// OpenAI Models (82 total)
OpenAIModels.gpt5          // gpt-5
OpenAIModels.gpt5Mini      // gpt-5-mini
OpenAIModels.gpt4o         // gpt-4o
OpenAIModels.o3            // o3 reasoning
OpenAIModels.o4Mini        // o4-mini
OpenAIModels.dalle3        // dall-e-3

// Anthropic Models (10 total)
AnthropicModels.claudeOpus4      // claude-opus-4-20250514
AnthropicModels.claudeSonnet4    // claude-sonnet-4-20250514
AnthropicModels.claude37Sonnet   // claude-3-7-sonnet-20250219
AnthropicModels.claude35Sonnet   // claude-3-5-sonnet-20241022

// Gemini Models (42 total)
GeminiModels.gemini25Pro         // gemini-2.5-pro
GeminiModels.gemini25Flash       // gemini-2.5-flash
GeminiModels.gemini20Flash       // gemini-2.0-flash
GeminiModels.imagen4             // imagen-4.0-generate
```

---

## 9. API Surface Reference

### Provider Initialization

```swift
// OpenAI - Model-aware (recommended)
let openai = OpenAIProvider(
    model: OpenAIModels.gpt4o,
    apiKey: "sk-...",
    baseUrl: "https://api.openai.com",
    session: .default
)

// Anthropic
let claude = AnthropicProvider(
    apiKey: "sk-ant-...",
    baseUrl: "https://api.anthropic.com/v1",
    session: .default
)

// Gemini
let gemini = GeminiProvider(
    model: GeminiModels.gemini25Flash,
    apiKey: "...",
    maxRetries: 3,
    retryDelay: 1.0
)
```

### Chat Completion

```swift
// Build request
let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        Message.system(content: .text("You are helpful")),
        Message.user(content: .text("Hello!"))
    ],
    temperature: 0.7,
    maxTokens: 1000,
    tools: [WeatherTool.jsonSchema()],
    toolChoice: .auto,
    parallelToolCalls: true
)

// Non-streaming
let response = try await openai.sendChatCompletion(request: request)
let content = response.choices.first?.message.content

// Streaming
for try await chunk in openai.sendChatCompletionStream(request: request) {
    print(chunk.choices.first?.delta.content ?? "", terminator: "")
}
```

### Structured Output

```swift
struct FruitList: Codable {
    let fruits: [Fruit]

    struct Fruit: Codable {
        let name: String
        let color: String
    }
}

let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [...],
    responseFormat: .jsonSchema(
        name: "fruit_list",
        description: "A list of fruits",
        schemaBuilder: FruitList.schema(),
        strict: true
    )
)

let fruits: FruitList = try await openai.generateObject(request: request)
```

### Agent Usage

```swift
// Create agent
let agent = Agent(
    llm: openai,
    tools: [WeatherTool.self, SearchTool.self],
    instructions: "You are a helpful assistant."
)

// Simple send
let response = try await agent.send("What's the weather in NYC?")

// Streaming with tool execution
for try await message in agent.sendStream(userMessage) {
    updateUI(message)
}

// Conversation management
agent.setMessages(previousMessages)
```

### Error Handling

```swift
do {
    let response = try await agent.send("...")
} catch let error as LLMError {
    switch error {
    case .authenticationError:
        print("Invalid API key")
    case .rateLimitExceeded:
        print("Rate limited - retry later")
    case .networkError(let code, let message):
        print("Network error \(code ?? 0): \(message)")
    case .parsingError(let details):
        print("Parse failed: \(details)")
    default:
        print("LLM error: \(error)")
    }
} catch let error as AgentError {
    switch error {
    case .toolExecutionFailed(let reason):
        print("Tool failed: \(reason)")
    case .operationCancelled:
        print("Cancelled by callback")
    default:
        print("Agent error: \(error)")
    }
}
```

---

## 10. Gap Analysis

### Missing Features vs Industry Standards

| Feature | AISDK Status | OpenAI SDK | Anthropic SDK | Vercel AI SDK | Gap Description |
|---------|--------------|------------|---------------|---------------|-----------------|
| **Prompt Caching** | Missing | Supported | Supported | Supported | No implementation for prompt caching to reduce costs |
| **Batching API** | Missing | Supported | Supported | N/A | No batch endpoint for async bulk processing |
| **Embeddings API** | Models only | Full | Full | Full | Model definitions exist but no `embed()` method |
| **PDF Support** | Missing | Supported | Supported | N/A | No native PDF handling in message system |
| **Token Counting** | Missing | tiktoken | Included | Included | No pre-request token estimation |
| **Rate Limiting** | Basic | Full | Full | Full | No automatic backoff or retry-after handling |
| **Retry Logic** | Gemini only | All | All | All | Inconsistent - only GeminiProvider has retries |
| **Computer Use** | Missing | N/A | Supported | N/A | No Anthropic computer use tool integration |
| **MCP Support** | Partial | N/A | Full | N/A | Basic MCP types but incomplete implementation |
| **Context Caching** | Missing | N/A | N/A | Supported (Gemini) | No Gemini context caching integration |
| **Cancellation** | Basic | Full | Full | Full | Stream cancellation works but no request cancellation |
| **Telemetry** | Missing | Optional | Optional | Built-in | No observability or tracing support |

### Provider-Specific Gaps

**OpenAI:**
- Missing: Assistants API, Files API, Fine-tuning API, Batch API
- Missing: Audio transcription/translation endpoints
- Missing: Image edit/variation endpoints

**Anthropic:**
- Missing: Native Messages API (uses OpenAI compatibility layer)
- Missing: Message Batches API
- Missing: Prompt caching headers

**Gemini:**
- Missing: Context caching API
- Missing: Grounding with Google Search
- Missing: Safety settings configuration

### Architecture Gaps

| Area | Current State | Industry Standard |
|------|---------------|-------------------|
| **Protocol Conformance** | GeminiProvider uses separate `GeminiService` protocol | Should conform to `LLM` protocol directly |
| **Error Standardization** | Multiple error types (AISDKError, LLMError, AgentError) | Single unified error type |
| **Logging** | Print statements | Structured logging with levels |
| **Configuration** | Environment variables only | Configuration objects with validation |
| **Testing** | Mock providers available | Dependency injection throughout |

---

## 11. File Index

### Sources/AISDK/ (66 files)

#### Root
| File | Purpose |
|------|---------|
| `AISDK.swift` | Package entry point and re-exports |

#### Agents/ (9 files)
| File | Purpose |
|------|---------|
| `Agent.swift` | Main agent class with LLM orchestration |
| `AgentState.swift` | State enum (idle, thinking, responding, executingTool, error) |
| `AgentCallbacks.swift` | Callback protocol for lifecycle hooks |
| `ResponseAgent.swift` | Specialized agent for OpenAI Responses API |
| `ResponseAgentError.swift` | Response agent error types |
| `ResearchAgent/Agent/ExperimentalResearchAgent.swift` | Experimental research agent |
| `ResearchAgent/Agent/ResearcherAgentState.swift` | Research agent states |
| `ResearchAgent/Models/ResearchMetadata.swift` | Research operation metadata |

#### Errors/ (1 file)
| File | Purpose |
|------|---------|
| `AISDKError.swift` | Error types: AISDKError, LLMError, AgentError, ToolError |

#### LLMs/ (52 files)
| File | Purpose |
|------|---------|
| `LLMProtocol.swift` | Core `LLM` protocol |
| `LLMModelProtocol.swift` | Model capabilities and metadata protocols |
| `AgenticModels.swift` | Legacy model definitions |

**LLMs/OpenAI/** (22 files)
| File | Purpose |
|------|---------|
| `OpenAIProvider.swift` | Main OpenAI provider implementation |
| `OpenAIProvider+Retry.swift` | Retry logic extension |
| `OpenAIProvider+Response.swift` | Responses API extension |
| `OpenAIModels.swift` | 82 OpenAI model definitions |
| `APIModels/ChatCompletion/ChatCompletionRequest.swift` | Request structure |
| `APIModels/ChatCompletion/ChatCompletionResponse.swift` | Response structure |
| `APIModels/ChatCompletion/ChatCompletionChunk.swift` | Streaming chunk |
| `APIModels/ChatCompletion/Message.swift` | Message types |
| `APIModels/ChatCompletion/AIMessage+ChatConversions.swift` | Universal → OpenAI |
| `APIModels/Responses/ResponseRequest.swift` | Responses API request |
| `APIModels/Responses/ResponseObject.swift` | Response object |
| `APIModels/Responses/ResponseChunk.swift` | Streaming response chunk |
| `APIModels/Responses/ResponseTool.swift` | Response tool definitions |
| `APIModels/Responses/ResponseTypes.swift` | Shared types |
| `APIModels/Responses/ResponseSession.swift` | Session tracking |
| `APIModels/Responses/AIMessage+ResponseConversions.swift` | Universal → Response |
| `APIModels/TextToSpeechQuery.swift` | TTS request |

**LLMs/Anthropic/** (11 files)
| File | Purpose |
|------|---------|
| `AnthropicProvider.swift` | OpenAI-compatible Anthropic provider |
| `AnthropicService.swift` | Native Anthropic service |
| `AnthropicModels.swift` | 10 Claude model definitions |
| `AnthropicMessageRequestBody.swift` | Request structure |
| `AnthropicMessageResponseBody.swift` | Response structure |
| `AnthropicMessageStreamingChunk.swift` | Streaming chunk |
| `AnthropicMessageStreamingContentBlockStart.swift` | Content block events |
| `AnthropicMessageStreamingDeltaBlock.swift` | Delta events |
| `AnthropicAsyncChunks.swift` | Async stream handling |
| `AIMessage+AnthropicConversions.swift` | Universal → Anthropic |
| `AnthropicMCPServer.swift` | MCP server support |
| `AnthropicMCPContentBlocks.swift` | MCP content blocks |

**LLMs/Gemini/** (12 files)
| File | Purpose |
|------|---------|
| `GeminiProvider.swift` | Main Gemini provider |
| `GeminiService.swift` | Service protocol |
| `GeminiModels.swift` | 42 Gemini model definitions |
| `GeminiGenerateContentRequestBody.swift` | Request structure |
| `GeminiGenerateContentResponseBody.swift` | Response structure |
| `GeminiImagenRequestBody.swift` | Imagen request |
| `GeminiImagenResponseBody.swift` | Imagen response |
| `GeminiFileUploadRequestBody.swift` | File upload request |
| `GeminiFileUploadResponseBody.swift` | File upload response |
| `GeminiFile.swift` | File metadata |
| `GeminiError.swift` | Gemini-specific errors |
| `AIMessage+GeminiConversions.swift` | Universal → Gemini |

#### Models/ (3 files)
| File | Purpose |
|------|---------|
| `AIMessage.swift` | Universal message format (AIInputMessage, AIContentPart) |
| `ChatMessage.swift` | Application-level message with metadata |
| `Attachment.swift` | File attachment support |
| `MedicalRecord.swift` | Domain-specific model |

#### Speech/ (1 file)
| File | Purpose |
|------|---------|
| `SpeechRecognizer.swift` | Speech recognition wrapper |

#### Tools/ (2 files)
| File | Purpose |
|------|---------|
| `Tool.swift` | Tool protocol, @Parameter, ToolMetadata |
| `ToolRegistry.swift` | Tool type registry |

#### Utilities/ (3 files)
| File | Purpose |
|------|---------|
| `ConfigManager.swift` | Environment variable management |
| `JSONSchemaRepresentable.swift` | JSON schema generation protocol |
| `AIProxyJSONValue.swift` | Dynamic JSON value handling |

---

### Examples/ (3 directories)

| Directory | Purpose |
|-----------|---------|
| `BasicChatDemo/main.swift` | CLI demo: chat, streaming, images, structured output |
| `ToolDemo/main.swift` | Tool framework demonstration |
| `Demos/` | SwiftUI demo views |

### Tests/AISDKTests/ (64 tests)

| Category | Tests | Focus |
|----------|-------|-------|
| Tool Tests | 19 | Schema generation, parameter handling, execution |
| Agent Integration | 13 | Send, stream, tools, callbacks, metadata |
| Basic Chat | 10 | Provider validation, token usage, auth |
| Streaming | 8 | SSE, chunks, concurrent, interruption |
| Multimodal | 8 | Images, base64, multiple images |
| Structured Output | 6 | JSON schema, object generation, types |

---

## Appendix: Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| Alamofire | 5.8.0+ | HTTP networking (OpenAI, Anthropic) |
| SwiftyJSON | 5.0.0+ | JSON handling |
| MarkdownUI | 2.0.0+ | Chat message rendering |
| Charts | 5.0.0+ | Data visualization |
| LiveKit | 2.0.0+ | Real-time video (Vision module) |

---

*This documentation is auto-generated from codebase analysis. Last updated: January 2025*
