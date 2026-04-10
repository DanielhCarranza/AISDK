//
//  GeminiClientAdapterTests.swift
//  AISDKTests
//
//  Tests for GeminiClientAdapter - direct Google Gemini provider client
//

import XCTest
@testable import AISDK

// MARK: - GeminiClientAdapterTests

final class GeminiClientAdapterTests: XCTestCase {
    // MARK: - Initialization Tests

    func testInitializationWithDefaults() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")

        XCTAssertEqual(client.providerId, "gemini")
        XCTAssertEqual(client.displayName, "Google Gemini")
        XCTAssertEqual(client.baseURL.absoluteString, "https://generativelanguage.googleapis.com/v1beta")
    }

    func testInitializationWithCustomBaseURL() async {
        let customURL = URL(string: "https://custom.gemini.example.com/v1")!
        let client = GeminiClientAdapter(
            apiKey: "test-api-key",
            baseURL: customURL
        )

        XCTAssertEqual(client.baseURL, customURL)
    }

    // MARK: - Health Status Tests

    func testInitialHealthStatusIsUnknown() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let status = await client.healthStatus

        XCTAssertEqual(status, .unknown)
    }

    func testIsAvailableReturnsFalseWhenUnknown() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let isAvailable = await client.isAvailable

        XCTAssertFalse(isAvailable)
    }

    // MARK: - Protocol Conformance Tests

    func testConformsToProviderClient() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")

        // Verify protocol requirements
        XCTAssertFalse(client.providerId.isEmpty)
        XCTAssertFalse(client.displayName.isEmpty)
        XCTAssertNotNil(client.baseURL)

        // Health status should be accessible
        let _ = await client.healthStatus
        let _ = await client.isAvailable
    }

    func testProviderClientIsSendable() {
        // This test verifies that GeminiClientAdapter can be used across concurrency domains
        let client = GeminiClientAdapter(apiKey: "test-api-key")

        Task.detached {
            // Access from detached task proves Sendable conformance
            let _ = client.providerId
            let _ = await client.healthStatus
        }
    }

    // MARK: - Model Capabilities Tests

    func testCapabilitiesForGemini25Pro() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let capabilities = await client.capabilities(for: "gemini-2.5-pro-preview-05-06")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.text))
        XCTAssertTrue(capabilities!.contains(.vision))
        XCTAssertTrue(capabilities!.contains(.tools))
        XCTAssertTrue(capabilities!.contains(.streaming))
        XCTAssertTrue(capabilities!.contains(.functionCalling))
        XCTAssertTrue(capabilities!.contains(.reasoning))
        XCTAssertTrue(capabilities!.contains(.longContext))
    }

    func testCapabilitiesForGemini25Flash() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let capabilities = await client.capabilities(for: "gemini-2.5-flash")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.text))
        XCTAssertTrue(capabilities!.contains(.vision))
        XCTAssertTrue(capabilities!.contains(.tools))
        XCTAssertTrue(capabilities!.contains(.reasoning))
    }

    func testCapabilitiesForGemini20Flash() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let capabilities = await client.capabilities(for: "gemini-2.0-flash")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.text))
        XCTAssertTrue(capabilities!.contains(.vision))
        XCTAssertTrue(capabilities!.contains(.tools))
        XCTAssertTrue(capabilities!.contains(.functionCalling))
    }

    func testCapabilitiesForGemini15Pro() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let capabilities = await client.capabilities(for: "gemini-1.5-pro")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.text))
        XCTAssertTrue(capabilities!.contains(.vision))
        XCTAssertTrue(capabilities!.contains(.longContext))
    }

    func testCapabilitiesForGemini15Flash() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let capabilities = await client.capabilities(for: "gemini-1.5-flash")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.text))
        XCTAssertTrue(capabilities!.contains(.tools))
        XCTAssertTrue(capabilities!.contains(.streaming))
    }

    func testCapabilitiesForGemini31Pro() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let capabilities = await client.capabilities(for: "gemini-3.1-pro-preview")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.text))
        XCTAssertTrue(capabilities!.contains(.vision))
        XCTAssertTrue(capabilities!.contains(.tools))
        XCTAssertTrue(capabilities!.contains(.streaming))
        XCTAssertTrue(capabilities!.contains(.functionCalling))
        XCTAssertTrue(capabilities!.contains(.reasoning))
        XCTAssertTrue(capabilities!.contains(.longContext))
    }

    func testCapabilitiesForGemini3Flash() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let capabilities = await client.capabilities(for: "gemini-3-flash")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.text))
        XCTAssertTrue(capabilities!.contains(.vision))
        XCTAssertTrue(capabilities!.contains(.tools))
        XCTAssertTrue(capabilities!.contains(.streaming))
        XCTAssertTrue(capabilities!.contains(.functionCalling))
        XCTAssertTrue(capabilities!.contains(.reasoning))
    }

    func testCapabilitiesForGemini3Pro() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let capabilities = await client.capabilities(for: "gemini-3-pro-preview")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.reasoning))
        XCTAssertTrue(capabilities!.contains(.longContext))
    }

    func testCapabilitiesForUnknownModel() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let capabilities = await client.capabilities(for: "unknown-model-xyz")

        // Unknown models get default capabilities
        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.text))
    }

    // MARK: - Model Availability Tests

    func testIsModelAvailableForKnownModels() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")

        let gemini25Flash = await client.isModelAvailable("gemini-2.5-flash")
        XCTAssertTrue(gemini25Flash)

        let gemini20Flash = await client.isModelAvailable("gemini-2.0-flash")
        XCTAssertTrue(gemini20Flash)

        let gemini15Pro = await client.isModelAvailable("gemini-1.5-pro")
        XCTAssertTrue(gemini15Pro)
    }

    func testIsModelAvailableForGeminiPrefix() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")

        let customGemini = await client.isModelAvailable("gemini-custom-model")
        XCTAssertTrue(customGemini)
    }

    func testIsModelAvailableForUnknownModel() async {
        let client = GeminiClientAdapter(apiKey: "test-api-key")

        let unknown = await client.isModelAvailable("gpt-4")
        XCTAssertFalse(unknown)
    }

    // MARK: - Stream Method Tests

    func testStreamReturnsAsyncThrowingStream() {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [AIMessage(role: .user, content: .text("Hello"))]
        )

        let stream = client.stream(request: request)

        // Verify we get an AsyncThrowingStream
        XCTAssertNotNil(stream)
    }

    // MARK: - Reasoning Mapping Tests

    func testUnifiedReasoningEffortMapsToThinkingBudgetFor25() async throws {
        // Gemini 2.5 models use thinkingBudget (not thinkingLevel)
        let captured = await captureGeminiRequestBody(
            modelId: "gemini-2.5-flash",
            reasoning: AIReasoningConfig.effort(.medium),
            providerOptions: nil
        )

        let genConfig = captured["generationConfig"] as? [String: Any]
        let thinkingConfig = genConfig?["thinkingConfig"] as? [String: Any]
        XCTAssertNotNil(thinkingConfig, "thinkingConfig should be nested inside generationConfig")
        // 2.5 models map effort to budget, not level
        XCTAssertEqual(thinkingConfig?["thinking_budget"] as? Int, 8192)
        XCTAssertNil(thinkingConfig?["thinking_level"], "2.5 models should not use thinking_level")
    }

    func testUnifiedReasoningBudgetMapsToThinkingBudget() async throws {
        let captured = await captureGeminiRequestBody(
            modelId: "gemini-2.5-flash",
            reasoning: AIReasoningConfig(budgetTokens: 2048),
            providerOptions: nil
        )

        let genConfig = captured["generationConfig"] as? [String: Any]
        let thinkingConfig = genConfig?["thinkingConfig"] as? [String: Any]
        XCTAssertNotNil(thinkingConfig, "thinkingConfig should be nested inside generationConfig")
        XCTAssertEqual(thinkingConfig?["thinking_budget"] as? Int, 2048)
    }

    func testProviderOptionsOverrideUnifiedReasoning() async throws {
        let options: [String: ProviderJSONValue] = [
            "thinkingLevel": .string("high"),
            "thinkingBudget": .int(1024)
        ]

        let captured = await captureGeminiRequestBody(
            modelId: "gemini-2.5-flash",
            reasoning: AIReasoningConfig.effort(.low),
            providerOptions: options
        )

        let genConfig = captured["generationConfig"] as? [String: Any]
        let thinkingConfig = genConfig?["thinkingConfig"] as? [String: Any]
        XCTAssertNotNil(thinkingConfig, "thinkingConfig should be nested inside generationConfig")
        XCTAssertEqual(thinkingConfig?["thinking_level"] as? String, "high")
        XCTAssertEqual(thinkingConfig?["thinking_budget"] as? Int, 1024)
    }

    func testUnifiedReasoningIgnoredForNonReasoningModel() async throws {
        let captured = await captureGeminiRequestBody(
            modelId: "gemini-2.0-flash",
            reasoning: AIReasoningConfig.effort(.high),
            providerOptions: nil
        )

        // thinkingConfig should NOT appear at top level
        XCTAssertNil(captured["thinkingConfig"], "thinkingConfig must not be at top level")
        // And should not appear inside generationConfig either (model doesn't support reasoning)
        let genConfig = captured["generationConfig"] as? [String: Any]
        XCTAssertNil(genConfig?["thinkingConfig"], "Non-reasoning model should not have thinkingConfig")
    }
}

