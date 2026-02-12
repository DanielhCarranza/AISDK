//
//  OpenRouterIntegrationTests.swift
//  AISDKTests
//
//  Real API integration tests for OpenRouter models.
//  These tests validate core AISDK behaviors (chat, streaming, JSON output, tools).
//

import Foundation
import XCTest
@testable import AISDK

final class OpenRouterIntegrationTests: XCTestCase {

    // MARK: - Configuration

    private static let defaultModels = [
        "tngtech/deepseek-r1t2-chimera:free",
        "nvidia/nemotron-3-nano-30b-a3b:free",
        "arcee-ai/trinity-mini:free"
    ]

    private static let modelsEnvKey = "OPENROUTER_TEST_MODELS"
    private static let defaultModelEnvKey = "OPENROUTER_DEFAULT_MODEL"
    private static let streamModelEnvKey = "OPENROUTER_STREAM_MODEL"
    private static let toolModelEnvKey = "OPENROUTER_TOOL_MODEL"

    // MARK: - Helpers

    private func apiKeyOrSkip() throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENROUTER_API_KEY environment variable is required for OpenRouter integration tests")
        }
        return apiKey
    }

    private func modelsUnderTest() -> [String] {
        if let raw = ProcessInfo.processInfo.environment[Self.modelsEnvKey],
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let models = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !models.isEmpty {
                return models
            }
        }
        return Self.defaultModels
    }

    private func defaultModel() -> String {
        if let override = ProcessInfo.processInfo.environment[Self.defaultModelEnvKey],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return modelsUnderTest().first ?? "tngtech/deepseek-r1t2-chimera:free"
    }

    private func toolModelOrSkip() throws -> String {
        if let model = ProcessInfo.processInfo.environment[Self.toolModelEnvKey],
           !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return model
        }
        // Default to Trinity Mini which has the best tool calling support on free tier
        // Note: Nemotron works with tool_choice: "auto" but not with specific tool forcing
        // DeepSeek R1T2 Chimera free tier doesn't support tool calling at all
        return "arcee-ai/trinity-mini:free"
    }

    private func streamModel() -> String {
        if let override = ProcessInfo.processInfo.environment[Self.streamModelEnvKey],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return "nvidia/nemotron-3-nano-30b-a3b:free"
    }

    private func createClient() throws -> OpenRouterClient {
        loadEnvironmentVariables()
        let apiKey = try apiKeyOrSkip()
        if ProcessInfo.processInfo.environment["OPENROUTER_DEBUG"] == "1" {
            print("🔐 OpenRouter key loaded (length: \(apiKey.count), prefix: \(apiKey.hasPrefix("sk-or-")))")
        }
        return OpenRouterClient(
            apiKey: apiKey,
            appName: "AISDK-OpenRouterIntegrationTests",
            siteURL: "https://github.com/AISDK"
        )
    }

    private func extractJSONObject(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }
        return nil
    }

    private func loadEnvironmentVariables() {
        let envPath = ".env"
        guard let envContent = try? String(contentsOfFile: envPath) else {
            return
        }

        for line in envContent.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                let parts = trimmedLine.components(separatedBy: "=")
                if parts.count >= 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
                    setenv(key, value, 0)
                }
            }
        }
    }

    // MARK: - Tests

    func test_basic_chat_across_models() async throws {
        let client = try createClient()
        let models = modelsUnderTest()

        for model in models {
            let request = ProviderRequest(
                modelId: model,
                messages: [
                    .system("You are a helpful assistant. Keep replies brief."),
                    .user("Say 'OK' and include the model name you used.")
                ],
                maxTokens: 1000
            )

            let response: ProviderResponse
            do {
                response = try await client.execute(request: request)
            } catch let error as ProviderError {
                if case .rateLimited = error {
                    throw XCTSkip("OpenRouter rate limited this test run")
                }
                throw error
            }
            let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                print("⚠️  [\(model)] Empty content. Raw length: \(response.content.count). Finish: \(response.finishReason). Tool calls: \(response.toolCalls.count). Usage: \(response.usage?.totalTokens ?? 0)")
            }
            XCTAssertFalse(trimmed.isEmpty, "Model \(model) should return content")
            print("✅ [\(model)] \(response.content)")
        }
    }

    func test_streaming_response_default_model() async throws {
        let client = try createClient()
        let model = streamModel()

        let request = ProviderRequest(
            modelId: model,
            messages: [
                .user("Count from 1 to 5, one number per token. No extra words.")
            ],
            maxTokens: 1000,
            stream: true
        )

        var chunks: [String] = []
        var finishReason: ProviderFinishReason?

        for try await event in client.stream(request: request) {
            switch event {
            case .textDelta(let text):
                chunks.append(text)
            case .finish(let reason, _):
                finishReason = reason
            default:
                break
            }
        }

        let combined = chunks.joined()
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            print("⚠️  [\(model)] Streaming yielded no text. Chunks: \(chunks.count)")
        }
        XCTAssertFalse(trimmed.isEmpty, "Streaming should yield text")
        XCTAssertNotNil(finishReason, "Streaming should finish with a reason")
        print("✅ [\(model)] Streamed: \(combined)")
    }

    func test_json_response_default_model() async throws {
        let client = try createClient()
        let model = defaultModel()

        let request = ProviderRequest(
            modelId: model,
            messages: [
                .system("Return only JSON, no code fences."),
                .user("Return JSON with fields {\"capital\": \"Paris\", \"country\": \"France\"}.")
            ],
            maxTokens: 1000,
            responseFormat: .json
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error {
                throw XCTSkip("OpenRouter rate limited this test run")
            }
            if case .invalidRequest(let message) = error,
               message.lowercased().contains("not found") {
                throw XCTSkip("Model \(model) does not support tool calling: \(message)")
            }
            throw error
        }
        if response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("⚠️  [\(model)] JSON response empty. Finish: \(response.finishReason). Usage: \(response.usage?.totalTokens ?? 0)")
        }
        guard let jsonString = extractJSONObject(from: response.content),
              let data = jsonString.data(using: .utf8) else {
            XCTFail("Expected JSON object in response: \(response.content)")
            return
        }

        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = object as? [String: Any] else {
            XCTFail("JSON response was not an object: \(response.content)")
            return
        }

        XCTAssertEqual(dict["capital"] as? String, "Paris")
        XCTAssertEqual(dict["country"] as? String, "France")
        print("✅ [\(model)] JSON response: \(jsonString)")
    }

    func test_reasoning_prompt_default_model() async throws {
        let client = try createClient()
        let model = defaultModel()

        let request = ProviderRequest(
            modelId: model,
            messages: [
                .system("Answer with a short justification. Do not reveal chain-of-thought."),
                .user("You buy 3 apples at $2 each and get $1 off. What is the total?")
            ],
            maxTokens: 1000
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            switch error {
            case .rateLimited:
                throw XCTSkip("OpenRouter rate limited this test run")
            case .invalidRequest(let message):
                let lower = message.lowercased()
                if lower.contains("not found") || lower.contains("tool") || lower.contains("unsupported") {
                    throw XCTSkip("Model \(model) does not support tool calling: \(message)")
                }
            case .modelNotFound(let message):
                throw XCTSkip("Model \(model) not available for tool calling: \(message)")
            default:
                break
            }
            throw error
        } catch {
            let description = String(describing: error).lowercased()
            if description.contains("not found") || description.contains("tool") || description.contains("unsupported") {
                throw XCTSkip("Model \(model) does not support tool calling: \(error)")
            }
            throw error
        }
        let trimmed = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            print("⚠️  [\(model)] Reasoning response empty. Finish: \(response.finishReason). Usage: \(response.usage?.totalTokens ?? 0)")
        }
        XCTAssertFalse(trimmed.isEmpty, "Reasoning prompt should return content")
        XCTAssertTrue(trimmed.contains("5") || trimmed.contains("$5"),
                      "Expected total to be 5: \(response.content)")
        print("✅ [\(model)] Reasoning response: \(response.content)")
    }

    func test_tool_calling_with_configured_model() async throws {
        let client = try createClient()
        let model = try toolModelOrSkip()

        let tool = ProviderJSONValue.object([
            "type": .string("function"),
            "function": .object([
                "name": .string("get_weather"),
                "description": .string("Get weather for a city"),
                "parameters": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "city": .object(["type": .string("string")]),
                        "unit": .object([
                            "type": .string("string"),
                            "enum": .array([.string("celsius"), .string("fahrenheit")])
                        ])
                    ]),
                    "required": .array([.string("city"), .string("unit")])
                ])
            ])
        ])

        // Use tool_choice: .auto for broader model compatibility
        // Note: Forcing specific tools with .tool(name:) only works on some models
        // (Trinity Mini supports it, but Nemotron/DeepSeek free tiers don't)
        let request = ProviderRequest(
            modelId: model,
            messages: [
                .system("You must use the get_weather tool. Do not respond with plain text."),
                .user("What is the weather in Boston? Use celsius as the unit.")
            ],
            maxTokens: 1000,
            tools: [tool],
            toolChoice: .auto
        )

        let response = try await client.execute(request: request)
        XCTAssertFalse(response.toolCalls.isEmpty, "Expected a tool call from \(model)")

        let toolCall = response.toolCalls.first
        XCTAssertEqual(toolCall?.name, "get_weather")
        XCTAssertTrue((toolCall?.arguments ?? "").lowercased().contains("boston"))
        print("✅ [\(model)] Tool call: \(toolCall?.arguments ?? "no-args")")
    }
}
