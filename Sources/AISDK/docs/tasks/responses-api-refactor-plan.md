# OpenAI Responses API Refactoring Plan

## Executive Summary

This document outlines a comprehensive refactoring plan for the OpenAI Responses API implementation in AISDK. The goal is to dramatically simplify the API surface while maintaining full functionality, making it more intuitive and easier to use for developers.

## Current Problems Analysis

**Key Discovery**: After thorough code review, the underlying Response API structures are **excellent**. The issue is **API surface complexity**, not implementation quality.

### 1. API Surface Complexity (7+ Entry Points)
**The Problem**: Despite excellent underlying code, too many entry points create confusion:
```swift
// Current: Multiple methods for similar tasks
provider.createTextResponse(model: "gpt-4o", text: "Hello")
provider.createResponseWithWebSearch(model: "gpt-4o", text: "Search")  
provider.createResponseWithCodeInterpreter(model: "gpt-4o", text: "Calculate")
provider.createTextResponseStream(model: "gpt-4o", text: "Stream")

// Current: Multiple builder factories (this is deprecated and will be removed in the future)
ResponseBuilder.text(model: "gpt-4o", "Hello")
ResponseBuilder.webSearch(model: "gpt-4o", "Query") 
ResponseBuilder.multiTool(model: "gpt-4o", "Complex")
```

**What's Actually Excellent**: 
- `ResponseBuilder` has all needed fluent methods (this is deprecated and will be removed in the future)
- `createResponse()` and `createResponseStream()` work perfectly
- All advanced features already exist

### 2. Hidden Existing Capabilities
**The Problem**: Excellent structures are buried behind complex entry points:

```swift
// ALREADY EXISTS: Perfect multimodal input handling
let input = ResponseInput.items([
    ResponseMessage(role: "user", content: [
        .inputText(ResponseInputText(text: "Compare these:")),
        .inputImage(ResponseInputImage(imageUrl: "image1.jpg")),
        .inputText(ResponseInputText(text: "vs")),
        .inputImage(ResponseInputImage(imageUrl: "image2.jpg"))
    ])
])

// ALREADY EXISTS: Perfect mixed tool syntax  
let tools: [ResponseTool] = [
    .webSearchPreview,                    // Built-in enum
    .codeInterpreter,                     // Built-in enum
    .function(WeatherTool().toFunction()) // Custom instance
]

// ALREADY EXISTS: Perfect response structure
response.outputText              // Clean text access
response.output                  // Full multimodal outputs
response.reasoning               // AI reasoning steps
response.previousResponseId      // Conversation continuation
response.usage                   // Token usage
```

### 3. Excellent Structures Need Simple Access
**The Problem**: Not structure complexity - just need easier access patterns:

```swift
// Current: Must navigate internal structure (but it's well-designed)
for output in response.output {
    if case .message(let message) = output {
        for content in message.content {
            if case .outputText(let textContent) = content {
                print(textContent.text)              // ✅ Text
                print(textContent.annotations)       // ✅ Citations already exist!
            }
        }
    }
}

// Desired: Direct access to existing excellent fields
print(response.outputText)        // ✅ Already exists!
// Just need: response.annotations (computed property from existing structure)
```

### 4. All Advanced Features Already Implemented
**What Already Works Perfectly**:
- ✅ **Background processing**: `builder.background(true)`
- ✅ **Conversation continuation**: `builder.previousResponse(id)`  
- ✅ **Advanced reasoning**: `builder.reasoning(ResponseReasoning(...))`
- ✅ **Mixed tool syntax**: `[.webSearchPreview, .function(tool)]`
- ✅ **Multimodal I/O**: `ResponseInput.items()` and `ResponseOutput` types
- ✅ **Sophisticated streaming**: `ResponseStreamEvent` with all event types
- ✅ **Citations**: `ResponseAnnotation` with `startIndex`, `endIndex`, `text`

### 5. Simple Solution Needed
**Not a rebuild - just a clean wrapper around excellent existing code**

## Core Capabilities This Refactoring Enables

### 🎯 **What Developers Get With The New API**

#### 1. Multimodal Input & Output (Order-Aware)
**Input**: Natural sequences of text, images, audio, files
```swift
provider.response([
    .text("Compare these medical scans:"),
    .image(scan1), .image(scan2),
    .audio(patientDescription)
])
```

*Note: Uses universal `AIContentPart` types that convert to Response API format*

**Output**: AI can generate images, audio, files - not just text
```swift
for content in response.content {
    switch content {
    case .image(let data): displayGeneratedChart(data)
    case .audio(let data): playGeneratedSummary(data)
    case .file(let url): downloadGeneratedReport(url)
    }
}
```

#### 2. Mixed Tool Ecosystem (Built-in + Custom + MCP)
**Perfect tool syntax mixing enums and instances:**
```swift
.tools([
    .webSearch,              // ✅ Built-in enum
    .codeInterpreter,        // ✅ Built-in enum  
    .imageGeneration,        // ✅ Built-in enum
    .mcp(                    // ✅ Built-in MCP enum
        serverLabel: "company-slack",
        serverUrl: "https://company.slack.mcp"
    ),
    WeatherTool(),           // ✅ Custom instance
    DatabaseTool(),          // ✅ Custom instance
    MCPNotionTool(),         // ✅ MCP custom instance
    MCPSalesforceTool()      // ✅ MCP custom instance (with approval)
])
```

**Multiple Ways to Use MCP Tools:**
```swift
// Option 1: Built-in MCP enum (simple servers)
.tools([
    .mcp(serverLabel: "slack", serverUrl: "https://company.slack.mcp"),
    .mcp(serverLabel: "notion", serverUrl: "https://company.notion.mcp")
])

// Option 2: Custom MCP tool instances (complex logic + approval)
.tools([
    MCPSalesforceTool(          // Custom instance with business logic
        serverUrl: "https://company.salesforce.mcp",
        authToken: "sf-token",
        requireApproval: true   // Needs user approval for data access
    ),
    MCPSlackTool(              // Custom instance with search logic
        serverUrl: "https://company.slack.mcp", 
        authToken: "slack-token",
        channelFilters: ["engineering", "product"]
    )
])

// Option 3: Mixed approach (simple + complex)
.tools([
    .webSearch,                // Built-in web search
    .mcp(                      // Built-in MCP for simple servers
        serverLabel: "docs",
        serverUrl: "https://company.docs.mcp"
    ),
    MCPCRMTool(               // Custom MCP with complex logic
        serverUrl: "https://company.crm.mcp",
        authToken: crmToken,
        requireApproval: true,
        allowedOperations: ["read", "search"]
    )
])
```

**Concrete MCP Tool Example:**
```swift
// MCP tool connecting to Slack workspace
class MCPSlackTool: Tool {
    let name = "slack_search"
    let description = "Search messages and files in Slack workspace"
    
    @Parameter(description: "Search query")
    var query: String = ""
    
    @Parameter(description: "Channel to search in", validation: ["type": "string"])
    var channel: String? = nil
    
    @Parameter(description: "Date range in days", validation: ["minimum": 1, "maximum": 30])
    var dayRange: Int = 7
    
    private let mcpClient: MCPClient
    
    init(serverUrl: String, authToken: String) {
        self.mcpClient = MCPClient(
            serverUrl: serverUrl,
            authToken: authToken,
            protocol: .slack
        )
    }
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Connect to MCP server
        let mcpResponse = try await mcpClient.call(
            method: "slack_search",
            parameters: [
                "query": query,
                "channel": channel,
                "day_range": dayRange
            ]
        )
        
        // Parse MCP response
        let results = try MCPSlackResponse.parse(mcpResponse)
        
        let summary = """
        Found \(results.messages.count) messages in Slack:
        
        \(results.messages.map { "- \($0.user): \($0.text)" }.joined(separator: "\n"))
        """
        
        let metadata = ToolMetadata(
            sources: results.messages.map { 
                Source(url: $0.permalink, title: "Slack: \($0.channel)", type: .slack)
            },
            data: ["total_results": results.messages.count]
        )
        
        return (summary, metadata)
    }
}

// Usage in the new API
let response = try await provider.response("What did the team discuss about the new feature?")
    .tools([
        .webSearch,                           // Built-in
        MCPSlackTool(                        // MCP tool
            serverUrl: "https://company.slack.mcp",
            authToken: "xoxb-token"
        ),
        MCPNotionTool(                       // Another MCP tool
            serverUrl: "https://company.notion.mcp",
            authToken: "notion-token"
        )
    ])
    .execute()

// AI can now search Slack + Notion + web simultaneously!

// Handle MCP approval requests (uses existing ResponseOutputMCPApprovalRequest)
for output in response.raw.output {
    if case .mcpApprovalRequest(let approval) = output {
        print("MCP tool '\(approval.name)' from server '\(approval.serverLabel)' needs approval")
        print("Arguments: \(approval.arguments)")
        
        // In a real app, prompt user for approval
        let userApproved = await promptUserForApproval(tool: approval.name, server: approval.serverLabel)
        
        if userApproved {
            // Continue conversation with approval
            let approvalResponse = try await provider.response("User approved the MCP tool access")
                .previousResponse(response.id)
                .execute()
        }
    }
}
```

#### 3. Background Processing (Long-Running Tasks)
**Tasks that exceed HTTP timeouts:**
```swift
let response = try await provider.response("Analyze 10GB dataset")
    .tools([.codeInterpreter, DataAnalysisTool()])
    .background(true)  // Runs in background, returns immediately
    .execute()

if response.status == .processing {
    print("Task running in background: \(response.id)")
    // Poll for completion when ready
}
```

#### 4. Stateful Conversations (Context Preservation)
**Automatic conversation management:**
```swift
// Conversation state maintained automatically
let response1 = try await provider.response("Start analyzing sales data")
    .execute()

let response2 = try await provider.response("Now compare to last quarter")
    .previousResponse(response1.id)  // Automatic context
    .execute()
```

#### 5. Advanced Reasoning & Citations (Deep Research)
**AI reasoning steps and source citations:**
```swift
let response = try await provider.response("Research climate impact of EVs")
    .tools([.webSearch, .codeInterpreter])
    .reasoning(true)
    .execute()

// Access AI's reasoning process
for step in response.reasoning {
    print("Step: \(step.summary)")
}

// Access citations and sources  
for annotation in response.annotations {
    print("Source: \(annotation.text)")
}
```

#### 6. Enhanced Streaming (Real-time Multimodal)
**Stream text, images, audio, files in real-time:**
```swift
for try await chunk in provider.response("Create infographic with audio narration")
    .tools([.webSearch, .imageGeneration, .audioGeneration])
    .stream() {
    
    switch chunk.type {
    case .text: print(chunk.text, terminator: "")
    case .imageGenerated: displayStreamingImage(chunk.imageData)
    case .audioGenerated: playStreamingAudio(chunk.audioData)
    case .toolCall: showProgress("Using \(chunk.toolName)")
    }
}
```

### 🤖 **Perfect Agent Foundation**

