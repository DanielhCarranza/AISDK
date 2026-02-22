//
//  OpenAIResponsesAPITests.swift
//  AISDKTests
//
//  Created for AISDK Testing - OpenAI Responses API Core Functionality
//

import XCTest
@testable import AISDK

final class OpenAIResponsesAPITests: XCTestCase {
    
    var provider: OpenAIProvider!
    var mockProvider: MockOpenAIResponsesProvider!
    
    override func setUp() {
        super.setUp()
        
        // Check if we should use real API or mock
        if shouldUseRealAPI() {
            provider = OpenAIProvider(apiKey: getOpenAIAPIKey())
        } else {
            // For mock testing, we'll test the models directly
            mockProvider = MockOpenAIResponsesProvider()
        }
    }
    
    override func tearDown() {
        provider = nil
        mockProvider = nil
        super.tearDown()
    }
    
    // MARK: - Basic Response Creation Tests
    
    func testBasicResponseCreation() async throws {
        if let provider = provider {
            // Real API test
            let response = try await provider.createTextResponse(
                model: "gpt-4o-mini", // Use mini for faster/cheaper testing
                text: "Say hello in one word",
                maxOutputTokens: 20
            )

            XCTAssertNotNil(response.id)
            XCTAssertEqual(response.object, "response")
            XCTAssertTrue(response.model.contains("gpt-4o-mini"), "Expected model containing 'gpt-4o-mini', got: \(response.model)")
            XCTAssertTrue(response.status.isFinal)
            XCTAssertNotNil(response.outputText)
            XCTAssertFalse(response.output.isEmpty)
            
        } else {
            // Mock test
            let request = ResponseRequest(
                model: "gpt-4o",
                input: .string("Say hello in one word")
            )
            
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(mockProvider.requestCount, 1)
            XCTAssertNotNil(mockProvider.lastRequest)
            XCTAssertEqual(response.status, .completed)
            XCTAssertNotNil(response.outputText)
            XCTAssertEqual(response.model, "gpt-4o")
        }
    }
    
    func testResponseCreationWithBuilder() async throws {
        if let provider = provider {
            // Real API test
            let request = ResponseRequest(
                model: "gpt-4o-mini",
                input: .string("What is 2+2?"),
                instructions: "Answer with just the number",
                temperature: 0.1,
                maxOutputTokens: 20
            )

            let response = try await provider.createResponse(request: request)

            XCTAssertNotNil(response.id)
            XCTAssertTrue(response.status.isFinal)
            XCTAssertNotNil(response.outputText)

        } else {
            // Mock test
            let request = ResponseRequest(
                model: "gpt-4o",
                input: .string("What is 2+2?"),
                instructions: "Answer with just the number",
                temperature: 0.1,
                maxOutputTokens: 20
            )
            
            _ = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(mockProvider.lastRequest?.instructions, "Answer with just the number")
            XCTAssertEqual(mockProvider.lastRequest?.temperature, 0.1)
            XCTAssertEqual(mockProvider.lastRequest?.maxOutputTokens, 20)
        }
    }
    
    func testResponseCreationWithMultipleInputItems() async throws {
        let inputItems: [ResponseInputItem] = [
            .message(ResponseMessage(
                role: "user",
                content: [
                    .inputText(ResponseInputText(text: "Hello, how are you?"))
                ]
            ))
        ]
        
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .items(inputItems)
        )
        
