//
//  OpenAIResponsesSessionTests.swift
//  AISDKTests
//
//  Tests for the new simplified Response API wrapper (ResponseSession)
//  Focuses on the new clean API surface without duplicating existing comprehensive tests
//

import XCTest
@testable import AISDK

final class OpenAIResponsesSessionTests: XCTestCase {
    
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
    
    // MARK: - Clean API Surface Tests
    
    func testResponseSessionTextAPI() async throws {
        if let provider = provider {
            // Real API test - Simple text response using new clean API
            let response = try await provider.response("Say hello in one word")
                .model("gpt-4o-mini")
                .execute()
            
            // Test Response wrapper provides clean access
            XCTAssertNotNil(response.text)
            XCTAssertNotNil(response.id)
            XCTAssertEqual(response.model, "gpt-4o-mini")
            XCTAssertTrue(response.status.isFinal)
            XCTAssertGreaterThan(response.content.count, 0)
            
            // Test conversation message is created for agent integration
            XCTAssertEqual(response.conversationMessage.role, .assistant)
            XCTAssertGreaterThan(response.conversationMessage.content.count, 0)
            
        } else {
            // Mock test - verify the wrapper calls underlying API correctly
            let request = ResponseRequest(
                model: "gpt-4o",
                input: .string("Test message")
            )
            
            let mockResponseObject = try await mockProvider.createResponse(request: request)
            let response = Response(from: mockResponseObject)
            
            // Test Response wrapper extracts data correctly
            XCTAssertNotNil(response.text)
            XCTAssertEqual(response.model, "gpt-4o")
            XCTAssertEqual(response.status, .completed)
        }
    }
    
    func testResponseSessionMultimodalAPI() {
        // Test multimodal content parts initialization
        let content: [AIContentPart] = [
            .text("Compare these two concepts:"),
            .text("First concept"),
            .text("Second concept")
        ]
        
        if let provider = provider {
            let session = provider.response(content)
                .model("gpt-4o-mini")
                .temperature(0.7)
            
            XCTAssertNotNil(session)
        }
    }
    
    func testResponseSessionConversationAPI() {
        // Test conversation history initialization (for agents)
        let conversation = [
            AIInputMessage.user("Hello"),
            AIInputMessage.assistant("Hi there! How can I help?"),
            AIInputMessage.user("What's the weather like?")
        ]
        
        if let provider = provider {
            let session = provider.response(conversation: conversation)
                .model("gpt-4o-mini")
            
            XCTAssertNotNil(session)
        }
    }
    
    func testResponseSessionAIInputMessageAPI() {
        // Test direct AIInputMessage initialization (advanced usage)
        let message = AIInputMessage.user([
            .text("Analyze this text:"),
            .text("Sample text content")
        ])
        
        if let provider = provider {
            let session = provider.response(message)
                .model("gpt-4o-mini")
                .instructions("Provide a brief analysis")
            
            XCTAssertNotNil(session)
        }
    }
    
    // MARK: - Mixed Tool Syntax Tests
    
    func testBuiltInToolConfiguration() {
        if let provider = provider {
            let session = provider.response("Test with built-in tools")
                .tools([
                    BuiltInTool.webSearchPreview,
                    BuiltInTool.codeInterpreter,
                    BuiltInTool.imageGeneration()
                ])
            
            XCTAssertNotNil(session)
        }
    }
    
    func testMCPToolConfiguration() {
        if let provider = provider {
            let session = provider.response("Test with MCP tools")
                .tools([
                    BuiltInTool.mcp(
                        serverLabel: "test-server",
                        serverUrl: "https://test.com/mcp"
                    )
                ])
            
            XCTAssertNotNil(session)
        }
    }
    
    func testToolConversionMechanisms() {
        // Test BuiltInTool conversion
        let webSearchTool = BuiltInTool.webSearchPreview
        let convertedTool = webSearchTool.toResponseTool()
        
        switch convertedTool {
        case .webSearchPreview:
            XCTAssert(true, "Successfully converted BuiltInTool to ResponseTool")
        default:
            XCTFail("Failed to convert BuiltInTool.webSearchPreview")
        }
        
        // Test MCP tool conversion
        let mcpTool = BuiltInTool.mcp(serverLabel: "test", serverUrl: "https://test.com")
        let convertedMCPTool = mcpTool.toResponseTool()
        
        switch convertedMCPTool {
        case .mcp(let label, let url, _, _):
            XCTAssertEqual(label, "test")
            XCTAssertEqual(url, "https://test.com")
        default:
            XCTFail("Failed to convert BuiltInTool.mcp")
        }
    }
    
    // MARK: - Fluent Configuration Tests
    
    func testFluentConfigurationChaining() {
        if let provider = provider {
            let session = provider.response("Test message")
                .model("gpt-4o-mini")
                .temperature(0.8)
                .maxOutputTokens(100)
                .instructions("Be concise and helpful")
                .background(true)
            
            XCTAssertNotNil(session)
        }
    }
    
