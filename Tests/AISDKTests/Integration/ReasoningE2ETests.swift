//
//  ReasoningE2ETests.swift
//  AISDKTests
//
//  End-to-end tests validating that AIReasoningConfig flows through
//  provider adapters to real APIs and produces valid responses.
//

import Foundation
import XCTest
@testable import AISDK

final class ReasoningE2ETests: XCTestCase {

    // MARK: - Helpers

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
        loadEnvironmentVariables()
        guard let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"],
              !key.isEmpty else {
            throw XCTSkip("ANTHROPIC_API_KEY required for Anthropic reasoning tests")
        }
        return key
    }

    private func openAIKeyOrSkip() throws -> String {
        loadEnvironmentVariables()
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !key.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY required for OpenAI reasoning tests")
        }
        return key
    }

    // MARK: - Anthropic Reasoning E2E

    func test_anthropic_reasoning_low_effort_returns_response() async throws {
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "claude-opus-4-20250514",
            messages: [
                .user("What is 15 * 17? Answer with just the number.")
            ],
            maxTokens: 4096,
            reasoning: AIReasoningConfig.effort(.low)
        )

        let response = try await client.execute(request: request)

        XCTAssertFalse(response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Anthropic reasoning (low effort) should return content")
        XCTAssertTrue(response.content.contains("255"),
                      "Expected 255 in response: \(response.content)")
        print("  Anthropic reasoning low effort: \(response.content)")
    }

    func test_anthropic_reasoning_explicit_budget_returns_response() async throws {
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "claude-opus-4-20250514",
            messages: [
                .user("What is the square root of 144? Just the number.")
            ],
            maxTokens: 4096,
            reasoning: AIReasoningConfig(budgetTokens: 2048)
        )

        let response = try await client.execute(request: request)

        XCTAssertFalse(response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Anthropic reasoning (explicit budget) should return content")
        XCTAssertTrue(response.content.contains("12"),
                      "Expected 12 in response: \(response.content)")
        print("  Anthropic reasoning explicit budget: \(response.content)")
    }

    func test_anthropic_reasoning_streaming_emits_thinking_deltas() async throws {
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "claude-opus-4-20250514",
            messages: [
                .user("What is 7 + 8? Just the number.")
            ],
            maxTokens: 4096,
            stream: true,
            reasoning: AIReasoningConfig.effort(.low)
        )

        var hasReasoningDelta = false
        var textChunks: [String] = []
        var finishReason: ProviderFinishReason?

        for try await event in client.stream(request: request) {
            switch event {
            case .reasoningDelta:
                hasReasoningDelta = true
            case .textDelta(let text):
                textChunks.append(text)
            case .finish(let reason, _):
                finishReason = reason
            default:
                break
            }
        }

        XCTAssertTrue(hasReasoningDelta,
                      "Streaming with reasoning should emit reasoningDelta events")
        let combined = textChunks.joined()
        XCTAssertFalse(combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Streaming should produce text content")
        XCTAssertTrue(combined.contains("15"),
                      "Expected 15 in streamed response: \(combined)")
        XCTAssertNotNil(finishReason, "Stream should finish with a reason")
        print("  Anthropic reasoning streaming: \(combined)")
    }

    func test_anthropic_reasoning_ignored_for_sonnet() async throws {
        let apiKey = try anthropicKeyOrSkip()
        let client = AnthropicClientAdapter(apiKey: apiKey)

        // Reasoning config should be silently ignored for non-opus models
        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [
                .user("Say hello in one word.")
            ],
            maxTokens: 1000,
            reasoning: AIReasoningConfig.effort(.high)
        )

        let response = try await client.execute(request: request)

        XCTAssertFalse(response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "Sonnet should respond even with reasoning config (ignored)")
        print("  Anthropic reasoning ignored for sonnet: \(response.content)")
    }

    // MARK: - OpenAI Reasoning E2E

    func test_openai_reasoning_low_effort_returns_response() async throws {
        let apiKey = try openAIKeyOrSkip()
        let client = OpenAIClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "o4-mini",
            messages: [
                .user("What is 12 * 13? Answer with just the number.")
            ],
            maxTokens: 4096,
            reasoning: AIReasoningConfig.effort(.low)
        )

        let response = try await client.execute(request: request)

        XCTAssertFalse(response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "OpenAI reasoning (low effort) should return content")
        XCTAssertTrue(response.content.contains("156"),
                      "Expected 156 in response: \(response.content)")
        print("  OpenAI reasoning low effort: \(response.content)")
    }

    func test_openai_reasoning_high_effort_returns_response() async throws {
        let apiKey = try openAIKeyOrSkip()
        let client = OpenAIClientAdapter(apiKey: apiKey)

        let request = ProviderRequest(
            modelId: "o4-mini",
            messages: [
                .user("What is 99 * 101? Answer with just the number.")
            ],
            maxTokens: 4096,
            reasoning: AIReasoningConfig.effort(.high)
        )

        let response = try await client.execute(request: request)

        XCTAssertFalse(response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "OpenAI reasoning (high effort) should return content")
        XCTAssertTrue(response.content.contains("9999"),
                      "Expected 9999 in response: \(response.content)")
        print("  OpenAI reasoning high effort: \(response.content)")
    }

    func test_openai_reasoning_ignored_for_gpt4o() async throws {
        let apiKey = try openAIKeyOrSkip()
        let client = OpenAIClientAdapter(apiKey: apiKey)

        // Reasoning config should be silently ignored for non-o-series models
        let request = ProviderRequest(
            modelId: "gpt-4o-mini",
            messages: [
                .user("Say hello in one word.")
            ],
            maxTokens: 500,
            reasoning: AIReasoningConfig.effort(.medium)
        )

        let response = try await client.execute(request: request)

        XCTAssertFalse(response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "gpt-4o-mini should respond even with reasoning config (ignored)")
        print("  OpenAI reasoning ignored for gpt-4o-mini: \(response.content)")
    }
}
