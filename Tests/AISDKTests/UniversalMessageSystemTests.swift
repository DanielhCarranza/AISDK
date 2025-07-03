//
//  UniversalMessageSystemTests.swift
//  AISDKTests
//
//  Tests for Universal Message System
//

import XCTest
@testable import AISDK

final class UniversalMessageSystemTests: XCTestCase {
    
    // MARK: - Core Message Creation Tests
    
    func testCreateSimpleMessage() {
        let message = AIInputMessage.user("Hello, world!")
        
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.textContent, "Hello, world!")
    }
    
    func testCreateImageMessage() {
        let url = URL(string: "https://example.com/image.jpg")!
        let message = AIInputMessage.user([
            .text("Look at this:"),
            .imageURL(url)
        ])
        
        XCTAssertEqual(message.content.count, 2)
        XCTAssertTrue(message.hasImages)
    }
    
    func testCreateMultimodalMessage() {
        let imageData = Data("fake image data".utf8)
        let message = AIInputMessage.user([
            .text("Look at this image:"),
            .image(imageData, detail: .high),
            .text("What do you see?")
        ])
        
        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content.count, 3)
        XCTAssertTrue(message.hasImages)
        XCTAssertEqual(message.images.count, 1)
        XCTAssertEqual(message.images.first?.detail, .high)
        XCTAssertEqual(message.textContent, "Look at this image:\nWhat do you see?")
    }
    
    func testCreateAssistantMessageWithToolCalls() {
        let toolCall = AIToolCall(id: "call_123", name: "get_weather", arguments: ["city": "Paris"])
        let message = AIInputMessage.assistant("I'll check the weather for you.", toolCalls: [toolCall])
        
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.toolCalls?.count, 1)
        XCTAssertEqual(message.toolCalls?.first?.name, "get_weather")
    }
    
    func testCreateSystemMessage() {
        let message = AIInputMessage.system("You are a helpful assistant.")
        
        XCTAssertEqual(message.role, .system)
        XCTAssertEqual(message.textContent, "You are a helpful assistant.")
    }
    
    func testCreateToolResponseMessage() {
        let message = AIInputMessage.tool("Temperature: 22°C", callId: "call_123", name: "get_weather")
        
        XCTAssertEqual(message.role, .tool)
        XCTAssertEqual(message.toolCallId, "call_123")
        XCTAssertEqual(message.name, "get_weather")
        XCTAssertEqual(message.textContent, "Temperature: 22°C")
    }
    
    // MARK: - Content Type Tests
    
    func testImageContentWithURL() {
        let url = URL(string: "https://example.com/image.jpg")!
        let contentPart = AIContentPart.imageURL(url, detail: .low)
        
        if case .image(let imageContent) = contentPart {
            XCTAssertEqual(imageContent.url, url)
            XCTAssertEqual(imageContent.detail, .low)
            XCTAssertNil(imageContent.data)
        } else {
            XCTFail("Expected image content")
        }
    }
    
    func testAudioContentWithTranscript() {
        let audioData = Data("fake audio data".utf8)
        let contentPart = AIContentPart.audio(audioData, format: .mp3, transcript: "Hello world")
        
        if case .audio(let audioContent) = contentPart {
            XCTAssertEqual(audioContent.data, audioData)
            XCTAssertEqual(audioContent.format, .mp3)
            XCTAssertEqual(audioContent.transcript, "Hello world")
        } else {
            XCTFail("Expected audio content")
        }
    }
    
    func testFileContent() {
        let fileData = Data("PDF content".utf8)
        let contentPart = AIContentPart.file(fileData, filename: "document.pdf", type: .pdf)
        
        if case .file(let fileContent) = contentPart {
            XCTAssertEqual(fileContent.data, fileData)
            XCTAssertEqual(fileContent.filename, "document.pdf")
            XCTAssertEqual(fileContent.type, .pdf)
            XCTAssertEqual(fileContent.mimeType, "application/pdf")
        } else {
            XCTFail("Expected file content")
        }
    }
    
    func testJSONContent() throws {
        struct TestObject: Codable {
            let name: String
            let age: Int
        }
        
        let testObject = TestObject(name: "John", age: 30)
        let contentPart = try AIContentPart.jsonObject(testObject)
        
        if case .json(let data) = contentPart {
            let decoded = try JSONDecoder().decode(TestObject.self, from: data)
            XCTAssertEqual(decoded.name, "John")
            XCTAssertEqual(decoded.age, 30)
        } else {
            XCTFail("Expected JSON content")
        }
    }
    
    // MARK: - Response API Conversion Tests
    
    func testConvertToResponseMessage() {
        let message = AIInputMessage.user([
            .text("Hello"),
            .html("<p>HTML content</p>"),
            .markdown("**Bold text**")
        ])
        
        let responseMessage = message.toResponseMessage()
        
        XCTAssertEqual(responseMessage.role, "user")
        XCTAssertEqual(responseMessage.content.count, 3)
        
        // All should be converted to text in Response API
        for contentItem in responseMessage.content {
            if case .inputText = contentItem {
                // Expected
            } else {
                XCTFail("All content should be converted to inputText in Response API")
            }
        }
    }
    
    func testConvertImageURLToResponseMessage() {
        let url = URL(string: "https://example.com/image.jpg")!
        let message = AIInputMessage.user([
            .text("Look at this:"),
            .imageURL(url)
        ])
        
        let responseMessage = message.toResponseMessage()
        
        XCTAssertEqual(responseMessage.content.count, 2)
        
        // First should be text, second should be image
        if case .inputText(let textContent) = responseMessage.content[0] {
            XCTAssertEqual(textContent.text, "Look at this:")
        } else {
            XCTFail("First content should be text")
        }
        
        if case .inputImage(let imageContent) = responseMessage.content[1] {
            XCTAssertEqual(imageContent.imageUrl, url.absoluteString)
        } else {
            XCTFail("Second content should be image")
        }
    }
    
    func testConvertToResponseInput() {
        // Test simple text conversion
        let simpleMessage = AIInputMessage.user("Hello")
        let simpleInput = simpleMessage.toResponseInput()
        
        if case .string(let text) = simpleInput {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Simple text should convert to string ResponseInput")
        }
        
        // Test complex message conversion
        let complexMessage = AIInputMessage.user([
            .text("Hello"),
            .markdown("**Bold**")
        ])
        let complexInput = complexMessage.toResponseInput()
        
        if case .items(let items) = complexInput {
            XCTAssertEqual(items.count, 1)
        } else {
            XCTFail("Complex message should convert to items ResponseInput")
        }
    }
    
    // MARK: - Chat Completions Conversion Tests
    
    func testConvertToChatCompletionMessage() {
        let message = AIInputMessage.user("Hello, AI!")
        let chatMessage = message.toChatCompletionMessage()
        
        if case .user(let content, let name) = chatMessage {
            if case .text(let text) = content {
                XCTAssertEqual(text, "Hello, AI!")
                XCTAssertNil(name)
            } else {
                XCTFail("Expected text content")
            }
        } else {
            XCTFail("Expected user message")
        }
    }
    
    func testConvertMultimodalToChatCompletion() {
        let imageData = Data("image".utf8)
        let message = AIInputMessage.user([
            .text("What's in this image?"),
            .image(imageData, detail: .high)
        ])
        
        let chatMessage = message.toChatCompletionMessage()
        
        if case .user(let content, _) = chatMessage {
            if case .parts(let parts) = content {
                XCTAssertEqual(parts.count, 2)
                
                if case .text(let text) = parts[0] {
                    XCTAssertEqual(text, "What's in this image?")
                } else {
                    XCTFail("First part should be text")
                }
                
                if case .imageURL(let imageSource, let detail) = parts[1] {
                    if case .base64(let data) = imageSource {
                        XCTAssertEqual(data, imageData)
                    } else {
                        XCTFail("Expected base64 image source")
                    }
                    XCTAssertEqual(detail, .high)
                } else {
                    XCTFail("Second part should be image")
                }
            } else {
                XCTFail("Expected parts content")
            }
        } else {
            XCTFail("Expected user message")
        }
    }
    
    // MARK: - Conversation Array Tests
    
    func testConversationConversions() {
        let conversation = [
            AIInputMessage.system("You are helpful."),
            AIInputMessage.user("Hello!"),
            AIInputMessage.assistant("Hi there!")
        ]
        
        // Test Response API conversion
        let responseItems = conversation.toResponseInputItems()
        XCTAssertEqual(responseItems.count, 3)
        
        // Test Chat Completions conversion
        let chatMessages = conversation.toChatCompletionMessages()
        XCTAssertEqual(chatMessages.count, 3)
        
        // Verify types
        if case .system = chatMessages[0] { /* Expected */ } else { XCTFail("Expected system message") }
        if case .user = chatMessages[1] { /* Expected */ } else { XCTFail("Expected user message") }
        if case .assistant = chatMessages[2] { /* Expected */ } else { XCTFail("Expected assistant message") }
    }
    
    // MARK: - Codable Tests
    
    func testMessageCodable() throws {
        let originalMessage = AIInputMessage.user([
            .text("Hello"),
            .imageURL(URL(string: "https://example.com/image.jpg")!)
        ])
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalMessage)
        
        let decoder = JSONDecoder()
        let decodedMessage = try decoder.decode(AIInputMessage.self, from: data)
        
        XCTAssertEqual(decodedMessage.role, originalMessage.role)
        XCTAssertEqual(decodedMessage.content.count, originalMessage.content.count)
        XCTAssertEqual(decodedMessage.textContent, originalMessage.textContent)
    }
}

// MARK: - Helper Extensions for Testing

extension AIInputMessage {
    /// Test helper to check equality
    func isEqual(to other: AIInputMessage) -> Bool {
        return role == other.role &&
               content.count == other.content.count &&
               textContent == other.textContent &&
               name == other.name
    }
} 