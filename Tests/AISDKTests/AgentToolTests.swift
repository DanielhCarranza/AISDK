import XCTest
@testable import AISDK

// MARK: - Agent Tool Integration Tests

// Currently disabled due to Agent API changes
/*
final class AgentToolTests: XCTestCase {
    
    var mockProvider: MockLLMProvider!
    
    override func setUp() {
        super.setUp()
        mockProvider = MockLLMProvider()
        
        // Register test tools
        ToolRegistry.registerAll(tools: [
            TestWeatherTool.self,
            TestCalculatorTool.self,
            TestTimeTool.self,
            TestChainedTool.self
        ])
    }
    
    // MARK: - Single Tool Call Tests
    
    func testAgentSingleToolCall() async throws {
        // Setup mock provider to return tool call
        mockProvider.setupMockToolCallResponse(
            toolName: "get_weather",
            arguments: "{\"city\": \"San Francisco\", \"unit\": \"celsius\"}"
        )
        
        // Then setup final response after tool execution
        mockProvider.setupMockResponse("Based on the weather data, it's 22°C and sunny in San Francisco today.")
        
        let agent = try Agent(
            model: AgenticModels.gpt4,
            tools: [TestWeatherTool.self],
            instructions: "You are a helpful weather assistant.",
            llmProvider: mockProvider
        )
        
        let response = try await agent.sendMessage("What's the weather in San Francisco?")
        
        XCTAssertEqual(agent.messages.count, 4) // User + Assistant (tool call) + Tool response + Final response
        XCTAssertEqual(response.message.role, .assistant)
        XCTAssertTrue(response.content.contains("22°C"))
    }
    
    func testAgentMultipleToolCalls() async throws {
        // Setup mock for weather tool
        mockProvider.setupMockToolCallResponse(
            toolName: "get_weather",
            arguments: "{\"city\": \"Boston\", \"unit\": \"fahrenheit\"}"
        )
        
        // Setup mock for calculator tool
        mockProvider.setupMockToolCallResponse(
            toolName: "calculate",
            arguments: "{\"a\": 72, \"b\": 32, \"operation\": \"-\"}"
        )
        
        // Final response
        mockProvider.setupMockResponse("The weather is 72°F, and the difference from freezing is 40°F.")
        
        let agent = try Agent(
            model: AgenticModels.gpt4,
            tools: [TestWeatherTool.self, TestCalculatorTool.self],
            instructions: "You are a helpful assistant.",
            llmProvider: mockProvider
        )
        
        let response = try await agent.sendMessage("What's the weather in Boston and calculate how much warmer it is than freezing?")
        
        XCTAssertGreaterThan(agent.messages.count, 4) // Multiple tool calls
        XCTAssertTrue(response.content.contains("72") || response.content.contains("40"))
    }
    
    // MARK: - Tool Error Handling Tests
    
    func testAgentHandlesToolExecutionError() async throws {
        // Setup mock to call failing tool
        mockProvider.setupMockToolCallResponse(
            toolName: "failing_tool",
            arguments: "{}"
        )
        
        let agent = try Agent(
            model: AgenticModels.gpt4,
            tools: [TestFailingTool.self],
            instructions: "You are a helpful assistant.",
            llmProvider: mockProvider
        )
        
        await XCTAssertThrowsErrorAsync(
            try await agent.sendMessage("Use the failing tool")
        ) { error in
            XCTAssertTrue(error is AgentError)
        }
        
        XCTAssertEqual(agent.state, .error(AgentError.toolExecutionFailed("This tool always fails")))
    }
    
    func testAgentHandlesUnknownTool() async throws {
        // Setup mock to call non-existent tool
        mockProvider.setupMockToolCallResponse(
            toolName: "unknown_tool",
            arguments: "{}"
        )
        
        let agent = try Agent(
            model: AgenticModels.gpt4,
            tools: [],
            instructions: "You are a helpful assistant.",
            llmProvider: mockProvider
        )
        
        await XCTAssertThrowsErrorAsync(
            try await agent.sendMessage("Use unknown tool")
        ) { error in
            XCTAssertTrue(error is AgentError)
            if case .toolExecutionFailed(let message) = error as? AgentError {
                XCTAssertTrue(message.contains("Tool not found"))
            }
        }
    }
    
    // MARK: - Streaming with Tools Tests
    
    func testAgentStreamingWithTools() async throws {
        // Setup mock for streaming with tool call
        mockProvider.setupMockStreamingWithToolCall(
            toolName: "get_time",
            arguments: "{\"timezone\": \"UTC\"}"
        )
        
        let agent = try Agent(
            model: AgenticModels.gpt4,
            tools: [TestTimeTool.self],
            instructions: "You are a helpful assistant.",
            llmProvider: mockProvider
        )
        
        var receivedMessages: [ChatMessage] = []
        
        for await message in try await agent.stream("What time is it?") {
            receivedMessages.append(message)
        }
        
        XCTAssertGreaterThan(receivedMessages.count, 2)
        XCTAssertTrue(receivedMessages.contains { $0.message.role == .tool })
    }
    
    // MARK: - Tool Metadata Tests
    
    func testAgentToolMetadataTracking() async throws {
        mockProvider.setupMockToolCallResponse(
            toolName: "get_weather",
            arguments: "{\"city\": \"Tokyo\", \"unit\": \"celsius\"}"
        )
        mockProvider.setupMockResponse("Weather data retrieved successfully")
        
        let agent = try Agent(
            model: AgenticModels.gpt4,
            tools: [TestWeatherTool.self],
            instructions: "You are a helpful weather assistant.",
            llmProvider: mockProvider
        )
        
        let metadataTracker = MetadataTracker()
        agent.addCallbacks(metadataTracker)
        
        _ = try await agent.sendMessage("Weather in Tokyo")
        
        let metadata = metadataTracker.getAllMetadata()
        XCTAssertFalse(metadata.isEmpty)
    }
    
    // MARK: - Tool Choice Tests
    
    func testAgentWithRequiredToolChoice() async throws {
        mockProvider.setupMockToolCallResponse(
            toolName: "calculate",
            arguments: "{\"a\": 15, \"b\": 3, \"operation\": \"*\"}"
        )
        mockProvider.setupMockResponse("The result is 45")
        
        let agent = try Agent(
            model: AgenticModels.gpt4,
            tools: [TestCalculatorTool.self],
            instructions: "Always use the calculator for math problems.",
            llmProvider: mockProvider
        )
        
        let response = try await agent.sendMessage("What is 15 times 3?")
        
        // Verify tool was called
        let toolMessages = agent.messages.filter { $0.message.role == .tool }
        XCTAssertEqual(toolMessages.count, 1)
        XCTAssertTrue(response.content.contains("45"))
    }
    
    // MARK: - Multi-turn Conversation with Tools
    
    func testAgentMultiTurnWithTools() async throws {
        let agent = try Agent(
            model: AgenticModels.gpt4,
            tools: [TestWeatherTool.self, TestCalculatorTool.self],
            instructions: "You are a helpful assistant.",
            llmProvider: mockProvider
        )
        
        // First turn - weather
        mockProvider.setupMockToolCallResponse(
            toolName: "get_weather",
            arguments: "{\"city\": \"Miami\", \"unit\": \"fahrenheit\"}"
        )
        mockProvider.setupMockResponse("It's 85°F in Miami today")
        
        let response1 = try await agent.sendMessage("What's the weather in Miami?")
        XCTAssertTrue(response1.content.contains("85"))
        
        // Second turn - calculation based on previous context
        mockProvider.setupMockToolCallResponse(
            toolName: "calculate",
            arguments: "{\"a\": 85, \"b\": 32, \"operation\": \"-\"}"
        )
        mockProvider.setupMockResponse("The difference is 53°F")
        
        let response2 = try await agent.sendMessage("How much warmer is that than freezing?")
        XCTAssertTrue(response2.content.contains("53"))
        
        // Verify conversation history includes both tool interactions
        XCTAssertGreaterThan(agent.messages.count, 6)
    }
    
    // MARK: - Tool Chaining Tests
    
    func testAgentToolChaining() async throws {
        // Setup a sequence of tool calls that depend on each other
        mockProvider.setupMockToolCallResponse(
            toolName: "chained_tool",
            arguments: "{\"input\": \"initial\"}"
        )
        
        mockProvider.setupMockToolCallResponse(
            toolName: "chained_tool",
            arguments: "{\"input\": \"processed_initial\"}"
        )
        
        mockProvider.setupMockResponse("Chain completed successfully")
        
        let agent = try Agent(
            model: AgenticModels.gpt4,
            tools: [TestChainedTool.self],
            instructions: "Process requests in chains when needed.",
            llmProvider: mockProvider
        )
        
        let response = try await agent.sendMessage("Process this data through a chain")
        
        // Verify multiple tool calls occurred
        let toolMessages = agent.messages.filter { $0.message.role == .tool }
        XCTAssertGreaterThanOrEqual(toolMessages.count, 2)
    }
    
    // MARK: - Performance Tests
    
    func testAgentToolPerformance() async throws {
        let agent = try Agent(
            model: AgenticModels.gpt4,
            tools: [TestWeatherTool.self],
            instructions: "You are a weather assistant.",
            llmProvider: mockProvider
        )
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<5 {
            mockProvider.setupMockToolCallResponse(
                toolName: "get_weather",
                arguments: "{\"city\": \"City\(i)\", \"unit\": \"celsius\"}"
            )
            mockProvider.setupMockResponse("Weather report for City\(i)")
            
            _ = try await agent.sendMessage("Weather for City\(i)?")
        }
        
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should complete 5 tool-based conversations in reasonable time
        XCTAssertLessThan(timeElapsed, 10.0)
    }
}

// MARK: - Additional Test Tools

struct TestTimeTool: Tool {
    let name = "get_time"
    let description = "Get current time in specified timezone"
    
    @Parameter(description: "Timezone identifier")
    var timezone: String = "UTC"
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timezone)
        formatter.dateFormat = "HH:mm:ss"
        
        let timeString = formatter.string(from: Date())
        return ("Current time in \(timezone): \(timeString)", nil)
    }
}

struct TestChainedTool: Tool {
    let name = "chained_tool"
    let description = "A tool that can be chained with other calls"
    
    @Parameter(description: "Input data to process")
    var input: String = ""
    
    init() {}
    
    func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        let processed = "processed_\(input)"
        return ("Processed: \(processed)", nil)
    }
}

// TestFailingTool defined in ToolTests.swift

// MARK: - Mock Provider Extensions

extension MockLLMProvider {
    func setupMockStreamingWithToolCall(toolName: String, arguments: String) {
        // Implementation would need to be added to MockLLMProvider
        // for streaming with tool calls
    }
}
*/ 