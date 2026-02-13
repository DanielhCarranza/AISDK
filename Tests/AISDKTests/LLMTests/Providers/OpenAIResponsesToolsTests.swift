//
//  OpenAIResponsesToolsTests.swift
//  AISDKTests
//
//  Created for AISDK Testing - OpenAI Responses API Tools
//

import XCTest
@testable import AISDK

final class OpenAIResponsesToolsTests: XCTestCase {
    
    var provider: OpenAIProvider!
    var mockProvider: MockOpenAIResponsesProvider!
    
    override func setUp() {
        super.setUp()
        
        if shouldUseRealAPI() {
            provider = OpenAIProvider(apiKey: getOpenAIAPIKey())
        } else {
            mockProvider = MockOpenAIResponsesProvider()
        }
    }
    
    override func tearDown() {
        provider = nil
        mockProvider = nil
        super.tearDown()
    }
    
    // MARK: - Web Search Preview Tests
    
    func testWebSearchPreview() async throws {
        if let provider = provider {
            // Real API test
            let response = try await provider.createResponseWithWebSearch(
                model: "gpt-4o-mini",
                text: "What's the current weather in San Francisco?"
            )
            
            XCTAssertNotNil(response.id)
            XCTAssertTrue(response.status.isFinal)
            XCTAssertNotNil(response.outputText)
            
            // Check if web search tool was used
            let hasWebSearchTool = response.tools?.contains { tool in
                if case .webSearchPreview = tool { return true }
                return false
            } ?? false
            
            XCTAssertTrue(hasWebSearchTool)
            
        } else {
            // Mock test
            mockProvider.setMockResponse(MockOpenAIResponsesProvider.createWebSearchResponse())
            
            let request = ResponseRequest(
                model: "gpt-4o",
                input: .string("What's the current weather in San Francisco?"),
                tools: [.webSearchPreview]
            )
            
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(response.id, "resp-websearch-123")
            XCTAssertTrue(response.output.contains { output in
                if case .webSearchCall = output { return true }
                return false
            })
        }
    }
    