#### Agent Capabilities Enabled:
- **Conversation Memory**: Built-in context management with `ConversationMessage`
- **Multimodal Agents**: Process images/audio, generate images/audio/files
- **Tool Orchestration**: Seamlessly combine multiple tool types
- **Background Agents**: Long-running agent workflows 
- **Agent Communication**: Structured message passing between agents
- **Streaming Agents**: Real-time interactive agent experiences

#### Agent Development Patterns:
```swift
// Multi-agent collaboration
class ResearchOrchestrator {
    func collaborate(on topic: String) async throws -> String {
        // Research agent gathers data
        let research = try await researchAgent.process([.text(topic)])
        
        // Analysis agent processes findings  
        let analysis = try await analysisAgent.process([
            .text("Research results:"), .text(research),
            .text("Provide detailed analysis")
        ])
        
        // Report agent creates final output with charts
        let report = try await reportAgent.process([
            .text("Research: \(research)"),
            .text("Analysis: \(analysis)"), 
            .text("Create comprehensive report with visualizations")
        ])
        
        return report
    }
}
```

### 🚀 **Responses API Superpowers vs Chat Completions**

| Capability | Chat Completions | Responses API |
|------------|------------------|---------------|
| **State Management** | Manual history | Automatic continuation |
| **Tools** | Function calling only | Built-in + custom + MCP |
| **Background Tasks** | ❌ Not supported | ✅ Native support |
| **Multimodal Output** | ❌ Text only | ✅ Images, audio, files |
| **Reasoning Access** | ❌ Hidden | ✅ Full reasoning steps |
| **Citations** | ❌ Manual | ✅ Automatic annotations |
| **Streaming Events** | Basic deltas | Semantic tool/reasoning events |
| **Agent Building** | Complex setup | Perfect foundation |

### 📋 **Implementation Clarity: What Gets Built**

#### New Files to Create (5 total):
1. **ContentTypes.swift** - Simple input types (ContentPart, ConversationMessage)
2. **ToolTypes.swift** - Mixed tool syntax (BuiltInTool enum + Tool conformance)  
3. **ResponseSession.swift** - Main API class with fluent configuration
4. **ResponseTypes.swift** - Simple output types (Response, ResponseChunk)
5. **OpenAIProvider+Response.swift** - Provider extension with response() methods

#### Conversion Strategy:
- **Simple → Complex**: Convert simple types to existing ResponseBuilder internally (this is deprecated and will be removed in the future)
- **Complex → Simple**: Convert ResponseObject back to simple Response externally  
- **Zero Duplication**: Reuse all existing ResponseObject, ResponseAnnotation, etc.
- **Backward Compatible**: All existing methods continue working

## Proposed Solution: Thin Wrapper Around Excellent Existing Code

### Architecture Overview

**Key Insight**: Don't rebuild - the existing code is excellent. Just add a clean unified entry point that wraps the existing `ResponseBuilder` and leverages all existing structures.

**Approach**: Create a simple wrapper that provides the clean API users want while using all existing excellent code underneath.

### Core Philosophy
1. **Leverage Existing Excellence** - Use existing `ResponseObject`, `ResponseAnnotation`, `ResponseInput`, `ResponseTool`
2. **Thin Wrapper Only** - New API is just a convenience layer over existing `ResponseBuilder`, DO NOT USE THIS! this is deprecated and will be removed in the future.
3. **Zero Duplication** - Reuse existing structures instead of recreating them
4. **Backward Compatible** - All existing methods continue to work
5. **Clean Entry Point** - One method (`response()`) that handles all cases
6. **Preserve Existing Features** - All current capabilities remain exactly as they are

### Refactoring Architecture Diagram

The diagram above ⬆️ illustrates how a thin wrapper transforms the complex API surface into a clean unified approach by leveraging all existing excellent structures.

### New API Design (Thin Wrapper)

#### 1. Single Entry Point with Beautiful Content Types

```swift
// NEW: Clean entry point with simple content types
public func response(_ content: String) -> ResponseSession
public func response(_ content: [ContentPart]) -> ResponseSession
public func response(conversation: [ConversationMessage]) -> ResponseSession

// Simple content types (the beautiful syntax you loved!)
public enum ContentPart {
    case text(String)
    case image(Data)
    case imageURL(String)
    case audio(Data)
    case file(URL)
}

// Example usage
provider.response("Hello")                    // Simple text
provider.response([.text("Compare"), .image(data), .text("vs"), .image(data2)])  // Multimodal
provider.response(conversation: history)      // For agents
```

#### 2. ResponseSession (Simple → Complex Conversion)

```swift
public class ResponseSession {
    private let provider: OpenAIProvider
    private let content: SessionContent
    
    init(provider: OpenAIProvider, content: SessionContent) {
        self.provider = provider
        self.content = content
    }
    
    // Simple configuration methods
    public func tools(_ tools: [any ToolType]) -> ResponseSession {
        content.tools = tools
        return self
    }
    
    public func background(_ enabled: Bool = true) -> ResponseSession {
        content.backgroundEnabled = enabled
        return self
    }
    
    public func reasoning(_ enabled: Bool = true) -> ResponseSession {
        content.reasoningEnabled = enabled
        return self
    }
    
    // Execute by converting simple → complex internally
    public func execute() async throws -> Response {
        // Convert simple types
        let complexRequest = content.toResponseRequest(provider: provider)
        let complexResponse = try await provider.createResponse(request: complexRequest)
        
        // Convert complex response back to simple
        return Response(from: complexResponse)
    }
    
    public func stream() -> AsyncThrowingStream<ResponseChunk, Error> {
        let complexRequest = content.toResponseRequest(provider: provider)
        return provider.createResponseStream(request: complexRequest)
    }
}

// Internal converter that handles the complexity
internal class SessionContent {
    var tools: [any ToolType] = []
    var backgroundEnabled = false
    var reasoningEnabled = false
    
    func toResponseRequest(provider: OpenAIProvider) -> ResponseRequest {
        // Convert simple tools to complex ResponseTool enum
        // Convert simple content to complex ResponseInput
        // Handle all the complexity internally
    }
}
```

#### 3. Simple Content System (The Beautiful Syntax You Loved)

```swift
// Simple text
let response = try await provider.response("Hello, world!")
    .execute()

// Beautiful multimodal content (order-aware!)
let response = try await provider.response([
    .text("Compare these images and generate an improved version:"),
    .image(beforeImage),
    .text("vs"),
    .image(afterImage), 
    .audio(voiceInstructions)
])
.tools([.webSearch, .codeInterpreter, .imageGeneration])
.execute()

// Mixed tool syntax (exactly what you wanted!)
let response = try await provider.response("What's the weather and create a chart?")
    .tools([
        .webSearch,           // Built-in enum
        .codeInterpreter,     // Built-in enum
        WeatherTool(),        // Custom instance
        CustomMCPTool(),      // Custom instance
        SampleTool()          // Custom instance
    ])
    .execute()

// Access results simply
print("Text:", response.text ?? "")
print("Citations:", response.annotations?.count ?? 0)

// Handle multimodal outputs
for content in response.content {
    switch content {
    case .text(let text):
        print("Generated:", text)
    case .image(let data):
        displayImage(data)
    case .audio(let data):
        playAudio(data)
    case .file(let url):
        openFile(url)
    }
}
```

#### 4. Mixed Tool Configuration (Your Preferred Syntax!)

```swift
// Beautiful mixed tool syntax - exactly what you wanted!
public protocol ToolType {}

// Built-in tools as simple enum cases
public enum BuiltInTool: ToolType {
    case webSearch
    case codeInterpreter  
    case imageGeneration
    case fileSearch(vectorStoreId: String)
}

// All custom tools automatically conform
extension Tool: ToolType {}

// Usage - perfect mix of enums and instances
let response = try await provider.response("What's the weather and create a chart?")
    .tools([
        .webSearch,           // ✅ Built-in enum
        .codeInterpreter,     // ✅ Built-in enum
        .imageGeneration,     // ✅ Built-in enum
        WeatherTool(),        // ✅ Custom instance
        CustomMCPTool(),      // ✅ Custom instance
        SampleTool()          // ✅ Custom instance
    ])
    .execute()

// Internally converts to existing ResponseTool enum when calling backend
```

#### 5. Simple Response Object 

```swift
// Clean response object that converts from complex ResponseObject
public struct Response {
    public let text: String?                     // Main response text
    public let content: [ContentPart]            // Multimodal outputs (images, audio, files)
    public let annotations: [Annotation]?        // Citations for research
    public let id: String                        // Response ID
    public let status: Status                    // Simple status
    public let usage: Usage?                     // Token usage
    
    // Background/research features
    public let isBackground: Bool                // Was this a background task
    public let reasoning: String?                // AI reasoning summary
    
    // Full access if needed
    public let raw: ResponseObject               // Original complex response
}

// Simple types
public struct Annotation {
    public let text: String
    public let startIndex: Int
    public let endIndex: Int
}

public enum Status {
    case completed
    case processing  
    case failed
}

// Usage
let response = try await provider.response("Research topic")
    .tools([.webSearch, WeatherTool()])
    .execute()

print("Text:", response.text ?? "")
print("Citations:", response.annotations?.count ?? 0)
print("Generated content:", response.content.count)
```

#### 6. Multimodal Outputs (Already Supported via ResponseOutputContent)

```swift
// Existing ResponseObject already handles multimodal outputs perfectly
let response = try await provider.response("Create a chart and summary")
    .tools([.codeInterpreter, .imageGeneration(partialImages: 3)])
    .execute()

// Access existing multimodal outputs 
print("Text:", response.outputText ?? "")

// Parse existing ResponseOutputContent structure
if let contentParts = response.contentParts {
    for content in contentParts {
        switch content {
        case .outputText(let textOutput):
            print("Generated text:", textOutput.text)
            // Citations already available in textOutput.annotations
            
        case .outputImage(let imageOutput):
            if let imageUrl = imageOutput.imageUrl {
                print("Generated image:", imageUrl)
            }
            if let fileId = imageOutput.fileId {
                print("Generated image file:", fileId)
            }
        }
    }
}

// Tool outputs are in existing response.output structure
for outputItem in response.output {
    switch outputItem {
    case .codeInterpreterCall(let codeCall):
        print("Code executed:", codeCall.code ?? "")
        print("Result:", codeCall.result ?? "")
        
    case .imageGenerationCall(let imageCall):
        print("Image prompt:", imageCall.prompt ?? "")
        print("Image result:", imageCall.result ?? "")
        
    default:
        break
    }
}
```

#### 7. Background Processing

```swift
let response = try await provider.response("Analyze massive dataset")
    .tools([.codeInterpreter])
    .background(true) 
    .execute()

// Existing ResponseStatus already handles background states perfectly
if response.status.isProcessing {  // ✅ Existing isProcessing property
    print("Task started in background. ID: \(response.id)")
    
    // Poll using existing retrieveResponse method (if implemented)
    while response.status.isProcessing {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        // Note: provider.retrieveResponse() may need to be added if not exists
        print("Status: \(response.status)")
        
        if response.status.isFinal {  // ✅ Existing isFinal property
            print("Final result:", response.outputText ?? "")
            break
        }
    }
}
```

#### 8. Streaming (Uses Existing ResponseChunk & ResponseStreamEvent)

