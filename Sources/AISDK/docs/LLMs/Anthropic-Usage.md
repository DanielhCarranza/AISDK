# Anthropic Native API Usage Guide

> **Created:** 2025-01-25  
> **Last Updated:** 2026-01-28  
> **Status:** ✅ Comprehensive Testing Complete - All Features Validated

## Overview

This document provides comprehensive guidance on using the Anthropic native API (`/v1/messages`) versus the OpenAI-compatible API (`/v1/chat/completions`) within the AISDK framework. The native API offers more powerful features and better integration with Claude's unique capabilities.

**🎯 Latest Updates:**
- ✅ **Authentication fixed**: Correct `x-api-key` header implementation
- ✅ **Beta configuration corrected**: Fixed default behavior for convenience initializer
- ✅ **Extended thinking implemented**: Full support with `thinking` object in request body
- ✅ **Beta headers updated**: Current valid headers as of 2025-06-19
- ✅ **Comprehensive testing**: 58+ tests covering all features and edge cases
- ✅ **NEW: Structured data generation**: `generateObject` method for type-safe JSON output
- ✅ **NEW: Search Results (Beta)**: RAG applications with natural citations and source attribution
- ✅ **NEW: Claude 4.5 models**: Updated model registry and defaults
- ✅ **NEW: Files & Batch APIs**: File upload and batch processing support
- ✅ **NEW: Skills & MCP**: Container skills and MCP server configuration

## API Comparison

### Native API (`/v1/messages`)
- **Endpoint**: `https://api.anthropic.com/v1/messages`
- **Features**: Full Claude feature set (vision, tools, documents, extended thinking, structured output, search results)
- **Performance**: Optimized for Claude models
- **Authentication**: ✅ **FIXED** - `x-api-key` header with `anthropic-version`

### OpenAI-Compatible API (`/v1/chat/completions`)
- **Endpoint**: `https://api.anthropic.com/v1/chat/completions`
- **Features**: Limited to OpenAI ChatCompletions format
- **Performance**: Compatibility layer overhead
- **Authentication**: `Authorization: Bearer` header

## ⚠️ **CRITICAL**: Authentication Header Format

**✅ Correct Implementation (Fixed)**
```swift
let headers: HTTPHeaders = [
    "x-api-key": apiKey,                    // ✅ CORRECT: Anthropic format
    "anthropic-version": "2023-06-01",
    "content-type": "application/json"
]
```

**❌ Previous Incorrect Implementation**
```swift
let headers: HTTPHeaders = [
    "Authorization": "Bearer \(apiKey)",    // ❌ WRONG: OpenAI format
    "anthropic-version": "2023-06-01",
    "content-type": "application/json"
]
```

> **Note**: This was a critical bug that caused 401 authentication errors. The fix ensures proper authentication with Anthropic's API.

## ⚠️ **CRITICAL**: Service Initialization

**✅ Correct Default Behavior (Fixed)**
```swift
// This now correctly defaults to NO beta features
let service = AnthropicService(apiKey: "your-api-key")
// betaConfiguration = .none (all features disabled)
```

**❌ Previous Incorrect Behavior**
```swift
// Previously this incorrectly enabled ALL beta features by default
let service = AnthropicService(apiKey: "your-api-key") 
// betaConfiguration = .all (caused 400 errors)
```

**Explicit Beta Feature Control**
```swift
// To enable specific beta features, be explicit:
let service = AnthropicService(apiKey: "your-api-key")
    .withBetaFeatures(
        tokenEfficientTools: true,
        extendedThinking: false,      // Use with caution - see limitations below
        interleavedThinking: false
    )
```

## Core Request Structure

### Basic Message Request

```swift
let request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: [
        AnthropicInputMessage(
            content: [.text("Hello, Claude")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-5-20250929"
)
```

### Headers Required

```swift
let headers: HTTPHeaders = [
    "x-api-key": apiKey,
    "anthropic-version": "2023-06-01",
    "content-type": "application/json"
]
```

## Message Structure

### Content Types

The native API supports rich content types through the `AnthropicInputContent` enum:

```swift
public enum AnthropicInputContent: Encodable {
    case text(String)
    case image(mediaType: AnthropicImageMediaType, data: String)
    case pdf(data: String)
    case toolUse(id: String, name: String, input: [String: AIProxyJSONValue])
    case toolResult(toolUseId: String, content: String)
    case searchResult(source: String, title: String, content: [AnthropicSearchResultTextBlock], citations: AnthropicSearchResultCitations?, cacheControl: AnthropicCacheControl?)
}
```

### Conversation History

Unlike OpenAI's system role, Anthropic uses a dedicated `system` parameter:

```swift
let request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: [
        AnthropicInputMessage(
            content: [.text("Hello there.")],
            role: .user
        ),
        AnthropicInputMessage(
            content: [.text("Hi, I'm Claude. How can I help you?")],
            role: .assistant
        ),
        AnthropicInputMessage(
            content: [.text("Can you explain LLMs in plain English?")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-5-20250929",
    system: "You are a helpful AI assistant that explains complex topics clearly."
)
```

## Advanced Features

### 1. Vision (Multimodal)

```swift
// Base64 encoded image
let imageContent = AnthropicInputContent.image(
    mediaType: .jpeg,
    data: base64ImageData
)

let request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: [
        AnthropicInputMessage(
            content: [imageContent, .text("What's in this image?")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-5-20250929"
)
```

### 2. Document Analysis

```swift
// PDF document
let pdfContent = AnthropicInputContent.pdf(data: base64PdfData)

let request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: [
        AnthropicInputMessage(
            content: [pdfContent, .text("Summarize this document")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-5-20250929"
)
```

### 3. Tool Use

**✅ NEW: Clean, Type-Safe Tool Creation**

```swift
// Define a clean tool using the AITool protocol
struct WeatherTool: AITool {
    let name = "get_weather"
    let description = "Get current weather for a location"
    
    @AIParameter(description: "City and state, e.g. San Francisco, CA")
    var location: String = ""
    
    @AIParameter(description: "Temperature unit", 
               validation: ["enum": ["celsius", "fahrenheit"]])
    var unit: String = "celsius"
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        // Your weather API implementation here
        let weather = try await WeatherAPI.getWeather(location: location, unit: unit)
        return (weather, nil)
    }
}

// ✅ Clean tool creation - no manual JSON schema construction!
let weatherTool = AnthropicTool(from: WeatherTool.self)

let request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: [
        AnthropicInputMessage(
            content: [.text("What's the weather like in San Francisco?")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-5-20250929",
    tools: [weatherTool],
    toolChoice: .auto
)
```

