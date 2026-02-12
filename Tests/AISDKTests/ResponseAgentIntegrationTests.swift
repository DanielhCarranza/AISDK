//
//  ResponseAgentIntegrationTests.swift
//  AISDKTests
//
//  Created by AISDK on 01/01/25.
//

import XCTest
@testable import AISDK

final class ResponseAgentIntegrationTests: XCTestCase {
    
    var provider: OpenAIProvider!
    var agent: ResponseAgent!
    
    override func setUpWithError() throws {
        provider = OpenAIProvider(apiKey: "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")
        agent = try ResponseAgent(
            provider: provider,
            tools: [],
            builtInTools: [.webSearchPreview],
            instructions: "You are a helpful assistant for testing.",
            model: "gpt-4o"
        )
    }
    
    override func tearDownWithError() throws {
        provider = nil
        agent = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationWithValidProvider() throws {
        // Test successful initialization
        let testAgent = try ResponseAgent(
            provider: provider,
            instructions: "Test instructions"
        )
        
        XCTAssertEqual(testAgent.state, .idle)
        XCTAssertEqual(testAgent.conversationId.isEmpty, false)
        XCTAssertEqual(testAgent.messages.count, 1) // System message
        XCTAssertEqual(testAgent.messages.first?.role, .system)
    }
    
    func testInitializationWithInvalidProvider() {
        // Test initialization with invalid provider - no API key
        let invalidProvider = OpenAIProvider(apiKey: "")
        
        XCTAssertThrowsError(try ResponseAgent(provider: invalidProvider)) { error in
            XCTAssertTrue(error is ResponseAgentError)
            if case .invalidProvider = error as? ResponseAgentError {
                // Expected error
            } else {
                XCTFail("Expected invalidProvider error, got \(error)")
            }
        }
    }
    
    func testToolConflictValidation() {
        // Create a mock tool that conflicts with built-in tools
        final class MockWebSearchTool: Tool {
            var name: String = "web_search_preview"
            var description: String = "Mock tool"
            var returnToolResponse: Bool = false
            
            required init() {}
            
            static func jsonSchema() -> ToolSchema {
                return ToolSchema(
                    type: "function",
                    function: ToolFunction(
                        name: "web_search_preview",
                        description: "Mock tool",
                        parameters: Parameters(
                            type: "object",
                            properties: [:],
                            required: []
                        )
                    )
                )
            }
            
            func setParameters(from arguments: [String: Any]) throws {
                // No parameters to set
            }
            
            func validateAndSetParameters(_ argumentsData: Data) throws -> Self {
                return self
            }
            
            func execute() async throws -> ToolResult {
                return ToolResult(content: "Mock result")
            }
        }
        
        // Test tool conflict detection
        XCTAssertThrowsError(try ResponseAgent(
            provider: provider,
            tools: [MockWebSearchTool.self],
            builtInTools: [.webSearchPreview]
        )) { error in
            XCTAssertTrue(error is ResponseAgentError)
            if case .toolConflict = error as? ResponseAgentError {
                // Expected error
            } else {
                XCTFail("Expected toolConflict error")
            }
        }
    }
    
    // MARK: - Send Method Tests
    
    func testSendTextMessage() async throws {
        // Test sending simple text message
        let message = "Hello, test message"
        
        var responses: [ResponseLegacyChatMessage] = []
        
        for try await response in agent.send(message, streaming: false) {
            responses.append(response)
        }
        
        // Verify basic response structure
        XCTAssertFalse(responses.isEmpty)
        XCTAssertEqual(agent.messages.count, 3) // System + User + Assistant
        XCTAssertEqual(agent.state, .idle)
    }
    
    func testSendMultimodalMessage() async throws {
        // Test sending multimodal message with mock provider
        let mockProvider = MockOpenAIProvider()
        let testAgent = try ResponseAgent(
            provider: mockProvider,
            instructions: "Test agent"
        )
        let contentParts: [AIContentPart] = [
            .text("Describe this image"),
            .image(AIImageContent(data: Data())) // Mock image data
        ]
        
        var responses: [ResponseLegacyChatMessage] = []
        
        for try await response in testAgent.send(contentParts, streaming: false) {
            responses.append(response)
        }
        
        // Verify multimodal message handling
        XCTAssertFalse(responses.isEmpty)
        XCTAssertEqual(testAgent.messages.count, 3) // System + User + Assistant
    }
    
    func testStreamingResponse() async throws {
        // Test streaming response
        let message = "Tell me a short story"
        
        var responses: [ResponseLegacyChatMessage] = []
        var pendingCount = 0
        
        for try await response in agent.send(message, streaming: true) {
            responses.append(response)
            if response.isPending {
                pendingCount += 1
            }
        }
        
        // Verify streaming behavior
        XCTAssertFalse(responses.isEmpty)
        XCTAssertTrue(pendingCount > 0) // Should have pending messages during streaming
        XCTAssertEqual(agent.state, .idle)
    }
    
    // MARK: - Background Processing Tests
    
    func testBackgroundTask() async throws {
        // Test background task execution with mock provider
        let mockProvider = MockOpenAIProvider()
        let testAgent = try ResponseAgent(
            provider: mockProvider,
            instructions: "Test agent"
        )
        let message = "Perform a complex analysis"
        
        let result = try await testAgent.task(
            message,
            configuration: .default
        )
        
        // Verify background task completion
        XCTAssertNotNil(result.response)
        XCTAssertEqual(testAgent.state, .idle)
        XCTAssertTrue(testAgent.messages.count >= 2) // At least user message added
        XCTAssertEqual(result.status, .completed)
        XCTAssertTrue(result.duration >= 0)
    }
    
    // MARK: - State Management Tests
    
    func testStateChanges() async throws {
        // Test state change notifications
        var stateChanges: [ResponseAgentState] = []
        
        agent.onStateChange = { state in
            stateChanges.append(state)
        }
        
        // Trigger state changes
        let message = "Test message"
        
        for try await _ in agent.send(message, streaming: false) {
            // Process responses
        }
        
        // Verify state changes occurred
        XCTAssertFalse(stateChanges.isEmpty)
        XCTAssertTrue(stateChanges.contains { $0.isProcessing })
    }
    
    func testConcurrentRequestPrevention() async throws {
        // Test that agent prevents concurrent requests using mock provider with delay
        let mockProvider = MockOpenAIProvider(simulatedDelay: 0.5) // 500ms delay
        let testAgent = try ResponseAgent(
            provider: mockProvider,
            instructions: "Test agent"
        )
        let message = "Test message"
        
        // Start first request
        let firstRequest = Task {
            var responses: [ResponseLegacyChatMessage] = []
            for try await response in testAgent.send(message, streaming: false) {
                responses.append(response)
            }
            return responses
        }
        
        // Add small delay to ensure first request starts
        try await Task.sleep(nanoseconds: 50_000_000)
        
        // Try to start second request while first is running
        let secondRequest = Task {
            var responses: [ResponseLegacyChatMessage] = []
            for try await response in testAgent.send(message, streaming: false) {
                responses.append(response)
            }
            return responses
        }
        
        // Second request should fail with agentBusy error
        do {
            let _ = try await secondRequest.value
            XCTFail("Expected agentBusy error")
        } catch {
            XCTAssertTrue(error is ResponseAgentError)
            if case .agentBusy = error as? ResponseAgentError {
                // Expected error
            } else {
                XCTFail("Expected agentBusy error, got \(error)")
            }
        }
        
        // First request should complete successfully
        let firstResults = try await firstRequest.value
        XCTAssertFalse(firstResults.isEmpty)
    }
    
    // MARK: - Conversation Management Tests
    
    func testConversationHistory() async throws {
        // Test conversation history management with mock provider
        let mockProvider = MockOpenAIProvider()
        let testAgent = try ResponseAgent(
            provider: mockProvider,
            instructions: "Test agent"
        )
        let firstMessage = "Hello"
        let secondMessage = "How are you?"
        
        // Send first message
        for try await _ in testAgent.send(firstMessage, streaming: false) {
            // Process responses
        }
        
        let messagesAfterFirst = testAgent.messages.count
        
        // Send second message
        for try await _ in testAgent.send(secondMessage, streaming: false) {
            // Process responses
        }
        
        let messagesAfterSecond = testAgent.messages.count
        
        // Verify conversation history
        XCTAssertTrue(messagesAfterSecond > messagesAfterFirst)
        XCTAssertTrue(testAgent.messages.contains { message in
            message.content.contains { part in
                if case .text(let text) = part {
                    return text.contains(firstMessage)
                }
                return false
            }
        })
        XCTAssertTrue(testAgent.messages.contains { message in
            message.content.contains { part in
                if case .text(let text) = part {
                    return text.contains(secondMessage)
                }
                return false
            }
        })
    }
    
    func testConversationReset() async throws {
        // Test conversation reset
        let message = "Test message"
        
        // Send message to populate conversation
        for try await _ in agent.send(message, streaming: false) {
            // Process responses
        }
        
        let messagesBeforeReset = agent.messages.count
        let conversationIdBeforeReset = agent.conversationId
        
        // Reset conversation
        agent.resetConversation()
        
        // Verify reset
        XCTAssertTrue(agent.messages.count < messagesBeforeReset)
        XCTAssertNotEqual(agent.conversationId, conversationIdBeforeReset)
        XCTAssertEqual(agent.state, .idle)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() async throws {
        // Test error handling with invalid input
        let invalidMessage = AIInputMessage.user("") // Empty message
        
        do {
            for try await _ in agent.send(invalidMessage, streaming: false) {
                // Process responses
            }
        } catch {
            // Should handle error gracefully
            XCTAssertTrue(error is ResponseAgentError)
            
            // LegacyAgent should return to idle state after error
            XCTAssertEqual(agent.state, .idle)
        }
    }
    
    // MARK: - Built-in Tools Tests
    
    func testBuiltInToolsConfiguration() {
        // Test built-in tools configuration
        let builtInTools: [ResponseBuiltInTool] = [
            .webSearchPreview,
            .codeInterpreter,
            .imageGeneration(partialImages: 3),
            .fileSearch(vectorStoreId: "test-vector-store")
        ]
        
        let agentWithTools = try! ResponseAgent(
            provider: provider,
            builtInTools: builtInTools
        )
        
        // Verify agent was created successfully with all tools
        XCTAssertEqual(agentWithTools.state, .idle)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceBasicSend() throws {
        // Test basic send performance with mock provider
        let mockProvider = MockOpenAIProvider()
        let mockAgent = try ResponseAgent(
            provider: mockProvider,
            instructions: "Test agent"
        )
        let message = "Hello"
        
        measure {
            let expectation = XCTestExpectation(description: "Send message")
            
            Task {
                for try await _ in mockAgent.send(message, streaming: false) {
                    // Process responses
                }
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
    
    // MARK: - Mock Response Tests
    
    func testMockResponseHandling() async throws {
        // Test with mock provider for predictable responses
        let mockProvider = MockOpenAIProvider()
        let mockAgent = try ResponseAgent(
            provider: mockProvider,
            instructions: "Test agent"
        )
        
        // Send message with mock provider
        let message = "Test message"
        
        var responses: [ResponseLegacyChatMessage] = []
        
        for try await response in mockAgent.send(message, streaming: false) {
            responses.append(response)
        }
        
        // Verify mock response handling
        XCTAssertFalse(responses.isEmpty)
        XCTAssertEqual(mockAgent.state, .idle)
    }
    
    // MARK: - MCP Integration Tests
    
    func testMCPServerConfiguration() throws {
        // Test ResponseAgent initialization with MCP servers
        let mcpServer = MCPServerConfiguration(
            serverLabel: "test_server",
            serverUrl: "https://example.com/mcp",
            requireApproval: .never
        )

        let mcpAgent = try ResponseAgent(
            provider: provider,
            tools: [],
            builtInTools: [.webSearchPreview],
            mcpServers: [mcpServer],
            instructions: "Test agent with MCP"
        )

        // Verify agent was created successfully with MCP configuration
        XCTAssertNotNil(mcpAgent)
    }
    
    func testEnhancedStateManagement() async throws {
        // Test enhanced state management with detailed states
        let mockProvider = MockOpenAIProvider()
        let testAgent = try ResponseAgent(
            provider: mockProvider,
            instructions: "Test agent"
        )
        
        var stateChanges: [ResponseAgentState] = []
        
        testAgent.onStateChange = { state in
            stateChanges.append(state)
        }
        
        // Send message to trigger state changes
        let message = "Test enhanced states"
        
        for try await _ in testAgent.send(message, streaming: false) {
            // Process responses
        }
        
        // Verify enhanced state tracking
        XCTAssertFalse(stateChanges.isEmpty)
        XCTAssertTrue(stateChanges.contains { state in
            if case .initializing = state { return true }
            return false
        })
        XCTAssertTrue(stateChanges.contains { state in
            if case .processing = state { return true }
            return false
        })
        XCTAssertTrue(stateChanges.contains { state in
            if case .completing = state { return true }
            return false
        })
    }
    
    func testBackgroundTaskConfiguration() async throws {
        // Test enhanced background task configuration
        let mockProvider = MockOpenAIProvider()
        let testAgent = try ResponseAgent(
            provider: mockProvider,
            instructions: "Test agent"
        )
        
        let cancellationToken = CancellationToken()
        var progressUpdates: [TaskProgress] = []
        var statusUpdates: [ResponseAgentState.BackgroundTaskStatus] = []
        
        let configuration = BackgroundTaskConfiguration(
            maxWaitTime: 60,
            pollInterval: 2,
            enableReasoning: true,
            enableProgressTracking: true,
            cancellationToken: cancellationToken,
            onProgress: { progress in
                progressUpdates.append(progress)
            },
            onStatusChange: { status in
                statusUpdates.append(status)
            }
        )
        
        let message = "Complex background task"
        
        let result = try await testAgent.task(
            message,
            configuration: configuration
        )
        
        // Verify enhanced background task features
        XCTAssertNotNil(result.response)
        XCTAssertEqual(result.status, .completed)
        XCTAssertTrue(result.duration >= 0)
        XCTAssertFalse(statusUpdates.isEmpty)
        XCTAssertTrue(statusUpdates.contains { status in
            if case .queued = status { return true }
            return false
        })
    }
}

// MARK: - Mock Provider for Testing

class MockOpenAIProvider: OpenAIProvider {
    
    var simulatedDelay: TimeInterval = 0
    
    init(simulatedDelay: TimeInterval = 0) {
        self.simulatedDelay = simulatedDelay
        super.init(apiKey: "mock-key")
    }
    
    override func createResponse(request: ResponseRequest) async throws -> ResponseObject {
        // Simulate delay if configured
        if simulatedDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))
        }
        
        // Return mock response
        return ResponseObject(
            id: "mock-response-id",
            object: "response",
            createdAt: Date().timeIntervalSince1970,
            model: "gpt-4o",
            status: .completed,
            output: [
                .message(ResponseOutputMessage(
                    id: "mock-message-id",
                    role: "assistant",
                    content: [
                        .outputText(ResponseOutputText(
                            text: "Mock response to input",
                            annotations: nil
                        ))
                    ]
                ))
            ],
            usage: nil,
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
            reasoning: nil,
            truncation: nil,
            text: nil,
            user: nil,
            store: nil,
            serviceTier: nil
        )
    }
    
    override func createResponseStream(request: ResponseRequest) -> AsyncThrowingStream<ResponseChunk, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                // Send mock streaming chunks
                let chunks = [
                    ResponseChunk(
                        id: "mock-chunk-1",
                        object: "response.chunk",
                        createdAt: Date().timeIntervalSince1970,
                        model: "gpt-4o",
                        status: nil,
                        delta: ResponseDelta(
                            output: nil,
                            outputText: "Mock ",
                            reasoning: nil,
                            text: "Mock "
                        ),
                        usage: nil,
                        error: nil
                    ),
                    ResponseChunk(
                        id: "mock-chunk-2",
                        object: "response.chunk",
                        createdAt: Date().timeIntervalSince1970,
                        model: "gpt-4o",
                        status: .completed,
                        delta: ResponseDelta(
                            output: nil,
                            outputText: "streaming response",
                            reasoning: nil,
                            text: "streaming response"
                        ),
                        usage: nil,
                        error: nil
                    )
                ]
                
                for chunk in chunks {
                    continuation.yield(chunk)
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
                
                continuation.finish()
            }
        }
    }
}
