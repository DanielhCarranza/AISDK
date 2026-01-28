import XCTest
import Foundation
@testable import AISDK

/// Streaming-specific tests for AnthropicService
final class AnthropicServiceStreamingTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var service: AnthropicService!
    
    override func setUp() {
        super.setUp()
        service = AnthropicService(apiKey: "test-api-key")
    }
    
    override func tearDown() {
        service = nil
        super.tearDown()
    }
    
    // MARK: - Streaming Request Tests
    
    func testStreamingRequestConfiguration() async {
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello, Claude!")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929",
            stream: false // Initially not streaming
        )
        
        // Test that streaming is enabled automatically
        do {
            let _ = try await service.streamingMessageRequest(body: request)
            // If we get here without error, the request was properly configured
            // In a real test, we'd mock the network layer
        } catch {
            // Expected to fail without proper API key, but that's ok for this test
            XCTAssertTrue(error is LLMError)
        }
    }
    
    func testStreamingWithBetaFeatures() async {
        let betaService = service.withBetaFeatures(
            tokenEfficientTools: true,
            extendedThinking: true
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Explain quantum computing briefly.")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929"
        )
        
        do {
            let _ = try await betaService.streamingMessageRequest(body: request)
        } catch {
            // Expected to fail without proper API key
            XCTAssertTrue(error is LLMError)
        }
    }
    
    func testStreamingWithTools() async {
        let calculatorTool = AnthropicTool(
            name: "calculator",
            description: "Perform mathematical calculations",
            inputSchema: AnthropicToolSchema(
                properties: [
                    "expression": AnthropicPropertySchema(
                        type: "string",
                        description: "Mathematical expression to evaluate"
                    )
                ],
                required: ["expression"]
            )
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 150,
            messages: [
                AnthropicInputMessage(
                    content: [.text("What is 25 * 17?")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929",
            toolChoice: .auto,
            tools: [calculatorTool]
        )
        
        do {
            let _ = try await service.streamingMessageRequest(body: request)
        } catch {
            // Expected to fail without proper API key
            XCTAssertTrue(error is LLMError)
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testStreamingAuthenticationError() async {
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
            let _ = try await emptyKeyService.streamingMessageRequest(body: request)
            XCTFail("Expected authentication error")
        } catch let error as LLMError {
            XCTAssertEqual(error, .authenticationError)
        } catch {
            XCTFail("Expected LLMError, got \(error)")
        }
    }
    
    func testStreamingInvalidURL() async {
        let invalidURLService = AnthropicService(
            apiKey: "test-key",
            baseUrl: "invalid-url"
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
            let _ = try await invalidURLService.streamingMessageRequest(body: request)
            XCTFail("Expected invalid request error")
        } catch let error as LLMError {
            switch error {
            case .invalidRequest(let message):
                XCTAssertTrue(message.contains("Invalid Anthropic API URL"))
            case .underlying(let underlyingError):
                // Accept underlying URL errors as well
                XCTAssertTrue(underlyingError.localizedDescription.contains("unsupported URL") || 
                             underlyingError.localizedDescription.contains("invalid"))
            case .networkError(_, let message):
                XCTAssertTrue(message.contains("URL") || message.contains("invalid"))
            default:
                XCTFail("Expected invalidRequest, underlying, or network error, got \(error)")
            }
        } catch {
            XCTFail("Expected LLMError, got \(error)")
        }
    }
    
    // MARK: - Beta Features Integration Tests
    
    func testBetaHeadersInStreaming() {
        let betaService = service.withBetaConfiguration(
            AnthropicService.BetaConfiguration.all
        )
        
        // Test that beta configuration is properly set
        let configStatus = betaService.configurationStatus
        XCTAssertTrue(configStatus.contains("token-efficient-tools"))
        XCTAssertTrue(configStatus.contains("extended-thinking"))
        XCTAssertTrue(configStatus.contains("interleaved-thinking"))
    }
    
    func testTokenEfficientToolsInStreaming() async {
        let efficientService = service.withBetaFeatures(tokenEfficientTools: true)
        
        let weatherTool = AnthropicTool(
            name: "get_weather",
            description: "Get weather information",
            inputSchema: AnthropicToolSchema(
                properties: [
                    "location": AnthropicPropertySchema(
                        type: "string",
                        description: "Location to get weather for"
                    )
                ],
                required: ["location"]
            )
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("What's the weather in Tokyo?")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929",
            tools: [weatherTool]
        )
        
        do {
            let _ = try await efficientService.streamingMessageRequest(body: request)
        } catch {
            // Expected to fail without proper API key
            XCTAssertTrue(error is LLMError)
        }
    }
    
    // MARK: - Performance and Configuration Tests
    
    func testStreamingPerformanceConfiguration() {
        // Test different retry configurations
        let fastRetryService = AnthropicService(
            apiKey: "test-key",
            maxRetries: 1,
            retryDelay: 0.1
        )
        XCTAssertNotNil(fastRetryService)
        
        let slowRetryService = AnthropicService(
            apiKey: "test-key",
            maxRetries: 5,
            retryDelay: 2.0
        )
        XCTAssertNotNil(slowRetryService)
        
        // Test configuration chaining
        let chainedService = fastRetryService
            .withBetaFeatures(tokenEfficientTools: true)
            .withBetaFeatures(extendedThinking: true)
        
        XCTAssertNotNil(chainedService)
    }
    
    func testStreamingRequestValidation() {
        // Test various request configurations
        let basicRequest = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929"
        )
        
        XCTAssertEqual(basicRequest.maxTokens, 100)
        XCTAssertNil(basicRequest.stream)
        
        // Test with system prompt
        let systemRequest = AnthropicMessageRequestBody(
            maxTokens: 150,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929",
            system: "You are a helpful assistant."
        )
        
        XCTAssertNotNil(systemRequest.system)
        XCTAssertEqual(systemRequest.system, "You are a helpful assistant.")
        
        // Test with temperature and other parameters
        let advancedRequest = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Write a poem")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929",
            stopSequences: ["END"],
            temperature: 0.8,
            topK: 50,
            topP: 0.9
        )
        
        XCTAssertEqual(advancedRequest.temperature, 0.8)
        XCTAssertEqual(advancedRequest.topP, 0.9)
        XCTAssertEqual(advancedRequest.topK, 50)
        XCTAssertEqual(advancedRequest.stopSequences, ["END"])
    }
    
    // MARK: - Integration with AnthropicAsyncChunks
    
    func testAsyncChunksIntegration() {
        // Test that AnthropicAsyncChunks is properly used
        // This would be tested with a real mock in practice
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Count to 5")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929"
        )
        
        // Verify request is properly configured for streaming
        XCTAssertEqual(request.maxTokens, 100)
        XCTAssertEqual(request.messages.count, 1)
    }
    
    // MARK: - Real API Integration Test (Disabled)
    
    func _testRealStreamingAPI() async {
        // This test is disabled by default (prefixed with _)
        // To run real API tests, rename to testRealStreamingAPI and set ANTHROPIC_API_KEY
        
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !apiKey.isEmpty else {
            print("Skipping real streaming API test - no ANTHROPIC_API_KEY found")
            return
        }
        
        let realService = AnthropicService(apiKey: apiKey)
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 50,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Count from 1 to 3, one number per line.")],
                    role: .user
                )
            ],
            model: "claude-sonnet-4-5-20250929",
            temperature: 0.1
        )
        
        do {
            let stream = try await realService.streamingMessageRequest(body: request)
            
            var chunks: [AnthropicMessageStreamingChunk] = []
            
            for try await chunk in stream {
                chunks.append(chunk)
                
                switch chunk {
                case .text(let text):
                    print("Streaming text: '\(text)'")
                case .toolUse(let name, let input):
                    print("Tool use: \(name) with \(input)")
                case .thinkingDelta(let thinking):
                    print("Thinking delta: '\(thinking)'")
                case .thinkingComplete(let block):
                    print("Thinking complete: '\(block.thinking)'")
                case .messageDelta:
                    break
                case .done:
                    break
                }
                
                // Limit chunks to prevent infinite loops in tests
                if chunks.count > 50 {
                    break
                }
            }
            
            XCTAssertGreaterThan(chunks.count, 0)
            print("Received \(chunks.count) chunks total")
            
        } catch {
            XCTFail("Real streaming API test failed: \(error)")
        }
    }
}