        if let provider = provider {
            // Real API test
            let response = try await provider.createResponse(request: request)
            
            XCTAssertNotNil(response.id)
            XCTAssertTrue(response.status.isFinal)
            XCTAssertNotNil(response.outputText)
            
        } else {
            // Mock test
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(response.status, .completed)
            XCTAssertNotNil(response.outputText)
        }
    }
    
    // MARK: - Response Retrieval Tests
    
    func testResponseRetrieval() async throws {
        if let provider = provider {
            // Real API test - create with store=true so retrieval is valid.
            let request = ResponseRequest(
                model: "gpt-4o-mini",
                input: .string("Say hello"),
                maxOutputTokens: 20,
                store: true
            )
            let createResponse = try await provider.createResponse(request: request)

            var retrievedResponse: ResponseObject?
            var lastError: Error?
            for attempt in 1...10 {
                do {
                    if attempt > 1 {
                        try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                    }
                    retrievedResponse = try await provider.retrieveResponse(id: createResponse.id)
                    break
                } catch {
                    lastError = error
                    if attempt == 10 {
                        if let llmError = error as? LLMError,
                           case .invalidRequest(let message) = llmError,
                           message.contains("store: true") {
                            throw XCTSkip("OpenAI retrieval not available for this API key/account even when store:true is set")
                        }
                        throw error
                    }
                }
            }

            if retrievedResponse == nil, let error = lastError as? LLMError,
               case .invalidRequest(let message) = error,
               message.contains("store: true") {
                throw XCTSkip("OpenAI retrieval not available for this API key/account even when store:true is set")
            }

            XCTAssertNotNil(retrievedResponse)
            XCTAssertEqual(retrievedResponse?.id, createResponse.id)
            XCTAssertEqual(retrievedResponse?.model, createResponse.model)
            XCTAssertTrue(retrievedResponse?.status.isFinal == true)

        } else {
            // Mock test
            let responseId = "test-response-id"
            let response = try await mockProvider.retrieveResponse(id: responseId)
            
            XCTAssertEqual(mockProvider.lastRetrieveId, responseId)
            XCTAssertNotNil(response.id)
            XCTAssertEqual(response.status, .completed)
        }
    }
    
    // MARK: - Response Cancellation Tests
    
    func testResponseCancellation() async throws {
        if let provider = provider {
            // Real API test - create a background response that we can cancel
            let request = ResponseRequest(
                model: "gpt-4o-mini",
                input: .string("Write a very long essay about AI"),
                background: true
            )
            
            let createResponse = try await provider.createResponse(request: request)
            
            // If it's still processing, try to cancel it
            if createResponse.status.isProcessing {
                let cancelledResponse = try await provider.cancelResponse(id: createResponse.id)
                
                // The response should either be cancelled or completed
                XCTAssertTrue(cancelledResponse.status == .cancelled || cancelledResponse.status.isFinal)
            }
            
        } else {
            // Mock test
            let responseId = "test-response-id"
            let response = try await mockProvider.cancelResponse(id: responseId)
            
            XCTAssertEqual(mockProvider.lastCancelId, responseId)
            XCTAssertEqual(response.status, .cancelled)
        }
    }
    
    // MARK: - Parameter Validation Tests
    
    func testMaxOutputTokensMinimumValidation() throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Test message"),
            maxOutputTokens: 10
        )

        XCTAssertThrowsError(try request.validate()) { error in
            guard case .invalidRequest(let message) = error as? LLMError else {
                return XCTFail("Expected LLMError.invalidRequest, got: \(error)")
            }
            XCTAssertTrue(message.contains("at least 16"))
        }
    }

    func testModelParameterValidation() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Test message"),
            temperature: 0.7,
            topP: 0.9,
            maxOutputTokens: 200
        )
        
        if let provider = provider {
            // Real API test
            let response = try await provider.createResponse(request: request)
            XCTAssertNotNil(response.id)
            
        } else {
            // Mock test
            let response = try await mockProvider.createResponse(request: request)
            
            XCTAssertEqual(mockProvider.lastRequest?.model, "gpt-4o")
            XCTAssertEqual(mockProvider.lastRequest?.temperature, 0.7)
            XCTAssertEqual(mockProvider.lastRequest?.topP, 0.9)
            XCTAssertEqual(mockProvider.lastRequest?.maxOutputTokens, 200)
        }
    }
    
    func testInputFormatValidation() async throws {
        // Test string input
        let stringRequest = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Simple string input")
        )
        
        // Test items input
        let itemsRequest = ResponseRequest(
            model: "gpt-4o-mini",
            input: .items([
                .message(ResponseMessage(
                    role: "user",
                    content: [.inputText(ResponseInputText(text: "Items input"))]
                ))
            ])
        )
        
        if let provider = provider {
            // Real API tests
            let stringResponse = try await provider.createResponse(request: stringRequest)
            XCTAssertNotNil(stringResponse.outputText)
            
            let itemsResponse = try await provider.createResponse(request: itemsRequest)
            XCTAssertNotNil(itemsResponse.outputText)
            
        } else {
            // Mock tests
            let stringResponse = try await mockProvider.createResponse(request: stringRequest)
            XCTAssertNotNil(stringResponse.outputText)
            
            let itemsResponse = try await mockProvider.createResponse(request: itemsRequest)
            XCTAssertNotNil(itemsResponse.outputText)
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidModelError() async throws {
        let request = ResponseRequest(
            model: "invalid-model-name",
            input: .string("Test message")
        )
        
        if let provider = provider {
            // Real API test - should throw an error
            do {
                _ = try await provider.createResponse(request: request)
                XCTFail("Expected error for invalid model")
            } catch {
                // Expected error
                XCTAssertTrue(error is LLMError || error is AISDKError)
            }
            
        } else {
            // Mock test - configure to throw error
            mockProvider.shouldThrowError = true
            mockProvider.errorToThrow = LLMError.modelNotAvailable
            
            do {
                _ = try await mockProvider.createResponse(request: request)
                XCTFail("Expected error to be thrown")
            } catch let error as LLMError {
                XCTAssertEqual(error, .modelNotAvailable)
            }
        }
    }
    
    func testNetworkErrorHandling() async throws {
        if mockProvider != nil {
            // Mock test only - simulate network error
            mockProvider.shouldThrowError = true
            mockProvider.errorToThrow = AISDKError.httpError(500, "Internal Server Error")
            
            let request = ResponseRequest(
                model: "gpt-4o",
                input: .string("Test message")
            )
            
            do {
                _ = try await mockProvider.createResponse(request: request)
                XCTFail("Expected error to be thrown")
            } catch let error as AISDKError {
                if case .httpError(let code, let message) = error {
                    XCTAssertEqual(code, 500)
                    XCTAssertEqual(message, "Internal Server Error")
                } else {
                    XCTFail("Unexpected error type: \(error)")
                }
            }
        }
    }
    
    // MARK: - Response Structure Tests
    
    func testResponseStructureValidation() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Hello"),
            metadata: ["test": "value"]
        )
        
        if let provider = provider {
            // Real API test
            let response = try await provider.createResponse(request: request)
            
            // Validate response structure
            XCTAssertFalse(response.id.isEmpty)
            XCTAssertEqual(response.object, "response")
            XCTAssertGreaterThan(response.createdAt, 0)
            XCTAssertTrue(response.model.contains("gpt-4o-mini"), "Expected model to contain 'gpt-4o-mini', got: \(response.model)")
            XCTAssertTrue(response.status.isFinal)
            XCTAssertFalse(response.output.isEmpty)
            XCTAssertNotNil(response.usage)
            
        } else {
            // Mock test
            let response = try await mockProvider.createResponse(request: request)
            
            // Validate mock response structure
            XCTAssertFalse(response.id.isEmpty)
            XCTAssertEqual(response.object, "response")
            XCTAssertGreaterThan(response.createdAt, 0)
            XCTAssertEqual(response.model, "gpt-4o-mini")
            XCTAssertEqual(response.status, .completed)
            XCTAssertFalse(response.output.isEmpty)
            XCTAssertNotNil(response.usage)
        }
    }
    
    // MARK: - Debug Tests
    
    func testDebugMinimalRequest() async throws {
        let provider = MockOpenAIResponsesProvider()
        
        // Test with absolute minimal request
        let minimalRequest = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Hello")
        )
        
        let response = try await provider.createResponse(request: minimalRequest)
        
        XCTAssertEqual(response.status, .completed)
        XCTAssertNotNil(response.outputText)
        
        print("✅ Minimal request works with mock provider")
        print("Response: \(response.outputText ?? "No output")")
    }
    
    func testDebugRequestSerialization() throws {
        // Test that our request can be serialized properly
        let request = ResponseRequest(
            model: "gpt-4o-mini", 
            input: .string("Hello"),
            maxOutputTokens: 20
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(request)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        print("📄 Serialized request JSON:")
        print(jsonString)
        
        // Basic validation that essential fields are present
        XCTAssertTrue(jsonString.contains("\"model\""))
        XCTAssertTrue(jsonString.contains("\"input\""))
        XCTAssertTrue(jsonString.contains("gpt-4o-mini"))
        XCTAssertTrue(jsonString.contains("Hello"))
        
        print("✅ Request serialization works")
    }
    
    func testDebugComplexRequestSerialization() throws {
        // Test a more complex request with multiple optional fields
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Hello"),
            instructions: "Be helpful",
            temperature: 0.7,
            maxOutputTokens: 200,
            store: true,
            parallelToolCalls: true
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(request)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        print("📄 Complex request JSON:")
        print(jsonString)
        
        // Verify complex fields are properly encoded
        XCTAssertTrue(jsonString.contains("\"instructions\""))
        XCTAssertTrue(jsonString.contains("\"temperature\""))
        XCTAssertTrue(jsonString.contains("\"max_output_tokens\""))
        XCTAssertTrue(jsonString.contains("\"store\""))
        XCTAssertTrue(jsonString.contains("\"parallel_tool_calls\""))
        
        print("✅ Complex request serialization works")
    }
    
    func testDebugMinimalRequestWithRealAPI() async throws {
        guard shouldUseRealAPI() else {
            print("⚠️ Skipping real API debug test")
            return
        }
        
        let provider = OpenAIProvider(apiKey: getOpenAIAPIKey())
        
        // Test 1: Direct ResponseRequest (working)
        let directRequest = ResponseRequest(
            model: "gpt-4o-mini", 
            input: .string("Hello")
        )
        
        // Test 2: Direct text request (modern approach)
        let builderRequest = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Hello")
        )
        
        // Test 3: Direct web search request
        let webSearchRequest = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Hello"),
            tools: [.webSearchPreview()]
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        print("🔍 DEBUG: Comparing request JSONs...")
        
        // Show direct request JSON
        let directJsonData = try encoder.encode(directRequest)
        let directJsonString = String(data: directJsonData, encoding: .utf8)!
        print("\n📄 Direct Request JSON (working):")
        print(directJsonString)
        
        // Show equivalent text request JSON  
        let builderJsonData = try encoder.encode(builderRequest)
        let builderJsonString = String(data: builderJsonData, encoding: .utf8)!
        print("\n📄 Direct Text Request JSON (modern approach):")
        print(builderJsonString)
        
        // Show web search request JSON
        let webSearchJsonData = try encoder.encode(webSearchRequest)
        let webSearchJsonString = String(data: webSearchJsonData, encoding: .utf8)!
        print("\n📄 Web Search Request JSON (working):")
        print(webSearchJsonString)
        
        // Test all three
        print("\n🧪 Testing direct request...")
        do {
            let directResponse = try await provider.createResponse(request: directRequest)
            print("✅ SUCCESS: Direct request worked!")
            print("Response: \(directResponse.outputText ?? "No output")")
        } catch {
            print("❌ ERROR: Direct request failed: \(error)")
        }
        
        print("\n🧪 Testing direct text request...")
        do {
            let builderResponse = try await provider.createResponse(request: builderRequest)
            print("✅ SUCCESS: Direct text request worked!")
            print("Response: \(builderResponse.outputText ?? "No output")")
        } catch {
            print("❌ ERROR: Direct text request failed: \(error)")
        }
        
        print("\n🧪 Testing web search request...")
        do {
            let webSearchResponse = try await provider.createResponse(request: webSearchRequest)
            print("✅ SUCCESS: Web search request worked!")
            print("Response: \(webSearchResponse.outputText ?? "No output")")
        } catch {
            print("❌ ERROR: Web search request failed: \(error)")
        }
    }
    
    func testDebugExactBasicResponseRequest() async throws {
        guard shouldUseRealAPI() else {
            print("⚠️ Skipping exact basic response debug test")
            return
        }
        
        let provider = OpenAIProvider(apiKey: getOpenAIAPIKey())
        
        print("🔍 DEBUG: Testing exact createTextResponse call that fails...")
        
        // First, let's see what request is actually being created
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Say hello in exactly 5 words"),
            maxOutputTokens: 20
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let requestData = try encoder.encode(request)
        let requestString = String(data: requestData, encoding: .utf8)!
        
        print("📄 Request JSON with maxOutputTokens:")
        print(requestString)
        
        do {
            let response = try await provider.createTextResponse(
                model: "gpt-4o-mini",
                text: "Say hello in exactly 5 words",
                maxOutputTokens: 20
            )
            
            print("✅ SUCCESS: createTextResponse worked!")
            print("Response model: \(response.model)")
            print("Response status: \(response.status)")
            print("Response outputText: \(response.outputText ?? "nil")")
            print("Response output count: \(response.output.count)")
            print("Response output types: \(response.output.map { String(describing: type(of: $0)) })")
            
            // Log the full response structure
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let responseData = try? encoder.encode(response),
               let responseString = String(data: responseData, encoding: .utf8) {
                print("📄 Full Response JSON:")
                print(responseString)
            }
            
        } catch {
            print("❌ ERROR: createTextResponse failed: \(error)")
            
            if let llmError = error as? LLMError {
                print("LLMError details: \(llmError)")
            }
            
            // Now let's try the same request but through direct createResponse
            print("\n🔍 Trying same request through createResponse...")
            do {
                let directResponse = try await provider.createResponse(request: request)
                print("✅ SUCCESS: Direct createResponse worked!")
                print("Response: \(directResponse.outputText ?? "nil")")
            } catch {
                print("❌ ERROR: Direct createResponse also failed: \(error)")
            }
        }
    }
    
    func testDebugMaxOutputTokensValues() async throws {
        guard shouldUseRealAPI() else {
            print("⚠️ Skipping max output tokens debug test")
            return
        }
        
        let provider = OpenAIProvider(apiKey: getOpenAIAPIKey())
        
        print("🔍 DEBUG: Testing different maxOutputTokens values...")
        
        let values = [20, 50, 100, 500, nil]
        
        for maxTokens in values {
            print("\n🧪 Testing maxOutputTokens: \(maxTokens?.description ?? "nil")")
            
            do {
                let response = try await provider.createTextResponse(
                    model: "gpt-4o-mini",
                    text: "Say hello",
                    maxOutputTokens: maxTokens
                )
                
                print("✅ SUCCESS with maxOutputTokens=\(maxTokens?.description ?? "nil")")
                print("Response: \(response.outputText ?? "nil")")
                
            } catch {
                print("❌ FAILED with maxOutputTokens=\(maxTokens?.description ?? "nil"): \(error)")
            }
        }
    }
    
    func testDebugActualAPIResponse() async throws {
        guard shouldUseRealAPI() else {
            print("⚠️ Skipping debug API response test")
            return
        }
        
        let provider = OpenAIProvider(apiKey: getOpenAIAPIKey())
        
        print("🔍 DEBUG: Capturing actual API response...")
        
        // Create a simple request
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Say 'Hello World'")
        )
        
        do {
            let response = try await provider.createResponse(request: request)
            
            print("📄 FULL RESPONSE OBJECT DEBUG:")
            print("- ID: \(response.id)")
            print("- Object: \(response.object)")
            print("- Model: \(response.model)")
            print("- Status: \(response.status)")
            print("- Output Array Count: \(response.output.count)")
            
            // Debug output array
            for (index, outputItem) in response.output.enumerated() {
                print("- Output[\(index)]: \(outputItem)")
            }
            
            print("- OutputText Property: \(response.outputText ?? "NIL")")
            if let usage = response.usage {
                print("- Usage: input=\(usage.inputTokens), output=\(usage.outputTokens), total=\(usage.totalTokens)")
            } else {
                print("- Usage: NIL")
            }
            
            // Try to encode response back to JSON to see its structure
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let responseData = try encoder.encode(response)
            let responseJSON = String(data: responseData, encoding: .utf8)!
            
            print("📄 FULL RESPONSE JSON:")
            print(responseJSON)
            
            print("✅ Debug complete - investigate outputText extraction")
            
        } catch {
            print("❌ ERROR in debug test: \(error)")
            throw error
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