```swift
// Existing streaming works perfectly - just expose it through wrapper
for try await chunk in provider.response("Tell me a story")
    .tools([.webSearchPreview])
    .stream() {  // ✅ Uses existing createResponseStream()
    
    // Existing ResponseChunk already has all needed fields
    if let text = chunk.delta?.outputText {
        print(text, terminator: "")
    }
    
    // Existing status handling
    if chunk.status?.isFinal == true {
        print("\nCompleted!")
        if let usage = chunk.usage {
            print("Tokens used:", usage.totalTokens)
        }
    }
    
    // Error handling with existing structure
    if let error = chunk.error {
        print("Error:", error.message ?? "Unknown error")
    }
}

// For research tasks with existing sophisticated streaming
for try await chunk in provider.response("Research AI trends")
    .tools([.webSearchPreview, .codeInterpreter])
    .reasoning(ResponseReasoning(effort: "detailed"))
    .stream() {
    
    // The existing ResponseStreamEvent already handles all these cases!
    // Just need to expose them through ResponseChunk conversion
    print("Chunk received:", chunk.delta?.outputText ?? "")
}
// Streaming with multimodal output support
for try await chunk in provider.response(content: complexContent)
    .tools([.webSearch, .codeInterpreter, .imageGeneration])
    .stream() {
    
    switch chunk.type {
    case .text:
        print(chunk.text ?? "", terminator: "")
    case .toolCall:
        print("\n[Using \(chunk.toolCall?.name ?? "tool")...]")
    case .toolResult:
        print("[Completed]")
    case .imageGenerated:
        if let imageData = chunk.imageData {
            displayStreamingImage(imageData)
        }
    case .audioGenerated:
        if let audioData = chunk.audioData {
            playStreamingAudio(audioData)
        }
    case .fileCreated:
        if let fileURL = chunk.fileURL {
            handleGeneratedFile(fileURL)
        }
    case .complete:
        print("\n[Response complete]")
    }
}

#### 8. Enhanced Content & Response System

```swift
// Flexible content input that preserves order and supports all modalities
public enum ContentInput {
    case text(String)                    // Simple text
    case parts([ContentPart])            // Complex multimodal with order
    case conversation([ConversationMessage])  // Full conversation history (for agents)
}

public enum ContentPart {
    case text(String)
    case image(Data, detail: ImageDetail = .auto)
    case imageURL(URL, detail: ImageDetail = .auto) 
    case audio(Data, format: AudioFormat)
    case video(Data, format: VideoFormat)
    case file(URL, type: FileType)
}

// Agent-friendly conversation format
public struct ConversationMessage {
    // Wraps universal AIInputMessage for Response API context
    private let universalMessage: AIInputMessage
    
    public init(_ universalMessage: AIInputMessage) {
        self.universalMessage = universalMessage
    }
    
    public var role: AIMessageRole { universalMessage.role }
    public var content: [AIContentPart] { universalMessage.content }
    public var toolCalls: [AIToolCall]? { universalMessage.toolCalls }
    
    func toResponseMessage() -> ResponseMessage {
        return universalMessage.toResponseMessage()
    }
}
```

#### 9. Enhanced Response with Multimodal Outputs & Annotations

```swift
// Response structure that handles multimodal outputs and citations
public struct Response {
    public let text: String?                      // Most common use case
    public let content: [ContentPart]             // ALL content including generated images/audio/files
    public let annotations: [ResponseAnnotation]  // Citations and references (existing structure)
    public let id: String
    public let model: String
    public let status: ResponseStatus     // processing, completed, failed
    public let tokens: TokenUsage         
    public let toolCalls: [ToolCall]      // Tools that were executed
    public let conversationMessage: ConversationMessage  // Ready for agent history
    
    // Responses API superpowers
    public let isBackground: Bool         // Whether this is a background task
    public let reasoning: [ReasoningStep]? // Model reasoning steps (Deep Research)
    public let previousResponseId: String? // For conversation continuation
    
    // Advanced access when needed
    public let raw: ResponseObject        // Full response for edge cases
}

// Use existing ResponseAnnotation (already implemented)
public typealias Annotation = ResponseAnnotation

// Reasoning steps for research capabilities
public struct ReasoningStep {
    public let type: ReasoningType       // plan, search, synthesize, etc.
    public let summary: String           // Step summary
    public let details: String?          // Detailed reasoning
}

## Implementation Plan

### What Needs to Be Built

This refactoring requires building **4 main components**:

#### 1. Content Types (Simple Input)
```swift
// File: Sources/AISDK/LLMs/OpenAI/ResponseAPI/ContentTypes.swift
public enum ContentPart {
    case text(String)
    case image(Data)
    case imageURL(String)
    case audio(Data)  
    case file(URL)
}

public struct ConversationMessage {
    public let role: Role
    public let content: [ContentPart]
}

public enum Role {
    case user, assistant, system
}
```

#### 2. Tool Types (Mixed Syntax)
```swift
// File: Sources/AISDK/LLMs/OpenAI/ResponseAPI/ToolTypes.swift
public protocol ToolType {}

public enum BuiltInTool: ToolType {
    case webSearch
    case codeInterpreter
    case imageGeneration
    case fileSearch(vectorStoreId: String)
}

extension Tool: ToolType {}  // All existing tools work
```

#### 3. ResponseSession (Main API)
```swift
// File: Sources/AISDK/LLMs/OpenAI/ResponseAPI/ResponseSession.swift
public class ResponseSession {
    private let provider: OpenAIProvider
    private let content: SessionContent
    
    public func tools(_ tools: [any ToolType]) -> ResponseSession
    public func background(_ enabled: Bool = true) -> ResponseSession
    public func reasoning(_ enabled: Bool = true) -> ResponseSession
    
    public func execute() async throws -> Response
    public func stream() -> AsyncThrowingStream<ResponseChunk, Error>
}
```

#### 4. Response Types (Simple Output)
```swift
// File: Sources/AISDK/LLMs/OpenAI/ResponseAPI/ResponseTypes.swift
public struct Response {
    public let text: String?
    public let content: [ContentPart]  // Multimodal outputs
    public let annotations: [Annotation]?
    public let status: Status
    // ... other fields
    
    init(from complexResponse: ResponseObject) {
        // Convert complex → simple
    }
}
```

#### 5. Provider Extension
```swift
// File: Sources/AISDK/LLMs/OpenAI/OpenAIProvider+Response.swift
extension OpenAIProvider {
    public func response(_ content: String) -> ResponseSession
    public func response(_ content: [ContentPart]) -> ResponseSession  
    public func response(conversation: [ConversationMessage]) -> ResponseSession
}
```

### Key Implementation Details

#### Content Conversion
```swift
// Convert simple ContentPart → complex ResponseInput
extension SessionContent {
    func toResponseRequest() -> ResponseRequest {
        let complexContent = contentParts.map { part in
            switch part {
            case .text(let text):
                return ResponseContentItem.inputText(ResponseInputText(text: text))
            case .image(let data):
                return ResponseContentItem.inputImage(ResponseInputImage(data: data))
            case .imageURL(let url):
                return ResponseContentItem.inputImage(ResponseInputImage(imageUrl: url))
            // ... other conversions
            }
        }
        
        let message = ResponseMessage(role: "user", content: complexContent)
        let input = ResponseInput.items([message])
        return ResponseRequest(model: defaultModel, input: input)
    }
}
```

#### Tool Conversion
```swift
// Convert simple ToolType → complex ResponseTool
extension BuiltInTool {
    func toResponseTool() -> ResponseTool {
        switch self {
        case .webSearch:
            return .webSearchPreview
        case .codeInterpreter:
            return .codeInterpreter
        case .imageGeneration:
            return .imageGeneration(partialImages: 3)
        case .fileSearch(let vectorId):
            return .fileSearch(vectorStoreId: vectorId)
        }
    }
}

extension Tool {
    func toResponseTool() -> ResponseTool {
        return .function(self.toFunction())
    }
}
```

#### Response Conversion
```swift
// Convert complex ResponseObject → simple Response
extension Response {
    init(from complexResponse: ResponseObject) {
        self.text = complexResponse.outputText
        self.id = complexResponse.id
        self.status = Status(from: complexResponse.status)
        
        // Extract multimodal content
        var contentParts: [ContentPart] = []
        for output in complexResponse.output {
            if case .message(let message) = output {
                for content in message.content {
                    switch content {
                    case .outputText(let textOutput):
                        if !textOutput.text.isEmpty {
                            contentParts.append(.text(textOutput.text))
                        }
                    case .outputImage(let imageOutput):
                        if let imageData = imageOutput.data {
                            contentParts.append(.image(imageData))
                        }
                    }
                }
            }
        }
        self.content = contentParts
        
        // Extract annotations
        self.annotations = extractAnnotations(from: complexResponse)
        
        // Keep raw for advanced usage
        self.raw = complexResponse
    }
}
```

### Detailed Implementation Steps

#### Week 1: Foundation Types
**File: `Sources/AISDK/LLMs/OpenAI/ResponseAPI/ResponseConversions.swift`**
```swift
// Uses Universal Message System types (AIInputMessage, AIContentPart)
// See: docs/tasks/universal-message-system-plan.md

// Conversion from universal types to Response API
extension AIInputMessage {
    func toResponseMessage() -> ResponseMessage {
        let responseContent = content.map { $0.toResponseContentItem() }
        return ResponseMessage(role: role.toResponseRole(), content: responseContent)
    }
}

extension AIContentPart {
    func toResponseContentItem() -> ResponseContentItem {
        switch self {
        case .text(let text):
            return .inputText(ResponseInputText(text: text))
        case .image(let imageContent):
            return .inputImage(ResponseInputImage(
                data: imageContent.data,
                imageUrl: imageContent.url?.absoluteString,
                detail: imageContent.detail.toResponseDetail()
            ))
        case .audio(let audioContent):
            return .inputAudio(ResponseInputAudio(
                data: audioContent.data,
                url: audioContent.url?.absoluteString,
                format: audioContent.format.toResponseFormat()
            ))
        case .file(let fileContent):
            return .inputFile(ResponseInputFile(
                data: fileContent.data,
                url: fileContent.url?.absoluteString,
                filename: fileContent.filename,
                type: fileContent.type.toResponseFileType()
            ))
        // ... handle other content types
        }
    }
}

// Conversation wrapper for agent integration using universal types
public struct ConversationMessage {
    public let role: MessageRole
    public let content: [ContentPart]
    public let toolCalls: [ToolCall]?
    public let toolResults: [ToolResult]?
    
    public init(role: MessageRole, content: [ContentPart]) { ... }
}

public enum MessageRole: String {
    case user, assistant, system
}

// Convert to existing ResponseInput types
extension Array where Element == ContentPart {
    func toResponseInput() -> ResponseInput { ... }
}
```