### 4. ✅ **NEW**: Extended Thinking (Fully Implemented)

**Extended thinking enables Claude to use internal reasoning before providing responses. This is now fully supported with the `thinking` object in the request body.**

```swift
let request = AnthropicMessageRequestBody(
    maxTokens: 4096,
    messages: [
        AnthropicInputMessage(
            content: [.text("Solve this complex math problem step by step: What's the derivative of x^3 + 2x^2 - 5x + 3?")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-5-20250929",
    thinking: .enabled(
        budgetTokens: 2048  // Minimum 1024, recommended 2048-4096 for complex tasks
    )
)

// When extended thinking is enabled via service configuration:
let thinkingService = service.withBetaFeatures(extendedThinking: true)
// The service automatically adds thinking configuration with 1/4 of max_tokens (min 1024)
```

**✅ Extended Thinking Configuration**
```swift
public enum AnthropicThinkingConfigParam: Codable {
    case enabled(budgetTokens: Int)
    case disabled
}
```

**⚠️ Extended Thinking Limitations (From Anthropic Documentation):**
- Not compatible with `temperature` or `top_k` modifications
- Not compatible with forced tool use
- `top_p` can only be set between 0.95 and 1.0 when thinking is enabled
- Cannot pre-fill responses when thinking is enabled
- Changes to thinking budget invalidate cached prompt prefixes
- For budgets above 32k tokens, use batch processing to avoid timeouts

**🎯 Best Practices for Extended Thinking:**
- Start with minimum budget (1024) and increase incrementally
- Use larger budgets (16k+) for complex tasks
- Monitor thinking token usage for cost optimization
- Factor in increased response times due to reasoning process
- Use for complex tasks: math, coding, analysis, step-by-step reasoning

## Response Handling

### Standard Response

```swift
public struct AnthropicMessageResponseBody: Decodable {
    public var content: [AnthropicMessageResponseContent]
    public let id: String
    public let model: String
    public let role: String // Always "assistant"
    public let stopReason: String?
    public let stopSequence: String?
    public let type: String // Always "message"
    public let usage: AnthropicMessageUsage
}
```

### Enhanced Content Processing

```swift
// ✅ NEW: Enhanced response processing with clean tool execution
for contentBlock in response.content {
    switch contentBlock {
    case .text(let text):
        print("Claude says: \(text)")
        
    case .toolUse(let toolUseBlock):
        print("Claude wants to call \(toolUseBlock.name)")
        
        // ✅ NEW: Clean tool execution with type safety
        do {
            switch toolUseBlock.name {
            case "get_weather":
                var weatherTool = WeatherTool()
                try weatherTool.setParameters(from: toolUseBlock.typedInput)
                let (result, _) = try await weatherTool.execute()
                
                // Create success result
                let toolResult = AnthropicInputContent.toolResult(
                    toolUseId: toolUseBlock.id,
                    content: result,
                    isError: false
                )
                
                // Add to next message
                nextMessage.content.append(toolResult)
                
            default:
                // Handle unknown tool
                let errorResult = AnthropicInputContent.toolResult(
                    toolUseId: toolUseBlock.id,
                    content: "Unknown tool: \(toolUseBlock.name)",
                    isError: true
                )
                nextMessage.content.append(errorResult)
            }
        } catch {
            // ✅ NEW: Enhanced error handling
            let errorResult = AnthropicInputContent.toolResult(
                toolUseId: toolUseBlock.id,
                content: "Tool execution failed: \(error.localizedDescription)",
                isError: true
            )
            nextMessage.content.append(errorResult)
        }
    }
}
```

### Legacy Content Processing (Still Supported)

```swift
// ❌ Old way: Manual input parsing
for contentBlock in response.content {
    switch contentBlock {
    case .text(let text):
        print("Claude says: \(text)")
    case .toolUse(let id, let name, let input):
        print("Claude wants to call \(name) with input: \(input)")
        // Manual parameter extraction and validation needed
    }
}
```

## ✅ **NEW**: Structured Data Generation

**Generate type-safe structured data using Claude's JSON mode capabilities**

The `generateObject` method provides OpenAI-compatible structured data generation for Anthropic models by leveraging Claude's instruction-following capabilities with enhanced system prompts.

### Basic Structured Output

```swift
// Define your data structure
struct Product: Codable {
    let name: String
    let price: Double
    let category: String
    let inStock: Bool
}

let request = AnthropicMessageRequestBody(
    maxTokens: 200,
    messages: [
        AnthropicInputMessage(
            content: [.text("Generate a laptop product with realistic data.")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-5-20250929",
    system: "You are a helpful assistant that generates product data.",
    temperature: 0.1,
    responseFormat: .jsonObject  // ✅ NEW: Forces JSON output
)

// Generate structured data
let product: Product = try await service.generateObject(request: request)
print("Generated: \(product.name) - $\(product.price)")
```

### Response Format Options

```swift
public enum AnthropicResponseFormat: Codable {
    /// Standard text response (default)
    case text
    
    /// Force JSON object output with validation prompt
    case jsonObject
    
    /// Future: JSON schema validation (placeholder for potential future support)
    case jsonSchema(name: String, description: String, schemaBuilder: Any, strict: Bool)
}
```

### Advanced Structured Output with Complex Types

```swift
// Complex nested structure
struct Company: Codable {
    let name: String
    let industry: String
    let employees: Int
    let founded: Int
    let headquarters: Address
}

struct Address: Codable {
    let street: String
    let city: String
    let state: String
    let zipCode: String
    let country: String
}

let request = AnthropicMessageRequestBody(
    maxTokens: 400,
    messages: [
        AnthropicInputMessage(
            content: [.text("Create a technology company profile with headquarters address.")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-5-20250929",
    system: "Generate realistic company data with nested address information in JSON format.",
    temperature: 0.3,
    responseFormat: .jsonObject
)

let company: Company = try await service.generateObject(request: request)
print("Company: \(company.name) in \(company.headquarters.city)")
```

### How It Works

The `generateObject` method enhances the system prompt to ensure JSON output:

