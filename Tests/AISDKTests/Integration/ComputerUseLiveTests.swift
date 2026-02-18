//
//  ComputerUseLiveTests.swift
//  AISDKTests
//
//  Live API integration tests for computer use tool.
//  Validates that computer use tool mappings work against real provider APIs.
//
//  Run with: RUN_LIVE_TESTS=1 swift test --filter ComputerUseLiveTests
//

import Foundation
import XCTest
@testable import AISDK

final class ComputerUseLiveTests: XCTestCase {

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

    private func openAIKeyOrSkip() throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY required")
        }
        return apiKey
    }

    /// Minimal 1x1 transparent PNG as base64 for mock screenshot results
    private static let minimalScreenshotBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

    // MARK: - OpenAI Computer Use Tests

    func test_openai_computerUse_singleTurn_returnsComputerCall() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()
        let provider = OpenAIProvider(apiKey: apiKey)

        let request = AITextRequest(
            messages: [.user("Take a screenshot of the current screen.")],
            model: "computer-use-preview",
            maxTokens: 1024,
            builtInTools: [.computerUseDefault]
        )

        let result: AITextResult
        do {
            result = try await provider.sendTextRequest(request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("OpenAI rate limited") }
            throw error
        } catch let error as LLMError {
            if case .rateLimitExceeded = error { throw XCTSkip("OpenAI rate limited") }
            if case .networkError(let code, let msg) = error, code == 400 || code == 404 {
                throw XCTSkip("computer-use-preview model not available: \(msg)")
            }
            throw error
        }

        // The model should return a computer_call which becomes a __computer_use__ tool call
        XCTAssertFalse(result.toolCalls.isEmpty, "Model should return at least one tool call")

        let cuCall = result.toolCalls.first { $0.name == "__computer_use__" }
        XCTAssertNotNil(cuCall, "Should have a __computer_use__ tool call")

        if let cuCall = cuCall,
           let data = cuCall.arguments.data(using: .utf8),
           let payload = try? JSONDecoder().decode(ComputerUseOpenAIPayload.self, from: data) {
            XCTAssertEqual(payload.actionType, "screenshot", "Action should be screenshot")
            print("✅ [OpenAI computerUse] Got computer_call: \(payload.actionType)")
        }
    }

    func test_openai_computerUse_withCustomConfig() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()
        let provider = OpenAIProvider(apiKey: apiKey)

        let config = BuiltInTool.ComputerUseConfig(
            displayWidth: 1920,
            displayHeight: 1080,
            environment: .mac
        )

        let request = AITextRequest(
            messages: [.user("Take a screenshot of the screen.")],
            model: "computer-use-preview",
            maxTokens: 1024,
            builtInTools: [.computerUse(config)]
        )

        let result: AITextResult
        do {
            result = try await provider.sendTextRequest(request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("OpenAI rate limited") }
            throw error
        } catch let error as LLMError {
            if case .rateLimitExceeded = error { throw XCTSkip("OpenAI rate limited") }
            if case .networkError(let code, let msg) = error, code == 400 || code == 404 {
                throw XCTSkip("computer-use-preview model not available: \(msg)")
            }
            throw error
        }

        XCTAssertFalse(result.toolCalls.isEmpty, "Model should return at least one tool call")
        let cuCall = result.toolCalls.first { $0.name == "__computer_use__" }
        XCTAssertNotNil(cuCall, "Should have a __computer_use__ tool call with custom config")
        print("✅ [OpenAI computerUse custom config] Got response with \(result.toolCalls.count) tool call(s)")
    }

    func test_openai_computerUse_multiTurn_acceptsScreenshotResult() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()
        let provider = OpenAIProvider(apiKey: apiKey)

        // Turn 1: Get computer_call
        let request1 = AITextRequest(
            messages: [.user("Take a screenshot of the screen.")],
            model: "computer-use-preview",
            maxTokens: 1024,
            builtInTools: [.computerUseDefault]
        )

        let result1: AITextResult
        do {
            result1 = try await provider.sendTextRequest(request1)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("OpenAI rate limited") }
            throw error
        } catch let error as LLMError {
            if case .rateLimitExceeded = error { throw XCTSkip("OpenAI rate limited") }
            if case .networkError(let code, let msg) = error, code == 400 || code == 404 {
                throw XCTSkip("computer-use-preview model not available: \(msg)")
            }
            throw error
        }

        guard let cuCall = result1.toolCalls.first(where: { $0.name == "__computer_use__" }) else {
            throw XCTSkip("Model did not return a computer_call — cannot test multi-turn")
        }

        // Extract callId from the payload
        var callId = cuCall.id
        if let data = cuCall.arguments.data(using: .utf8),
           let payload = try? JSONDecoder().decode(ComputerUseOpenAIPayload.self, from: data),
           let payloadCallId = payload.callId {
            callId = payloadCallId
        }

        // Build the screenshot result payload
        let resultPayload = ComputerUseResultPayload(
            type: "__computer_use_result__",
            screenshot: Self.minimalScreenshotBase64,
            mediaType: "image/png",
            text: nil,
            isError: false,
            callId: callId
        )
        let resultJSON = String(data: try JSONEncoder().encode(resultPayload), encoding: .utf8)!

        // Turn 2: Send full conversation with screenshot result.
        // The provider converts the assistant __computer_use__ tool call into a computer_call
        // input item, and the tool result into a computer_call_output item.
        let messages: [AIMessage] = [
            .user("Take a screenshot of the screen."),
            .assistant("", toolCalls: [AIMessage.ToolCall(id: cuCall.id, name: cuCall.name, arguments: cuCall.arguments)]),
            .tool(resultJSON, toolCallId: cuCall.id)
        ]

        let request2 = AITextRequest(
            messages: messages,
            model: "computer-use-preview",
            maxTokens: 1024,
            builtInTools: [.computerUseDefault]
        )

        let result2: AITextResult
        do {
            result2 = try await provider.sendTextRequest(request2)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("OpenAI rate limited") }
            throw error
        } catch let error as LLMError {
            if case .rateLimitExceeded = error { throw XCTSkip("OpenAI rate limited") }
            throw error
        }

        // The API should accept the result - it may return text or another computer_call
        let hasContent = !result2.text.isEmpty || !result2.toolCalls.isEmpty
        XCTAssertTrue(hasContent, "API should accept screenshot result and continue")
        print("✅ [OpenAI computerUse multi-turn] API accepted screenshot result. Text: \(result2.text.prefix(100))...")
    }

    func test_openai_chatCompletions_computerUse_throws() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()
        let client = OpenAIClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "gpt-4o-mini",
            messages: [.user("Hello")],
            maxTokens: 256,
            builtInTools: [.computerUseDefault]
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error for computerUse on OpenAI Chat Completions")
        } catch let error as ProviderError {
            guard case .invalidRequest(let message) = error else {
                XCTFail("Expected invalidRequest, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("Responses API"), "Error should mention Responses API: \(message)")
            print("✅ [OpenAI Chat Completions computerUse] Correctly rejected: \(message)")
        }
    }

    // MARK: - Anthropic Computer Use Tests

    func test_anthropic_computerUse_singleTurn_returnsToolUse() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let config = BuiltInTool.ComputerUseConfig(
            displayWidth: 1024,
            displayHeight: 768
        )

        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Take a screenshot of the desktop. Respond with the computer tool only.")],
            maxTokens: 1024,
            builtInTools: [.computerUse(config)]
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Anthropic rate limited") }
            throw error
        }

        // Anthropic should accept the request with computer use beta header
        // The model may return a computer tool_use block
        let hasToolCall = !response.toolCalls.isEmpty
        let hasContent = !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        XCTAssertTrue(hasToolCall || hasContent, "Anthropic should return tool calls or content")

        if hasToolCall {
            let computerCall = response.toolCalls.first { $0.name == "computer" }
            XCTAssertNotNil(computerCall, "Tool call should be named 'computer'")
            print("✅ [Anthropic computerUse] Got computer tool call: \(computerCall?.arguments.prefix(100) ?? "nil")")
        } else {
            print("✅ [Anthropic computerUse] Request accepted. Content: \(response.content.prefix(100))...")
        }
    }

    func test_anthropic_computerUseZoom_accepted() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let config = BuiltInTool.ComputerUseConfig(
            displayWidth: 1920,
            displayHeight: 1080,
            enableZoom: true
        )

        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Take a screenshot of the desktop.")],
            maxTokens: 1024,
            builtInTools: [.computerUse(config)]
        )

        let response: ProviderResponse
        do {
            response = try await client.execute(request: request)
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Anthropic rate limited") }
            // computer_20251124 may not be available for all models
            if case .invalidRequest(let msg) = error, msg.contains("not support") || msg.contains("beta") {
                throw XCTSkip("Zoom computer use not available: \(msg)")
            }
            throw error
        }

        let hasContent = !response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasToolCalls = !response.toolCalls.isEmpty
        XCTAssertTrue(hasContent || hasToolCalls, "Anthropic should accept zoom-enabled computer use")
        print("✅ [Anthropic computerUse zoom] Request accepted with computer_20251124")
    }

    func test_anthropic_computerUse_multiTurn_acceptsScreenshotResult() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let config = BuiltInTool.ComputerUseConfig(
            displayWidth: 1024,
            displayHeight: 768
        )

        // Turn 1: Get computer tool_use
        let request1 = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Take a screenshot of the desktop. Use the computer tool.")],
            maxTokens: 1024,
            builtInTools: [.computerUse(config)]
        )

        let response1: ProviderResponse
        do {
            response1 = try await client.execute(request: request1)
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

        guard let computerCall = response1.toolCalls.first(where: { $0.name == "computer" }) else {
            throw XCTSkip("Model did not return a computer tool_use — cannot test multi-turn")
        }

        // Build screenshot result payload
        let resultPayload = ComputerUseResultPayload(
            type: "__computer_use_result__",
            screenshot: Self.minimalScreenshotBase64,
            mediaType: "image/png",
            text: nil,
            isError: false,
            callId: nil
        )
        let resultJSON = String(data: try JSONEncoder().encode(resultPayload), encoding: .utf8)!

        // Turn 2: Send screenshot result back
        let messages: [AIMessage] = [
            .user("Take a screenshot of the desktop. Use the computer tool."),
            .assistant(response1.content, toolCalls: [
                AIMessage.ToolCall(id: computerCall.id, name: computerCall.name, arguments: computerCall.arguments)
            ]),
            .tool(resultJSON, toolCallId: computerCall.id)
        ]

        let request2 = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: messages,
            maxTokens: 1024,
            builtInTools: [.computerUse(config)]
        )

        let response2: ProviderResponse
        do {
            response2 = try await client.execute(request: request2)
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

        let hasContent = !response2.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasToolCalls = !response2.toolCalls.isEmpty
        XCTAssertTrue(hasContent || hasToolCalls, "API should accept screenshot result and continue")
        print("✅ [Anthropic computerUse multi-turn] API accepted screenshot result. Content: \(response2.content.prefix(100))...")
    }

    func test_anthropic_computerUse_streaming() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let config = BuiltInTool.ComputerUseConfig(
            displayWidth: 1024,
            displayHeight: 768
        )

        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Take a screenshot of the desktop.")],
            maxTokens: 1024,
            stream: true,
            builtInTools: [.computerUse(config)]
        )

        var textChunks: [String] = []
        var eventCount = 0

        do {
            for try await event in client.stream(request: request) {
                eventCount += 1
                switch event {
                case .textDelta(let text):
                    textChunks.append(text)
                default:
                    break
                }
            }
        } catch let error as ProviderError {
            if case .rateLimited = error { throw XCTSkip("Anthropic rate limited") }
            throw error
        }

        XCTAssertGreaterThan(eventCount, 0, "Should receive streaming events")
        print("✅ [Anthropic computerUse streaming] Events: \(eventCount), Text: \(textChunks.joined().prefix(100))...")
    }
}