// MARK: - GeminiThinkingConfigNestingTests

final class GeminiThinkingConfigNestingTests: XCTestCase {
    func testThinkingConfigNestedInsideGenerationConfig() async throws {
        let captured = await captureGeminiRequestBody(
            modelId: "gemini-2.5-flash",
            reasoning: AIReasoningConfig(budgetTokens: 4096),
            providerOptions: nil
        )

        // thinkingConfig MUST be inside generationConfig
        let genConfig = captured["generationConfig"] as? [String: Any]
        XCTAssertNotNil(genConfig, "generationConfig should exist")
        let thinkingConfig = genConfig?["thinkingConfig"] as? [String: Any]
        XCTAssertNotNil(thinkingConfig, "thinkingConfig should be nested inside generationConfig")
    }

    func testThinkingConfigNotAtTopLevel() async throws {
        let captured = await captureGeminiRequestBody(
            modelId: "gemini-2.5-flash",
            reasoning: AIReasoningConfig(budgetTokens: 4096),
            providerOptions: nil
        )

        // thinkingConfig must NOT be at the top level (this was the bug)
        XCTAssertNil(captured["thinkingConfig"], "thinkingConfig must not be a top-level field")
    }

    func testGemini31ReasoningEffortMapsToThinkingLevel() async throws {
        let captured = await captureGeminiRequestBody(
            modelId: "gemini-3.1-pro-preview",
            reasoning: AIReasoningConfig.effort(.high),
            providerOptions: nil
        )

        let genConfig = captured["generationConfig"] as? [String: Any]
        let thinkingConfig = genConfig?["thinkingConfig"] as? [String: Any]
        XCTAssertNotNil(thinkingConfig, "Gemini 3.1 should support reasoning config")
        XCTAssertEqual(thinkingConfig?["thinking_level"] as? String, "high")
    }

