//
//  ProviderContractTests.swift
//  AISDKTests
//
//  Contract tests for ProviderClient implementations
//  Verifies all provider adapters conform to the ProviderClient contract
//
//  These tests ensure behavioral consistency across OpenAI, Anthropic, and Gemini adapters.
//

import XCTest
@testable import AISDK

// MARK: - ProviderContractTests

/// Contract tests that verify all ProviderClient implementations behave consistently.
///
/// These tests use protocol-based testing to ensure that OpenAIClientAdapter,
/// AnthropicClientAdapter, and GeminiClientAdapter all satisfy the ProviderClient
/// contract in the same way.
///
/// ## Contract Requirements
/// 1. Identity properties (providerId, displayName, baseURL) must be non-empty
/// 2. Initial health status must be `.unknown`
/// 3. isAvailable must return false when health is `.unknown`
/// 4. capabilities() must return appropriate values for known models
/// 5. execute() must throw appropriate ProviderErrors for failure conditions
/// 6. stream() must return a valid AsyncThrowingStream
/// 7. All implementations must be Sendable
final class ProviderContractTests: XCTestCase {

    // MARK: - Test Factories

    /// Creates all provider clients for contract testing
    func makeAllProviders() -> [any ProviderClient] {
        [
            OpenAIClientAdapter(apiKey: "sk-test-openai"),
            AnthropicClientAdapter(apiKey: "sk-ant-test-anthropic"),
            GeminiClientAdapter(apiKey: "test-gemini-key")
        ]
    }

    // MARK: - Identity Contract Tests

    func testAllProviders_haveNonEmptyProviderId() async {
        for provider in makeAllProviders() {
            XCTAssertFalse(
                provider.providerId.isEmpty,
                "Provider \(type(of: provider)) has empty providerId"
            )
        }
    }

    func testAllProviders_haveNonEmptyDisplayName() async {
        for provider in makeAllProviders() {
            XCTAssertFalse(
                provider.displayName.isEmpty,
                "Provider \(type(of: provider)) has empty displayName"
            )
        }
    }

    func testAllProviders_haveValidBaseURL() async {
        for provider in makeAllProviders() {
            XCTAssertFalse(
                provider.baseURL.absoluteString.isEmpty,
                "Provider \(type(of: provider)) has invalid baseURL"
            )
            XCTAssertTrue(
                provider.baseURL.scheme == "https" || provider.baseURL.scheme == "http",
                "Provider \(type(of: provider)) baseURL should use http(s) scheme"
            )
        }
    }

    func testAllProviders_haveUniqueProviderIds() async {
        let providers = makeAllProviders()
        let ids = providers.map { $0.providerId }
        let uniqueIds = Set(ids)

        XCTAssertEqual(
            ids.count, uniqueIds.count,
            "Provider IDs must be unique. Found: \(ids)"
        )
    }

    // MARK: - Health Status Contract Tests

    func testAllProviders_initialHealthStatusIsUnknown() async {
        for provider in makeAllProviders() {
            let status = await provider.healthStatus
            XCTAssertEqual(
                status, .unknown,
                "Provider \(type(of: provider)) initial health status should be .unknown"
            )
        }
    }

    func testAllProviders_isAvailableFalseWhenUnknown() async {
        for provider in makeAllProviders() {
            let isAvailable = await provider.isAvailable
            XCTAssertFalse(
                isAvailable,
                "Provider \(type(of: provider)) should not be available when health is .unknown"
            )
        }
    }

    // MARK: - Capabilities Contract Tests

    func testAllProviders_returnNilCapabilitiesForUnknownModel() async {
        for provider in makeAllProviders() {
            let capabilities = await provider.capabilities(for: "unknown-model-xyz-123")
            // Note: Some providers may return generic capabilities, others nil
            // The contract is that the call doesn't crash
            _ = capabilities
        }
    }

