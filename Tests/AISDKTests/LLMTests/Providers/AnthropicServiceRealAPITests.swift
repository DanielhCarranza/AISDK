import XCTest
import Foundation
@testable import AISDK

/// Real API integration tests for AnthropicService
/// These tests require a valid ANTHROPIC_API_KEY or CLAUDE_API_KEY environment variable
/// Set USE_REAL_ANTHROPIC_API=true to enable these tests
final class AnthropicServiceRealAPITests: XCTestCase {
    
    var service: AnthropicService!
    
    override func setUp() {
        super.setUp()
        
        guard shouldUseRealAPI() else {
            // Skip real API tests if not configured
            return
        }
        
        service = AnthropicService(
            apiKey: getAnthropicAPIKey(),
            betaConfiguration: .none
        )
    }
    
    override func tearDown() {
        service = nil
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
    
    // MARK: - Authentication & Configuration Tests
    
    func testRealAPIAuthentication() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let apiKey = getAnthropicAPIKey()
        XCTAssertFalse(apiKey.isEmpty, "API key is required for real API tests")
        
        let testService = AnthropicService(
            apiKey: apiKey,
            betaConfiguration: .none
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 50,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219"
        )
        
        // This should succeed with valid API key
        let response = try await testService.messageRequest(body: request)
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertEqual(response.role, "assistant")
        XCTAssertGreaterThan(response.content.count, 0)
        
        print("✅ Real API Authentication Test Passed")
        print("Response ID: \(response.id)")
    }
    
    func testRealAPIInvalidKey() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let invalidService = AnthropicService(
            apiKey: "invalid-key-12345",
            betaConfiguration: .none
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 50,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219"
        )
        
        do {
            _ = try await invalidService.messageRequest(body: request)
            XCTFail("Expected authentication error with invalid key")
        } catch let error as LLMError {
            switch error {
            case .authenticationError:
                XCTAssertTrue(true) // Expected
            case .networkError(let code, _):
                XCTAssertEqual(code, 401) // Also acceptable
            case .underlying(let underlyingError):
                // Check if underlying error is authentication-related
                if let llmError = underlyingError as? LLMError {
                    switch llmError {
                    case .authenticationError, .networkError(401, _):
                        XCTAssertTrue(true) // Expected
                    default:
                        XCTFail("Expected authentication error, got underlying \(llmError)")
                    }
                } else {
                    XCTFail("Expected authentication error, got underlying \(underlyingError)")
                }
            default:
                XCTFail("Expected authentication error, got \(error)")
            }
        } catch {
            XCTFail("Expected LLMError, got \(error)")
        }
        
