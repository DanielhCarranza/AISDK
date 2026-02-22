# OpenAI Responses API

> Native OpenAI Responses API integration with streaming, built-in tools, conversation chaining, and reasoning support

## Overview

The Responses API is OpenAI's next-generation endpoint (`POST /v1/responses`) that replaces Chat Completions for new features. AISDK provides full coverage through three layers:

- **`OpenAIProvider`** — direct access to the Responses API
- **`OpenAIResponsesClientAdapter`** — bridges to the v2 `ProviderClient` protocol
- **`ResponseAgent`** — high-level agent with tool execution, conversation management, and background tasks

## Quick Start

```swift
import AISDK

let provider = OpenAIProvider(apiKey: "sk-...")

// Simple request
let response = try await provider.createResponse(request: ResponseRequest(
    model: "gpt-4o-mini",
    input: .string("What is Swift concurrency?")
))
print(response.outputText ?? "No output")

// Fluent session builder
let result = try await provider.response("Explain async/await")
    .model("gpt-4o")
    .temperature(0.7)
    .execute()
print(result.text ?? "")
```

## ResponseRequest

Main request body for `POST /v1/responses`.

```swift
public struct ResponseRequest: Encodable {
    public let model: String
    public let input: ResponseInput

    // Configuration
    public var instructions: String?
    public var tools: [ResponseTool]?
    public var toolChoice: ToolChoice?
    public var temperature: Double?
    public var topP: Double?
    public var maxOutputTokens: Int?
    public var reasoning: ResponseReasoning?
    public var text: ResponseTextConfig?
    public var truncation: String?

    // Conversation & storage
    public var previousResponseId: String?
    public var store: Bool?
    public var include: [String]?

    // Execution
    public var stream: Bool?
    public var background: Bool?
    public var parallelToolCalls: Bool?
    public var serviceTier: String?
    public var metadata: [String: String]?
    public var user: String?
}
```

### ResponseInput

```swift
public enum ResponseInput: Encodable {
    case string(String)               // Simple text (treated as user message)
    case items([ResponseInputItem])   // Structured conversation items
}
```

### ResponseInputItem

```swift
public enum ResponseInputItem: Codable {
    case message(ResponseMessage)
    case functionCallOutput(ResponseFunctionCallOutput)
    case computerCallOutput(ResponseComputerCallOutput)
    case computerCall(ResponseInputComputerCall)
    case mcpApprovalResponse(ResponseMCPApprovalResponse)
    case itemReference(ResponseItemReference)
}
```

### Content Types

```swift
// Text
ResponseInputText(text: "Hello")

// Image (URL or base64 data URL)
ResponseInputImage(imageUrl: "https://example.com/photo.jpg")
ResponseInputImage(imageUrl: "data:image/png;base64,iVBOR...")

// File (three modes)
ResponseInputFile(fileId: "file_abc")
ResponseInputFile(fileUrl: "https://example.com/doc.pdf", filename: "doc.pdf")
ResponseInputFile(fileData: "base64...", filename: "data.csv")
```

## ResponseObject

Full response from the API.

```swift
public struct ResponseObject: Codable {
    public let id: String
    public let model: String
    public let status: ResponseStatus
    public let output: [ResponseOutputItem]
    public let usage: ResponseUsage?
    public let previousResponseId: String?
    public let error: ResponseError?
    // ... plus metadata, config echo-back fields

    /// Extract text from the first message output
    public var outputText: String?
}
```

### ResponseStatus

```swift
public enum ResponseStatus: String, Codable {
    case completed, inProgress, queued, failed, cancelled, incomplete

    public var isFinal: Bool      // completed, failed, cancelled, or incomplete
    public var isProcessing: Bool  // inProgress or queued
}
```

### ResponseUsage

```swift
public struct ResponseUsage: Codable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int
    public let inputTokensDetails: ResponseInputTokensDetails?   // cachedTokens
    public let outputTokensDetails: ResponseOutputTokensDetails?  // reasoningTokens
}
```