#### Week 2: Tool System
**File: `Sources/AISDK/LLMs/OpenAI/ResponseAPI/ToolTypes.swift`**
```swift
// Protocol for all tool types
public protocol ToolType {}

// Built-in tools as enum (including MCP servers)
public enum BuiltInTool: ToolType {
    case webSearch
    case codeInterpreter  
    case imageGeneration(partialImages: Int = 3)
    case fileSearch(vectorStoreId: String)
    case mcp(serverLabel: String, serverUrl: String, requireApproval: String? = nil)
}

// Make existing Tool protocol conform
extension Tool: ToolType {}

// Conversion to existing ResponseTool
extension BuiltInTool {
    func toResponseTool() -> ResponseTool {
        switch self {
        case .webSearch:
            return .webSearchPreview
        case .codeInterpreter:
            return .codeInterpreter
        case .imageGeneration(let partialImages):
            return .imageGeneration(partialImages: partialImages)
        case .fileSearch(let vectorStoreId):
            return .fileSearch(vectorStoreId: vectorStoreId)
        case .mcp(let serverLabel, let serverUrl, let requireApproval):
            return .mcp(serverLabel: serverLabel, serverUrl: serverUrl, requireApproval: requireApproval)
        }
    }
}

extension Tool {
    func toResponseTool() -> ResponseTool { 
        return .function(self.toFunction())
    }
}

// Special handling for MCP tools (uses existing ResponseTool.mcp case)
extension Tool {
    func toResponseTool() -> ResponseTool {
        // Check if this is an MCP tool
        if let mcpTool = self as? MCPTool {
            return .mcp(
                serverLabel: mcpTool.serverLabel,
                serverUrl: mcpTool.serverUrl,
                requireApproval: mcpTool.requireApproval,
                headers: mcpTool.headers
            )
        }
        
        // Regular custom tool
        return .function(self.toFunction())
    }
}

// MCP tool protocol (matches existing ResponseTool.mcp structure)
protocol MCPTool: Tool {
    var serverLabel: String { get }
    var serverUrl: String { get }
    var requireApproval: String? { get }
    var headers: [String: String]? { get }
}

// Concrete MCP tool implementations
extension MCPSlackTool: MCPTool {
    var serverLabel: String { "slack-mcp" }
    var requireApproval: String? { nil }
    var headers: [String: String]? { ["Authorization": "Bearer \(authToken)"] }
}

extension MCPNotionTool: MCPTool {
    var serverLabel: String { "notion-mcp" }
    var requireApproval: String? { nil }
    var headers: [String: String]? { ["Authorization": "Bearer \(authToken)"] }
}

extension MCPSalesforceTool: MCPTool {
    var serverLabel: String { "salesforce-mcp" }
    var requireApproval: String? { "user" } // Require user approval for data access
    var headers: [String: String]? { ["Authorization": "Bearer \(authToken)"] }
}
```

#### Week 3: Main API Class
**File: `Sources/AISDK/LLMs/OpenAI/ResponseAPI/ResponseSession.swift`**
```swift
public class ResponseSession {
    private let provider: OpenAIProvider
    private let content: SessionContent
    
    public init(provider: OpenAIProvider, content: ContentInput) { ... }
    
    // Configuration methods (fluent interface)
    public func tools(_ tools: [any ToolType]) -> ResponseSession { ... }
    public func background(_ enabled: Bool = true) -> ResponseSession { ... }
    public func reasoning(_ enabled: Bool = true) -> ResponseSession { ... }
    public func instructions(_ text: String) -> ResponseSession { ... }
    public func model(_ model: String) -> ResponseSession { ... }
    public func previousResponse(_ id: String) -> ResponseSession { ... }
    
    // Execution methods
    public func execute() async throws -> Response {
        let complexRequest = content.toResponseRequest(provider: provider)
        let complexResponse = try await provider.createResponse(request: complexRequest)
        return Response(from: complexResponse)
    }
    
    public func stream() -> AsyncThrowingStream<ResponseChunk, Error> {
        let complexRequest = content.toResponseRequest(provider: provider)
        return provider.createResponseStream(request: complexRequest)
            .map { ResponseChunk(from: $0) }
    }
}

// Internal conversion logic
internal class SessionContent {
    var tools: [any ToolType] = []
    var backgroundEnabled = false
    var reasoningEnabled = false
    var instructions: String?
    var model: String = "gpt-4o"
    
    func toResponseRequest(provider: OpenAIProvider) -> ResponseRequest { ... }
}
```

#### Week 4: Response Types  
**File: `Sources/AISDK/LLMs/OpenAI/ResponseAPI/ResponseTypes.swift`**
```swift
// Simple response structure
public struct Response {
    public let id: String
    public let text: String?                      // Most common access
    public let content: [ContentPart]             // Multimodal outputs
    public let annotations: [ResponseAnnotation]  // Citations (existing type)
    public let model: String
    public let status: ResponseStatus            // Use existing status
    public let usage: ResponseUsage?             // Use existing usage
    public let reasoning: [ReasoningStep]?       // AI reasoning steps
    public let toolCalls: [ToolCall]            // Tools executed
    public let conversationMessage: ConversationMessage  // For agent history
    
    // Advanced access
    public let raw: ResponseObject              // Full complex response
    
    // Conversion from complex ResponseObject
    public init(from response: ResponseObject) {
        self.id = response.id
        self.text = response.outputText
        self.status = response.status
        self.usage = response.usage
        self.model = response.model
        self.raw = response
        
        // Extract multimodal content
        self.content = extractContentParts(from: response.output)
        
        // Extract annotations (use existing ResponseAnnotation)
        self.annotations = extractAnnotations(from: response)
        
        // Convert to ConversationMessage format
        self.conversationMessage = ConversationMessage(
            role: .assistant,
            content: self.content
        )
        
        // Extract reasoning if available
        self.reasoning = extractReasoningSteps(from: response)
        
        // Extract tool calls
        self.toolCalls = extractToolCalls(from: response)
    }
}

// Helper extraction functions
private func extractContentParts(from output: [ResponseOutputItem]) -> [ContentPart] { ... }
private func extractAnnotations(from response: ResponseObject) -> [ResponseAnnotation] { ... }
private func extractReasoningSteps(from response: ResponseObject) -> [ReasoningStep]? { ... }
```

#### Week 5: Provider Integration
**File: `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+Response.swift`**
```swift
extension OpenAIProvider {
    // Main entry points
    public func response(_ content: String) -> ResponseSession {
        return ResponseSession(provider: self, content: .text(content))
    }
    
    public func response(_ content: [ContentPart]) -> ResponseSession {
        return ResponseSession(provider: self, content: .parts(content))
    }
    
    public func response(conversation: [ConversationMessage]) -> ResponseSession {
        return ResponseSession(provider: self, content: .conversation(conversation))
    }
}

// Content input types
public enum ContentInput {
    case text(String)
    case parts([ContentPart])
    case conversation([ConversationMessage])
}
```

#### Week 6: Testing & Documentation
**Test Coverage:**
- Simple text responses
- Multimodal input/output
- Mixed tool syntax
- Background processing
- Streaming responses
- Conversion accuracy (simple ↔ complex)
- Agent integration patterns

**Documentation Updates:**
- New API usage guide
- Migration guide from old API
- Agent development patterns
- Capability comparison table

### Testing Strategy

```swift
// Test simple API works
func testSimpleText() async throws {
    let response = try await provider.response("Hello")
        .execute()
    XCTAssertNotNil(response.text)
}

// Test multimodal content
func testMultimodal() async throws {
    let response = try await provider.response([
        .text("Compare these"),
        .image(testImage),
        .text("vs"),
        .image(testImage2)
    ])
    .execute()
    XCTAssertNotNil(response.text)
}

// Test mixed tools
func testMixedTools() async throws {
    let response = try await provider.response("Weather and chart")
        .tools([.webSearch, .codeInterpreter, WeatherTool()])
        .execute()
    XCTAssertNotNil(response.text)
}
```

## Summary: Thin Wrapper Benefits

### ✅ **What This Achieves**

1. **Beautiful Simplicity**: The clean content syntax you loved (`.text`, `.image`, `.audio`)
2. **Perfect Tool Syntax**: Mixed built-in enums and custom instances exactly as requested 
3. **Order-Aware Multimodal**: Complex sequences preserved naturally
4. **Responses API Superpowers**: Background processing, citations, multimodal outputs
5. **Agent Foundation**: Perfect building blocks for sophisticated agents

### ✅ **Developer Experience Transform**

**Before** (7+ confusing entry points):
```swift
// Which method do I use? What's the difference?
provider.createTextResponse(...)
provider.createResponseWithWebSearch(...)
provider.createResponseWithCodeInterpreter(...)

// Complex multimodal setup
let items: [ResponseInputItem] = [
    .message(ResponseMessage(role: "user", content: [
        .inputText(ResponseInputText(text: "Compare")),
        .inputImage(ResponseInputImage(imageUrl: "url1")),
        .inputText(ResponseInputText(text: "vs")),
        .inputImage(ResponseInputImage(imageUrl: "url2"))
    ]))
]
```

**After** (Beautiful simplicity):
```swift
// One entry point, crystal clear
provider.response("Hello").execute()

// Beautiful multimodal content
provider.response([
    .text("Compare these images"),
    .image(beforeImage),
    .text("vs"), 
    .image(afterImage)
])
.tools([.webSearch, .codeInterpreter, WeatherTool()])
.execute()
```

### ✅ **Key Insight**

This provides the simple, beautiful API you want while leveraging all the excellent existing backend code. The conversion layer handles the complexity so developers get simplicity with full power.

### Deep Research API Integration (Uses Existing Structures)

The wrapper seamlessly exposes existing Deep Research capabilities:

```swift
// Complex research
let response = try await provider.response("Research semaglutide economic impact")
    .tools([.webSearchPreview, .codeInterpreter])         // ✅ Existing ResponseTool
    .reasoning(ResponseReasoning(effort: "detailed"))     // ✅ Existing ResponseReasoning
    .background(true)                                     // ✅ Existing background support
    .instructions("""
        You are a professional researcher preparing a structured report.
        Include inline citations and prioritize reliable sources.
        """)                                              // ✅ Existing instructions
    .execute()

// Rich response using existing ResponseObject
print("Research Report:", response.outputText ?? "")     // ✅ Existing outputText

// Citations using existing ResponseAnnotation (via computed property)
if let annotations = response.annotations {               // ✅ New computed property
    for annotation in annotations {
        print("Citation: \(annotation.text ?? "")")      // ✅ Existing ResponseAnnotation
        print("Span: \(annotation.startIndex ?? 0)-\(annotation.endIndex ?? 0)")
    }
}

// Reasoning using existing ResponseReasoning
if let reasoning = response.reasoning {                   // ✅ Existing field
    print("Reasoning Summary:", reasoning.summary ?? "")
    print("Reasoning Effort:", reasoning.effort ?? "")
}

// MCP tool integration using existing ResponseTool.mcp
let mcpResponse = try await provider.response("Search internal studies")
    .tools([
        .webSearchPreview,                                // ✅ Existing built-in
        .mcp(serverLabel: "internal", 
             serverUrl: "https://internal.com/mcp")       // ✅ Existing MCP support
    ])
    .execute()
```

**Key Point**: All Deep Research capabilities already exist in the current implementation. The wrapper just makes them easier to access.
    .execute()

