# OpenAI Responses API Usage Guide

This guide covers how to use OpenAI's advanced Responses API in AISDK. The Responses API is a stateful, next-generation API that combines the best capabilities from chat completions and assistants APIs in one unified experience.

> **📋 Note:** This guide has been updated to show the modern approach using direct `ResponseRequest` construction. The `ResponseBuilder` pattern is deprecated and should not be used in new code.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Basic Usage](#basic-usage)
- [Built-in Tools](#built-in-tools)
- [Streaming](#streaming)
- [Advanced Features](#advanced-features)
- [Direct Request Construction](#direct-request-construction)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)
- [Migration from Chat Completions](#migration-from-chat-completions)

## Overview

The OpenAI Responses API offers several key advantages over the Chat Completions API:

- **Stateful Conversations**: Automatic conversation history management
- **Built-in Tools**: Native support for web search, code interpreter, image generation, and file search
- **Multimodal Support**: Built-in handling for text, images, and audio inputs/outputs
- **Real-time Streaming**: Enhanced streaming with semantic events
- **Background Tasks**: Support for long-running operations with polling
- **Flexible Input/Output**: Item-based structure for complex interaction patterns

### Compatibility

✅ **Non-Breaking**: The Responses API extends the existing `OpenAIProvider` without breaking any existing functionality.

## Quick Start

### Basic Setup

```swift
import AISDK

// Initialize your OpenAI provider as usual
let provider = OpenAIProvider(apiKey: "your-openai-api-key")

// Simple text response
let response = try await provider.createTextResponse(
    model: "gpt-4o",
    text: "Explain quantum computing in simple terms"
)

print("Response: \(response.outputText ?? "No response")")
```

### With Built-in Tools

```swift
// Enable web search for current information
let response = try await provider.createResponseWithWebSearch(
    model: "gpt-4o",
    text: "What are the latest developments in AI this week?"
)

print("Research: \(response.outputText ?? "No response")")
```

## Basic Usage

### Creating Simple Responses

```swift
// Method 1: Using convenience method
let response = try await provider.createTextResponse(
    model: "gpt-4o",
    text: "Write a haiku about programming",
    maxOutputTokens: 100
)

// Method 2: Using detailed request
let request = ResponseRequest(
    model: "gpt-4o",
    input: .string("Write a haiku about programming"),
    maxOutputTokens: 100
)

let response = try await provider.createResponse(request: request)
```

### Response Structure

```swift
// Access response data
print("Response ID: \(response.id)")
print("Model: \(response.model)")
print("Status: \(response.status)")
print("Output Text: \(response.outputText ?? "No text")")
print("Usage: \(response.usage?.totalTokens ?? 0) tokens")

// Access detailed output items
for output in response.output {
    switch output {
    case .text(let textOutput):
        print("Text: \(textOutput.text)")
    case .webSearchCall(let searchCall):
        print("Web search performed: \(searchCall.query)")
    case .imageGeneration(let imageGen):
        print("Image generated: \(imageGen.prompt)")
    }
}
```

### Managing Responses

```swift
// Retrieve a response by ID
let retrievedResponse = try await provider.retrieveResponse(id: "response-id")

// Cancel a running response
let cancelledResponse = try await provider.cancelResponse(id: "response-id")
```

## Built-in Tools

The Responses API includes several powerful built-in tools that work seamlessly without additional setup.

### Web Search

Perfect for accessing current information and real-time data:

```swift
// Convenience method
let response = try await provider.createResponseWithWebSearch(
    model: "gpt-4o",
    text: "What's the current stock price of Apple?"
)

// With additional parameters using direct construction
let request = ResponseRequest(
    model: "gpt-4o",
    input: .string("Latest AI research papers"),
    instructions: "Provide recent, peer-reviewed sources",
    tools: [.webSearchPreview],
    maxOutputTokens: 500
)

let response = try await provider.createResponse(request: request)
```

### Code Interpreter

For data analysis, calculations, and visualizations:

```swift
// Convenience method
let response = try await provider.createResponseWithCodeInterpreter(
    model: "gpt-4o",
    text: "Calculate the first 20 Fibonacci numbers and create a chart"
)

// Check for code execution results
for output in response.output {
    if case .codeInterpreterCall(let codeCall) = output {
        print("Code executed: \(codeCall.code ?? "")")
        print("Result: \(codeCall.result ?? "")")
        
        // Handle any generated files or visualizations
        if let files = codeCall.files {
            for file in files {
                print("Generated file: \(file.name)")
            }
        }
    }
}
```

### Image Generation

Create images directly within conversations:

```swift
let request = ResponseRequest(
    model: "gpt-4o",
    input: .string("Create a beautiful sunset landscape"),
    tools: [.imageGeneration()]
)

let response = try await provider.createResponse(request: request)

// Access generated images
for output in response.output {
    if case .imageGeneration(let imageGen) = output {
        if let imageURL = imageGen.imageURL {
            print("Generated image: \(imageURL)")
        }
    }
}
```

### File Search

Search through vector stores for relevant information:

```swift
let request = ResponseRequest(
    model: "gpt-4o",
    input: .string("Find information about our product requirements"),
    tools: [.fileSearch(vectorStoreId: "vs_abc123")]
)

let response = try await provider.createResponse(request: request)
```

### Multiple Tools

Combine multiple tools for complex tasks:

```swift
let request = ResponseRequest(
    model: "gpt-4o",
    input: .string("Research current AI trends and create a visualization"),
    tools: [.webSearchPreview, .codeInterpreter]
)

let response = try await provider.createResponse(request: request)
```

## Streaming

Stream responses in real-time with enhanced semantic events:

### Basic Streaming

```swift
print("Streaming response:")

for try await chunk in provider.createTextResponseStream(
    model: "gpt-4o",
    text: "Write a story about AI"
) {
    // Handle text deltas
    if let delta = chunk.delta?.outputText {
        print(delta, terminator: "")
    }
    
    // Check completion status
    if chunk.status?.isFinal == true {
        print("\n\nCompleted with status: \(chunk.status?.rawValue ?? "")")
        
        // Access usage information
        if let usage = chunk.usage {
            print("Total tokens: \(usage.totalTokens)")
        }
    }
}
```

### Streaming with Tools

```swift
let request = ResponseRequest(
    model: "gpt-4o",
    input: .string("What's happening in tech today?"),
    tools: [.webSearchPreview],
    stream: true
)

for try await chunk in provider.createResponseStream(request: request) {
    // Handle different event types
    switch chunk.type {
    case .outputTextDelta:
        if let text = chunk.delta?.outputText {
            print(text, terminator: "")
        }
        
    case .webSearchCall:
        print("\n[Searching the web...]")
        
    case .webSearchResult:
        print("\n[Search completed]")
        
    case .codeInterpreterCall:
        print("\n[Running code...]")
        
    case .imageGeneration:
        print("\n[Generating image...]")
        
    default:
        break
    }
}
```

## Advanced Features

### Background Processing

For long-running tasks that exceed typical response times:

```swift
let request = ResponseRequest(
    model: "gpt-4o",
    input: .string("Analyze this large dataset"),
    tools: [.codeInterpreter],
    background: true
)

let response = try await provider.createResponse(request: request)

// Check if processing in background
if response.status.isProcessing {
    print("Processing in background. ID: \(response.id)")
    
    // Poll for completion
    var finalResponse = response
    while finalResponse.status.isProcessing {
        try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
        finalResponse = try await provider.retrieveResponse(id: response.id)
        print("Status: \(finalResponse.status.rawValue)")
    }
    
    print("Final result: \(finalResponse.outputText ?? "")")
}
```

### Stateful Conversations

Chain responses together to maintain conversation context:

```swift
// First response
let firstResponse = try await provider.createTextResponse(
    model: "gpt-4o",
    text: "Start writing a story about a robot"
)

print("First part: \(firstResponse.outputText ?? "")")

// Continue the conversation
let continuationRequest = ResponseRequest(
    model: "gpt-4o",
    input: .string("Continue the story with more action"),
    instructions: "Build on the previous story and add excitement",
    previousResponseId: firstResponse.id
)

let continuation = try await provider.createResponse(request: continuationRequest)
print("Continuation: \(continuation.outputText ?? "")")
```

### Multimodal Input

Handle text, images, and other media types in your responses:

#### Image URL + Text Analysis

```swift
// Analyze an image from a URL
let inputItems: [ResponseInputItem] = [
    .message(ResponseMessage(
        role: "user",
        content: [
            .inputText(ResponseInputText(text: "What do you see in this image? Describe it in detail.")),
            .inputImage(ResponseInputImage(imageUrl: "https://example.com/landscape.jpg"))
        ]
    ))
]

let request = ResponseRequest(
    model: "gpt-4o",
    input: .items(inputItems)
)

let response = try await provider.createResponse(request: request)
print("Image analysis: \(response.outputText ?? "No analysis")")
```

#### Multiple Images Comparison

```swift
// Compare multiple images
let inputItems: [ResponseInputItem] = [
    .message(ResponseMessage(
        role: "user",
        content: [
            .inputText(ResponseInputText(text: "Compare these two images and tell me the differences")),
            .inputImage(ResponseInputImage(imageUrl: "https://example.com/image1.jpg")),
            .inputImage(ResponseInputImage(imageUrl: "https://example.com/image2.jpg"))
        ]
    ))
]

let request = ResponseRequest(
    model: "gpt-4o",
    input: .items(inputItems)
)

let response = try await provider.createResponse(request: request)
print("Comparison: \(response.outputText ?? "No comparison")")
```

#### File-based Images

```swift
// Use uploaded file ID (after uploading to OpenAI Files API)
let inputItems: [ResponseInputItem] = [
    .message(ResponseMessage(
        role: "user",
        content: [
            .inputText(ResponseInputText(text: "Analyze this uploaded document image")),
            .inputImage(ResponseInputImage(fileId: "file-abc123xyz"))
        ]
    ))
]

let request = ResponseRequest(
    model: "gpt-4o",
    input: .items(inputItems)
)

let response = try await provider.createResponse(request: request)
```

#### Multimodal with Built-in Tools

```swift
// Combine image analysis with web search for context
let inputItems: [ResponseInputItem] = [
    .message(ResponseMessage(
        role: "user",
        content: [
            .inputText(ResponseInputText(text: "What landmark is this? Search for more information about it.")),
            .inputImage(ResponseInputImage(imageUrl: "https://example.com/landmark.jpg"))
        ]
    ))
]

let request = ResponseRequest(
    model: "gpt-4o",
    input: .items(inputItems),
    instructions: "First identify the landmark, then search for interesting facts about it",
    tools: [.webSearchPreview]
)

let response = try await provider.createResponse(request: request)
```

#### Streaming Multimodal Response

```swift
// Stream multimodal analysis
let inputItems: [ResponseInputItem] = [
    .message(ResponseMessage(
        role: "user",
        content: [
            .inputText(ResponseInputText(text: "Describe this image in detail, step by step")),
            .inputImage(ResponseInputImage(imageUrl: "https://example.com/complex-scene.jpg"))
        ]
    ))
]

let request = ResponseRequest(
    model: "gpt-4o",
    input: .items(inputItems),
    stream: true
)

print("Streaming image analysis:")
for try await chunk in provider.createResponseStream(request: request) {
    if let delta = chunk.delta?.outputText {
        print(delta, terminator: "")
    }
}
```

### Custom Function Calling

Integrate your own functions alongside built-in tools:

```swift
// Define a custom function
let weatherFunction = ToolFunction(
    name: "get_weather",
    description: "Get current weather for a city",
    parameters: Parameters(
        type: "object",
        properties: [
            "city": PropertyDefinition(type: "string", description: "The city name")
        ],
        required: ["city"]
    )
)

let request = ResponseRequest(
    model: "gpt-4o",
    input: .string("What's the weather in San Francisco?"),
    tools: [
        .function(weatherFunction),
        .webSearchPreview
    ]
)

let response = try await provider.createResponse(request: request)

// Handle function calls in the response
for output in response.output {
    if case .functionCall(let funcCall) = output {
        if funcCall.name == "get_weather" {
            // Execute your weather function
            let weatherResult = getWeather(city: funcCall.arguments["city"] as? String ?? "")
            
            // You can continue the conversation with the result
            let followUpRequest = ResponseRequest(
                model: "gpt-4o",
                input: .items([
                    .functionCallOutput(
                        callId: funcCall.id,
                        output: weatherResult
                    )
                ]),
                previousResponseId: response.id
            )
            
            let finalResponse = try await provider.createResponse(request: followUpRequest)
        }
    }
}
```

## Direct Request Construction

The modern approach uses direct `ResponseRequest` construction for clean, explicit configuration:

### Basic Request Types

```swift
// Simple text request
let textRequest = ResponseRequest(
    model: "gpt-4o",
    input: .string("Your message here")
)

// Web search request
let searchRequest = ResponseRequest(
    model: "gpt-4o", 
    input: .string("Your search query"),
    tools: [.webSearchPreview]
)

// Code interpreter request
let codeRequest = ResponseRequest(
    model: "gpt-4o",
    input: .string("Your analysis request"),
    tools: [.codeInterpreter]
)

// Multi-tool request
let multiRequest = ResponseRequest(
    model: "gpt-4o",
    input: .string("Complex task requiring multiple tools"),
    tools: [.webSearchPreview, .codeInterpreter, .imageGeneration()]
)
```

### Complex Configuration

```swift
let complexRequest = ResponseRequest(
    model: "gpt-4o",
    input: .string("Research and analyze AI trends"),
    instructions: "Provide detailed analysis with current data",
    tools: [.webSearchPreview, .codeInterpreter],
    temperature: 0.7,
    maxOutputTokens: 2000,
    metadata: ["task": "research", "priority": "high"]
)
```

### All Available Parameters

```swift
let fullRequest = ResponseRequest(
    model: "gpt-4o",
    input: .string("Your input"),
    instructions: "System instructions",
    tools: [.webSearchPreview, .codeInterpreter, .imageGeneration(partialImages: 3), .fileSearch(vectorStoreId: "vs_123")],
    toolChoice: .auto,
    metadata: ["key": "value"],
    temperature: 0.8,
    topP: 0.9,
    maxOutputTokens: 1500,
    stream: true,
    background: false,
    previousResponseId: "previous-response-id",
    include: ["reasoning"],
    store: true,
    reasoning: nil,
    parallelToolCalls: true,
    serviceTier: "scale",
    user: "user-123",
    truncation: nil,
    text: nil
)
```

### Benefits of Direct Construction

- **🔍 Explicit**: All parameters are clearly visible
- **🚀 Performance**: No intermediate builder objects
- **💡 IntelliSense**: Better IDE autocompletion 
- **📋 Maintainable**: Easier to read and modify
- **⚡ Future-proof**: Ready for new parameters without API changes

## Error Handling

Handle errors gracefully with comprehensive error information:

```swift
do {
    let response = try await provider.createTextResponse(
        model: "gpt-4o",
        text: "Your message"
    )
    
    print("Success: \(response.outputText ?? "")")
    
} catch let error as AISDKError {
    switch error {
    case .apiError(let statusCode, let message):
        print("API Error (\(statusCode)): \(message)")
        
    case .invalidAPIKey:
        print("Invalid API key provided")
        
    case .rateLimitExceeded:
        print("Rate limit exceeded, try again later")
        
    case .modelNotFound:
        print("Specified model not available")
        
    case .networkError:
        print("Network connection error")
        
    default:
        print("Unknown error: \(error)")
    }
    
} catch {
    print("Unexpected error: \(error)")
}
```

### Response Status Handling

```swift
let response = try await provider.createResponse(request: request)

switch response.status {
case .completed:
    print("Response completed successfully")
    
case .failed:
    print("Response failed: \(response.error?.message ?? "Unknown error")")
    
case .cancelled:
    print("Response was cancelled")
    
case .inProgress, .queued:
    print("Response is still processing...")
    
default:
    print("Unknown status: \(response.status)")
}
```

## Best Practices

### 1. Choose the Right Tool for the Task

```swift
// For current information or real-time data
let newsRequest = ResponseRequest(
    model: "gpt-4o", 
    input: .string("Latest AI news"),
    tools: [.webSearchPreview]
)

// For calculations or data analysis
let analysisRequest = ResponseRequest(
    model: "gpt-4o",
    input: .string("Analyze sales data"),
    tools: [.codeInterpreter]
)

// For creative content
let creativeRequest = ResponseRequest(
    model: "gpt-4o",
    input: .string("Write a story"),
    temperature: 0.8
)
```

### 2. Use Streaming for Better UX

```swift
// Always prefer streaming for user-facing applications
for try await chunk in provider.createTextResponseStream(
    model: "gpt-4o",
    text: userInput
) {
    // Update UI progressively
    updateUI(with: chunk.delta?.outputText)
}
```

### 3. Handle Background Tasks Appropriately

```swift
// Only use background processing for truly long-running tasks
let isLongRunningTask = estimatedTokens > 10000

let request = ResponseRequest(
    model: "gpt-4o",
    input: .string(userInput),
    background: isLongRunningTask
)
```

### 4. Optimize Token Usage

```swift
// Set appropriate limits
let request = ResponseRequest(
    model: "gpt-4o",
    input: .string(userInput),
    maxOutputTokens: 500, // Reasonable limit
    temperature: 0.3 // Lower temperature for focused responses
)
```

### 5. Use Conversation Continuation Wisely

```swift
// Keep track of conversation context
class ConversationManager {
    private var lastResponseId: String?
    
    func sendMessage(_ text: String) async throws -> ResponseObject {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string(text),
            previousResponseId: lastResponseId
        )
        
        let response = try await provider.createResponse(request: request)
        
        // Update for next message
        lastResponseId = response.id
        
        return response
    }
}
```

## Migration from Chat Completions

The Responses API is designed to be a seamless upgrade from Chat Completions:

### Before (Chat Completions)

```swift
// Old Chat Completions approach
let messages = [
    ChatMessage(role: .user, content: "What's the weather today?")
]

let request = ChatRequest(
    model: "gpt-4o",
    messages: messages
)

let response = try await provider.createChatCompletion(request: request)
```

### After (Responses API)

```swift
// New Responses API approach
let response = try await provider.createTextResponse(
    model: "gpt-4o",
    text: "What's the weather today?"
)

// Or with web search for current weather
let response = try await provider.createResponseWithWebSearch(
    model: "gpt-4o",
    text: "What's the weather today?"
)
```

### Key Differences

| Feature | Chat Completions | Responses API |
|---------|------------------|---------------|
| **State Management** | Stateless | Stateful with `previousResponseId` |
| **Tools** | Function calling only | Built-in tools + functions |
| **Streaming** | Delta-based | Semantic events |
| **Background Processing** | Not supported | Native support |
| **Multimodal** | Manual handling | Built-in support |

### Gradual Migration Strategy

1. **Start with simple replacements**: Replace basic chat completions with `createTextResponse`
2. **Add tools gradually**: Enhance with web search, code interpreter as needed
3. **Implement streaming**: Upgrade to streaming for better UX
4. **Add advanced features**: Utilize stateful conversations and background processing

---

## Summary

The OpenAI Responses API in AISDK provides a powerful, stateful alternative to Chat Completions with built-in tools, enhanced streaming, and advanced features. It's designed to be easy to adopt while providing significant new capabilities for modern AI applications.

Key benefits:
- ✅ **Non-breaking**: Works alongside existing Chat Completions code
- ✅ **Enhanced capabilities**: Web search, code interpreter, image generation
- ✅ **Better UX**: Semantic streaming events and background processing
- ✅ **Stateful**: Automatic conversation management
- ✅ **Flexible**: Builder pattern for complex requests

Start with simple text responses and gradually adopt advanced features as needed!

---

## Migration from ResponseBuilder (Deprecated)

**⚠️ Important:** `ResponseBuilder` is now deprecated. If you're upgrading from code that uses `ResponseBuilder`, here's how to migrate:

### Before (Deprecated)
```swift
// Old ResponseBuilder pattern
let request = ResponseBuilder
    .webSearch(model: "gpt-4o", "Search query")
    .instructions("Be thorough")
    .temperature(0.7)
    .build()
```

### After (Recommended)
```swift
// New direct construction
let request = ResponseRequest(
    model: "gpt-4o",
    input: .string("Search query"),
    instructions: "Be thorough",
    tools: [.webSearchPreview],
    temperature: 0.7
)
```

### Key Migration Points

- **Replace `.build()`** → Use `ResponseRequest()` constructor
- **Replace `.text(model, input)`** → Use `input: .string(input)`
- **Replace `.withWebSearch()`** → Use `tools: [.webSearchPreview]`
- **Replace `.withCodeInterpreter()`** → Use `tools: [.codeInterpreter]`
- **Replace `.previousResponse(id)`** → Use `previousResponseId: id`
- **Replace `.streaming(true)`** → Use `stream: true`

### Migration Benefits

- ✅ **Better Performance**: No intermediate builder objects
- ✅ **Clearer Code**: All parameters visible at construction
- ✅ **IDE Support**: Better autocompletion and error checking
- ✅ **Future-Proof**: Ready for new OpenAI API features 