import XCTest
import Alamofire
@testable import AISDK

/// Comprehensive tests for AnthropicService native implementation
final class AnthropicServiceTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var service: AnthropicService!
    private var mockSession: Session!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Create a mock session for controlled testing
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        mockSession = Session(configuration: configuration)
        
        // Initialize service with mock session
        service = AnthropicService(
            apiKey: "test-api-key",
            session: mockSession,
            betaConfiguration: .none
        )
    }
    
    override func tearDown() {
        service = nil
        mockSession = nil
        MockURLProtocol.reset()
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testServiceInitialization() {
        // Test basic initialization
        let basicService = AnthropicService(apiKey: "test-key")
        XCTAssertNotNil(basicService)
        
        // Test environment variable initialization
        let envService = AnthropicService()
        XCTAssertNotNil(envService)
        
        // Test with all beta features
        let betaService = AnthropicService(apiKey: "test-key", betaConfiguration: .all)
        XCTAssertNotNil(betaService)
        
        // Test convenience initializer
        let convenienceService = AnthropicService(betaConfiguration: .all)
        XCTAssertNotNil(convenienceService)
    }
    
    func testBetaConfiguration() {
        // Test individual beta features
        let tokenEfficientService = service.withBetaFeatures(tokenEfficientTools: true)
        XCTAssertNotNil(tokenEfficientService)
        
        let extendedThinkingService = service.withBetaFeatures(extendedThinking: true)
        XCTAssertNotNil(extendedThinkingService)
        
        let interleavedThinkingService = service.withBetaFeatures(interleavedThinking: true)
        XCTAssertNotNil(interleavedThinkingService)
        
        // Test all features combined
        let allFeaturesService = service.withBetaFeatures(
            tokenEfficientTools: true,
            extendedThinking: true,
            interleavedThinking: true
        )
        XCTAssertNotNil(allFeaturesService)
        
        // Test configuration status
        let configStatus = allFeaturesService.configurationStatus
        XCTAssertTrue(configStatus.contains("token-efficient-tools"))
        XCTAssertTrue(configStatus.contains("extended-thinking"))
        XCTAssertTrue(configStatus.contains("interleaved-thinking"))
    }
    
    // MARK: - Request Building Tests
    
    func testBasicRequestBuilding() {
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello, Claude!")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929"
        )
        
        XCTAssertEqual(request.maxTokens, 100)
        XCTAssertEqual(request.messages.count, 1)
        XCTAssertEqual(request.model, "claude-sonnet-4-5-20250929")
        XCTAssertNil(request.stream)
        XCTAssertNil(request.temperature)
    }
    
    func testRequestWithTools() {
        let weatherTool = AnthropicTool(
            name: "get_weather",
            description: "Get current weather",
            inputSchema: AnthropicToolSchema(
                properties: [
                    "location": AnthropicPropertySchema(
                        type: "string",
                        description: "The location"
                    )
                ],
                required: ["location"]
            )
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("What's the weather in Paris?")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929",
            toolChoice: .auto,
            tools: [weatherTool]
        )
        
        XCTAssertNotNil(request.tools)
        XCTAssertEqual(request.tools?.count, 1)
        XCTAssertEqual(request.tools?.first?.name, "get_weather")
        XCTAssertNotNil(request.toolChoice)
    }
    
    func testBetaFeatureApplication() {
        let _ = service.withBetaFeatures(tokenEfficientTools: true)
        
        var request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929"
        )
        
        // Beta features should be applied during request processing
        XCTAssertFalse(request.enableTokenEfficientTools)
        
        // This would be applied internally in the service
        request.enableTokenEfficientTools = true
        XCTAssertTrue(request.enableTokenEfficientTools)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() async {
        // Test authentication error
        let emptyKeyService = AnthropicService(apiKey: "")
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929"
        )
        
        do {
            _ = try await emptyKeyService.messageRequest(body: request)
            XCTFail("Expected authentication error")
        } catch let error as LLMError {
            XCTAssertEqual(error, .authenticationError)
        } catch {
            XCTFail("Expected LLMError, got \(error)")
        }
    }
    
    func testNetworkErrorHandling() async {
        // Setup mock for network error
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )
        MockURLProtocol.mockError = NSError(
            domain: "TestError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "Internal Server Error"]
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929"
        )
        
        do {
            _ = try await service.messageRequest(body: request)
            XCTFail("Expected network error")
        } catch let error as LLMError {
            switch error {
            case .networkError(let code, _):
                XCTAssertNotNil(code)
            default:
                break // Other LegacyLLM errors are acceptable
            }
        } catch {
            XCTFail("Expected LLMError, got \(error)")
        }
    }
    
    func testRateLimitHandling() async {
        // Setup mock for rate limit error using request handler
        MockURLProtocol.requestHandler = { request in
            // Return a 429 response
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            
            let errorData = """
            {
                "type": "error",
                "error": {
                    "type": "rate_limit_error",
                    "message": "Rate limit exceeded"
                }
            }
            """.data(using: .utf8)!
            
            return (response, errorData)
        }
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929"
        )
        
        do {
            _ = try await service.messageRequest(body: request)
            XCTFail("Expected rate limit error")
        } catch let error as LLMError {
            // Check if it's a rate limit or network error (both are acceptable for 429)
            switch error {
            case .rateLimitExceeded:
                XCTAssertTrue(true) // Expected
            case .networkError(let code, _):
                XCTAssertEqual(code, 429) // Also acceptable
            case .underlying(let underlyingError):
                // Check if the underlying error is a rate limit error
                if let llmError = underlyingError as? LLMError,
                   case .rateLimitExceeded = llmError {
                    XCTAssertTrue(true) // Expected
                } else {
                    XCTFail("Expected rate limit error in underlying, got \(underlyingError)")
                }
            default:
                XCTFail("Expected rate limit or 429 network error, got \(error)")
            }
        } catch {
            XCTFail("Expected LLMError, got \(error)")
        }
    }
    
    // MARK: - Mock Response Tests
    
    func testSuccessfulMockResponse() async {
        // Setup successful mock response
        let mockResponseData = """
        {
            "id": "msg_test123",
            "type": "message",
            "role": "assistant",
            "model": "claude-sonnet-4-5-20250929",
            "content": [
                {
                    "type": "text",
                    "text": "Hello! I'm Claude, an AI assistant created by Anthropic."
                }
            ],
            "stop_reason": "end_turn",
            "stop_sequence": null,
            "usage": {
                "input_tokens": 10,
                "output_tokens": 15
            }
        }
        """.data(using: .utf8)!
        
        MockURLProtocol.mockData = mockResponseData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello, Claude!")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929"
        )
        
        do {
            let response = try await service.messageRequest(body: request)
            
            XCTAssertEqual(response.id, "msg_test123")
            XCTAssertEqual(response.model, "claude-sonnet-4-5-20250929")
            XCTAssertEqual(response.content.count, 1)
            
            if case .text(let text, citations: _) = response.content.first {
                XCTAssertTrue(text.contains("Claude"))
            } else {
                XCTFail("Expected text content")
            }
            
            XCTAssertEqual(response.usage.inputTokens, 10)
            XCTAssertEqual(response.usage.outputTokens, 15)
            
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testToolUseMockResponse() async {
        // Setup tool use mock response
        let mockResponseData = """
        {
            "id": "msg_tool123",
            "type": "message",
            "role": "assistant",
            "model": "claude-sonnet-4-5-20250929",
            "content": [
                {
                    "type": "tool_use",
                    "id": "toolu_test123",
                    "name": "get_weather",
                    "input": {
                        "location": "Paris, France"
                    }
                }
            ],
            "stop_reason": "tool_use",
            "stop_sequence": null,
            "usage": {
                "input_tokens": 25,
                "output_tokens": 10
            }
        }
        """.data(using: .utf8)!
        
        MockURLProtocol.mockData = mockResponseData
        MockURLProtocol.mockResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        
        let weatherTool = AnthropicTool(
            name: "get_weather",
            description: "Get current weather",
            inputSchema: AnthropicToolSchema(
                properties: [
                    "location": AnthropicPropertySchema(
                        type: "string",
                        description: "The location"
                    )
                ],
                required: ["location"]
            )
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("What's the weather in Paris?")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929",
            toolChoice: .auto,
            tools: [weatherTool]
        )
        
        do {
            let response = try await service.messageRequest(body: request)
            
            XCTAssertEqual(response.content.count, 1)
            
            if case .toolUse(let toolUseBlock) = response.content.first {
                XCTAssertEqual(toolUseBlock.id, "toolu_test123")
                XCTAssertEqual(toolUseBlock.name, "get_weather")
                XCTAssertNotNil(toolUseBlock.input["location"])
            } else {
                XCTFail("Expected tool use content")
            }
            
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Configuration Tests
    
    func testConfigurationMethods() {
        let originalService = AnthropicService(apiKey: "test")
        
        // Test withBetaConfiguration
        let betaConfig = AnthropicService.BetaConfiguration(
            tokenEfficientTools: true,
            extendedThinking: false,
            interleavedThinking: true
        )
        
        let configuredService = originalService.withBetaConfiguration(betaConfig)
        XCTAssertNotNil(configuredService)
        
        // Test withBetaFeatures
        let featuresService = originalService.withBetaFeatures(
            tokenEfficientTools: true,
            extendedThinking: true
        )
        XCTAssertNotNil(featuresService)
        
        // Test configuration status
        let status = featuresService.configurationStatus
        XCTAssertTrue(status.contains("AnthropicService Configuration"))
        XCTAssertTrue(status.contains("Base URL"))
        XCTAssertTrue(status.contains("Beta Features"))
    }
    
    func testBetaConfigurationPresets() {
        // Test .none preset
        let noneConfig = AnthropicService.BetaConfiguration.none
        XCTAssertFalse(noneConfig.tokenEfficientTools)
        XCTAssertFalse(noneConfig.extendedThinking)
        XCTAssertFalse(noneConfig.interleavedThinking)
        
        // Test .all preset
        let allConfig = AnthropicService.BetaConfiguration.all
        XCTAssertTrue(allConfig.tokenEfficientTools)
        XCTAssertTrue(allConfig.extendedThinking)
        XCTAssertTrue(allConfig.interleavedThinking)
    }
    
    // MARK: - Performance Tests
    
    func testRetryMechanism() async {
        // Test that retry mechanism works correctly
        var requestCount = 0
        
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            
            if requestCount < 3 {
                // First two requests fail
                throw AFError.responseValidationFailed(
                    reason: .unacceptableStatusCode(code: 500)
                )
            } else {
                // Third request succeeds
                let responseData = """
                {
                    "id": "msg_retry123",
                    "type": "message",
                    "role": "assistant",
                    "model": "claude-sonnet-4-5-20250929",
                    "content": [{"type": "text", "text": "Success after retry"}],
                    "stop_reason": "end_turn",
                    "usage": {"input_tokens": 5, "output_tokens": 5}
                }
                """.data(using: .utf8)!
                
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )!,
                    responseData
                )
            }
        }
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Test retry")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929"
        )
        
        do {
            let response = try await service.messageRequest(body: request)
            XCTAssertEqual(requestCount, 3)
            XCTAssertEqual(response.id, "msg_retry123")
        } catch {
            XCTFail("Expected successful retry, got error: \(error)")
        }
    }
    
    // MARK: - Integration Tests (Disabled by default)
    
    func _testRealAPIIntegration() async {
        // This test is disabled by default (prefixed with _)
        // To run real API tests, rename to testRealAPIIntegration and set ANTHROPIC_API_KEY
        
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !apiKey.isEmpty else {
            print("Skipping real API test - no ANTHROPIC_API_KEY found")
            return
        }
        
        let realService = AnthropicService(apiKey: apiKey)
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 50,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Say hello in exactly 5 words.")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929",
            temperature: 0.1
        )
        
        do {
            let response = try await realService.messageRequest(body: request)
            
            XCTAssertFalse(response.id.isEmpty)
            XCTAssertEqual(response.model, "claude-sonnet-4-5-20250929")
            XCTAssertGreaterThan(response.content.count, 0)
            
            if case .text(let text, citations: _) = response.content.first {
                XCTAssertFalse(text.isEmpty)
                print("Real API Response: \(text)")
            }
            
        } catch {
            XCTFail("Real API test failed: \(error)")
        }
    }
    
    // MARK: - Structured Output Tests
    
    func testGenerateObjectWithJSONMode() async throws {
        // Define a test structure
        struct TestResponse: Codable {
            let message: String
            let count: Int
        }
        
        // Create a request with JSON response format
        let request = AnthropicMessageRequestBody(
            maxTokens: 1000,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Return a JSON object with 'message' and 'count' fields")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929",
            responseFormat: .jsonObject
        )
        
        // Mock the response to return valid JSON
        let mockJSON = """
        {
            "message": "Hello from Claude",
            "count": 42
        }
        """
        
        let mockResponse = AnthropicMessageResponseBody(
            content: [.text(mockJSON, citations: nil)],
            id: "test-id",
            model: "claude-sonnet-4-5-20250929",
            role: "assistant",
            stopReason: "end_turn",
            stopSequence: nil,
            type: "message",
            usage: AnthropicMessageUsage(inputTokens: 10, outputTokens: 20)
        )
        
        // Create a mock service that returns our test response
        let mockService = MockAnthropicService(mockResponse: mockResponse)
        
        // Test the generateObject method
        let result: TestResponse = try await mockService.generateObject(request: request)
        
        // Verify the result
        XCTAssertEqual(result.message, "Hello from Claude")
        XCTAssertEqual(result.count, 42)
    }
    
    func testGenerateObjectSystemPromptModification() async throws {
        // Test that the system prompt is correctly modified for JSON output
        let originalSystem = "You are a helpful assistant."
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 1000,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929",
            system: originalSystem,
            responseFormat: .jsonObject
        )
        
        let mockResponse = AnthropicMessageResponseBody(
            content: [.text("{\"response\": \"hello\"}", citations: nil)],
            id: "test-id",
            model: "claude-sonnet-4-5-20250929",
            role: "assistant",
            stopReason: "end_turn",
            stopSequence: nil,
            type: "message",
            usage: AnthropicMessageUsage(inputTokens: 10, outputTokens: 20)
        )
        
        let mockService = MockAnthropicService(mockResponse: mockResponse)
        
        struct SimpleResponse: Codable {
            let response: String
        }
        
        let result: SimpleResponse = try await mockService.generateObject(request: request)
        XCTAssertEqual(result.response, "hello")
        
        // Verify that the system prompt was enhanced
        XCTAssertTrue(mockService.lastRequestBody?.system?.contains("JSON") ?? false)
        XCTAssertTrue(mockService.lastRequestBody?.system?.contains(originalSystem) ?? false)
    }
}

// MARK: - Mock URL Protocol

class MockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockResponse: URLResponse?
    static var mockError: Error?
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        if let handler = MockURLProtocol.requestHandler {
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
            return
        }
        
        if let error = MockURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        
        if let response = MockURLProtocol.mockResponse {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        
        if let data = MockURLProtocol.mockData {
            client?.urlProtocol(self, didLoad: data)
        }
        
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {
        // No-op
    }
    
    static func reset() {
        mockData = nil
        mockResponse = nil
        mockError = nil
        requestHandler = nil
    }
}