//
//  ProviderTestSuite.swift
//  AISDKTestRunner
//
//  Tests for provider adapters: OpenAI, Anthropic, Gemini via OpenRouter
//

import Foundation
import AISDK

public final class ProviderTestSuite: TestSuiteProtocol {
    public let reporter: TestReporter
    public let verbose: Bool
    private let suiteName = "Providers"
    private let provider: String?
    private let model: String?
    private let reasoningDisplay: ReasoningDisplay

    public init(reporter: TestReporter, verbose: Bool, provider: String? = nil, model: String? = nil, reasoningDisplay: ReasoningDisplay) {
        self.reporter = reporter
        self.verbose = verbose
        self.provider = provider
        self.model = model
        self.reasoningDisplay = reasoningDisplay
    }

    public func run() async throws {
        reporter.log("Starting provider adapter tests...")

        // Run tests based on provider filter
        let runAll = provider == nil

        if runAll || provider == "openai" {
            await runOpenAITests()
        }

        if runAll || provider == "anthropic" {
            await runAnthropicTests()
        }

        if runAll || provider == "gemini" {
            await runGeminiTests()
        }

        if runAll || provider == "openrouter" {
            await runOpenRouterTests()
        }
    }

    // MARK: - OpenAI Tests (via OpenRouter)

    private func runOpenAITests() async {
        reporter.printSubsection("OpenAI Provider Tests")

        await testOpenAIBasicCompletion()
        await testOpenAIStreaming()
        await testOpenAIToolCalling()
    }

    private func testOpenAIBasicCompletion() async {
        await withTimer("OpenAI basic completion", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "OpenAI basic", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "openai/gpt-4o-mini"
            reporter.debug("Testing model: \(modelId)")

            let request = ProviderRequest(
                modelId: modelId,
                messages: [
                    .system("You are a helpful assistant."),
                    .user("Say 'Hello from OpenAI' in exactly those words.")
                ],
                maxTokens: 2000
            )

            let response = try await client.execute(request: request)

            guard !response.content.isEmpty else {
                throw TestError.assertionFailed("Empty response from \(modelId). Model returned: \(response.model), finishReason: \(response.finishReason.rawValue)")
            }

            reporter.log("Response: \(response.content.prefix(50))")
            if let usage = response.usage {
                reporter.log("Tokens: \(usage.totalTokens)")
            }
        }
    }

    private func testOpenAIStreaming() async {
        await withTimer("OpenAI streaming", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "OpenAI streaming", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "openai/gpt-4o-mini"
            reporter.debug("Testing model: \(modelId)")

            let request = ProviderRequest(
                modelId: modelId,
                messages: [
                    .user("Count from 1 to 5.")
                ],
                maxTokens: 2000,
                stream: true
            )

            var chunkCount = 0
            var responseText = ""

            for try await event in client.stream(request: request) {
                switch event {
                case .textDelta(let text):
                    chunkCount += 1
                    responseText += text
                default:
                    break
                }
            }

            guard chunkCount > 0 else {
                throw TestError.assertionFailed("No chunks received from \(modelId)")
            }

            reporter.log("Received \(chunkCount) chunks: \(responseText.prefix(30))...")
        }
    }

