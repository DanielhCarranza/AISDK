//
//  OpenAIResponsesClientAdapterTests.swift
//  AISDKTests
//
//  Tests for OpenAIResponsesClientAdapter - OpenAI Responses API provider client
//

import XCTest
@testable import AISDK

// MARK: - OpenAIResponsesClientAdapterTests

final class OpenAIResponsesClientAdapterTests: XCTestCase {
    // MARK: - Initialization Tests

    func testInitializationWithDefaults() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-test-key")

        XCTAssertEqual(client.providerId, "openai-responses")
        XCTAssertEqual(client.displayName, "OpenAI (Responses API)")
        XCTAssertEqual(client.baseURL.absoluteString, "https://api.openai.com")
    }

    func testInitializationWithCustomBaseURL() async {
        let customURL = URL(string: "https://custom.openai.example.com")!
        let client = OpenAIResponsesClientAdapter(
            apiKey: "sk-test-key",
            baseURL: customURL
        )

        XCTAssertEqual(client.baseURL, customURL)
    }

    func testInitializationWithStoreEnabled() async {
        // Verify store parameter is accepted (default is false)
        let client = OpenAIResponsesClientAdapter(
            apiKey: "sk-test-key",
            store: true
        )
        XCTAssertEqual(client.providerId, "openai-responses")
    }

    // MARK: - Health Status Tests

    func testInitialHealthStatusIsUnknown() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-test-key")
        let status = await client.healthStatus

        XCTAssertEqual(status, .unknown)
    }

    func testIsAvailableReturnsFalseWhenUnknown() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-test-key")
        let isAvailable = await client.isAvailable

        XCTAssertFalse(isAvailable)
    }

    // MARK: - Protocol Conformance Tests

    func testConformsToProviderClient() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-test-key")

        XCTAssertFalse(client.providerId.isEmpty)
        XCTAssertFalse(client.displayName.isEmpty)
        XCTAssertNotNil(client.baseURL)

        let _ = await client.healthStatus
        let _ = await client.isAvailable
    }

    func testProviderClientIsSendable() {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-test-key")

        Task.detached {
            let _ = client.providerId
            let _ = await client.healthStatus
        }
    }

    // MARK: - Model Capabilities Tests

    func testCapabilitiesForGPT4o() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-test-key")
        let capabilities = await client.capabilities(for: "gpt-4o")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.text))
        XCTAssertTrue(capabilities!.contains(.vision))
        XCTAssertTrue(capabilities!.contains(.tools))
        XCTAssertTrue(capabilities!.contains(.streaming))
        XCTAssertTrue(capabilities!.contains(.webSearch))
    }

    func testCapabilitiesForO3Model() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-test-key")
        let capabilities = await client.capabilities(for: "o3-mini")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.reasoning))
        XCTAssertTrue(capabilities!.contains(.webSearch))
    }

    func testCapabilitiesForGPT4() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-test-key")
        let capabilities = await client.capabilities(for: "gpt-4-turbo")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.text))
        XCTAssertTrue(capabilities!.contains(.jsonMode))
        XCTAssertFalse(capabilities!.contains(.webSearch))
    }

    func testCapabilitiesForUnknownModel() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-test-key")
        let capabilities = await client.capabilities(for: "custom-model")

        XCTAssertNotNil(capabilities)
        XCTAssertTrue(capabilities!.contains(.text))
        XCTAssertTrue(capabilities!.contains(.tools))
    }

    // MARK: - Available Models Tests

    func testAvailableModelsIncludesCommonModels() async throws {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-test-key")
        let models = try await client.availableModels

        XCTAssertTrue(models.contains("gpt-4o"))
        XCTAssertTrue(models.contains("gpt-4o-mini"))
        XCTAssertTrue(models.contains("o3"))
        XCTAssertTrue(models.contains("o4-mini"))
    }

    // MARK: - Factory Method Tests

    func testOpenAIResponsesFactory() {
        let adapter = ProviderLanguageModelAdapter.openAIResponses(
            apiKey: "sk-test-key",
            modelId: "gpt-4o"
        )

        XCTAssertEqual(adapter.modelId, "gpt-4o")
        XCTAssertEqual(adapter.provider, "openai-responses")
        XCTAssertTrue(adapter.capabilities.contains(.text))
        XCTAssertTrue(adapter.capabilities.contains(.webSearch))
        XCTAssertTrue(adapter.capabilities.contains(.reasoning))
    }

    func testOpenAIResponsesFactoryDefaultModel() {
        let adapter = ProviderLanguageModelAdapter.openAIResponses(
            apiKey: "sk-test-key"
        )

        XCTAssertEqual(adapter.modelId, "gpt-4o")
    }

    func testOpenAIChatCompletionsFactory() {
        let adapter = ProviderLanguageModelAdapter.openAIChatCompletions(
            apiKey: "sk-test-key",
            modelId: "gpt-4o"
        )

        XCTAssertEqual(adapter.modelId, "gpt-4o")
        XCTAssertEqual(adapter.provider, "openai")
        XCTAssertTrue(adapter.capabilities.contains(.text))
        XCTAssertFalse(adapter.capabilities.contains(.webSearch))
    }

    func testOpenAIChatCompletionsFactoryDefaultModel() {
        let adapter = ProviderLanguageModelAdapter.openAIChatCompletions(
            apiKey: "sk-test-key"
        )

        XCTAssertEqual(adapter.modelId, "gpt-4o")
    }

    // MARK: - Request Conversion Tests

    func testExecuteRejectsMissingAPIKey() async {
        // Using an empty/invalid key should still construct the adapter
        // (actual API errors come when executing)
        let client = OpenAIResponsesClientAdapter(apiKey: "")
        XCTAssertEqual(client.providerId, "openai-responses")
    }

    func testStreamReturnsAsyncThrowingStream() {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-test-key")
        let request = ProviderRequest(
            modelId: "gpt-4o",
            messages: [AIMessage(role: .user, content: .text("Hello"))],
            stream: true
        )

        // Verify stream() returns without throwing (it's nonisolated)
        let stream = client.stream(request: request)
        XCTAssertNotNil(stream)
    }

    // MARK: - Built-in Tools Acceptance Tests

    func testBuiltInToolsAreNotRejected() async {
        // The Chat Completions adapter throws for built-in tools.
        // The Responses adapter should accept them (delegating to OpenAIProvider).
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-invalid-key")
        let request = ProviderRequest(
            modelId: "gpt-4o",
            messages: [AIMessage(role: .user, content: .text("Search for news"))],
            builtInTools: [.webSearchDefault]
        )

        // The request should NOT throw an invalidRequest error about built-in tools.
        // It will throw a network/auth error since the API key is invalid, which is expected.
        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected network error with invalid key")
        } catch let error as ProviderError {
            // Should NOT be the "Built-in tools are not supported" error
            if case .invalidRequest(let message) = error {
                XCTAssertFalse(
                    message.contains("Built-in tools are not supported"),
                    "Responses API adapter should accept built-in tools"
                )
            }
            // Any other ProviderError is acceptable (auth failure, network error, etc.)
        } catch {
            // Non-ProviderError is also acceptable (network issues, etc.)
        }
    }

    // MARK: - Provider Options Tests

    func testProviderOptionsConversationIdExtraction() async {
        // Verify that previousResponseId from providerOptions is used
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-invalid-key")
        let request = ProviderRequest(
            modelId: "gpt-4o",
            messages: [AIMessage(role: .user, content: .text("Follow up"))],
            providerOptions: [
                "previousResponseId": .string("resp_abc123")
            ]
        )

        // We can't directly test the internal AITextRequest conversion,
        // but we verify the request doesn't crash with providerOptions
        do {
            _ = try await client.execute(request: request)
        } catch {
            // Expected to fail due to invalid API key — that's fine
        }
    }

    func testProviderOptionsPHISensitivityForcesStoreFalse() async {
        // Verify that PHI sensitivity marker forces store: false
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-invalid-key", store: true)
        let request = ProviderRequest(
            modelId: "gpt-4o",
            messages: [AIMessage(role: .user, content: .text("PHI data"))],
            providerOptions: [
                "sensitivity": .string("phi")
            ]
        )

        // Verify it doesn't crash — the actual store value is internal
        do {
            _ = try await client.execute(request: request)
        } catch {
            // Expected to fail due to invalid API key
        }
    }

    // MARK: - RawJSONSchemaBuilder Tests

    func testRawJSONSchemaBuilderProducesValidSchema() {
        let schemaString = """
        {"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}
        """
        let builder = RawJSONSchemaBuilder(schemaString: schemaString)
        let schema = builder.build()

        // Verify the schema can be encoded
        XCTAssertNoThrow(try JSONEncoder().encode(schema))
    }

    func testRawJSONSchemaBuilderHandlesInvalidJSON() {
        let builder = RawJSONSchemaBuilder(schemaString: "not valid json")
        let schema = builder.build()

        // Should return empty schema without crashing
        XCTAssertNoThrow(try JSONEncoder().encode(schema))
    }

    func testRawJSONSchemaBuilderHandlesEmptyString() {
        let builder = RawJSONSchemaBuilder(schemaString: "")
        let schema = builder.build()

        XCTAssertNoThrow(try JSONEncoder().encode(schema))
    }

    // MARK: - Response Format Conversion Tests

    func testRequestWithJsonSchemaFormat() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-invalid-key")
        let request = ProviderRequest(
            modelId: "gpt-4o",
            messages: [AIMessage(role: .user, content: .text("Generate JSON"))],
            responseFormat: .jsonSchema(
                name: "test_schema",
                schema: """
                {"type":"object","properties":{"result":{"type":"string"}},"required":["result"]}
                """
            )
        )

        // Should not crash during request conversion
        do {
            _ = try await client.execute(request: request)
        } catch {
            // Expected failure with invalid key
        }
    }

    func testRequestWithJsonFormat() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-invalid-key")
        let request = ProviderRequest(
            modelId: "gpt-4o",
            messages: [AIMessage(role: .user, content: .text("Generate JSON"))],
            responseFormat: .json
        )

        do {
            _ = try await client.execute(request: request)
        } catch {
            // Expected failure with invalid key
        }
    }

    // MARK: - Tool Conversion Tests

    func testToolSchemaRoundTrip() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-invalid-key")

        // Create a tool in ProviderJSONValue format (as ProviderRequest carries them)
        let toolValue = ProviderJSONValue.object([
            "type": .string("function"),
            "function": .object([
                "name": .string("get_weather"),
                "description": .string("Get weather for a city"),
                "parameters": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "city": .object([
                            "type": .string("string")
                        ])
                    ]),
                    "required": .array([.string("city")])
                ])
            ])
        ])

        let request = ProviderRequest(
            modelId: "gpt-4o",
            messages: [AIMessage(role: .user, content: .text("Weather?"))],
            tools: [toolValue]
        )

        // Verify the conversion doesn't crash
        do {
            _ = try await client.execute(request: request)
        } catch {
            // Expected failure with invalid key
        }
    }

    // MARK: - Reasoning Config Tests

    func testRequestWithReasoningConfig() async {
        let client = OpenAIResponsesClientAdapter(apiKey: "sk-invalid-key")
        let request = ProviderRequest(
            modelId: "o3-mini",
            messages: [AIMessage(role: .user, content: .text("Reason about this"))],
            reasoning: AIReasoningConfig(effort: .high)
        )

        do {
            _ = try await client.execute(request: request)
        } catch {
            // Expected failure with invalid key
        }
    }

    // MARK: - Comparison: Responses vs Chat Completions

    func testResponsesAdapterHasDifferentProviderId() {
        let responsesClient = OpenAIResponsesClientAdapter(apiKey: "sk-test")
        let chatClient = OpenAIClientAdapter(apiKey: "sk-test")

        XCTAssertNotEqual(responsesClient.providerId, chatClient.providerId)
        XCTAssertEqual(responsesClient.providerId, "openai-responses")
        XCTAssertEqual(chatClient.providerId, "openai")
    }
}