Token details are preserved through all adapter layers:
- `inputTokensDetails.cachedTokens` maps to `AIUsage.cachedTokens`
- `outputTokensDetails.reasoningTokens` maps to `AIUsage.reasoningTokens`

## Output Items

Responses return a polymorphic array of output items.

```swift
public enum ResponseOutputItem: Codable {
    case message(ResponseOutputMessage)
    case functionCall(ResponseOutputFunctionCall)
    case functionCallOutput(ResponseOutputFunctionCallOutput)
    case webSearchCall(ResponseOutputWebSearchCall)
    case imageGenerationCall(ResponseOutputImageGenerationCall)
    case codeInterpreterCall(ResponseOutputCodeInterpreterCall)
    case computerCall(ResponseOutputComputerCall)
    case reasoning(ResponseOutputReasoningItem)
    case mcpCall(ResponseOutputMCPCall)
    case mcpListTools(ResponseOutputMCPListTools)
    case mcpApprovalRequest(ResponseOutputMCPApprovalRequest)
    case unknown(String)  // Forward-compatible with future types
}
```

### Message Output

```swift
public struct ResponseOutputMessage: Codable {
    public let id: String
    public let role: String
    public let content: [ResponseOutputContent]
    public let status: String?
}

public enum ResponseOutputContent: Codable {
    case outputText(ResponseOutputText)
    case outputImage(ResponseOutputImage)
    case refusal(ResponseOutputRefusal)
    case unknown(String)
}
```

### Annotations

Text output may include citation annotations from web search or file search.

```swift
public enum ResponseAnnotation: Codable {
    case urlCitation(URLCitationAnnotation)            // Web search source
    case fileCitation(FileCitationAnnotation)           // File search source
    case containerFileCitation(ContainerFileCitationAnnotation)
    case filePath(FilePathAnnotation)
    case unknown(String)
}

public struct URLCitationAnnotation: Codable {
    public let url: String
    public let title: String?
    public let startIndex: Int
    public let endIndex: Int
}
```

### Reasoning Output

Reasoning items from o-series models (o1, o3, o4-mini).

```swift
public struct ResponseOutputReasoningItem: Codable {
    public let id: String
    public let content: [ReasoningTextContent]?    // Actual reasoning text
    public let summary: [ReasoningSummaryContent]?  // Summary when summary="auto"
    public let encryptedContent: String?            // For multi-turn when store=false
    public let status: String?
}

public struct ReasoningTextContent: Codable {
    public let text: String
    public let type: String  // "reasoning_text"
}
```

Configure reasoning via `ResponseReasoning(effort: "low"|"medium"|"high", summary: "auto"|"concise"|"detailed")`.

Use `include: ["reasoning.encrypted_content"]` to get encrypted content for stateless multi-turn conversations.

### Function Call Output

```swift
public struct ResponseOutputFunctionCall: Codable {
    public let id: String
    public let name: String
    public let arguments: String   // JSON string
    public let callId: String
    public let status: String?
}
```

### Web Search Output

```swift
public struct ResponseOutputWebSearchCall: Codable {
    public let id: String
    public let query: String?
    public let result: String?
    public let status: String?
    public let action: WebSearchAction?  // Detailed action info with sources
}
```

### Code Interpreter Output

```swift
public struct ResponseOutputCodeInterpreterCall: Codable {
    public let id: String
    public let code: String?
    public let result: String?
    public let status: String?
    public let containerId: String?
    public let outputs: [CodeInterpreterOutput]?  // logs, images
}
```

## Built-in Tools

Configure tools via the `ResponseTool` enum.

```swift
public enum ResponseTool: Codable {
    case webSearchPreview(ResponseWebSearchTool)
    case fileSearch(ResponseFileSearchTool)
    case codeInterpreter(ResponseCodeInterpreterTool)
    case imageGeneration(ResponseImageGenerationTool)
    case computerUsePreview(ResponseComputerUseTool)
    case mcp(ResponseMCPTool)
    case function(ToolFunction)
}
```

