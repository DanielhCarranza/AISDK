# ResponseAgent Usage Guide

The ResponseAgent class is AISDK's next-generation agent that leverages OpenAI's advanced Responses API for superior AI capabilities. It provides 100% Response API native experience with built-in tools, background processing, and seamless multimodal support.

## Table of Contents

1. [What's New](#whats-new)
2. [Overview](#overview)
3. [Initialization](#initialization)
4. [Basic Usage](#basic-usage)
5. [Built-in Tools](#built-in-tools)
6. [Streaming Conversations](#streaming-conversations)
7. [Background Processing](#background-processing)
8. [Multimodal Support](#multimodal-support)
9. [State Management](#state-management)
10. [MCP Integration](#mcp-integration)
11. [Error Handling](#error-handling)
12. [Advanced Examples](#advanced-examples)
13. [OpenAI Deep Research Agent](#openai-deep-research-agent)
14. [Best Practices](#best-practices)

## What's New

### Latest Enhancements (v2.0)

🎉 **Major Feature Updates:**

- **Enhanced State Management**: 10+ granular states including `reasoning`, `streamingResponse`, `backgroundProcessing`, `polling`
- **Advanced Background Processing**: New `BackgroundTaskConfiguration` with progress tracking, cancellation tokens, and reasoning extraction
- **MCP Integration**: Full Model Context Protocol support for external tool integrations
- **Parameter Consistency**: Renamed `customTools` to `tools` for better API consistency
- **Progress Tracking**: Real-time progress updates with percentage, current step, and time estimation
- **Reasoning Extraction**: Access to AI reasoning steps and detailed tool execution results
- **Enhanced Error Handling**: Comprehensive `ResponseAgentError` types with recovery suggestions
- **Cancellation Support**: Graceful task cancellation with `CancellationToken`

### Migration Guide

If upgrading from previous versions:

```swift
// OLD: v1.x
let agent = try ResponseAgent(
    provider: provider,
    customTools: [MyTool.self],  // ❌ Old parameter name
    builtInTools: [.webSearchPreview]
)

// NEW: v2.0
let agent = try ResponseAgent(
    provider: provider,
    tools: [MyTool.self],        // ✅ New parameter name
    builtInTools: [.webSearchPreview],
    mcpServers: [mcpConfig]      // ✅ New MCP support
)

// OLD: Basic background task
let response = try await agent.task("prompt", maxWaitTime: 300, pollInterval: 5)

// NEW: Enhanced background task
let result = try await agent.task("prompt", configuration: .detailed)
// Access detailed results: result.reasoning, result.toolExecutions, result.duration
```

## Overview

ResponseAgent provides significant advantages over the traditional Agent class:

- **100% Response API Native**: Leverages OpenAI's advanced Responses API for superior performance
- **Built-in Tools**: Native support for web search, code interpreter, image generation, and file search
- **Enhanced Background Processing**: Advanced task configuration with progress tracking, reasoning extraction, and cancellation support
- **Multimodal Support**: Seamless handling of text, images, and complex content
- **Granular State Management**: 10+ detailed states including reasoning, streaming content types, and background task status
- **MCP Integration**: Model Context Protocol support for external tool integrations
- **Advanced Error Handling**: Comprehensive error types with detailed recovery suggestions
- **Progress Tracking**: Real-time progress updates and cancellation tokens for long-running tasks
- **Reasoning Extraction**: Access to AI reasoning steps and tool execution details
- **Enhanced Streaming**: Real-time responses with semantic events and content type detection
- **Tool Conflict Detection**: Prevents naming conflicts between custom and built-in tools

### Key Differences from Agent

| Feature | Agent | ResponseAgent |
|---------|-------|---------------|
| **API Backend** | Chat Completions | Responses API |
| **Built-in Tools** | None | Web search, code interpreter, image generation, file search |
| **Background Processing** | Not supported | Native support with polling |
| **Multimodal** | Manual handling | Built-in support |
| **State Management** | Basic | Enhanced with tool execution states |
| **Streaming** | Delta-based | Semantic events |

## Initialization

### Basic Initialization

```swift
import AISDK

// Initialize with OpenAI provider
let provider = OpenAIProvider(apiKey: "your-openai-api-key")

let agent = try ResponseAgent(
    provider: provider,
    builtInTools: [.webSearchPreview, .codeInterpreter],
    instructions: "You are a helpful assistant with web search and code execution capabilities."
)

// Send a message
let response = try await agent.send("What's the latest news about AI?")
print("Response: \(response.displayContent)")
```

### With Built-in Tools

```swift
// Enable specific built-in tools
let agent = try ResponseAgent(
    provider: provider,
    tools: [],
    builtInTools: [
        .webSearchPreview,           // Web search capability
        .codeInterpreter,            // Code execution and analysis
        .imageGeneration(),          // Image generation
        .fileSearch(vectorStoreId: "vs_abc123") // File search in vector store
    ],
    instructions: "You are a research assistant with web search, code execution, and image generation capabilities."
)
```

### With Custom Tools

```swift
// Define custom tools
let customTools: [AITool.Type] = [
    WeatherTool.self,
    DatabaseQueryTool.self,
    EmailSenderTool.self
]

let agent = try ResponseAgent(
    provider: provider,
    tools: customTools,  // Updated parameter name
    builtInTools: [.webSearchPreview, .codeInterpreter],
    instructions: "You are a business assistant with custom tools and built-in capabilities."
)
```

### Advanced Configuration

```swift
let agent = try ResponseAgent(
    provider: provider,
    tools: [CustomAnalyticsTool.self],  // Updated parameter name
    builtInTools: [.webSearchPreview, .codeInterpreter, .imageGeneration(partialImages: 5)],
    instructions: """
    You are an advanced AI assistant with the following capabilities:
    - Web search for current information
    - Code execution for data analysis
    - Image generation for visual content
    - Custom analytics for business insights
    
    Always provide detailed, accurate responses with proper citations.
    """,
    model: "gpt-4o"
)
```

### MCP Integration

```swift
// Configure MCP servers for external integrations
let mcpServers = [
    MCPServerConfiguration(
        serverUrl: "https://your-mcp-server.com/endpoint",
        serverLabel: "internal_docs",
        requireApproval: .never,
        connectionTimeout: 30,
        requestTimeout: 120
    ),
    MCPServerConfiguration(
        serverUrl: "https://api.example.com/mcp",
        serverLabel: "external_api",
        requireApproval: .dangerous
    )
]

let agent = try ResponseAgent(
    provider: provider,
    tools: [CustomTool.self],
    builtInTools: [.webSearchPreview, .codeInterpreter],
    mcpServers: mcpServers,
    instructions: """
    You are an advanced assistant with access to:
    - Built-in tools for web search and code execution
    - Custom tools for specialized tasks
    - MCP servers for external integrations
    
    Use all available resources to provide comprehensive responses.
    """
)
```

## Basic Usage

### Simple Text Interaction

```swift
// Send a simple text message
let response = try await agent.send("Explain quantum computing")
print("Response: \(response.displayContent)")
```

### Streaming Responses

```swift
// Stream responses in real-time
for try await message in agent.send("Tell me a story", streaming: true) {
    if message.isPending {
        print("Streaming: \(message.displayContent)")
    } else {
        print("Final: \(message.displayContent)")
    }
}
```

### Multimodal Input

```swift
// Analyze image with text
let imageData = loadImageData("chart.png")
let contentParts: [AIContentPart] = [
    .text("Analyze this chart"),
    .image(AIImageContent(data: imageData))
]

let response = try await agent.send(contentParts)
print("Analysis: \(response.displayContent)")
```

## Built-in Tools

ResponseAgent includes powerful built-in tools that work seamlessly:

### Web Search

```swift
let agent = try ResponseAgent(
    provider: provider,
    builtInTools: [.webSearchPreview],
    instructions: "Provide current information using web search."
)

let response = try await agent.send("Latest renewable energy developments")
```

### Code Interpreter

```swift
let agent = try ResponseAgent(
    provider: provider,
    builtInTools: [.codeInterpreter],
    instructions: "Perform analysis and create visualizations."
)

let response = try await agent.send("Calculate fibonacci sequence and create chart")
```

### Image Generation

```swift
let agent = try ResponseAgent(
    provider: provider,
    builtInTools: [.imageGeneration()],
    instructions: "Create images when requested."
)

let response = try await agent.send("Create a futuristic city skyline")
```

### Multiple Tools Combined

```swift
// Combine multiple tools for complex tasks
let agent = try ResponseAgent(
    provider: provider,
    builtInTools: [.webSearchPreview, .codeInterpreter, .imageGeneration()],
    instructions: "Research, analyze, and visualize information as needed."
)

let response = try await agent.send("Research current AI trends, analyze the data, and create an infographic")
// Agent uses web search, code execution, and image generation together
```

## Streaming Conversations

Enhanced streaming with semantic events:

### Basic Streaming

```swift
func streamResponse(message: String) async throws {
    for try await response in agent.send(message, streaming: true) {
        DispatchQueue.main.async {
            if response.isPending {
                // Update UI with partial content
                updateChatUI(with: response.displayContent, isPending: true)
            } else {
                // Finalize the message
                updateChatUI(with: response.displayContent, isPending: false)
            }
        }
    }
}
```

### Streaming with Tool Execution

```swift
func streamWithTools(message: String) async throws {
    // Monitor agent state for tool execution
    agent.onStateChange = { state in
        DispatchQueue.main.async {
            switch state {
            case .processing:
                showStatus("Processing your request...")
            case .executingTool(let toolName):
                showStatus("Using \(toolName)...")
            case .responding:
                showStatus("Generating response...")
            case .idle:
                hideStatus()
            case .error(let error):
                showError(error.localizedDescription)
            default:
                break
            }
        }
    }
    
    for try await response in agent.send(message, streaming: true) {
        // Handle streaming response
        handleStreamingResponse(response)
    }
}
```

## Background Processing

Handle long-running tasks with enhanced background processing and progress tracking:

### Basic Background Task

```swift
// Execute long-running task in background
let result = try await agent.task(
    "Analyze this large dataset and provide comprehensive insights",
    configuration: .default
)

print("Background task completed: \(result.response.displayContent)")
print("Task duration: \(result.duration) seconds")
print("Tool executions: \(result.toolExecutions.count)")
```

### Enhanced Background Task Configuration

```swift
func executeAdvancedBackgroundTask(prompt: String) async throws {
    // Create cancellation token
    let cancellationToken = CancellationToken()
    
    // Configure background task with full options
    let configuration = BackgroundTaskConfiguration(
        maxWaitTime: 600,           // 10 minutes
        pollInterval: 5,            // Check every 5 seconds
        enableReasoning: true,      // Extract reasoning steps
        enableProgressTracking: true, // Track progress
        cancellationToken: cancellationToken,
        onProgress: { progress in
            DispatchQueue.main.async {
                updateProgressBar(progress.percentage)
                if let step = progress.currentStep {
                    updateStatusLabel(step)
                }
            }
        },
        onStatusChange: { status in
            DispatchQueue.main.async {
                switch status {
                case .queued:
                    showStatus("Task queued...")
                case .inProgress(let progress):
                    if let progress = progress {
                        showStatus("Processing... \(Int(progress * 100))%")
                    } else {
                        showStatus("Processing...")
                    }
                case .reasoning:
                    showStatus("Reasoning through problem...")
                case .executingTools:
                    showStatus("Executing tools...")
                case .completing:
                    showStatus("Finalizing results...")
                }
            }
        }
    )
    
    // Execute background task
    let result = try await agent.task(prompt, configuration: configuration)
    
    // Process detailed results
    print("Task completed in \(result.duration) seconds")
    print("Status: \(result.status)")
    
    // Access reasoning if available
    if let reasoning = result.reasoning {
        print("Reasoning steps:")
        for step in reasoning {
            print("- \(step.content)")
        }
    }
    
    // Review tool executions
    print("Tool executions:")
    for execution in result.toolExecutions {
        print("- \(execution.toolName): \(execution.duration)s")
    }
}
```

### Background Task with Cancellation

```swift
class BackgroundTaskManager {
    private var cancellationToken: CancellationToken?
    
    func startTask(prompt: String) async throws -> BackgroundTaskResult {
        // Create new cancellation token
        cancellationToken = CancellationToken()
        
        let configuration = BackgroundTaskConfiguration(
            maxWaitTime: 900,
            pollInterval: 10,
            enableReasoning: true,
            enableProgressTracking: true,
            cancellationToken: cancellationToken
        )
        
        return try await agent.task(prompt, configuration: configuration)
    }
    
    func cancelCurrentTask() {
        cancellationToken?.cancel()
        cancellationToken = nil
    }
}
```

### Background Task Error Handling

```swift
func robustBackgroundTask(prompt: String) async throws {
    do {
        let result = try await agent.task(
            prompt,
            configuration: .detailed  // Use detailed configuration
        )
        
        // Handle successful completion
        handleBackgroundResult(result)
        
    } catch ResponseAgentError.backgroundTaskTimeout(let taskId) {
        print("Task \(taskId) timed out after maximum wait time")
        // Optionally try to retrieve partial results
        
    } catch ResponseAgentError.backgroundTaskFailed(let message) {
        print("Task failed: \(message)")
        // Handle failure appropriately
        
    } catch ResponseAgentError.operationCancelled {
        print("Task was cancelled by user")
        // Handle cancellation
        
    } catch {
        print("Unexpected error: \(error)")
        // Handle other errors
    }
}

## Multimodal Support

ResponseAgent provides seamless multimodal support:

### Text and Image Analysis

```swift
// Analyze image with text description
let imageData = loadImageData("chart.png")
let contentParts: [AIContentPart] = [
    .text("Analyze this chart and explain the trends you see"),
    .image(AIImageContent(data: imageData))
]

let response = try await agent.send(contentParts)
print("Image analysis: \(response.displayContent)")
```

### Multiple Images Comparison

```swift
// Compare multiple images
let image1 = loadImageData("before.jpg")
let image2 = loadImageData("after.jpg")

let contentParts: [AIContentPart] = [
    .text("Compare these two images and describe the differences"),
    .image(AIImageContent(data: image1)),
    .image(AIImageContent(data: image2))
]

let response = try await agent.send(contentParts)
print("Comparison: \(response.displayContent)")
```

### Multimodal with Tools

```swift
// Combine image analysis with web search
let agent = try ResponseAgent(
    provider: provider,
    builtInTools: [.webSearchPreview, .imageGeneration()],
    instructions: "Analyze images and search for related information when needed."
)

let landmarkImage = loadImageData("landmark.jpg")
let contentParts: [AIContentPart] = [
    .text("What landmark is this? Search for information about it and create a similar artistic rendition"),
    .image(AIImageContent(data: landmarkImage))
]

let response = try await agent.send(contentParts)
// Agent identifies landmark, searches for info, and generates artistic version
```

## State Management

ResponseAgent provides enhanced state management:

### Enhanced State Monitoring

```swift
// Monitor all state changes with enhanced granular states
agent.onStateChange = { state in
    DispatchQueue.main.async {
        switch state {
        case .idle:
            updateStatusUI("Ready")
            enableInput()
            
        case .initializing:
            updateStatusUI("Initializing...")
            disableInput()
            
        case .processing:
            updateStatusUI("Processing...")
            disableInput()
            
        case .reasoning(let effort):
            if let effort = effort {
                updateStatusUI("Reasoning (\(effort))...")
            } else {
                updateStatusUI("Reasoning...")
            }
            
        case .executingTool(let toolName, let progress):
            if let progress = progress {
                updateStatusUI("Using \(toolName) (\(Int(progress * 100))%)...")
            } else {
                updateStatusUI("Using \(toolName)...")
            }
            
        case .streamingResponse(let contentType):
            switch contentType {
            case .text:
                updateStatusUI("Streaming response...")
            case .multimodal:
                updateStatusUI("Streaming multimodal content...")
            case .toolExecution:
                updateStatusUI("Streaming tool execution...")
            case .reasoning:
                updateStatusUI("Streaming reasoning...")
            }
            
        case .backgroundProcessing(let taskId, let status):
            switch status {
            case .queued:
                updateStatusUI("Background task queued...")
            case .inProgress(let progress):
                if let progress = progress {
                    updateStatusUI("Background processing (\(Int(progress * 100))%)...")
                } else {
                    updateStatusUI("Background processing...")
                }
            case .reasoning:
                updateStatusUI("Background reasoning...")
            case .executingTools:
                updateStatusUI("Background tool execution...")
            case .completing:
                updateStatusUI("Completing background task...")
            }
            
        case .polling(let taskId, let attempts):
            updateStatusUI("Polling task (\(attempts) attempts)...")
            
        case .completing:
            updateStatusUI("Completing...")
            
        case .error(let error):
            showError(error.localizedDescription)
            enableInput()
        }
    }
}
```

### State-Based UI Updates

```swift
func updateUIForState(_ state: ResponseAgentState) {
    switch state {
    case .idle:
        enableInputField()
        hideProgressIndicator()
        
    case .processing, .responding, .backgroundProcessing:
        disableInputField()
        showProgressIndicator()
        
    case .executingTool(let toolName):
        disableInputField()
        showToolExecutionIndicator(toolName)
        
    case .error(let error):
        enableInputField()
        showErrorMessage(error.localizedDescription)
    }
}
```

## MCP Integration

ResponseAgent supports Model Context Protocol (MCP) for integrating external tools and services:

### Basic MCP Configuration

```swift
// Configure MCP servers
let mcpServers = [
    MCPServerConfiguration(
        serverUrl: "https://internal-docs.company.com/mcp",
        serverLabel: "internal_knowledge",
        requireApproval: .never,
        connectionTimeout: 30,
        requestTimeout: 120
    )
]

let agent = try ResponseAgent(
    provider: provider,
    tools: [],
    builtInTools: [.webSearchPreview],
    mcpServers: mcpServers,
    instructions: "You have access to internal company knowledge via MCP integration."
)
```

### MCP Approval Levels

```swift
// Different approval levels for MCP operations
let mcpServers = [
    // Never require approval - trusted internal systems
    MCPServerConfiguration(
        serverUrl: "https://trusted-internal.com/mcp",
        serverLabel: "trusted_internal",
        requireApproval: .never
    ),
    
    // Always require approval - external services
    MCPServerConfiguration(
        serverUrl: "https://external-api.com/mcp",
        serverLabel: "external_service",
        requireApproval: .always
    ),
    
    // Require approval only for dangerous operations
    MCPServerConfiguration(
        serverUrl: "https://database.company.com/mcp",
        serverLabel: "database_access",
        requireApproval: .dangerous
    )
]
```

### Advanced MCP Usage

```swift
class MCPIntegratedAgent {
    private let agent: ResponseAgent
    
    init() throws {
        let mcpServers = [
            MCPServerConfiguration(
                serverUrl: "https://docs.internal.com/mcp",
                serverLabel: "internal_docs",
                requireApproval: .never
            ),
            MCPServerConfiguration(
                serverUrl: "https://customer-db.internal.com/mcp",
                serverLabel: "customer_data",
                requireApproval: .dangerous
            )
        ]
        
        self.agent = try ResponseAgent(
            provider: OpenAIProvider(apiKey: "your-api-key"),
            tools: [CustomAnalyticsTool.self],
            builtInTools: [.webSearchPreview, .codeInterpreter],
            mcpServers: mcpServers,
            instructions: """
            You are a business intelligence assistant with access to:
            - Internal documentation via MCP
            - Customer database via MCP (requires approval for sensitive operations)
            - Web search and code interpreter
            """
        )
    }
    
    func analyzeBusinessMetrics(query: String) async throws -> ResponseChatMessage {
        return try await agent.send("""
        Analyze business metrics: \(query)
        
        Use internal documentation and customer data as needed,
        supplement with web search for external context.
        """)
    }
}
```

## Error Handling

Comprehensive error handling:

### Basic Error Handling

```swift
do {
    let response = try await agent.send("Your message")
    print("Success: \(response.displayContent)")
    
} catch ResponseAgentError.agentBusy {
    print("Agent is currently processing another request")
    
} catch ResponseAgentError.toolExecutionFailed(let toolName, let error) {
    print("Tool \(toolName) failed: \(error?.localizedDescription ?? "Unknown error")")
    
} catch ResponseAgentError.toolNotFound(let toolName) {
    print("Tool \(toolName) not found in registry")
    
} catch ResponseAgentError.toolConflict(let customTool, let builtInTool) {
    print("Tool name conflict: \(customTool) conflicts with built-in \(builtInTool)")
    
} catch ResponseAgentError.backgroundTaskTimeout(let taskId) {
    print("Background task \(taskId) timed out")
    
} catch ResponseAgentError.backgroundTaskFailed(let message) {
    print("Background task failed: \(message)")
    
} catch ResponseAgentError.operationCancelled {
    print("Operation was cancelled by user")
    
} catch ResponseAgentError.invalidProvider(let message) {
    print("Provider error: \(message)")
    
} catch ResponseAgentError.invalidState(let message) {
    print("Invalid agent state: \(message)")
    
} catch ResponseAgentError.streamingError(let message) {
    print("Streaming error: \(message)")
    
} catch {
    print("Unexpected error: \(error.localizedDescription)")
}
```

### Error Recovery

```swift
func sendWithRetry(message: String, maxRetries: Int = 3) async throws -> ResponseChatMessage {
    for attempt in 1...maxRetries {
        do {
            let response = try await agent.send(message)
            return response
        } catch ResponseAgentError.agentBusy {
            if attempt < maxRetries {
                // Wait before retry
                try await Task.sleep(nanoseconds: 1_000_000_000 * UInt64(attempt))
                continue
            }
            throw ResponseAgentError.agentBusy
        } catch {
            // Don't retry for other errors
            throw error
        }
    }
    throw ResponseAgentError.operationCancelled
}
```

## Advanced Examples

### Research Assistant

```swift
class ResearchAssistant {
    private let agent: ResponseAgent
    
    init() throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        self.agent = try ResponseAgent(
            provider: provider,
            builtInTools: [.webSearchPreview, .codeInterpreter, .fileSearch(vectorStoreId: "research_db")],
            instructions: """
            You are a research assistant specialized in:
            - Finding current information via web search
            - Analyzing data and creating visualizations
            - Searching through research databases
            - Providing comprehensive, cited responses
            """
        )
    }
    
    func research(topic: String) async throws -> ResponseChatMessage {
        return try await agent.send("""
        Research the topic: \(topic)
        
        Please:
        1. Search for current information
        2. Analyze key trends and data
        3. Create visualizations if helpful
        4. Provide a comprehensive summary with citations
        """)
    }
    
    func analyzeData(description: String, data: Data) async throws -> ResponseChatMessage {
        let contentParts: [AIContentPart] = [
            .text("Analyze this data: \(description)"),
            .image(AIImageContent(data: data)) // Assuming data is image format
        ]
        
        return try await agent.send(contentParts)
    }
}
```

### Creative Assistant

```swift
class CreativeAssistant {
    private let agent: ResponseAgent
    
    init() throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        self.agent = try ResponseAgent(
            provider: provider,
            builtInTools: [.imageGeneration(partialImages: 5), .webSearchPreview],
            instructions: """
            You are a creative assistant that helps with:
            - Generating creative content and ideas
            - Creating visual content and artwork
            - Researching creative inspiration
            - Providing artistic guidance
            """
        )
    }
    
    func createContent(prompt: String, includeVisuals: Bool = true) async throws -> ResponseChatMessage {
        let fullPrompt = includeVisuals ? 
            "\(prompt)\n\nPlease create relevant visual content to accompany your response." :
            prompt
            
        return try await agent.send(fullPrompt)
    }
    
    func generateCampaign(theme: String) async throws -> ResponseChatMessage {
        return try await agent.send("""
        Create a comprehensive creative campaign for: \(theme)
        
        Include:
        1. Research current trends
        2. Develop creative concepts
        3. Generate visual mockups
        4. Provide detailed campaign strategy
        """)
    }
}
```

## OpenAI Deep Research Agent

Create a specialized agent for deep research using OpenAI's Deep Research capabilities:

### Deep Research Agent Implementation

```swift
class DeepResearchAgent {
    private let agent: ResponseAgent
    
    init() throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        self.agent = try ResponseAgent(
            provider: provider,
            builtInTools: [.webSearchPreview, .codeInterpreter],
            instructions: """
            You are a deep research specialist capable of:
            - Conducting comprehensive multi-source research
            - Analyzing complex topics from multiple angles
            - Synthesizing information into structured reports
            - Providing detailed citations and evidence
            - Creating data visualizations and charts
            """,
            model: "gpt-4o"
        )
    }
    
    func conductDeepResearch(query: String) async throws -> ResponseChatMessage {
        let researchPrompt = """
        Conduct deep research on: \(query)
        
        Please provide comprehensive analysis including:
        
        **Research Methodology:**
        - Break down into key sub-questions
        - Identify authoritative sources
        - Explain research approach
        
        **Findings:**
        - Current state and trends
        - Expert opinions and data
        - Quantitative statistics
        
        **Analysis:**
        - Synthesis of findings
        - Pattern identification
        - Critical evaluation
        - Future implications
        
        **Visualizations:**
        - Charts for key data points
        - Timeline of developments
        - Comparative analysis visuals
        
        **Citations:**
        - Detailed source citations
        - Links to original sources
        - Source credibility assessment
        
        Use web search extensively for current coverage.
        """
        
        return try await agent.task(researchPrompt, maxWaitTime: 600, pollInterval: 10)
    }
    
    func analyzeHealthcareEconomics(topic: String) async throws -> ResponseChatMessage {
        return try await conductDeepResearch("""
        Healthcare Economics Analysis: \(topic)
        
        Focus on:
        - Economic impact with specific figures
        - Cost-effectiveness analyses
        - Market size and projections
        - Regulatory implications
        - Regional cost variations
        - Healthcare system burden
        - ROI calculations
        - Patient access considerations
        """)
    }
}
```

### Using Deep Research Agent

```swift
// Initialize and use
let researchAgent = try DeepResearchAgent()

// Conduct research
let report = try await researchAgent.analyzeHealthcareEconomics(
    "economic impact of semaglutide on global healthcare systems"
)

print("Research Report:")
print(report.displayContent)

// General deep research
let techReport = try await researchAgent.conductDeepResearch(
    "impact of artificial intelligence on healthcare diagnostics"
)

print("Tech Analysis:")
print(techReport.displayContent)
```

### Advanced Deep Research with Custom Sources

```swift
class AdvancedDeepResearchAgent {
    private let agent: ResponseAgent
    
    init(vectorStoreId: String? = nil) throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        var builtInTools: [BuiltInTool] = [.webSearchPreview, .codeInterpreter]
        if let vectorStoreId = vectorStoreId {
            builtInTools.append(.fileSearch(vectorStoreId: vectorStoreId))
        }
        
        self.agent = try ResponseAgent(
            provider: provider,
            builtInTools: builtInTools,
            instructions: """
            You are an advanced deep research specialist with access to:
            - Web search for current information
            - Code interpreter for data analysis
            - File search for internal documents and research
            
            Provide comprehensive, data-driven reports with:
            - Multiple source verification
            - Quantitative analysis
            - Visual data representations
            - Detailed citations and methodology
            """,
            model: "gpt-4o"
        )
    }
    
    func researchWithInternalSources(query: String, internalContext: String? = nil) async throws -> ResponseChatMessage {
        var fullPrompt = "Deep research query: \(query)\n\n"
        
        if let context = internalContext {
            fullPrompt += "Internal context: \(context)\n\n"
        }
        
        fullPrompt += """
        Please conduct comprehensive research using:
        1. Web search for current public information
        2. File search for relevant internal documents
        3. Data analysis for quantitative insights
        4. Cross-reference findings across all sources
        
        Provide structured report with clear source attribution.
        """
        
        return try await agent.task(fullPrompt, maxWaitTime: 900, pollInterval: 15)
    }
}
```

## Best Practices

### 1. Efficient Tool Usage

```swift
// Use specific tools for specific tasks
let webSearchAgent = try ResponseAgent(
    provider: provider,
    builtInTools: [.webSearchPreview],
    instructions: "Focus on current information from web sources."
)

let analysisAgent = try ResponseAgent(
    provider: provider,
    builtInTools: [.codeInterpreter],
    instructions: "Specialize in data analysis and mathematical computations."
)
```

### 2. Proper State Management

```swift
// Always monitor state changes for better UX
agent.onStateChange = { state in
    // Update UI based on agent state
    updateUserInterface(for: state)
}
```

### 3. Error Recovery Strategies

```swift
func robustSend(message: String) async throws -> ResponseChatMessage {
    do {
        return try await agent.send(message)
    } catch ResponseAgentError.agentBusy {
        // Wait and retry for busy state
        try await Task.sleep(nanoseconds: 1_000_000_000)
        return try await agent.send(message)
    } catch ResponseAgentError.toolExecutionFailed(let toolName, _) {
        // Retry without the problematic tool
        print("Tool \(toolName) failed, retrying with basic capabilities")
        return try await agent.send("Please answer without using external tools: \(message)")
    }
}
```

### 4. Performance Optimization

```swift
// Use streaming for better user experience
func optimizedResponse(message: String) async throws {
    for try await response in agent.send(message, streaming: true) {
        // Immediately update UI as content arrives
        DispatchQueue.main.async {
            updateUIWithPartialContent(response.displayContent)
        }
    }
}
```

### 5. Conversation Management

```swift
// Periodically reset conversation to manage context length
func manageConversationLength() {
    if agent.messages.count > 20 {
        // Save important context
        let summary = summarizeConversation(agent.messages)
        
        // Reset and add summary
        agent.resetConversation()
        agent.setMessages([.system("Previous conversation summary: \(summary)")])
    }
}
```

---

## Summary

ResponseAgent provides a powerful, modern approach to AI agent development with:

- ✅ **100% Response API native experience**
- ✅ **Built-in tools for web search, code execution, and image generation**
- ✅ **Enhanced background processing with progress tracking and cancellation**
- ✅ **Seamless multimodal support**
- ✅ **Granular state management with 10+ detailed states**
- ✅ **MCP integration for external tool and service connections**
- ✅ **Advanced error handling with comprehensive error types**
- ✅ **Reasoning extraction and detailed tool execution tracking**
- ✅ **Real-time progress updates and cancellation tokens**
- ✅ **Deep research capabilities**
- ✅ **Production-ready implementation with extensive test coverage**

### Version 2.0 Enhancements

🚀 **Major improvements** include:
- **BackgroundTaskConfiguration** for advanced task control
- **CancellationToken** support for graceful operation cancellation
- **TaskProgress** tracking with percentage and time estimation
- **ReasoningStep** extraction from AI processing
- **ToolExecutionResult** detailed tracking
- **MCPServerConfiguration** for external integrations
- **Enhanced ResponseAgentState** with granular status tracking
- **Comprehensive ResponseAgentError** types with recovery guidance

Start with simple text interactions and progressively adopt advanced features like background processing with progress tracking, MCP integrations, multimodal input, and deep research capabilities as your needs grow! 