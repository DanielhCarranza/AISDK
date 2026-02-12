//
//  ProviderClientTests.swift
//  AISDKTests
//
//  Tests for ProviderClient protocol and supporting types
//

import XCTest
@testable import AISDK

final class ProviderClientTests: XCTestCase {

    // MARK: - ProviderHealthStatus Tests

    func testHealthStatusAcceptsTraffic() {
        XCTAssertTrue(ProviderHealthStatus.healthy.acceptsTraffic)
        XCTAssertTrue(ProviderHealthStatus.degraded(reason: "High latency").acceptsTraffic)
        XCTAssertFalse(ProviderHealthStatus.unhealthy(reason: "Server down").acceptsTraffic)
        XCTAssertFalse(ProviderHealthStatus.unknown.acceptsTraffic)
    }

    func testHealthStatusEquality() {
        XCTAssertEqual(ProviderHealthStatus.healthy, ProviderHealthStatus.healthy)
        XCTAssertEqual(
            ProviderHealthStatus.degraded(reason: "Test"),
            ProviderHealthStatus.degraded(reason: "Test")
        )
        XCTAssertNotEqual(
            ProviderHealthStatus.degraded(reason: "A"),
            ProviderHealthStatus.degraded(reason: "B")
        )
    }

    // MARK: - ProviderToolChoice Tests

    func testProviderToolChoiceEquality() {
        XCTAssertEqual(ProviderToolChoice.auto, ProviderToolChoice.auto)
        XCTAssertEqual(ProviderToolChoice.none, ProviderToolChoice.none)
        XCTAssertEqual(ProviderToolChoice.required, ProviderToolChoice.required)
        XCTAssertEqual(ProviderToolChoice.tool(name: "search"), ProviderToolChoice.tool(name: "search"))
        XCTAssertNotEqual(ProviderToolChoice.tool(name: "search"), ProviderToolChoice.tool(name: "other"))
    }

    // MARK: - ProviderResponseFormat Tests

    func testProviderResponseFormatEquality() {
        XCTAssertEqual(ProviderResponseFormat.text, ProviderResponseFormat.text)
        XCTAssertEqual(ProviderResponseFormat.json, ProviderResponseFormat.json)
        XCTAssertEqual(
            ProviderResponseFormat.jsonSchema(name: "test", schema: "{}"),
            ProviderResponseFormat.jsonSchema(name: "test", schema: "{}")
        )
        XCTAssertNotEqual(
            ProviderResponseFormat.jsonSchema(name: "a", schema: "{}"),
            ProviderResponseFormat.jsonSchema(name: "b", schema: "{}")
        )
    }

    // MARK: - ProviderRequest Tests

    func testProviderRequestInitialization() {
        let messages = [AIMessage.user("Hello")]
        let request = ProviderRequest(
            modelId: "gpt-4",
            messages: messages,
            maxTokens: 1000,
            temperature: 0.7,
            topP: 0.9,
            stop: ["END"],
            stream: true,
            tools: nil,
            toolChoice: .auto,
            responseFormat: .json,
            timeout: 60,
            providerOptions: nil,
            traceContext: nil
        )

        XCTAssertEqual(request.modelId, "gpt-4")
        XCTAssertEqual(request.maxTokens, 1000)
        XCTAssertEqual(request.temperature, 0.7)
        XCTAssertEqual(request.topP, 0.9)
        XCTAssertEqual(request.stop, ["END"])
        XCTAssertTrue(request.stream)
        XCTAssertEqual(request.toolChoice, .auto)
        XCTAssertEqual(request.responseFormat, .json)
        XCTAssertEqual(request.timeout, 60)
    }

