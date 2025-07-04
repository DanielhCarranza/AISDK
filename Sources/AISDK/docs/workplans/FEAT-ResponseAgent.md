# ResponseAgent Implementation Workplan

## Task ID
FEAT-ResponseAgent

## Problem Statement
The current `Agent` class uses OpenAI's Chat Completions API, which is stateless and requires manual conversation management. We need a **100% Responses API native agent** that fully leverages all Responses API advantages:

- **Stateful multi-conversation support**: Handle multiple conversation threads with storage integration
- **All built-in tools**: Native web search, code interpreter, image generation, file search, MCP
- **Enhanced streaming with semantic events**: Better tool execution feedback and progress tracking
- **Background task processing**: Long-running tasks with detailed state management and UI/UX integration
- **Superior multimodal handling**: Item-based structure for complex interactions
- **Tool execution orchestration**: Handle tool execution loops while API manages tool selection

We need a `ResponseAgent` class that provides a **modern, native Responses API experience** with multi-session support, **full multimodal input via AIInputMessage**, and **flexible storage integration** (SwiftData, Firebase, Supabase).

## Proposed Implementation

### Core Design Principles
1. **100% Responses API Native**: No Chat Completions fallback, pure Responses API experience
2. **AIInputMessage Primary Interface**: Full multimodal support (text, images, audio, files, etc.) with String convenience methods
3. **Multi-Conversation/Session Support**: Handle multiple conversation threads with persistence (inspired by ChatSession patterns)
4. **Flexible Storage Integration**: SwiftData, Firebase, Supabase support with protocol-based abstraction
5. **All Built-in Tools**: Full access to all OpenAI built-in tools by default with conflict detection
6. **Tool Execution Focus**: Handle tool execution orchestration using proven Agent validateAndSetParameters pattern while API manages selection
7. **Background Task Processing**: Long-running tasks with detailed state management via `.task()` method
8. **Modern UX**: Parameter-controlled streaming, detailed task state, observable patterns

### Architecture Overview
```swift
public class ResponseAgent {
    // Core initialization with local storage by default
    init(
        llm: OpenAIProvider, 
        tools: [Tool.Type] = [], 
        instructions: String? = nil,
        storage: ResponseAgentStorage? = LocalStorage() // Default to local storage
    )
    
    // PRIMARY: AIInputMessage interface for full multimodal support
    func send(
        _ message: AIInputMessage, 
        streaming: Bool = false, 
        conversationId: String? = nil
    ) async throws -> ResponseResult
    
    // CONVENIENCE: String interface for simple text messages
    func send(
        _ text: String, 
        streaming: Bool = false, 
        conversationId: String? = nil
    ) async throws -> ResponseResult
    
    // Background task processing with multimodal support
    func task(
        _ message: AIInputMessage, 
        conversationId: String? = nil
    ) async throws -> ResponseTask
    
    // Background task convenience for text
    func task(
        _ text: String, 
        conversationId: String? = nil
    ) async throws -> ResponseTask
    
    // Multi-conversation management (inspired by ChatSession patterns)
    func startConversation(id: String? = nil) -> String
    func continueConversation(id: String)
    func listConversations() -> [ConversationInfo]
    func deleteConversation(id: String) async throws
    
    // Built-in tools configuration (all available by default)
    func configureBuiltInTools(_ tools: [BuiltInTool] = .all) -> Self
    func validateToolConflicts() -> [ToolConflict] // Warnings for same-named tools
}
```

### Key Implementation Details

1. **Full Multimodal Support via AIInputMessage**:
   - Primary interface uses AIInputMessage for rich multimodal content (text, images, audio, files, etc.)
   - Built-in conversion to Response API format via existing AIMessage+ResponseConversions.swift
   - Support for all OpenAI model capabilities: .text, .vision, .audio, .reasoning, .tools
   - String convenience methods for simple text-only interactions

2. **Multi-Conversation Architecture (inspired by ChatSession)**:
   - Each conversation thread has its own `previousResponseId` chain
   - ConversationData structure similar to ChatSession with id, title, messages, createdAt, lastModified
   - Thread-safe conversation management with real-time listeners
   - Automatic conversation cleanup and archival