// Streaming research with real-time updates
for try await chunk in provider.response(content: "Research AI trends in 2024")
    .tools([.webSearch, .codeInterpreter])
    .reasoning(.detailed)
    .stream() {
    
    switch chunk.type {
    case .reasoningStep:
        print("🧠 Reasoning: \(chunk.reasoningStep?.summary ?? "")")
    case .webSearch:
        print("🔍 Searching: \(chunk.webSearchQuery ?? "")")
    case .codeExecution:
        print("💻 Running code...")
    case .textGeneration:
        print(chunk.text ?? "", terminator: "")
    case .annotationAdded:
        print("\n📚 Citation added: \(chunk.annotation?.text ?? "")")
    }
}
```

### Migration Strategy

#### Phase 1: Implementation (Non-Breaking)
1. **Create new unified API** alongside existing API
2. **Implement ResponseSession** with clean internal architecture
3. **Add comprehensive tests** for new API
4. **Update documentation** with new patterns

#### Phase 2: Soft Deprecation
1. **Mark old methods as deprecated** with migration guidance
2. **Update examples** to use new API
3. **Provide automatic migration** suggestions in IDE
4. **Add migration guide** to documentation

#### Phase 3: Cleanup (Breaking)
1. **Remove deprecated methods** (major version bump)
2. **Clean up internal structures** no longer needed
3. **Simplify test suite** to focus on new API
4. **Update package dependencies** if needed

## Implementation Details

### File Structure Changes

```
Sources/AISDK/LLMs/OpenAI/
├── OpenAIProvider.swift           # Add new response() method
├── ResponseAPI/                   # New clean API
│   ├── ResponseSession.swift      # Main session class
│   ├── Response.swift            # Simplified response
│   ├── ResponseChunk.swift       # Simplified streaming
│   └── ToolResults.swift         # Simplified tool results
└── APIModels/                    # Keep existing for compatibility
    └── Responses/ (unchanged until Phase 3)
```

### Internal Architecture

```swift
// Clean internal implementation
internal class ResponseExecutor {
    private let provider: OpenAIProvider
    private let request: InternalRequest
    
    func execute() async throws -> Response {
        // Convert clean API to existing complex API internally
        let legacyRequest = request.toLegacyRequest()
        let legacyResponse = try await provider.createResponse(request: legacyRequest)
        return Response(from: legacyResponse) // Convert back to clean API
    }
}
```

### Backwards Compatibility

```swift
// Keep existing methods during migration
@available(*, deprecated, message: "Use response(_:).execute() instead")
public func createTextResponse(model: String, text: String) async throws -> ResponseObject {
    // Internally delegate to new API
    let newResponse = try await response(text).model(model).execute()
    return newResponse.raw
}
```

## Key Improvements Addressing User Feedback

### 1. Order-Aware Multimodal Input AND Output
```swift
// ✅ NEW: Natural sequence preservation + multimodal outputs
let response = try await provider.response(content: [
    .text("Create an infographic comparing:"),
    .image(chart1),
    .text("vs"),
    .image(chart2),
    .audio(voiceInstructions)
]).tools([.webSearch, .codeInterpreter, .imageGeneration])
.execute()

// Access generated content
for content in response.content {
    switch content {
    case .image(let data): displayGeneratedImage(data)
    case .audio(let data): playGeneratedAudio(data)
    case .file(let url): openGeneratedFile(url)
    default: break
    }
}

// ❌ OLD: Complex nested structures, no multimodal outputs
```

### 2. Mixed Tool Syntax (Exactly What You Wanted)
```swift
// ✅ NEW: Perfect mix of built-in and custom tools
.tools([.webSearch, .codeInterpreter, WeatherTool(), CustomMCPTool(), SampleTool()])

// ❌ OLD: Verbose method chaining or complex enums
.withWebSearch().withCodeInterpreter().tool(.function(customFunction))
```

### 3. Responses API Superpowers Unlocked
```swift
// ✅ NEW: Background processing for long tasks
let response = try await provider.response(content: "Analyze massive dataset")
    .tools([.codeInterpreter, DataAnalysisTool()])
    .background(true)
    .execute()

// ✅ NEW: Stateful conversations with continuation
let response = try await provider.response(content: "Continue our analysis")
    .previousResponse(lastResponseId)
    .execute()

// ✅ NEW: Reasoning steps and metadata
if let reasoning = response.reasoning {
    print("Model reasoning:", reasoning)
}

// ❌ OLD: None of these capabilities available
```

### 4. Tool Definition Compatibility
```swift
// ✅ NEW: Same Tool definition, multiple API support
struct WeatherTool: Tool {
    @Parameter(description: "City name")
    var city: String = ""
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        // Implementation
    }
}

// Generate schema for different APIs
WeatherTool.jsonSchema(for: .responsesAPI)      // For responses API
WeatherTool.jsonSchema(for: .chatCompletions)   // For chat completions
WeatherTool.jsonSchema(for: .anthropic)         // For Claude

// ❌ OLD: Different tool formats for different APIs
```

### 5. Agent Foundation: Perfect Building Blocks for AI Agents

**What Makes This Perfect for Agents:**

1. **Conversation State Management**: Built-in conversation continuation with `ConversationMessage` type
2. **Multimodal Agent Interactions**: Agents can process AND generate images, audio, files
3. **Tool Orchestration**: Mix built-in tools (.webSearch) with custom tools (WeatherTool()) seamlessly
4. **Background Agent Tasks**: Long-running agent workflows that persist across sessions
5. **Agent-to-Agent Communication**: Structured message passing between multiple agents

```swift
// ✅ PERFECT AGENT FOUNDATION: Everything agents need in one API
class AdvancedAgent {
    private var conversation: [ConversationMessage] = []
    
    // 1. Multimodal conversation memory
    func remember(_ input: [ContentPart]) async throws {
        conversation.append(ConversationMessage(role: .user, content: input))
    }
    
    // 2. Background task processing 
    func processLongTask(_ description: String) async throws -> String {
        let response = try await provider.response(.conversation(conversation))
            .tools([.webSearch, .codeInterpreter, DataAnalysisTool()])
            .background(true)  // Key capability for agents!
            .execute()
        
        conversation.append(response.conversationMessage)
        return response.text ?? ""
    }
    
    // 3. Multimodal output generation
    func createVisualResponse(_ prompt: String) async throws -> AgentOutput {
        let response = try await provider.response(.conversation(conversation))
            .tools([.webSearch, .imageGeneration, ChartTool()])
            .execute()
        
        return AgentOutput(
            text: response.text,
            images: response.content.compactMap { if case .image(let data) = $0 { return data } else { return nil }},
            files: response.content.compactMap { if case .file(let url) = $0 { return url } else { return nil }}
        )
    }
    
    // 4. Tool orchestration with mixed syntax
    func useToolsIntelligently(_ task: String) async throws -> String {
        let response = try await provider.response(task)
            .tools([
                .webSearch,          // Built-in for current info
                .codeInterpreter,    // Built-in for calculations
                WeatherTool(),       // Custom for weather
                DatabaseTool(),      // Custom for data access
                MCPFileTool()        // MCP for file operations
            ])
            .execute()
        
        conversation.append(response.conversationMessage)
        return response.text ?? ""
    }
    
    // 5. Streaming agent interactions
    func streamResponse(_ input: String) -> AsyncThrowingStream<AgentEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                for try await chunk in provider.response(input).tools(agentTools).stream() {
                    switch chunk.type {
                    case .text: continuation.yield(.textGenerated(chunk.text ?? ""))
                    case .toolCall: continuation.yield(.toolStarted(chunk.toolCall?.name ?? ""))
                    case .imageGenerated: continuation.yield(.imageCreated(chunk.imageData))
                    case .complete: continuation.finish()
                    default: break
                    }
                }
            }
        }
    }
}

struct AgentOutput {
    let text: String?
    let images: [Data]
    let files: [URL]
}

enum AgentEvent {
    case textGenerated(String)
    case toolStarted(String)
    case imageCreated(Data?)
}

// ❌ OLD: Agents limited to text input/output, no state management, complex tool integration
```

**Why This Is Revolutionary for Agents:**

- **Stateful Conversations**: Agents naturally maintain context across interactions
- **Multimodal Capabilities**: Agents can see images, generate images, handle audio/files
- **Background Processing**: Agents can handle long-running tasks that persist beyond HTTP timeouts
- **Tool Ecosystem**: Seamless integration of built-in tools + custom tools + MCP tools
- **Agent Composition**: Multiple agents can easily communicate using `ConversationMessage` format

## Benefits of This Refactoring

### 1. Dramatically Simplified Learning Curve
- **Single entry point** (`response(content:)`) eliminates choice paralysis
- **Content-first design** matches how developers think about multimodal AI
- **Mixed tool syntax** feels natural and intuitive
- **Consistent patterns** from simple text to complex agents

### 2. Unlocks Responses API Superpowers
- **Multimodal outputs**: AI can generate images, audio, files - not just consume them
- **Background processing**: Handle long-running tasks that exceed normal timeouts
- **Stateful conversations**: Automatic conversation continuation and context management
- **Enhanced streaming**: Real-time multimodal content delivery
- **Advanced reasoning**: Access to model reasoning steps and confidence

### 3. Perfect Agent Foundation
- **Conversation state management** built-in via `ConversationMessage`
- **Multimodal agent interactions** with preserved order and context
- **Tool orchestration** with mixed built-in and custom tools
- **Background agent tasks** for complex, long-running workflows
- **Agent-to-agent communication** patterns enabled

### 4. Developer Experience Excellence
- **Mixed tool syntax**: `[.webSearch, WeatherTool(), MCPTool()]` - exactly what was requested
- **Order-aware multimodal**: Complex sequences preserved naturally
- **Same Tool definition**: Works across all APIs (responses, chat completions, anthropic)
- **Unified streaming/sync**: Same API shape for both execution modes
- **Rich output handling**: Easy access to generated images, audio, files

### 5. Future-Proof Architecture
- **Content-first approach** scales to any new modality (video, 3D, AR, etc.)
- **Tool system** accommodates built-in, custom, and MCP tools seamlessly
- **Agent-ready structure** supports sophisticated agentic patterns
- **API compatibility layer** allows same tools across different LLM providers
- **Responses API evolution**: Ready for new OpenAI features as they launch

### 6. Massive Simplification
- **90% reduction** in API surface area (from 20+ methods to 1 + configuration)
- **Single pattern** works from simple text to complex multimodal agents
- **No more builder complexity** - fluent configuration that makes sense
- **Eliminated confusion** about which method to use for which scenario

## Agentic Capabilities & Advanced Patterns

This design specifically enables sophisticated agent patterns that are difficult or impossible with the current API:

### 1. Multi-Turn Reasoning Agents
```swift
class ReasoningAgent {
    private let provider: OpenAIProvider
    private var reasoning: [ConversationMessage] = []
    
    func reason(about problem: String) async throws -> String {
        // Multi-step reasoning with tool use
        reasoning.append(ConversationMessage(role: .user, content: [.text(problem)]))
        
        for step in 1...5 {  // Max reasoning steps
            let response = try await provider.response(content: .conversation(reasoning))
                .tools([.webSearch, .codeInterpreter, .custom(ReasoningTool())])
                .instructions("Think step by step. Use tools when you need information.")
                .execute()
            
            reasoning.append(response.conversationMessage)
            
            // Check if reasoning is complete
            if response.text?.contains("CONCLUSION:") == true {
                break
            }
        }
        
        return reasoning.last?.content.first?.text ?? ""
    }
}
```

### 2. Multimodal Memory Agents
```swift
class MemoryAgent {
    private var memory: [ConversationMessage] = []
    private let provider: OpenAIProvider
    
