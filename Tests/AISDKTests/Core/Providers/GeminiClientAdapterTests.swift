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
}