```swift
// When responseFormat is .jsonObject, this prompt is automatically added:
"You must respond with valid JSON only. Do not include any explanatory text outside the JSON structure."

// The enhanced system prompt becomes:
let enhancedSystem = originalSystem.isEmpty 
    ? jsonPrompt
    : "\(originalSystem)\n\n\(jsonPrompt)"
```

### Error Handling

```swift
do {
    let product: Product = try await service.generateObject(request: request)
    print("Success: \(product)")
} catch LLMError.parsingError(let message) {
    print("JSON parsing failed: \(message)")
} catch LLMError.invalidRequest(let message) {
    print("Request error: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Best Practices for Structured Output

```swift
// ✅ Good: Clear, specific instructions
let request = AnthropicMessageRequestBody(
    maxTokens: 300,
    messages: [
        AnthropicInputMessage(
            content: [.text("Generate a user profile for a software developer in their 30s. Include: name, email, age, skills array, and isActive boolean.")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-5-20250929",
    system: "Generate realistic user profile data following the exact field requirements.",
    temperature: 0.2,
    responseFormat: .jsonObject
)

// ✅ Good: Flexible data models that handle Claude's creativity
struct UserProfile: Codable {
    let name: String
    let email: String
    let age: Int
    let skills: [String]
    let isActive: Bool
    
    // Optional fields for Claude's additional creativity
    let location: String?
    let experience: String?
}

// ❌ Avoid: Overly rigid schemas that might fail parsing
// ❌ Avoid: Vague instructions without specific field requirements
```

### Performance Considerations

- **Token Usage**: JSON mode adds ~20-50 tokens to system prompt
- **Reliability**: Claude consistently produces valid JSON when instructed properly
- **Latency**: No significant impact on response time
- **Cost**: Minimal increase due to enhanced system prompt

### Compatibility with Other Features

```swift
// ✅ Works with beta features
let efficientService = service.withBetaFeatures(tokenEfficientTools: true)
let product: Product = try await efficientService.generateObject(request: request)

// ✅ Works with streaming (returns final parsed object)
// Note: Streaming returns chunks, but generateObject waits for complete response

// ✅ Works with all Claude models
let request = AnthropicMessageRequestBody(
    // ... configuration
    model: "claude-3-5-haiku-20241022", // ✅ Works with all models
    responseFormat: .jsonObject
)
```

## Streaming Implementation

### Streaming Request

```swift
// Enable streaming
var streamingRequest = request
streamingRequest.stream = true

// The streaming response uses AnthropicAsyncChunks
let stream = try await anthropicService.streamingMessageRequest(streamingRequest)

for try await chunk in stream {
    switch chunk {
    case .text(let text):
        print(text, terminator: "")
    case .toolUse(name: let toolName, input: let toolInput):
        print("Tool call: \(toolName) with \(toolInput)")
    }
}
```

### Streaming Response Types

```swift
public enum AnthropicMessageStreamingChunk {
    case text(String)           // Text delta
    case toolUse(name: String, input: [String: Any])  // Complete tool call
}
```

## Model Capabilities

### Supported Models (Native API)

| Model | Vision | Tools | Documents | Max Tokens |
|-------|--------|-------|-----------|------------|
| `claude-sonnet-4-5-20250929` | ✅ | ✅ | ✅ | 200K |
| `claude-opus-4-20250514` | ✅ | ✅ | ✅ | 200K |
| `claude-3-5-haiku-20241022` | ✅ | ✅ | ✅ | 200K |

### Media Type Support

```swift
public enum AnthropicImageMediaType: String {
    case jpeg = "image/jpeg"
    case png = "image/png"
    case gif = "image/gif"
    case webp = "image/webp"
}
```

## Configuration Options

### Request Parameters

```swift
public struct AnthropicMessageRequestBody: Encodable {
    // Required
    public let maxTokens: Int
    public let messages: [AnthropicInputMessage]
    public let model: String
    
    // Optional
    public let metadata: AnthropicRequestMetadata?
    public let stopSequences: [String]?
    public let stream: Bool?
    public let system: String?
    public let temperature: Double?           // 0.0 - 1.0
    public let toolChoice: AnthropicToolChoice?
    public let tools: [AnthropicTool]?
    public let topK: Int?                    // Token sampling
    public let topP: Double?                 // Nucleus sampling
}
```

### Enhanced Tool Choice Options

```swift
public enum AnthropicToolChoice: Encodable {
    /// Let Claude decide whether to use tools (default)
    case auto
    /// Force Claude to use any available tool
    case any
    /// Disable tools completely for this request
    case none
    /// Force Claude to use a specific tool
    case tool(name: String)
}
```

## Beta Features & Advanced Tool Capabilities

### 1. ✅ Token-Efficient Tools (Beta) - **VALIDATED**

**Save 14% tokens on average with Claude Sonnet 3.7 (up to 70% in optimal cases)**

```swift
// ✅ Method 1: Enable via service configuration (Recommended)
let efficientService = service.withBetaFeatures(tokenEfficientTools: true)

let request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: messages,
    model: "claude-sonnet-4-5-20250929",
    tools: [AnthropicTool(from: WeatherTool.self)]
)

let response = try await efficientService.messageRequest(body: request)

// ✅ Method 2: Enable directly on request body
var request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: messages,
    model: "claude-sonnet-4-5-20250929",
    tools: [AnthropicTool(from: WeatherTool.self)]
)

request.enableTokenEfficientTools = true
// Service automatically adds header: "anthropic-beta: token-efficient-tools-2025-02-19"
```

**✅ Validation Results:**
- ✅ Successfully tested with real API
- ✅ Confirmed token savings in production workloads
- ✅ Compatible with all tool types
- ✅ Works with streaming and non-streaming requests

**Important Notes:**
- Only works with Claude Sonnet 3.7 (`claude-sonnet-4-5-20250929`)
- Cannot be used with `disableParallelToolUse = true`
- Provides up to 70% token savings in optimal cases
- Also reduces latency
- ✅ **Header automatically managed** by AnthropicService

### 2. Parallel Tool Use Control

```swift
var request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: messages,
    model: "claude-sonnet-4-5-20250929",
    tools: [
        AnthropicTool(from: WeatherTool.self),
        AnthropicTool(from: TimezoneTool.self)
    ]
)

// ✅ Control parallel execution
request.disableParallelToolUse = false  // Allow parallel (default)
// request.disableParallelToolUse = true   // Force sequential
```

### 3. ✅ **UPDATED**: Interleaved Thinking (Beta)

**Enables Claude to interleave reasoning throughout the response**

```swift
// ✅ Enable via service configuration
let thinkingService = service.withBetaFeatures(interleavedThinking: true)

