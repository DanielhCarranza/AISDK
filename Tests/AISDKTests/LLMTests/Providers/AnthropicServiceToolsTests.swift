import XCTest
import Foundation
@testable import AISDK

/// Tool integration tests for AnthropicService
/// Tests both mock and real API scenarios for tool functionality
final class AnthropicServiceToolsTests: XCTestCase {
    
    var service: AnthropicService!
    var mockService: MockAnthropicService!
    
    override func setUp() {
        super.setUp()
        
        if shouldUseRealAPI() {
            service = AnthropicService(
                apiKey: getAnthropicAPIKey(),
                betaConfiguration: .none
            )
        }
        
        mockService = MockAnthropicService()
    }
    
    override func tearDown() {
        service = nil
        mockService = nil
        super.tearDown()
    }
    
    // MARK: - Helper Functions
    
    private func shouldUseRealAPI() -> Bool {
        return ProcessInfo.processInfo.environment["USE_REAL_ANTHROPIC_API"] == "true" ||
               ProcessInfo.processInfo.environment["USE_REAL_API"] == "true"
    }
    
    private func getAnthropicAPIKey() -> String {
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ??
               ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] ??
               ""
    }
    
    // MARK: - Mock Tool Tests
    
    func testMockToolCreation() throws {
        // Test creating AnthropicTool from various Tool types
        let calculatorTool = AnthropicTool(
            name: "calculator",
            description: "Perform basic arithmetic calculations",
            inputSchema: AnthropicToolSchema(
                properties: [
                    "operation": AnthropicPropertySchema(
                        type: "string",
                        description: "The operation to perform",
                        enum: ["add", "subtract", "multiply", "divide"]
                    ),
                    "a": AnthropicPropertySchema(
                        type: "number",
                        description: "First number"
                    ),
                    "b": AnthropicPropertySchema(
                        type: "number",
                        description: "Second number"
                    )
                ],
                required: ["operation", "a", "b"]
            )
        )
        
        XCTAssertEqual(calculatorTool.name, "calculator")
        XCTAssertEqual(calculatorTool.description, "Perform basic arithmetic calculations")
        XCTAssertEqual(calculatorTool.inputSchema.required.count, 3)
        XCTAssertEqual(calculatorTool.inputSchema.properties.count, 3)
        
        print("✅ Mock Tool Creation Test Passed")
    }
    
    func testMockToolResponse() async throws {
        let weatherTool = createWeatherTool()
        
        // Setup mock response with tool use
        let mockResponse = AnthropicMessageResponseBody(
            content: [
                .text("I'll check the weather for you.", citations: nil),
                .toolUse(createMockToolUseBlock(
                    id: "tool_123",
                    name: "get_weather",
                    input: ["location": "Paris, France", "unit": "celsius"]
                ))
            ],
            id: "msg_test123",
            model: "claude-3-7-sonnet-20250219",
            role: "assistant",
            stopReason: "tool_use",
            stopSequence: nil,
            type: "message",
            usage: AnthropicMessageUsage(
                inputTokens: 50,
                outputTokens: 30
            )
        )
        
        mockService.setMockResponse(mockResponse)
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("What's the weather like in Paris?")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            toolChoice: .auto,
            tools: [weatherTool]
        )
        
        let response = try await mockService.messageRequest(body: request)
        
        XCTAssertEqual(response.content.count, 2)
        
        // Verify text content
        if case .text(let text, citations: _) = response.content[0] {
            XCTAssertEqual(text, "I'll check the weather for you.")
        } else {
            XCTFail("Expected text content")
        }
        
        // Verify tool use content
        if case .toolUse(let toolUse) = response.content[1] {
            XCTAssertEqual(toolUse.name, "get_weather")
            XCTAssertEqual(toolUse.input["location"] as? String, "Paris, France")
            XCTAssertEqual(toolUse.input["unit"] as? String, "celsius")
        } else {
            XCTFail("Expected tool use content")
        }
        
        XCTAssertEqual(response.stopReason, "tool_use")
        XCTAssertEqual(mockService.requestCount, 1)
        XCTAssertNotNil(mockService.lastRequest)
        
        print("✅ Mock Tool Response Test Passed")
    }
    
    func testMockToolChoiceOptions() async throws {
        let tools = [createWeatherTool(), createCalculatorTool()]
        
        let testCases: [(AnthropicToolChoice, String)] = [
            (.auto, "auto"),
            (.none, "none"),
            (.any, "any"),
            (.tool(name: "get_weather"), "specific tool")
        ]
        
        for (toolChoice, description) in testCases {
            let request = AnthropicMessageRequestBody(
                maxTokens: 100,
                messages: [
                    AnthropicInputMessage(
                        content: [.text("Test \(description)")],
                        role: .user
                    )
                ],
                model: "claude-3-7-sonnet-20250219",
                toolChoice: toolChoice,
                tools: tools
            )
            
            _ = try await mockService.messageRequest(body: request)
            
            // Note: Can't directly compare AnthropicToolChoice as it doesn't conform to Equatable
            XCTAssertNotNil(mockService.lastRequest?.toolChoice)
        }
        
        print("✅ Mock Tool Choice Options Test Passed")
    }
    
    // MARK: - Real API Tool Tests
    
    func testRealAPIBasicToolUse() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let weatherTool = createWeatherTool()
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("What's the weather like in San Francisco?")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            toolChoice: .auto,
            tools: [weatherTool]
        )
        
        let response = try await service.messageRequest(body: request)
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertGreaterThan(response.content.count, 0)
        
        // Check if tool was used
        let hasToolUse = response.content.contains { content in
            if case .toolUse = content { return true }
            return false
        }
        
        if hasToolUse {
            print("✅ Tool use detected in response")
            
            // Find the tool use block
            for content in response.content {
                if case .toolUse(let toolUse) = content {
                    XCTAssertEqual(toolUse.name, "get_weather")
                    XCTAssertNotNil(toolUse.input["location"])
                    print("Tool called with input: \(toolUse.input)")
                    break
                }
            }
        } else {
            print("⚠️ Tool was not used (Claude chose not to use it)")
        }
        
        print("✅ Real API Basic Tool Use Test Passed")
    }
    
    func testRealAPIToolWithBetaFeatures() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let efficientService = service.withBetaFeatures(tokenEfficientTools: true)
        let calculatorTool = createCalculatorTool()
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("What is 25 multiplied by 17?")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            toolChoice: .auto,
            tools: [calculatorTool]
        )
        
        let response = try await efficientService.messageRequest(body: request)
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertGreaterThan(response.content.count, 0)
        
        // Check if tool was used
        let hasToolUse = response.content.contains { content in
            if case .toolUse = content { return true }
            return false
        }
        
        if hasToolUse {
            print("✅ Tool use detected with beta features")
            
            // Find the tool use block
            for content in response.content {
                if case .toolUse(let toolUse) = content {
                    XCTAssertEqual(toolUse.name, "calculator")
                    XCTAssertNotNil(toolUse.input["operation"])
                    XCTAssertNotNil(toolUse.input["a"])
                    XCTAssertNotNil(toolUse.input["b"])
                    print("Calculator called with: \(toolUse.input)")
                    break
                }
            }
        }
        
        // Verify beta configuration is active
        let configStatus = efficientService.configurationStatus
        XCTAssertTrue(configStatus.contains("token-efficient-tools"))
        
        print("✅ Real API Tool with Beta Features Test Passed")
    }
    
    func testRealAPIMultipleTools() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let tools = [
            createWeatherTool(),
            createCalculatorTool(),
            createTimeTool()
        ]
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 300,
            messages: [
                AnthropicInputMessage(
                    content: [.text("What time is it, and what's 15 + 25?")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            toolChoice: .auto,
            tools: tools
        )
        
        let response = try await service.messageRequest(body: request)
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertGreaterThan(response.content.count, 0)
        
        var toolsUsed: [String] = []
        
        for content in response.content {
            if case .toolUse(let toolUse) = content {
                toolsUsed.append(toolUse.name)
                print("Tool used: \(toolUse.name) with input: \(toolUse.input)")
            }
        }
        
        if !toolsUsed.isEmpty {
            print("✅ Tools used: \(toolsUsed)")
        } else {
            print("⚠️ No tools were used (Claude chose not to use them)")
        }
        
        print("✅ Real API Multiple Tools Test Passed")
    }
    
    func testRealAPIToolChoice() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let weatherTool = createWeatherTool()
        
        // Test forcing tool use with .any
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello there!")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            toolChoice: .any,
            tools: [weatherTool]
        )
        
        let response = try await service.messageRequest(body: request)
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertGreaterThan(response.content.count, 0)
        
        // With .any, Claude should be forced to use a tool
        let hasToolUse = response.content.contains { content in
            if case .toolUse = content { return true }
            return false
        }
        
        if hasToolUse {
            print("✅ Tool was forced to be used with .any choice")
        } else {
            print("⚠️ Tool was not used despite .any choice")
        }
        
        print("✅ Real API Tool Choice Test Passed")
    }
    
    func testRealAPISpecificToolChoice() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let tools = [
            createWeatherTool(),
            createCalculatorTool()
        ]
        
        // Force use of specific tool
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("I need some help")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            toolChoice: .tool(name: "calculator"),
            tools: tools
        )
        
        let response = try await service.messageRequest(body: request)
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertGreaterThan(response.content.count, 0)
        
        // Should specifically use the calculator tool
        var usedCalculator = false
        
        for content in response.content {
            if case .toolUse(let toolUse) = content {
                if toolUse.name == "calculator" {
                    usedCalculator = true
                    print("✅ Specific tool (calculator) was used as requested")
                }
            }
        }
        
        if !usedCalculator {
            print("⚠️ Specific tool was not used")
        }
        
        print("✅ Real API Specific Tool Choice Test Passed")
    }
    
    // MARK: - Tool Streaming Tests
    
    func testRealAPIToolStreaming() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let weatherTool = createWeatherTool()
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("What's the weather in Tokyo?")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            toolChoice: .auto,
            tools: [weatherTool]
        )
        
        var chunks: [AnthropicMessageStreamingChunk] = []
        var textChunks: [String] = []
        var toolUseChunks: [(String, [String: Any])] = []
        
        let stream = try await service.streamingMessageRequest(body: request)
        
        for try await chunk in stream {
            chunks.append(chunk)
            
            switch chunk {
            case .text(let text):
                textChunks.append(text)
                print("Text chunk: '\(text)'")
            case .toolUse(let name, let input):
                toolUseChunks.append((name, input))
                print("Tool use chunk: \(name) with \(input)")
            }
            
            // Limit chunks to prevent infinite loops
            if chunks.count > 100 {
                break
            }
        }
        
        XCTAssertGreaterThan(chunks.count, 0)
        
        if !toolUseChunks.isEmpty {
            print("✅ Tool use detected in streaming response")
            print("Tool use chunks: \(toolUseChunks.count)")
        }
        
        if !textChunks.isEmpty {
            let fullText = textChunks.joined()
            print("Full text from stream: '\(fullText)'")
        }
        
        print("✅ Real API Tool Streaming Test Passed")
        print("Total chunks: \(chunks.count)")
    }
    
    // MARK: - Complex Tool Scenarios
    
    func testRealAPIComplexToolWorkflow() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        

        
        let tools = [
            createWeatherTool(),
            createCalculatorTool(),
            createTimeTool()
        ]
        
        // Multi-step conversation with tools
        let firstRequest = AnthropicMessageRequestBody(
            maxTokens: 300,
            messages: [
                AnthropicInputMessage(
                    content: [.text("I'm planning a trip. Can you help me calculate how much I'll spend if I buy 3 items at $25 each, and also tell me what time it is?")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            system: "You are a helpful travel assistant. Use tools when appropriate to help users.",
            toolChoice: .auto,
            tools: tools
        )
        
        let firstResponse = try await service.messageRequest(body: firstRequest)
        
        XCTAssertFalse(firstResponse.id.isEmpty)
        XCTAssertGreaterThan(firstResponse.content.count, 0)
        
        var toolsUsed: [String] = []
        var responses: [String] = []
        
        for content in firstResponse.content {
            switch content {
            case .text(let text, citations: _):
                responses.append(text)
            case .toolUse(let toolUse):
                toolsUsed.append(toolUse.name)
                print("Tool used: \(toolUse.name) with \(toolUse.input)")
            case .mcpToolUse(let mcpToolUse):
                toolsUsed.append(mcpToolUse.name)
                print("MCP Tool used: \(mcpToolUse.name) from \(mcpToolUse.serverName)")
            case .mcpToolResult(let mcpToolResult):
                print("MCP Tool result: \(mcpToolResult.allTextContent)")
            }
        }
        
        print("✅ Complex workflow completed")
        print("Tools used: \(toolsUsed)")
        print("Response parts: \(responses.count)")
        print("Total tokens - Input: \(firstResponse.usage.inputTokens), Output: \(firstResponse.usage.outputTokens)")
        
        print("✅ Real API Complex Tool Workflow Test Passed")
    }
    
    // MARK: - Helper Methods
    
    private func createMockToolUseBlock(id: String, name: String, input: [String: Any]) -> AnthropicToolUseBlock {
        // Create a mock tool use block since AnthropicToolUseBlock only has a Decodable init
        // We'll use a JSON encoding/decoding approach
        let mockJSON: [String: Any] = [
            "id": id,
            "name": name,
            "input": input,
            "type": "tool_use"
        ]
        
        let jsonData = try! JSONSerialization.data(withJSONObject: mockJSON)
        let decoder = JSONDecoder()
        return try! decoder.decode(AnthropicToolUseBlock.self, from: jsonData)
    }
    
    private func createWeatherTool() -> AnthropicTool {
        return AnthropicTool(
            name: "get_weather",
            description: "Get current weather information for a specific location",
            inputSchema: AnthropicToolSchema(
                properties: [
                    "location": AnthropicPropertySchema(
                        type: "string",
                        description: "The city and country, e.g. 'San Francisco, CA'"
                    ),
                    "unit": AnthropicPropertySchema(
                        type: "string",
                        description: "Temperature unit",
                        enum: ["celsius", "fahrenheit"]
                    )
                ],
                required: ["location"]
            )
        )
    }
    
    private func createCalculatorTool() -> AnthropicTool {
        return AnthropicTool(
            name: "calculator",
            description: "Perform basic arithmetic calculations",
            inputSchema: AnthropicToolSchema(
                properties: [
                    "operation": AnthropicPropertySchema(
                        type: "string",
                        description: "The operation to perform",
                        enum: ["add", "subtract", "multiply", "divide"]
                    ),
                    "a": AnthropicPropertySchema(
                        type: "number",
                        description: "First number"
                    ),
                    "b": AnthropicPropertySchema(
                        type: "number",
                        description: "Second number"
                    )
                ],
                required: ["operation", "a", "b"]
            )
        )
    }
    
    private func createTimeTool() -> AnthropicTool {
        return AnthropicTool(
            name: "get_current_time",
            description: "Get the current time and date",
            inputSchema: AnthropicToolSchema(
                properties: [
                    "timezone": AnthropicPropertySchema(
                        type: "string",
                        description: "Timezone (optional, defaults to UTC)"
                    ),
                    "format": AnthropicPropertySchema(
                        type: "string",
                        description: "Time format",
                        enum: ["12h", "24h"]
                    )
                ],
                required: []
            )
        )
    }
}

// MARK: - Mock AnthropicService

/// Mock implementation of AnthropicService for testing
public class MockAnthropicService {
    
    // MARK: - Configuration
    
    public var shouldThrowError = false
    public var errorToThrow: Error = LLMError.invalidRequest("Mock error")
    public var delay: TimeInterval = 0.1
    
    // MARK: - Mock Responses
    
    public var mockResponse: AnthropicMessageResponseBody?
    public var mockStreamChunks: [AnthropicMessageStreamingChunk] = []
    
    // MARK: - Tracking
    
    public private(set) var lastRequest: AnthropicMessageRequestBody?
    public private(set) var lastRequestBody: AnthropicMessageRequestBody?
    public private(set) var requestCount = 0
    
    // MARK: - Initialization
    
    public init() {
        setupDefaultResponses()
    }
    
    public init(mockResponse: AnthropicMessageResponseBody) {
        self.mockResponse = mockResponse
        // Don't call setupDefaultResponses() here since it would reset mockResponse
    }
    
    // MARK: - Mock Methods
    
    public func messageRequest(body: AnthropicMessageRequestBody) async throws -> AnthropicMessageResponseBody {
        lastRequest = body
        lastRequestBody = body
        requestCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        return mockResponse ?? createDefaultResponse(for: body)
    }
    
    public func streamingMessageRequest(body: AnthropicMessageRequestBody) -> AsyncThrowingStream<AnthropicMessageStreamingChunk, Error> {
        lastRequest = body
        requestCount += 1
        
        return AsyncThrowingStream { continuation in
            Task {
                if self.shouldThrowError {
                    continuation.finish(throwing: self.errorToThrow)
                    return
                }
                
                let chunks = self.mockStreamChunks.isEmpty ? self.createDefaultStreamChunks() : self.mockStreamChunks
                
                for chunk in chunks {
                    // Simulate streaming delay
                    try await Task.sleep(nanoseconds: UInt64(self.delay * 1_000_000_000))
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }
    
    public func generateObject<T: Decodable>(request: AnthropicMessageRequestBody) async throws -> T {
        // Simulate the system prompt modification logic from the real AnthropicService
        var enhancedRequest = request
        
        // Handle response format by modifying the system prompt
        if let responseFormat = request.responseFormat {
            let originalSystem = request.system ?? ""
            
            if let systemAddition = responseFormat.systemPromptAddition {
                let enhancedSystem = originalSystem.isEmpty 
                    ? systemAddition
                    : "\(originalSystem)\n\n\(systemAddition)"
                
                enhancedRequest = AnthropicMessageRequestBody(
                    maxTokens: request.maxTokens,
                    messages: request.messages,
                    model: request.model,
                    metadata: request.metadata,
                    stopSequences: request.stopSequences,
                    stream: request.stream,
                    system: enhancedSystem,
                    temperature: request.temperature,
                    toolChoice: request.toolChoice,
                    tools: request.tools,
                    topK: request.topK,
                    topP: request.topP,
                    thinking: request.thinking,
                    mcpServers: request.mcpServers,
                    responseFormat: nil // Remove from actual request since Anthropic doesn't support it
                )
            }
        }
        
        let response = try await messageRequest(body: enhancedRequest)
        
        // If T is AnthropicMessageResponseBody, return it directly
        if T.self is AnthropicMessageResponseBody.Type {
            return response as! T
        }
        
        // Otherwise, extract content and parse as JSON
        guard let firstContent = response.content.first else {
            throw LLMError.parsingError("No content in mock response")
        }
        
        let contentText: String
        switch firstContent {
        case .text(let text, citations: _):
            contentText = text
        case .toolUse(_):
            throw LLMError.parsingError("Received tool use response when expecting structured data")
        case .mcpToolUse(_):
            throw LLMError.parsingError("Received MCP tool use response when expecting structured data")
        case .mcpToolResult(_):
            throw LLMError.parsingError("Received MCP tool result response when expecting structured data")
        }
        
        guard let jsonData = contentText.data(using: .utf8) else {
            throw LLMError.parsingError("Failed to convert mock response to UTF-8 data")
        }
        
        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(T.self, from: jsonData)
            return result
        } catch {
            throw LLMError.parsingError("Failed to decode mock response to \(T.self): \(error.localizedDescription). Response content: \(contentText)")
        }
    }
    
    // MARK: - Helper Methods
    
    public func reset() {
        requestCount = 0
        lastRequest = nil
        shouldThrowError = false
        setupDefaultResponses()
    }
    
    public func setMockResponse(_ response: AnthropicMessageResponseBody) {
        mockResponse = response
    }
    
    public func setMockStreamChunks(_ chunks: [AnthropicMessageStreamingChunk]) {
        mockStreamChunks = chunks
    }
    
    // MARK: - Private Methods
    
    private func setupDefaultResponses() {
        // Only reset if not already set
        if mockResponse == nil {
            mockResponse = nil
        }
        mockStreamChunks = []
    }
    
    private func createDefaultResponse(for request: AnthropicMessageRequestBody) -> AnthropicMessageResponseBody {
        let responseId = "msg-mock-\(UUID().uuidString.prefix(8))"
        
        // Extract text from messages
        let inputText = request.messages.compactMap { message in
            message.content.compactMap { content in
                if case .text(let text) = content {
                    return text
                }
                return nil
            }.joined(separator: " ")
        }.joined(separator: " ")
        
        let responseText = "Mock response to: \(inputText)"
        
        return AnthropicMessageResponseBody(
            content: [.text(responseText, citations: nil)],
            id: responseId,
            model: request.model,
            role: "assistant",
            stopReason: "end_turn",
            stopSequence: nil,
            type: "message",
            usage: AnthropicMessageUsage(
                inputTokens: inputText.count / 4, // Rough token estimate
                outputTokens: responseText.count / 4
            )
        )
    }
    
    private func createDefaultStreamChunks() -> [AnthropicMessageStreamingChunk] {
        let textChunks = ["Hello", " from", " mock", " streaming", " service!"]
        return textChunks.map { .text($0) }
    }
}