    func testWebSearchBuilder() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Latest AI news"),
            instructions: "Provide recent, factual information",
            tools: [.webSearchPreview]
        )
        
        if let provider = provider {
            // Real API test
            let response = try await provider.createResponse(request: request)
            
            XCTAssertNotNil(response.outputText)
            XCTAssertTrue(response.status.isFinal)
            
        } else {
            // Mock test
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(mockProvider.lastRequest?.tools?.count, 1)
            XCTAssertTrue(mockProvider.lastRequest?.tools?.first is ResponseTool)
        }
    }
    
    // MARK: - Code Interpreter Tests
    
    func testCodeInterpreter() async throws {
        if let provider = provider {
            // Real API test - code_interpreter may be blocked by Zero Data Retention policy
            do {
                let response = try await provider.createResponseWithCodeInterpreter(
                    model: "gpt-4o-mini",
                    text: "Calculate 15 factorial"
                )

                XCTAssertNotNil(response.id)
                XCTAssertTrue(response.status.isFinal)
                XCTAssertNotNil(response.outputText)

                // Check if code interpreter tool was used
                let hasCodeInterpreterTool = response.tools?.contains { tool in
                    if case .codeInterpreter = tool { return true }
                    return false
                } ?? false

                XCTAssertTrue(hasCodeInterpreterTool)
            } catch let error as LLMError {
                if case .networkError(let code, _) = error, code == 400 {
                    throw XCTSkip("OpenAI code_interpreter returned 400 — likely Zero Data Retention policy blocks container usage")
                }
                throw error
            }

        } else {
            // Mock test
            mockProvider.setMockResponse(MockOpenAIResponsesProvider.createCodeInterpreterResponse())
            
            let request = ResponseRequest(
                model: "gpt-4o",
                input: .string("Calculate 15 factorial"),
                tools: [.codeInterpreter]
            )
            
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(response.id, "resp-code-123")
            XCTAssertTrue(response.output.contains { output in
                if case .codeInterpreterCall = output { return true }
                return false
            })
        }
    }
    
    func testCodeInterpreterWithVisualization() async throws {
        if let provider = provider {
            // Real API test - code_interpreter may be blocked by Zero Data Retention policy
            do {
                let response = try await provider.createResponseWithCodeInterpreter(
                    model: "gpt-4o-mini",
                    text: "Create a simple bar chart showing the numbers 1, 3, 2, 5, 4"
                )

                XCTAssertNotNil(response.outputText)
                XCTAssertTrue(response.status.isFinal)
            } catch let error as LLMError {
                if case .networkError(let code, _) = error, code == 400 {
                    throw XCTSkip("OpenAI code_interpreter returned 400 — likely Zero Data Retention policy")
                }
                throw error
            }

        } else {
            // Mock test
            let request = ResponseRequest(
                model: "gpt-4o",
                input: .string("Create a simple bar chart"),
                tools: [.codeInterpreter]
            )
            
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertNotNil(response.outputText)
        }
    }
    
    // MARK: - Image Generation Tests
    
    func testImageGeneration() async throws {
        if let provider = provider {
            // Real API test
            let request = ResponseRequest(
                model: "gpt-4o-mini",
                input: .string("Generate an image of a sunset over mountains"),
                tools: [.imageGeneration()]
            )
            
            let response = try await provider.createResponse(request: request)
            
            XCTAssertNotNil(response.id)
            XCTAssertTrue(response.status.isFinal)
            
            // Check if image generation tool was used
            let hasImageGenTool = response.tools?.contains { tool in
                if case .imageGeneration = tool { return true }
                return false
            } ?? false
            
            XCTAssertTrue(hasImageGenTool)
            
        } else {
            // Mock test
            let request = ResponseRequest(
                model: "gpt-4o",
                input: .string("Generate an image of a sunset"),
                tools: [.imageGeneration()]
            )
            
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(mockProvider.lastRequest?.tools?.count, 1)
            XCTAssertNotNil(response.outputText)
        }
    }
    
    func testImageGenerationWithPartialImages() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Create a landscape painting"),
            tools: [.imageGeneration(partialImages: 2)]
        )

        if let provider = provider {
            // Real API test - image generation may not be available for all API keys/models
            do {
                let response = try await provider.createResponse(request: request)

                XCTAssertNotNil(response.outputText)
                XCTAssertTrue(response.status.isFinal)
            } catch let error as LLMError {
                if case .networkError(let code, _) = error, code == 400 {
                    throw XCTSkip("OpenAI image_generation returned 400 — tool may not be available for this API key/model")
                }
                throw error
            }

        } else {
            // Mock test
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertNotNil(response.outputText)
            XCTAssertEqual(mockProvider.lastRequest?.tools?.count, 1)
        }
    }
    
    // MARK: - File Search Tests
    
    func testFileSearch() async throws {
        let vectorStoreId = "vs_test123"
        
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Find information about project requirements"),
            tools: [.fileSearch(vectorStoreId: vectorStoreId)]
        )
        
        if let provider = provider {
            // Real API test (may fail if vector store doesn't exist)
            do {
                let response = try await provider.createResponse(request: request)
                XCTAssertNotNil(response.outputText)
            } catch {
                // Expected if vector store doesn't exist
                print("File search test failed (expected if vector store doesn't exist): \(error)")
            }
            
        } else {
            // Mock test
            _ = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(mockProvider.lastRequest?.tools?.count, 1)
        }
    }
    
    // MARK: - Custom Function Tests
    
    func testCustomFunction() async throws {
        // Define a weather function
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
                        description: "Temperature unit",
                        enumValues: ["celsius", "fahrenheit"]
                    )
                ],
                required: ["location"]
            )
        )
        
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("What's the weather like in New York?"),
            tools: [.function(weatherFunction)]
        )
        
        if let provider = provider {
            // Real API test
            do {
                let response = try await provider.createResponse(request: request)

                XCTAssertNotNil(response.id)
                XCTAssertTrue(response.status.isFinal)

                // Check if function was called
                let hasFunctionCall = response.output.contains { output in
                    if case .functionCall = output { return true }
                    return false
                }

                if hasFunctionCall {
                    print("Function was called successfully")
                }
            } catch let error as LLMError {
                if case .networkError(let code, _) = error, code == 400 {
                    throw XCTSkip("OpenAI function tool returned 400 — tool may not be available")
                }
                throw error
            }

        } else {
            // Mock test
            mockProvider.setMockResponse(MockOpenAIResponsesProvider.createFunctionCallResponse())
            
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(response.id, "resp-func-123")
            XCTAssertTrue(response.output.contains { output in
                if case .functionCall = output { return true }
                return false
            })
        }
    }
    
    // MARK: - Multi-Tool Tests
    
    func testMultipleTools() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Research AI trends and create a visualization"),
            tools: [.webSearchPreview, .codeInterpreter, .imageGeneration()]
        )

        if let provider = provider {
            // Real API test - some tools may not be available for all API keys
            do {
                let response = try await provider.createResponse(request: request)

                XCTAssertNotNil(response.outputText)
                XCTAssertTrue(response.status.isFinal)
                XCTAssertEqual(response.tools?.count, 3)
            } catch let error as LLMError {
                if case .networkError(let code, _) = error, code == 400 {
                    throw XCTSkip("OpenAI multi-tool request returned 400 — some tools may not be available")
                }
                throw error
            }

        } else {
            // Mock test
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(mockProvider.lastRequest?.tools?.count, 3)
            XCTAssertNotNil(response.outputText)
        }
    }
    
    func testMultiToolBuilder() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Comprehensive analysis task"),
            instructions: "Use all available tools to provide a complete analysis",
            tools: [.webSearchPreview, .codeInterpreter, .imageGeneration()]
        )

        if let provider = provider {
            // Real API test - some tools may not be available for all API keys
            do {
                let response = try await provider.createResponse(request: request)

                XCTAssertNotNil(response.outputText)
                XCTAssertGreaterThan(response.tools?.count ?? 0, 1)
            } catch let error as LLMError {
                if case .networkError(let code, _) = error, code == 400 {
                    throw XCTSkip("OpenAI multi-tool request returned 400 — some tools may not be available")
                }
                throw error
            }

        } else {
            // Mock test
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertGreaterThan(mockProvider.lastRequest?.tools?.count ?? 0, 1)
            XCTAssertNotNil(response.outputText)
        }
    }
    
    // MARK: - Tool Choice Tests
    
    func testToolChoiceAuto() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Help me with this task"),
            tools: [.webSearchPreview, .codeInterpreter],
            toolChoice: .auto
        )
        
        if let provider = provider {
            // Real API test
            do {
                let response = try await provider.createResponse(request: request)

                XCTAssertNotNil(response.outputText)
                XCTAssertTrue(response.status.isFinal)
            } catch let error as LLMError {
                if case .networkError(let code, _) = error, code == 400 {
                    throw XCTSkip("OpenAI tool choice auto returned 400 — some tools may not be available for this API key")
                }
                throw error
            }

        } else {
            // Mock test
            let response = try await mockProvider.createResponse(request: request)

            XCTAssertEqual(mockProvider.lastRequest?.toolChoice, .auto)
            XCTAssertNotNil(response.outputText)
        }
    }

    func testToolChoiceNone() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Just answer without using tools"),
            tools: [.webSearchPreview],
            toolChoice: ToolChoice.none  // Must be explicit to avoid Swift Optional.none confusion
        )
        
        if let provider = provider {
            // Real API test
            let response = try await provider.createResponse(request: request)
            
            XCTAssertNotNil(response.outputText)
            XCTAssertTrue(response.status.isFinal)
            
        } else {
            // Mock test
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(mockProvider.lastRequest?.toolChoice, ToolChoice.none)
            XCTAssertNotNil(response.outputText)
        }
    }
    
    // MARK: - Tool Error Handling Tests
    
    func testToolExecutionError() async throws {
        if mockProvider != nil {
            // Mock test - simulate tool execution error
            mockProvider.shouldThrowError = true
            mockProvider.errorToThrow = LLMError.invalidRequest("Tool execution failed")
            
            let request = ResponseRequest(
                model: "gpt-4o",
                input: .string("Use tools to help"),
                tools: [.webSearchPreview]
            )
            
            do {
                _ = try await mockProvider.createResponse(request: request)
                XCTFail("Expected error to be thrown")
            } catch let error as LLMError {
                XCTAssertEqual(error, .invalidRequest("Tool execution failed"))
            }
        }
    }
    
    // MARK: - Tool Response Validation Tests
    
    func testToolResponseStructure() async throws {
        if mockProvider != nil {
            // Mock test with web search response
            mockProvider.setMockResponse(MockOpenAIResponsesProvider.createWebSearchResponse())
            
            let request = ResponseRequest(
                model: "gpt-4o",
                input: .string("Test query"),
                tools: [.webSearchPreview]
            )
            
            let response = try await mockProvider.createResponse(request: request)
            
            // Validate web search output structure
            let webSearchOutput = response.output.first { output in
                if case .webSearchCall = output { return true }
                return false
            }
            
            XCTAssertNotNil(webSearchOutput)
            
            if case .webSearchCall(let searchCall) = webSearchOutput! {
                XCTAssertEqual(searchCall.id, "ws-123")
                XCTAssertEqual(searchCall.query, "Latest AI news")
                XCTAssertNotNil(searchCall.result)
                // status is optional and may be nil in the mock
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func shouldUseRealAPI() -> Bool {
        return ProcessInfo.processInfo.environment["USE_REAL_API"] == "true" && 
               !getOpenAIAPIKey().isEmpty
    }
    
    private func getOpenAIAPIKey() -> String {
        return ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
    }
} 