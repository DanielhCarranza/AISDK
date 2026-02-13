//
//  BuiltInToolMappingTests.swift
//  AISDKTests
//
//  Tests for provider mapping of core BuiltInTool configuration
//

import XCTest
@testable import AISDK

final class BuiltInToolMappingTests: XCTestCase {

    func testOpenAIChatCompletionsRejectsBuiltInTools() async throws {
        let client = OpenAIClientAdapter(apiKey: "sk-test")
        let request = ProviderRequest(
            modelId: "gpt-4o",
            messages: [.user("Hello")],
            builtInTools: [.webSearchDefault]
        )

        do {
            _ = try await client.execute(request: request)
            XCTFail("Expected invalidRequest error")
        } catch let error as ProviderError {
            guard case .invalidRequest(let message) = error else {
                XCTFail("Expected invalidRequest error")
                return
            }
            XCTAssertTrue(message.contains("Responses API"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGeminiWebSearchMapping() async throws {
        let body = await captureGeminiRequestBody(builtInTools: [.webSearchDefault], tools: nil)
        let tools = body["tools"] as? [[String: Any]]
        XCTAssertTrue(tools?.contains(where: { $0["google_search"] != nil }) ?? false)
    }

    func testGeminiCodeExecutionMapping() async throws {
        let body = await captureGeminiRequestBody(builtInTools: [.codeExecutionDefault], tools: nil)
        let tools = body["tools"] as? [[String: Any]]
        XCTAssertTrue(tools?.contains(where: { $0["code_execution"] != nil }) ?? false)
    }

    func testGeminiUrlContextMapping() async throws {
        let body = await captureGeminiRequestBody(builtInTools: [.urlContext], tools: nil)
        let tools = body["tools"] as? [[String: Any]]
        XCTAssertTrue(tools?.contains(where: { $0["url_context"] != nil }) ?? false)
    }

    func testGeminiRejectsFileSearch() async throws {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let request = ProviderRequest(
            modelId: "gemini-2.5-pro",
            messages: [.user("Hello")],
            builtInTools: [.fileSearch(BuiltInTool.FileSearchConfig(vectorStoreIds: ["vs_1"]))]
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

    func testGeminiRejectsImageGeneration() async throws {
        let client = GeminiClientAdapter(apiKey: "test-api-key")
        let request = ProviderRequest(
            modelId: "gemini-2.5-pro",
            messages: [.user("Hello")],
            builtInTools: [.imageGenerationDefault]
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

    func testGeminiBuiltInToolsAlongsideFunctionTools() async throws {
        let function = ToolFunction(
            name: "search",
            description: "Search",
            parameters: Parameters(
                type: "object",
                properties: ["query": PropertyDefinition(type: "string")],
                required: ["query"]
            )
        )
        let schema = ToolSchema(type: "function", function: function)
        let tools = try [schema.toProviderJSONValue()]

        let body = await captureGeminiRequestBody(builtInTools: [.webSearchDefault], tools: tools)
        let toolsArray = body["tools"] as? [[String: Any]]
        XCTAssertTrue(toolsArray?.contains(where: { $0["functionDeclarations"] != nil }) ?? false)
        XCTAssertTrue(toolsArray?.contains(where: { $0["google_search"] != nil }) ?? false)
    }

    func testAnthropicWebSearchMapping() async throws {
        let config = BuiltInTool.WebSearchConfig(maxUses: 2)
        let captured = await captureAnthropicRequest(builtInTools: [.webSearch(config)])
        let tools = captured.body["tools"] as? [[String: Any]]
        let webTool = tools?.first { $0["type"] as? String == "web_search_20250305" }
        XCTAssertEqual(webTool?["name"] as? String, "web_search")
        XCTAssertEqual(webTool?["max_uses"] as? Int, 2)
    }

    func testAnthropicWebSearchWithFullConfig() async throws {
        let location = BuiltInTool.UserLocation(city: "Seattle", region: "WA", country: "US", timezone: "America/Los_Angeles")
        let config = BuiltInTool.WebSearchConfig(
            maxUses: 3,
            allowedDomains: ["example.com"],
            blockedDomains: ["ads.example.com"],
            userLocation: location
        )

        let captured = await captureAnthropicRequest(builtInTools: [.webSearch(config)])
        let tools = captured.body["tools"] as? [[String: Any]]
        let webTool = tools?.first { $0["type"] as? String == "web_search_20250305" }
        XCTAssertEqual(webTool?["name"] as? String, "web_search")
        XCTAssertEqual(webTool?["allowed_domains"] as? [String], ["example.com"])
        XCTAssertEqual(webTool?["blocked_domains"] as? [String], ["ads.example.com"])

        let userLocation = webTool?["user_location"] as? [String: String]
        XCTAssertEqual(userLocation?["city"], "Seattle")
        XCTAssertEqual(userLocation?["region"], "WA")
        XCTAssertEqual(userLocation?["country"], "US")
        XCTAssertEqual(userLocation?["timezone"], "America/Los_Angeles")
    }

    func testAnthropicCodeExecutionMapping() async throws {
        let captured = await captureAnthropicRequest(builtInTools: [.codeExecutionDefault])
        let tools = captured.body["tools"] as? [[String: Any]]
        let codeTool = tools?.first { $0["type"] as? String == "code_execution_20250825" }
        XCTAssertEqual(codeTool?["name"] as? String, "code_execution")
    }

    func testAnthropicCodeExecutionBetaHeader() async throws {
        let captured = await captureAnthropicRequest(builtInTools: [.codeExecutionDefault])
        XCTAssertTrue(captured.betaHeader?.contains("code-execution-2025-08-25") ?? false)
    }

    func testAnthropicRejectsFileSearch() async throws {
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test")
        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Hello")],
            builtInTools: [.fileSearch(BuiltInTool.FileSearchConfig(vectorStoreIds: ["vs_1"]))]
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

    func testAnthropicRejectsImageGeneration() async throws {
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test")
        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Hello")],
            builtInTools: [.imageGenerationDefault]
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

    func testAnthropicRejectsUrlContext() async throws {
        let client = AnthropicClientAdapter(apiKey: "sk-ant-test")
        let request = ProviderRequest(
            modelId: "claude-sonnet-4-20250514",
            messages: [.user("Hello")],
            builtInTools: [.urlContext]
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

    func testOpenAIResponsesWebSearchMapping() throws {
        let provider = OpenAIProvider(apiKey: "test")
        let request = AITextRequest(
            messages: [.user("Hello")],
            builtInTools: [.webSearchDefault]
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        guard let tools = responseRequest.tools else {
            XCTFail("Expected tools")
            return
        }
        XCTAssertEqual(tools.count, 1)
        guard case .webSearchPreview = tools[0] else {
            XCTFail("Expected webSearchPreview tool")
            return
        }
    }

    func testOpenAIResponsesCodeInterpreterMapping() throws {
        let provider = OpenAIProvider(apiKey: "test")
        let request = AITextRequest(
            messages: [.user("Hello")],
            builtInTools: [.codeExecutionDefault]
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        guard let tools = responseRequest.tools else {
            XCTFail("Expected tools")
            return
        }
        XCTAssertEqual(tools.count, 1)
        guard case .codeInterpreter = tools[0] else {
            XCTFail("Expected codeInterpreter tool")
            return
        }
    }

    func testOpenAIResponsesFileSearchMapping() throws {
        let provider = OpenAIProvider(apiKey: "test")
        let config = BuiltInTool.FileSearchConfig(vectorStoreIds: ["vs_1", "vs_2"])
        let request = AITextRequest(
            messages: [.user("Hello")],
            builtInTools: [.fileSearch(config)]
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        let vectorStoreIds = responseRequest.tools?.compactMap { tool -> String? in
            if case .fileSearch(let id) = tool { return id }
            return nil
        }
        XCTAssertEqual(vectorStoreIds, ["vs_1", "vs_2"])
    }

    func testOpenAIResponsesImageGenerationMapping() throws {
        let provider = OpenAIProvider(apiKey: "test")
        let config = BuiltInTool.ImageGenerationConfig(partialImages: 2)
        let request = AITextRequest(
            messages: [.user("Hello")],
            builtInTools: [.imageGeneration(config)]
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        guard let tools = responseRequest.tools else {
            XCTFail("Expected tools")
            return
        }
        XCTAssertEqual(tools.count, 1)
        guard case .imageGeneration(let partialImages) = tools[0] else {
            XCTFail("Expected imageGeneration tool")
            return
        }
        XCTAssertEqual(partialImages, 2)
    }

    func testOpenAIResponsesRejectsUrlContext() throws {
        let provider = OpenAIProvider(apiKey: "test")
        let request = AITextRequest(
            messages: [.user("Hello")],
            builtInTools: [.urlContext]
        )

        XCTAssertThrowsError(try provider.convertToResponseRequest(request)) { error in
            guard case ProviderError.invalidRequest = error else {
                XCTFail("Expected invalidRequest error")
                return
            }
        }
    }

    func testOpenAIResponsesMergeWithRequestOptions() throws {
        let provider = OpenAIProvider(apiKey: "test")
        var options = OpenAIRequestOptions()
        options.webSearch = WebSearchConfig()
        options.fileSearch = FileSearchConfig(vectorStoreIds: ["vs_options"])
        options.codeInterpreter = CodeInterpreterConfig()

        let builtInFileSearch = BuiltInTool.FileSearchConfig(vectorStoreIds: ["vs_override"])
        var request = AITextRequest(
            messages: [.user("Hello")],
            builtInTools: [.webSearchDefault, .fileSearch(builtInFileSearch)]
        )
        request.providerOptions = options

        let responseRequest = try provider.convertToResponseRequest(request)
        let fileSearchIds = responseRequest.tools?.compactMap { tool -> String? in
            if case .fileSearch(let id) = tool { return id }
            return nil
        }
        XCTAssertEqual(fileSearchIds, ["vs_override"])

        let toolTypes = responseRequest.tools?.map { tool -> String in
            switch tool {
            case .webSearchPreview:
                return "web_search"
            case .codeInterpreter:
                return "code_interpreter"
            case .fileSearch:
                return "file_search"
            case .imageGeneration:
                return "image_generation"
            case .mcp:
                return "mcp"
            case .computerUsePreview:
                return "computer_use_preview"
            case .function:
                return "function"
            }
        } ?? []

        XCTAssertTrue(toolTypes.contains("web_search"))
        XCTAssertTrue(toolTypes.contains("code_interpreter"))
        XCTAssertTrue(toolTypes.contains("file_search"))
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

private func captureGeminiRequestBody(builtInTools: [BuiltInTool], tools: [ProviderJSONValue]?) async -> [String: Any] {
    MockURLProtocol.reset()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let client = GeminiClientAdapter(apiKey: "test-api-key", session: session)

    var capturedBody: [String: Any] = [:]
    MockURLProtocol.requestHandler = { request in
        let bodyData = readRequestBody(request)
        if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            capturedBody = json
        }

        let responseJSON = """
        {
            "candidates": [{
                "content": {
                    "role": "model",
                    "parts": [{"text": "ok"}]
                },
                "finishReason": "STOP"
            }],
            "usageMetadata": {
                "promptTokenCount": 1,
                "candidatesTokenCount": 1,
                "totalTokenCount": 2
            },
            "modelVersion": "gemini-2.5-pro",
            "responseId": "resp-test"
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
        messages: [.user("Hello")],
        tools: tools,
        builtInTools: builtInTools
    )

    _ = try? await client.execute(request: providerRequest)
    return capturedBody
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