3. **Flexible Storage Integration**:
   ```swift
   protocol ResponseAgentStorage {
       func saveConversation(_ conversation: ConversationData) async throws
       func loadConversation(id: String) async throws -> ConversationData?
       func listConversations() async throws -> [ConversationInfo]
       func deleteConversation(id: String) async throws
   }
   
   // Storage implementations
   class LocalStorage: ResponseAgentStorage { ... } // DEFAULT - local file system
   class NoStorage: ResponseAgentStorage { ... }    // No persistence option
   class SwiftDataStorage: ResponseAgentStorage { ... }
   class FirebaseStorage: ResponseAgentStorage { ... }
   class SupabaseStorage: ResponseAgentStorage { ... }
   
   // Default initialization uses local storage
   let agent = ResponseAgent(llm: provider) // Uses LocalStorage() by default
   
   // Explicitly disable storage
   let agent = ResponseAgent(llm: provider, storage: NoStorage())
   ```

4. **Custom Tool Call Handling (Using Proven Agent Pattern)**:
   - **Tool Registration**: Use existing ToolRegistry system from baseline Agent
   - **Parameter Validation**: Use existing `validateAndSetParameters()` method from Tool protocol
   - **Non-Streaming**: 
     1. Convert custom tools to `ResponseTool.function()` format → send to OpenAI API
     2. API returns `functionCall` chunks → ResponseAgent intercepts and processes
     3. **Tool Execution Pattern** (same as baseline Agent):
        - Create tool instance: `var tool = toolType.init()`
        - Parse arguments: `let argumentsData = arguments.data(using: .utf8)`
        - Validate & set: `tool = try tool.validateAndSetParameters(argumentsData)`
        - Execute: `let (response, metadata) = try await tool.execute()`
     4. Send tool results back to API → continue with final response
   - **Streaming**: Same tool execution pattern, but with real-time semantic events (`functionCall`, `functionCallOutput`)
   - **Conflict Detection**: Warn when custom tools have same names as built-in tools (WeatherTool vs web search)

5. **Built-in Tool Integration**:
   - All OpenAI built-in tools available by default (web search, code interpreter, image generation, file search, MCP)
   - Semantic streaming events for built-in tools (`webSearchCall`, `codeInterpreterCall`, `imageGeneration`)
   - Metadata extraction and preservation from all tool executions

6. **Modern Send Method with Parameter Control**:
   ```swift
   // Primary multimodal interface
   let message = AIInputMessage.user([
       .text("Analyze this image"),
       .image(imageData, detail: .high)
   ])
   let response = try await agent.send(message, streaming: false)
   
   // Streaming response with semantic events
   for try await chunk in agent.send(message, streaming: true) {
       // Handle real-time chunks with semantic events
   }
   
   // Convenience for simple text
   let textResponse = try await agent.send("Hello", streaming: false)
   ```

7. **Background Task Processing**:
   - Detailed state tracking: `.queued`, `.inProgress`, `.completed`, `.failed`
   - Observable patterns for UI integration
   - Progress reporting and time estimates
   - Cancellation and recovery support
   - Multimodal task support via AIInputMessage

8. **Enhanced Error Handling**:
   - 100% Responses API native (no Chat Completions fallback)
   - Retry with exponential backoff
   - Graceful degradation for tool failures
   - User-friendly error reporting for manual recovery

## Components Involved
- **New Components**:
  - `ResponseAgent.swift` - Main agent class with multimodal support and multi-conversation management
  - `ResponseAgentStorage.swift` - Storage abstraction protocol 
  - `LocalStorage.swift` - Local file system storage (DEFAULT)
  - `NoStorage.swift` - No persistence storage option
  - `SwiftDataStorage.swift` - SwiftData implementation for local storage
  - `FirebaseStorage.swift` - Firebase implementation for cloud storage
  - `SupabaseStorage.swift` - Supabase implementation for cloud storage  
  - `ResponseTask.swift` - Background task management with detailed state tracking
  - `ConversationManager.swift` - Thread-safe conversation management
  - `ConversationData.swift` - Data model inspired by ChatSession structure
  - `ToolConflictDetector.swift` - Tool name conflict detection and warnings
  - `ResponseResult.swift` - Unified result type for streaming/non-streaming responses
  - `CustomToolHandler.swift` - Handle custom tool calls using existing ToolRegistry and validateAndSetParameters
  
- **Enhanced Components**:
  - `AgentState.swift` - Add Response-specific states (.backgroundProcessing, .toolExecuting, etc.)
  - `ToolRegistry.swift` - Enhanced with Response API tool conversion
  - Documentation in `docs/Agents/ResponseAgentUsage.md`
  
- **Integration Points**:
  - `OpenAIProvider+Response.swift` - Use existing Response API methods extensively
  - `ResponseObject.swift` - Extract tool metadata and semantic events
  - `ResponseChunk.swift` - Handle streaming semantic events
  - `AIMessage+ResponseConversions.swift` - Already exists for multimodal conversion (✅)
  - `AIMessage.swift` - Universal message system for full multimodal support (✅)
  - `OpenAIModels.swift` - Model capability checking for multimodal support (✅)