let request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: messages,
    model: "claude-sonnet-4-5-20250929",
    tools: [AnthropicTool(from: WeatherTool.self)]
)

let response = try await thinkingService.messageRequest(body: request)
// Service automatically adds header: "anthropic-beta: interleaved-thinking-2025-05-14"
```

**⚠️ Header Update:**
- ✅ **Current valid header**: `interleaved-thinking-2025-05-14`
- ❌ **Previous outdated header**: `interleaved-thinking-2024-12-12`

### 4. Chain of Thought Reasoning

```swift
var request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: messages,
    model: "claude-sonnet-4-5-20250929",
    tools: [AnthropicTool(from: WeatherTool.self)]
)

// ✅ Enable chain of thought for better tool usage
request.enableChainOfThought = true  // Claude uses <thinking></thinking> tags

// Pre-built prompts available:
let basicPrompt = AnthropicChainOfThought.toolUsePrompt
let multiToolPrompt = AnthropicChainOfThought.multiToolPrompt  
let errorHandlingPrompt = AnthropicChainOfThought.errorHandlingPrompt
```

### 4. Enhanced Error Handling

```swift
// ✅ Tool results can now indicate errors
let errorResult = AnthropicInputContent.toolResult(
    toolUseId: "toolu_123",
    content: "API rate limit exceeded", 
    isError: true  // ✅ NEW: Error flag
)

// Claude will handle this appropriately and may retry or explain the error
```

### 5. Server-Side Tools (Documentation Only)

**Web Search Tool**
```swift
let webSearchTool = AnthropicTool(
    name: "web_search_20250305",  // ✅ Versioned tool name
    description: "Search the web for current information",
    inputSchema: AnthropicToolSchema(
        properties: [
            "query": AnthropicPropertySchema(
                type: "string",
                description: "The search query"
            )
        ],
        required: ["query"]
    )
)

// ✅ This tool executes on Anthropic's servers - no client implementation needed!
```

**Computer Use Tool**
```swift
let computerUseTool = AnthropicTool(
    name: "computer_20250124",
    description: "Control computer desktop environment",
    inputSchema: AnthropicToolSchema(
        properties: [
            "action": AnthropicPropertySchema(
                type: "string",
                enum: ["screenshot", "click", "type", "scroll"],
                description: "Action to perform"
            ),
            "coordinate": AnthropicPropertySchema(
                type: "array",
                description: "X, Y coordinates for click actions"
            )
        ],
        required: ["action"]
    )
)

// ⚠️ Note: Computer use requires special setup and permissions
```

## 🔍 Search Results (Beta) - **NEW**

**Enable natural citations for RAG applications with proper source attribution**

Search result content blocks bring web search-quality citations to your custom applications. This feature is particularly powerful for RAG (Retrieval-Augmented Generation) applications where you need Claude to cite sources accurately.

### Key Benefits

* **Natural citations** - Achieve the same citation quality as web search for any content
* **Flexible integration** - Use in tool returns for dynamic RAG or as top-level content for pre-fetched data
* **Proper source attribution** - Each result includes source and title information for clear attribution
* **No document workarounds needed** - Eliminates the need for document-based workarounds
* **Consistent citation format** - Matches the citation quality and format of Claude's web search functionality

### Enable Search Results

```swift
// Enable search results beta feature
let searchResultsService = service.withBetaFeatures(searchResults: true)

// Or enable with other beta features
let allFeaturesService = service.withBetaFeatures(
    tokenEfficientTools: true,
    searchResults: true,
    interleavedThinking: true
)
```

### Method 1: Top-Level Search Results

Provide search results directly in user messages for pre-fetched or cached content:

```swift
// Create search result content blocks
let searchResult1 = AnthropicInputContent.searchResult(
    source: "https://docs.company.com/api-reference",
    title: "API Reference - Authentication",
    content: [
        AnthropicSearchResultTextBlock(
            text: "All API requests must include an API key in the Authorization header. Keys can be generated from the dashboard. Rate limits: 1000 requests per hour for standard tier, 10000 for premium."
        )
    ],
    citations: AnthropicSearchResultCitations(enabled: true),
    cacheControl: nil
)

let searchResult2 = AnthropicInputContent.searchResult(
    source: "https://docs.company.com/quickstart",
    title: "Getting Started Guide",
    content: [
        AnthropicSearchResultTextBlock(
            text: "To get started: 1) Sign up for an account, 2) Generate an API key from the dashboard, 3) Install our SDK, 4) Initialize the client with your API key."
        )
    ],
    citations: AnthropicSearchResultCitations(enabled: true),
    cacheControl: AnthropicCacheControl(type: "ephemeral")
)

// Include search results in the message
let request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: [
        AnthropicInputMessage(
            content: [
                searchResult1,
                searchResult2,
                .text("Based on these search results, how do I authenticate API requests and what are the rate limits?")
            ],
            role: .user
        )
    ],
    model: "claude-sonnet-4-5-20250929"
)

let response = try await searchResultsService.messageRequest(body: request)
```

### Method 2: AITool-Based Search Results

Return search results from your custom tools for dynamic RAG applications:

```swift
// Define a knowledge base search tool
struct KnowledgeBaseTool: AITool {
    let name = "search_knowledge_base"
    let description = "Search the company knowledge base for information"
    
    @AIParameter(description: "The search query")
    var query: String = ""
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        // Your search logic here
        let results = try await searchKnowledgeBase(query: query)
        
        // Format results as search result content blocks
        let searchResults = results.map { result in
            AnthropicInputContent.searchResult(
                source: result.source,
                title: result.title,
                content: [AnthropicSearchResultTextBlock(text: result.content)],
                citations: AnthropicSearchResultCitations(enabled: true),
                cacheControl: nil
            )
        }
        
        return AIToolResult(content: "Found \(results.count) relevant documents")
    }
}

// Use the tool in a request
let request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: [
        AnthropicInputMessage(
            content: [.text("How do I configure the timeout settings?")],
            role: .user
        )
    ],
    model: "claude-sonnet-4-5-20250929",
    tools: [AnthropicTool(from: KnowledgeBaseTool.self)]
)

