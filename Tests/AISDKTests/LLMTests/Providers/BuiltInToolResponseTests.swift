//
//  BuiltInToolResponseTests.swift
//  AISDKTests
//
//  Tests for parsing built-in tool responses in provider adapters
//

import XCTest
@testable import AISDK

final class BuiltInToolResponseTests: XCTestCase {

    func testAnthropicWebSearchResponseParsing() async throws {
        let session = makeMockSession()
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test", session: session)

        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let responseJSON = """
            {
                "id": "msg_1",
                "type": "message",
                "role": "assistant",
                "content": [
                    {"type": "text", "text": "Results:"},
                    {"type": "web_search_tool_result", "tool_use_id": "tool_1", "content": [
                        {"type": "web_search_result", "title": "Example", "url": "https://example.com", "page_age": "1d"}
                    ]}
                ],
                "model": "claude-sonnet-4-20250514",
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
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Hello")],
            maxTokens: 256
        )

        let response = try await client.execute(request: providerRequest)
        XCTAssertTrue(response.content.contains("Example"))
        XCTAssertTrue(response.content.contains("https://example.com"))
    }

    func testAnthropicServerToolUseBlock() async throws {
        let session = makeMockSession()
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test", session: session)

        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let responseJSON = """
            {
                "id": "msg_1",
                "type": "message",
                "role": "assistant",
                "content": [
                    {"type": "server_tool_use", "id": "srv_1", "name": "web_search", "input": {"query": "test"}},
                    {"type": "text", "text": "Done"}
                ],
                "model": "claude-sonnet-4-20250514",
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
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Hello")],
            maxTokens: 256
        )

        let response = try await client.execute(request: providerRequest)
        XCTAssertTrue(response.content.contains("Done"))
    }

    func testAnthropicWebSearchResultBlock() async throws {
        let session = makeMockSession()
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test", session: session)

        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let responseJSON = """
            {
                "id": "msg_1",
                "type": "message",
                "role": "assistant",
                "content": [
                    {"type": "web_search_tool_result", "tool_use_id": "tool_1", "content": [
                        {"type": "web_search_result", "title": "AISDK", "url": "https://example.org"}
                    ]}
                ],
                "model": "claude-sonnet-4-20250514",
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
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Hello")],
            maxTokens: 256
        )

        let response = try await client.execute(request: providerRequest)
        XCTAssertTrue(response.content.contains("AISDK"))
        XCTAssertTrue(response.content.contains("https://example.org"))
    }

    func testAnthropicStreamWebSearchEvents() async throws {
        let session = makeMockSession()
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test", session: session)

        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let stream = """
            data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-sonnet-4-20250514","usage":{"input_tokens":1,"output_tokens":1}}}
            
            data: {"type":"content_block_start","index":0,"content_block":{"type":"web_search_tool_result","tool_use_id":"tool_1","content":[{"type":"web_search_result","title":"Example","url":"https://example.com","page_age":"1d"}]}}
            
            data: {"type":"message_stop"}
            
            """.data(using: .utf8) ?? Data()

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.anthropic.com/v1/messages")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, stream)
        }

        let providerRequest = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Hello")],
            maxTokens: 256
        )

        var sources: [AISource] = []
        for try await event in client.stream(request: providerRequest) {
            if case .source(let source) = event {
                sources.append(source)
            }
        }

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.url, "https://example.com")
        XCTAssertEqual(sources.first?.title, "Example")
    }

    func testGeminiGroundingMetadataParsing() async throws {
        let session = makeMockSession()
        let client = GeminiClientAdapter(apiKey: "test-api-key", session: session)

        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let chunk = """
            {"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]},"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://example.com","title":"Example"}}]}}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1,"totalTokenCount":2},"modelVersion":"gemini-2.5-pro","responseId":"resp-1"}
            """
            let sse = "data: \(chunk)\n\n"
            let data = sse.data(using: .utf8) ?? Data()

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let providerRequest = ProviderRequest(
            modelId: "gemini-2.5-pro",
            messages: [.user("Hello")]
        )

        var sources: [AISource] = []
        for try await event in client.stream(request: providerRequest) {
            if case .source(let source) = event {
                sources.append(source)
            }
        }

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.url, "https://example.com")
        XCTAssertEqual(sources.first?.title, "Example")
    }

    func testGeminiCodeExecutionResultParsing() async throws {
        let session = makeMockSession()
        let client = GeminiClientAdapter(apiKey: "test-api-key", session: session)

        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let responseJSON = """
            {
                "candidates": [{
                    "content": {
                        "role": "model",
                        "parts": [
                            {"code_execution_result": {"outcome": "success", "output": "ok"}}
                        ]
                    },
                    "finishReason": "STOP"
                }],
                "usageMetadata": {"promptTokenCount": 1, "candidatesTokenCount": 1, "totalTokenCount": 2},
                "modelVersion": "gemini-2.5-pro",
                "responseId": "resp-1"
            }
            """.data(using: .utf8) ?? Data()

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseJSON)
        }

        let providerRequest = ProviderRequest(
            modelId: "gemini-2.5-pro",
            messages: [.user("Hello")]
        )

        let response = try await client.execute(request: providerRequest)
        XCTAssertTrue(response.content.contains("ok"))
    }

    func testGeminiExecutableCodePart() async throws {
        let session = makeMockSession()
        let client = GeminiClientAdapter(apiKey: "test-api-key", session: session)

        MockURLProtocol.reset()
        MockURLProtocol.requestHandler = { request in
            let responseJSON = """
            {
                "candidates": [{
                    "content": {
                        "role": "model",
                        "parts": [
                            {"executable_code": {"language": "python", "code": "print('hi')"}}
                        ]
                    },
                    "finishReason": "STOP"
                }],
                "usageMetadata": {"promptTokenCount": 1, "candidatesTokenCount": 1, "totalTokenCount": 2},
                "modelVersion": "gemini-2.5-pro",
                "responseId": "resp-1"
            }
            """.data(using: .utf8) ?? Data()

            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, responseJSON)
        }

        let providerRequest = ProviderRequest(
            modelId: "gemini-2.5-pro",
            messages: [.user("Hello")]
        )

        let response = try await client.execute(request: providerRequest)
        XCTAssertTrue(response.content.contains("print('hi')"))
    }
}

// MARK: - Helpers

private func makeMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}