    func processMemory(images: [Data], description: String) async throws {
        let memoryContent: [ContentPart] = [
            .text("Remember this: \(description)")
        ] + images.map { .image($0) }
        
        memory.append(ConversationMessage(role: .user, content: memoryContent))
        
        let response = try await provider.response(content: .conversation(memory))
            .tools([.custom(MemoryStorageTool())])
            .execute()
            
        memory.append(response.conversationMessage)
    }
    
    func recall(query: String) async throws -> String {
        let fullContext = memory + [ConversationMessage(role: .user, content: [.text("Recall: \(query)")])]
        
        let response = try await provider.response(content: .conversation(fullContext))
            .tools([.custom(MemoryRetrievalTool())])
            .execute()
            
        return response.text ?? ""
    }
}
```

### 3. Tool-Orchestrating Agents
```swift
class WorkflowAgent {
    private let provider: OpenAIProvider
    private let availableTools: [ResponseTool]
    
    func executeWorkflow(_ description: String) async throws -> [WorkflowStep] {
        var steps: [WorkflowStep] = []
        var conversation: [ConversationMessage] = [
            ConversationMessage(role: .user, content: [.text(description)])
        ]
        
        while steps.count < 10 {  // Max workflow steps
            let response = try await provider.response(content: .conversation(conversation))
                .tools(availableTools)
                .instructions("Break this into steps and execute them one by one.")
                .execute()
            
            conversation.append(response.conversationMessage)
            
            // Extract workflow step from response
            if let step = parseWorkflowStep(from: response) {
                steps.append(step)
                
                if step.isComplete {
                    break
                }
            }
        }
        
        return steps
    }
}
```

### 4. Streaming Agentic Interactions
```swift
class StreamingAgent {
    func interactiveSession(_ initialInput: ContentInput) -> AsyncThrowingStream<AgentEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                var conversation: [ConversationMessage] = []
                conversation.append(ConversationMessage(role: .user, content: initialInput))
                
                for try await chunk in provider.response(content: .conversation(conversation))
                    .tools([.webSearch, .codeInterpreter, .custom(InteractiveTool())])
                    .stream() {
                    
                    switch chunk.type {
                    case .text:
                        continuation.yield(.textOutput(chunk.text ?? ""))
                    case .toolCall:
                        continuation.yield(.toolStarted(chunk.toolCall?.name ?? ""))
                    case .toolResult:
                        continuation.yield(.toolCompleted(chunk.toolResult?.result ?? ""))
                    case .complete:
                        continuation.finish()
                    default:
                        break
                    }
                }
            }
        }
    }
}

enum AgentEvent {
    case textOutput(String)
    case toolStarted(String)
    case toolCompleted(String)
    case needsInput(String)
}
```

### 5. Agent-to-Agent Communication
```swift
class AgentOrchestrator {
    private let researchAgent: Agent
    private let analysisAgent: Agent
    private let reportAgent: Agent
    
    func collaborate(on task: String) async throws -> String {
        // Research phase
        let researchResult = try await researchAgent.process(content: [.text(task)])
        
        // Analysis phase with research context
        let analysisInput: [ContentPart] = [
            .text("Based on this research:"),
            .text(researchResult),
            .text("Provide detailed analysis.")
        ]
        let analysisResult = try await analysisAgent.process(content: analysisInput)
        
        // Report generation with full context
        let reportInput: [ContentPart] = [
            .text("Research: \(researchResult)"),
            .text("Analysis: \(analysisResult)"),
            .text("Generate a comprehensive report.")
        ]
        
        return try await reportAgent.process(content: reportInput)
    }
}
```

These patterns are only possible because the new API provides:
- **Conversation state management** through `ConversationMessage`
- **Flexible content ordering** for complex multimodal interactions
- **Clean tool integration** that scales to custom and MCP tools
- **Unified streaming/sync patterns** for real-time agent interactions

## Example Usage Comparisons

### Before (Current API)
```swift
// Simple text
let response = try await provider.createTextResponse(
    model: "gpt-4o",
    text: "Hello"
)
print(response.outputText ?? "No response")

// With web search
let response = try await provider.createResponseWithWebSearch(
    model: "gpt-4o", 
    text: "Current weather"
)

// Complex multimodal (very difficult!)
let inputItems: [ResponseInputItem] = [
    .message(ResponseMessage(
        role: "user",
        content: [
            .inputText(ResponseInputText(text: "Compare these images:")),
            .inputImage(ResponseInputImage(imageUrl: "url1")),
            .inputText(ResponseInputText(text: "vs")),
            .inputImage(ResponseInputImage(imageUrl: "url2"))
        ]
    ))
]
let request = ResponseRequest(model: "gpt-4o", input: .items(inputItems))
let response = try await provider.createResponse(request: request)

```

### After (New API with Responses Superpowers)
```swift
// Simple text
let response = try await provider.response(content: "Hello").execute()
print(response.text ?? "No response")

// Mixed tool syntax (your preferred approach)
let response = try await provider.response(content: "Current weather and create a chart")
    .tools([.webSearch, .codeInterpreter, WeatherTool(), ChartTool()])
    .execute()

// Complex multimodal input AND output
let response = try await provider.response(content: [
    .text("Compare these images and generate an improved version:"),
    .image(beforeImage),
    .text("vs"),
    .image(afterImage),
    .audio(voiceInstructions)
]).tools([.webSearch, .codeInterpreter, .imageGeneration])
.execute()

// Access multimodal outputs with citations (Deep Research style)
print("Text:", response.text ?? "")

// Handle citations and annotations (using existing ResponseAnnotation)
for annotation in response.annotations {
    print("Citation type: \(annotation.type ?? "unknown")")
    print("Citation text: \(annotation.text ?? "")")
    print("Text span: \(annotation.startIndex ?? 0)-\(annotation.endIndex ?? 0)")
}

// Access reasoning steps (for research tasks)
if let reasoning = response.reasoning {
    for step in reasoning {
        print("Reasoning (\(step.type)): \(step.summary)")
    }
}

// Handle multimodal outputs
for content in response.content {
    switch content {
    case .text(let text):
        print("Generated:", text)
    case .image(let data):
        displayGeneratedImage(data)
    case .audio(let data):
        playGeneratedAudio(data)
    case .file(let url):
        openGeneratedFile(url)
    }
}

// Background processing for long tasks
let response = try await provider.response(content: "Process this massive dataset")
    .tools([.codeInterpreter])
    .background(true)
    .execute()

if response.status == .processing {
    // Task running in background, poll for completion
    print("Background task started: \(response.id)")
}

// Enhanced streaming with multimodal chunks
for try await chunk in provider.response(content: complexContent)
    .tools([.webSearch, .codeInterpreter, .imageGeneration, WeatherTool()])
    .stream() {
    
    switch chunk.type {
    case .text:
        print(chunk.text ?? "", terminator: "")
    case .toolCall:
        print("\n[Using \(chunk.toolCall?.name ?? "tool")...]")
    case .toolResult:
        print("[Completed]")
    case .imageGenerated:
        if let imageData = chunk.imageData {
            displayStreamingImage(imageData)
        }
    case .audioGenerated:
        if let audioData = chunk.audioData {
            playStreamingAudio(audioData)
        }
    case .fileCreated:
        if let fileURL = chunk.fileURL {
            showCreatedFile(fileURL)
        }
    case .reasoningStep:
        print("\n[Reasoning...]")
    case .complete:
        print("\n[Complete]")
    default:
        break
    }
}
```

### Agent Building Example

```swift
// Before: Very difficult to build agents on current API
class OldAgent {
    func send(_ text: String) async throws -> String {
        // Have to manually manage conversation state
        // Complex builder patterns
        // Hard to extract tool results
        // Inconsistent streaming
    }
}

// After: Powerful agent foundation with responses superpowers
class NewAgent {
    private let provider: OpenAIProvider
    private var conversation: [ConversationMessage] = []
    private let tools: [any ResponseToolType]
    
    init(provider: OpenAIProvider, tools: [any ResponseToolType]) {
        self.provider = provider
        self.tools = tools
    }
    
    func send(_ input: ContentInput) async throws -> String {
        conversation.append(ConversationMessage(role: .user, content: input))
        
        let response = try await provider.response(content: .conversation(conversation))
            .tools(tools)  // Mix of built-in and custom tools
            .execute()
        
        conversation.append(response.conversationMessage)
        return response.text ?? ""
    }
    
    func sendWithMultimodalOutput(_ input: ContentInput) async throws -> AgentResponse {
        conversation.append(ConversationMessage(role: .user, content: input))
        
        let response = try await provider.response(content: .conversation(conversation))
            .tools([.webSearch, .codeInterpreter, .imageGeneration, WeatherTool(), DataAnalysisTool()])
            .execute()
        
        conversation.append(response.conversationMessage)
        
        // Return rich response with multimodal content
        return AgentResponse(
            text: response.text,
            images: response.content.compactMap { if case .image(let data) = $0 { return data } else { return nil }},
            audio: response.content.compactMap { if case .audio(let data) = $0 { return data } else { return nil }},
            files: response.content.compactMap { if case .file(let url) = $0 { return url } else { return nil }}
        )
    }
    
    func processLongTask(_ input: ContentInput) async throws -> String {
        conversation.append(ConversationMessage(role: .user, content: input))
        
        let response = try await provider.response(content: .conversation(conversation))
            .tools([.codeInterpreter, LongRunningAnalysisTool()])
            .background(true)  // Enable background processing
            .execute()
        
        if response.status == .processing {
            // Poll for completion
            var finalResponse = response
            while finalResponse.status.isProcessing {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                finalResponse = try await provider.retrieveResponse(id: response.id)
            }
            conversation.append(finalResponse.conversationMessage)
            return finalResponse.text ?? ""
        } else {
            conversation.append(response.conversationMessage)
            return response.text ?? ""
        }
    }
    
    func stream(_ input: ContentInput) -> AsyncThrowingStream<AgentStreamEvent, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                conversation.append(ConversationMessage(role: .user, content: input))
                
                var fullContent: [ContentPart] = []
                
                for try await chunk in provider.response(content: .conversation(conversation))
                    .tools(tools)
                    .stream() {
                    
                    switch chunk.type {
                    case .text:
                        if let text = chunk.text {
                            fullContent.append(.text(text))
                            continuation.yield(.text(text))
                        }
                    case .imageGenerated:
                        if let imageData = chunk.imageData {
                            fullContent.append(.image(imageData))
                            continuation.yield(.image(imageData))
                        }
                    case .audioGenerated:
                        if let audioData = chunk.audioData {
                            fullContent.append(.audio(audioData))
                            continuation.yield(.audio(audioData))
                        }
                    case .fileCreated:
                        if let fileURL = chunk.fileURL {
                            fullContent.append(.file(fileURL))
                            continuation.yield(.file(fileURL))
                        }
                    case .toolCall:
                        continuation.yield(.toolStarted(chunk.toolCall?.name ?? ""))
                    case .toolResult:
                        continuation.yield(.toolCompleted(chunk.toolResult?.result ?? ""))
                    case .complete:
                        // Add complete response to conversation
                        conversation.append(ConversationMessage(role: .assistant, content: fullContent))
                        continuation.finish()
                    default:
                        break
                    }
                }
            }
        }
    }
}

