//
//  ResponseUsageDemo.swift
//  AISDK
//
//  Created by AISDK on 01/01/25.
//

import Foundation

/// Quick start guide and usage examples for the OpenAI Responses API
public struct ResponseUsageDemo {
    
    // MARK: - Quick Start Examples
    
    /// 🚀 Simplest possible usage - just text
    public static func quickStart() async throws {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        let response = try await provider.createTextResponse(
            model: "gpt-4o",
            text: "Hello! Explain what you can do."
        )
        
        print("AI Response: \(response.outputText ?? "No response")")
    }
    
    /// 🔍 Web search enabled response
    public static func withWebSearch() async throws {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        let response = try await provider.createResponseWithWebSearch(
            model: "gpt-4o",
            text: "What are the latest AI developments in 2025?"
        )
        
        print("Research Result: \(response.outputText ?? "No result")")
    }
    
    /// 💻 Code interpreter for data analysis
    public static func withCodeInterpreter() async throws {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        let response = try await provider.createResponseWithCodeInterpreter(
            model: "gpt-4o",
            text: "Generate the first 10 Fibonacci numbers and create a simple visualization"
        )
        
        print("Code Result: \(response.outputText ?? "No result")")
    }
    
    /// ⚡ Streaming response for real-time output
    public static func streamingResponse() async throws {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        print("Streaming response: ", terminator: "")
        
        for try await chunk in provider.createTextResponseStream(
            model: "gpt-4o",
            text: "Write a short poem about technology"
        ) {
            if let text = chunk.delta?.outputText {
                print(text, terminator: "")
            }
        }
        print("\n") // New line after streaming
    }
    
    // MARK: - Direct Request Examples
    
    /// 🏗️ Using direct request construction for complex requests
    public static func directRequestPattern() async throws {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Analyze the current state of renewable energy"),
            instructions: "Provide a comprehensive analysis with recent data",
            tools: [.webSearchPreview, .codeInterpreter],
            temperature: 0.3,
            maxOutputTokens: 1000
        )
        