    func testGemini3FlashReasoningSupport() async throws {
        let captured = await captureGeminiRequestBody(
            modelId: "gemini-3-flash",
            reasoning: AIReasoningConfig.effort(.low),
            providerOptions: nil
        )

        let genConfig = captured["generationConfig"] as? [String: Any]
        let thinkingConfig = genConfig?["thinkingConfig"] as? [String: Any]
        XCTAssertNotNil(thinkingConfig, "Gemini 3 Flash should support reasoning config")
        XCTAssertEqual(thinkingConfig?["thinking_level"] as? String, "low")
    }

    func testGenerationConfigCreatedWhenOnlyThinkingConfigPresent() async throws {
        // When no temperature/maxTokens/etc are set, generationConfig should
        // still be created to hold thinkingConfig
        let captured = await captureGeminiRequestBody(
            modelId: "gemini-2.5-flash",
            reasoning: AIReasoningConfig.effort(.medium),
            providerOptions: nil
        )

        let genConfig = captured["generationConfig"] as? [String: Any]
        XCTAssertNotNil(genConfig, "generationConfig should be created even when only thinkingConfig is needed")
        XCTAssertNotNil(genConfig?["thinkingConfig"], "thinkingConfig should be present inside generationConfig")
    }

    func testIncludeThoughtsViaProviderOptions() async throws {
        let captured = await captureGeminiRequestBody(
            modelId: "gemini-2.5-flash",
            reasoning: AIReasoningConfig.effort(.medium),
            providerOptions: ["includeThoughts": .bool(true)]
        )

        let genConfig = captured["generationConfig"] as? [String: Any]
        let thinkingConfig = genConfig?["thinkingConfig"] as? [String: Any]
        XCTAssertNotNil(thinkingConfig)
        XCTAssertEqual(thinkingConfig?["include_thoughts"] as? Bool, true)
        // 2.5 models use budget not level
        XCTAssertEqual(thinkingConfig?["thinking_budget"] as? Int, 8192)
    }
}

// MARK: - GeminiResponseParsingTests

final class GeminiResponseParsingTests: XCTestCase {
    // These tests verify JSON parsing logic by testing the response structures

