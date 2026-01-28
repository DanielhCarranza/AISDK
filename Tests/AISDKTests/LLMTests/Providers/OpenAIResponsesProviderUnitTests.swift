//
//  OpenAIResponsesProviderUnitTests.swift
//  AISDKTests
//
//  Unit tests for OpenAIProvider Responses API conversions
//

import Foundation
import XCTest
@testable import AISDK

final class OpenAIResponsesProviderUnitTests: XCTestCase {

    private var provider: OpenAIProvider!

    override func setUp() {
        super.setUp()
        provider = OpenAIProvider(apiKey: "test-key")
    }

    override func tearDown() {
        provider = nil
        super.tearDown()
    }

    // MARK: - Request Conversion

    func testConvertToResponseRequest_SystemPromptMapsToInstructions() throws {
        let request = AITextRequest(
            messages: [
                AIMessage(role: .system, content: .text("You are helpful.")),
                AIMessage(role: .user, content: .text("Hello"))
            ],
            model: "gpt-4o-mini"
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        XCTAssertEqual(responseRequest.instructions, "You are helpful.")

        if case .string(let text) = responseRequest.input {
            XCTAssertEqual(text, "Hello")
        } else {
            XCTFail("Expected string input for single user text message")
        }
    }

    func testConvertToResponseRequest_MultiMessageBecomesItems() throws {
        let request = AITextRequest(
            messages: [
                AIMessage(role: .user, content: .text("Hi")),
                AIMessage(role: .assistant, content: .text("Hello"))
            ],
            model: "gpt-4o-mini"
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        if case .items(let items) = responseRequest.input {
            XCTAssertEqual(items.count, 2)
        } else {
            XCTFail("Expected items input for multi-message request")
        }
    }

    func testConvertToResponseRequest_ToolOutputConversion() throws {
        let request = AITextRequest(
            messages: [
                AIMessage(role: .tool, content: .text("Result"), toolCallId: "call_1")
            ],
            model: "gpt-4o-mini"
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        if case .items(let items) = responseRequest.input {
            guard case .functionCallOutput(let output) = items.first else {
                XCTFail("Expected function call output item")
                return
            }
            XCTAssertEqual(output.callId, "call_1")
            XCTAssertEqual(output.output, "Result")
        } else {
            XCTFail("Expected items input for tool output")
        }
    }

    func testConvertToResponseRequest_ProviderOptions() throws {
        var options = OpenAIRequestOptions()
        options.store = true
        options.background = true
        options.serviceTier = .auto
        options.reasoning = ReasoningConfig(effort: .high, summary: .detailed)
        options.webSearch = WebSearchConfig(enabled: true, searchContextSize: .high)
        options.fileSearch = FileSearchConfig(vectorStoreIds: ["vs_1", "vs_2"], maxNumResults: 3)
        options.codeInterpreter = CodeInterpreterConfig(enabled: true)

        var request = AITextRequest(
            messages: [AIMessage(role: .user, content: .text("Search and compute"))],
            model: "gpt-4o-mini"
        )
        request.providerOptions = options

        let responseRequest = try provider.convertToResponseRequest(request)
        XCTAssertEqual(responseRequest.store, true)
        XCTAssertEqual(responseRequest.background, true)
        XCTAssertEqual(responseRequest.serviceTier, ServiceTier.auto.rawValue)
        XCTAssertEqual(responseRequest.reasoning?.effort, ReasoningConfig.ReasoningEffort.high.rawValue)
        XCTAssertEqual(responseRequest.reasoning?.summary, ReasoningConfig.ReasoningSummary.detailed.rawValue)

        let toolTypes = responseRequest.tools?.compactMap { tool -> String in
            switch tool {
            case .webSearchPreview: return "web"
            case .fileSearch: return "file"
            case .codeInterpreter: return "code"
            case .imageGeneration, .mcp, .function: return "other"
            }
        } ?? []

        XCTAssertTrue(toolTypes.contains("web"))
        XCTAssertTrue(toolTypes.contains("file"))
        XCTAssertTrue(toolTypes.contains("code"))
    }

    func testConvertToResponseRequest_ModelFallback() throws {
        let request = AITextRequest(
            messages: [AIMessage(role: .user, content: .text("Hello"))]
        )

        let responseRequest = try provider.convertToResponseRequest(request)
        XCTAssertEqual(responseRequest.model, provider.model.name)
    }

    // MARK: - Response Conversion

    func testConvertToAITextResult_ExtractsTextAndToolCalls() {
        let response = ResponsesAPIFixtures.makeToolCallResponse()
        let result = provider.convertToAITextResult(response)

        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls.first?.name, "get_weather")
        XCTAssertEqual(result.toolCalls.first?.id, "call_abc")
        XCTAssertTrue(result.toolCalls.first?.arguments.contains("Tokyo") ?? false)
    }

    func testConvertToAITextResult_TextAndUsage() {
        let response = ResponsesAPIFixtures.makeResponse(text: "Hello!")
        let result = provider.convertToAITextResult(response)

        XCTAssertEqual(result.text, "Hello!")
        XCTAssertEqual(result.usage.promptTokens, 10)
        XCTAssertEqual(result.usage.completionTokens, 20)
        XCTAssertEqual(result.finishReason, .stop)
    }
}