## Dependencies
- OpenAI Responses API implementation (already exists) ✅
- Tool system with metadata support and validateAndSetParameters (already exists) ✅
- ToolRegistry for tool lookup and registration (already exists) ✅
- AIInputMessage universal message system (already exists) ✅
- AIMessage+ResponseConversions multimodal conversion (already exists) ✅
- OpenAI model capability detection (already exists) ✅
- Storage abstraction with multiple backends including local default and no-storage option (need to create) 📝
- Multi-conversation management (need to create) 📝
- Background task state management (need to create) 📝
- Tool conflict detection (need to create) 📝
- Custom tool handling using existing ToolRegistry and validateAndSetParameters (need to create) 📝
- ConversationData model inspired by ChatSession (need to create) 📝

## Implementation Checklist

### Phase 1: Core ResponseAgent & Multimodal Support
- [ ] Create `ResponseAgent.swift` with AIInputMessage primary interface and String convenience methods
- [ ] Implement multimodal support using existing AIMessage+ResponseConversions.swift
- [ ] Create `ConversationData.swift` model inspired by ChatSession (id, title, messages, timestamps)
- [ ] Implement `ConversationManager.swift` for thread-safe conversation management
- [ ] Create `ResponseAgentStorage.swift` protocol 
- [ ] Create `LocalStorage.swift` implementation (DEFAULT) for local file system persistence
- [ ] Create `NoStorage.swift` implementation for no conversation persistence
- [ ] Implement `ResponseResult.swift` for unified streaming/non-streaming responses
- [ ] Create `CustomToolHandler.swift` to intercept and execute custom tool calls using existing ToolRegistry
- [ ] Integrate existing `validateAndSetParameters()` pattern from baseline Agent for parameter validation
- [ ] Add custom tool call handling for both streaming and non-streaming scenarios using proven Agent approach
- [ ] Implement tool conflict detection and warnings between custom and built-in tools
- [ ] Add basic conversation persistence and retrieval

### Phase 2: Background Task Processing & Tool Orchestration
- [ ] Create `ResponseTask.swift` with detailed state management
- [ ] Implement observable state patterns for UI integration
- [ ] Add background task processing with `.task()` method
- [ ] Implement tool execution orchestration loops
- [ ] Add progress reporting and cancellation support
- [ ] Create enhanced streaming with semantic events
- [ ] Extract and preserve tool metadata from Response outputs

### Phase 3: Storage Backends & Advanced Features
- [ ] Enable all OpenAI built-in tools by default (web search, code interpreter, image generation, file search, MCP)
- [ ] Create `SwiftDataStorage.swift` implementation for local storage
- [ ] Create `FirebaseStorage.swift` implementation for cloud storage (inspired by ChatSession patterns)
- [ ] Create `SupabaseStorage.swift` implementation for cloud storage
- [ ] Add conversation cleanup and archival features
- [ ] Implement retry logic with exponential backoff
- [ ] Add performance optimizations for large conversations
- [ ] Add model capability checking for multimodal support (using OpenAIModels.swift)

### Phase 4: Testing & Documentation
- [ ] Create `ResponseAgentIntegrationTests.swift` mirroring Agent tests
- [ ] Add Response API specific feature tests (built-in tools, background tasks)
- [ ] Test multi-conversation scenarios and storage persistence
- [ ] Create comprehensive usage documentation
- [ ] Add migration examples from Agent to ResponseAgent
- [ ] Create performance benchmark comparisons

## Verification Steps

### Automated Tests
- [ ] Run ResponseAgentIntegrationTests with real OpenAI Responses API
- [ ] Test multimodal support with AIInputMessage (text, images, audio, files)
- [ ] Test model capability checking for multimodal features
- [ ] Test multi-conversation management and thread safety
- [ ] Verify all built-in tools integration (web search, code interpreter, image generation, file search, MCP)
- [ ] Test background task processing with state management
- [ ] Test parameter-controlled streaming vs non-streaming
- [ ] Test custom tool call handling in both streaming and non-streaming scenarios (WeatherTool, CalculatorTool)
- [ ] Test all storage backends (LocalStorage default, NoStorage, SwiftData, Firebase, Supabase)
- [ ] Test storage persistence and retrieval across sessions
- [ ] Test tool conflict detection and warnings
- [ ] Test error handling and retry mechanisms
- [ ] Test conversation cleanup and archival
- [ ] Test AIMessage+ResponseConversions multimodal conversion accuracy
- [ ] Test custom tool parameter validation using existing validateAndSetParameters pattern
- [ ] Verify tool execution flow matches baseline Agent behavior (ToolRegistry, parameter validation, execution)