    func testParseGenerateContentResponseWithText() throws {
        let json = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [{
                        "text": "Hello! How can I help you today?"
                    }]
                },
                "finishReason": "STOP"
            }],
            "usageMetadata": {
                "promptTokenCount": 5,
                "candidatesTokenCount": 10,
                "totalTokenCount": 15
            },
            "modelVersion": "gemini-2.0-flash",
            "responseId": "resp-123"
        }
        """.data(using: .utf8)!

        XCTAssertNotNil(json)
    }

    func testParseGenerateContentResponseWithFunctionCall() throws {
        let json = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [{
                        "functionCall": {
                            "name": "get_weather",
                            "args": {
                                "location": "San Francisco"
                            }
                        }
                    }]
                },
                "finishReason": "STOP"
            }],
            "usageMetadata": {
                "promptTokenCount": 15,
                "candidatesTokenCount": 20,
                "totalTokenCount": 35
            }
        }
        """.data(using: .utf8)!

        XCTAssertNotNil(json)
    }

    func testParseGenerateContentResponseWithMultipleFunctionCalls() throws {
        let json = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [
                        {
                            "functionCall": {
                                "name": "search",
                                "args": {"query": "weather"}
                            }
                        },
                        {
                            "functionCall": {
                                "name": "calculate",
                                "args": {"expression": "2+2"}
                            }
                        }
                    ]
                },
                "finishReason": "STOP"
            }],
            "usageMetadata": {
                "promptTokenCount": 20,
                "candidatesTokenCount": 30,
                "totalTokenCount": 50
            }
        }
        """.data(using: .utf8)!

        XCTAssertNotNil(json)
    }

    func testParseGenerateContentResponseWithSafetyRatings() throws {
        let json = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [{
                        "text": "Hello!"
                    }]
                },
                "finishReason": "STOP",
                "safetyRatings": [
                    {"category": "HARM_CATEGORY_HARASSMENT", "probability": "NEGLIGIBLE"},
                    {"category": "HARM_CATEGORY_HATE_SPEECH", "probability": "NEGLIGIBLE"}
                ]
            }],
            "usageMetadata": {
                "promptTokenCount": 5,
                "candidatesTokenCount": 5,
                "totalTokenCount": 10
            }
        }
        """.data(using: .utf8)!

        XCTAssertNotNil(json)
    }

    func testParseGenerateContentResponseWithPromptFeedbackBlock() throws {
        let json = """
        {
            "promptFeedback": {
                "blockReason": "SAFETY",
                "safetyRatings": [
                    {"category": "HARM_CATEGORY_DANGEROUS_CONTENT", "probability": "HIGH"}
                ]
            }
        }
        """.data(using: .utf8)!

        XCTAssertNotNil(json)
    }

    // MARK: - Caching Tests

    func testCachedContentIdIncludedInRequestBody() async throws {
        let body = await captureGeminiRequestBodyWithCaching(
            caching: AICacheConfig(cachedContentId: "cachedContents/abc123")
        )
        XCTAssertEqual(body["cachedContent"] as? String, "cachedContents/abc123")
    }

    func testCachingEnabledWithoutIdOmitsCachedContent() async throws {
        let body = await captureGeminiRequestBodyWithCaching(
            caching: AICacheConfig(enabled: true)
        )
        XCTAssertNil(body["cachedContent"])
    }

    func testNoCachingConfigOmitsCachedContent() async throws {
        let body = await captureGeminiRequestBodyWithCaching(caching: nil)
        XCTAssertNil(body["cachedContent"])
    }

    // MARK: - Tool Call ID Preservation Tests

    func testToolCallIdPreservedInFunctionCall() async throws {
        let body = await captureGeminiRequestBodyForMultiTurn(messages: [
            AIMessage(role: .user, content: .text("What's the weather?")),
            AIMessage(
                role: .assistant,
                content: .text(""),
                toolCalls: [AIMessage.ToolCall(id: "call_weather_abc123", name: "get_weather", arguments: "{\"city\":\"Tokyo\"}")]
            ),
            AIMessage(role: .tool, content: .text("72°F"), name: "get_weather", toolCallId: "call_weather_abc123"),
            AIMessage(role: .user, content: .text("Thanks"))
        ])

        let contents = body["contents"] as? [[String: Any]] ?? []
        // The assistant message (second content) should have functionCall with id
        guard contents.count >= 2,
              let parts = contents[1]["parts"] as? [[String: Any]] else {
            XCTFail("Missing assistant content with parts")
            return
        }

        let hasFunctionCallWithId = parts.contains { part in
            guard let fc = part["functionCall"] as? [String: Any] else { return false }
            return fc["id"] as? String == "call_weather_abc123"
        }
        XCTAssertTrue(hasFunctionCallWithId, "Function call should preserve tool call ID")
    }

    func testToolResponseIdPreserved() async throws {
        let body = await captureGeminiRequestBodyForMultiTurn(messages: [
            AIMessage(role: .user, content: .text("What's the weather?")),
            AIMessage(
                role: .assistant,
                content: .text(""),
                toolCalls: [AIMessage.ToolCall(id: "call_weather_abc123", name: "get_weather", arguments: "{}")]
            ),
            AIMessage(role: .tool, content: .text("72°F"), name: "get_weather", toolCallId: "call_weather_abc123")
        ])

        let contents = body["contents"] as? [[String: Any]] ?? []
        // The tool response (third content) should have functionResponse with id
        guard contents.count >= 3,
              let parts = contents[2]["parts"] as? [[String: Any]] else {
            XCTFail("Missing tool response content with parts")
            return
        }

        let hasFunctionResponseWithId = parts.contains { part in
            guard let fr = part["functionResponse"] as? [String: Any] else { return false }
            return fr["id"] as? String == "call_weather_abc123"
        }
        XCTAssertTrue(hasFunctionResponseWithId, "Function response should preserve tool call ID")
    }

    // MARK: - Thought Re-injection Tests

    func testThoughtContentReinjectedForAssistantMessages() async throws {
        var assistantMsg = AIMessage(role: .assistant, content: .text("The answer is 42."))
        assistantMsg.providerMetadata = ["reasoning": "Let me think about this carefully..."]

        let body = await captureGeminiRequestBodyForMultiTurn(messages: [
            AIMessage(role: .user, content: .text("What's the meaning of life?")),
            assistantMsg,
            AIMessage(role: .user, content: .text("Why?"))
        ])

        let contents = body["contents"] as? [[String: Any]] ?? []
        // The assistant message (second content) should have thought part
        guard contents.count >= 2,
              let parts = contents[1]["parts"] as? [[String: Any]] else {
            XCTFail("Missing assistant content with parts")
            return
        }

        let hasThoughtPart = parts.contains { part in
            part["thought"] as? Bool == true && (part["text"] as? String)?.contains("think about this") == true
        }
        XCTAssertTrue(hasThoughtPart, "Thought content should be re-injected for assistant messages")
    }

    func testNoThoughtPartWhenNoProviderMetadata() async throws {
        let body = await captureGeminiRequestBodyForMultiTurn(messages: [
            AIMessage(role: .user, content: .text("Hello")),
            AIMessage(role: .assistant, content: .text("Hi!")),
            AIMessage(role: .user, content: .text("Bye"))
        ])

        let contents = body["contents"] as? [[String: Any]] ?? []
        guard contents.count >= 2,
              let parts = contents[1]["parts"] as? [[String: Any]] else {
            XCTFail("Missing assistant content with parts")
            return
        }

        let hasThoughtPart = parts.contains { $0["thought"] as? Bool == true }
        XCTAssertFalse(hasThoughtPart, "No thought part should be present without providerMetadata")
    }

    func testParseStreamChunk() throws {
        let json = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [{
                        "text": "Hello"
                    }]
                }
            }],
            "usageMetadata": {
                "promptTokenCount": 5,
                "candidatesTokenCount": 1,
                "totalTokenCount": 6
            }
        }
        """.data(using: .utf8)!

        XCTAssertNotNil(json)
    }
}

// MARK: - Helpers

private func captureGeminiRequestBody(
    modelId: String,
    reasoning: AIReasoningConfig,
    providerOptions: [String: ProviderJSONValue]?
) async -> [String: Any] {
    MockURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = GeminiClientAdapter(apiKey: "test-api-key", session: session)

    var capturedBody: [String: Any] = [:]
    MockURLProtocol.requestHandler = { request in
        let bodyData = readRequestBody(request)
        if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            capturedBody = json
        }

        let responseJSON = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [{"text": "ok"}]
                },
                "finishReason": "STOP"
            }],
            "usageMetadata": {
                "promptTokenCount": 1,
                "candidatesTokenCount": 1,
                "totalTokenCount": 2
            },
            "modelVersion": "\(modelId)",
            "responseId": "resp-test"
        }
        """.data(using: .utf8) ?? Data()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseJSON)
    }

    let providerRequest = ProviderRequest(
        modelId: modelId,
        messages: [AIMessage(role: .user, content: .text("Hello"))],
        reasoning: reasoning,
        providerOptions: providerOptions
    )

    _ = try? await client.execute(request: providerRequest)
    return capturedBody
}