struct AgentResponse {
    let text: String?
    let images: [Data]
    let audio: [Data] 
    let files: [URL]
}

enum AgentStreamEvent {
    case text(String)
    case image(Data)
    case audio(Data)
    case file(URL)
    case toolStarted(String)
    case toolCompleted(String)
}

// Example usage with mixed tools
let agent = NewAgent(
    provider: openAIProvider,
    tools: [
        .webSearch,              // Built-in
        .codeInterpreter,        // Built-in
        .imageGeneration,        // Built-in
        WeatherTool(),           // Custom
        DataAnalysisTool(),      // Custom
        MCPSearchTool()          // MCP tool
    ]
)
```

## Risk Assessment

### Low Risk
- **Non-breaking implementation** in Phase 1
- **Existing API remains** during transition
- **Internal delegation** ensures compatibility

### Medium Risk
- **Learning curve** for existing users (mitigated by similarity)
- **Documentation updates** needed across ecosystem
- **Example code** needs updating

### High Risk
- **Breaking changes** in Phase 3 (major version bump required)
- **Third-party integrations** may need updates
- **Complex migration** for heavily customized usage

## Success Metrics

### Developer Experience
- **Reduce onboarding time** by 70% (measured by documentation read time)
- **Increase API adoption** of advanced features by 50%
- **Reduce support questions** about basic usage by 60%

### Code Quality
- **Reduce API surface** by 80% (number of public methods)
- **Increase test coverage** to 95% (focused testing)
- **Reduce cyclomatic complexity** by 50% (internal implementation)

### Performance
- **Maintain current performance** (no regressions)
- **Reduce memory allocation** by 20% (simplified object model)
- **Faster compilation** due to simpler API surface

## Timeline

### Phase 1: Implementation (4-6 weeks)
- Week 1-2: Core ResponseSession implementation
- Week 3-4: Tool integration and streaming
- Week 5-6: Testing and documentation

### Phase 2: Migration (8-12 weeks)
- Week 1-4: Deprecation warnings and migration guides
- Week 5-8: Community feedback and iteration
- Week 9-12: Ecosystem updates and examples

### Phase 3: Cleanup (2-4 weeks)
- Week 1-2: Remove deprecated code
- Week 3-4: Final testing and release

## Why This Is Perfect for Agent Development

### 🧠 **Agent-First Design Principles**

#### 1. Conversation State = Agent Memory
```swift
// Agents need memory - this API provides it naturally
class ConversationalAgent {
    private var conversation: [ConversationMessage] = []
    
    func remember(_ input: [ContentPart]) {
        conversation.append(ConversationMessage(role: .user, content: input))
    }
    
    func respond() async throws -> String {
        let response = try await provider.response(.conversation(conversation))
            .tools(agentTools)
            .execute()
        
        conversation.append(response.conversationMessage)  // Perfect for agents!
        return response.text ?? ""
    }
}
```

#### 2. Multimodal Processing = Smart Agents
```swift
// Agents that can see, hear, and create - not just text
func processPatientData(_ images: [Data], _ description: String) async throws -> AgentDiagnosis {
    let response = try await provider.response([
        .text("Analyze these medical images: \(description)"),
        .image(images[0]), .image(images[1])
    ])
    .tools([.webSearch, MedicalKnowledgeTool(), DiagnosisAssistantTool()])
    .execute()
    
    return AgentDiagnosis(
        textAnalysis: response.text,
        generatedCharts: response.content.compactMap { if case .image(let data) = $0 { return data } else { return nil }},
        citations: response.annotations
    )
}
```

#### 3. Tool Orchestration = Capable Agents
```swift
// Mix built-in capabilities with custom domain knowledge AND MCP integrations
let smartAgent = SmartAgent(tools: [
    .webSearch,              // Real-time information
    .codeInterpreter,        // Data analysis
    .imageGeneration,        // Visual creation
    DatabaseTool(),          // Custom business logic
    MCPSlackTool(            // MCP integration
        serverUrl: "https://company.slack.mcp",
        authToken: "xoxb-token"
    ),
    MCPSalesforceTool(       // Another MCP integration
        serverUrl: "https://company.salesforce.mcp", 
        authToken: "sf-token"
    ),
    DomainExpertTool()       // Specialized knowledge
])

// Agent can now access: web + code execution + image creation + database + Slack + Salesforce!
```

**Real MCP Agent Example:**
```swift
class CustomerSupportAgent {
    private let provider: OpenAIProvider
    private let tools: [any ToolType]
    
    init() {
        self.provider = OpenAIProvider(apiKey: "...")
        self.tools = [
            .webSearch,                      // For general knowledge
            MCPSlackTool(                   // Internal team communication
                serverUrl: "https://company.slack.mcp",
                authToken: ProcessInfo.processInfo.environment["SLACK_TOKEN"]!
            ),
            MCPZendeskTool(                 // Customer tickets
                serverUrl: "https://company.zendesk.mcp",
                authToken: ProcessInfo.processInfo.environment["ZENDESK_TOKEN"]!
            ),
            MCPSalesforceTool(              // Customer data
                serverUrl: "https://company.salesforce.mcp",
                authToken: ProcessInfo.processInfo.environment["SF_TOKEN"]!
            ),
            KnowledgeBaseTool()             // Custom tool for internal docs
        ]
    }
    
    func handleCustomerQuery(_ query: String, customerId: String) async throws -> SupportResponse {
        let response = try await provider.response([
            .text("Customer ID: \(customerId)"),
            .text("Query: \(query)"),
            .text("Please help resolve this customer issue using all available information.")
        ])
        .tools(tools)
        .instructions("""
            You are a customer support agent with access to:
            - Slack for team communication
            - Zendesk for ticket history
            - Salesforce for customer data
            - Knowledge base for solutions
            
            Provide comprehensive help and escalate to team if needed.
            """)
        .execute()
        
        return SupportResponse(
            reply: response.text ?? "",
            sources: response.annotations.map { $0.text ?? "" },
            escalationNeeded: response.text?.contains("escalate") == true
        )
    }
}

struct SupportResponse {
    let reply: String
    let sources: [String]
    let escalationNeeded: Bool
}
```

#### 4. Background Processing = Persistent Agents
```swift
// Agents that work on long-term projects
func startLongTermResearch(_ topic: String) async throws -> TaskHandle {
    let response = try await provider.response("Research \(topic) comprehensively")
        .tools([.webSearch, .codeInterpreter, ResearchTool()])
        .background(true)  // Agent keeps working!
        .execute()
    
    return TaskHandle(id: response.id, agent: self)
}
```

#### 5. Agent Communication = Agent Swarms
```swift
// Agents can easily talk to each other
class AgentSwarm {
    func collaborate(_ task: String) async throws -> String {
        // Research agent
        let research = try await researchAgent.process([.text(task)])
        
        // Analysis agent (gets research as structured input)
        let analysis = try await analysisAgent.process([
            .text("Research findings:"),
            .text(research),
            .text("Provide detailed analysis")
        ])
        
        // Report agent (gets both inputs)
        return try await reportAgent.process([
            .text("Research: \(research)"),
            .text("Analysis: \(analysis)"),
            .text("Create executive summary")
        ])
    }
}
```

### 🎯 **What Makes This Revolutionary for Agents**

| Agent Capability | Current API | New API | Impact |
|------------------|-------------|---------|---------|
| **Memory Management** | Manual conversation arrays | Built-in `ConversationMessage` | 🚀 Seamless |
| **Multimodal I/O** | Text only | Images, audio, files | 🚀 Game-changing |
| **Tool Integration** | Function calling only | Mixed built-in + custom | 🚀 Limitless |
| **Persistent Tasks** | HTTP timeout limits | Background processing | 🚀 Enterprise-ready |
| **Agent Collaboration** | Complex manual setup | Natural message passing | 🚀 Swarm-enabled |
| **Real-time Interaction** | Basic streaming | Multimodal streaming | 🚀 Interactive |

### 🔮 **Agent Patterns This Enables**

#### Research Agents with Deep Analysis
```swift
// Multi-step reasoning with tool use and citations
let researchAgent = ResearchAgent(
    tools: [.webSearch, .codeInterpreter, DataAnalysisTool()],
    specialization: "climate science"
)

let report = try await researchAgent.investigate("carbon capture effectiveness")
// Gets: comprehensive analysis + charts + source citations + raw data
```

#### Multimodal Creative Agents  
```swift
// Agents that create rich media content
let creativeAgent = CreativeAgent(
    tools: [.imageGeneration, .audioGeneration, VideoEditingTool()]
)

let campaign = try await creativeAgent.createCampaign([
    .text("Create marketing campaign for eco-friendly cars"),
    .image(productPhotos), 
    .audio(brandGuidelines)
])
// Gets: images + copy + audio + video content
```

#### Autonomous Workflow Agents
```swift
// Agents that execute complex business processes
let workflowAgent = WorkflowAgent(
    tools: [.codeInterpreter, DatabaseTool(), EmailTool(), SlackTool()]
)