### Manual Verification
- [ ] Compare response quality and capabilities vs. Agent
- [ ] Test multimodal interactions (text + image, audio, files) vs. Agent limitations
- [ ] Verify conversation continuity across multiple sessions
- [ ] Test background task UI/UX with state tracking
- [ ] Validate developer experience with AIInputMessage primary interface
- [ ] Test storage integration with all backends (LocalStorage default, NoStorage, SwiftData, Firebase, Supabase)
- [ ] Test conversation management patterns inspired by ChatSession
- [ ] Verify tool execution orchestration works seamlessly
- [ ] Test tool conflict detection and warnings in real scenarios
- [ ] Test custom tool execution flow and semantic events in streaming vs non-streaming
- [ ] Verify custom tool parameter validation behaves identically to baseline Agent

### Performance Benchmarks
- [ ] Measure response latency vs. Agent (should be faster due to stateful API)
- [ ] Test memory usage for multiple concurrent conversations
- [ ] Measure storage performance with large conversation histories across all backends
- [ ] Test multimodal content processing performance (image, audio, file upload/conversion)
- [ ] Measure tool execution orchestration performance vs. Agent
- [ ] Test background task processing efficiency and resource usage

## Example Usage

### Basic Setup with Storage Options
```swift
import AISDK

// Default initialization - uses LocalStorage automatically
let agent = ResponseAgent(
    llm: OpenAIProvider(model: OpenAIModels.gpt4o),
    tools: [WeatherTool.self, CalculatorTool.self],
    instructions: "You are a helpful assistant with access to tools."
    // storage: LocalStorage() is default
)

// No storage option - conversations not persisted
let ephemeralAgent = ResponseAgent(
    llm: OpenAIProvider(model: OpenAIModels.gpt4o),
    tools: [WeatherTool.self, CalculatorTool.self],
    instructions: "You are a helpful assistant.",
    storage: NoStorage()
)

// Cloud storage options
let firebaseAgent = ResponseAgent(
    llm: OpenAIProvider(model: OpenAIModels.gpt4o),
    tools: [WeatherTool.self, CalculatorTool.self],
    storage: FirebaseStorage() // or SwiftDataStorage(), SupabaseStorage()
)

// Configure built-in tools (all available by default)
agent.configureBuiltInTools([.webSearchPreview, .codeInterpreter, .imageGeneration])

// Check for tool conflicts between custom and built-in tools
let conflicts = agent.validateToolConflicts()
if !conflicts.isEmpty {
    print("⚠️ Tool conflicts detected: \(conflicts)")
}
```

### Multimodal Conversations
```swift
// Create multimodal message
let message = AIInputMessage.user([
    .text("Analyze this image and search for more information about it"),
    .image(imageData, detail: .high),
    .file(pdfData, filename: "context.pdf", type: .pdf)
])

// Start conversation
let conversationId = agent.startConversation()

// Non-streaming response
let response = try await agent.send(message, conversationId: conversationId)
print("Response: \(response.outputText)")

// Streaming response with semantic events
for try await chunk in agent.send(message, streaming: true, conversationId: conversationId) {
    switch chunk.type {
    case .outputTextDelta:
        print(chunk.delta?.outputText ?? "", terminator: "")
    case .webSearchCall:
        print("\n🔍 Searching web...")
    case .imageGeneration:
        print("\n🎨 Generating image...")
    case .codeInterpreterCall:
        print("\n💻 Running code...")
    default:
        break
    }
}
```

### Custom Tool Call Handling (Using Proven Agent Pattern)

```swift
// Custom tools registered using existing ToolRegistry system
let agent = ResponseAgent(
    llm: OpenAIProvider(model: OpenAIModels.gpt4o),
    tools: [WeatherTool.self, CalculatorTool.self, SearchTool.self]
)

// Non-streaming: Custom tools validated and executed using baseline Agent pattern
let response = try await agent.send("What's the weather in Paris and calculate 15 * 23?")
print("Final response with tool results: \(response.outputText)")

// Streaming: Custom tool calls with parameter validation
for try await chunk in agent.send("Calculate 15 * 23 and search for Paris weather", streaming: true) {
    switch chunk.type {
    case .outputTextDelta:
        print(chunk.delta?.outputText ?? "", terminator: "")
        
    case .functionCall:
        // Custom tool call intercepted by ResponseAgent
        if let toolCall = chunk.functionCall {
            print("\n🔧 Calling \(toolCall.name) with args: \(toolCall.arguments)")
            // ResponseAgent will use validateAndSetParameters() internally
        }
        
    case .functionCallOutput:
        // Custom tool execution completed using Agent pattern
        if let output = chunk.functionCallOutput {
            print("\n✅ Tool result: \(output.output)")
        }
        
    case .webSearchCall:
        print("\n🔍 Built-in web search...")
        
    case .codeInterpreterCall:
        print("\n💻 Built-in code interpreter...")
        
    default:
        break
    }
}

// Internal tool execution flow (same as baseline Agent):
// 1. User message → ResponseAgent converts tools using Tool.jsonSchema()
// 2. OpenAI API calls function → sends functionCall chunk with arguments
// 3. ResponseAgent intercepts and executes:
//    - Find tool: ToolRegistry.toolType(forName: toolName)
//    - Create: var tool = toolType.init()
//    - Validate: tool = try tool.validateAndSetParameters(argumentsData)
//    - Execute: let (response, metadata) = try await tool.execute()
// 4. Send results back to API → continue with final response
```