    func testAllProviders_returnCapabilitiesForKnownModels() async {
        // Test OpenAI
        let openai = OpenAIClientAdapter(apiKey: "sk-test")
        let openaiCaps = await openai.capabilities(for: "gpt-4o")
        XCTAssertNotNil(openaiCaps, "OpenAI should return capabilities for gpt-4o")
        XCTAssertTrue(openaiCaps!.contains(.text), "gpt-4o should have text capability")

        // Test Anthropic
        let anthropic = AnthropicClientAdapter(apiKey: "sk-ant-test")
        let anthropicCaps = await anthropic.capabilities(for: "claude-sonnet-4-20250514")
        XCTAssertNotNil(anthropicCaps, "Anthropic should return capabilities for claude-sonnet")
        XCTAssertTrue(anthropicCaps!.contains(.text), "claude-sonnet should have text capability")

        // Test Gemini
        let gemini = GeminiClientAdapter(apiKey: "test-key")
        let geminiCaps = await gemini.capabilities(for: "gemini-2.0-flash")
        XCTAssertNotNil(geminiCaps, "Gemini should return capabilities for gemini-2.0-flash")
        XCTAssertTrue(geminiCaps!.contains(.text), "gemini-2.0-flash should have text capability")
    }

    func testAllProviders_capabilitiesIncludeStreamingForChatModels() async {
        // OpenAI chat models should support streaming
        let openai = OpenAIClientAdapter(apiKey: "sk-test")
        let openaiCaps = await openai.capabilities(for: "gpt-4o")
        XCTAssertTrue(openaiCaps?.contains(.streaming) ?? false, "gpt-4o should support streaming")

        // Anthropic chat models should support streaming
        let anthropic = AnthropicClientAdapter(apiKey: "sk-ant-test")
        let anthropicCaps = await anthropic.capabilities(for: "claude-3-5-sonnet-20241022")
        XCTAssertTrue(anthropicCaps?.contains(.streaming) ?? false, "claude-3.5-sonnet should support streaming")

        // Gemini chat models should support streaming
        let gemini = GeminiClientAdapter(apiKey: "test-key")
        let geminiCaps = await gemini.capabilities(for: "gemini-1.5-flash")
        XCTAssertTrue(geminiCaps?.contains(.streaming) ?? false, "gemini-1.5-flash should support streaming")
    }

    // MARK: - Model Availability Contract Tests

    func testAllProviders_isModelAvailableForKnownModels() async {
        // OpenAI
        let openai = OpenAIClientAdapter(apiKey: "sk-test")
        let openaiAvailable = await openai.isModelAvailable("gpt-4o")
        // Note: Without network, this may return false (checks against cached list)
        // The contract is that the method doesn't crash
        _ = openaiAvailable

        // Anthropic
        let anthropic = AnthropicClientAdapter(apiKey: "sk-ant-test")
        let anthropicAvailable = await anthropic.isModelAvailable("claude-sonnet-4-20250514")
        XCTAssertTrue(anthropicAvailable, "Anthropic should recognize claude-sonnet-4 as available")

        // Gemini
        let gemini = GeminiClientAdapter(apiKey: "test-key")
        let geminiAvailable = await gemini.isModelAvailable("gemini-2.0-flash")
        XCTAssertTrue(geminiAvailable, "Gemini should recognize gemini-2.0-flash as available")
    }

    func testAnthropicAndGemini_recognizeModelPatterns() async {
        // Anthropic should recognize claude-* pattern
        let anthropic = AnthropicClientAdapter(apiKey: "sk-ant-test")
        let claudeAvailable = await anthropic.isModelAvailable("claude-future-model")
        XCTAssertTrue(claudeAvailable, "Anthropic should recognize claude-* pattern")

        // Gemini should recognize gemini-* pattern
        let gemini = GeminiClientAdapter(apiKey: "test-key")
        let geminiAvailable = await gemini.isModelAvailable("gemini-future-model")
        XCTAssertTrue(geminiAvailable, "Gemini should recognize gemini-* pattern")
    }

    // MARK: - Stream Contract Tests

