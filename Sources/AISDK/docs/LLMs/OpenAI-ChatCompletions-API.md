# OpenAI Chat Completions API Usage Guide

This guide covers how to use OpenAI's Chat Completions API in AISDK. The Chat Completions API is OpenAI's primary conversational AI interface, supporting text, images, function calling, and structured outputs.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Basic Usage](#basic-usage)
- [Message Types](#message-types)
- [Multimodal Support](#multimodal-support)
- [Streaming](#streaming)
- [Function Calling](#function-calling)
- [Structured Outputs](#structured-outputs)
- [Advanced Features](#advanced-features)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)
- [Migration to Responses API](#migration-to-responses-api)

## Overview

The OpenAI Chat Completions API in AISDK provides:

- **Conversational AI**: Natural language conversations with GPT models
- **Multimodal Support**: Text, image, and file inputs 
- **Function Calling**: Custom tool integration with automatic schema generation
- **Streaming**: Real-time response streaming for better UX
- **Structured Outputs**: JSON mode and schema-validated responses
- **Fine-grained Control**: Temperature, tokens, penalties, and more
- **Multiple Models**: Support for GPT-4o, GPT-4, GPT-3.5-turbo, and specialized models

### Models Available

- **`gpt-4o`** - Latest multimodal model (text + vision)
- **`gpt-4o-mini`** - Faster, cost-effective version 
- **`gpt-4-turbo`** - High intelligence model
- **`gpt-3.5-turbo`** - Fast and economical
- **`o1-preview`** - Advanced reasoning model
- **`o1-mini`** - Faster reasoning model

## Quick Start

### Basic Setup

```swift
import AISDK

// Initialize your OpenAI provider
let provider = OpenAIProvider(apiKey: "your-openai-api-key")

// Create a simple chat request
let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .system(content: .text("You are a helpful assistant.")),
        .user(content: .text("What is the capital of France?"))
    ]
)

// Send the request
let response = try await provider.sendChatCompletion(request: request)

// Access the response
if let content = response.choices.first?.message.content {
    print("Response: \(content)")
    print("Tokens used: \(response.usage?.totalTokens ?? 0)")
}
```

### One-Line Quick Chat

```swift
// For simple questions without conversation history
let provider = OpenAIProvider(apiKey: "your-api-key")

let response = try await provider.sendChatCompletion(request: ChatCompletionRequest(
    model: "gpt-4o-mini",
    messages: [.user(content: .text("Explain quantum computing in one sentence"))]
))
```

## Basic Usage

### Creating Chat Requests

```swift
let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .system(content: .text("You are a helpful assistant that responds concisely.")),
        .user(content: .text("How do neural networks work?"))
    ],
    maxTokens: 150,        // Limit response length
    temperature: 0.7,      // Control creativity (0.0-2.0)
    topP: 0.9,            // Nucleus sampling parameter
    presencePenalty: 0.0,  // Reduce repetition
    frequencyPenalty: 0.0  // Reduce repetition based on frequency
)

let response = try await provider.sendChatCompletion(request: request)
```

### Response Structure

```swift
// Access the main response
let content = response.choices.first?.message.content
let finishReason = response.choices.first?.finishReason

// Check token usage
let usage = response.usage
print("Prompt tokens: \(usage?.promptTokens ?? 0)")
print("Completion tokens: \(usage?.completionTokens ?? 0)")
print("Total tokens: \(usage?.totalTokens ?? 0)")

// Response metadata
print("Model: \(response.model)")
print("ID: \(response.id)")
print("Created: \(Date(timeIntervalSince1970: TimeInterval(response.created)))")
```

### Conversation Management

```swift
// Maintain conversation history
var conversationHistory: [Message] = [
    .system(content: .text("You are a helpful coding assistant."))
]

// Function to send message and update history
func sendMessage(_ text: String) async throws -> String {
    // Add user message
    conversationHistory.append(.user(content: .text(text)))
    
    let request = ChatCompletionRequest(
        model: "gpt-4o",
        messages: conversationHistory,
        maxTokens: 500
    )
    
    let response = try await provider.sendChatCompletion(request: request)
    let assistantMessage = response.choices.first?.message.content ?? ""
    
    // Add assistant response to history
    conversationHistory.append(.assistant(content: .text(assistantMessage)))
    
    return assistantMessage
}

// Usage
let response1 = try await sendMessage("How do I create a Swift class?")
let response2 = try await sendMessage("Now show me how to add inheritance")
```

## Message Types

The Chat Completions API supports several message roles:

### System Messages

Set the assistant's behavior and personality:

```swift
.system(content: .text("You are a professional translator. Translate all messages to French."))
.system(content: .text("You are a code reviewer. Focus on security and performance."))
.system(content: .text("Respond only in JSON format with 'answer' and 'confidence' fields."))
```

### User Messages

Input from the user:

```swift
.user(content: .text("What is machine learning?"))
.user(content: .text("Translate this to Spanish: Hello world"))
```

### Assistant Messages

Previous AI responses (for conversation context):

```swift
.assistant(content: .text("Machine learning is a subset of AI..."))
```

### Developer Messages

Special instructions that don't appear in conversation:

```swift
.developer(content: .text("The user is a beginner, explain concepts simply"))
```

### Tool Messages

Responses from function calls (covered in Function Calling section):

```swift
.tool(content: "Temperature: 72°F", name: "get_weather", toolCallId: "call_123")
```

## Multimodal Support

Send images along with text for visual AI capabilities:

### Image from URL

```swift
let imageRequest = ChatCompletionRequest(
    model: "gpt-4o",  // Vision-capable model required
    messages: [
        .user(content: .parts([
            .text("What do you see in this image? Describe it in detail."),
            .imageURL(.url(URL(string: "https://example.com/image.jpg")!))
        ]))
    ]
)

let response = try await provider.sendChatCompletion(request: imageRequest)
```

### Image from Data (Base64)

```swift
// Load image data (from file, camera, etc.)
let imageData = try Data(contentsOf: imageURL)

let imageRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .user(content: .parts([
            .text("Analyze this document and extract the key information"),
            .imageURL(.base64(imageData), detail: .high)
        ]))
    ]
)
```

### Multiple Images

```swift
let multiImageRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .user(content: .parts([
            .text("Compare these two images and tell me the differences"),
            .imageURL(.url(URL(string: "https://example.com/image1.jpg")!)),
            .imageURL(.url(URL(string: "https://example.com/image2.jpg")!))
        ]))
    ]
)
```

### Image Detail Levels

Control processing cost and quality:

```swift
.imageURL(.url(imageURL), detail: .low)     // Faster, cheaper
.imageURL(.url(imageURL), detail: .high)    // Better quality, more expensive
.imageURL(.url(imageURL), detail: .auto)    // Automatic selection (default)
```

### Vision with Conversation

```swift
var messages: [Message] = [
    .system(content: .text("You are a helpful image analysis assistant."))
]

// First image
messages.append(.user(content: .parts([
    .text("What's in this image?"),
    .imageURL(.url(URL(string: "https://example.com/photo1.jpg")!))
])))

let response1 = try await provider.sendChatCompletion(request: ChatCompletionRequest(
    model: "gpt-4o",
    messages: messages
))

// Add response to conversation
messages.append(.assistant(content: .text(response1.choices.first?.message.content ?? "")))

// Follow up question
messages.append(.user(content: .text("What colors are dominant in the image?")))
```

## Streaming

Stream responses for real-time user experience:

### Basic Streaming

```swift
let streamRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .user(content: .text("Write a short story about AI"))
    ],
    maxTokens: 500,
    stream: true  // Enable streaming
)

print("Story: ", terminator: "")
for try await chunk in try await provider.sendChatCompletionStream(request: streamRequest) {
    if let content = chunk.choices.first?.delta.content {
        print(content, terminator: "")
        fflush(stdout) // Ensure immediate output
    }
}
print() // New line when complete
```

### Streaming with UI Updates

```swift
@State private var streamingText = ""
@State private var isStreaming = false

func streamResponse() async {
    isStreaming = true
    streamingText = ""
    
    let request = ChatCompletionRequest(
        model: "gpt-4o",
        messages: [.user(content: .text(userInput))],
        stream: true
    )
    
    do {
        for try await chunk in try await provider.sendChatCompletionStream(request: request) {
            if let content = chunk.choices.first?.delta.content {
                await MainActor.run {
                    streamingText += content
                }
            }
        }
    } catch {
        print("Streaming error: \(error)")
    }
    
    isStreaming = false
}
```

### Streaming with Function Calls

```swift
for try await chunk in try await provider.sendChatCompletionStream(request: request) {
    let choice = chunk.choices.first
    
    // Handle text content
    if let content = choice?.delta.content {
        accumulatedText += content
    }
    
    // Handle function calls
    if let toolCalls = choice?.delta.toolCalls {
        for toolCall in toolCalls {
            // Process tool call...
        }
    }
    
    // Check if stream is complete
    if choice?.finishReason != nil {
        print("Stream completed with reason: \(choice?.finishReason ?? "unknown")")
    }
}
```

## Function Calling

Integrate custom tools and functions with automatic schema generation:

### Defining Functions with AISDK Tools

```swift
struct WeatherTool: AITool {
    let name = "get_weather"
    let description = "Get current weather for a location"

    enum TemperatureUnit: String, Codable, CaseIterable {
        case celsius
        case fahrenheit
    }
    
    @AIParameter(description: "The city to get weather for")
    var city: String = ""
    
    @AIParameter(description: "Temperature unit")
    var unit: TemperatureUnit = .fahrenheit
    
    func execute() async throws -> AIToolResult {
        // Your weather API call here
        let weather = await fetchWeather(city: city, unit: unit)
        return AIToolResult(
            content: "Temperature in \(city): \(weather.temperature)°\(unit.rawValue.prefix(1).uppercased())"
        )
    }
}
```

### Using Functions in Chat

```swift
let tools = [WeatherTool.jsonSchema()]

let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .user(content: .text("What's the weather in San Francisco?"))
    ],
    tools: tools,
    toolChoice: .auto  // Let the model decide when to use tools
)

let response = try await provider.sendChatCompletion(request: request)

// Handle tool calls
if let toolCalls = response.choices.first?.message.toolCalls {
    var followUpMessages = request.messages
    
    // Add the assistant's response with tool calls
    followUpMessages.append(.assistant(
        content: .text(response.choices.first?.message.content ?? ""),
        toolCalls: toolCalls
    ))
    
    for toolCall in toolCalls {
        if let function = toolCall.function {
            // Execute the tool
            let jsonData = function.arguments.data(using: .utf8)!
            var tool = WeatherTool()
            tool = try tool.validateAndSetParameters(jsonData)
            let (result, _) = try await tool.execute()
            
            // Add tool result to conversation
            followUpMessages.append(.tool(
                content: result,
                name: function.name,
                toolCallId: toolCall.id
            ))
        }
    }
    
    // Send follow-up request with tool results
    let followUpRequest = ChatCompletionRequest(
        model: "gpt-4o",
        messages: followUpMessages
    )
    
    let finalResponse = try await provider.sendChatCompletion(request: followUpRequest)
}
```

### Manual Function Definition

```swift
let manualFunction = ToolSchema(
    type: "function",
    function: ToolFunction(
        name: "calculate_tip",
        description: "Calculate tip amount for a bill",
        parameters: Parameters(
            type: "object",
            properties: [
                "bill_amount": PropertyDefinition(
                    type: "number",
                    description: "The total bill amount",
                    minimum: 0
                ),
                "tip_percentage": PropertyDefinition(
                    type: "number", 
                    description: "Tip percentage (0-100)",
                    minimum: 0,
                    maximum: 100
                )
            ],
            required: ["bill_amount", "tip_percentage"]
        )
    )
)
```

### Tool Choice Options

```swift
// Let the model decide when to use tools
toolChoice: .auto

// Force the model to call a specific function
toolChoice: .function(ToolChoice.FunctionChoice(name: "get_weather"))

// Require the model to call any available function
toolChoice: .required

// Never call functions
toolChoice: .none
```

## Structured Outputs

Get predictable, structured responses:

### JSON Mode

```swift
let jsonRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .system(content: .text("You are a helpful assistant that returns valid JSON.")),
        .user(content: .text("List 3 programming languages with their characteristics as JSON"))
    ],
    responseFormat: .jsonObject
)

let response = try await provider.sendChatCompletion(request: jsonRequest)

// Parse the JSON response
if let jsonString = response.choices.first?.message.content,
   let jsonData = jsonString.data(using: .utf8) {
    let parsedObject = try JSONSerialization.jsonObject(with: jsonData)
    print("Parsed JSON: \(parsedObject)")
}
```

### Schema-Validated JSON

```swift
// Define your expected structure
struct LanguageList: Codable {
    let languages: [ProgrammingLanguage]
}

struct ProgrammingLanguage: Codable {
    let name: String
    let paradigm: String
    let difficulty: String
}

let schemaRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [
        .user(content: .text("List 3 programming languages with their paradigm and difficulty"))
    ],
    responseFormat: .jsonSchema(
        name: "language_list",
        description: "A list of programming languages",
        schemaBuilder: LanguageList.schema(),
        strict: true
    )
)

// Use generateObject for automatic parsing
let languageList: LanguageList = try await provider.generateObject(request: schemaRequest)
print("Languages: \(languageList.languages.map { $0.name })")
```

## Advanced Features

### Temperature and Creativity Control

```swift
// Very focused, deterministic responses
let factualRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [.user(content: .text("What is 2+2?"))],
    temperature: 0.0
)

// Balanced creativity
let balancedRequest = ChatCompletionRequest(
    model: "gpt-4o", 
    messages: [.user(content: .text("Write a poem about coding"))],
    temperature: 0.7
)

// Maximum creativity
let creativeRequest = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [.user(content: .text("Create a fantasy story"))],
    temperature: 1.5
)
```

### Token Management

```swift
let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: messages,
    maxTokens: 500,              // Limit response length
    maxCompletionTokens: 300,    // Alternative token limit
    presencePenalty: 0.6,        // Reduce repetition (-2.0 to 2.0)
    frequencyPenalty: 0.3        // Reduce frequent phrases (-2.0 to 2.0)
)
```

### Stop Sequences

```swift
let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [.user(content: .text("List programming languages:"))],
    stop: ["\n\n", "That's all"]  // Stop generation at these sequences
)
```

### Seed for Reproducibility

```swift
let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: messages,
    seed: 42,           // Same seed = same output (when temperature = 0)
    temperature: 0.0
)
```

### Multiple Responses

```swift
let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [.user(content: .text("Write a tagline for a tech startup"))],
    n: 3  // Generate 3 different responses
)

// Access all responses
for (index, choice) in response.choices.enumerated() {
    print("Option \(index + 1): \(choice.message.content ?? "")")
}
```

### Logprobs for Token Analysis

```swift
let request = ChatCompletionRequest(
    model: "gpt-4o",
    messages: [.user(content: .text("The capital of France is"))],
    logprobs: true,      // Enable logprobs
    topLogprobs: 5       // Return top 5 alternative tokens
)

// Analyze token probabilities
if let logprobs = response.choices.first?.logprobs?.content {
    for tokenInfo in logprobs {
        print("Token: '\(tokenInfo.token)' - Probability: \(tokenInfo.logprob)")
    }
}
```

## Error Handling

Handle various error scenarios gracefully:

```swift
do {
    let response = try await provider.sendChatCompletion(request: request)
    print("Success: \(response.choices.first?.message.content ?? "")")
    
} catch let error as AISDKError {
    switch error {
    case .httpError(let statusCode, let message):
        switch statusCode {
        case 400:
            print("Bad request: \(message)")
        case 401:
            print("Invalid API key")
        case 429:
            print("Rate limit exceeded - try again later")
        case 500:
            print("OpenAI server error")
        default:
            print("HTTP error \(statusCode): \(message)")
        }
        
    case .underlying(let afError):
        print("Network error: \(afError.localizedDescription)")
        
    case .parsingError(let details):
        print("Response parsing failed: \(details)")
        
    default:
        print("Unknown error: \(error)")
    }
    
} catch {
    print("Unexpected error: \(error)")
}
```

### Handling Token Limits

```swift
func sendWithTokenManagement(messages: [Message]) async throws -> String {
    let request = ChatCompletionRequest(
        model: "gpt-4o",
        messages: messages,
        maxTokens: 1000
    )
    
    do {
        let response = try await provider.sendChatCompletion(request: request)
        
        // Check if response was truncated
        if response.choices.first?.finishReason == "length" {
            print("⚠️ Response was truncated due to token limit")
        }
        
        return response.choices.first?.message.content ?? ""
        
    } catch let error as AISDKError {
        if case .httpError(400, let message) = error,
           message.contains("maximum context length") {
            // Handle context length exceeded
            print("Context too long, truncating conversation...")
            let truncatedMessages = Array(messages.suffix(5)) // Keep last 5 messages
            return try await sendWithTokenManagement(messages: truncatedMessages)
        }
        throw error
    }
}
```

## Best Practices

### 1. Optimize for Your Use Case

```swift
// For factual Q&A - low temperature
let factualRequest = ChatCompletionRequest(
    model: "gpt-4o-mini",  // Faster for simple tasks
    messages: messages,
    temperature: 0.1,
    maxTokens: 100
)

// For creative writing - higher temperature
let creativeRequest = ChatCompletionRequest(
    model: "gpt-4o",       // Better for complex tasks
    messages: messages,
    temperature: 0.8,
    maxTokens: 1000
)
```

### 2. Manage Conversation Context

```swift
class ConversationManager {
    private var messages: [Message] = []
    private let maxMessages = 20  // Prevent context from growing too large
    
    func addSystemMessage(_ content: String) {
        messages.append(.system(content: .text(content)))
    }
    
    func sendMessage(_ content: String) async throws -> String {
        // Add user message
        messages.append(.user(content: .text(content)))
        
        // Trim conversation if too long
        if messages.count > maxMessages {
            let systemMessages = messages.filter { 
                if case .system = $0 { return true }
                return false
            }
            let recentMessages = Array(messages.suffix(maxMessages - systemMessages.count))
            messages = systemMessages + recentMessages
        }
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: messages
        )
        
        let response = try await provider.sendChatCompletion(request: request)
        let assistantMessage = response.choices.first?.message.content ?? ""
        
        // Add assistant response
        messages.append(.assistant(content: .text(assistantMessage)))
        
        return assistantMessage
    }
}
```

### 3. Use Streaming for Better UX

```swift
// Always prefer streaming for user-facing applications
func streamingChat(input: String) async throws {
    let request = ChatCompletionRequest(
        model: "gpt-4o",
        messages: [.user(content: .text(input))],
        stream: true
    )
    
    for try await chunk in try await provider.sendChatCompletionStream(request: request) {
        if let content = chunk.choices.first?.delta.content {
            // Update UI progressively
            await updateUI(with: content)
        }
    }
}
```

### 4. Cache and Reuse Requests

```swift
// Cache expensive requests
class ChatCache {
    private var cache: [String: ChatCompletionResponse] = [:]
    
    func getCachedResponse(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let cacheKey = createCacheKey(request)
        
        if let cached = cache[cacheKey] {
            return cached
        }
        
        let response = try await provider.sendChatCompletion(request: request)
        cache[cacheKey] = response
        return response
    }
}
```

### 5. Model Selection Strategy

```swift
func selectOptimalModel(for task: TaskType) -> String {
    switch task {
    case .simpleQA:
        return "gpt-4o-mini"      // Fast and economical
    case .complexAnalysis:
        return "gpt-4o"           // High capability
    case .codeGeneration:
        return "gpt-4.1"      // Good for programming
    case .vision:
        return "gpt-4o"           // Vision capabilities
    case .reasoning:
        return "o1-preview"       // Advanced reasoning
    }
}
```


## Summary

The OpenAI Chat Completions API in AISDK provides a comprehensive foundation for conversational AI applications. Key capabilities include:

- ✅ **Multiple Models**: GPT-4o, GPT-4, GPT-3.5-turbo, and reasoning models
- ✅ **Multimodal**: Text and vision support with multiple image formats
- ✅ **Function Calling**: Automatic schema generation with AISDK tools
- ✅ **Streaming**: Real-time response streaming for better UX
- ✅ **Structured Outputs**: JSON mode and schema validation
- ✅ **Fine Control**: Temperature, tokens, penalties, and more
- ✅ **Production Ready**: Error handling, caching, and conversation management

For new projects, consider the [Responses API](OpenAI-Responses-API.md) which offers enhanced features like stateful conversations, built-in tools, and semantic streaming while maintaining full compatibility with existing Chat Completions code. 