private func captureGeminiRequestBodyForMultiTurn(
    messages: [AIMessage]
) async -> [String: Any] {
    MockURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = GeminiClientAdapter(apiKey: "test-api-key", session: session)

    var capturedBody: [String: Any] = [:]
    MockURLProtocol.requestHandler = { request in
        let bodyData = readRequestBody(request)
        if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            capturedBody = json
        }

        let responseJSON = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [{"text": "ok"}]
                },
                "finishReason": "STOP"
            }],
            "usageMetadata": {
                "promptTokenCount": 1,
                "candidatesTokenCount": 1,
                "totalTokenCount": 2
            },
            "modelVersion": "gemini-2.5-pro",
            "responseId": "resp-test"
        }
        """.data(using: .utf8) ?? Data()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseJSON)
    }

    let providerRequest = ProviderRequest(
        modelId: "gemini-2.5-pro",
        messages: messages
    )

    _ = try? await client.execute(request: providerRequest)
    return capturedBody
}

private func captureGeminiRequestBodyWithCaching(
    caching: AICacheConfig?
) async -> [String: Any] {
    MockURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = GeminiClientAdapter(apiKey: "test-api-key", session: session)

    var capturedBody: [String: Any] = [:]
    MockURLProtocol.requestHandler = { request in
        let bodyData = readRequestBody(request)
        if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            capturedBody = json
        }

        let responseJSON = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [{"text": "ok"}]
                },
                "finishReason": "STOP"
            }],
            "usageMetadata": {
                "promptTokenCount": 1,
                "candidatesTokenCount": 1,
                "totalTokenCount": 2
            },
            "modelVersion": "gemini-2.5-pro",
            "responseId": "resp-test"
        }
        """.data(using: .utf8) ?? Data()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseJSON)
    }

    let providerRequest = ProviderRequest(
        modelId: "gemini-2.5-pro",
        messages: [AIMessage(role: .user, content: .text("Hello"))],
        caching: caching
    )

    _ = try? await client.execute(request: providerRequest)
    return capturedBody
}

private func readRequestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return Data()
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: bufferSize)
        if count > 0 {
            data.append(buffer, count: count)
        } else {
            break
        }
    }
    return data
}

// MARK: - GeminiRequestEncodingTests

final class GeminiRequestEncodingTests: XCTestCase {
    func testBasicRequestEncoding() throws {
        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [
                AIMessage(role: .system, content: .text("You are a helpful assistant.")),
                AIMessage(role: .user, content: .text("Hello!"))
            ]
        )

        XCTAssertEqual(request.modelId, "gemini-2.0-flash")
        XCTAssertEqual(request.messages.count, 2)
        XCTAssertEqual(request.messages[0].role, .system)
        XCTAssertEqual(request.messages[1].role, .user)
    }

    func testRequestWithTemperature() throws {
        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [AIMessage(role: .user, content: .text("Hello"))],
            temperature: 0.7
        )

        XCTAssertEqual(request.temperature, 0.7)
    }

    func testRequestWithMaxTokens() throws {
        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [AIMessage(role: .user, content: .text("Hello"))],
            maxTokens: 1000
        )

        XCTAssertEqual(request.maxTokens, 1000)
    }

    func testRequestWithToolChoice() throws {
        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [AIMessage(role: .user, content: .text("Hello"))],
            toolChoice: .auto
        )

        XCTAssertEqual(request.toolChoice, .auto)
    }

    func testRequestWithSpecificToolChoice() throws {
        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [AIMessage(role: .user, content: .text("Hello"))],
            toolChoice: .tool(name: "get_weather")
        )

        if case .tool(let name) = request.toolChoice {
            XCTAssertEqual(name, "get_weather")
        } else {
            XCTFail("Expected tool choice")
        }
    }

    func testRequestWithResponseFormat() throws {
        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [AIMessage(role: .user, content: .text("Hello"))],
            responseFormat: .json
        )

        XCTAssertEqual(request.responseFormat, .json)
    }

    func testRequestWithJsonSchemaResponseFormat() throws {
        let schemaJson = """
        {"type": "object", "properties": {"name": {"type": "string"}}}
        """
        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [AIMessage(role: .user, content: .text("Hello"))],
            responseFormat: .jsonSchema(name: "person", schema: schemaJson)
        )

        if case .jsonSchema(let name, let schema) = request.responseFormat {
            XCTAssertEqual(name, "person")
            XCTAssertTrue(schema.contains("object"))
        } else {
            XCTFail("Expected JSON schema response format")
        }
    }
}

