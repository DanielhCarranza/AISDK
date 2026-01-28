# OpenAI Responses API Implementation

> AISDK's integration with OpenAI's Responses API - a stateful, tool-native alternative to the Chat Completions API.

**Last Updated**: January 2026
**Status**: Production Ready

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Core Components](#3-core-components)
4. [Built-in Tools](#4-built-in-tools)
5. [Advanced Features](#5-advanced-features)
6. [Testing](#6-testing)
7. [Usage Examples](#7-usage-examples)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Overview

### What is the Responses API?

The Responses API is OpenAI's newer API that provides:

- **Server-side conversation state** via `previous_response_id` - no need to resend message history
- **Native tool support** - web search, file search (RAG), code interpreter built-in
- **Richer streaming events** - granular status updates, reasoning tokens, tool progress
- **Background execution** - for long-running tasks like file processing

### Why AISDK Uses It

- **Eliminates client-side message history management** - server remembers context
- **Built-in RAG via file_search** - no custom vector database needed
- **Web search without external APIs** - OpenAI handles search infrastructure
- **Code execution in sandboxed containers** - Python execution with file access
- **Privacy-first defaults** - `store: nil` by default, explicit opt-in required

### Key Differences from Chat Completions API

| Feature | Chat Completions | Responses API |
|---------|-----------------|---------------|
| State Management | Client-side | Server-side |
| Message History | Send full history | Use `previous_response_id` |
| Built-in Tools | None | Web search, file search, code interpreter |
| Streaming Events | Basic deltas | Rich event taxonomy |
| Background Tasks | Not supported | Supported |

---

## 2. Architecture

### File Structure

```
Sources/AISDK/LLMs/OpenAI/
├── OpenAIProvider.swift                    # Main provider (LLM protocol)
├── OpenAIProvider+AITextRequest.swift      # AITextRequest bridge
├── OpenAIProvider+BackgroundTasks.swift    # Async operations
├── OpenAIProvider+Compaction.swift         # Conversation compaction
└── APIModels/Responses/
    ├── ResponseRequest.swift               # Request model
    ├── ResponseObject.swift                # Response model
    ├── ResponseChunk.swift                 # Streaming chunks
    ├── ResponseTool.swift                  # Tool definitions
    ├── ResponseSession.swift               # Fluent builder API
    ├── ResponseTypes.swift                 # Wrapper types (Response, SimpleResponseChunk)
    ├── OpenAIRequestOptions.swift          # Provider-specific options
    ├── OpenAIFileManager.swift             # File upload/download
    ├── OpenAIVectorStoreManager.swift      # Vector store CRUD
    ├── OpenAIContainerManager.swift        # Container lifecycle
    ├── OpenAIConversationManager.swift     # Conversation state
    └── OpenAICompactionModels.swift        # Compaction types
```

### Data Flow

```
┌─────────────────┐     ┌──────────────────────────────┐     ┌─────────────────┐
│  AITextRequest  │ ──▶ │ OpenAIProvider+AITextRequest │ ──▶ │ ResponseRequest │
└─────────────────┘     │ (converts messages/tools)    │     └────────┬────────┘
                        └──────────────────────────────┘              │
                                                                      ▼
                                                              ┌───────────────┐
                                                              │  OpenAI API   │
                                                              │ /v1/responses │
                                                              └───────┬───────┘
                                                                      │
┌─────────────────┐     ┌──────────────────────────────┐              │
│  AITextResult   │ ◀── │    convertToAITextResult()   │ ◀────────────┘
└─────────────────┘     └──────────────────────────────┘     ResponseObject
```

### Provider Extension Pattern

The implementation uses Swift extensions to separate concerns:

- **OpenAIProvider.swift** - Core HTTP client, Chat Completions API
- **OpenAIProvider+AITextRequest.swift** - Provider-agnostic `AITextRequest` bridge
- **OpenAIProvider+BackgroundTasks.swift** - Background task management
- **OpenAIProvider+Compaction.swift** - Conversation compaction

---

## 3. Core Components

### ResponseRequest

Flexible request model supporting multiple input formats:

```swift
public struct ResponseRequest: Codable, Sendable {
    public let model: String
    public let input: ResponseInput           // String or structured items
    public var instructions: String?          // System prompt
    public var tools: [ResponseTool]?         // Built-in + custom tools
    public var previousResponseId: String?    // Conversation chaining
    public var stream: Bool?
    public var background: Bool?
    public var store: Bool?                   // Server-side storage
    public var reasoning: ResponseReasoning?  // For o1/o3 models
    // ... additional parameters
}
```

### ResponseObject

Rich response with multiple output types:

```swift
public struct ResponseObject: Codable, Sendable {
    public let id: String
    public let status: ResponseStatus
    public let output: [ResponseOutputItem]
    public let usage: ResponseUsage?
    public let model: String
    public let createdAt: Int
}

public enum ResponseStatus: String, Codable, Sendable {
    case completed
    case inProgress = "in_progress"
    case queued
    case failed
    case cancelled
    case incomplete
}
```

### ResponseOutputItem Types

```swift
public enum ResponseOutputItem: Codable, Sendable {
    case message(ResponseOutputMessage)           // Text/image output
    case functionCall(ResponseOutputFunctionCall) // Tool invocation
    case functionCallOutput(...)                  // Tool result
    case webSearchCall(...)                       // Web search execution
    case codeInterpreterCall(...)                 // Code execution
    case imageGenerationCall(...)                 // Image generation
    case mcpApprovalRequest(...)                  // MCP approval
}
```

### ResponseChunk (Streaming)

Granular streaming events:

- **Text deltas** - Incremental text content
- **Tool call progress** - Function arguments streaming
- **Reasoning tokens** - For o1/o3 models
- **Status updates** - Response lifecycle events

---

## 4. Built-in Tools

### Web Search

Enable real-time web search in responses:

```swift
var request = AITextRequest(
    messages: [.user("What's the latest news about Swift?")],
    model: "gpt-4o"
)
request.providerOptions = OpenAIRequestOptions.withWebSearch(
    searchContextSize: .medium,
    domainFilters: .allow(["apple.com", "swift.org"]),
    userLocation: UserLocation(country: "US", city: "San Francisco")
)
let result = try await provider.sendTextRequest(request)
```

**Configuration Options:**

| Option | Type | Description |
|--------|------|-------------|
| `searchContextSize` | `.low`, `.medium`, `.high` | Amount of search context |
| `domainFilters` | `DomainFilters` | Allow/block specific domains |
| `userLocation` | `UserLocation` | Localized search results |

### File Search (RAG)

Vector-based document search:

```swift
request.providerOptions = OpenAIRequestOptions.withFileSearch(
    vectorStoreIds: ["vs_abc123"],
    maxNumResults: 10,
    rankingOptions: FileSearchRankingOptions(
        ranker: "default_2024_11_15",
        scoreThreshold: 0.7
    )
)
```

**Requires**: Upload files via `OpenAIFileManager` and create vector stores via `OpenAIVectorStoreManager`.

### Code Interpreter

Execute Python code in sandboxed containers:

```swift
request.providerOptions = OpenAIRequestOptions.withCodeInterpreter(
    containerId: "container_xyz",  // Optional: persistent state
    fileIds: ["file-abc123"]       // Optional: available files
)
```

**Use Cases**: Data analysis, file processing, calculations, chart generation.

---

## 5. Advanced Features

### Conversation Chaining

Server-side context preservation without resending history:

```swift
// First request
let result1 = try await provider.sendTextRequest(
    AITextRequest(messages: [.user("My name is Alice")])
)

// Second request - server remembers context
var request2 = AITextRequest(messages: [.user("What's my name?")])
request2 = request2.withConversationId(result1.responseId)
let result2 = try await provider.sendTextRequest(request2)
// result2.text contains "Alice"
```

### Background Tasks

For long-running operations (file processing, complex reasoning):

```swift
var options = OpenAIRequestOptions()
options.background = true
request.providerOptions = options

let result = try await provider.sendTextRequest(request)
// Poll via result.responseId until status is .completed
```

### Reasoning Configuration (o1/o3 Models)

Configure reasoning effort for complex tasks:

```swift
request.providerOptions = OpenAIRequestOptions.withReasoning(
    effort: .high,      // .low, .medium, .high
    summary: .detailed  // .auto, .concise, .detailed
)
```

### Fluent API (ResponseSession)

Clean builder pattern for complex requests:

```swift
let response = try await provider.response("Analyze this data")
    .model("gpt-4o")
    .tools([.webSearchPreview, .codeInterpreter])
    .temperature(0.7)
    .maxOutputTokens(4096)
    .instructions("You are a data analyst")
    .execute()

print(response.text)
```

### Streaming with ResponseSession

```swift
for try await chunk in provider.response("Tell me a story").stream() {
    if let delta = chunk.textDelta {
        print(delta, terminator: "")
    }
}
```

---

## 6. Testing

### Test File Organization

```
Tests/AISDKTests/LLMTests/Providers/
├── OpenAIResponsesModelsTests.swift      # Request/response encoding
├── OpenAIStreamParserTests.swift         # SSE event parsing
├── OpenAIRequestOptionsTests.swift       # Options configuration
├── OpenAIProviderTextRequestTests.swift  # AITextRequest integration
├── OpenAIResponsesProviderUnitTests.swift # Provider unit tests
├── OpenAIResponsesSessionTests.swift     # Fluent API tests
├── OpenAIResponsesStreamingTests.swift   # Streaming tests
├── OpenAIResponsesToolsTests.swift       # Tool tests
├── OpenAIFileManagerTests.swift          # File operations
├── OpenAIVectorStoreManagerTests.swift   # Vector store CRUD
├── OpenAIResponsesRealAPITests.swift     # Live API integration
└── OpenAILiveTestHelpers.swift           # Test utilities
```

### Running Unit Tests

```bash
swift test --filter "OpenAIResponses"
```

### Running Live API Tests

```bash
USE_REAL_API=true OPENAI_API_KEY=sk-... swift test \
  --filter OpenAIResponsesRealAPITests
```

### CLI Testing

```bash
# Basic text request
swift run AISDKCLI --provider openai "What is 2+2?"

# With web search
swift run AISDKCLI --provider openai --web-search "Latest Swift news"

# Streaming
swift run AISDKCLI --provider openai --stream "Tell me a joke"
```

---

## 7. Usage Examples

### Basic Text Request

```swift
let provider = OpenAIProvider(apiKey: "sk-...")

let request = AITextRequest(
    messages: [AIMessage(role: .user, content: .text("Hello!"))],
    model: "gpt-4o"
)

let result = try await provider.sendTextRequest(request)
print(result.text)
print("Tokens used: \(result.usage.totalTokens)")
```

### Streaming Response

```swift
let request = AITextRequest(
    messages: [.user("Write a short poem")],
    model: "gpt-4o"
)

for try await chunk in provider.streamTextRequest(request) {
    if let delta = chunk.delta?.outputText {
        print(delta, terminator: "")
    }
}
```

### With Custom Tools

```swift
struct WeatherTool: AITool {
    static var name = "get_weather"
    static var description = "Get current weather for a location"

    @Parameter(description: "City name")
    var city: String

    func execute() async throws -> String {
        return "Sunny, 72°F in \(city)"
    }
}

let request = AITextRequest(
    messages: [.user("What's the weather in San Francisco?")],
    tools: [WeatherTool.self]
)

let result = try await provider.sendTextRequest(request)
// Provider will call WeatherTool and include result
```

### Multimodal (Images)

```swift
let imageData = try Data(contentsOf: imageURL)

let request = AITextRequest(
    messages: [
        AIMessage(role: .user, content: .parts([
            .text("What's in this image?"),
            .image(imageData, mimeType: "image/jpeg")
        ]))
    ],
    model: "gpt-4o"
)

let result = try await provider.sendTextRequest(request)
```

### Multiple Built-in Tools

```swift
var request = AITextRequest(
    messages: [.user("Search for Swift 6 features and write a summary")],
    model: "gpt-4o"
)

var options = OpenAIRequestOptions()
options.webSearch = WebSearchConfig(enabled: true, searchContextSize: .high)
options.codeInterpreter = CodeInterpreterConfig(enabled: true)
request.providerOptions = options

let result = try await provider.sendTextRequest(request)
```

---

## 8. Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| 401 Unauthorized | Invalid API key | Verify `OPENAI_API_KEY` environment variable |
| 400 Bad Request | Invalid model name | Use valid model like `gpt-4o` |
| Tool not found | Wrong tool type | Use `ResponseTool` enum values |
| Stream hangs | Network timeout | Set request timeout, check connectivity |
| Empty response | Model finished early | Check `finishReason` in result |
| Rate limited | Too many requests | Implement exponential backoff |

### Debug Logging

The provider includes debug output showing:
- Request payloads (JSON)
- Response data
- HTTP status codes

Check console output during development for request/response details.

### Streaming Issues

If streaming stops unexpectedly:

1. Check `finishReason` in the final chunk
2. Verify network connectivity
3. Ensure response isn't being filtered (content moderation)
4. Check for timeout settings

### Tool Execution Failures

If tools aren't being called:

1. Verify tool is in `tools` array
2. Check tool schema matches expected format
3. Ensure model supports function calling
4. Review tool `description` for clarity

---

## Additional Resources

- **OpenAI Responses API Documentation**: https://platform.openai.com/docs/api-reference/responses
- **AISDK Repository**: Internal documentation and examples
- **CLI Help**: `swift run AISDKCLI --help`
