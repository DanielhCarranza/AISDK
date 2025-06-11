//
//  MultimodalTests.swift
//  AISDKTests
//
//  Created by AI Assistant
//

import XCTest
@testable import AISDK

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
    
    // MARK: - Integration Tests with Real OpenAI Provider
    
    func testOpenAIImageURL() async throws {
        // Skip if no API key is available
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY environment variable is required for integration tests")
        }
        
        // Get model from environment variable or use default
        let model = ProcessInfo.processInfo.environment["TEST_MODEL"] ?? "gpt-4o"
        
        print("🖼️ Testing OpenAI image URL analysis with model: \(model)")
        
        // Initialize real OpenAI provider
        let provider = OpenAIProvider(apiKey: apiKey)
        
        // Use a simple nature image (same as main.swift)
        let imageURL = "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"
        
        let request = ChatCompletionRequest(
            model: model,
            messages: [
                .user(content: .parts([
                    .text("Describe this nature scene briefly. What do you see?"),
                    .imageURL(.url(URL(string: imageURL)!))
                ]))
            ],
            maxTokens: 150
        )
        
        // When
        let response = try await provider.sendChatCompletion(request: request)
        
        // Then
        XCTAssertFalse(response.choices.isEmpty)
        XCTAssertNotNil(response.choices.first?.message.content)
        
        let content = response.choices.first?.message.content ?? ""
        XCTAssertFalse(content.isEmpty)
        
        // Should mention nature elements
        let lowerContent = content.lowercased()
        XCTAssertTrue(
            lowerContent.contains("water") || 
            lowerContent.contains("wood") || 
            lowerContent.contains("boardwalk") ||
            lowerContent.contains("path") ||
            lowerContent.contains("nature") ||
            lowerContent.contains("green"),
            "Response should describe the boardwalk nature scene"
        )
        
        print("✅ Image URL analysis: \(content)")
        print("📊 Usage: \(response.usage?.totalTokens ?? 0) tokens")
        print("🏷️  Returned model: \(response.model)")
    }
    
    func testOpenAIImageBase64() async throws {
        // Skip if no API key is available
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY environment variable is required for integration tests")
        }
        
        // Get model from environment variable or use default
        let model = ProcessInfo.processInfo.environment["TEST_MODEL"] ?? "gpt-4o"
        
        print("🖼️ Testing OpenAI base64 image analysis with model: \(model)")
        
        // Initialize real OpenAI provider
        let provider = OpenAIProvider(apiKey: apiKey)
        
        // Load image from Tests/Assets/baltolo.webp
        guard let testImageData = loadTestImage() else {
            throw XCTSkip("Could not load test image from Tests/Assets/baltolo.webp")
        }
        
        let request = ChatCompletionRequest(
            model: model,
            messages: [
                .user(content: .parts([
                    .text("Describe what you see in this image. What is the main subject?"),
                    .imageURL(.base64(testImageData))
                ]))
            ],
            maxTokens: 150
        )
        
        // When
        let response = try await provider.sendChatCompletion(request: request)
        
        // Then
        XCTAssertFalse(response.choices.isEmpty)
        XCTAssertNotNil(response.choices.first?.message.content)
        
        let content = response.choices.first?.message.content ?? ""
        XCTAssertFalse(content.isEmpty)
        
        print("✅ Base64 image analysis: \(content)")
        print("📊 Usage: \(response.usage?.totalTokens ?? 0) tokens")
        print("🏷️  Returned model: \(response.model)")
    }
    
    func testOpenAIMultipleImages() async throws {
        // Skip if no API key is available
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY environment variable is required for integration tests")
        }
        
        // Get model from environment variable or use default
        let model = ProcessInfo.processInfo.environment["TEST_MODEL"] ?? "gpt-4o"
        
        print("🖼️🖼️ Testing OpenAI multiple images with model: \(model)")
        
        // Initialize real OpenAI provider
        let provider = OpenAIProvider(apiKey: apiKey)
        
        // Use the same image URLs as in main.swift
        let imageURL1 = "https://www.wiggles.in/cdn/shop/articles/shutterstock_245621623.jpg?v=1706863987"
        let imageURL2 = "https://media1.popsugar-assets.com/files/thumbor/gFMaLiceRbGWkZUWwl2Xhkft6eU=/0x159:2003x2162/fit-in/2011x2514/filters:format_auto():quality(85):upscale()/2019/08/07/875/n/24155406/9ffb00255d4b2e079b0b23.01360060_.jpg"
        
        let request = ChatCompletionRequest(
            model: model,
            messages: [
                .user(content: .parts([
                    .text("Compare these two images. What are the similarities and differences?"),
                    .imageURL(.url(URL(string: imageURL1)!)),
                    .imageURL(.url(URL(string: imageURL2)!))
                ]))
            ]
        )
        
        // When
        let response = try await provider.sendChatCompletion(request: request)
        
        // Then
        XCTAssertFalse(response.choices.isEmpty)
        XCTAssertNotNil(response.choices.first?.message.content)
        
        let content = response.choices.first?.message.content ?? ""
        XCTAssertFalse(content.isEmpty)
        
        // Should mention comparison aspects
        let lowerContent = content.lowercased()
        XCTAssertTrue(
            lowerContent.contains("similar") || 
            lowerContent.contains("different") || 
            lowerContent.contains("both") ||
            lowerContent.contains("compare") ||
            lowerContent.contains("two"),
            "Response should contain comparison language"
        )
        
        print("✅ Multiple images analysis: \(content)")
        print("📊 Usage: \(response.usage?.totalTokens ?? 0) tokens")
        print("🏷️  Returned model: \(response.model)")
    }
    
    // MARK: - Helper Functions
    
    private func loadTestImage() -> Data? {
        // Load image from Tests/Assets/baltolo.webp
        let testBundle = Bundle(for: type(of: self))
        
        // Try to find the file in the test bundle
        if let path = testBundle.path(forResource: "baltolo", ofType: "webp"),
           let data = FileManager.default.contents(atPath: path) {
            return data
        }
        
        // Fallback: try relative path from test working directory
        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let imageURL = currentDirectoryURL.appendingPathComponent("Tests/Assets/baltolo.webp")
        
        return try? Data(contentsOf: imageURL)
    }
} 