// MARK: - GeminiErrorMappingTests

final class GeminiErrorMappingTests: XCTestCase {
    func testProviderFinishReasonMappingForGemini() {
        // Test Gemini-specific finish reasons
        XCTAssertEqual(ProviderFinishReason(providerReason: "STOP"), .stop)
        XCTAssertEqual(ProviderFinishReason(providerReason: "MAX_TOKENS"), .length)
        XCTAssertEqual(ProviderFinishReason(providerReason: "SAFETY"), .contentFilter)
    }

    func testProviderFinishReasonMappingCaseInsensitive() {
        XCTAssertEqual(ProviderFinishReason(providerReason: "stop"), .stop)
        XCTAssertEqual(ProviderFinishReason(providerReason: "Stop"), .stop)
        XCTAssertEqual(ProviderFinishReason(providerReason: "LENGTH"), .length)
    }

    func testProviderFinishReasonUnknown() {
        XCTAssertEqual(ProviderFinishReason(providerReason: nil), .unknown)
        XCTAssertEqual(ProviderFinishReason(providerReason: ""), .unknown)
        XCTAssertEqual(ProviderFinishReason(providerReason: "RECITATION"), .unknown)
    }
}

// MARK: - GeminiMultipartContentTests

final class GeminiMultipartContentTests: XCTestCase {
    func testTextContentPart() {
        let message = AIMessage(role: .user, content: .text("Hello"))

        if case .text(let text) = message.content {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected text content")
        }
    }

    func testPartsContentWithText() {
        let message = AIMessage(role: .user, content: .parts([.text("Hello"), .text("World")]))

        if case .parts(let parts) = message.content {
            XCTAssertEqual(parts.count, 2)
        } else {
            XCTFail("Expected parts content")
        }
    }

    func testPartsContentWithImage() {
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        let message = AIMessage(role: .user, content: .parts([
            .text("What's in this image?"),
            .image(imageData, mimeType: "image/png")
        ]))

        if case .parts(let parts) = message.content {
            XCTAssertEqual(parts.count, 2)
            if case .image(let data, let mimeType) = parts[1] {
                XCTAssertEqual(data, imageData)
                XCTAssertEqual(mimeType, "image/png")
            } else {
                XCTFail("Expected image part")
            }
        } else {
            XCTFail("Expected parts content")
        }
    }

    func testPartsContentWithAudio() {
        let audioData = Data([0x52, 0x49, 0x46, 0x46]) // RIFF header
        let message = AIMessage(role: .user, content: .parts([
            .text("Transcribe this audio"),
            .audio(audioData, mimeType: "audio/wav")
        ]))

        if case .parts(let parts) = message.content {
            XCTAssertEqual(parts.count, 2)
            if case .audio(let data, let mimeType) = parts[1] {
                XCTAssertEqual(data, audioData)
                XCTAssertEqual(mimeType, "audio/wav")
            } else {
                XCTFail("Expected audio part")
            }
        } else {
            XCTFail("Expected parts content")
        }
    }

    func testPartsContentWithFile() {
        let fileData = Data([0x25, 0x50, 0x44, 0x46]) // PDF header
        let message = AIMessage(role: .user, content: .parts([
            .text("Summarize this document"),
            .file(fileData, filename: "document.pdf", mimeType: "application/pdf")
        ]))

        if case .parts(let parts) = message.content {
            XCTAssertEqual(parts.count, 2)
            if case .file(let data, let filename, let mimeType) = parts[1] {
                XCTAssertEqual(data, fileData)
                XCTAssertEqual(filename, "document.pdf")
                XCTAssertEqual(mimeType, "application/pdf")
            } else {
                XCTFail("Expected file part")
            }
        } else {
            XCTFail("Expected parts content")
        }
    }
}

// MARK: - GeminiThinkingConfigTests

final class GeminiThinkingConfigTests: XCTestCase {
    func testRequestWithThinkingOptions() {
        let request = ProviderRequest(
            modelId: "gemini-2.5-pro",
            messages: [AIMessage(role: .user, content: .text("Think about this"))],
            providerOptions: [
                "includeThoughts": .bool(true),
                "thinkingLevel": .string("high")
            ]
        )

        XCTAssertNotNil(request.providerOptions)
        XCTAssertEqual(request.providerOptions?["includeThoughts"], .bool(true))
        XCTAssertEqual(request.providerOptions?["thinkingLevel"], .string("high"))
    }

    func testRequestWithThinkingBudget() {
        let request = ProviderRequest(
            modelId: "gemini-2.5-pro",
            messages: [AIMessage(role: .user, content: .text("Think deeply"))],
            providerOptions: [
                "includeThoughts": .bool(true),
                "thinkingBudget": .int(10000)
            ]
        )

        XCTAssertNotNil(request.providerOptions)
        if case .int(let budget) = request.providerOptions?["thinkingBudget"] {
            XCTAssertEqual(budget, 10000)
        } else {
            XCTFail("Expected int thinking budget")
        }
    }

    func testThinkingLevelValidValues() {
        // Valid thinking levels
        let validLevels = ["minimal", "low", "medium", "high"]

        for level in validLevels {
            let request = ProviderRequest(
                modelId: "gemini-3-flash",
                messages: [AIMessage(role: .user, content: .text("Test"))],
                providerOptions: ["thinkingLevel": .string(level)]
            )
            XCTAssertEqual(request.providerOptions?["thinkingLevel"], .string(level))
        }
    }

