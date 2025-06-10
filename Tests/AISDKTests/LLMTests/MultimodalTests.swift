//
//  MultimodalTests.swift
//  AISDKTests
//
//  Created by AI Assistant
//

import XCTest
@testable import AISDK

final class MultimodalTests: XCTestCase {
    
    var mockProvider: MockLLMProvider!
    
    override func setUp() {
        super.setUp()
        mockProvider = MockLLMProvider()
    }
    
    override func tearDown() {
        mockProvider = nil
        super.tearDown()
    }
    
    // MARK: - Image URL Tests
    
    func testImageURLWithText() async throws {
        // Setup mock response for image analysis
        mockProvider.setMockResponse(ChatCompletionResponse(
            id: "test-image-url",
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: "gpt-4o",
            systemFingerprint: nil,
            serviceTier: nil,
            choices: [
                ChatCompletionResponse.Choice(
                    index: 0,
                    message: ChatCompletionResponse.Message(
                        role: "assistant",
                        content: "I can see a beautiful landscape with a wooden boardwalk extending through a green meadow. The image shows rolling hills in the background and a clear blue sky.",
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 120,
                completionTokens: 45,
                totalTokens: 165,
                completionTokensDetails: nil
            )
        ))
        
        let imageURL = "https://example.com/test-image.jpg"
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .parts([
                    .text("What do you see in this image?"),
                    .imageURL(.url(URL(string: imageURL)!))
                ]))
            ],
            maxTokens: 200
        )
        
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Verify response
        XCTAssertEqual(response.choices.count, 1)
        XCTAssertNotNil(response.choices.first?.message.content)
        XCTAssertTrue(response.choices.first?.message.content?.contains("landscape") ?? false)
        
        // Verify request was tracked
        XCTAssertEqual(mockProvider.requestCount, 1)
        XCTAssertNotNil(mockProvider.lastRequest)
    }
    
    func testImageURLWithInvalidURL() async throws {
        // Setup mock to simulate error
        mockProvider.shouldThrowError = true
        mockProvider.errorToThrow = LLMError.networkError(404, "Image not found")
        
        let invalidURL = "https://example.com/nonexistent-image.jpg"
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .parts([
                    .text("What do you see in this image?"),
                    .imageURL(.url(URL(string: invalidURL)!))
                ]))
            ]
        )
        
        do {
            _ = try await mockProvider.sendChatCompletion(request: request)
            XCTFail("Expected error to be thrown")
        } catch let error as LLMError {
            if case .networkError(let code, let message) = error {
                XCTAssertEqual(code, 404)
                XCTAssertEqual(message, "Image not found")
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        }
    }
    
    // MARK: - Base64 Image Tests
    
    func testBase64ImageWithText() async throws {
        // Create test image data (simulate base64 encoded image)
        let testImageData = "test-image-data".data(using: .utf8)!
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .parts([
                    .text("Describe this test image"),
                    .imageURL(.base64(testImageData))
                ]))
            ]
        )
        
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Verify response
        XCTAssertEqual(response.choices.count, 1)
        XCTAssertNotNil(response.choices.first?.message.content)
    }
    
    func testBase64ImageWithLargeData() async throws {
        // Test with large image data
        let largeImageData = Data(repeating: 0xFF, count: 1024 * 1024) // 1MB of data
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .parts([
                    .text("Analyze this large image"),
                    .imageURL(.base64(largeImageData))
                ]))
            ]
        )
        
        // Should not throw an error for large data
        let response = try await mockProvider.sendChatCompletion(request: request)
        XCTAssertNotNil(response)
    }
    
    // MARK: - Multiple Images Tests
    
    func testMultipleImagesComparison() async throws {
        let imageURL1 = "https://example.com/cat1.jpg"
        let imageURL2 = "https://example.com/cat2.jpg"
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .parts([
                    .text("Compare these two cat images"),
                    .imageURL(.url(URL(string: imageURL1)!)),
                    .imageURL(.url(URL(string: imageURL2)!))
                ]))
            ]
        )
        
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Verify response analyzes both images
        XCTAssertNotNil(response.choices.first?.message.content)
        let content = response.choices.first?.message.content ?? ""
        XCTAssertFalse(content.isEmpty)
    }
    
    func testMixedImageTypes() async throws {
        // Test mixing URL and base64 images
        let imageURL = "https://example.com/test.jpg"
        let base64Data = "test-data".data(using: .utf8)!
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .parts([
                    .text("Compare these different image types"),
                    .imageURL(.url(URL(string: imageURL)!)),
                    .imageURL(.base64(base64Data))
                ]))
            ]
        )
        
        let response = try await mockProvider.sendChatCompletion(request: request)
        XCTAssertNotNil(response)
        XCTAssertEqual(mockProvider.requestCount, 1)
    }
    
    // MARK: - Performance Tests
    
    func testMultimodalPerformance() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .parts([
                    .text("Quick image analysis"),
                    .imageURL(.url(URL(string: "https://example.com/test.jpg")!))
                ]))
            ]
        )
        
        _ = try await mockProvider.sendChatCompletion(request: request)
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(timeElapsed, 1.0, "Multimodal request should complete within 1 second")
    }
    
    // MARK: - Error Handling Tests
    
    func testImageProcessingErrors() async throws {
        // Test various error scenarios
        let errorScenarios: [(String, LLMError)] = [
            ("Network Error", .networkError(-1, "No internet")),
            ("Rate Limit", .rateLimitExceeded),
            ("Parsing Error", .parsingError("Invalid response"))
        ]
        
        for (scenario, expectedError) in errorScenarios {
            mockProvider.reset()
            mockProvider.shouldThrowError = true
            mockProvider.errorToThrow = expectedError
            
            let request = ChatCompletionRequest(
                model: "gpt-4o",
                messages: [
                    .user(content: .parts([
                        .text("Test \(scenario)"),
                        .imageURL(.url(URL(string: "https://example.com/test.jpg")!))
                    ]))
                ]
            )
            
            do {
                _ = try await mockProvider.sendChatCompletion(request: request)
                XCTFail("Expected error for scenario: \(scenario)")
            } catch {
                // Expected error
                XCTAssertTrue(error is LLMError, "Error should be LLMError type for \(scenario)")
            }
        }
    }
} 