    func testProviderRequestDefaults() {
        let messages = [AIMessage.user("Test")]
        let request = ProviderRequest(modelId: "test-model", messages: messages)

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

    // MARK: - ProviderResponse Tests

    func testProviderResponseInitialization() {
        let usage = ProviderUsage(promptTokens: 100, completionTokens: 50)
        let toolCalls = [ProviderToolCall(id: "tc1", name: "search", arguments: "{\"q\":\"test\"}")]

        let response = ProviderResponse(
            id: "resp-123",
            model: "gpt-4",
            provider: "openai",
            content: "Hello, world!",
            toolCalls: toolCalls,
            usage: usage,
            finishReason: .stop,
            latencyMs: 500,
            metadata: ["custom": "value"]
        )

        XCTAssertEqual(response.id, "resp-123")
        XCTAssertEqual(response.model, "gpt-4")
        XCTAssertEqual(response.provider, "openai")
        XCTAssertEqual(response.content, "Hello, world!")
        XCTAssertEqual(response.toolCalls.count, 1)
        XCTAssertEqual(response.toolCalls[0].name, "search")
        XCTAssertEqual(response.usage?.promptTokens, 100)
        XCTAssertEqual(response.usage?.completionTokens, 50)
        XCTAssertEqual(response.finishReason, .stop)
        XCTAssertEqual(response.latencyMs, 500)
        XCTAssertEqual(response.metadata?["custom"], "value")
    }

    // MARK: - ProviderToolCall Tests

    func testProviderToolCallCodable() throws {
        let toolCall = ProviderToolCall(
            id: "call-123",
            name: "get_weather",
            arguments: "{\"city\":\"Seattle\"}"
        )

        let encoded = try JSONEncoder().encode(toolCall)
        let decoded = try JSONDecoder().decode(ProviderToolCall.self, from: encoded)

        XCTAssertEqual(decoded.id, "call-123")
        XCTAssertEqual(decoded.name, "get_weather")
        XCTAssertEqual(decoded.arguments, "{\"city\":\"Seattle\"}")
    }

    // MARK: - ProviderUsage Tests

    func testProviderUsageTotalTokens() {
        let usage = ProviderUsage(promptTokens: 100, completionTokens: 50)
        XCTAssertEqual(usage.totalTokens, 150)
    }

    func testProviderUsageWithOptionalTokens() {
        let usage = ProviderUsage(
            promptTokens: 100,
            completionTokens: 50,
            cachedTokens: 20,
            reasoningTokens: 10
        )

        XCTAssertEqual(usage.promptTokens, 100)
        XCTAssertEqual(usage.completionTokens, 50)
        XCTAssertEqual(usage.cachedTokens, 20)
        XCTAssertEqual(usage.reasoningTokens, 10)
        XCTAssertEqual(usage.totalTokens, 150)
    }

    func testProviderUsageZero() {
        let zero = ProviderUsage.zero
        XCTAssertEqual(zero.promptTokens, 0)
        XCTAssertEqual(zero.completionTokens, 0)
        XCTAssertEqual(zero.totalTokens, 0)
    }

    // MARK: - ProviderFinishReason Tests

    func testProviderFinishReasonCodable() throws {
        let reasons: [ProviderFinishReason] = [.stop, .length, .toolCalls, .contentFilter, .functionCall, .unknown]

        for reason in reasons {
            let encoded = try JSONEncoder().encode(reason)
            let decoded = try JSONDecoder().decode(ProviderFinishReason.self, from: encoded)
            XCTAssertEqual(decoded, reason)
        }
    }

    // MARK: - ProviderError Tests

    func testProviderErrorDescriptions() {
        let errors: [ProviderError] = [
            .invalidRequest("Bad params"),
            .authenticationFailed("Invalid key"),
            .rateLimited(retryAfter: 30),
            .rateLimited(retryAfter: nil),
            .modelNotFound("gpt-5"),
            .timeout(60),
            .serverError(statusCode: 500, message: "Internal error"),
            .networkError("Connection failed"),
            .parseError("Invalid JSON"),
            .contentFiltered("Unsafe content"),
            .providerSpecific(code: "E001", message: "Custom error"),
            .unknown("Something went wrong")
        ]

        for error in errors {
            XCTAssertNotNil(error.localizedDescription)
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    // MARK: - Conversion Tests

    func testProviderUsageToAIUsage() {
        let providerUsage = ProviderUsage(
            promptTokens: 100,
            completionTokens: 50,
            cachedTokens: 20,
            reasoningTokens: 10
        )

        let aiUsage = providerUsage.toAIUsage()

        XCTAssertEqual(aiUsage.promptTokens, 100)
        XCTAssertEqual(aiUsage.completionTokens, 50)
        XCTAssertEqual(aiUsage.totalTokens, 150)
        XCTAssertEqual(aiUsage.cachedTokens, 20)
        XCTAssertEqual(aiUsage.reasoningTokens, 10)
    }

    func testProviderFinishReasonToAIFinishReason() {
        XCTAssertEqual(ProviderFinishReason.stop.toAIFinishReason(), .stop)
        XCTAssertEqual(ProviderFinishReason.length.toAIFinishReason(), .length)
        XCTAssertEqual(ProviderFinishReason.toolCalls.toAIFinishReason(), .toolCalls)
        XCTAssertEqual(ProviderFinishReason.functionCall.toAIFinishReason(), .toolCalls)
        XCTAssertEqual(ProviderFinishReason.contentFilter.toAIFinishReason(), .contentFilter)
        XCTAssertEqual(ProviderFinishReason.unknown.toAIFinishReason(), .unknown)
    }

    func testProviderResponseToAITextResult() {
        let usage = ProviderUsage(promptTokens: 100, completionTokens: 50)
        let toolCalls = [ProviderToolCall(id: "tc1", name: "search", arguments: "{\"q\":\"test\"}")]

        let response = ProviderResponse(
            id: "resp-123",
            model: "gpt-4",
            provider: "openai",
            content: "Test response",
            toolCalls: toolCalls,
            usage: usage,
            finishReason: .stop
        )

        let result = response.toAITextResult()

        XCTAssertEqual(result.text, "Test response")
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].id, "tc1")
        XCTAssertEqual(result.toolCalls[0].name, "search")
        XCTAssertEqual(result.usage.promptTokens, 100)
        XCTAssertEqual(result.usage.completionTokens, 50)
        XCTAssertEqual(result.finishReason, .stop)
        XCTAssertEqual(result.requestId, "resp-123")
        XCTAssertEqual(result.model, "gpt-4")
        XCTAssertEqual(result.provider, "openai")
    }

    func testProviderStreamEventConversions() {
        // Test textDelta
        let textEvent = ProviderStreamEvent.textDelta("Hello").toAIStreamEvent()
        if case .textDelta(let text) = textEvent {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected textDelta event")
        }

        // Test start
        let startEvent = ProviderStreamEvent.start(id: "id-1", model: "gpt-4").toAIStreamEvent()
        if case .start(let metadata) = startEvent {
            XCTAssertEqual(metadata?.requestId, "id-1")
            XCTAssertEqual(metadata?.model, "gpt-4")
        } else {
            XCTFail("Expected start event")
        }

        // Test toolCallStart
        let toolStartEvent = ProviderStreamEvent.toolCallStart(id: "tc1", name: "search").toAIStreamEvent()
        if case .toolCallStart(let id, let name) = toolStartEvent {
            XCTAssertEqual(id, "tc1")
            XCTAssertEqual(name, "search")
        } else {
            XCTFail("Expected toolCallStart event")
        }

        // Test finish with usage
        let usage = ProviderUsage(promptTokens: 10, completionTokens: 5)
        let finishEvent = ProviderStreamEvent.finish(reason: .stop, usage: usage).toAIStreamEvent()
        if case .finish(let finishReason, let aiUsage) = finishEvent {
            XCTAssertEqual(finishReason, .stop)
            XCTAssertEqual(aiUsage.totalTokens, 15)
        } else {
            XCTFail("Expected finish event")
        }

        // Test finish without usage
        let finishNoUsageEvent = ProviderStreamEvent.finish(reason: .length, usage: nil).toAIStreamEvent()
        if case .finish(let finishReason, let aiUsage) = finishNoUsageEvent {
            XCTAssertEqual(finishReason, .length)
            XCTAssertEqual(aiUsage.totalTokens, 0) // Defaults to zero when nil
        } else {
            XCTFail("Expected finish event")
        }
    }

    // MARK: - ToolChoice Conversion Tests

    func testToolChoiceToProviderToolChoice() {
        XCTAssertEqual(ToolChoice.auto.toProviderToolChoice(), .auto)
        XCTAssertEqual(ToolChoice.none.toProviderToolChoice(), .none)
        XCTAssertEqual(ToolChoice.required.toProviderToolChoice(), .required)

        let functionChoice = ToolChoice.FunctionChoice(name: "get_weather")
        XCTAssertEqual(ToolChoice.function(functionChoice).toProviderToolChoice(), .tool(name: "get_weather"))
    }

    // MARK: - AITextRequest Conversion Tests

    func testAITextRequestToProviderRequest() throws {
        let providerOptions: [String: ProviderJSONValue] = ["includeThoughts": .bool(true)]
        let request = AITextRequest(
            messages: [.user("Hello")],
            model: "gpt-4",
            maxTokens: 100,
            temperature: 0.7,
            topP: 0.9,
            stop: ["END"],
            toolChoice: .auto,
            reasoning: AIReasoningConfig.effort(.low),
            providerOptions: providerOptions
        )

        let providerRequest = try request.toProviderRequest(modelId: "fallback-model", stream: true)

        XCTAssertEqual(providerRequest.modelId, "gpt-4") // Uses request.model
        XCTAssertEqual(providerRequest.maxTokens, 100)
        XCTAssertEqual(providerRequest.temperature, 0.7)
        XCTAssertEqual(providerRequest.topP, 0.9)
        XCTAssertEqual(providerRequest.stop, ["END"])
        XCTAssertTrue(providerRequest.stream)
        XCTAssertEqual(providerRequest.toolChoice, .some(.auto))
        XCTAssertEqual(providerRequest.reasoning, AIReasoningConfig.effort(.low))
        XCTAssertEqual(providerRequest.providerOptions?["includeThoughts"], .bool(true))
    }

    func testAITextRequestToProviderRequestUsesFallbackModel() throws {
        let request = AITextRequest(
            messages: [.user("Hello")],
            model: nil // No model specified
        )

        let providerRequest = try request.toProviderRequest(modelId: "fallback-model")

        XCTAssertEqual(providerRequest.modelId, "fallback-model")
    }
}

// MARK: - Mock ProviderClient for Testing

/// A mock implementation of ProviderClient for testing purposes
final class MockProviderClient: ProviderClient, @unchecked Sendable {
    var providerId: String = "mock"
    var displayName: String = "Mock Provider"
    var baseURL: URL = URL(string: "https://api.mock.com")!