### Web Search

```swift
// Default
let tool = ResponseTool.webSearchPreview()

// With configuration
let tool = ResponseTool.webSearchPreview(ResponseWebSearchTool(
    searchContextSize: "high",       // "low", "medium", "high"
    userLocation: WebSearchUserLocation(
        city: "San Francisco",
        country: "US",
        timezone: "America/Los_Angeles"
    ),
    filters: WebSearchFilters(
        allowedDomains: ["docs.swift.org", "developer.apple.com"]
    )
))
```

### Code Interpreter

```swift
// Auto container
let tool = ResponseTool.codeInterpreter()

// With file access
let tool = ResponseTool.codeInterpreter(ResponseCodeInterpreterTool(
    container: .auto(fileIds: ["file_abc", "file_def"])
))

// Reuse existing container
let tool = ResponseTool.codeInterpreter(ResponseCodeInterpreterTool(
    container: .id("ctr_existing_123")
))
```

### File Search (RAG)

```swift
let tool = ResponseTool.fileSearch(ResponseFileSearchTool(
    vectorStoreIds: ["vs_abc"],
    maxNumResults: 20,
    rankingOptions: ResponseFileSearchRankingOptions(
        ranker: "auto",
        scoreThreshold: 0.5
    )
))
```

### Image Generation

```swift
let tool = ResponseTool.imageGeneration(ResponseImageGenerationTool(
    background: "transparent",
    model: "gpt-image-1",
    outputFormat: "png",
    quality: "high",
    size: "1024x1024"
))
```

### MCP Server

```swift
let tool = ResponseTool.mcp(ResponseMCPTool(
    serverLabel: "my-mcp",
    serverUrl: "https://mcp.example.com",
    allowedTools: ["search", "create"],
    requireApproval: "always"   // "always", "never"
))
```

## Streaming

### Direct Streaming

```swift
let stream = provider.createResponseStream(request: ResponseRequest(
    model: "gpt-4o",
    input: .string("Tell me a story")
))

for try await chunk in stream {
    if let text = chunk.delta?.outputText {
        print(text, terminator: "")
    }
    if chunk.status?.isFinal == true {
        print("\nDone!")
    }
}
```

### Fluent Session Streaming

```swift
for try await chunk in provider.response("Tell me a story").stream() {
    if let text = chunk.text {
        print(text, terminator: "")
    }
}
```

### Stream Event Types

The streaming pipeline handles 27 event types from the Responses API:

| Event | Mapping |
|-------|---------|
| `response.output_text.delta` | `ResponseDelta.outputText` / `ProviderStreamEvent.textDelta` |
| `response.function_call_arguments.delta` | `ResponseDelta.functionCallArgumentsDelta` / `ProviderStreamEvent.toolCallDelta` |
| `response.function_call_arguments.done` | `ResponseDelta.functionCallArgumentsDelta` |
| `response.output_item.added` | `ResponseDelta.output` (function call start tracking) |
| `response.output_item.done` | `ResponseDelta.output` (complete item with citations, tool calls) |
| `response.reasoning_summary_text.delta` | `ResponseDelta.reasoning` / `ProviderStreamEvent.reasoningDelta` |
| `response.completed` | `ProviderStreamEvent.finish(reason: .stop)` |
| `response.incomplete` | `ProviderStreamEvent.finish(reason: .length)` |

URL citation annotations on completed message items are emitted as `ProviderStreamEvent.source(AISource)`.

### ResponseDelta

```swift
public struct ResponseDelta: Codable {
    public let output: [ResponseOutputItem]?
    public let outputText: String?
    public let reasoning: ResponseReasoning?
    public let text: String?
    public let functionCallArgumentsDelta: String?
}
```

### SimpleResponseChunk

Simplified streaming wrapper for consumer-friendly access.