    private func testOpenAIToolCalling() async {
        await withTimer("OpenAI tool calling", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "OpenAI tools", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "openai/gpt-4o-mini"

            let weatherTool = ProviderJSONValue.object([
                "type": .string("function"),
                "function": .object([
                    "name": .string("get_weather"),
                    "description": .string("Get weather for a location"),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "location": .object(["type": .string("string"), "description": .string("City name")])
                        ]),
                        "required": .array([.string("location")])
                    ])
                ])
            ])

            let request = ProviderRequest(
                modelId: modelId,
                messages: [
                    .user("What's the weather in Tokyo?")
                ],
                maxTokens: 2000,
                tools: [weatherTool],
                toolChoice: .auto
            )

            let response = try await client.execute(request: request)

            if !response.toolCalls.isEmpty {
                reporter.log("Tool called: \(response.toolCalls.first?.name ?? "unknown")")
            } else {
                reporter.log("Response: \(response.content.prefix(50))")
            }
        }
    }

    // MARK: - Anthropic Tests (via OpenRouter)

    private func runAnthropicTests() async {
        reporter.printSubsection("Anthropic Provider Tests")

        await testAnthropicBasicCompletion()
        await testAnthropicStreamingWithThinking()
        await testAnthropicToolCalling()
    }

    private func testAnthropicBasicCompletion() async {
        await withTimer("Anthropic basic completion", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "Anthropic basic", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "anthropic/claude-haiku-4.5"
            reporter.debug("Testing model: \(modelId)")

            let request = ProviderRequest(
                modelId: modelId,
                messages: [
                    .user("Say 'Hello from Anthropic' in exactly those words.")
                ],
                maxTokens: 2000
            )

            let response = try await client.execute(request: request)

            guard !response.content.isEmpty else {
                throw TestError.assertionFailed("Empty response from \(modelId). Model returned: \(response.model), finishReason: \(response.finishReason.rawValue)")
            }

            reporter.log("Response: \(response.content.prefix(50))")
        }
    }

    private func testAnthropicStreamingWithThinking() async {
        await withTimer("Anthropic streaming", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "Anthropic streaming", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "anthropic/claude-haiku-4.5"

            let request = ProviderRequest(
                modelId: modelId,
                messages: [
                    .user("What is 15 + 27?")
                ],
                maxTokens: 2000,
                stream: true
            )

            var chunkCount = 0
            var responseText = ""

            for try await event in client.stream(request: request) {
                switch event {
                case .textDelta(let text):
                    chunkCount += 1
                    responseText += text
                default:
                    break
                }
            }

            guard chunkCount > 0 else {
                throw TestError.assertionFailed("No text chunks received")
            }

            reporter.log("Chunks: \(chunkCount)")
            reporter.log("Response: \(responseText.prefix(50))...")
        }
    }

    private func testAnthropicToolCalling() async {
        await withTimer("Anthropic tool calling", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "Anthropic tools", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "anthropic/claude-haiku-4.5"

            let calculatorTool = ProviderJSONValue.object([
                "type": .string("function"),
                "function": .object([
                    "name": .string("calculate"),
                    "description": .string("Perform a mathematical calculation"),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "expression": .object(["type": .string("string"), "description": .string("Math expression")])
                        ]),
                        "required": .array([.string("expression")])
                    ])
                ])
            ])

            let request = ProviderRequest(
                modelId: modelId,
                messages: [
                    .user("Calculate 15 * 7")
                ],
                maxTokens: 2000,
                tools: [calculatorTool],
                toolChoice: .auto
            )

            let response = try await client.execute(request: request)

            if !response.toolCalls.isEmpty {
                reporter.log("Tool called: \(response.toolCalls.first?.name ?? "unknown")")
            } else {
                reporter.log("Response: \(response.content.prefix(50))")
            }
        }
    }

    // MARK: - Gemini Tests (via OpenRouter)

    private func runGeminiTests() async {
        reporter.printSubsection("Gemini Provider Tests")

        await testGeminiBasicCompletion()
        await testGeminiStreaming()
        await testGeminiToolCalling()
    }

    private func testGeminiBasicCompletion() async {
        await withTimer("Gemini basic completion", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "Gemini basic", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "google/gemini-2.0-flash-001"
            reporter.debug("Testing model: \(modelId)")

            let request = ProviderRequest(
                modelId: modelId,
                messages: [
                    .user("Say 'Hello from Gemini' in exactly those words.")
                ],
                maxTokens: 2000
            )

            let response = try await client.execute(request: request)

            guard !response.content.isEmpty else {
                throw TestError.assertionFailed("Empty response from \(modelId). Model returned: \(response.model), finishReason: \(response.finishReason.rawValue)")
            }

            reporter.log("Response: \(response.content.prefix(50))")
        }
    }

    private func testGeminiStreaming() async {
        await withTimer("Gemini streaming", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "Gemini streaming", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "google/gemini-2.0-flash-001"

            let request = ProviderRequest(
                modelId: modelId,
                messages: [
                    .user("Count from 1 to 5, one number per line.")
                ],
                maxTokens: 2000,
                stream: true
            )

            var chunkCount = 0
            var responseText = ""

            for try await event in client.stream(request: request) {
                switch event {
                case .textDelta(let text):
                    chunkCount += 1
                    responseText += text
                default:
                    break
                }
            }

            guard chunkCount > 0 else {
                throw TestError.assertionFailed("No chunks received")
            }

            reporter.log("Received \(chunkCount) chunks: \(responseText.prefix(30))...")
        }
    }

    private func testGeminiToolCalling() async {
        await withTimer("Gemini tool calling", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "Gemini tools", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "google/gemini-2.0-flash-001"

            let searchTool = ProviderJSONValue.object([
                "type": .string("function"),
                "function": .object([
                    "name": .string("search"),
                    "description": .string("Search for information"),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "query": .object(["type": .string("string"), "description": .string("Search query")])
                        ]),
                        "required": .array([.string("query")])
                    ])
                ])
            ])

            let request = ProviderRequest(
                modelId: modelId,
                messages: [
                    .user("Search for information about the Eiffel Tower")
                ],
                maxTokens: 2000,
                tools: [searchTool],
                toolChoice: .auto
            )

            let response = try await client.execute(request: request)

            if !response.toolCalls.isEmpty {
                reporter.log("Tool called: \(response.toolCalls.first?.name ?? "unknown")")
            } else {
                reporter.log("Response: \(response.content.prefix(50))")
            }
        }
    }

    // MARK: - OpenRouter Tests

    private func runOpenRouterTests() async {
        reporter.printSubsection("OpenRouter Provider Tests")

        await testOpenRouterBasicCompletion()
        await testOpenRouterMultiProvider()
    }

    private func testOpenRouterBasicCompletion() async {
        await withTimer("OpenRouter basic completion", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "OpenRouter basic", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            let modelId = model ?? "openai/gpt-4o-mini"
            reporter.debug("Testing model: \(modelId)")

            let request = ProviderRequest(
                modelId: modelId,
                messages: [
                    .user("Say 'Hello from OpenRouter' in exactly those words.")
                ],
                maxTokens: 2000
            )

            let response = try await client.execute(request: request)

            guard !response.content.isEmpty else {
                throw TestError.assertionFailed("Empty response from \(modelId). Model returned: \(response.model), finishReason: \(response.finishReason.rawValue)")
            }

            reporter.log("Response: \(response.content.prefix(50))")
        }
    }

    private func testOpenRouterMultiProvider() async {
        await withTimer("OpenRouter multi-provider routing", suiteName) {
            guard let apiKey = requireEnvVar("OPENROUTER_API_KEY") else {
                reporter.recordSkipped(suiteName, "OpenRouter multi", reason: "OPENROUTER_API_KEY not set")
                return
            }

            let client = OpenRouterClient(
                apiKey: apiKey,
                appName: "AISDKTestRunner",
                siteURL: "https://github.com/AISDK"
            )

            // Test multiple providers through OpenRouter
            let models = [
                "openai/gpt-4o-mini",
                "google/gemini-2.0-flash-001"
            ]

            var successCount = 0

            for modelId in models {
                let request = ProviderRequest(
                    modelId: modelId,
                    messages: [.user("Hello")],
                    maxTokens: 10
                )

                do {
                    let response = try await client.execute(request: request)
                    if !response.content.isEmpty {
                        successCount += 1
                        reporter.debug("Model \(modelId): OK")
                    }
                } catch {
                    reporter.debug("Model \(modelId): Failed - \(error)")
                }
            }

            reporter.log("Multi-provider: \(successCount)/\(models.count) models responded")

            guard successCount > 0 else {
                throw TestError.assertionFailed("No models responded")
            }
        }
    }
}
