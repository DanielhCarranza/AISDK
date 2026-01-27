import XCTest
@testable import AISDK

/// Comprehensive Agent Integration Tests with Real API Calls
/// Tests Agent as a black box with tools, multimodal, streaming, and callbacks
final class AgentIntegrationTests: XCTestCase {
    
    // MARK: - Test Setup
    
    // Helper function to get test provider from environment variable
    private func getTestProvider() -> OpenAIProvider {
        let modelName = ProcessInfo.processInfo.environment["TEST_MODEL"] ?? "gpt-4o"
        
        // Get API key
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            fatalError("OPENAI_API_KEY environment variable is required for integration tests")
        }
        
        // Map model names to OpenAIModels
        let model: LLMModelProtocol
        switch modelName {
        case "o4-mini":
            model = OpenAIModels.o4Mini
        case "gpt-4o":
            model = OpenAIModels.gpt4o
        case "gpt-4o-mini":
            model = OpenAIModels.gpt4oMini
        default:
            // Default to gpt-4o for unknown models
            model = OpenAIModels.gpt4o
        }
        
        return OpenAIProvider(model: model, apiKey: apiKey)
    }
    
    override func setUpWithError() throws {
        try super.setUpWithError()

        // Skip tests when API key is not available (don't fail, just skip)
        let openAIKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        try XCTSkipIf(openAIKey == nil || openAIKey?.isEmpty == true,
                      "OPENAI_API_KEY environment variable is required for integration tests - skipping")

        let testProvider = getTestProvider()
        print("🧪 Running Agent tests with model: \(testProvider.model.name)")
    }
    
    // MARK: - Basic Agent Tests
    
    func testAgentBasicSend() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [],
            instructions: "You are a helpful assistant. Keep responses brief."
        )
        
        let response = try await agent.send("What is the capital of France? Answer in one sentence.")
        
        XCTAssertFalse(response.displayContent.isEmpty)
        XCTAssertTrue(response.displayContent.lowercased().contains("paris"))
        XCTAssertEqual(agent.messages.count, 3) // System + User + Assistant
        print("✅ Basic send test completed: \(response.displayContent)")
    }
    
    func testAgentBasicStreaming() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [],
            instructions: "You are a helpful assistant. Count from 1 to 5."
        )
        
        let userMessage = ChatMessage(message: .user(content: .text("Count from 1 to 5, one number at a time.")))
        var responses: [ChatMessage] = []
        var fullContent = ""
        
        for try await message in agent.sendStream(userMessage) {
            responses.append(message)
            if case .assistant(let content, _, _) = message.message {
                let textContent = extractTextFromAssistantContent(content)
                fullContent = textContent
                print("Stream chunk: \(textContent)")
            }
        }
        
        XCTAssertGreaterThan(responses.count, 0)
        XCTAssertFalse(fullContent.isEmpty)
        print("✅ Basic streaming test completed with \(responses.count) chunks")
    }
    
    func testAgentWithImageURL() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [],
            instructions: "You are a helpful assistant that can analyze images."
        )
        
        // Use a simple, reliable image URL
        let imageURL = "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"
        
        let userMessage = ChatMessage(message: .user(content: .parts([
            .text("What do you see in this image? Describe it briefly."),
            .imageURL(.url(URL(string: imageURL)!))
        ])))
        
        var responses: [ChatMessage] = []
        
        for try await message in agent.sendStream(userMessage) {
            responses.append(message)
            if case .assistant(let content, _, _) = message.message {
                print("Image analysis: \(content)")
            }
        }
        
        XCTAssertGreaterThan(responses.count, 0)
        let finalResponse = responses.last!
        if case .assistant(let content, _, _) = finalResponse.message {
            let textContent = extractTextFromAssistantContent(content)
            XCTAssertFalse(textContent.isEmpty)
            // Should contain some visual descriptors
            XCTAssertTrue(textContent.lowercased().contains("nature") || 
                         textContent.lowercased().contains("board") ||
                         textContent.lowercased().contains("path") ||
                         textContent.lowercased().contains("green"))
        }
        print("✅ Multimodal test completed")
    }
    
    func testAgentConversationFlow() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [],
            instructions: "You are a helpful assistant with good memory."
        )
        
        // First message
        let response1 = try await agent.send("My name is John and I like pizza.")
        XCTAssertFalse(response1.displayContent.isEmpty)
        
        // Second message referencing previous context
        let response2 = try await agent.send("What's my name and favorite food?")
        XCTAssertTrue(response2.displayContent.lowercased().contains("john"))
        XCTAssertTrue(response2.displayContent.lowercased().contains("pizza"))
        
        // Verify conversation history
        XCTAssertEqual(agent.messages.count, 5) // System + User1 + Assistant1 + User2 + Assistant2
        print("✅ Conversation flow test completed")
    }
    
    // MARK: - Agent + Tools Tests
    
    func testAgentWithWeatherTool() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [TestWeatherTool.self],
            instructions: "You are a helpful weather assistant. Use the weather tool when asked about weather."
        )
        
        let response = try await agent.send("What's the weather in Boston?")
        
        XCTAssertFalse(response.displayContent.isEmpty)
        // Should have called the weather tool
        let toolMessages = agent.messages.filter { message in
            if case .tool = message.message { return true }
            return false
        }
        XCTAssertEqual(toolMessages.count, 1)
        
        if case .tool(let content, let name, _) = toolMessages.first!.message {
            XCTAssertEqual(name, "get_weather")
            XCTAssertTrue(content.contains("Boston"))
        }
        
        print("✅ Weather tool test completed")
    }
    
    func testAgentStreamingWithTool() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [TestWeatherTool.self],
            instructions: "You are a helpful weather assistant."
        )
        
        let userMessage = ChatMessage(message: .user(content: .text("What's the weather in San Francisco?")))
        var responses: [ChatMessage] = []
        var toolCalled = false
        
        for try await message in agent.sendStream(userMessage) {
            responses.append(message)
            
            switch message.message {
            case .assistant(let content, _, _):
                let textContent = extractTextFromAssistantContent(content)
                print("Assistant: \(textContent)")
            case .tool(let content, let name, _):
                print("Tool \(name): \(content)")
                XCTAssertEqual(name, "get_weather")
                toolCalled = true
            default:
                break
            }
        }
        
        XCTAssertGreaterThan(responses.count, 1)
        XCTAssertTrue(toolCalled)
        print("✅ Streaming with tool test completed")
    }
    
    func testAgentMultimodalWithTool() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [TestWeatherTool.self],
            instructions: "You are a helpful assistant that can analyze images and provide weather information."
        )
        
        let imageURL = "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"
        
        let userMessage = ChatMessage(message: .user(content: .parts([
            .text("Look at this image and tell me the weather in Wisconsin using the weather tool."),
            .imageURL(.url(URL(string: imageURL)!))
        ])))
        
        var responses: [ChatMessage] = []
        var toolCalled = false
        var imageAnalyzed = false
        
        for try await message in agent.sendStream(userMessage) {
            responses.append(message)
            
            switch message.message {
            case .assistant(let content, _, _):
                let textContent = extractTextFromAssistantContent(content)
                if textContent.lowercased().contains("wisconsin") || textContent.lowercased().contains("weather") {
                    imageAnalyzed = true
                }
                print("Assistant: \(textContent)")
            case .tool(let content, let name, _):
                print("Tool \(name): \(content)")
                if name == "get_weather" {
                    toolCalled = true
                }
            default:
                break
            }
        }
        
        XCTAssertGreaterThan(responses.count, 1)
        XCTAssertTrue(toolCalled)
        print("✅ Multimodal + tool test completed")
    }
    
    func testAgentToolErrorHandling() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [TestFailingTool.self],
            instructions: "Use the failing tool when asked to do something that would fail."
        )
        
        let userMessage = ChatMessage(message: .user(content: .text("Please use the failing tool to demonstrate error handling.")))
        var responses: [ChatMessage] = []
        var errorHandled = false
        
        do {
            for try await message in agent.sendStream(userMessage, requiredTool: "failing_tool") {
                responses.append(message)
                
                switch message.message {
                case .assistant(let content, _, _):
                    // Agent should handle the error gracefully
                    let textContent = extractTextFromAssistantContent(content)
                    if textContent.lowercased().contains("error") || 
                       textContent.lowercased().contains("failed") ||
                       textContent.lowercased().contains("sorry") {
                        errorHandled = true
                    }
                    print("Assistant: \(textContent)")
                case .tool(let content, let name, _):
                    print("Tool \(name): \(content)")
                default:
                    break
                }
            }
        } catch {
            // Error should be properly wrapped
            print("Caught error: \(error)")
            errorHandled = true
        }
        
        XCTAssertTrue(errorHandled)
        print("✅ Tool error handling test completed")
    }
    
    func testAgentUnknownToolError() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [], // No tools registered
            instructions: "You are a helpful assistant."
        )
        
        // Force the agent to try to call a non-existent tool
        do {
            for try await message in agent.sendStream(
                ChatMessage(message: .user(content: .text("Use some tool"))),
                requiredTool: "nonexistent_tool"
            ) {
                print("Message: \(message)")
            }
        } catch {
            // Should fail gracefully
            print("Properly caught unknown tool error: \(error)")
            XCTAssertTrue(error is AgentError || error.localizedDescription.contains("tool"))
        }
        
        print("✅ Unknown tool error test completed")
    }
    
    func testAgentRequiredToolChoice() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [TestWeatherTool.self, TestCalculatorTool.self],
            instructions: "You are a helpful assistant with access to weather and calculator tools."
        )
        
        let userMessage = ChatMessage(message: .user(content: .text("Calculate 15 times 3")))
        var responses: [ChatMessage] = []
        var calculatorUsed = false
        
        // Force calculator tool usage
        for try await message in agent.sendStream(userMessage, requiredTool: "calculate") {
            responses.append(message)
            
            if case .tool(let content, let name, _) = message.message {
                if name == "calculate" {
                    calculatorUsed = true
                    XCTAssertTrue(content.contains("45"))
                }
            }
        }
        
        XCTAssertTrue(calculatorUsed)
        print("✅ Required tool choice test completed")
    }
    
    // MARK: - Agent Callbacks Tests
    
    func testAgentBasicCallbacks() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [TestWeatherTool.self],
            instructions: "You are a helpful weather assistant."
        )
        
        let tracker = TestCallbackTracker()
        agent.addCallbacks(tracker)
        
        let userMessage = ChatMessage(message: .user(content: .text("What's the weather in Paris?")))
        
        for try await _ in agent.sendStream(userMessage) {
            // Just process the stream
        }
        
        // Verify callbacks were called
        XCTAssertGreaterThan(tracker.messagesReceived.count, 0)
        XCTAssertGreaterThan(tracker.toolsExecuted.count, 0)
        XCTAssertEqual(tracker.toolsExecuted.first?.0, "get_weather")
        
        print("✅ Basic callbacks test completed")
        print("   Messages received: \(tracker.messagesReceived.count)")
        print("   Tools executed: \(tracker.toolsExecuted.count)")
    }
    
    func testAgentCallbackCancellation() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [],
            instructions: "You are a helpful assistant."
        )
        
        let tracker = TestCallbackTracker()
        tracker.shouldCancel = true // Set to cancel after first message
        agent.addCallbacks(tracker)
        
        let userMessage = ChatMessage(message: .user(content: .text("Hello!")))
        
        do {
            for try await _ in agent.sendStream(userMessage) {
                XCTFail("Should have been cancelled")
            }
        } catch {
            // Should throw cancellation error
            XCTAssertTrue(error is AgentError)
            print("✅ Callback cancellation test completed")
        }
    }
    
    func testAgentMetadataTracking() async throws {
        let agent = Agent(
            llm: getTestProvider(),
            tools: [TestWeatherTool.self],
            instructions: "You are a helpful weather assistant."
        )
        
        let metadataTracker = MetadataTracker()
        agent.addCallbacks(metadataTracker)
        
        let userMessage = ChatMessage(message: .user(content: .text("What's the weather in Tokyo?")))
        
        for try await message in agent.sendStream(userMessage) {
            if case .tool = message.message {
                // Tool message should have metadata
                print("Tool message metadata: \(message.metadata != nil ? "present" : "none")")
            }
        }
        
        // MetadataTracker should have captured metadata
        print("✅ Metadata tracking test completed")
        print("   Last metadata: \(metadataTracker.lastMetadata != nil ? "present" : "none")")
    }
}

// MARK: - Helper Functions

/// Extracts text content from AssistantContent enum
private func extractTextFromAssistantContent(_ content: AssistantContent) -> String {
    switch content {
    case .text(let text):
        return text
    case .parts(let parts):
        return parts.joined(separator: "\n")
    }
}

// MARK: - Test Callback Tracker

class TestCallbackTracker: AgentCallbacks {
    var messagesReceived: [Message] = []
    var toolsExecuted: [(String, String)] = [] // (name, arguments)
    var llmRequests: [String] = []
    var shouldCancel = false
    
    func onMessageReceived(message: Message) async -> CallbackResult {
        messagesReceived.append(message)
        return shouldCancel ? .cancel : .continue
    }
    
    func onBeforeToolExecution(name: String, arguments: String) async -> CallbackResult {
        toolsExecuted.append((name, arguments))
        return .continue
    }
    
    func onBeforeLLMRequest(messages: [Message]) async -> CallbackResult {
        llmRequests.append("LLM request with \(messages.count) messages")
        return .continue
    }
    
    func onStreamChunk(chunk: Message) async -> CallbackResult {
        // Track streaming chunks
        return .continue
    }
} 