        print("✅ Real API Invalid Key Test Passed")
    }
    
    // MARK: - Core Messaging Tests
    
    func testRealAPIBasicConversation() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello, Claude! Say hi back in exactly 3 words.")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            temperature: 0.1
        )
        
        let response = try await service.messageRequest(body: request)
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertEqual(response.model, "claude-3-7-sonnet-20250219")
        XCTAssertGreaterThan(response.content.count, 0)
        
        if case .text(let text, citations: _) = response.content.first {
            XCTAssertFalse(text.isEmpty)
            print("✅ Real API Basic Conversation Test Passed")
            print("Response: '\(text)'")
        } else {
            XCTFail("Expected text content in response")
        }
        
        // Validate usage information
        XCTAssertGreaterThan(response.usage.inputTokens, 0)
        XCTAssertGreaterThan(response.usage.outputTokens, 0)
    }
    
    func testRealAPISystemPrompt() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("What's your favorite color?")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            system: "You are a helpful assistant who always answers in exactly one word.",
            temperature: 0.1
        )
        
        let response = try await service.messageRequest(body: request)
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertGreaterThan(response.content.count, 0)
        
        if case .text(let text, citations: _) = response.content.first {
            // Should be roughly one word due to system prompt
            let wordCount = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .count
            
            XCTAssertLessThanOrEqual(wordCount, 3, "Expected roughly one word response")
            print("✅ Real API System Prompt Test Passed")
            print("Response: '\(text)' (word count: \(wordCount))")
        }
    }
    
    func testRealAPIMultiTurnConversation() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        // First turn
        let firstRequest = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("I'm thinking of a number between 1 and 10. Can you guess?")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            temperature: 0.1
        )
        
        let firstResponse = try await service.messageRequest(body: firstRequest)
        
        XCTAssertGreaterThan(firstResponse.content.count, 0)
        
        guard case .text(let firstText, citations: _) = firstResponse.content.first else {
            XCTFail("Expected text content in first response")
            return
        }
        
        // Second turn - continue conversation
        let secondRequest = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("I'm thinking of a number between 1 and 10. Can you guess?")],
                    role: .user
                ),
                AnthropicInputMessage(
                    content: [.text(firstText)],
                    role: .assistant
                ),
                AnthropicInputMessage(
                    content: [.text("Close! The number was 7. Try guessing a number between 1 and 5 now.")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            temperature: 0.1
        )
        
        let secondResponse = try await service.messageRequest(body: secondRequest)
        
        XCTAssertGreaterThan(secondResponse.content.count, 0)
        
        if case .text(let secondText) = secondResponse.content.first {
            print("✅ Real API Multi-turn Conversation Test Passed")
            print("First response: '\(firstText)'")
            print("Second response: '\(secondText)'")
        }
    }
    
    // MARK: - Model Support Tests
    
    func testRealAPIModelVersions() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let models = [
            "claude-3-7-sonnet-20250219",
            "claude-3-5-sonnet-20241022",
            "claude-3-5-haiku-20241022"
        ]
        
        for model in models {
            do {
                let request = AnthropicMessageRequestBody(
                    maxTokens: 50,
                    messages: [
                        AnthropicInputMessage(
                            content: [.text("Hello")],
                            role: .user
                        )
                    ],
                    model: model
                )
                
                let response = try await service.messageRequest(body: request)
                
                XCTAssertFalse(response.id.isEmpty)
                XCTAssertEqual(response.model, model)
                XCTAssertGreaterThan(response.content.count, 0)
                
                print("✅ Model \(model) works correctly")
            } catch {
                print("⚠️ Model \(model) failed: \(error)")
                // Don't fail the test for model availability issues
            }
        }
        
        print("✅ Real API Model Versions Test Completed")
    }
    
    // MARK: - Streaming Tests
    
    func testRealAPIStreaming() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Count from 1 to 5, one number per line.")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            temperature: 0.1
        )
        
        var chunks: [AnthropicMessageStreamingChunk] = []
        var accumulatedText = ""
        let startTime = Date()
        
        let stream = try await service.streamingMessageRequest(body: request)
        
        for try await chunk in stream {
            chunks.append(chunk)
            
            switch chunk {
            case .text(let text):
                accumulatedText += text
                print("Delta: '\(text)'", terminator: "")
            case .toolUse(_, _):
                print("Tool use chunk received")
            }
            
            // Limit chunks to prevent infinite loops
            if chunks.count > 100 {
                break
            }
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertGreaterThan(chunks.count, 0)
        XCTAssertFalse(accumulatedText.isEmpty)
        XCTAssertLessThan(duration, 30.0) // Should complete within 30 seconds
        
        print("\n✅ Real API Streaming Test Passed")
        print("Received \(chunks.count) chunks in \(String(format: "%.2f", duration)) seconds")
        print("Accumulated text: '\(accumulatedText)'")
    }
    
    // MARK: - Beta Features Tests
    
    func testRealAPIBetaFeatures() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let betaService = service.withBetaFeatures(
            tokenEfficientTools: true,
            extendedThinking: true
        )
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 150,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Explain quantum computing in simple terms.")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            temperature: 0.3
        )
        
        let response = try await betaService.messageRequest(body: request)
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertGreaterThan(response.content.count, 0)
        
        if case .text(let text, citations: _) = response.content.first {
            XCTAssertFalse(text.isEmpty)
            print("✅ Real API Beta Features Test Passed")
            print("Response with beta features: '\(text.prefix(100))...'")
        }
        
        // Verify beta configuration is active
        let configStatus = betaService.configurationStatus
        XCTAssertTrue(configStatus.contains("token-efficient-tools"))
        XCTAssertTrue(configStatus.contains("extended-thinking"))
    }
    
    func testRealAPITokenEfficientTools() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let efficientService = service.withBetaFeatures(tokenEfficientTools: true)
        
        let weatherTool = AnthropicTool(
            name: "get_weather",
            description: "Get current weather for a location",
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
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("What's the weather like in Paris, France?")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            toolChoice: .auto,
            tools: [weatherTool]
        )
        
        let response = try await efficientService.messageRequest(body: request)
        
        XCTAssertGreaterThan(response.content.count, 0)
        
        // Check if tool was used
        let hasToolUse = response.content.contains { content in
            if case .toolUse = content { return true }
            return false
        }
        
        if hasToolUse {
            print("✅ Tool use detected in response")
        }
        
        print("✅ Real API Token Efficient Tools Test Passed")
    }
    
    // MARK: - Error Handling Tests
    
    func testRealAPIRateLimit() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        // Make multiple rapid requests to potentially trigger rate limiting
        var requests: [Task<Void, Never>] = []
        
        for i in 0..<5 {
            let task = Task {
                let request = AnthropicMessageRequestBody(
                    maxTokens: 50,
                    messages: [
                        AnthropicInputMessage(
                            content: [.text("Quick test \(i)")],
                            role: .user
                        )
                    ],
                    model: "claude-3-7-sonnet-20250219"
                )
                
                do {
                    _ = try await service.messageRequest(body: request)
                    print("Request \(i) succeeded")
                } catch let error as LLMError {
                    switch error {
                    case .rateLimitExceeded:
                        print("Request \(i) hit rate limit (expected)")
                    case .underlying(let underlyingError):
                        if let llmError = underlyingError as? LLMError,
                           case .rateLimitExceeded = llmError {
                            print("Request \(i) hit rate limit (underlying)")
                        } else {
                            print("Request \(i) failed with: \(error)")
                        }
                    default:
                        print("Request \(i) failed with: \(error)")
                    }
                } catch {
                    print("Request \(i) failed with unexpected error: \(error)")
                }
            }
            requests.append(task)
        }
        
        // Wait for all requests to complete
        for task in requests {
            await task.value
        }
        
        print("✅ Real API Rate Limit Test Completed")
    }
    
    func testRealAPIInvalidModel() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 50,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello")],
                    role: .user
                )
            ],
            model: "invalid-model-name"
        )
        
        do {
            _ = try await service.messageRequest(body: request)
            XCTFail("Expected error with invalid model")
        } catch let error as LLMError {
            switch error {
            case .invalidRequest(let message):
                XCTAssertTrue(message.contains("model") || message.contains("invalid"))
            case .networkError(let code, _):
                XCTAssertEqual(code, 400) // Bad request
            default:
                print("Got error: \(error) (acceptable)")
            }
        } catch {
            XCTFail("Expected LLMError, got \(error)")
        }
        
        print("✅ Real API Invalid Model Test Passed")
    }
    
    // MARK: - Performance Tests
    
    func testRealAPIPerformance() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Say hello")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219"
        )
        
        let startTime = Date()
        let response = try await service.messageRequest(body: request)
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertGreaterThan(response.content.count, 0)
        XCTAssertLessThan(duration, 10.0) // Should complete within 10 seconds
        
        print("✅ Real API Performance Test Passed")
        print("Response time: \(String(format: "%.2f", duration)) seconds")
        print("Input tokens: \(response.usage.inputTokens)")
        print("Output tokens: \(response.usage.outputTokens)")
    }
    
    func testRealAPIConcurrentRequests() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        let requestCount = 3
        var tasks: [Task<AnthropicMessageResponseBody, Error>] = []
        
        for i in 0..<requestCount {
            let task = Task {
                let request = AnthropicMessageRequestBody(
                    maxTokens: 50,
                    messages: [
                        AnthropicInputMessage(
                            content: [.text("Concurrent test \(i)")],
                            role: .user
                        )
                    ],
                    model: "claude-3-7-sonnet-20250219"
                )
                
                return try await service.messageRequest(body: request)
            }
            tasks.append(task)
        }
        
        let startTime = Date()
        let responses = try await withThrowingTaskGroup(of: AnthropicMessageResponseBody.self) { group in
            for task in tasks {
                group.addTask { try await task.value }
            }
            
            var results: [AnthropicMessageResponseBody] = []
            for try await response in group {
                results.append(response)
            }
            return results
        }
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertEqual(responses.count, requestCount)
        
        for (index, response) in responses.enumerated() {
            XCTAssertFalse(response.id.isEmpty)
            XCTAssertGreaterThan(response.content.count, 0)
            print("Response \(index): \(response.id)")
        }
        
        print("✅ Real API Concurrent Requests Test Passed")
        print("Completed \(requestCount) concurrent requests in \(String(format: "%.2f", duration)) seconds")
    }
    
    // MARK: - Structured Output Tests
    
    func testRealAPIGenerateObjectBasic() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        // Simple schema model with only the fields we explicitly request
        struct SimpleProduct: Codable {
            let name: String
            let price: Double
            let category: String
            let stockStatus: String
        }
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 200,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Generate a simple laptop product with ONLY these fields: name (string), price (number), category (string), stockStatus (string). Keep it simple and don't add extra fields.")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            system: "You are a helpful assistant. Generate ONLY a simple JSON object with exactly these 4 fields: name, price, category, stockStatus. Do not add any other fields.",
            temperature: 0.1,
            responseFormat: .jsonObject
        )
        
        let product: SimpleProduct = try await service.generateObject(request: request)
        
        // Validate the generated product
        XCTAssertFalse(product.name.isEmpty, "Product name should not be empty")
        XCTAssertGreaterThan(product.price, 0, "Product price should be positive")
        XCTAssertFalse(product.category.isEmpty, "Product category should not be empty")
        
        print("✅ Real API Generate Object Basic Test Passed")
        print("Generated Product:")
        print("  📦 Name: \(product.name)")
        print("  💰 Price: $\(product.price)")
        print("  🏷️  Category: \(product.category)")
        print("  📊 Stock Status: \(product.stockStatus)")
    }
    
    func testRealAPIGenerateObjectWithSchema() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        // Test with a simple structured model
        struct UserProfile: Codable {
            let id: Int
            let name: String
            let email: String
            let age: Int
        }
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 300,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Create a user profile for a software developer in their 30s")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            system: "Generate realistic user profile data with id, name, email, and age fields in JSON format.",
            temperature: 0.2,
            responseFormat: .jsonObject
        )
        
        let userProfile: UserProfile = try await service.generateObject(request: request)
        
        // Validate the generated user profile
        XCTAssertGreaterThan(userProfile.id, 0, "User ID should be positive")
        XCTAssertFalse(userProfile.name.isEmpty, "User name should not be empty")
        XCTAssertTrue(userProfile.email.contains("@"), "Email should contain @ symbol")
        XCTAssertGreaterThanOrEqual(userProfile.age, 18, "Age should be at least 18")
        XCTAssertLessThanOrEqual(userProfile.age, 120, "Age should be reasonable")
        
        print("✅ Real API Generate Object with Schema Test Passed")
        print("Generated User Profile:")
        print("  🆔 ID: \(userProfile.id)")
        print("  👤 Name: \(userProfile.name)")
        print("  📧 Email: \(userProfile.email)")
        print("  🎂 Age: \(userProfile.age)")
    }
    
    func testRealAPIGenerateObjectComplexStructure() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        // Test with nested structures
        struct Address: Codable {
            let street: String
            let city: String
            let country: String
            let zipCode: String
        }
        
        struct CompanyWrapper: Codable {
            let company: Company?
            let name: String?
            let industry: String?
            let employees: Int?
            let founded: Int?
            let headquarters: Address?
            
            // Extract the actual company data regardless of structure
            var actualCompany: Company {
                if let company = company {
                    return company
                } else {
                    return Company(
                        name: name ?? "Unknown",
                        industry: industry ?? "Unknown",
                        employees: employees ?? 0,
                        founded: founded ?? 2000,
                        headquarters: headquarters ?? Address(street: "", city: "", country: "", zipCode: "")
                    )
                }
            }
        }
        
        struct Company: Codable {
            let name: String
            let industry: String
            let employees: Int
            let founded: Int
            let headquarters: Address
        }
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 400,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Create a technology company profile with headquarters address. Make it realistic and detailed.")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            system: "Generate realistic company data with nested address information in JSON format.",
            temperature: 0.3,
            responseFormat: .jsonObject
        )
        
        let companyWrapper: CompanyWrapper = try await service.generateObject(request: request)
        let company = companyWrapper.actualCompany
        
        // Validate the generated company
        XCTAssertFalse(company.name.isEmpty, "Company name should not be empty")
        XCTAssertFalse(company.industry.isEmpty, "Industry should not be empty")
        XCTAssertGreaterThan(company.employees, 0, "Employee count should be positive")
        XCTAssertGreaterThan(company.founded, 1800, "Founded year should be reasonable")
        
        // Validate nested address
        XCTAssertFalse(company.headquarters.street.isEmpty, "Street should not be empty")
        XCTAssertFalse(company.headquarters.city.isEmpty, "City should not be empty")
        XCTAssertFalse(company.headquarters.country.isEmpty, "Country should not be empty")
        XCTAssertFalse(company.headquarters.zipCode.isEmpty, "Zip code should not be empty")
        
        print("✅ Real API Generate Object Complex Structure Test Passed")
        print("Generated Company:")
        print("  🏢 Name: \(company.name)")
        print("  🏭 Industry: \(company.industry)")
        print("  👥 Employees: \(company.employees)")
        print("  📅 Founded: \(company.founded)")
        print("  📍 HQ: \(company.headquarters.street), \(company.headquarters.city), \(company.headquarters.country)")
    }
    
    func testRealAPIGenerateObjectErrorHandling() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        // Test with intentionally difficult parsing scenario
        struct StrictSchema: Codable {
            let requiredField: String
            let numericField: Int
        }
        
        let request = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Respond with completely invalid JSON that cannot be parsed")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            system: "You must respond with valid JSON only.",
            temperature: 0.1,
            responseFormat: .jsonObject
        )
        
        do {
            let _: StrictSchema = try await service.generateObject(request: request)
            // If we get here, Claude managed to produce valid JSON despite the conflicting instruction
            print("✅ Claude produced valid JSON despite conflicting instructions")
        } catch let error as LLMError {
            // Expected to fail with parsing error
            switch error {
            case .parsingError(let message):
                XCTAssertTrue(message.contains("decode") || message.contains("JSON"))
                print("✅ Real API Generate Object Error Handling Test Passed")
                print("Got expected parsing error: \(message)")
            default:
                XCTFail("Expected parsing error, got \(error)")
            }
        } catch {
            XCTFail("Expected LLMError, got \(error)")
        }
    }
    
    // MARK: - Integration Tests
    
    func testRealAPIFullWorkflow() async throws {
        try XCTSkipUnless(shouldUseRealAPI(), "Real API tests disabled")
        
        // Test a complete workflow with multiple features
        
        // 1. Basic conversation
        let conversationRequest = AnthropicMessageRequestBody(
            maxTokens: 150,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Hello! I'm testing the AnthropicService. Can you help me understand how it works?")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219",
            system: "You are a helpful AI assistant built with AnthropicService.",
            temperature: 0.2
        )
        
        let conversationResponse = try await service.messageRequest(body: conversationRequest)
        
        XCTAssertFalse(conversationResponse.id.isEmpty)
        XCTAssertGreaterThan(conversationResponse.content.count, 0)
        
        // 2. Streaming test
        let streamRequest = AnthropicMessageRequestBody(
            maxTokens: 100,
            messages: [
                AnthropicInputMessage(
                    content: [.text("Count from 1 to 3")],
                    role: .user
                )
            ],
            model: "claude-3-7-sonnet-20250219"
        )
        
        var streamChunks = 0
        let stream = try await service.streamingMessageRequest(body: streamRequest)
        
        for try await _ in stream {
            streamChunks += 1
            if streamChunks > 50 { break } // Prevent infinite loops
        }
        
        XCTAssertGreaterThan(streamChunks, 0)
        
        print("✅ Real API Full Workflow Test Passed")
        print("Conversation response ID: \(conversationResponse.id)")
        print("Streaming chunks received: \(streamChunks)")
        print("Total usage - Input: \(conversationResponse.usage.inputTokens), Output: \(conversationResponse.usage.outputTokens)")
    }
}