    var _healthStatus: ProviderHealthStatus = .healthy
    var healthStatus: ProviderHealthStatus {
        get async { _healthStatus }
    }

    var _isAvailable: Bool = true
    var isAvailable: Bool {
        get async { _isAvailable }
    }

    var _availableModels: [String] = ["mock-model-1", "mock-model-2"]
    var availableModels: [String] {
        get async throws { _availableModels }
    }

    var executeHandler: ((ProviderRequest) async throws -> ProviderResponse)?
    var streamHandler: ((ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error>)?

    func execute(request: ProviderRequest) async throws -> ProviderResponse {
        if let handler = executeHandler {
            return try await handler(request)
        }
        return ProviderResponse(
            id: "mock-id",
            model: request.modelId,
            provider: providerId,
            content: "Mock response",
            usage: .zero,
            finishReason: .stop
        )
    }

    func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        if let handler = streamHandler {
            return handler(request)
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("Mock "))
            continuation.yield(.textDelta("stream"))
            continuation.yield(.finish(reason: .stop, usage: .zero))
            continuation.finish()
        }
    }

    func capabilities(for modelId: String) async -> LLMCapabilities? {
        return [.text, .streaming]
    }
}

final class MockProviderClientTests: XCTestCase {

    func testMockProviderClientDefaults() async throws {
        let client = MockProviderClient()

        XCTAssertEqual(client.providerId, "mock")
        XCTAssertEqual(client.displayName, "Mock Provider")

        let health = await client.healthStatus
        XCTAssertEqual(health, .healthy)

        let isAvailable = await client.isAvailable
        XCTAssertTrue(isAvailable)

        let models = try await client.availableModels
        XCTAssertEqual(models, ["mock-model-1", "mock-model-2"])
    }