### Background Task Processing
```swift
// Long-running task with state management
let task = try await agent.task(message, conversationId: conversationId)

// Monitor task state
for await state in task.stateStream {
    switch state {
    case .queued:
        print("Task queued...")
    case .inProgress(let progress):
        print("Task progress: \(progress.percentage)%")
    case .completed(let result):
        print("Task completed: \(result.outputText)")
        break
    case .failed(let error):
        print("Task failed: \(error.localizedDescription)")
        break
    }
}
```

### Conversation Management
```swift
// List all conversations
let conversations = try await agent.listConversations()
print("Found \(conversations.count) conversations")

// Continue existing conversation
agent.continueConversation(id: "previous-conversation-id")

// Simple text message (convenience method)
let quickResponse = try await agent.send("What's the weather like?", conversationId: conversationId)

// Delete conversation
try await agent.deleteConversation(id: conversationId)
```
- [ ] Test throughput for background task processing
- [ ] Benchmark tool execution performance

## Decision Authority

### Independent Decisions (Proceed Autonomously)
- Implementation details of internal methods
- Error message formatting
- Internal state management structure
- Test structure and organization
- Documentation organization

### Requires User Input
- Future roadmap for ResponseAgent vs. Agent coexistence
- Storage backend prioritization (local/cloud/database)
- Performance benchmarking criteria and targets
- Documentation scope and migration examples

## Questions/Uncertainties

### Blocking Questions ✅ RESOLVED
1. **Tool Mixing Strategy**: ✅ Allow both, warn users about conflicts
2. **Background Processing**: ✅ Separate `.task()` method for background processing
3. **Conversation Continuity**: ✅ Multi-conversation support with storage integration
4. **Error Recovery**: ✅ 100% Responses API native, retry with exponential backoff
5. **Send Method**: ✅ Parameter control `send(content, streaming: Bool)`
6. **Task State Management**: ✅ Detailed state + observable patterns for UI/UX
7. **Built-in Tools**: ✅ All tools available by default

### Non-Blocking Questions (Proceeding with Assumptions)
1. **Storage Default**: Assume in-memory storage as default, with pluggable backends
2. **Conversation Cleanup**: Assume automatic cleanup after configurable time period
3. **Tool Metadata Format**: Assume same metadata structure as current Agent
4. **Error Message Format**: Assume user-friendly error messages with retry suggestions
5. **Performance Targets**: Assume 2x improvement over Agent for multi-turn conversations

## Acceptable Tradeoffs

### For Implementation Speed
- Start with in-memory storage, add persistent backends iteratively
- Use existing Response API methods without modifications initially
- Implement basic conversation management first, add advanced features later
- Accept some performance overhead initially for multi-conversation management

### For User Experience
- Some storage backends may require additional setup/configuration
- Background task state management may be more complex than simple async calls
- Tool conflict warnings may require user intervention for resolution
- Multi-conversation management adds API surface complexity

### For Compatibility
- ResponseAgent is OpenAI-only (no fallback to other providers)
- Some advanced Response API features may not have Agent equivalents
- Storage abstraction may not cover all possible backend requirements initially

## Status
Ready to Implement ✅

## Notes
- **100% Responses API Native**: No Chat Completions API dependencies or fallbacks
- **Multi-Conversation First**: Built from ground up for handling multiple conversation threads
- **Modern UX Patterns**: Parameter-controlled streaming, observable state, detailed task management
- **Tool-First Design**: All built-in tools available by default, seamless tool execution orchestration
- **Storage Agnostic**: Pluggable storage abstraction for different persistence needs
- **Performance Focused**: Leverage stateful API advantages for better performance than Agent
- **Production Ready**: Comprehensive error handling, retry logic, and state management 