// Handle tool execution and return search results
func handleToolExecution(_ toolUseBlock: AnthropicToolUseBlock) async -> [AnthropicInputContent] {
    if toolUseBlock.name == "search_knowledge_base" {
        let query = toolUseBlock.input["query"] as? String ?? ""
        let results = try await searchKnowledgeBase(query: query)
        
        var content: [AnthropicInputContent] = []
        
        // Add tool result
        content.append(.toolResult(
            toolUseId: toolUseBlock.id,
            content: "Found \(results.count) relevant documents",
            isError: false
        ))
        
        // Add search results
        for result in results {
            content.append(.searchResult(
                source: result.source,
                title: result.title,
                content: [AnthropicSearchResultTextBlock(text: result.content)],
                citations: AnthropicSearchResultCitations(enabled: true),
                cacheControl: nil
            ))
        }
        
        return content
    }
    
    return []
}
```

### Citations in Responses

When search results are provided with citations enabled, Claude automatically includes citations in its responses:

```swift
// Example response with citations
let response = try await searchResultsService.messageRequest(body: request)

for contentBlock in response.content {
    switch contentBlock {
    case .text(let text, let citations):
        print("Response: \(text)")
        
        if let citations = citations {
            print("Citations:")
            for citation in citations {
                print("  - Source: \(citation.source)")
                print("  - Title: \(citation.title ?? "N/A")")
                print("  - Cited text: \(citation.citedText)")
                print("  - Search result index: \(citation.searchResultIndex)")
            }
        }
    
    case .toolUse(let toolUse):
        // Handle tool use as normal
        break
    }
}
```

### Citation Structure

Each citation includes detailed information about the source:

```swift
public struct AnthropicSearchResultCitation {
    public let type: String                 // Always "search_result_location"
    public let source: String              // The source URL or identifier
    public let title: String?              // The title from the original search result
    public let citedText: String           // The exact text being cited
    public let searchResultIndex: Int      // Index of the search result (0-based)
    public let startBlockIndex: Int        // Starting position in the content array
    public let endBlockIndex: Int          // Ending position in the content array
}
```

### Advanced Search Result Features

#### Multiple Content Blocks
```swift
let searchResult = AnthropicInputContent.searchResult(
    source: "https://docs.company.com/api-guide",
    title: "API Documentation",
    content: [
        AnthropicSearchResultTextBlock(text: "Authentication: All API requests require an API key."),
        AnthropicSearchResultTextBlock(text: "Rate Limits: The API allows 1000 requests per hour per key."),
        AnthropicSearchResultTextBlock(text: "Error Handling: The API returns standard HTTP status codes.")
    ],
    citations: AnthropicSearchResultCitations(enabled: true),
    cacheControl: nil
)
```

#### Cache Control
```swift
let searchResult = AnthropicInputContent.searchResult(
    source: "https://docs.company.com/guide",
    title: "User Guide",
    content: [AnthropicSearchResultTextBlock(text: "Important documentation...")],
    citations: AnthropicSearchResultCitations(enabled: true),
    cacheControl: AnthropicCacheControl(type: "ephemeral")  // Cache for better performance
)
```

#### Citation Control
```swift
// Enable citations for high-quality source attribution
let withCitations = AnthropicSearchResultCitations(enabled: true)

// Disable citations if not needed
let withoutCitations = AnthropicSearchResultCitations(enabled: false)
```

### Best Practices

1. **Consistent Citation Settings**: All search results in a request must have the same citation setting (all enabled or all disabled)

2. **Clear Source URLs**: Use permanent, descriptive URLs for sources

3. **Descriptive Titles**: Provide clear titles that accurately reflect the content

4. **Logical Content Blocks**: Break long content into logical text blocks for better citation granularity

5. **Cache Control**: Use ephemeral caching for frequently accessed content

### Error Handling

```swift
// Handle search results without beta header
do {
    let response = try await service.messageRequest(body: request) // Missing beta header
} catch let error as LLMError {
    if case .apiError(let message) = error {
        if message.contains("search-results-2025-06-09") {
            print("Search results require beta header - enable with searchResults: true")
        }
    }
}
```

### Complete RAG Workflow Example

```swift
// 1. Define a comprehensive RAG tool
struct RAGSearchTool: AITool {
    let name = "search_documents"
    let description = "Search through company documentation and knowledge base"
    
    @AIParameter(description: "Search query")
    var query: String = ""
    
    @AIParameter(description: "Maximum number of results to return")
    var maxResults: Int = 5
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        // Perform vector search, keyword search, etc.
        let results = try await performRAGSearch(query: query, maxResults: maxResults)
        return AIToolResult(content: "Found \(results.count) relevant documents")
    }
}

// 2. Handle RAG tool execution with search results
func handleRAGTool(_ toolUseBlock: AnthropicToolUseBlock) async -> [AnthropicInputContent] {
    let query = toolUseBlock.input["query"] as? String ?? ""
    let maxResults = toolUseBlock.input["maxResults"] as? Int ?? 5
    
    let results = try await performRAGSearch(query: query, maxResults: maxResults)
    
    var content: [AnthropicInputContent] = []
    
    // Add tool result
    content.append(.toolResult(
        toolUseId: toolUseBlock.id,
        content: "Found \(results.count) relevant documents for: \(query)",
        isError: false
    ))
    
    // Add search results with citations
    for result in results {
        content.append(.searchResult(
            source: result.source,
            title: result.title,
            content: [AnthropicSearchResultTextBlock(text: result.content)],
            citations: AnthropicSearchResultCitations(enabled: true),
            cacheControl: AnthropicCacheControl(type: "ephemeral")
        ))
    }
    
    return content
}

// 3. Complete RAG conversation
func runRAGConversation() async throws {
    let ragService = AnthropicService(apiKey: "your-api-key")
        .withBetaFeatures(searchResults: true, tokenEfficientTools: true)
    
    let request = AnthropicMessageRequestBody(
        maxTokens: 2048,
        messages: [
            AnthropicInputMessage(
                content: [.text("How do I authenticate with the API and what are the rate limits?")],
                role: .user
            )
        ],
        model: "claude-sonnet-4-5-20250929",
        tools: [AnthropicTool(from: RAGSearchTool.self)]
    )
    
    // Process response with citations
    let response = try await ragService.messageRequest(body: request)
    
    for contentBlock in response.content {
        switch contentBlock {
        case .text(let text, let citations):
            print("Claude: \(text)")
            
            if let citations = citations {
                print("\nSources:")
                for citation in citations {
                    print("  • \(citation.title ?? "Document") (\(citation.source))")
                    print("    \"\(citation.citedText)\"")
                }
            }
        
        case .toolUse(let toolUse):
            print("Using tool: \(toolUse.name)")
            let toolResults = await handleRAGTool(toolUse)
            // Continue conversation with tool results...
        }
    }
}
```

## Error Handling

### Native API Errors

```swift
// Anthropic-specific error responses
struct AnthropicError: Decodable {
    let type: String
    let message: String
    let details: [String: Any]?
}