        let response = try await provider.createResponse(request: request)
        print("Analysis: \(response.outputText ?? "No analysis")")
    }
    
    /// 🎨 Multi-tool request with image generation
    public static func multiToolRequest() async throws {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Create a data visualization about climate change"),
            instructions: "First research current climate data, then create a compelling visualization",
            tools: [.webSearchPreview, .codeInterpreter, .imageGeneration()]
        )
        
        let response = try await provider.createResponse(request: request)
        print("Multi-tool result: \(response.outputText ?? "No result")")
    }
    
    // MARK: - Advanced Usage
    
    /// 🔄 Conversation continuation
    public static func conversationContinuation() async throws {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        // First message
        let firstResponse = try await provider.createTextResponse(
            model: "gpt-4o",
            text: "Start writing a story about a robot discovering emotions"
        )
        
        print("Chapter 1: \(firstResponse.outputText ?? "No story")")
        
        // Continue the story
        let continuation = ResponseRequest(
            model: "gpt-4o",
            input: .string("Continue the story with more character development"),
            instructions: "Build on the previous story, adding depth to the robot character",
            previousResponseId: firstResponse.id
        )
        
        let secondResponse = try await provider.createResponse(request: continuation)
        print("Chapter 2: \(secondResponse.outputText ?? "No continuation")")
    }
    
    /// ⏱️ Background processing for long tasks
    public static func backgroundProcessing() async throws {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Perform a comprehensive analysis of this large dataset"),
            tools: [.codeInterpreter],
            background: true
        )
        
        let response = try await provider.createResponse(request: request)
        
        if response.status.isProcessing {
            print("Task started in background. ID: \(response.id)")
            
            // Poll for completion
            var currentResponse = response
            while currentResponse.status.isProcessing {
                print("Status: \(currentResponse.status.rawValue)")
                try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                currentResponse = try await provider.retrieveResponse(id: response.id)
            }
            
            print("Final result: \(currentResponse.outputText ?? "No result")")
        }
    }
    
    // MARK: - Error Handling Best Practices
    
    /// 🛡️ Proper error handling
    public static func errorHandling() async {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        do {
            let response = try await provider.createTextResponse(
                model: "gpt-4o",
                text: "Hello, world!"
            )
            print("Success: \(response.outputText ?? "No response")")
            
        } catch let error as LLMError {
            switch error {
            case .authenticationError:
                print("❌ Authentication failed. Please check your API key.")
            case .rateLimitExceeded:
                print("⏳ Rate limit exceeded. Please wait and try again.")
            case .networkError(let code, let message):
                print("🌐 Network error (\(code ?? 0)): \(message)")
            case .modelNotAvailable:
                print("🤖 The requested model is not available.")
            default:
                print("⚠️ LLM Error: \(error.detailedDescription)")
            }
        } catch {
            print("💥 Unexpected error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Real-World Use Cases
    
    /// 📊 Data analysis workflow
    public static func dataAnalysisWorkflow() async throws {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("""
                I have sales data for Q4 2024. Please:
                1. Research current market trends
                2. Analyze the data patterns
                3. Create visualizations
                4. Provide actionable insights
                """),
            instructions: "Be thorough and provide specific recommendations",
            tools: [.webSearchPreview, .codeInterpreter],
            temperature: 0.2 // Lower temperature for analytical tasks
        )
        
        let response = try await provider.createResponse(request: request)
        print("Analysis Complete: \(response.outputText ?? "No analysis")")
    }
    
    /// 🎓 Educational content creation
    public static func educationalContent() async throws {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Create an interactive lesson about quantum computing for beginners"),
            instructions: "Make it engaging with examples and visual aids",
            tools: [.webSearchPreview, .imageGeneration()],  // Get latest information and create diagrams
            temperature: 0.7  // Higher temperature for creative content
        )
        
        let response = try await provider.createResponse(request: request)
        print("Lesson Created: \(response.outputText ?? "No lesson")")
    }
    
    /// 🔬 Research assistant
    public static func researchAssistant() async throws {
        let provider = OpenAIProvider(apiKey: "your-openai-api-key")
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Research the latest developments in sustainable energy storage"),
            instructions: """
                Provide a comprehensive research summary including:
                - Latest technological breakthroughs
                - Key companies and researchers
                - Market implications
                - Future outlook
                """,
            tools: [.webSearchPreview],
            maxOutputTokens: 2000
        )
        
        let response = try await provider.createResponse(request: request)
        print("Research Summary: \(response.outputText ?? "No research")")
    }
}

// MARK: - Usage Tips

/*
 💡 USAGE TIPS:
 
 1. **Model Selection**:
    - Use "gpt-4o" for most tasks
    - Use "gpt-4o-mini" for simpler, faster responses
    - Use "o1" models for complex reasoning tasks
 
 2. **Tool Selection**:
    - .webSearchPreview: For current information
    - .codeInterpreter: For data analysis, calculations, visualizations
    - .imageGeneration: For creating images and diagrams
    - .fileSearch: For searching through uploaded documents
 
 3. **Temperature Settings**:
    - 0.0-0.3: Analytical, factual tasks
    - 0.4-0.7: Balanced creativity and accuracy
    - 0.8-1.0: Creative writing, brainstorming
 
 4. **Streaming vs Non-Streaming**:
    - Use streaming for long responses to show progress
    - Use non-streaming for short responses or when you need the complete result
 
 5. **Background Processing**:
    - Use for complex tasks that might take time
    - Always poll for completion status
    - Handle timeouts gracefully
 
 6. **Error Handling**:
    - Always wrap API calls in try-catch blocks
    - Handle specific error types appropriately
    - Provide user-friendly error messages
 
 7. **Rate Limiting**:
    - Implement exponential backoff for rate limit errors
    - Consider batching requests when possible
    - Monitor your usage to avoid unexpected limits
 */ 