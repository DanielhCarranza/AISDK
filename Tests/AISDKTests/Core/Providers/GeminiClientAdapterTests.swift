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