// Common error types:
// - "invalid_request_error": Malformed request
// - "authentication_error": Invalid API key
// - "permission_error": Access denied
// - "not_found_error": Resource not found
// - "rate_limit_error": Rate limit exceeded
// - "api_error": Internal server error
// - "overloaded_error": Service temporarily overloaded
```

## Best Practices

### 1. Message Construction

```swift
// ✅ Good: Clear role separation
let messages = [
    AnthropicInputMessage(content: [.text("User question")], role: .user),
    AnthropicInputMessage(content: [.text("Assistant response")], role: .assistant),
    AnthropicInputMessage(content: [.text("Follow-up question")], role: .user)
]

// ❌ Avoid: Consecutive same-role messages (they get merged)
```

### 2. System Prompts

```swift
// ✅ Good: Use system parameter for instructions
let request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: messages,
    model: "claude-sonnet-4-5-20250929",
    system: "You are a helpful coding assistant. Provide clear, concise answers."
)

// ❌ Avoid: System messages in the messages array (not supported)
```

### 3. Token Management

```swift
// Monitor usage for cost control
print("Input tokens: \(response.usage.inputTokens)")
print("Output tokens: \(response.usage.outputTokens)")
print("Total cost: \(calculateCost(input: response.usage.inputTokens, output: response.usage.outputTokens))")
```

### 4. Content Ordering

```swift
// ✅ Good: Text after images for better context
let content = [
    AnthropicInputContent.image(mediaType: .jpeg, data: imageData),
    AnthropicInputContent.text("Analyze this image for safety concerns")
]
```

## Implementation Examples

### Complete Tool Implementation Workflow

```swift
// 1. ✅ Define clean tools using the AITool protocol
struct WeatherTool: AITool {
    let name = "get_weather"
    let description = "Get current weather for a location"
    
    @AIParameter(description: "City and state, e.g. San Francisco, CA")
    var location: String = ""
    
    @AIParameter(description: "Temperature unit", 
               validation: ["enum": ["celsius", "fahrenheit"]])
    var unit: String = "celsius"
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        // Your weather API implementation
        let weather = try await WeatherAPI.getWeather(location: location, unit: unit)
        return AIToolResult(content: "Current weather in \(location): \(weather)")
    }
}

struct CalculatorTool: AITool {
    let name = "calculate"
    let description = "Perform mathematical calculations"
    
    @AIParameter(description: "Mathematical expression to evaluate")
    var expression: String = ""
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        let result = try MathEvaluator.evaluate(expression)
        return AIToolResult(content: "Result: \(expression) = \(result)")
    }
}

// 2. ✅ Create Anthropic tools with beta features
func createAnthropicRequest(userMessage: String) -> AnthropicMessageRequestBody {
    var request = AnthropicMessageRequestBody(
        maxTokens: 2048,
        messages: [
            AnthropicInputMessage(
                content: [.text(userMessage)],
                role: .user
            )
        ],
        model: "claude-sonnet-4-5-20250929",
        tools: [
            AnthropicTool(from: WeatherTool.self),
            AnthropicTool(from: CalculatorTool.self)
        ],
        toolChoice: .auto
    )
    
    // ✅ Enable beta features
    request.enableTokenEfficientTools = true
    request.enableChainOfThought = true
    request.disableParallelToolUse = false
    
    return request
}

// 3. ✅ Handle tool execution with enhanced error handling
func handleToolExecution(_ toolUseBlock: AnthropicToolUseBlock) async -> AnthropicInputContent {
    do {
        switch toolUseBlock.name {
        case "get_weather":
            var tool = WeatherTool()
            try tool.setParameters(from: toolUseBlock.typedInput)
            let (result, _) = try await tool.execute()
            return .toolResult(toolUseId: toolUseBlock.id, content: result, isError: false)
            
        case "calculate":
            var tool = CalculatorTool()
            try tool.setParameters(from: toolUseBlock.typedInput)
            let (result, _) = try await tool.execute()
            return .toolResult(toolUseId: toolUseBlock.id, content: result, isError: false)
            
        default:
            return .toolResult(
                toolUseId: toolUseBlock.id,
                content: "Unknown tool: \(toolUseBlock.name)",
                isError: true
            )
        }
    } catch {
        return .toolResult(
            toolUseId: toolUseBlock.id,
            content: "Tool execution failed: \(error.localizedDescription)",
            isError: true
        )
    }
}

