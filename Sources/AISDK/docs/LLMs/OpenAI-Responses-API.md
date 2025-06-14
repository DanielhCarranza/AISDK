# OpenAI Responses API Usage Guide

This guide covers how to use OpenAI's advanced Responses API in AISDK. The Responses API is a stateful, next-generation API that combines the best capabilities from chat completions and assistants APIs in one unified experience.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Basic Usage](#basic-usage)
- [Built-in Tools](#built-in-tools)
- [Streaming](#streaming)
- [Advanced Features](#advanced-features)
- [Builder Pattern](#builder-pattern)
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

// With additional parameters
let request = ResponseBuilder
    .webSearch(model: "gpt-4o", "Latest AI research papers")
    .instructions("Provide recent, peer-reviewed sources")
    .maxOutputTokens(500)
    .build()

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
let request = ResponseBuilder
    .text(model: "gpt-4o", "Create a beautiful sunset landscape")
    .withImageGeneration()
    .build()

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
let request = ResponseBuilder
    .text(model: "gpt-4o", "Find information about our product requirements")
    .withFileSearch(vectorStoreId: "vs_abc123")
    .build()

let response = try await provider.createResponse(request: request)
```

### Multiple Tools

Combine multiple tools for complex tasks:

```swift
let request = ResponseBuilder
    .text(model: "gpt-4o", "Research current AI trends and create a visualization")
    .withWebSearch()
    .withCodeInterpreter()
    .build()

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
let request = ResponseBuilder
    .webSearch(model: "gpt-4o", "What's happening in tech today?")
    .streaming(true)
    .build()

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
let request = ResponseBuilder
    .text(model: "gpt-4o", "Analyze this large dataset")
    .background(true)
    .withCodeInterpreter()
    .build()

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
let continuationRequest = ResponseBuilder
    .text(model: "gpt-4o", "Continue the story with more action")
    .previousResponse(firstResponse.id)
    .instructions("Build on the previous story and add excitement")
    .build()

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

let request = ResponseBuilder
    .items(model: "gpt-4o", inputItems)
    .withWebSearch()
    .instructions("First identify the landmark, then search for interesting facts about it")
    .build()

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

let request = ResponseBuilder
    .items(model: "gpt-4o", inputItems)
    .streaming(true)
    .build()

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
let weatherFunction = Function(
    name: "get_weather",
    description: "Get current weather for a city",
    parameters: .object([
        "city": .init(type: .string, description: "The city name")
    ])
)

let request = ResponseBuilder
    .text(model: "gpt-4o", "What's the weather in San Francisco?")
    .tools([
        .function(weatherFunction),
        .webSearch
    ])
    .build()

let response = try await provider.createResponse(request: request)

// Handle function calls in the response
for output in response.output {
    if case .functionCall(let funcCall) = output {
        if funcCall.name == "get_weather" {
            // Execute your weather function
            let weatherResult = getWeather(city: funcCall.arguments["city"] as? String ?? "")
            
            // You can continue the conversation with the result
            let followUpRequest = ResponseBuilder
                .items(model: "gpt-4o", [
                    .functionCallOutput(
                        callId: funcCall.id,
                        output: weatherResult
                    )
                ])
                .previousResponse(response.id)
                .build()
            
            let finalResponse = try await provider.createResponse(request: followUpRequest)
        }
    }
}
```

## Builder Pattern

The `ResponseBuilder` provides a fluent interface for constructing complex requests:

### Factory Methods

```swift
// Text-based requests
let textRequest = ResponseBuilder
    .text(model: "gpt-4o", "Your message here")
    .build()

// Web search requests
let searchRequest = ResponseBuilder
    .webSearch(model: "gpt-4o", "Your search query")
    .build()

// Code interpreter requests
let codeRequest = ResponseBuilder
    .codeInterpreter(model: "gpt-4o", "Your analysis request")
    .build()

// Multi-tool requests
let multiRequest = ResponseBuilder
    .multiTool(model: "gpt-4o", "Complex task requiring multiple tools")
    .build()
```

### Chaining Methods

```swift
let complexRequest = ResponseBuilder
    .text(model: "gpt-4o", "Research and analyze AI trends")
    .instructions("Provide detailed analysis with current data")
    .withWebSearch()
    .withCodeInterpreter()
    .temperature(0.7)
    .maxOutputTokens(2000)
    .metadata(["task": "research", "priority": "high"])
    .build()
```

### All Available Methods

```swift
let fullRequest = ResponseBuilder
    .text(model: "gpt-4o", "Your input")
    .instructions("System instructions")
    .withWebSearch()
    .withCodeInterpreter()
    .withImageGeneration(partialImages: 3)
    .withFileSearch(vectorStoreId: "vs_123")
    .temperature(0.8)
    .topP(0.9)
    .maxOutputTokens(1500)
    .streaming(true)
    .background(false)
    .previousResponse("previous-response-id")
    .toolChoice(.auto)
    .metadata(["key": "value"])
    .include(["reasoning"])
    .parallelToolCalls(true)
    .serviceTier("scale")
    .user("user-123")
    .build()
```

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
let newsRequest = ResponseBuilder.webSearch(model: "gpt-4o", "Latest AI news")

// For calculations or data analysis
let analysisRequest = ResponseBuilder.codeInterpreter(model: "gpt-4o", "Analyze sales data")

// For creative content
let creativeRequest = ResponseBuilder.text(model: "gpt-4o", "Write a story")
    .temperature(0.8)
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

let request = ResponseBuilder
    .text(model: "gpt-4o", userInput)
    .background(isLongRunningTask)
    .build()
```

### 4. Optimize Token Usage

```swift
// Set appropriate limits
let request = ResponseBuilder
    .text(model: "gpt-4o", userInput)
    .maxOutputTokens(500) // Reasonable limit
    .temperature(0.3) // Lower temperature for focused responses
    .build()
```

### 5. Use Conversation Continuation Wisely

```swift
// Keep track of conversation context
class ConversationManager {
    private var lastResponseId: String?
    
    func sendMessage(_ text: String) async throws -> ResponseObject {
        let builder = ResponseBuilder.text(model: "gpt-4o", text)
        
        if let previousId = lastResponseId {
            builder.previousResponse(previousId)
        }
        
        let request = builder.build()
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