# AISDK Usage Guide

A comprehensive, easy-to-follow guide for building AI-powered Swift applications with AISDK.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core Concepts](#core-concepts)
3. [Basic Agent Usage](#basic-agent-usage)
4. [Working with Tools](#working-with-tools)
5. [Chat Management](#chat-management)
6. [Voice Interactions](#voice-interactions)
7. [Vision Features](#vision-features)
8. [Research Capabilities](#research-capabilities)
9. [Storage & Persistence](#storage--persistence)
10. [Error Handling](#error-handling)
11. [Best Practices](#best-practices)
12. [Common Patterns](#common-patterns)
13. [Troubleshooting](#troubleshooting)

## Quick Start

### Installation

Add AISDK to your Swift package or Xcode project:

**Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/yourusername/AISDK.git", from: "1.0.0")
]

targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "AISDK", package: "AISDK"),           // Required
            .product(name: "AISDKChat", package: "AISDK"),       // Optional
            .product(name: "AISDKVoice", package: "AISDK"),      // Optional
            .product(name: "AISDKVision", package: "AISDK"),     // Optional
            .product(name: "AISDKResearch", package: "AISDK"),   // Optional
        ]
    )
]
```

**Xcode:**
1. File → Add Package Dependencies
2. Enter: `https://github.com/yourusername/AISDK.git`
3. Select the products you need

### Environment Setup

**Option 1: Environment Variables (Recommended)**
```bash
export OPENAI_API_KEY="your-openai-key-here"
export ANTHROPIC_API_KEY="your-anthropic-key-here"
export GOOGLE_API_KEY="your-gemini-key-here"
```

**Option 2: Runtime Configuration**
```swift
// Provider-centric approach with explicit API keys
let openai = OpenAIProvider(apiKey: "your-openai-key")
let anthropic = AnthropicService(apiKey: "your-anthropic-key")
let gemini = GeminiProvider(apiKey: "your-gemini-key")

// Create agents with specific providers
let agent = Agent(llm: openai)
```

### 5-Minute Example

```swift
import AISDK

// 1. Create an agent with provider (uses smart default: gpt-4o)
let openai = OpenAIProvider()
let agent = Agent(llm: openai)

// 2. Send a simple message
let response = try await agent.send("Hello, world!")
print(response.displayContent)

// 3. Stream responses for better UX
let userMessage = ChatMessage(message: .user(content: .text("Tell me a joke")))
for try await chunk in agent.sendStream(userMessage) {
    print(chunk.displayContent, terminator: "")
}
print() // New line after streaming
```

## Core Concepts

### Understanding AISDK Architecture

AISDK is built around several key concepts:

**🤖 Agent**: The main orchestrator that manages conversations with AI models
**🏗️ LLM Providers**: Direct interfaces to OpenAI, Anthropic, and Gemini APIs
**🛠️ Tools**: Functions the AI can call to perform specific tasks
**💬 ChatManager**: Handles session management and storage
**🗣️ VoiceMode**: Manages speech recognition and synthesis
**👁️ Vision**: Real-time video interactions with AI
**🔬 Research**: Specialized research capabilities

### Provider-Centric Architecture

AISDK uses a provider-centric approach where you create specific provider instances and pass them to agents:

```swift
// Create provider with smart defaults
let openai = OpenAIProvider()        // Uses gpt-4o by default
let anthropic = AnthropicService()   // Uses sonnet-3.7 by default
let gemini = GeminiProvider()        // Uses gemini-2.5-flash by default

// Create agents that use these providers
let agent = Agent(llm: openai)
```

This approach provides:
- **Smart Defaults**: Each provider has an optimal default model
- **Type Safety**: Provider-specific model enums prevent configuration errors
- **Easy Switching**: Change providers without changing agent code
- **Model Flexibility**: Override defaults with specific models when needed

### Modular Design

```swift
// Core - Always required
import AISDK

// Optional modules based on your needs
import AISDKChat      // For chat UI and session management
import AISDKVoice     // For voice interactions
import AISDKVision    // For video/camera features
import AISDKResearch  // For research capabilities
```

## Direct LLM Usage

AISDK provides direct access to LLM providers for when you need lower-level control over AI interactions. This is useful for custom workflows, testing, or when you don't need the full Agent system.

### Available LLM Providers

```swift
import AISDK

// OpenAI Provider
let openAIProvider = OpenAIProvider(apiKey: "your-openai-key")

// Claude Provider
let claudeProvider = ClaudeProvider(apiKey: "your-claude-key")

// Using environment variables (recommended)
let openAIProvider = OpenAIProvider(apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "")
```

### Basic Chat Completion

```swift
// Simple text completion
let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .system(content: .text("You are a helpful assistant.")),
        .user(content: .text("What is the capital of France?"))
    ],
    maxTokens: 100,
    temperature: 0.7
)

let response = try await openAIProvider.sendChatCompletion(request: request)

if let content = response.choices.first?.message.content {
    print("Response: \(content)")
    print("Tokens used: \(response.usage?.totalTokens ?? 0)")
}
```

### Streaming Responses

Stream responses for better user experience:

```swift
let streamRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [.user(content: .text("Tell me a story"))],
    maxTokens: 200,
    stream: true
)

print("Story: ", terminator: "")
for try await chunk in try await openAIProvider.sendChatCompletionStream(request: streamRequest) {
    if let content = chunk.choices.first?.delta.content {
        print(content, terminator: "")
        fflush(stdout) // Flush output for real-time display
    }
}
print() // New line when done
```

### Multimodal Inputs (Vision)

Send images along with text:

```swift
// With image URL
let imageRequest = ChatCompletionRequest(
    model: "gpt-4o", // Vision-capable model
    messages: [
        .user(content: .parts([
            .text("What do you see in this image?"),
            .imageURL(.url(URL(string: "https://example.com/image.jpg")!))
        ]))
    ]
)

// With base64 image data
let imageData = // ... your image data
let base64Request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .user(content: .parts([
            .text("Analyze this image"),
            .imageURL(.base64(imageData), detail: .high)
        ]))
    ]
)

let response = try await openAIProvider.sendChatCompletion(request: base64Request)
```

### JSON Mode & Structured Outputs

Get structured JSON responses:

```swift
// Simple JSON mode
let jsonRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .system(content: .text("Return valid JSON only")),
        .user(content: .text("List 3 programming languages with their main uses"))
    ],
    responseFormat: .jsonObject
)

let jsonResponse = try await openAIProvider.sendChatCompletion(request: jsonRequest)
if let jsonContent = jsonResponse.choices.first?.message.content {
    let data = jsonContent.data(using: .utf8)!
    let parsed = try JSONSerialization.jsonObject(with: data)
    print("Parsed JSON: \(parsed)")
}
```

### Schema-Validated Structured Output

Use AISDK's JSON schema system for type-safe responses:

```swift
// Define your data model with automatic enum validation
enum ProductCategory: String, CaseIterable, Codable {
    case electronics = "Electronics"
    case clothing = "Clothing"
    case books = "Books"
    case home = "Home"
}

struct Product: JSONSchemaModel, Codable {
    @Field(description: "Product name")
    var name: String = ""
    
    @Field(description: "Price in dollars", validation: ["minimum": 0])
    var price: Double = 0.0
    
    // ✨ Automatic enum validation - no validation dictionary needed!
    @Field(description: "Product category")
    var category: ProductCategory = .electronics
    
    @Field(description: "Whether the product is in stock")
    var inStock: Bool = false
    
    init() {}
}

// Request with JSON Schema validation
let schemaRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .user(content: .text("Generate a laptop product with realistic data"))
    ],
    responseFormat: .jsonSchema(
        name: "product",
        description: "A product with details",
        schemaBuilder: Product.schema(),
        strict: true
    )
)

// Get type-safe response
let product: Product = try await openAIProvider.generateObject(request: schemaRequest)
print("Product: \(product.name), Price: $\(product.price), Category: \(product.category.rawValue)")
```

### Tool Calling (Function Calling)

Use tools directly with LLMs:

```swift
// Define a simple tool
struct WeatherTool: AITool {
    let name = "get_weather"
    let description = "Get current weather for a city"

    enum TemperatureUnit: String, Codable, CaseIterable {
        case celsius
        case fahrenheit
    }
    
    @AIParameter(description: "City name")
    var city: String = ""
    
    @AIParameter(description: "Temperature unit")
    var unit: TemperatureUnit = .fahrenheit
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        // Your weather API call here
        return AIToolResult(content: "Weather in \(city): 72°F, sunny")
    }
}

// Request with tool available
let toolRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .user(content: .text("What's the weather in Boston?"))
    ],
    tools: [WeatherTool.jsonSchema()],
    toolChoice: .auto
)

let toolResponse = try await openAIProvider.sendChatCompletion(request: toolRequest)

// Handle tool calls
if let toolCalls = toolResponse.choices.first?.message.toolCalls {
    for toolCall in toolCalls {
        if let function = toolCall.function {
            print("Tool called: \(function.name)")
            print("Arguments: \(function.arguments)")
            
            // Execute the tool
            let jsonData = function.arguments.data(using: .utf8)!
            var tool = WeatherTool()
            tool = try tool.validateAndSetParameters(jsonData)
            let (result, _) = try await tool.execute()
            print("Result: \(result)")
        }
    }
}
```

### Model-Specific Features

#### OpenAI-Specific

```swift
// o4-mini model with reasoning tokens
let reasoningRequest = ChatCompletionRequest(
    model: "o4-mini",
    messages: [.user(content: .text("Solve this complex problem step by step"))],
    maxCompletionTokens: 1000, // Use maxCompletionTokens for o4-mini
    reasoningEffort: "high"
)

// With function calling
let functionRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [.user(content: .text("Calculate 15 * 23"))],
    tools: [CalculatorTool.jsonSchema()],
    parallelToolCalls: true
)
```

#### Claude-Specific

```swift
// Claude with extended thinking (if supported)
let claudeRequest = ChatCompletionRequest(
    model: "claude-3-5-sonnet-20241022",
    messages: [.user(content: .text("Analyze this complex scenario"))],
    maxTokens: 1000,
    temperature: 0.7 // Claude caps at 1.0
)

// Use Claude provider's extended thinking feature
let extendedRequest = claudeProvider.withExtendedThinking(
    request: claudeRequest,
    budgetTokens: 2000
)
```

### Conversation Management

Build conversational flows:

```swift
var conversationHistory: [Message] = [
    .system(content: .text("You are a helpful coding assistant."))
]

func sendMessage(_ userInput: String) async throws -> String {
    // Add user message
    conversationHistory.append(.user(content: .text(userInput)))
    
    let request = ChatCompletionRequest(
        model: "gpt-4o",
        messages: conversationHistory,
        maxTokens: 150
    )
    
    let response = try await openAIProvider.sendChatCompletion(request: request)
    
    if let content = response.choices.first?.message.content {
        // Add assistant response to history
        conversationHistory.append(.assistant(content: .text(content)))
        return content
    }
    
    throw AISDKError.custom("No response content")
}

// Usage
let response1 = try await sendMessage("What's a good programming language for beginners?")
let response2 = try await sendMessage("How do I get started with that language?")
```

### Error Handling with LLMs

```swift
do {
    let response = try await openAIProvider.sendChatCompletion(request: request)
    // Handle response
} catch let error as AISDKError {
    switch error {
    case .httpError(let code, let message):
        print("HTTP Error \(code): \(message)")
        if code == 429 {
            // Rate limit - implement retry with backoff
        }
    case .parsingError(let details):
        print("Failed to parse response: \(details)")
    case .streamError(let details):
        print("Streaming failed: \(details)")
    default:
        print("Other error: \(error.localizedDescription)")
    }
} catch {
    print("Unexpected error: \(error)")
}
```

### Performance Tips for Direct LLM Usage

```swift
// 1. Use appropriate models for tasks
let fastModel = "gpt-4o-mini"     // For simple tasks
let smartModel = "gpt-4o"         // For complex reasoning
let visionModel = "gpt-4o"        // For image analysis

// 2. Set reasonable token limits
let request = ChatCompletionRequest(
    model: fastModel,
    messages: messages,
    maxTokens: 100  // Adjust based on expected response length
)

// 3. Use streaming for long responses
let streamingRequest = ChatCompletionRequest(
    model: smartModel,
    messages: messages,
    maxTokens: 500,
    stream: true
)

// 4. Implement request caching for repeated queries
private var responseCache: [String: String] = [:]

func getCachedResponse(for prompt: String) async throws -> String {
    if let cached = responseCache[prompt] {
        return cached
    }
    
    let response = try await sendRequest(prompt)
    responseCache[prompt] = response
    return response
}
```

## Basic Agent Usage

### Creating an Agent (Provider-Centric Approach)

```swift
import AISDK

// Basic agent with OpenAI (uses smart default: gpt-4o)
let openai = OpenAIProvider()
let agent = Agent(llm: openai)

// Agent with system instructions
let openai = OpenAIProvider()
let agent = Agent(
    llm: openai,
    instructions: "You are a helpful coding assistant."
)

// Agent with tools
let openai = OpenAIProvider()
let agent = Agent(
    llm: openai,
    tools: [WeatherTool.self, CalculatorTool.self]
)

// Agent with specific model
let openaiMini = OpenAIProvider(model: OpenAIModels.gpt4oMini)
let agent = Agent(llm: openaiMini)
```

### Available Providers and Models

```swift
// OpenAI Provider
let openai = OpenAIProvider() // Uses gpt-4o by default
let openaiMini = OpenAIProvider(model: OpenAIModels.gpt4oMini)
let openaiO3 = OpenAIProvider(model: OpenAIModels.o3)

// Anthropic Provider  
let anthropic = AnthropicService() // Uses sonnet-3.7 by default
let anthropicSonnet4 = AnthropicService(model: AnthropicModels.sonnet4)

// Gemini Provider
let gemini = GeminiProvider() // Uses gemini-2.5-flash by default
let geminiPro = GeminiProvider(model: GeminiModels.gemini25Pro)

// Create agents with any provider
let openaiAgent = Agent(llm: openai)
let claudeAgent = Agent(llm: anthropic)
let geminiAgent = Agent(llm: gemini)
```

### Legacy Approach (Still Supported)

```swift
// Legacy model-based initialization - deprecated but functional
let agent = Agent(
    model: AgenticModels.gpt4,
    instructions: "You are a helpful assistant."
)
```

### Sending Messages

#### Simple Text Messages

```swift
let response = try await agent.send("What's the weather like?")
print(response.displayContent)
```

#### Streaming Responses

```swift
let message = ChatMessage(message: .user(content: .text("Tell me a story")))

for try await chunk in agent.sendStream(message) {
    print(chunk.displayContent, terminator: "")
}
```

#### With Required Tool

```swift
let message = ChatMessage(message: .user(content: .text("What's the weather in Paris?")))

// Force the agent to use a specific tool
for try await response in agent.sendStream(message, requiredTool: "get_weather") {
    print(response.displayContent)
}
```

### Agent State Monitoring

```swift
agent.onStateChange = { state in
    switch state {
    case .idle:
        print("Agent is ready")
    case .thinking:
        print("Agent is thinking...")
    case .executingTool(let toolName):
        print("Executing \(toolName)...")
    case .responding:
        print("Generating response...")
    case .error(let error):
        print("Error: \(error.localizedDescription)")
    }
}
```

## Working with Tools

### Creating a Basic Tool

```swift
import AISDK

struct CalculatorTool: AITool {
    let name = "calculator"
    let description = "Perform basic mathematical calculations"
    
    @AIParameter(description: "First number")
    var a: Double = 0
    
    @AIParameter(description: "Second number") 
    var b: Double = 0
    
    enum Operation: String, Codable, CaseIterable {
        case add
        case subtract
        case multiply
        case divide
    }

    @AIParameter(description: "Operation to perform")
    var operation: Operation = .add
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        let result: Double
        
        switch operation {
        case .add: result = a + b
        case .subtract: result = a - b
        case .multiply: result = a * b
        case .divide:
            guard b != 0 else { throw ToolError.executionFailed("Division by zero") }
            result = a / b
        }
        
        return AIToolResult(content: "The result is \(result)")
    }
}
```

### Creating a Renderable Tool

```swift
import AISDK
import SwiftUI
import Charts

struct ChartTool: RenderableTool {
    let name = "create_chart"
    let description = "Create a visual chart from data"
    
    @AIParameter(description: "Chart title")
    var title: String = ""
    
    @AIParameter(description: "Data points as JSON array")
    var data: String = ""
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        // Parse the data
        guard let jsonData = data.data(using: .utf8),
              let chartData = try? JSONDecoder().decode(ChartData.self, from: jsonData) else {
            throw ToolError.invalidParameters("Invalid JSON data")
        }
        
        // Create metadata for rendering
        let metadata = RenderMetadata(toolName: name, jsonData: jsonData)
        
        return AIToolResult(
            content: "Created chart '\(title)' with \(chartData.points.count) data points",
            metadata: metadata
        )
    }
    
    func render(from data: Data) -> AnyView {
        guard let chartData = try? JSONDecoder().decode(ChartData.self, from: data) else {
            return AnyView(Text("Failed to load chart data"))
        }
        
        return AnyView(
            VStack {
                Text(chartData.title)
                    .font(.headline)
                    .padding()
                
                Chart(chartData.points, id: \.label) { point in
                    BarMark(
                        x: .value("Category", point.label),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(.blue)
                }
                .frame(height: 200)
                .padding()
            }
        )
    }
}

struct ChartData: Codable {
    let title: String
    let points: [DataPoint]
    
    struct DataPoint: Codable {
        let label: String
        let value: Double
    }
}
```

### Using Tools with Agent

```swift
// Register tools with agent
let agent = try Agent(
    model: AgenticModels.gpt4,
    tools: [CalculatorTool.self, ChartTool.self]
)

// Agent will automatically use tools when needed
let response = try await agent.send("Calculate 15 * 23 and show the result in a chart")
```

## Chat Management

### Basic Chat Setup

```swift
import AISDK
import AISDKChat

// Create chat manager with provider-centric approach
let openai = OpenAIProvider()
let agent = Agent(llm: openai)
let storage = MemoryStorage() // or your custom storage
let chatManager = AIChatManager(agent: agent, storage: storage)

// Create a new session
await chatManager.createNewSession(title: "My First Chat")

// Send messages
await chatManager.sendMessage([.text("Hello!")])
```

### Using in SwiftUI

```swift
import SwiftUI
import AISDKChat

struct ChatView: View {
    @State private var chatManager: AIChatManager
    
    init() {
        let openai = OpenAIProvider()
        let agent = Agent(llm: openai)
        let storage = MemoryStorage()
        _chatManager = State(wrappedValue: AIChatManager(agent: agent, storage: storage))
    }
    
    var body: some View {
        AIConversationView(manager: chatManager)
    }
}
```

### Managing Sessions

```swift
// Load existing sessions
try await chatManager.loadChatSessions()

// Create new session with custom title
await chatManager.createNewSession(title: "Code Review Session")

// Switch to a specific session
chatManager.currentSession = chatManager.chatSessions.first

// Delete a session
if let session = chatManager.currentSession {
    try await chatManager.deleteSession(session)
}
```

### Working with Attachments

```swift
// Send message with image
let imageData = // ... your image data
let imagePart = UserContent.Part.imageURL(.base64(imageData))
await chatManager.sendMessage([.text("What's in this image?"), imagePart])

// Send message with document
let documentURL = // ... your document URL
let attachment = Attachment(url: documentURL, name: "document.pdf", type: .pdf)
await chatManager.sendMessage([.text("Analyze this document")], attachments: [attachment])
```

## Voice Interactions

### Basic Voice Setup

```swift
import AISDKVoice

@State private var voiceMode = AIVoiceMode()

// Request permissions
let hasPermission = try await SpeechRecognizer.requestAuthorization()
guard hasPermission else { return }

// Start voice conversation  
let openai = OpenAIProvider()
let agent = Agent(llm: openai)
try await voiceMode.startConversation(with: agent)
```

### Voice UI Components

```swift
import SwiftUI
import AISDKVoice

struct VoiceChatView: View {
    let agent: Agent
    
    var body: some View {
        AIVoiceModeView(agent: agent)
    }
}
```

### Custom Voice Controls

```swift
struct CustomVoiceView: View {
    @StateObject private var voiceMode = AIVoiceMode()
    
    var body: some View {
        VStack {
            // Audio level indicator
            ProgressView(value: voiceMode.audioLevel)
                .progressViewStyle(LinearProgressViewStyle())
            
            // Transcript display
            Text(voiceMode.transcript)
                .padding()
            
            // Record button
            Button(voiceMode.isRecording ? "Stop" : "Record") {
                if voiceMode.isRecording {
                    Task { try await voiceMode.stopRecording() }
                } else {
                    Task { try await voiceMode.startRecording() }
                }
            }
            .disabled(voiceMode.isProcessing)
        }
    }
}
```

### Voice Settings

```swift
// Configure voice settings
voiceMode.settings = VoiceSettings(
    locale: Locale(identifier: "en-US"),
    voice: "com.apple.ttsbundle.Samantha-compact",
    speechRate: 0.5,
    pitchMultiplier: 1.0,
    preDelay: 0.5,
    postDelay: 1.0
)
```

## Vision Features

### Basic Vision Setup

```swift
import AISDKVision

// LiveKit connection details
let connectionDetails = ConnectionDetails(
    serverUrl: "wss://your-livekit-server.com",
    token: "your-jwt-token",
    roomName: "vision-room"
)

// Vision camera view
struct VisionView: View {
    var body: some View {
        VisionCameraView(connectionDetails: connectionDetails)
    }
}
```

### Agent Integration

```swift
struct VisionAgentView: View {
    let agent: Agent
    @StateObject private var chatContext = ChatContext()
    
    var body: some View {
        AgentView(agent: agent, chatContext: chatContext)
    }
}
```

## Research Capabilities

### Basic Research Agent

```swift
import AISDKResearch

// Create research agent
let openai = OpenAIProvider()
let researcher = try ResearcherAgent(llm: openai)

// Conduct research
let result = try await researcher.research(
    topic: "Swift concurrency best practices",
    sources: ["academic", "web", "documentation"],
    depth: .comprehensive
)

print("Summary: \(result.summary)")
print("Key Findings:")
result.keyFindings.forEach { finding in
    print("- \(finding.text)")
}
```

### Custom Research Tools

```swift
struct WebSearchTool: AITool {
    let name = "web_search"
    let description = "Search the web for information"
    
    @AIParameter(description: "Search query")
    var query: String = ""
    
    @AIParameter(description: "Number of results", validation: ["minimum": 1, "maximum": 10])
    var maxResults: Int = 5
    
    func execute() async throws -> AIToolResult {
        // Implement web search logic
        let results = try await performWebSearch(query: query, maxResults: maxResults)
        
        let metadata = ResearchMetadata(
            sources: results.map { Source(url: $0.url, title: $0.title, type: .web) },
            evidenceLevel: "web",
            confidence: 0.7,
            citations: []
        )
        
        return (formatResults(results), metadata)
    }
}
```

## Storage & Persistence

### Memory Storage (Default)

```swift
let storage = MemoryStorage()
let chatManager = AIChatManager(agent: agent, storage: storage)
```

### Custom Storage Implementation

```swift
class CloudStorage: ChatStorageProtocol {
    private let apiClient: APIClient
    
    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }
    
    func save(session: ChatSession) async throws {
        try await apiClient.saveSession(session)
    }
    
    func load(id: String) async throws -> ChatSession? {
        return try await apiClient.loadSession(id: id)
    }
    
    func delete(id: String) async throws {
        try await apiClient.deleteSession(id: id)
    }
    
    func list() async throws -> [ChatSession] {
        return try await apiClient.listSessions()
    }
    
    // Implement other required methods...
}
```

### Firebase Storage Example

```swift
import FirebaseFirestore

class FirebaseStorage: ChatStorageProtocol {
    private let db = Firestore.firestore()
    private let collection = "chat_sessions"
    
    func save(session: ChatSession) async throws {
        let data = try JSONEncoder().encode(session)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        
        if let id = session.id {
            try await db.collection(collection).document(id).setData(dict)
        } else {
            let ref = db.collection(collection).document()
            session.id = ref.documentID
            try await ref.setData(dict)
        }
    }
    
    func load(id: String) async throws -> ChatSession? {
        let document = try await db.collection(collection).document(id).getDocument()
        
        guard let data = document.data() else { return nil }
        
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        return try JSONDecoder().decode(ChatSession.self, from: jsonData)
    }
    
    // Implement other methods...
}
```

## Error Handling

### Common Error Types

```swift
do {
    let response = try await agent.send("Hello")
} catch let error as AgentError {
    switch error {
    case .invalidModel:
        print("Invalid model configuration")
    case .missingAPIKey:
        print("API key not found")
    case .toolExecutionFailed(let message):
        print("Tool failed: \(message)")
    case .operationCancelled:
        print("Operation was cancelled")
    default:
        print("Agent error: \(error.localizedDescription)")
    }
} catch let error as ToolError {
    switch error {
    case .invalidParameters(let message):
        print("Invalid tool parameters: \(message)")
    case .executionFailed(let message):
        print("Tool execution failed: \(message)")
    default:
        print("Tool error: \(error.localizedDescription)")
    }
} catch {
    print("Unexpected error: \(error.localizedDescription)")
}
```

### Retry Logic

```swift
func sendWithRetry(_ message: String, maxRetries: Int = 3) async throws -> ChatMessage {
    var lastError: Error?
    
    for attempt in 1...maxRetries {
        do {
            return try await agent.send(message)
        } catch let error as AISDKError {
            lastError = error
            
            // Only retry on certain errors
            switch error {
            case .networkError, .rateLimitExceeded:
                let delay = TimeInterval(attempt * 2) // Exponential backoff
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            default:
                throw error
            }
        }
    }
    
    throw lastError ?? AISDKError.networkError("Max retries exceeded")
}
```

## Best Practices

### 1. Provider and Model Selection

```swift
// For general chat applications - OpenAI with smart defaults
let openai = OpenAIProvider()
let chatAgent = Agent(llm: openai)

// For tool-heavy applications - OpenAI excels at function calling
let openaiProvider = OpenAIProvider(model: OpenAIModels.gpt4o)
let toolAgent = Agent(llm: openaiProvider)

// For faster, cost-effective responses
let openaiMini = OpenAIProvider(model: OpenAIModels.gpt4oMini)
let fastAgent = Agent(llm: openaiMini)

// For complex reasoning tasks - Anthropic Claude
let anthropic = AnthropicService(model: AnthropicModels.sonnet37)
let reasoningAgent = Agent(llm: anthropic)

// For multimodal tasks - Gemini  
let gemini = GeminiProvider(model: GeminiModels.gemini25Pro)
let multimodalAgent = Agent(llm: gemini)
```

### 2. Memory Management

```swift
// Clear conversation history periodically
if agent.messages.count > 100 {
    // Keep system message and last 20 messages
    let systemMessages = agent.messages.filter { 
        if case .system = $0.message { return true }
        return false
    }
    let recentMessages = Array(agent.messages.suffix(20))
    agent.setMessages(systemMessages + recentMessages)
}
```

### 3. Tool Design

```swift
// ✅ Good: Specific, focused tool
struct GetWeatherTool: AITool {
    let name = "get_weather"
    let description = "Get current weather for a specific location"
    
    @AIParameter(description: "City name")
    var city: String = ""
    
    // Implementation...
}

// ❌ Avoid: Overly broad tool
struct UniversalTool: AITool {
    let name = "do_everything"
    let description = "Does everything you need"
    
    @AIParameter(description: "What to do")
    var action: String = ""
    
    // Too broad, hard for LLM to use correctly
}
```

### 4. Error Recovery

```swift
agent.onStateChange = { state in
    if case .error(let error) = state {
        // Log error for debugging
        print("Agent error: \(error)")
        
        // Potentially recover or show user-friendly message
        DispatchQueue.main.async {
            // Update UI to show error state
        }
    }
}
```

### 5. Performance Optimization

```swift
// Use streaming for better user experience
for try await chunk in agent.sendStream(message) {
    DispatchQueue.main.async {
        // Update UI immediately with each chunk
        self.updateUI(with: chunk)
    }
}

// Batch similar operations
let messages = [
    ChatMessage(message: .user(content: .text("Question 1"))),
    ChatMessage(message: .user(content: .text("Question 2"))),
    ChatMessage(message: .user(content: .text("Question 3")))
]

// Instead of sending one by one, combine context
let combinedMessage = ChatMessage(message: .user(content: .text("""
Please answer these questions:
1. \(messages[0].displayContent)
2. \(messages[1].displayContent)  
3. \(messages[2].displayContent)
""")))
```

## Common Patterns

### 1. Chat Bot with Tools

```swift
struct ChatBot {
    private let agent: Agent
    
    init() {
        let openai = OpenAIProvider()
        self.agent = Agent(
            llm: openai,
            tools: [
                WeatherTool.self,
                CalculatorTool.self,
                SearchTool.self
            ],
            instructions: """
            You are a helpful assistant with access to various tools.
            Use tools when appropriate to provide accurate information.
            Always be conversational and helpful.
            """
        )
    }
    
    func respond(to message: String) async throws -> String {
        let response = try await agent.send(message)
        return response.displayContent
    }
}
```

### 2. Document Analysis Agent

```swift
struct DocumentAnalyzer {
    private let agent: Agent
    
    init() {
        let openai = OpenAIProvider()
        self.agent = Agent(
            llm: openai,
            tools: [PDFReaderTool.self, SummarizerTool.self],
            instructions: """
            You are a document analysis expert. 
            Analyze documents thoroughly and provide structured insights.
            """
        )
    }
    
    func analyze(document: URL) async throws -> DocumentAnalysis {
        let message = ChatMessage(message: .user(content: .text("Analyze this document")))
        // Add document as attachment
        let attachment = Attachment(url: document, name: document.lastPathComponent)
        message.attachments = [attachment]
        
        let response = try await agent.send("Analyze the attached document")
        return DocumentAnalysis(summary: response.displayContent)
    }
}
```

### 3. Multi-Modal Agent

```swift
struct MultiModalAgent {
    private let agent: Agent
    
    init() {
        // Use OpenAI for vision capabilities
        let openai = OpenAIProvider(model: OpenAIModels.gpt4o) // Vision-capable model
        self.agent = Agent(
            llm: openai,
            tools: [ImageAnalysisTool.self, TextToSpeechTool.self]
        )
    }
    
    func processImage(_ imageData: Data, question: String) async throws -> String {
        let imagePart = UserContent.Part.imageURL(.base64(imageData))
        let textPart = UserContent.Part.text(question)
        
        // Create message with both text and image
        let content = UserContent.parts([textPart, imagePart])
        let message = ChatMessage(message: .user(content: content))
        
        let response = try await agent.send(question)
        return response.displayContent
    }
}
```

### 4. Streaming Chat Interface

```swift
struct StreamingChatView: View {
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isStreaming = false
    
    private let agent: Agent
    
    var body: some View {
        VStack {
            ScrollView {
                LazyVStack {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                    }
                }
            }
            
            HStack {
                TextField("Type a message...", text: $inputText)
                
                Button("Send") {
                    sendMessage()
                }
                .disabled(inputText.isEmpty || isStreaming)
            }
            .padding()
        }
    }
    
    private func sendMessage() {
        let userMessage = ChatMessage(message: .user(content: .text(inputText)))
        messages.append(userMessage)
        
        let messageText = inputText
        inputText = ""
        isStreaming = true
        
        Task {
            var responseContent = ""
            let responseMessage = ChatMessage(message: .assistant(content: .text("")))
            responseMessage.isPending = true
            
            await MainActor.run {
                messages.append(responseMessage)
            }
            
            do {
                for try await chunk in agent.sendStream(userMessage) {
                    responseContent = chunk.displayContent
                    
                    await MainActor.run {
                        if let index = messages.firstIndex(where: { $0.id == responseMessage.id }) {
                            messages[index] = ChatMessage(message: .assistant(content: .text(responseContent)))
                        }
                    }
                }
                
                await MainActor.run {
                    isStreaming = false
                }
            } catch {
                await MainActor.run {
                    // Handle error
                    isStreaming = false
                }
            }
        }
    }
}
```

## Troubleshooting

### Common Issues

#### 1. "Missing API Key" Error

**Problem**: `AgentError.missingAPIKey` when creating an agent.

**Solutions**:
```swift
// Check environment variables
print("OpenAI Key:", ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "Not found")

// Set API key manually
var model = AgenticModels.gpt4
model.apiKey = "your-api-key-here"
let agent = try Agent(model: model)
```

#### 2. Tool Execution Failures

**Problem**: Tools fail with parameter validation errors.

**Solutions**:
```swift
// Enable debug logging for tools
print("Tool JSON Schema:")
print(YourTool.jsonSchema().prettyPrintJSON())

// Check parameter types match exactly
struct DebugTool: AITool {
    @AIParameter(description: "Must be string, not number")
    var city: String = ""  // ✅ Correct
    
    // var city: Int = 0   // ❌ Wrong type
}
```

#### 3. Streaming Connection Issues

**Problem**: Streaming responses fail or timeout.

**Solutions**:
```swift
// Add timeout handling
let timeoutTask = Task {
    try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
    throw AISDKError.streamError("Timeout")
}

let streamTask = Task {
    for try await chunk in agent.sendStream(message) {
        // Process chunk
    }
}

// Race the tasks
_ = try await [timeoutTask, streamTask].first { _ in true }
```

#### 4. Memory Issues with Long Conversations

**Problem**: App crashes or slows down with long chat histories.

**Solutions**:
```swift
// Implement conversation pruning
extension Agent {
    func pruneConversation(maxMessages: Int = 50) {
        guard messages.count > maxMessages else { return }
        
        // Keep system messages and recent messages
        let systemMessages = messages.filter { 
            if case .system = $0.message { return true }
            return false
        }
        let recentMessages = Array(messages.suffix(maxMessages - systemMessages.count))
        
        setMessages(systemMessages + recentMessages)
    }
}
```

#### 5. SwiftUI State Issues

**Problem**: UI doesn't update with streaming responses.

**Solutions**:
```swift
// Ensure updates happen on main thread
for try await chunk in agent.sendStream(message) {
    await MainActor.run {
        self.responseText = chunk.displayContent
    }
}

// Use @MainActor for your view model
@Observable
class ChatViewModel {
    var messages: [ChatMessage] = []
    
    func sendMessage(_ text: String) async {
        // This automatically runs on main thread
    }
}
```

### Performance Tips

#### 1. Choose the Right Provider and Model

```swift
// For simple tasks - faster and cheaper
let openaiMini = OpenAIProvider(model: OpenAIModels.gpt4oMini)
let quickAgent = Agent(llm: openaiMini)

// For complex reasoning - Anthropic Claude
let anthropic = AnthropicService(model: AnthropicModels.sonnet37)
let smartAgent = Agent(llm: anthropic)

// For tool-heavy workflows - OpenAI excels at function calling
let openai = OpenAIProvider(model: OpenAIModels.gpt4o)
let toolAgent = Agent(llm: openai)
```

#### 2. Optimize Tool Design

```swift
// ✅ Good: Focused, single-purpose tool
struct GetWeatherTool: AITool {
    let name = "get_weather"
    let description = "Get current weather for a specific city"
    
    @AIParameter(description: "City name")
    var city: String = ""
}

// ❌ Avoid: Overly broad tool
struct DoEverythingTool: AITool {
    let name = "do_everything"
    let description = "Handles all possible tasks"
    
    @AIParameter(description: "What to do")
    var task: String = ""
}
```

#### 3. Efficient Message Management

```swift
// Batch operations when possible
let combinedMessage = """
Please help me with these tasks:
1. Calculate 15 * 23
2. Get weather for Paris
3. Summarize the results
"""

// Instead of three separate API calls
let response = try await agent.send(combinedMessage)
```

### Debugging Tips

#### 1. Enable Detailed Logging

```swift
// Add to your agent initialization
agent.onStateChange = { state in
    print("Agent State: \(state)")
    
    switch state {
    case .executingTool(let name):
        print("Executing tool: \(name)")
    case .error(let error):
        print("Error details: \(error.localizedDescription)")
    default:
        break
    }
}
```

#### 2. Inspect Tool Schemas

```swift
// Print generated schemas for debugging
let schema = YourTool.jsonSchema()
if let data = try? JSONEncoder().encode(schema),
   let jsonString = String(data: data, encoding: .utf8) {
    print("Tool Schema:\n\(jsonString)")
}
```

#### 3. Monitor API Requests

```swift
// Log raw API requests (in development only)
let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted

if let requestData = try? encoder.encode(request),
   let requestString = String(data: requestData, encoding: .utf8) {
    print("API Request:\n\(requestString)")
}
```

### Getting Help

- **Documentation**: [Complete API Reference](APIReference.md)
- **Examples**: Check the `Examples/` directory in the repository
- **Issues**: Report bugs on [GitHub Issues](https://github.com/yourusername/AISDK/issues)
- **Discussions**: Join the [GitHub Discussions](https://github.com/yourusername/AISDK/discussions)
- **Discord**: [Community Discord Server](https://discord.gg/aisdk)

This comprehensive usage guide covers all essential patterns and best practices for using AISDK effectively. Each section includes practical examples that you can adapt to your specific use case. 