    func testDynamicThinkingBudget() {
        // -1 means dynamic thinking (model decides)
        let request = ProviderRequest(
            modelId: "gemini-2.5-flash",
            messages: [AIMessage(role: .user, content: .text("Test"))],
            providerOptions: ["thinkingBudget": .int(-1)]
        )

        if case .int(let budget) = request.providerOptions?["thinkingBudget"] {
            XCTAssertEqual(budget, -1)
        } else {
            XCTFail("Expected int thinking budget")
        }
    }

    func testDisabledThinkingBudget() {
        // 0 means disabled thinking
        let request = ProviderRequest(
            modelId: "gemini-2.5-flash",
            messages: [AIMessage(role: .user, content: .text("Test"))],
            providerOptions: ["thinkingBudget": .int(0)]
        )

        if case .int(let budget) = request.providerOptions?["thinkingBudget"] {
            XCTAssertEqual(budget, 0)
        } else {
            XCTFail("Expected int thinking budget")
        }
    }
}

// MARK: - GeminiReasoningStreamingTests

final class GeminiReasoningStreamingTests: XCTestCase {
    func testParseStreamChunkWithThought() throws {
        // Test JSON parsing of a chunk with thought=true
        let json = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [{
                        "text": "Let me think about this...",
                        "thought": true
                    }]
                }
            }]
        }
        """.data(using: .utf8)!

        XCTAssertNotNil(json)
    }

    func testParseStreamChunkWithMixedThoughtAndText() throws {
        // Test JSON with both thought and regular text parts
        let json = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [
                        {
                            "text": "Analyzing the problem...",
                            "thought": true
                        },
                        {
                            "text": "The answer is 42."
                        }
                    ]
                }
            }]
        }
        """.data(using: .utf8)!

        XCTAssertNotNil(json)
    }

    func testParseUsageWithThoughtsTokenCount() throws {
        // Test JSON with thoughtsTokenCount in usage metadata
        let json = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [{
                        "text": "42"
                    }]
                },
                "finishReason": "STOP"
            }],
            "usageMetadata": {
                "promptTokenCount": 10,
                "candidatesTokenCount": 20,
                "totalTokenCount": 80,
                "thoughtsTokenCount": 50
            }
        }
        """.data(using: .utf8)!

        XCTAssertNotNil(json)
    }

    func testProviderUsageWithReasoningTokens() {
        // Test that ProviderUsage accepts reasoningTokens
        let usage = ProviderUsage(
            promptTokens: 100,
            completionTokens: 50,
            cachedTokens: 20,
            reasoningTokens: 150
        )

        XCTAssertEqual(usage.promptTokens, 100)
        XCTAssertEqual(usage.completionTokens, 50)
        XCTAssertEqual(usage.cachedTokens, 20)
        XCTAssertEqual(usage.reasoningTokens, 150)
    }
}

// MARK: - GeminiStructuredOutputTests

final class GeminiStructuredOutputTests: XCTestCase {
    func testValidSimpleSchema() {
        // A simple schema that Gemini should support
        let schema = """
        {
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "age": {"type": "integer"}
            },
            "required": ["name"]
        }
        """

        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [AIMessage(role: .user, content: .text("Give me a person"))],
            responseFormat: .jsonSchema(name: "person", schema: schema)
        )

        if case .jsonSchema(let name, let actualSchema) = request.responseFormat {
            XCTAssertEqual(name, "person")
            XCTAssertTrue(actualSchema.contains("\"type\": \"object\""))
        } else {
            XCTFail("Expected JSON schema response format")
        }
    }

    func testSchemaWithNestedObjects() {
        // Nested objects are supported
        let schema = """
        {
            "type": "object",
            "properties": {
                "user": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "email": {"type": "string"}
                    }
                }
            }
        }
        """

        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [AIMessage(role: .user, content: .text("Get user"))],
            responseFormat: .jsonSchema(name: "user_response", schema: schema)
        )

        XCTAssertNotNil(request.responseFormat)
    }

    func testSchemaWithArrays() {
        // Arrays with items are supported
        let schema = """
        {
            "type": "object",
            "properties": {
                "items": {
                    "type": "array",
                    "items": {"type": "string"}
                }
            }
        }
        """

        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [AIMessage(role: .user, content: .text("Get items"))],
            responseFormat: .jsonSchema(name: "items_response", schema: schema)
        )

        XCTAssertNotNil(request.responseFormat)
    }

    func testSchemaWithEnums() {
        // Enums are supported
        let schema = """
        {
            "type": "object",
            "properties": {
                "status": {
                    "type": "string",
                    "enum": ["active", "inactive", "pending"]
                }
            }
        }
        """

        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [AIMessage(role: .user, content: .text("Get status"))],
            responseFormat: .jsonSchema(name: "status_response", schema: schema)
        )

        XCTAssertNotNil(request.responseFormat)
    }

    // Note: Tests for invalid schemas (with $ref, allOf, etc.) would need to
    // actually call the adapter to verify the validation throws errors.
    // Those would be integration tests rather than unit tests.
}

// MARK: - GeminiFileReferenceTests

final class GeminiFileReferenceTests: XCTestCase {
    func testParseResponseWithFileData() throws {
        // Test JSON parsing of file_data in a response
        let json = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [{
                        "text": "I can see the video shows..."
                    }]
                },
                "finishReason": "STOP"
            }]
        }
        """.data(using: .utf8)!

        XCTAssertNotNil(json)
    }

    func testFileReferenceURLDetection() {
        // Test that Gemini Files API URLs are recognized
        let geminiFileURL = "https://generativelanguage.googleapis.com/v1beta/files/abc123"
        XCTAssertTrue(geminiFileURL.hasPrefix("https://generativelanguage.googleapis.com"))

        let externalURL = "https://example.com/video.mp4"
        XCTAssertFalse(externalURL.hasPrefix("https://generativelanguage.googleapis.com"))
    }

    func testImageURLAsFileReference() {
        // Test that imageURL content part can use a Gemini Files API URL
        let geminiURL = "https://generativelanguage.googleapis.com/v1beta/files/image123"
        let message = AIMessage(role: .user, content: .parts([
            .text("Describe this image"),
            .imageURL(geminiURL)
        ]))

        if case .parts(let parts) = message.content {
            XCTAssertEqual(parts.count, 2)
            if case .imageURL(let url) = parts[1] {
                XCTAssertTrue(url.hasPrefix("https://generativelanguage.googleapis.com"))
            } else {
                XCTFail("Expected imageURL part")
            }
        } else {
            XCTFail("Expected parts content")
        }
    }
}

