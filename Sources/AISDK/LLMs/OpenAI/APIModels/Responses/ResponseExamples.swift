//
//  ResponseExamples.swift
//  AISDK
//
//  Created by AISDK on 01/01/25.
//

import Foundation

/// Example usage patterns for the OpenAI Responses API
/// 
/// Note: These examples show the recommended approach using direct ResponseRequest construction.
public struct ResponseExamples {
    
    // MARK: - Basic Examples
    
    /// Example: Simple text response
    public static func simpleTextExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        // Method 1: Using convenience method
        let response = try await provider.createTextResponse(
            model: "gpt-4o",
            text: "Explain quantum computing in simple terms"
        )
        
        print("Response: \(response.outputText ?? "No response")")
    }
    
    /// Example: Using direct ResponseRequest construction (recommended)
    public static func directRequestExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Write a short story about AI"),
            instructions: "Make it engaging and under 200 words",
            temperature: 0.8,
            maxOutputTokens: 300
        )
        
        let response = try await provider.createResponse(request: request)
        print("Story: \(response.outputText ?? "No story generated")")
    }
    
    // MARK: - Tool Examples
    
    /// Example: Web search enabled response
    public static func webSearchExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        // Method 1: Using convenience method
        let response = try await provider.createResponseWithWebSearch(
            model: "gpt-4o",
            text: "What are the latest developments in renewable energy?"
        )
        
        print("Research: \(response.outputText ?? "No research found")")
        
        // Method 2: Using direct ResponseRequest with tools
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Current AI trends in 2025"),
            instructions: "Provide recent, factual information with sources",
            tools: [.webSearchPreview()]
        )

        let response2 = try await provider.createResponse(request: request)
        print("Trends: \(response2.outputText ?? "No trends found")")
    }
    
    /// Example: Code interpreter response
    public static func codeInterpreterExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        let response = try await provider.createResponseWithCodeInterpreter(
            model: "gpt-4o",
            text: "Calculate the first 20 Fibonacci numbers and create a visualization"
        )
        
        print("Code result: \(response.outputText ?? "No result")")
        
        // Check for code interpreter outputs
        for output in response.output {
            if case .codeInterpreterCall(let codeCall) = output {
                print("Code executed: \(codeCall.code ?? "No code")")
                print("Result: \(codeCall.result ?? "No result")")
            }
        }
    }
    
    /// Example: Multi-tool response
    public static func multiToolExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Research the latest AI models and create a comparison chart"),
            instructions: "Use web search for current info, then create a visual comparison",
            tools: [.webSearchPreview(), .codeInterpreter(), .imageGeneration()],
            temperature: 0.3
        )
        
        let response = try await provider.createResponse(request: request)
        print("Multi-tool result: \(response.outputText ?? "No result")")
    }
    
    // MARK: - Streaming Examples
    
    /// Example: Streaming text response
    public static func streamingExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        print("Streaming response:")
        
        for try await chunk in provider.createTextResponseStream(
            model: "gpt-4o",
            text: "Write a poem about the ocean"
        ) {
            if let delta = chunk.delta {
                if let text = delta.outputText {
                    print(text, terminator: "")
                }
            }
            
            // Check if response is complete
            if chunk.status?.isFinal == true {
                print("\n\nResponse completed with status: \(chunk.status?.rawValue ?? "unknown")")
            }
        }
    }
    
    /// Example: Streaming with web search
    public static func streamingWebSearchExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("What's happening in tech today?"),
            tools: [.webSearchPreview()],
            stream: true
        )
        
        print("Streaming web search response:")
        
        for try await chunk in provider.createResponseStream(request: request) {
            if let delta = chunk.delta {
                if let text = delta.outputText {
                    print(text, terminator: "")
                }
            }
        }
    }
    
    // MARK: - Advanced Examples
    
    /// Example: Background processing
    public static func backgroundProcessingExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Analyze this large dataset and provide insights"),
            tools: [.codeInterpreter()],
            background: true
        )
        
        let response = try await provider.createResponse(request: request)
        
        if response.status.isProcessing {
            print("Response is processing in background. ID: \(response.id)")
            
            // Poll for completion
            var finalResponse = response
            while finalResponse.status.isProcessing {
                try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                finalResponse = try await provider.retrieveResponse(id: response.id)
                print("Status: \(finalResponse.status.rawValue)")
            }
            
            print("Final result: \(finalResponse.outputText ?? "No result")")
        }
    }
    
    /// Example: Conversation continuation
    public static func conversationContinuationExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        // First response
        let firstResponse = try await provider.createTextResponse(
            model: "gpt-4o",
            text: "Start writing a story about a robot"
        )
        
        print("First part: \(firstResponse.outputText ?? "No response")")
        
        // Continue the conversation
        let continuationRequest = ResponseRequest(
            model: "gpt-4o",
            input: .string("Continue the story with more action"),
            instructions: "Build on the previous story",
            previousResponseId: firstResponse.id
        )
        
        let continuation = try await provider.createResponse(request: continuationRequest)
        print("Continuation: \(continuation.outputText ?? "No continuation")")
    }
    
    /// Example: Function calling
    public static func functionCallingExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        // Define a custom function
        let weatherFunction = ToolFunction(
            name: "get_weather",
            description: "Get current weather for a location",
            parameters: Parameters(
                type: "object",
                properties: [
                    "location": PropertyDefinition(
                        type: "string",
                        description: "The city and state, e.g. San Francisco, CA"
                    ),
                    "unit": PropertyDefinition(
                        type: "string",
                        description: "Temperature unit"
                    )
                ],
                required: ["location"]
            )
        )
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("What's the weather like in New York?"),
            tools: [.function(weatherFunction)]
        )
        
        let response = try await provider.createResponse(request: request)
        
        // Check for function calls
        for output in response.output {
            if case .functionCall(let functionCall) = output {
                print("Function called: \(functionCall.name)")
                print("Arguments: \(functionCall.arguments)")
                
                // In a real app, you would execute the function and provide the result
                // For this example, we'll simulate a response
                let functionResult = """
                {"temperature": 72, "condition": "sunny", "humidity": 45}
                """
                
                // Continue with function result
                let followUpRequest = ResponseRequest(
                    model: "gpt-4o",
                    input: .items([
                        .functionCallOutput(ResponseFunctionCallOutput(
                            callId: functionCall.callId,
                            output: functionResult
                        ))
                    ]),
                    previousResponseId: response.id
                )
                
                let finalResponse = try await provider.createResponse(request: followUpRequest)
                print("Final response: \(finalResponse.outputText ?? "No response")")
            }
        }
    }
    
    // MARK: - Error Handling Examples
    
    /// Example: Proper error handling
    public static func errorHandlingExample() async {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        do {
            let response = try await provider.createTextResponse(
                model: "gpt-4o",
                text: "Hello, world!"
            )
            print("Success: \(response.outputText ?? "No response")")
        } catch let error as LLMError {
            switch error {
            case .authenticationError:
                print("Authentication failed. Check your API key.")
            case .rateLimitExceeded:
                print("Rate limit exceeded. Please wait and try again.")
            case .networkError(let code, let message):
                print("Network error (\(code ?? 0)): \(message)")
            case .modelNotAvailable:
                print("The requested model is not available.")
            default:
                print("LegacyLLM Error: \(error.detailedDescription)")
            }
        } catch {
            print("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    /// Example: Response cancellation
    public static func cancellationExample() async throws {
        let provider = OpenAIProvider(apiKey: "your-api-key")
        
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Write a very long essay about AI"),
            background: true
        )
        
        let response = try await provider.createResponse(request: request)
        
        if response.status.isProcessing {
            print("Response started. Cancelling...")
            
            let cancelledResponse = try await provider.cancelResponse(id: response.id)
            print("Cancelled: \(cancelledResponse.status == .cancelled)")
        }
    }
} 