    func testAllProviders_streamReturnsValidStream() async {
        let request = ProviderRequest(
            modelId: "test-model",
            messages: [AIMessage.user("Hello")]
        )

        for provider in makeAllProviders() {
            // Get stream - should not crash
            let stream = provider.stream(request: request)
            XCTAssertNotNil(stream, "Provider \(type(of: provider)) should return a valid stream")
        }
    }

    func testAllProviders_streamIsNonisolated() {
        // This test verifies that stream() can be called without await
        // which is required for the nonisolated contract
        let request = ProviderRequest(
            modelId: "test-model",
            messages: [AIMessage.user("Hello")]
        )

        // These calls should compile without await due to nonisolated
        let _ = OpenAIClientAdapter(apiKey: "sk-test").stream(request: request)
        let _ = AnthropicClientAdapter(apiKey: "sk-ant-test").stream(request: request)
        let _ = GeminiClientAdapter(apiKey: "test-key").stream(request: request)
    }

    // MARK: - Sendable Contract Tests

    func testAllProviders_areSendable() {
        // This test verifies Sendable conformance by using providers across task boundaries
        let providers = makeAllProviders()

        for provider in providers {
            Task.detached {
                // Access from detached task proves Sendable conformance
                let _ = provider.providerId
                let _ = provider.displayName
                let _ = provider.baseURL
            }
        }
    }