try await workflowAgent.processOrder(orderData)
.background(true)  // Runs independently, notifies when complete
```

## Conclusion

This refactoring completely reimagines the OpenAI Responses API interface, addressing every piece of feedback while unlocking the full power of the responses API. The new design delivers:

### 🎯 **Exactly What Was Requested**
- **Mixed tool syntax**: `[.webSearch, WeatherTool(), MCPTool()]` - built-in enums + custom instances
- **Order-aware multimodal**: Complex sequences with text, images, audio preserved naturally
- **Agent-friendly foundation**: Perfect building blocks for sophisticated agents
- **Tool compatibility**: Same `Tool` definition works across all APIs

### 🚀 **Responses API Superpowers Unlocked**
- **Multimodal outputs**: Generate images, audio, files - not just consume them
- **Background processing**: Long-running tasks with polling support
- **Stateful conversations**: Automatic context management and continuation
- **Enhanced streaming**: Real-time delivery of multimodal content
- **Advanced reasoning**: Access to model thought processes

### 🛠 **Perfect Developer Experience**
- **90% API reduction**: From 20+ confusing methods to 1 intuitive entry point
- **Natural progression**: Simple text → multimodal → agents → background tasks
- **Zero learning curve**: `response(content:)` is instantly understandable
- **Future-proof**: Ready for any new OpenAI capabilities

### 🤖 **Agent Development Revolution**
This API makes building sophisticated agents trivial - from simple chatbots to complex multimodal, multi-tool, background-processing agents with just a few lines of code. The conversation state management, tool orchestration, and multimodal capabilities provide the perfect foundation for the next generation of AI agents.

**The refactored API transforms AISDK from a provider interface into a true agentic development platform**, while maintaining the simplicity that makes it accessible to developers at every level.

## Implementation Todo List

### ✅ Phase 0: Planning & Design
- [x] **Analysis of current Response API implementation**
- [x] **Identify core problems (API surface complexity)**
- [x] **Design thin wrapper approach**
- [x] **Create comprehensive refactoring plan**
- [x] **Add concrete MCP tool integration examples**
- [x] **Identify need for Universal Message System**
- [x] **Create Universal Message System plan** (see `docs/tasks/universal-message-system-plan.md`)

### ✅ Phase 0.5: Universal Message System (FULLY COMPLETE)
- [x] **CRITICAL DEPENDENCY: Complete Universal Message System first**
  - [x] Implement `AIInputMessage` struct ✅
  - [x] Implement `AIContentPart` enum with image, audio, file support ✅
  - [x] Implement `AIMessageRole` enum ✅
  - [x] Implement structured content types: `AIImageContent`, `AIAudioContent`, `AIFileContent` ✅
  - [x] Implement Response API conversion extensions ✅
  - [x] Implement Anthropic API conversion extensions ✅
  - [x] Implement Gemini API conversion extensions ✅
  - [x] Test universal → Response API conversion accuracy ✅
  - [x] **Status**: Complete universal message system with full multi-provider support
- [x] **Status**: All compilation issues resolved, full test coverage achieved

### 🎉 Universal Message System Results (DELIVERED)
**Files Implemented:**
- ✅ `Sources/AISDK/Models/AIMessage.swift` (493 lines) - Core universal types
- ✅ `Sources/AISDK/LLMs/OpenAI/ResponseAPI/AIMessage+ResponseConversions.swift` - OpenAI Responses API conversions
- ✅ `Sources/AISDK/LLMs/OpenAI/APIModels/AIMessage+ChatConversions.swift` - OpenAI Chat Completions conversions
- ✅ `Sources/AISDK/LLMs/Anthropic/AIMessage+AnthropicConversions.swift` (196 lines) - Anthropic API conversions
- ✅ `Sources/AISDK/LLMs/Gemini/AIMessage+GeminiConversions.swift` (188 lines) - Gemini API conversions
- ✅ `Tests/AISDKTests/UniversalMessageSystemTests.swift` (316 lines) - Complete test coverage

**Key Features Delivered:**
- 🎯 Beautiful content syntax: `.text()`, `.image()`, `.audio()`, `.file()`, `.video()`
- 🔄 Multi-provider support: OpenAI (Chat + Responses), Anthropic, Gemini
- 🛡️ Graceful fallbacks for unsupported content types per provider
- 🧪 Complete test coverage with 17 passing tests
- 📚 Full documentation with provider feature matrix

### 📋 Phase 1: Core Implementation (Weeks 1-3) 

**🎯 Simplified Implementation Philosophy: Direct Universal Message System Usage**
- ✅ **USE** `AIInputMessage` directly (no wrapper needed - it's already perfect)
- ✅ **LEVERAGE** existing Response API structures: `ResponseObject`, `ResponseTool`
- ✅ **LEVERAGE** existing conversion: `AIMessage+ResponseConversions.swift` (already complete)
- ✅ **CREATE** simple convenience overloads for common patterns
- ✅ **AVOID** unnecessary abstractions and wrappers

#### Week 1: ResponseSession Class (Direct AIInputMessage Usage)
- [ ] **File: `Sources/AISDK/LLMs/OpenAI/ResponseAPI/ResponseSession.swift`**
  - [ ] Create `ResponseSession` class that accepts `AIInputMessage` directly
  - [ ] Add init: `ResponseSession(provider: OpenAIProvider, message: AIInputMessage)`
  - [ ] Add convenience inits:
    - [ ] `ResponseSession(provider: OpenAIProvider, text: String)` → creates `AIInputMessage.user(text)`
    - [ ] `ResponseSession(provider: OpenAIProvider, content: [AIContentPart])` → creates `AIInputMessage.user(content)`
    - [ ] `ResponseSession(provider: OpenAIProvider, conversation: [AIInputMessage])`
  - [ ] Add fluent configuration methods: 
    - [ ] `.tools([Tool])` → converts using existing Tool protocol
    - [ ] `.background(Bool)`, `.reasoning(ResponseReasoning)`, `.instructions(String)`
    - [ ] `.model(String)`, `.previousResponse(String)`
  - [ ] Write unit tests for session configuration

#### Week 1: Execute & Stream Methods  
- [ ] **Continue ResponseSession implementation**
  - [ ] Add `execute() async throws -> Response` method
    - [ ] Convert `AIInputMessage` using existing `toResponseMessage()` 
    - [ ] Use existing `ResponseBuilder` with converted message
    - [ ] Return wrapped `Response` object
  - [ ] Add `stream() -> AsyncThrowingStream<ResponseChunk, Error>` method
    - [ ] Convert `AIInputMessage` and stream using existing `ResponseBuilder`
    - [ ] Wrap `ResponseStreamEvent` in simple `ResponseChunk`
  - [ ] Write integration tests with real provider

#### Week 2: Response & Streaming Wrappers
- [ ] **File: `Sources/AISDK/LLMs/OpenAI/ResponseAPI/ResponseTypes.swift`**
  - [ ] Create simple `Response` struct wrapping `ResponseObject`:
    - [ ] `text: String?` → extract from `response.outputText`
    - [ ] `content: [AIContentPart]` → extract multimodal outputs and convert back to universal types
    - [ ] `annotations: [ResponseAnnotation]` → extract existing annotations
    - [ ] `reasoning: [ReasoningStep]?` → extract reasoning if present
    - [ ] `id: String`, `status: ResponseStatus`, `usage: ResponseUsage?`
    - [ ] `conversationMessage: AIInputMessage` → convert back for agent integration
  - [ ] Create simple `ResponseChunk` struct wrapping `ResponseStreamEvent`:
    - [ ] `text: String?` → extract delta text
    - [ ] `isComplete: Bool`, `eventType: String`
    - [ ] `toolCall: ToolCall?`, `reasoning: ReasoningStep?`
  - [ ] Write unit tests for response extraction

#### Week 2: Provider Integration
- [ ] **File: `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+Response.swift`**
  - [ ] Add extension methods to existing `OpenAIProvider`:
    - [ ] `response(_ message: AIInputMessage) -> ResponseSession`
    - [ ] `response(_ text: String) -> ResponseSession` → creates `AIInputMessage.user(text)`
    - [ ] `response(_ content: [AIContentPart]) -> ResponseSession` → creates `AIInputMessage.user(content)`
    - [ ] `response(conversation: [AIInputMessage]) -> ResponseSession`
  - [ ] Ensure backward compatibility with existing methods
  - [ ] Write integration tests

#### Week 3: Tool Integration & Testing
- [ ] **Tool Integration**
  - [ ] Leverage existing `Tool` protocol (no changes needed)
  - [ ] Convert `[Tool]` to `[ResponseTool]` using existing mechanisms
  - [ ] Test mixed tool arrays: `[WeatherTool(), .webSearch, .codeInterpreter]`
  - [ ] Add MCP tool enum cases to existing `ResponseTool` if needed
  
- [ ] **Comprehensive Testing**
  - [ ] Test simple usage: `provider.response("Hello").execute()`
  - [ ] Test multimodal: `provider.response([.text("Hi"), .image(data)]).execute()`
  - [ ] Test with tools: `provider.response("Weather?").tools([WeatherTool()]).execute()`
  - [ ] Test streaming: `provider.response("Story").stream()`
  - [ ] Test conversation: `provider.response(conversation: messages).execute()`
  - [ ] Test Response API specific features: `.background()`, `.reasoning()`

### 📋 Phase 2: Advanced Features & Documentation (Week 4)

#### Advanced Features Testing
- [ ] **MCP Integration** (if needed)
  - [ ] Add MCP tool enum cases to `ResponseTool`
  - [ ] Test MCP tool integration patterns
  - [ ] Document MCP setup and usage

- [ ] **Agent Integration Testing**
  - [ ] Test `Response.conversationMessage` with existing Agent class
  - [ ] Verify agent conversation patterns work
  - [ ] Test multi-turn conversations

#### Documentation & Examples
- [ ] **Update Documentation**
  - [ ] Update `OpenAI-Responses-API.md` with new simple API
  - [ ] Add migration examples from old to new API
  - [ ] Document tool integration patterns
  - [ ] Add troubleshooting section

- [ ] **Code Examples**
  - [ ] Simple text response example
  - [ ] Multimodal input example  
  - [ ] Tool usage example
  - [ ] Streaming example
  - [ ] Agent integration example

### 📋 Phase 3: Production Polish (Week 5)

#### Code Quality & Release
- [ ] **Final Testing**
  - [ ] Integration test suite with real API
  - [ ] Performance comparison with existing API
  - [ ] Memory usage testing
  - [ ] Error handling edge cases

- [ ] **Documentation Polish**
  - [ ] Proofread all documentation
  - [ ] Verify all code examples work
  - [ ] Update package README
  - [ ] Prepare release notes

#### Backward Compatibility
- [ ] **Migration Support**
  - [ ] Ensure all existing Response API methods still work
  - [ ] Add deprecation warnings where appropriate
  - [ ] Create migration guide
  - [ ] Update all examples to use new API

### 🎯 Simplified API Design

#### Before (Complex)
```swift
// Multiple entry points, confusing
provider.createTextResponse(model: "gpt-4o", text: "Hello")
provider.createResponseWithWebSearch(model: "gpt-4o", text: "Search")
ResponseBuilder.text(model: "gpt-4o", "Hello").build()
```

#### After (Simple - Direct Universal Message Usage)
```swift
// Single, clean API using AIInputMessage directly
provider.response("Hello").execute()
provider.response([.text("Hi"), .image(data)]).tools([WeatherTool()]).execute()
provider.response(AIInputMessage.user("Hello")).stream()

// For advanced users, full control
let message = AIInputMessage.user([
    .text("Compare these:"),
    .image(image1),
    .text("vs"), 
    .image(image2)
])
provider.response(message).tools([.webSearch, .codeInterpreter]).execute()
```

### ✅ Key Benefits of This Approach

1. **🚀 Leverage Existing Foundation**: Uses completed Universal Message System directly
2. **🎯 No Over-Engineering**: No unnecessary wrapper layers 
3. **💎 Beautiful Syntax**: `provider.response([.text("Hi"), .image(data)])`
4. **🔄 Multi-Provider Ready**: `AIInputMessage` already converts to all providers
5. **🛡️ Backward Compatible**: Existing Response API methods remain unchanged
6. **⚡ Fast Implementation**: 3-5 weeks vs original 8-10 weeks

### 📋 Progress Tracking

#### Updated Timeline: 3-5 Weeks (Dramatically Simplified)
- **Week 1**: ResponseSession class with direct AIInputMessage usage ✅ Ready to start
- **Week 2**: Response wrappers and provider integration  
- **Week 3**: Tool integration and comprehensive testing
- **Week 4**: Advanced features and documentation
- **Week 5**: Production polish and release

**Critical Insight**: By using `AIInputMessage` directly instead of creating wrapper abstractions, we eliminate 2-3 weeks of unnecessary work while providing a cleaner, more powerful API.