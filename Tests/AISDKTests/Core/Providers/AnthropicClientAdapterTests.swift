//
//  AnthropicClientAdapterTests.swift
//  AISDKTests
//
//  Tests for AnthropicClientAdapter reasoning mapping
//

import XCTest
@testable import AISDK

final class AnthropicClientAdapterTests: XCTestCase {
    func testUnifiedReasoningEffortLowMapsToMinimumBudget() async throws {
        let captured = await captureAnthropicRequest(
            modelId: "claude-opus-4-20250514",
            maxTokens: 4096,
            reasoning: AIReasoningConfig.effort(.low),
            betaConfiguration: .none
        )

        let thinking = captured.body["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["budget_tokens"] as? Int, 1024)
    }

    func testUnifiedReasoningEffortHighUsesHalfMaxTokens() async throws {
        let captured = await captureAnthropicRequest(
            modelId: "claude-opus-4-20250514",
            maxTokens: 6000,
            reasoning: AIReasoningConfig.effort(.high),
            betaConfiguration: .none
        )

        let thinking = captured.body["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["budget_tokens"] as? Int, 3000)
    }

    func testUnifiedReasoningBudgetOverridesEffort() async throws {
        let reasoning = AIReasoningConfig(effort: .high, budgetTokens: 2048)
        let captured = await captureAnthropicRequest(
            modelId: "claude-opus-4-20250514",
            maxTokens: 8000,
            reasoning: reasoning,
            betaConfiguration: .none
        )

        let thinking = captured.body["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["budget_tokens"] as? Int, 2048)
    }

    func testUnifiedReasoningUsesDefaultMaxTokensWhenNil() async throws {
        let captured = await captureAnthropicRequest(
            modelId: "claude-opus-4-20250514",
            maxTokens: nil,
            reasoning: AIReasoningConfig.effort(.high),
            betaConfiguration: .none
        )

        let thinking = captured.body["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["budget_tokens"] as? Int, 2048)
    }

    func testUnifiedReasoningSkippedWhenMaxTokensTooSmall() async throws {
        let captured = await captureAnthropicRequest(
            modelId: "claude-opus-4-20250514",
            maxTokens: 1024,
            reasoning: AIReasoningConfig.effort(.high),
            betaConfiguration: .none
        )

        XCTAssertNil(captured.body["thinking"])
    }

    func testUnifiedReasoningIgnoredForNonReasoningModel() async throws {
        let captured = await captureAnthropicRequest(
            modelId: "claude-3-haiku-20240307",
            maxTokens: 4096,
            reasoning: AIReasoningConfig.effort(.medium),
            betaConfiguration: .none
        )

        XCTAssertNil(captured.body["thinking"])
        XCTAssertNil(captured.betaHeader)
    }

    func testReasoningAddsThinkingBetaHeaderWhenNeeded() async throws {
        let captured = await captureAnthropicRequest(
            modelId: "claude-opus-4-20250514",
            maxTokens: 4096,
            reasoning: AIReasoningConfig.effort(.low),
            betaConfiguration: .none
        )

        XCTAssertTrue(captured.betaHeader?.contains("interleaved-thinking-2025-05-14") ?? false)
    }

    func testUnifiedReasoningOverridesAdapterThinking() async throws {
        let captured = await captureAnthropicRequest(
            modelId: "claude-opus-4-20250514",
            maxTokens: 4096,
            reasoning: AIReasoningConfig(budgetTokens: 2048),
            betaConfiguration: .init(extendedThinking: true)
        )

        let thinking = captured.body["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["budget_tokens"] as? Int, 2048)
    }

    func testInvalidThinkingBudgetThrows() async {
        let session = makeMockSession()
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test", session: session)
        let request = ProviderRequest(
            modelId: "claude-opus-4-20250514",
            messages: [AIMessage(role: .user, content: .text("Hello"))],
            maxTokens: 2000,
            reasoning: AIReasoningConfig(budgetTokens: 512)
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error")
        } catch let error as LLMError {
            guard case .invalidRequest = error else {
                XCTFail("Expected invalidRequest error")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testThinkingBudgetMustBeLessThanMaxTokens() async {
        let session = makeMockSession()
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test", session: session)
        let request = ProviderRequest(
            modelId: "claude-opus-4-20250514",
            messages: [AIMessage(role: .user, content: .text("Hello"))],
            maxTokens: 1500,
            reasoning: AIReasoningConfig(budgetTokens: 1500)
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error")
        } catch let error as LLMError {
            guard case .invalidRequest = error else {
                XCTFail("Expected invalidRequest error")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Helpers

private struct AnthropicCapturedRequest {
    let body: [String: Any]
    let betaHeader: String?
}

private func makeMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func readRequestBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return Data()
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: bufferSize)
        if count > 0 {
            data.append(buffer, count: count)
        } else {
            break
        }
    }
    return data
}

private func captureAnthropicRequest(
    modelId: String,
    maxTokens: Int?,
    reasoning: AIReasoningConfig,
    betaConfiguration: BetaConfiguration
) async -> AnthropicCapturedRequest {
    MockURLProtocol.reset()
    let session = makeMockSession()
    let client = AnthropicClientAdapter(
        apiKey: "sk-ant-test",
        session: session,
        betaConfiguration: betaConfiguration
    )

    var capturedBody: [String: Any] = [:]
    var capturedBetaHeader: String?

    MockURLProtocol.requestHandler = { request in
        let bodyData = readRequestBody(request)
        if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            capturedBody = json
        }
        capturedBetaHeader = request.value(forHTTPHeaderField: "anthropic-beta")

        let responseJSON = """
        {
            "id": "msg_1",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "ok"}],
            "model": "\(modelId)",
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 1, "output_tokens": 1}
        }
        """.data(using: .utf8) ?? Data()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, responseJSON)
    }

    let providerRequest = ProviderRequest(
        modelId: modelId,
        messages: [AIMessage(role: .user, content: .text("Hello"))],
        maxTokens: maxTokens,
        reasoning: reasoning
    )

    _ = try? await client.execute(request: providerRequest)
    return AnthropicCapturedRequest(body: capturedBody, betaHeader: capturedBetaHeader)
}
