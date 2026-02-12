//
//  BasicChatTests.swift
//  AISDKTests
//
//  Created for AISDK Testing
//

import XCTest
@testable import AISDK

final class BasicChatTests: XCTestCase {
    
    var mockProvider: MockLLMProvider!
    
    override func setUp() {
        super.setUp()
        mockProvider = MockLLMProvider()
    }
    
    override func tearDown() {
        mockProvider = nil
        super.tearDown()
    }
    
    // MARK: - Basic Chat Completion Tests
    
    func testBasicChatCompletion() async throws {
        // Given
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [
                .user(content: .text("Hello, how are you?"))
            ]
        )
        
        // When
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Then
        XCTAssertEqual(mockProvider.requestCount, 1)
        XCTAssertNotNil(mockProvider.lastRequest)
        XCTAssertEqual(response.choices.count, 1)
        XCTAssertEqual(response.choices.first?.message.role, "assistant")
        XCTAssertNotNil(response.choices.first?.message.content)
        XCTAssertEqual(response.model, "test-model")
    }
    
    func testChatCompletionWithMultipleMessages() async throws {
        // Given
        let messages: [LegacyMessage] = [
            .system(content: .text("You are a helpful assistant.")),
            .user(content: .text("What is 2+2?")),
            .assistant(content: .text("2+2 equals 4.")),
            .user(content: .text("What about 3+3?"))
        ]
        
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: messages
        )
        
        // When
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Then
        XCTAssertEqual(mockProvider.lastRequest?.messages.count, 4)
        XCTAssertNotNil(response.choices.first?.message.content)
        XCTAssertEqual(response.choices.first?.finishReason, "stop")
    }
    
    func testChatCompletionWithParameters() async throws {
        // Given
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [.user(content: .text("Tell me a joke"))],
            frequencyPenalty: 0.1,
            maxTokens: 100,
            presencePenalty: 0.1,
            temperature: 0.7,
            topP: 0.9
        )
        
        // When
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Then
        let lastRequest = mockProvider.lastRequest!
        XCTAssertEqual(lastRequest.model, "gpt-4")
        XCTAssertEqual(lastRequest.maxTokens, 100)
        XCTAssertEqual(lastRequest.temperature, 0.7)
        XCTAssertEqual(lastRequest.topP, 0.9)
        XCTAssertEqual(lastRequest.frequencyPenalty, 0.1)
        XCTAssertEqual(lastRequest.presencePenalty, 0.1)
        XCTAssertNotNil(response.usage)
    }
    
    // MARK: - Error Handling Tests
    
    func testChatCompletionErrorHandling() async throws {
        // Given
        mockProvider.shouldThrowError = true
        mockProvider.errorToThrow = AISDKError.httpError(400, "Bad Request")
        
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [.user(content: .text("Hello"))]
        )
        
        // When & Then
        do {
            _ = try await mockProvider.sendChatCompletion(request: request)
            XCTFail("Expected error to be thrown")
        } catch let error as AISDKError {
            if case .httpError(let code, let message) = error {
                XCTAssertEqual(code, 400)
                XCTAssertEqual(message, "Bad Request")
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }
    
    // MARK: - LegacyMessage Content Type Tests
    
    func testChatCompletionWithTextContent() async throws {
        // Given
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [.user(content: .text("Simple text message"))]
        )
        
        // When
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Then
        XCTAssertTrue(response.choices.first?.message.content?.contains("Simple text message") ?? false)
    }
    
    func testChatCompletionWithMultipartContent() async throws {
        // Given
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [
                .user(content: .parts([
                    .text("Describe this image:"),
                    .imageURL(.url(URL(string: "https://example.com/image.jpg")!))
                ]))
            ]
        )
        
        // When
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Then
        XCTAssertNotNil(response.choices.first?.message.content)
        XCTAssertEqual(mockProvider.lastRequest?.messages.count, 1)
    }
    
    // MARK: - Custom Response Tests
    
    func testChatCompletionWithCustomMockResponse() async throws {
        // Given
        let customResponse = ChatCompletionResponse(
            id: "custom-id",
            object: "chat.completion",
            created: 1234567890,
            model: "custom-model",
            systemFingerprint: "custom-fingerprint",
            serviceTier: nil,
            choices: [
                ChatCompletionResponse.Choice(
                    index: 0,
                    message: ChatCompletionResponse.LegacyMessage(
                        role: "assistant",
                        content: "Custom mock response content",
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 5,
                completionTokens: 10,
                totalTokens: 15,
                completionTokensDetails: nil
            )
        )
        
        mockProvider.setMockResponse(customResponse)
        
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [.user(content: .text("Test"))]
        )
        
        // When
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Then
        XCTAssertEqual(response.id, "custom-id")
        XCTAssertEqual(response.model, "custom-model")
        XCTAssertEqual(response.choices.first?.message.content, "Custom mock response content")
        XCTAssertEqual(response.usage?.promptTokens, 5)
        XCTAssertEqual(response.usage?.completionTokens, 10)
        XCTAssertEqual(response.usage?.totalTokens, 15)
    }
    
    // MARK: - Request Tracking Tests
    
    func testRequestTracking() async throws {
        // Given
        XCTAssertEqual(mockProvider.requestCount, 0)
        XCTAssertNil(mockProvider.lastRequest)
        
        let request1 = ChatCompletionRequest(
            model: "model-1",
            messages: [.user(content: .text("First request"))]
        )
        
        let request2 = ChatCompletionRequest(
            model: "model-2",
            messages: [.user(content: .text("Second request"))]
        )
        
        // When
        _ = try await mockProvider.sendChatCompletion(request: request1)
        XCTAssertEqual(mockProvider.requestCount, 1)
        XCTAssertEqual(mockProvider.lastRequest?.model, "model-1")
        
        _ = try await mockProvider.sendChatCompletion(request: request2)
        
        // Then
        XCTAssertEqual(mockProvider.requestCount, 2)
        XCTAssertEqual(mockProvider.lastRequest?.model, "model-2")
    }
    
    func testProviderReset() async throws {
        // Given
        _ = try await mockProvider.sendChatCompletion(request: ChatCompletionRequest(
            model: "test",
            messages: [.user(content: .text("Test"))]
        ))
        
        XCTAssertEqual(mockProvider.requestCount, 1)
        XCTAssertNotNil(mockProvider.lastRequest)
        
        // When
        mockProvider.reset()
        
        // Then
        XCTAssertEqual(mockProvider.requestCount, 0)
        XCTAssertNil(mockProvider.lastRequest)
        XCTAssertFalse(mockProvider.shouldThrowError)
    }
    
    // MARK: - Performance Tests
    
    func testChatCompletionPerformance() throws {
        // Given
        mockProvider.delay = 0.01 // Reduce delay for performance test
        
        let request = ChatCompletionRequest(
            model: "test-model",
            messages: [.user(content: .text("Performance test"))]
        )
        
        // When & Then
        measure {
            let expectation = XCTestExpectation(description: "Chat completion")
            
            Task {
                do {
                    _ = try await mockProvider.sendChatCompletion(request: request)
                    expectation.fulfill()
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    // MARK: - Integration Tests with Real OpenAI Provider
    
    func testOpenAIIntegration() async throws {
        // Skip if no API key is available
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY environment variable is required for integration tests")
        }
        
        // Get model from environment variable or use default
        let model = ProcessInfo.processInfo.environment["TEST_MODEL"] ?? "gpt-4o"
        
        print("🧠 Testing OpenAI with model: \(model)")
        
        // Initialize real OpenAI provider
        let provider = OpenAIProvider(apiKey: apiKey)
        
        // Create request
        let request = ChatCompletionRequest(
            model: model,
            messages: [
                .system(content: .text("You are a helpful assistant. Think through your response carefully.")),
                .user(content: .text("What is the capital of France? Explain your reasoning."))
            ],
            maxTokens: 200
        )
        
        // When
        let response = try await provider.sendChatCompletion(request: request)
        
        // Then
        XCTAssertFalse(response.choices.isEmpty, "Response should have at least one choice")
        XCTAssertNotNil(response.choices.first?.message.content, "Response should have content")
        XCTAssertNotNil(response.usage, "Response should include usage information")
        
        let content = response.choices.first?.message.content ?? ""
        XCTAssertTrue(content.contains("Paris"), "Response should mention Paris")
        
        print("✅ Response: \(content)")
        print("📊 Usage: \(response.usage?.totalTokens ?? 0) tokens")
        print("🏷️  Returned model: \(response.model)")
    }
} 