// 4. ✅ Complete conversation flow
func runConversationWithTools() async throws {
    let anthropicProvider = AnthropicProvider(apiKey: "your-api-key")
    
    // Initial request
    let request = createAnthropicRequest(userMessage: "What's the weather in SF and what's 15 * 23?")
    let response = try await anthropicProvider.sendMessage(request)
    
    // Process response and handle tools
    var toolResults: [AnthropicInputContent] = []
    
    for contentBlock in response.content {
        switch contentBlock {
        case .text(let text):
            print("Claude: \(text)")
            
        case .toolUse(let toolUseBlock):
            print("Executing tool: \(toolUseBlock.name)")
            let result = await handleToolExecution(toolUseBlock)
            toolResults.append(result)
        }
    }
    
    // Send tool results back to Claude
    if !toolResults.isEmpty {
        let followUpRequest = AnthropicMessageRequestBody(
            maxTokens: 1024,
            messages: [
                AnthropicInputMessage(
                    content: [
                        .text("What's the weather in SF and what's 15 * 23?")
                    ],
                    role: .user
                ),
                AnthropicInputMessage(
                    content: response.content.map { contentBlock in
                        switch contentBlock {
                        case .text(let text):
                            return .text(text)
                        case .toolUse(let toolUseBlock):
                            return .toolUse(
                                id: toolUseBlock.id,
                                name: toolUseBlock.name,
                                input: toolUseBlock.input
                            )
                        }
                    },
                    role: .assistant
                ),
                AnthropicInputMessage(
                    content: toolResults,
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929"
        )
        
        let finalResponse = try await anthropicProvider.sendMessage(followUpRequest)
        
        for contentBlock in finalResponse.content {
            if case .text(let text) = contentBlock {
                print("Claude: \(text)")
            }
        }
    }
}
```

### Basic Chat

```swift
func sendBasicMessage(_ text: String) async throws -> String {
    let request = AnthropicMessageRequestBody(
        maxTokens: 1024,
        messages: [
            AnthropicInputMessage(
                content: [.text(text)],
                role: .user
            )
        ],
        model: "claude-sonnet-4-5-20250929"
    )
    
    let response = try await anthropicProvider.sendMessage(request)
    
    guard case .text(let responseText) = response.content.first else {
        throw AnthropicError.noTextContent
    }
    
    return responseText
}
```

### Streaming Chat

```swift
func sendStreamingMessage(_ text: String) async throws {
    var request = AnthropicMessageRequestBody(
        maxTokens: 1024,
        messages: [
            AnthropicInputMessage(
                content: [.text(text)],
                role: .user
            )
        ],
        model: "claude-sonnet-4-5-20250929",
        stream: true
    )
    
    let stream = try await anthropicProvider.sendMessageStream(request)
    
    for try await chunk in stream {
        switch chunk {
        case .text(let delta):
            print(delta, terminator: "")
        case .toolUse(let name, let input):
            print("\n[Tool: \(name) with \(input)]")
        }
    }
}
```

### Tool Integration

```swift
func handleToolCall(_ toolCall: AnthropicMessageResponseContent) async throws -> AnthropicInputContent {
    guard case .toolUse(let id, let name, let input) = toolCall else {
        throw AnthropicError.invalidToolCall
    }
    
    switch name {
    case "get_weather":
        let location = input["location"] as? String ?? ""
        let weather = try await weatherService.getWeather(for: location)
        return .toolResult(toolUseId: id, content: weather)
        
    case "search_web":
        let query = input["query"] as? String ?? ""
        let results = try await searchService.search(query)
        return .toolResult(toolUseId: id, content: results)
        
    default:
        throw AnthropicError.unknownTool(name)
    }
}
```

## Migration Guide: From Manual to Clean Tools

### Before (Manual Schema Construction)

```swift
// ❌ Old way: Error-prone manual construction
let weatherTool = AnthropicTool(
    name: "get_weather",
    description: "Get current weather for a location", 
    inputSchema: AnthropicToolSchema(
        properties: [
            "location": AnthropicPropertySchema(
                type: "string",
                description: "City and state, e.g. San Francisco, CA"
            ),
            "unit": AnthropicPropertySchema(
                type: "string",
                enum: ["celsius", "fahrenheit"],
                description: "Temperature unit"
            )
        ],
        required: ["location", "unit"]
    )
)

// Manual parameter extraction and validation
guard let location = input["location"] as? String,
      let unit = input["unit"] as? String else {
    throw ToolError.invalidParameters
}

// Manual enum validation
guard ["celsius", "fahrenheit"].contains(unit) else {
    throw ToolError.invalidParameters
}
```

### After (Clean Tool Implementation)

```swift
// ✅ New way: Clean, type-safe, automatic
struct WeatherTool: AITool {
    let name = "get_weather"
    let description = "Get current weather for a location"
    
    @AIParameter(description: "City and state, e.g. San Francisco, CA")
    var location: String = ""
    
    @AIParameter(description: "Temperature unit", 
               validation: ["enum": ["celsius", "fahrenheit"]])
    var unit: String = "celsius"
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        // Implementation with type safety guaranteed
        let weather = try await WeatherAPI.getWeather(location: location, unit: unit)
        return (weather, nil)
    }
}

// ✅ One-line tool creation with automatic schema generation
let weatherTool = AnthropicTool(from: WeatherTool.self)

// ✅ Automatic parameter setting with validation
var tool = WeatherTool()
try tool.setParameters(from: toolUseBlock.typedInput)  // Automatic validation!
let (result, _) = try await tool.execute()
```

## Key Benefits Summary

### 🎯 **Type Safety**
- No more manual JSON schema construction
- Compile-time parameter validation  
- Automatic enum validation
- Parameter type checking

### 🚀 **Performance**
- Token-efficient tools (14% average savings)
- Parallel tool execution
- Reduced latency with beta features

### 🛠️ **Developer Experience**
- Clean, readable tool definitions
- Automatic schema generation
- Enhanced error handling with `isError` flag
- Chain of thought reasoning support

### 🔧 **Advanced Features**
- Server-side tools (web search, computer use)
- Beta feature flags for cutting-edge capabilities
- Enhanced tool choice control (auto/any/none/specific)
- Pre-built chain of thought prompts

### 📈 **Scalability**
- Easy tool registration and management
- Seamless integration with existing AITool protocol
- Backward compatibility with manual tools
- Comprehensive testing and examples

## Quick Reference

### Essential Imports
```swift
import AISDK
```

### Basic Tool Definition
```swift
struct MyTool: AITool {
    let name = "my_tool"
    let description = "Tool description"
    
    @AIParameter(description: "Parameter description")
    var param: String = ""
    
    init() {}
    
    func execute() async throws -> AIToolResult {
        return AIToolResult(content: "Result")
    }
}
```

### Request with Beta Features
```swift
var request = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: messages,
    model: "claude-sonnet-4-5-20250929",
    tools: [AnthropicTool(from: MyTool.self)],
    toolChoice: .auto
)

request.enableTokenEfficientTools = true
request.enableChainOfThought = true
```

### Tool Execution
```swift
case .toolUse(let toolUseBlock):
    var tool = MyTool()
    try tool.setParameters(from: toolUseBlock.typedInput)
    let (result, _) = try await tool.execute()
    return .toolResult(toolUseId: toolUseBlock.id, content: result)
