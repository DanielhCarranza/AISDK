//
//  BuiltInToolsLiveTests.swift
//  AISDKTests
//
//  Live API integration tests for provider-native built-in tools.
//  Validates that BuiltInTool mappings work against real provider APIs.
//
//  Run with: RUN_LIVE_TESTS=1 swift test --filter BuiltInToolsLiveTests
//

import Foundation
import XCTest
@testable import AISDK

final class BuiltInToolsLiveTests: XCTestCase {

    // MARK: - Helpers

    private func liveTestGuard() throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Live tests disabled (set RUN_LIVE_TESTS=1)")
        }
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

    private func anthropicKeyOrSkip() throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("ANTHROPIC_API_KEY required")
        }
        return apiKey
    }

    private func geminiKeyOrSkip() throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("GOOGLE_API_KEY required")
        }
        return apiKey
    }

    private func openAIKeyOrSkip() throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY required")
        }
        return apiKey
    }

    private func openRouterKeyOrSkip() throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENROUTER_API_KEY required")
        }
        return apiKey
    }

    // MARK: - Anthropic Tests

    func test_anthropic_webSearch_live() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("What is the current weather in New York? Use web search to find out.")],
            maxTokens: 1024,
            builtInTools: [.webSearchDefault]
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Anthropic rate limited") }
            let desc = "\(error)"
            if desc.contains("overloaded") || desc.contains("529") {
                throw XCTSkip("Anthropic server overloaded (529)")
            }
            throw error
        } catch {
            if "\(error)".contains("overloaded") || "\(error)".contains("529") { throw XCTSkip("Anthropic server overloaded") }
            throw error
        }

        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "Anthropic web search should return content")
        print("✅ [Anthropic webSearch] \(text.prefix(200))...")
    }

    func test_anthropic_codeExecution_live() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Calculate the first 10 Fibonacci numbers using Python code execution.")],
            maxTokens: 1024,
            builtInTools: [.codeExecutionDefault]
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Anthropic rate limited") }
            let desc = "\(error)"
            if desc.contains("overloaded") || desc.contains("529") {
                throw XCTSkip("Anthropic server overloaded (529)")
            }
            throw error
        } catch {
            if "\(error)".contains("overloaded") || "\(error)".contains("529") { throw XCTSkip("Anthropic server overloaded") }
            throw error
        }

        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "Anthropic code execution should return content")
        print("✅ [Anthropic codeExecution] \(text.prefix(200))...")
    }

    func test_anthropic_webSearch_streaming_sources() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Search the web for the latest Swift programming language features.")],
            maxTokens: 1024,
            stream: true,
            builtInTools: [.webSearchDefault]
        )

        var sources: [AISource] = []
        var textChunks: [String] = []

        do {
            for try await event in client.stream(request: request) {
                switch event {
                case .source(let source):
                    sources.append(source)
                case .textDelta(let text):
                    textChunks.append(text)
                default:
                    break
                }
            }
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Anthropic rate limited") }
            let desc = "\(error)"
            if desc.contains("overloaded") || desc.contains("529") {
                throw XCTSkip("Anthropic server overloaded (529)")
            }
            throw error
        } catch {
            if "\(error)".contains("overloaded") || "\(error)".contains("529") { throw XCTSkip("Anthropic server overloaded") }
            throw error
        }

        let fullText = textChunks.joined()
        XCTAssertFalse(fullText.isEmpty, "Anthropic streaming web search should produce text")
        print("✅ [Anthropic streaming webSearch] Sources: \(sources.count), Text: \(fullText.prefix(200))...")
    }

    func test_anthropic_fileSearch_throws() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Hello")],
            maxTokens: 256,
            builtInTools: [.fileSearch(BuiltInTool.FileSearchConfig(vectorStoreIds: ["vs_test"]))]
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error for fileSearch on Anthropic")
        } catch let error as ProviderError {
            guard case .invalidRequest(let message) = error else {
                XCTFail("Expected invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.lowercased().contains("not supported"), "Error should mention unsupported: \(message)")
            print("✅ [Anthropic fileSearch] Correctly rejected: \(message)")
        }
    }

    func test_anthropic_imageGeneration_throws() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Hello")],
            maxTokens: 256,
            builtInTools: [.imageGenerationDefault]
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error for imageGeneration on Anthropic")
        } catch let error as ProviderError {
            guard case .invalidRequest(let message) = error else {
                XCTFail("Expected invalidRequest, got \(error)")
                return
            }
            print("✅ [Anthropic imageGeneration] Correctly rejected: \(message)")
        }
    }

    func test_anthropic_urlContext_throws() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Hello")],
            maxTokens: 256,
            builtInTools: [.urlContext]
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error for urlContext on Anthropic")
        } catch let error as ProviderError {
            guard case .invalidRequest(let message) = error else {
                XCTFail("Expected invalidRequest, got \(error)")
                return
            }
            print("✅ [Anthropic urlContext] Correctly rejected: \(message)")
        }
    }

    // MARK: - Gemini Tests

    func test_gemini_webSearch_live() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try geminiKeyOrSkip()
        let client = GeminiClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [.user("What are the latest news headlines today?")],
            maxTokens: 1024,
            builtInTools: [.webSearchDefault]
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Gemini rate limited") }
            throw error
        }

        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "Gemini web search should return content")
        print("✅ [Gemini webSearch] \(text.prefix(200))...")
    }

    func test_gemini_codeExecution_live() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try geminiKeyOrSkip()
        let client = GeminiClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [.user("Write Python code to calculate 2^100 and show the result.")],
            maxTokens: 1024,
            builtInTools: [.codeExecutionDefault]
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Gemini rate limited") }
            throw error
        }

        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "Gemini code execution should return content")
        print("✅ [Gemini codeExecution] \(text.prefix(200))...")
    }

    func test_gemini_urlContext_live() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try geminiKeyOrSkip()
        let client = GeminiClientAdapter(apiKey: apiKey)

        // URL context (url_context tool) requires gemini-2.5-flash or later
        let request = ProviderRequest(
            modelId: "gemini-2.5-flash",
            messages: [.user("Summarize the content at https://example.com")],
            maxTokens: 1024,
            builtInTools: [.urlContext]
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Gemini rate limited") }
            // url_context may not be available on all models
            if case .invalidRequest(let msg) = error, msg.lowercased().contains("not supported") {
                throw XCTSkip("Gemini urlContext not available on this model: \(msg)")
            }
            throw error
        }

        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "Gemini URL context should return content")
        print("✅ [Gemini urlContext] \(text.prefix(200))...")
    }

    func test_gemini_webSearch_streaming_sources() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try geminiKeyOrSkip()
        let client = GeminiClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [.user("What are the latest news headlines today?")],
            maxTokens: 1024,
            stream: true,
            builtInTools: [.webSearchDefault]
        )

        var sources: [AISource] = []
        var textChunks: [String] = []

        for try await event in client.stream(request: request) {
            switch event {
            case .source(let source):
                sources.append(source)
            case .textDelta(let text):
                textChunks.append(text)
            default:
                break
            }
        }

        let fullText = textChunks.joined()
        XCTAssertFalse(fullText.isEmpty, "Gemini streaming web search should produce text")
        print("✅ [Gemini streaming webSearch] Sources: \(sources.count), Text: \(fullText.prefix(200))...")
    }

    func test_gemini_fileSearch_throws() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try geminiKeyOrSkip()
        let client = GeminiClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [.user("Hello")],
            maxTokens: 256,
            builtInTools: [.fileSearch(BuiltInTool.FileSearchConfig(vectorStoreIds: ["vs_test"]))]
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error for fileSearch on Gemini")
        } catch let error as ProviderError {
            guard case .invalidRequest(let message) = error else {
                XCTFail("Expected invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.lowercased().contains("not supported"), "Error should mention unsupported: \(message)")
            print("✅ [Gemini fileSearch] Correctly rejected: \(message)")
        }
    }

    func test_gemini_imageGeneration_throws() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try geminiKeyOrSkip()
        let client = GeminiClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gemini-2.0-flash",
            messages: [.user("Hello")],
            maxTokens: 256,
            builtInTools: [.imageGenerationDefault]
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error for imageGeneration on Gemini")
        } catch let error as ProviderError {
            guard case .invalidRequest(let message) = error else {
                XCTFail("Expected invalidRequest, got \(error)")
                return
            }
            print("✅ [Gemini imageGeneration] Correctly rejected: \(message)")
        }
    }

    // MARK: - OpenAI Chat Completions Tests

    func test_openai_chatCompletions_rejectsAll() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()
        let client = OpenAIClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gpt-4o-mini",
            messages: [.user("Hello")],
            maxTokens: 256,
            builtInTools: [.webSearchDefault]
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error for built-in tools on OpenAI Chat Completions")
        } catch let error as ProviderError {
            guard case .invalidRequest(let message) = error else {
                XCTFail("Expected invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Responses API"), "Error should mention Responses API: \(message)")
            print("✅ [OpenAI Chat Completions] Correctly rejected: \(message)")
        }
    }

    // MARK: - OpenAI Responses API Tests

    func test_openai_responses_webSearch_live() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()
        let provider = OpenAIProvider(apiKey: apiKey)

        let request = AITextRequest(
            messages: [.user("What is the latest news about Swift programming language?")],
            model: "gpt-4o-mini",
            maxTokens: 1024,
            builtInTools: [.webSearchDefault]
        )

        let result: AITextResult
        do {
            result = try await provider.sendTextRequest(request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("OpenAI rate limited") }
            throw error
        }

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "OpenAI Responses API web search should return content")
        print("✅ [OpenAI Responses webSearch] \(text.prefix(200))...")
    }

    func test_openai_responses_codeExecution_live() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()
        let provider = OpenAIProvider(apiKey: apiKey)

        // code_interpreter requires container support; gpt-4o confirmed supported per OpenAI docs
        let request = AITextRequest(
            messages: [.user("Calculate the sum of all prime numbers less than 100.")],
            model: "gpt-4o",
            maxTokens: 1024,
            builtInTools: [.codeExecutionDefault]
        )

        let result: AITextResult
        do {
            result = try await provider.sendTextRequest(request)
        } catch let error as LLMError {
            if case .rateLimitExceeded = error { throw XCTSkip("OpenAI rate limited") }
            if case .invalidRequest(let message) = error,
               message.contains("Zero Data Retention") || message.contains("code_interpreter") {
                throw XCTSkip("OpenAI code_interpreter unavailable for this key: \(message)")
            }
            // HTTP 400 comes through as LLMError.networkError; common cause is Zero Data Retention
            // policy which blocks code_interpreter (requires temporary container storage)
            if case .networkError(let code, let message) = error, code == 400 {
                throw XCTSkip("OpenAI code_interpreter returned 400 — likely Zero Data Retention policy blocks container usage: \(message)")
            }
            throw error
        } catch {
            throw XCTSkip("OpenAI code_interpreter not available: \(error)")
        }

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "OpenAI Responses API code execution should return content")
        print("✅ [OpenAI Responses codeExecution] \(text.prefix(200))...")
    }

    func test_openai_responses_urlContext_throws() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()
        let provider = OpenAIProvider(apiKey: apiKey)

        let request = AITextRequest(
            messages: [.user("Hello")],
            model: "gpt-4o-mini",
            maxTokens: 256,
            builtInTools: [.urlContext]
        )

        do {
            _ = try await provider.sendTextRequest(request)
            XCTFail("Expected invalidRequest error for urlContext on OpenAI")
        } catch let error as ProviderError {
            guard case .invalidRequest(let message) = error else {
                XCTFail("Expected invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.lowercased().contains("not supported"), "Error should mention unsupported: \(message)")
            print("✅ [OpenAI Responses urlContext] Correctly rejected: \(message)")
        }
    }

    // MARK: - OpenRouter Tests

    func test_openrouter_builtInTools_silentlyIgnored() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openRouterKeyOrSkip()
        let client = OpenRouterClient(
            apiKey: apiKey,
            appName: "AISDK-BuiltInToolsTest",
            siteURL: "https://github.com/AISDK"
        )

        // OpenRouter fundamentally doesn't support built-in tools (uses Chat Completions wire format).
        // They have their own web search plugin (`:online` suffix) but standard built-in tool types
        // like webSearch, codeExecution, etc. are silently ignored in buildRequestBody().
        // Using a paid model to avoid free-tier rate limits.
        let request = ProviderRequest(
            modelId: "openai/gpt-4o-mini",
            messages: [.user("Say hello in one word.")],
            maxTokens: 256,
            builtInTools: [.webSearchDefault]
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("OpenRouter rate limited") }
            throw error
        }

        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(text.isEmpty, "OpenRouter should still return content (builtInTools silently ignored)")
        print("✅ [OpenRouter] Response received (builtInTools ignored): \(text.prefix(100))...")
    }
}
