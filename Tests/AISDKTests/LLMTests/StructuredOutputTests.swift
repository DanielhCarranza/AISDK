//
//  StructuredOutputTests.swift
//  AISDKTests
//
//  Created by AI Assistant
//

import XCTest
@testable import AISDK

final class StructuredOutputTests: XCTestCase {
    
    var mockProvider: MockLLMProvider!
    
    override func setUp() {
        super.setUp()
        mockProvider = MockLLMProvider()
    }
    
    override func tearDown() {
        mockProvider = nil
        super.tearDown()
    }
    
    // MARK: - JSON Mode Tests
    
    func testBasicJSONMode() async throws {
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .system(content: .text("Return valid JSON only")),
                .user(content: .text("List 3 programming languages with their details"))
            ],
            responseFormat: .jsonObject
        )
        
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Verify response structure
        XCTAssertNotNil(response.choices.first?.message.content)
        XCTAssertEqual(mockProvider.requestCount, 1)
    }
    
    func testJSONModeErrorHandling() async throws {
        // Test invalid JSON response
        let invalidJSON = "This is not valid JSON: { invalid: json }"
        
        mockProvider.setMockResponse(ChatCompletionResponse(
            id: "test-invalid-json",
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
                        content: invalidJSON,
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 30,
                completionTokens: 15,
                totalTokens: 45,
                completionTokensDetails: nil
            )
        ))
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .text("Return invalid JSON"))
            ],
            responseFormat: .jsonObject
        )
        
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Even if the model returns invalid JSON, our provider should handle it gracefully
        XCTAssertNotNil(response.choices.first?.message.content)
        
        // Try to parse - should fail gracefully
        if let content = response.choices.first?.message.content,
           let jsonData = content.data(using: .utf8) {
            XCTAssertThrowsError(try JSONSerialization.jsonObject(with: jsonData, options: []))
        }
    }
    
    // MARK: - Structured Output Tests
    
    func testStructuredOutputWithSimpleModel() async throws {
        // Define test model
        struct Product: Codable {
            let name: String
            let price: Double
            let category: String
            let inStock: Bool
        }
        
        let productJSON = """
        {
            "name": "MacBook Pro",
            "price": 1999.99,
            "category": "Electronics",
            "inStock": true
        }
        """
        
        mockProvider.setMockResponse(ChatCompletionResponse(
            id: "test-product",
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
                        content: productJSON,
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 40,
                completionTokens: 25,
                totalTokens: 65,
                completionTokensDetails: nil
            )
        ))
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .text("Generate a product with name, price, category, and stock status"))
            ],
            responseFormat: .jsonObject
        )
        
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Parse into structured model
        guard let content = response.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            XCTFail("No content received")
            return
        }
        
        let product = try JSONDecoder().decode(Product.self, from: jsonData)
        
        // Verify structured data
        XCTAssertEqual(product.name, "MacBook Pro")
        XCTAssertEqual(product.price, 1999.99)
        XCTAssertEqual(product.category, "Electronics")
        XCTAssertTrue(product.inStock)
    }
    
    func testGenerateObjectMethod() async throws {
        // Define test model
        struct Book: Codable {
            let title: String
            let author: String
            let year: Int
        }
        
        let bookJSON = """
        {
            "title": "1984",
            "author": "George Orwell",
            "year": 1949
        }
        """
        
        mockProvider.setMockResponse(ChatCompletionResponse(
            id: "test-book",
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
                        content: bookJSON,
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 30,
                completionTokens: 20,
                totalTokens: 50,
                completionTokensDetails: nil
            )
        ))
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .text("Recommend a classic book"))
            ],
            responseFormat: .jsonObject
        )
        
        // Test generateObject method
        let book: Book = try await mockProvider.generateObject(request: request)
        
        // Verify structured data
        XCTAssertEqual(book.title, "1984")
        XCTAssertEqual(book.author, "George Orwell")
        XCTAssertEqual(book.year, 1949)
    }
    
    func testGenerateObjectWithComplexModel() async throws {
        // Define complex test model
        struct User: Codable {
            let id: Int
            let name: String
            let email: String
            let preferences: Preferences
            let tags: [String]
        }
        
        struct Preferences: Codable {
            let theme: String
            let notifications: Bool
            let language: String
        }
        
        let userJSON = """
        {
            "id": 123,
            "name": "John Doe",
            "email": "john@example.com",
            "preferences": {
                "theme": "dark",
                "notifications": true,
                "language": "en"
            },
            "tags": ["developer", "swift", "ai"]
        }
        """
        
        mockProvider.setMockResponse(ChatCompletionResponse(
            id: "test-complex-user",
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
                        content: userJSON,
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 40,
                completionTokens: 60,
                totalTokens: 100,
                completionTokensDetails: nil
            )
        ))
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .text("Generate a user profile"))
            ],
            responseFormat: .jsonObject
        )
        
        // Test generateObject with complex model
        let user: User = try await mockProvider.generateObject(request: request)
        
        // Verify complex structured data
        XCTAssertEqual(user.id, 123)
        XCTAssertEqual(user.name, "John Doe")
        XCTAssertEqual(user.email, "john@example.com")
        XCTAssertEqual(user.preferences.theme, "dark")
        XCTAssertTrue(user.preferences.notifications)
        XCTAssertEqual(user.preferences.language, "en")
        XCTAssertEqual(user.tags.count, 3)
        XCTAssertTrue(user.tags.contains("developer"))
    }
    
    func testGenerateObjectWithInvalidJSON() async throws {
        struct Product: Codable {
            let name: String
            let price: Double
        }
        
        // Set up invalid JSON response
        let invalidJSON = "{ invalid json structure"
        
        mockProvider.setMockResponse(ChatCompletionResponse(
            id: "test-invalid",
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
                        content: invalidJSON,
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 20,
                completionTokens: 10,
                totalTokens: 30,
                completionTokensDetails: nil
            )
        ))
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .text("Generate a product"))
            ],
            responseFormat: .jsonObject
        )
        
        // Should throw parsing error
        do {
            let _: Product = try await mockProvider.generateObject(request: request)
            XCTFail("Expected generateObject to throw error for invalid JSON")
        } catch let error as AISDKError {
            if case .parsingError(let message) = error {
                XCTAssertTrue(message.contains("Failed to decode object"))
            } else {
                XCTFail("Expected parsingError, got \(error)")
            }
        }
    }
    
    func testGenerateObjectWithMismatchedSchema() async throws {
        struct Book: Codable {
            let title: String
            let author: String
            let year: Int
        }
        
        // JSON that doesn't match Book schema (missing required fields)
        let mismatchedJSON = """
        {
            "title": "Some Book",
            "price": 29.99
        }
        """
        
        mockProvider.setMockResponse(ChatCompletionResponse(
            id: "test-mismatched",
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
                        content: mismatchedJSON,
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 20,
                completionTokens: 15,
                totalTokens: 35,
                completionTokensDetails: nil
            )
        ))
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .text("Generate a book"))
            ],
            responseFormat: .jsonObject
        )
        
        // Should throw parsing error due to schema mismatch
        do {
            let _: Book = try await mockProvider.generateObject(request: request)
            XCTFail("Expected generateObject to throw error for schema mismatch")
        } catch let error as AISDKError {
            if case .parsingError(let message) = error {
                XCTAssertTrue(message.contains("Failed to decode object"))
            } else {
                XCTFail("Expected parsingError, got \(error)")
            }
        }
    }
    
    func testGenerateObjectWithEmptyResponse() async throws {
        struct Item: Codable {
            let name: String
        }
        
        // Set up response with no content
        mockProvider.setMockResponse(ChatCompletionResponse(
            id: "test-empty",
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
                        content: nil,
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 10,
                completionTokens: 0,
                totalTokens: 10,
                completionTokensDetails: nil
            )
        ))
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .text("Generate an item"))
            ],
            responseFormat: .jsonObject
        )
        
        // Should throw parsing error for empty content
        do {
            let _: Item = try await mockProvider.generateObject(request: request)
            XCTFail("Expected generateObject to throw error for empty content")
        } catch let error as AISDKError {
            if case .parsingError(let message) = error {
                XCTAssertEqual(message, "No content in response")
            } else {
                XCTFail("Expected parsingError with 'No content in response', got \(error)")
            }
        }
    }
    
    func testGenerateObjectPerformance() async throws {
        struct SimpleModel: Codable {
            let value: String
        }
        
        let simpleJSON = """
        {
            "value": "test"
        }
        """
        
        mockProvider.setMockResponse(ChatCompletionResponse(
            id: "test-performance",
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
                        content: simpleJSON,
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 10,
                completionTokens: 5,
                totalTokens: 15,
                completionTokensDetails: nil
            )
        ))
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .text("Generate simple object"))
            ],
            responseFormat: .jsonObject
        )
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let _: SimpleModel = try await mockProvider.generateObject(request: request)
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(timeElapsed, 0.5, "generateObject should complete quickly")
    }
    
    // MARK: - Performance Tests
    
    func testJSONModePerformance() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .text("Generate simple JSON"))
            ],
            responseFormat: .jsonObject
        )
        
        _ = try await mockProvider.sendChatCompletion(request: request)
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThan(timeElapsed, 0.5, "JSON mode should be fast with mock provider")
    }
    
    // MARK: - Edge Cases
    
    func testEmptyJSONResponse() async throws {
        mockProvider.setMockResponse(ChatCompletionResponse(
            id: "test-empty",
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
                        content: "{}",
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 20,
                completionTokens: 2,
                totalTokens: 22,
                completionTokensDetails: nil
            )
        ))
        
        let request = ChatCompletionRequest(
            model: "gpt-4o",
            messages: [
                .user(content: .text("Return empty JSON"))
            ],
            responseFormat: .jsonObject
        )
        
        let response = try await mockProvider.sendChatCompletion(request: request)
        
        // Should handle empty JSON gracefully
        XCTAssertEqual(response.choices.first?.message.content, "{}")
    }
} 