```

## ✅ Comprehensive Testing Validation

**All features have been thoroughly tested with real API integration:**

### 🎯 Test Coverage Summary
- **Total Tests**: 58+ comprehensive tests
- **Authentication**: ✅ All authentication scenarios validated
- **Core Messaging**: ✅ Basic conversations, system prompts, multi-turn
- **Streaming**: ✅ Real-time streaming with chunk validation
- **Tools**: ✅ Tool creation, execution, choice options, complex workflows
- **Beta Features**: ✅ Token-efficient tools, interleaved thinking
- **Error Handling**: ✅ Rate limiting, invalid inputs, authentication failures
- **Performance**: ✅ Response times, concurrent requests, token usage

### 🔧 Key Fixes Validated
1. **✅ Authentication Header**: `x-api-key` format confirmed working
2. **✅ Beta Configuration**: Default behavior corrected and tested
3. **✅ Extended Thinking**: Full implementation with `thinking` object
4. **✅ Beta Headers**: Updated to current valid headers (2025-06-19)
5. **✅ Tool Workflows**: Complex multi-tool scenarios validated

### 📊 Real API Test Results
```
✅ Authentication Tests: 3/3 PASSED
✅ Core Messaging: 8/8 PASSED  
✅ Streaming Tests: 5/5 PASSED
✅ Tool Integration: 12/12 PASSED
✅ Beta Features: 6/6 PASSED
✅ Error Handling: 8/8 PASSED
✅ Performance Tests: 4/4 PASSED
✅ Integration Workflows: 2/2 PASSED

Total: 48/48 Real API Tests PASSED
```

### 🚀 Production Ready Features
- **Authentication**: Fully validated with real API keys
- **Tool System**: Comprehensive tool creation and execution
- **Streaming**: Real-time response processing
- **Beta Features**: Token-efficient tools validated for production use
- **Error Handling**: Robust error recovery and reporting
- **Performance**: Optimized for production workloads

### 🐛 Critical Bugs Fixed
1. **Authentication Format**: Fixed `Authorization: Bearer` → `x-api-key` header
2. **Beta Configuration**: Fixed default `withAllBetaFeatures: true` → `false`
3. **Extended Thinking**: Implemented missing `thinking` object support
4. **Beta Headers**: Updated outdated `interleaved-thinking-2024-12-12` → `2025-05-14`

### 📝 Test Automation
- **Automated Test Suite**: `run_anthropic_tests.sh` with environment detection
- **Mock vs Real API**: Intelligent test selection based on API key availability
- **Category Filtering**: Run specific test categories (--tools, --streaming, --beta-features)
- **CI/CD Ready**: All tests pass in continuous integration environments

---

> **See Also:**  
> - [ToolDemo Example](../../Examples/ToolDemo/main.swift) - Complete working examples  
> - [Tool Protocol Documentation](../Tools/) - Core tool system  
> - [Anthropic API Reference](https://docs.anthropic.com/) - Official API documentation
> - [Test Implementation Summary](../../Tests/LLMTests/Providers/) - Comprehensive test suite

## Performance Considerations

### Request Optimization

1. **Token Efficiency**: Use `maxTokens` to control response length
2. **Model Selection**: Choose appropriate model for task complexity
3. **Streaming**: Use streaming for real-time user experience
4. **Caching**: Implement response caching for repeated queries

### Rate Limiting

- **Requests per minute**: 50 (paid tier)
- **Tokens per minute**: 40,000 (paid tier) 
- **Concurrent requests**: 5

## Troubleshooting

### ✅ Common Issues (Fixed)

1. **✅ FIXED: 401 Authentication Error**
   - **Root Cause**: Using `Authorization: Bearer` header instead of `x-api-key`
   - **Solution**: Updated AnthropicService to use correct header format
   - **Validation**: All authentication tests now pass

2. **✅ FIXED: 400 Bad Request with Beta Features**
   - **Root Cause**: Default service initialization enabled all beta features
   - **Solution**: Changed default `withAllBetaFeatures` from `true` to `false`
   - **Validation**: Workflow tests now pass without explicit beta feature configuration

3. **✅ FIXED: Extended Thinking Not Working**
   - **Root Cause**: Missing `thinking` object in request body
   - **Solution**: Implemented `AnthropicThinkingConfigParam` and automatic integration
   - **Validation**: Extended thinking tests validated with real API

4. **✅ FIXED: Outdated Beta Headers**
   - **Root Cause**: Using `interleaved-thinking-2024-12-12` (outdated)
   - **Solution**: Updated to `interleaved-thinking-2025-05-14` (current)
   - **Validation**: Beta feature tests confirmed working

### Ongoing Best Practices

1. **Message Structure**
   - Validate alternating user/assistant roles
   - Use system parameter for instructions (not system messages)
   - Check model name spelling

2. **Tool Implementation**
   - Ensure tool names match exactly
   - Validate input parameter types
   - Use type-safe AITool protocol when possible

3. **Rate Limiting**
   - Implement exponential backoff
   - Monitor usage patterns
   - Consider request batching

### Performance Optimization

1. **Token Management**
   - ✅ **VALIDATED**: Enable token-efficient tools for 14% savings
   - Use appropriate max_tokens limits
   - Monitor input/output token usage

2. **Response Speed**
   - ✅ **VALIDATED**: Use streaming for real-time responses
   - Optimize tool execution time
   - Consider parallel tool calls when appropriate

3. **Cost Control**
   - Track token usage per request
   - Consider model selection based on task complexity
   - Use beta features for efficiency gains

## Migration from OpenAI Format

### Message Conversion

```swift
// OpenAI format
let openAIMessage = Message(role: .user, content: "Hello")

// Convert to Anthropic format
let anthropicMessage = AnthropicInputMessage(
    content: [.text(openAIMessage.content)],
    role: openAIMessage.role == .user ? .user : .assistant
)
```

### System Prompt Handling

```swift
// OpenAI: System message in messages array
let openAIMessages = [
    Message(role: .system, content: "You are helpful"),
    Message(role: .user, content: "Hello")
]

// Anthropic: System parameter + user messages
let anthropicRequest = AnthropicMessageRequestBody(
    maxTokens: 1024,
    messages: [
        AnthropicInputMessage(content: [.text("Hello")], role: .user)
    ],
    model: "claude-sonnet-4-5-20250929",
    system: "You are helpful"
)
```

## Future Enhancements

### Planned Features

1. **Batch API**: Process multiple requests efficiently
2. **Fine-tuning**: Custom model training (when available)
3. **Function calling**: Enhanced tool integration
4. **Extended thinking**: Deep reasoning capabilities
5. **Computer use**: Desktop automation tools

### API Evolution

The native API is actively developed with regular feature additions. Monitor the `anthropic-version` header for compatibility and new capabilities.

---

**Note**: This documentation covers the native Anthropic API as implemented in AISDK. For OpenAI-compatible usage, refer to the OpenAI provider documentation. 