```swift
public struct SimpleResponseChunk {
    public let text: String?
    public let toolCall: ToolCallInfo?       // Extracted from output items
    public let reasoning: String?
    public let error: ErrorInfo?
    public let isComplete: Bool
    public let id: String
    public let status: ResponseStatus?
    public let raw: ResponseChunk
}
```

## Conversation Chaining

Link responses for multi-turn conversations without re-sending full history.

```swift
// First turn
let response1 = try await provider.createResponse(request: ResponseRequest(
    model: "gpt-4o",
    input: .string("My name is Alice."),
    store: true
))

// Second turn — server recalls context
let response2 = try await provider.createResponse(request: ResponseRequest(
    model: "gpt-4o",
    input: .string("What is my name?"),
    previousResponseId: response1.id,
    store: true
))
```

Set `store: true` for server-side storage. When `store: false` (default), pass `previousResponseId` explicitly and include `reasoning.encrypted_content` for reasoning model conversations.

## OpenAIResponsesClientAdapter

Bridges the Responses API to the v2 `ProviderClient` protocol for use with `ProviderLanguageModelAdapter` and the unified `LLM` interface.

```swift
let adapter = OpenAIResponsesClientAdapter(
    apiKey: "sk-...",
    store: false  // Privacy-first default
)

// Use via ProviderLanguageModelAdapter
let llm = ProviderLanguageModelAdapter(client: adapter)
let result = try await llm.generateText(prompt: "Hello", model: "gpt-4o")
```

### Finish Reason Mapping

| ResponseStatus | AIFinishReason | ProviderFinishReason |
|----------------|---------------|---------------------|
| `.completed` | `.stop` | `.stop` |
| `.incomplete` | `.length` | `.length` |
| `.failed` | `.error` | `.unknown` |
| `.cancelled` | `.cancelled` | `.unknown` |

### Streaming Event Mapping

The adapter emits the full set of `ProviderStreamEvent` cases:

- **`.textDelta`** from text output deltas
- **`.toolCallStart`** / **`.toolCallDelta`** / **`.toolCallFinish`** from function call events (supports incremental argument streaming)
- **`.reasoningDelta`** from reasoning summary text deltas
- **`.source(AISource)`** from URL citation annotations on completed messages
- **`.usage`** with `cachedTokens` and `reasoningTokens` preserved
- **`.finish`** with correct reason mapping

## ResponseAgent

High-level agent with automatic tool execution, conversation tracking, and background task support.

```swift
let agent = try ResponseAgent(
    provider: provider,
    tools: [WeatherTool.self, CalculatorTool.self],
    builtInTools: [.webSearchPreview, .codeInterpreter],
    instructions: "You are a helpful assistant.",
    model: "gpt-4o"
)

// Streaming conversation
for try await message in agent.send("What's the weather in Tokyo?", streaming: true) {
    print(message.content, terminator: "")
}

// Background task
let result = try await agent.task("Analyze this dataset", configuration: .init(
    maxWaitTime: 300,
    pollInterval: 5,
    enableProgressTracking: true
))
```

The agent tracks `lastResponseId` automatically across turns and manages tool call/result round-trips.

## ResponseSession (Fluent Builder)

Chainable request builder for lightweight use cases.

```swift
let result = try await provider.response("Summarize this article")
    .model("gpt-4o-mini")
    .tools([.webSearchPreview()])
    .instructions("Be concise.")
    .temperature(0.3)
    .maxOutputTokens(500)
    .previousResponse("resp_abc123")
    .execute()

print(result.text ?? "")
print(result.annotations)  // URL citations
print(result.usage)         // Token counts
```

## Image Data Handling

When converting `AIImageContent` with raw `Data` (no URL), the SDK automatically encodes it as a base64 data URL:

```swift
let image = AIImageContent(data: pngData, mimeType: "image/png")
// Converted to: data:image/png;base64,iVBOR...
// Sent as ResponseInputImage(imageUrl: "data:image/png;base64,...")
```

URL-based images are passed through directly.