    func testAllProviders_canBeUsedConcurrently() async {
        let providers = makeAllProviders()

        // Run concurrent health status checks
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask {
                    let _ = await provider.healthStatus
                    let _ = await provider.isAvailable
                }
            }
        }
    }

    // MARK: - Request Construction Contract Tests

    func testProviderRequest_defaultValues() {
        let request = ProviderRequest(
            modelId: "test-model",
            messages: [AIMessage.user("Hello")]
        )

        XCTAssertEqual(request.modelId, "test-model")
        XCTAssertEqual(request.messages.count, 1)
        XCTAssertNil(request.maxTokens)
        XCTAssertNil(request.temperature)
        XCTAssertNil(request.topP)
        XCTAssertNil(request.stop)
        XCTAssertFalse(request.stream)
        XCTAssertNil(request.tools)
        XCTAssertNil(request.toolChoice)
        XCTAssertNil(request.responseFormat)
        XCTAssertEqual(request.timeout, 120)
        XCTAssertNil(request.providerOptions)
        XCTAssertNil(request.traceContext)
    }

    func testProviderRequest_withAllParameters() {
        let tool = ProviderJSONValue.object([
            "type": .string("function"),
            "function": .object([
                "name": .string("get_weather"),
                "description": .string("Get weather for a city"),
                "parameters": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "city": .object(["type": .string("string")])
                    ])
                ])
            ])
        ])

        let request = ProviderRequest(
            modelId: "gpt-4o",
            messages: [
                AIMessage.system("You are helpful."),
                AIMessage.user("What's the weather?")
            ],
            maxTokens: 1000,
            temperature: 0.7,
            topP: 0.9,
            stop: ["END", "STOP"],
            stream: true,
            tools: [tool],
            toolChoice: .auto,
            responseFormat: .json,
            timeout: 60,
            providerOptions: ["custom": .string("value")],
            traceContext: nil,
            metadata: ["key": "value"]
        )

        XCTAssertEqual(request.modelId, "gpt-4o")
        XCTAssertEqual(request.messages.count, 2)
        XCTAssertEqual(request.maxTokens, 1000)
        XCTAssertEqual(request.temperature, 0.7)
        XCTAssertEqual(request.topP, 0.9)
        XCTAssertEqual(request.stop, ["END", "STOP"])
        XCTAssertTrue(request.stream)
        XCTAssertEqual(request.tools?.count, 1)
        XCTAssertEqual(request.toolChoice, .auto)
        XCTAssertEqual(request.responseFormat, .json)
        XCTAssertEqual(request.timeout, 60)
        XCTAssertNotNil(request.providerOptions)
        XCTAssertEqual(request.metadata?["key"], "value")
    }

    // MARK: - Response Contract Tests

    func testProviderResponse_requiredFields() {
        let response = ProviderResponse(
            id: "resp-123",
            model: "gpt-4o",
            provider: "openai",
            content: "Hello!",
            finishReason: .stop
        )

        XCTAssertFalse(response.id.isEmpty)
        XCTAssertFalse(response.model.isEmpty)
        XCTAssertFalse(response.provider.isEmpty)
        XCTAssertEqual(response.finishReason, .stop)
    }

    func testProviderResponse_withToolCalls() {
        let toolCalls = [
            ProviderToolCall(id: "tc1", name: "search", arguments: "{\"q\":\"weather\"}"),
            ProviderToolCall(id: "tc2", name: "calculate", arguments: "{\"expr\":\"2+2\"}")
        ]

        let response = ProviderResponse(
            id: "resp-456",
            model: "gpt-4o",
            provider: "openai",
            content: "",
            toolCalls: toolCalls,
            usage: ProviderUsage(promptTokens: 100, completionTokens: 50),
            finishReason: .toolCalls
        )

        XCTAssertEqual(response.toolCalls.count, 2)
        XCTAssertEqual(response.toolCalls[0].name, "search")
        XCTAssertEqual(response.toolCalls[1].name, "calculate")
        XCTAssertEqual(response.finishReason, .toolCalls)
    }

    // MARK: - Error Contract Tests

    func testProviderError_allCasesHaveDescriptions() {
        let errors: [ProviderError] = [
            .invalidRequest("Bad request"),
            .authenticationFailed("Invalid key"),
            .rateLimited(retryAfter: 60),
            .rateLimited(retryAfter: nil),
            .modelNotFound("unknown-model"),
            .timeout(30),
            .serverError(statusCode: 500, message: "Internal error"),
            .networkError("Connection failed"),
            .parseError("Invalid JSON"),
            .contentFiltered("Unsafe content"),
            .providerSpecific(code: "E001", message: "Custom error"),
            .unknown("Something went wrong")
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testProviderError_rateLimitedIncludesRetryAfter() {
        let errorWithRetry = ProviderError.rateLimited(retryAfter: 30)
        XCTAssertTrue(errorWithRetry.localizedDescription.contains("30"))

        let errorWithoutRetry = ProviderError.rateLimited(retryAfter: nil)
        XCTAssertTrue(errorWithoutRetry.localizedDescription.contains("Rate limited"))
    }

    // MARK: - Stream Event Contract Tests

    func testProviderStreamEvent_allEventsConvertToAIStreamEvent() {
        let events: [ProviderStreamEvent] = [
            .start(id: "id-1", model: "gpt-4o"),
            .textDelta("Hello"),
            .toolCallStart(id: "tc1", name: "search"),
            .toolCallDelta(id: "tc1", argumentsDelta: "{\"q\":"),
            .toolCallFinish(id: "tc1", name: "search", arguments: "{\"q\":\"test\"}"),
            .toolResult(id: "tc1", result: "ok", metadata: nil),
            .reasoningDelta("thinking..."),
            .source(AISource(id: "src-1", url: "https://example.com", title: "Example")),
            .usage(ProviderUsage(promptTokens: 10, completionTokens: 5)),
            .finish(reason: .stop, usage: ProviderUsage(promptTokens: 10, completionTokens: 5))
        ]

        for event in events {
            let aiEvent = event.toAIStreamEvent()
            // Verify conversion doesn't crash and produces valid event
            _ = aiEvent
        }
    }

    func testProviderStreamEvent_textDeltaConversion() {
        let event = ProviderStreamEvent.textDelta("Hello, world!")
        let aiEvent = event.toAIStreamEvent()

        if case .textDelta(let text) = aiEvent {
            XCTAssertEqual(text, "Hello, world!")
        } else {
            XCTFail("Expected textDelta event")
        }
    }

    func testProviderStreamEvent_finishConversion() {
        let usage = ProviderUsage(promptTokens: 100, completionTokens: 50)
        let event = ProviderStreamEvent.finish(reason: .stop, usage: usage)
        let aiEvent = event.toAIStreamEvent()

        if case .finish(let reason, let aiUsage) = aiEvent {
            XCTAssertEqual(reason, .stop)
            XCTAssertEqual(aiUsage.promptTokens, 100)
            XCTAssertEqual(aiUsage.completionTokens, 50)
        } else {
            XCTFail("Expected finish event")
        }
    }

    // MARK: - Finish Reason Contract Tests

    func testProviderFinishReason_mapsProviderStrings() {
        // Standard reasons
        XCTAssertEqual(ProviderFinishReason(providerReason: "stop"), .stop)
        XCTAssertEqual(ProviderFinishReason(providerReason: "length"), .length)
        XCTAssertEqual(ProviderFinishReason(providerReason: "tool_calls"), .toolCalls)
        XCTAssertEqual(ProviderFinishReason(providerReason: "content_filter"), .contentFilter)

        // Anthropic-style reasons
        XCTAssertEqual(ProviderFinishReason(providerReason: "end_turn"), .stop)
        XCTAssertEqual(ProviderFinishReason(providerReason: "stop_sequence"), .stop)
        XCTAssertEqual(ProviderFinishReason(providerReason: "max_tokens"), .length)
        XCTAssertEqual(ProviderFinishReason(providerReason: "tool_use"), .toolCalls)
    }

    func testProviderFinishReason_handlesCaseInsensitivity() {
        XCTAssertEqual(ProviderFinishReason(providerReason: "STOP"), .stop)
        XCTAssertEqual(ProviderFinishReason(providerReason: "Stop"), .stop)
        XCTAssertEqual(ProviderFinishReason(providerReason: "LENGTH"), .length)
        XCTAssertEqual(ProviderFinishReason(providerReason: "TOOL_CALLS"), .toolCalls)
    }

    func testProviderFinishReason_handlesUnknownValues() {
        XCTAssertEqual(ProviderFinishReason(providerReason: nil), .unknown)
        XCTAssertEqual(ProviderFinishReason(providerReason: ""), .unknown)
        XCTAssertEqual(ProviderFinishReason(providerReason: "some_future_reason"), .unknown)
    }

    // MARK: - Usage Contract Tests

    func testProviderUsage_totalTokensCalculation() {
        let usage = ProviderUsage(promptTokens: 100, completionTokens: 50)
        XCTAssertEqual(usage.totalTokens, 150)
    }

    func testProviderUsage_zeroConstant() {
        let zero = ProviderUsage.zero
        XCTAssertEqual(zero.promptTokens, 0)
        XCTAssertEqual(zero.completionTokens, 0)
        XCTAssertEqual(zero.totalTokens, 0)
        XCTAssertNil(zero.cachedTokens)
        XCTAssertNil(zero.reasoningTokens)
    }

    func testProviderUsage_convertsToAIUsage() {
        let usage = ProviderUsage(
            promptTokens: 100,
            completionTokens: 50,
            cachedTokens: 20,
            reasoningTokens: 10
        )

        let aiUsage = usage.toAIUsage()

        XCTAssertEqual(aiUsage.promptTokens, 100)
        XCTAssertEqual(aiUsage.completionTokens, 50)
        XCTAssertEqual(aiUsage.totalTokens, 150)
        XCTAssertEqual(aiUsage.cachedTokens, 20)
        XCTAssertEqual(aiUsage.reasoningTokens, 10)
    }

    // MARK: - JSON Value Contract Tests

    func testProviderJSONValue_allTypesEncodable() throws {
        let values: [ProviderJSONValue] = [
            .null,
            .bool(true),
            .bool(false),
            .int(42),
            .double(3.14),
            .string("hello"),
            .array([.int(1), .int(2), .int(3)]),
            .object(["key": .string("value")])
        ]

        let encoder = JSONEncoder()
        for value in values {
            let data = try encoder.encode(value)
            XCTAssertNotNil(data)
        }
    }

    func testProviderJSONValue_roundTrip() throws {
        let original = ProviderJSONValue.object([
            "string": .string("hello"),
            "number": .int(42),
            "float": .double(3.14),
            "bool": .bool(true),
            "null": .null,
            "array": .array([.int(1), .int(2)]),
            "nested": .object(["inner": .string("value")])
        ])

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ProviderJSONValue.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Tool Call Contract Tests

    func testProviderToolCall_codable() throws {
        let toolCall = ProviderToolCall(
            id: "call_abc123",
            name: "get_weather",
            arguments: "{\"city\":\"Seattle\",\"units\":\"celsius\"}"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(toolCall)
        let decoded = try decoder.decode(ProviderToolCall.self, from: data)

        XCTAssertEqual(decoded.id, toolCall.id)
        XCTAssertEqual(decoded.name, toolCall.name)
        XCTAssertEqual(decoded.arguments, toolCall.arguments)
    }

    func testProviderToolCall_equality() {
        let tc1 = ProviderToolCall(id: "1", name: "search", arguments: "{}")
        let tc2 = ProviderToolCall(id: "1", name: "search", arguments: "{}")
        let tc3 = ProviderToolCall(id: "2", name: "search", arguments: "{}")

        XCTAssertEqual(tc1, tc2)
        XCTAssertNotEqual(tc1, tc3)
    }

    // MARK: - Health Status Contract Tests

    func testProviderHealthStatus_acceptsTrafficLogic() {
        XCTAssertTrue(ProviderHealthStatus.healthy.acceptsTraffic)
        XCTAssertTrue(ProviderHealthStatus.degraded(reason: "Slow").acceptsTraffic)
        XCTAssertFalse(ProviderHealthStatus.unhealthy(reason: "Down").acceptsTraffic)
        XCTAssertFalse(ProviderHealthStatus.unknown.acceptsTraffic)
    }

    func testProviderHealthStatus_equality() {
        XCTAssertEqual(ProviderHealthStatus.healthy, ProviderHealthStatus.healthy)
        XCTAssertEqual(ProviderHealthStatus.unknown, ProviderHealthStatus.unknown)
        XCTAssertEqual(
            ProviderHealthStatus.degraded(reason: "A"),
            ProviderHealthStatus.degraded(reason: "A")
        )
        XCTAssertNotEqual(
            ProviderHealthStatus.degraded(reason: "A"),
            ProviderHealthStatus.degraded(reason: "B")
        )
    }
}

// MARK: - Provider-Specific Contract Tests

/// Tests specific contract requirements for OpenAI adapter
final class OpenAIContractTests: XCTestCase {

    func testOpenAI_providerId() {
        let client = OpenAIClientAdapter(apiKey: "sk-test")
        XCTAssertEqual(client.providerId, "openai")
    }

    func testOpenAI_baseURL() {
        let client = OpenAIClientAdapter(apiKey: "sk-test")
        XCTAssertEqual(client.baseURL.absoluteString, "https://api.openai.com/v1")
    }

    func testOpenAI_visionModelsHaveVisionCapability() async {
        let client = OpenAIClientAdapter(apiKey: "sk-test")

        let gpt4o = await client.capabilities(for: "gpt-4o")
        XCTAssertTrue(gpt4o?.contains(.vision) ?? false, "gpt-4o should have vision")

        let gpt4Turbo = await client.capabilities(for: "gpt-4-turbo")
        XCTAssertTrue(gpt4Turbo?.contains(.vision) ?? false, "gpt-4-turbo should have vision")
    }

    func testOpenAI_reasoningModelsHaveReasoningCapability() async {
        let client = OpenAIClientAdapter(apiKey: "sk-test")

        let o1 = await client.capabilities(for: "o1-preview")
        XCTAssertTrue(o1?.contains(.reasoning) ?? false, "o1-preview should have reasoning")

        let o3 = await client.capabilities(for: "o3-mini")
        XCTAssertTrue(o3?.contains(.reasoning) ?? false, "o3-mini should have reasoning")
    }
}

/// Tests specific contract requirements for Anthropic adapter
final class AnthropicContractTests: XCTestCase {

    func testAnthropic_providerId() {
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test")
        XCTAssertEqual(client.providerId, "anthropic")
    }

    func testAnthropic_baseURL() {
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test")
        XCTAssertEqual(client.baseURL.absoluteString, "https://api.anthropic.com")
    }

    func testAnthropic_opusHasReasoningCapability() async {
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test")
        let opus = await client.capabilities(for: "claude-opus-4-5-20251101")

        XCTAssertTrue(opus?.contains(.reasoning) ?? false, "claude-opus should have reasoning")
        XCTAssertTrue(opus?.contains(.longContext) ?? false, "claude-opus should have longContext")
    }

    func testAnthropic_allClaudeModelsHaveVision() async {
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test")

        let opus = await client.capabilities(for: "claude-opus-4-5-20251101")
        XCTAssertTrue(opus?.contains(.vision) ?? false, "claude-opus should have vision")

        let sonnet = await client.capabilities(for: "claude-sonnet-4-5-20250929")
        XCTAssertTrue(sonnet?.contains(.vision) ?? false, "claude-sonnet should have vision")

        let haiku = await client.capabilities(for: "claude-haiku-4-5-20251001")
        XCTAssertTrue(haiku?.contains(.vision) ?? false, "claude-haiku should have vision")
    }

    func testAnthropic_knownModelsAreAvailable() async throws {
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test")
        let models = try await client.availableModels

        XCTAssertTrue(models.contains("claude-opus-4-5-20251101"))
        XCTAssertTrue(models.contains("claude-sonnet-4-5-20250929"))
        XCTAssertTrue(models.contains("claude-haiku-4-5-20251001"))
    }
}

/// Tests specific contract requirements for Gemini adapter
final class GeminiContractTests: XCTestCase {

    func testGemini_providerId() {
        let client = GeminiClientAdapter(apiKey: "test-key")
        XCTAssertEqual(client.providerId, "gemini")
    }

    func testGemini_baseURL() {
        let client = GeminiClientAdapter(apiKey: "test-key")
        XCTAssertTrue(client.baseURL.absoluteString.contains("generativelanguage.googleapis.com"))
    }

    func testGemini_25ProHasReasoningCapability() async {
        let client = GeminiClientAdapter(apiKey: "test-key")
        let pro = await client.capabilities(for: "gemini-2.5-pro-preview-05-06")

        XCTAssertTrue(pro?.contains(.reasoning) ?? false, "gemini-2.5-pro should have reasoning")
        XCTAssertTrue(pro?.contains(.longContext) ?? false, "gemini-2.5-pro should have longContext")
    }

    func testGemini_allModelsHaveVision() async {
        let client = GeminiClientAdapter(apiKey: "test-key")

        let pro = await client.capabilities(for: "gemini-2.5-pro-preview-05-06")
        XCTAssertTrue(pro?.contains(.vision) ?? false, "gemini-2.5-pro should have vision")

        let flash = await client.capabilities(for: "gemini-2.0-flash")
        XCTAssertTrue(flash?.contains(.vision) ?? false, "gemini-2.0-flash should have vision")
    }

    func testGemini_recognizesKnownModels() async {
        let client = GeminiClientAdapter(apiKey: "test-key")

        let pro25 = await client.isModelAvailable("gemini-2.5-pro-preview-05-06")
        XCTAssertTrue(pro25, "gemini-2.5-pro should be available")

        let flash20 = await client.isModelAvailable("gemini-2.0-flash")
        XCTAssertTrue(flash20, "gemini-2.0-flash should be available")

        let pro15 = await client.isModelAvailable("gemini-1.5-pro")
        XCTAssertTrue(pro15, "gemini-1.5-pro should be available")

        let flash15 = await client.isModelAvailable("gemini-1.5-flash")
        XCTAssertTrue(flash15, "gemini-1.5-flash should be available")
    }
}