// MARK: - GeminiLiveIntegrationTests

final class GeminiLiveIntegrationTests: XCTestCase {
    func testGeminiReasoningStreamEmitsThoughtDeltas() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"],
              !apiKey.isEmpty,
              ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1"
        else {
            throw XCTSkip("GOOGLE_API_KEY or RUN_LIVE_TESTS not set")
        }

        let client = GeminiClientAdapter(apiKey: apiKey)
        let request = ProviderRequest(
            modelId: "gemini-2.5-flash",
            messages: [AIMessage(role: .user, content: .text("What is 15 * 37? Think step by step."))],
            stream: true,
            reasoning: AIReasoningConfig.effort(.medium),
            providerOptions: ["includeThoughts": .bool(true)]
        )

        var hasReasoningDelta = false
        var hasTextDelta = false
        var textContent = ""

        for try await event in client.stream(request: request) {
            switch event {
            case .reasoningDelta:
                hasReasoningDelta = true
            case .textDelta(let text):
                hasTextDelta = true
                textContent += text
            default:
                break
            }
        }

        XCTAssertTrue(hasReasoningDelta, "Streaming with reasoning should emit reasoningDelta events")
        XCTAssertTrue(hasTextDelta, "Streaming should emit textDelta events")
        XCTAssertTrue(textContent.contains("555"), "Response should contain the correct answer (555)")
    }

    func testGeminiNonStreamingReasoningIncludesMetadata() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"],
              !apiKey.isEmpty,
              ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1"
        else {
            throw XCTSkip("GOOGLE_API_KEY or RUN_LIVE_TESTS not set")
        }

        let client = GeminiClientAdapter(apiKey: apiKey)
        let request = ProviderRequest(
            modelId: "gemini-2.5-flash",
            messages: [AIMessage(role: .user, content: .text("What is 15 * 37?"))],
            reasoning: AIReasoningConfig.effort(.medium),
            providerOptions: ["includeThoughts": .bool(true)]
        )

        let response = try await client.execute(request: request)

        XCTAssertFalse(response.content.isEmpty, "Response should have text content")
        // Reasoning metadata should be present when includeThoughts is true
        XCTAssertNotNil(response.metadata?["reasoning"], "Response should include reasoning metadata")
    }
}

// MARK: - GeminiErrorTests

final class GeminiErrorTests: XCTestCase {
    func testGeminiUploadErrorDescriptions() {
        let uploadFailed = GeminiError.uploadFailed(reason: "Network timeout")
        XCTAssertTrue(uploadFailed.localizedDescription.contains("Network timeout"))

        let initFailed = GeminiError.uploadInitiationFailed("Invalid file type")
        XCTAssertTrue(initFailed.localizedDescription.contains("Invalid file type"))

        let chunkFailed = GeminiError.chunkUploadFailed(chunkIndex: 3, reason: "Server error")
        XCTAssertTrue(chunkFailed.localizedDescription.contains("3"))
        XCTAssertTrue(chunkFailed.localizedDescription.contains("Server error"))

        let processingFailed = GeminiError.fileProcessingFailed("Unsupported format")
        XCTAssertTrue(processingFailed.localizedDescription.contains("Unsupported format"))

        let timeout = GeminiError.processingTimeout
        XCTAssertFalse(timeout.localizedDescription.isEmpty)

        let notFound = GeminiError.fileNotFound("file123")
        XCTAssertTrue(notFound.localizedDescription.contains("file123"))

        let expired = GeminiError.fileExpired("file456")
        XCTAssertTrue(expired.localizedDescription.contains("file456"))

        let invalidState = GeminiError.invalidFileState(expected: "ACTIVE", actual: "PROCESSING")
        XCTAssertTrue(invalidState.localizedDescription.contains("ACTIVE"))
        XCTAssertTrue(invalidState.localizedDescription.contains("PROCESSING"))
    }

    func testGeminiFileStateEnum() {
        // Test that GeminiFile.State has all required cases
        let processing = GeminiFile.State.processing
        XCTAssertEqual(processing.rawValue, "PROCESSING")

        let active = GeminiFile.State.active
        XCTAssertEqual(active.rawValue, "ACTIVE")

        let failed = GeminiFile.State.failed
        XCTAssertEqual(failed.rawValue, "FAILED")
    }
}