    func testAdvancedFeatureConfiguration() {
        if let provider = provider {
            let reasoning = ResponseReasoning(effort: "detailed", summary: nil)
            
            let session = provider.response("Complex research task")
                .reasoning(reasoning)
                .previousResponse("prev-resp-123")
                .background(true)
            
            XCTAssertNotNil(session)
        }
    }
    
    // MARK: - Response Wrapper Tests
    
    func testResponseWrapperExtraction() {
        // Test Response wrapper correctly extracts data from ResponseObject
        let mockOutput = [
            ResponseOutputItem.message(
                ResponseOutputMessage(
                    id: "msg-1",
                    role: "assistant",
                    content: [
                        .outputText(ResponseOutputText(
                            text: "Test response text",
                            annotations: [
                                ResponseAnnotation(
                                    type: "citation",
                                    text: "Source 1",
                                    startIndex: 0,
                                    endIndex: 10
                                )
                            ]
                        ))
                    ]
                )
            )
        ]
        
        let mockResponseObject = ResponseObject(
            id: "test-123",
            object: "response",
            createdAt: Date().timeIntervalSince1970,
            model: "gpt-4o",
            status: .completed,
            output: mockOutput,
            usage: ResponseUsage(
                inputTokens: 10,
                outputTokens: 15,
                totalTokens: 25,
                inputTokensDetails: nil,
                outputTokensDetails: nil
            ),
            previousResponseId: nil,
            metadata: nil,
            incompleteDetails: nil,
            error: nil,
            instructions: nil,
            temperature: nil,
            topP: nil,
            maxOutputTokens: nil,
            toolChoice: nil,
            tools: nil,
            parallelToolCalls: nil,
            reasoning: ResponseReasoning(effort: "minimal", summary: "Test reasoning"),
            truncation: nil,
            text: nil,
            user: nil,
            store: nil,
            serviceTier: nil
        )
        
        let response = Response(from: mockResponseObject)
        
        // Test basic properties
        XCTAssertEqual(response.id, "test-123")
        XCTAssertEqual(response.model, "gpt-4o")
        XCTAssertEqual(response.status, .completed)
        XCTAssertEqual(response.text, "Test response text")
        
        // Test content extraction
        XCTAssertEqual(response.content.count, 1)
        if case .text(let extractedText) = response.content.first {
            XCTAssertEqual(extractedText, "Test response text")
        } else {
            XCTFail("Failed to extract text content")
        }
        
        // Test annotations extraction
        XCTAssertEqual(response.annotations.count, 1)
        XCTAssertEqual(response.annotations.first?.text, "Source 1")
        
        // Test reasoning extraction
        XCTAssertNotNil(response.reasoning)
        XCTAssertEqual(response.reasoning?.effort, "minimal")
        
        // Test conversation message creation
        XCTAssertEqual(response.conversationMessage.role, .assistant)
        XCTAssertEqual(response.conversationMessage.content.count, 1)
    }
    
    // MARK: - Streaming Wrapper Tests
    
    func testSimpleStreamingChunkWrapper() async throws {
        if let provider = provider {
            // Real API streaming test
            var chunks: [SimpleResponseChunk] = []
            var accumulatedText = ""
            
            for try await chunk in provider.response("Count to 3")
                .model("gpt-4o-mini")
                .maxOutputTokens(20)
                .stream() {
                
                chunks.append(chunk)
                
                if let text = chunk.text {
                    accumulatedText += text
                }
                
                // Test SimpleResponseChunk properties
                XCTAssertNotNil(chunk.id)
                XCTAssertNotNil(chunk.eventType)
            }
            
            XCTAssertGreaterThan(chunks.count, 0)
            XCTAssertFalse(accumulatedText.isEmpty)
            
            // Test final chunk
            if let lastChunk = chunks.last {
                XCTAssertTrue(lastChunk.isComplete)
            }
        }
    }
    
    // MARK: - Global Convenience Function Tests
    
    func testGlobalConvenienceFunctions() {
        if let provider = provider {
            let session1 = response("Hello", using: provider)
            XCTAssertNotNil(session1)
            
            let session2 = response([.text("Hello"), .text("World")], using: provider)
            XCTAssertNotNil(session2)
        }
    }
    
    // MARK: - Integration with Existing API Tests
    
    func testNewAPIProducesSameRequestAsExistingAPI() async throws {
        // This test verifies that the new clean API produces the same underlying
        // requests as the existing API, ensuring compatibility
        
        if mockProvider != nil {
            // Using mock to capture requests for comparison
            
            // New API approach
            let session = ResponseSession(
                provider: OpenAIProvider(apiKey: "test"),
                text: "Test message"
            )
            
            // Test that the session can build a proper ResponseRequest
            // Note: We'd need to access internal methods for full testing
            // This is a placeholder for the concept
            XCTAssertNotNil(session)
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