    func testMockProviderClientExecute() async throws {
        let client = MockProviderClient()
        let request = ProviderRequest(
            modelId: "test-model",
            messages: [.user("Hello")]
        )

        let response = try await client.execute(request: request)

        XCTAssertEqual(response.id, "mock-id")
        XCTAssertEqual(response.model, "test-model")
        XCTAssertEqual(response.content, "Mock response")
    }

    func testMockProviderClientCustomHandler() async throws {
        let client = MockProviderClient()
        client.executeHandler = { request in
            ProviderResponse(
                id: "custom-id",
                model: request.modelId,
                provider: "custom",
                content: "Custom response for \(request.modelId)",
                usage: ProviderUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .stop
            )
        }

        let request = ProviderRequest(
            modelId: "my-model",
            messages: [.user("Test")]
        )

        let response = try await client.execute(request: request)

        XCTAssertEqual(response.id, "custom-id")
        XCTAssertEqual(response.content, "Custom response for my-model")
        XCTAssertEqual(response.usage?.totalTokens, 15)
    }

    func testMockProviderClientStream() async throws {
        let client = MockProviderClient()
        let request = ProviderRequest(
            modelId: "test-model",
            messages: [.user("Hello")]
        )

        var events: [ProviderStreamEvent] = []
        for try await event in client.stream(request: request) {
            events.append(event)
        }

        XCTAssertEqual(events.count, 3)
    }

    func testMockProviderClientIsModelAvailable() async {
        let client = MockProviderClient()

        let available1 = await client.isModelAvailable("mock-model-1")
        XCTAssertTrue(available1)

        let available2 = await client.isModelAvailable("unknown-model")
        XCTAssertFalse(available2)
    }

    func testMockProviderClientCapabilities() async {
        let client = MockProviderClient()

        let caps = await client.capabilities(for: "any-model")
        XCTAssertNotNil(caps)
        XCTAssertTrue(caps!.contains(.text))
        XCTAssertTrue(caps!.contains(.streaming))
    }
}
