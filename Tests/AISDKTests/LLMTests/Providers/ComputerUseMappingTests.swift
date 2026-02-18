//
//  ComputerUseMappingTests.swift
//  AISDKTests
//
//  Tests for computer use provider mapping (Anthropic, OpenAI, Gemini rejection)
//

import XCTest
@testable import AISDK

final class ComputerUseMappingTests: XCTestCase {

    // MARK: - Gemini Rejection

    func testGeminiRejectsComputerUse() async throws {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let request = ProviderRequest(
            modelId: "gemini-2.5-pro",
            messages: [.user("Hello")],
            builtInTools: [.computerUseDefault]
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error")
        } catch let error as ProviderError {
            guard case .invalidRequest(let message) = error else {
                XCTFail("Expected invalidRequest error, got \(error)")
                return
            }
            XCTAssertTrue(message.contains("computerUse"))
            XCTAssertTrue(message.contains("not supported"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGeminiRejectsComputerUseWithConfig() async throws {
        let config = BuiltInTool.ComputerUseConfig(displayWidth: 1920, displayHeight: 1080)
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let request = ProviderRequest(
            modelId: "gemini-2.5-pro",
            messages: [.user("Hello")],
            builtInTools: [.computerUse(config)]
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error")
        } catch let error as ProviderError {
            guard case .invalidRequest = error else {
                XCTFail("Expected invalidRequest error")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Anthropic Mapping

    func testAnthropicComputerUseDefaultMapping() async throws {
        let captured = await captureAnthropicRequest(builtInTools: [.computerUseDefault])
        let tools = captured.body["tools"] as? [[String: Any]]
        let cuTool = tools?.first { $0["name"] as? String == "computer" }
        XCTAssertNotNil(cuTool)
        XCTAssertEqual(cuTool?["type"] as? String, "computer_20250124")
        XCTAssertEqual(cuTool?["display_width_px"] as? Int, 1024)
        XCTAssertEqual(cuTool?["display_height_px"] as? Int, 768)
    }

    func testAnthropicComputerUseWithConfig() async throws {
        let config = BuiltInTool.ComputerUseConfig(
            displayWidth: 1920,
            displayHeight: 1080,
            environment: .mac,
            displayNumber: 2
        )
        let captured = await captureAnthropicRequest(builtInTools: [.computerUse(config)])
        let tools = captured.body["tools"] as? [[String: Any]]
        let cuTool = tools?.first { $0["name"] as? String == "computer" }
        XCTAssertNotNil(cuTool)
        XCTAssertEqual(cuTool?["type"] as? String, "computer_20250124")
        XCTAssertEqual(cuTool?["display_width_px"] as? Int, 1920)
        XCTAssertEqual(cuTool?["display_height_px"] as? Int, 1080)
    }

    func testAnthropicComputerUseZoomVersionSelection() async throws {
        let config = BuiltInTool.ComputerUseConfig(
            displayWidth: 1920,
            displayHeight: 1080,
            enableZoom: true
        )
        let captured = await captureAnthropicRequest(builtInTools: [.computerUse(config)])
        let tools = captured.body["tools"] as? [[String: Any]]
        let cuTool = tools?.first { $0["name"] as? String == "computer" }
        XCTAssertEqual(cuTool?["type"] as? String, "computer_20251124")
    }

    func testAnthropicComputerUseBetaHeader() async throws {
        let captured = await captureAnthropicRequest(builtInTools: [.computerUseDefault])
        XCTAssertTrue(captured.betaHeader?.contains("computer-use-2025-01-24") ?? false)
    }

    func testAnthropicComputerUseZoomBetaHeader() async throws {
        let config = BuiltInTool.ComputerUseConfig(enableZoom: true)
        let captured = await captureAnthropicRequest(builtInTools: [.computerUse(config)])
        XCTAssertTrue(captured.betaHeader?.contains("computer-use-2025-11-24") ?? false)
    }

    // MARK: - OpenAI Responses Mapping

    func testOpenAIComputerUseDefaultMapping() throws {
        let provider = OpenAIProvider(apiKey: "test")
        let request = AITextRequest(
            messages: [.user("Hello")],
            builtInTools: [.computerUseDefault]
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        guard let tools = responseRequest.tools else {
            XCTFail("Expected tools")
            return
        }
        let cuTool = tools.first { tool in
            if case .computerUsePreview = tool { return true }
            return false
        }
        XCTAssertNotNil(cuTool)
        if case .computerUsePreview(let w, let h, let env) = cuTool {
            XCTAssertEqual(w, 1024)
            XCTAssertEqual(h, 768)
            XCTAssertEqual(env, "browser")
        }
    }

    func testOpenAIComputerUseWithConfig() throws {
        let config = BuiltInTool.ComputerUseConfig(
            displayWidth: 1920,
            displayHeight: 1080,
            environment: .mac
        )
        let provider = OpenAIProvider(apiKey: "test")
        let request = AITextRequest(
            messages: [.user("Hello")],
            builtInTools: [.computerUse(config)]
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        guard let tools = responseRequest.tools else {
            XCTFail("Expected tools")
            return
        }
        let cuTool = tools.first { tool in
            if case .computerUsePreview = tool { return true }
            return false
        }
        if case .computerUsePreview(let w, let h, let env) = cuTool {
            XCTAssertEqual(w, 1920)
            XCTAssertEqual(h, 1080)
            XCTAssertEqual(env, "mac")
        } else {
            XCTFail("Expected computerUsePreview tool")
        }
    }

    func testOpenAIComputerUseAutoTruncation() throws {
        let provider = OpenAIProvider(apiKey: "test")
        let request = AITextRequest(
            messages: [.user("Hello")],
            builtInTools: [.computerUseDefault]
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        XCTAssertEqual(responseRequest.truncation, "auto")
    }

    func testOpenAIComputerUseNoTruncationWithoutTool() throws {
        let provider = OpenAIProvider(apiKey: "test")
        let request = AITextRequest(
            messages: [.user("Hello")],
            builtInTools: [.webSearchDefault]
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        XCTAssertNil(responseRequest.truncation)
    }

    // MARK: - OpenAI Response Parsing (computer_call)

    func testOpenAIComputerCallParsing() throws {
        let provider = OpenAIProvider(apiKey: "test")

        // Create a mock ResponseObject with a computer_call output
        let json = """
        {
            "id": "resp_123",
            "object": "response",
            "created_at": 1700000000,
            "model": "computer-use-preview",
            "status": "completed",
            "output": [{
                "type": "computer_call",
                "id": "cu_1",
                "call_id": "call_abc",
                "status": "completed",
                "action": {
                    "type": "click",
                    "x": 150,
                    "y": 250,
                    "button": "left"
                }
            }]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ResponseObject.self, from: json)
        let result = provider.convertToAITextResult(response)

        XCTAssertEqual(result.toolCalls.count, 1)
        let toolCall = result.toolCalls[0]
        XCTAssertEqual(toolCall.name, "__computer_use__")
        XCTAssertEqual(toolCall.id, "call_abc")

        // Verify the arguments can be decoded as ComputerUseOpenAIPayload
        let payloadData = toolCall.arguments.data(using: .utf8)!
        let payload = try JSONDecoder().decode(ComputerUseOpenAIPayload.self, from: payloadData)
        XCTAssertEqual(payload.actionType, "click")
        XCTAssertEqual(payload.x, 150)
        XCTAssertEqual(payload.y, 250)
        XCTAssertEqual(payload.button, "left")
        XCTAssertEqual(payload.callId, "call_abc")
    }

    func testOpenAIComputerCallWithSafetyChecks() throws {
        let json = """
        {
            "id": "resp_456",
            "object": "response",
            "created_at": 1700000000,
            "model": "computer-use-preview",
            "status": "completed",
            "output": [{
                "type": "computer_call",
                "id": "cu_2",
                "call_id": "call_def",
                "status": "completed",
                "action": {
                    "type": "click",
                    "x": 100,
                    "y": 100,
                    "button": "left"
                },
                "pending_safety_checks": [{
                    "id": "sc_1",
                    "code": "malicious_url",
                    "message": "Suspicious URL detected"
                }]
            }]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ResponseObject.self, from: json)
        let provider = OpenAIProvider(apiKey: "test")
        let result = provider.convertToAITextResult(response)

        let payloadData = result.toolCalls[0].arguments.data(using: .utf8)!
        let payload = try JSONDecoder().decode(ComputerUseOpenAIPayload.self, from: payloadData)
        XCTAssertEqual(payload.safetyChecks?.count, 1)
        XCTAssertEqual(payload.safetyChecks?.first?["code"], "malicious_url")
    }

    // MARK: - ResponseComputerCallOutput

    func testResponseComputerCallOutputEncoding() throws {
        let output = ResponseComputerCallOutput(
            callId: "call_abc",
            output: ResponseComputerCallOutput.ComputerCallOutputContent(
                type: "computer_screenshot",
                imageUrl: "data:image/png;base64,abc123"
            ),
            acknowledgedSafetyChecks: [
                ResponseComputerCallOutput.AcknowledgedSafetyCheck(
                    id: "sc_1", code: "warn", message: "test"
                )
            ]
        )

        let data = try JSONEncoder().encode(output)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "computer_call_output")
        XCTAssertEqual(json?["call_id"] as? String, "call_abc")

        let outputContent = json?["output"] as? [String: Any]
        XCTAssertEqual(outputContent?["type"] as? String, "computer_screenshot")
        XCTAssertEqual(outputContent?["image_url"] as? String, "data:image/png;base64,abc123")

        let checks = json?["acknowledged_safety_checks"] as? [[String: Any]]
        XCTAssertEqual(checks?.count, 1)
        XCTAssertEqual(checks?.first?["id"] as? String, "sc_1")
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

private func captureAnthropicRequest(builtInTools: [BuiltInTool]) async -> AnthropicCapturedRequest {
    MockURLProtocol.reset()
    let session = makeMockSession()
    let client = AnthropicClientAdapter(apiKey: "sk-ant-test", session: session)

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
        builtInTools: builtInTools
    )

    _ = try? await client.execute(request: providerRequest)
    return AnthropicCapturedRequest(body: capturedBody, betaHeader: capturedBetaHeader)
}
