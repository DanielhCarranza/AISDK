//
//  OpenAIResponsesModelsTests.swift
//  AISDKTests
//
//  Model encoding/decoding tests for OpenAI Responses API
//

import Foundation
import XCTest
@testable import AISDK

final class OpenAIResponsesModelsTests: XCTestCase {

    private var encoder: JSONEncoder!
    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    override func tearDown() {
        encoder = nil
        decoder = nil
        super.tearDown()
    }

    // MARK: - ResponseRequest Encoding

    func testResponseRequestEncoding_AllFields() throws {
        let function = ToolFunction(
            name: "get_weather",
            description: "Get weather",
            parameters: Parameters(
                type: "object",
                properties: [
                    "location": PropertyDefinition(type: "string", description: "City")
                ],
                required: ["location"]
            )
        )

        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .items([
                .message(ResponseMessage(
                    role: "user",
                    content: [
                        .inputText(ResponseInputText(text: "Hello")),
                        .inputImage(ResponseInputImage(imageUrl: "https://example.com/image.png", detail: "high")),
                        .inputFile(ResponseInputFile(fileId: "file_123"))
                    ]
                )),
                .functionCallOutput(ResponseFunctionCallOutput(callId: "call_1", output: "Result")),
                .itemReference(ResponseItemReference(id: "item_123"))
            ]),
            instructions: "Be helpful",
            tools: [
                .webSearchPreview(),
                .fileSearch(ResponseFileSearchTool(vectorStoreIds: ["vs_123"])),
                .imageGeneration(ResponseImageGenerationTool(partialImages: 2)),
                .codeInterpreter(),
                .function(function)
            ],
            toolChoice: .auto,
            metadata: ["team": "aisdk"],
            temperature: 0.7,
            topP: 0.9,
            maxOutputTokens: 256,
            stream: true,
            background: true,
            previousResponseId: "resp_prev",
            include: ["output"],
            store: true,
            reasoning: ResponseReasoning(effort: "low", summary: "auto"),
            parallelToolCalls: false,
            serviceTier: "auto",
            user: "user_123",
            truncation: "disabled",
            text: ResponseTextConfig(format: ResponseTextFormat(type: "text"))
        )

        let data = try encoder.encode(request)
        let json = try decodeJSON(data)

        XCTAssertEqual(json["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(json["instructions"] as? String, "Be helpful")
        XCTAssertEqual(json["previous_response_id"] as? String, "resp_prev")
        XCTAssertEqual(json["store"] as? Bool, true)
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["background"] as? Bool, true)
        XCTAssertEqual(json["truncation"] as? String, "disabled")

        let maxTokens = (json["max_output_tokens"] as? NSNumber)?.intValue
        XCTAssertEqual(maxTokens, 256)

        let tools = json["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 5)

        let inputItems = json["input"] as? [[String: Any]]
        XCTAssertEqual(inputItems?.count, 3)

        let firstItem = inputItems?.first
        XCTAssertEqual(firstItem?["type"] as? String, "message")

        let content = firstItem?["content"] as? [[String: Any]]
        let imageItem = content?.first { ($0["type"] as? String) == "input_image" }
        XCTAssertEqual(imageItem?["detail"] as? String, "high")
    }

    func testResponseInputEncoding_StringAndItems() throws {
        let stringRequest = ResponseRequest(model: "gpt-4o-mini", input: .string("Hello"))
        let stringData = try encoder.encode(stringRequest)
        let stringJSON = try decodeJSON(stringData)
        XCTAssertEqual(stringJSON["input"] as? String, "Hello")

        let itemsRequest = ResponseRequest(
            model: "gpt-4o-mini",
            input: .items([
                .message(ResponseMessage(
                    role: "user",
                    content: [.inputText(ResponseInputText(text: "Hello"))]
                ))
            ])
        )
        let itemsData = try encoder.encode(itemsRequest)
        let itemsJSON = try decodeJSON(itemsData)
        let items = itemsJSON["input"] as? [[String: Any]]
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?["type"] as? String, "message")
    }

    // MARK: - ResponseObject Decoding

    func testResponseObjectDecoding_Statuses() throws {
        let statuses: [String] = ["completed", "in_progress", "queued", "failed", "cancelled", "incomplete"]

        for status in statuses {
            let jsonString = ResponsesAPIFixtures.responseJSONWithStatus(status)
            let data = Data(jsonString.utf8)
            let response = try decoder.decode(ResponseObject.self, from: data)
            XCTAssertEqual(response.status.rawValue, status)
        }
    }

    func testResponseObjectDecoding_Basic() throws {
        let data = Data(ResponsesAPIFixtures.responseJSON.utf8)
        let response = try decoder.decode(ResponseObject.self, from: data)

        XCTAssertEqual(response.id, "resp_123")
        XCTAssertEqual(response.status, .completed)
        XCTAssertEqual(response.outputText, "Hello!")
        XCTAssertEqual(response.usage?.inputTokens, 10)
        XCTAssertEqual(response.usage?.outputTokens, 5)
    }

    func testResponseObjectDecoding_UsageDetails() throws {
        let data = Data(ResponsesAPIFixtures.responseWithUsageDetailsJSON.utf8)
        let response = try decoder.decode(ResponseObject.self, from: data)

        XCTAssertEqual(response.usage?.inputTokens, 100)
        XCTAssertEqual(response.usage?.outputTokens, 50)
        XCTAssertEqual(response.usage?.inputTokensDetails?.cachedTokens, 80)
        XCTAssertEqual(response.usage?.outputTokensDetails?.reasoningTokens, 20)
    }

    // MARK: - Tool Encoding

    func testResponseToolEncodingAndDecoding() throws {
        let function = ToolFunction(
            name: "get_weather",
            description: "Get weather",
            parameters: Parameters(type: "object", properties: [:])
        )

        let tools: [ResponseTool] = [
            .webSearchPreview(),
            .fileSearch(ResponseFileSearchTool(vectorStoreIds: ["vs_123"])),
            .imageGeneration(ResponseImageGenerationTool(partialImages: 1)),
            .codeInterpreter(),
            .mcp(ResponseMCPTool(serverLabel: "server", serverUrl: "https://mcp.example.com")),
            .function(function)
        ]

        let data = try encoder.encode(tools)
        let decodedTools = try decoder.decode([ResponseTool].self, from: data)
        XCTAssertEqual(decodedTools.count, tools.count)

        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(json?.first?["type"] as? String, "web_search_preview")
        XCTAssertEqual(json?[1]["type"] as? String, "file_search")
        XCTAssertEqual(json?[1]["vector_store_ids"] as? [String], ["vs_123"])
        XCTAssertNil(json?[1]["vector_store_id"])
        XCTAssertEqual(json?[2]["type"] as? String, "image_generation")
        XCTAssertEqual(json?[3]["type"] as? String, "code_interpreter")
        XCTAssertEqual(json?[4]["type"] as? String, "mcp")
        XCTAssertEqual(json?[5]["type"] as? String, "function")
    }

    // MARK: - Content Item Encoding

    func testResponseContentItemEncodingDecoding() throws {
        let contentItems: [ResponseContentItem] = [
            .inputText(ResponseInputText(text: "Hello")),
            .inputImage(ResponseInputImage(imageUrl: "https://example.com/image.png", detail: "high")),
            .inputFile(ResponseInputFile(fileId: "file_123"))
        ]

        let data = try encoder.encode(contentItems)
        let decoded = try decoder.decode([ResponseContentItem].self, from: data)
        XCTAssertEqual(decoded.count, 3)

        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(json?.first?["type"] as? String, "input_text")
        XCTAssertEqual(json?[1]["type"] as? String, "input_image")
        XCTAssertEqual(json?[2]["type"] as? String, "input_file")
    }

    // MARK: - Compaction Models

    func testCompactionModelsEncodingDecoding() throws {
        let request = CompactRequest(
            model: "gpt-4o-mini",
            input: .string("Summarize"),
            instructions: "Summarize the conversation",
            previousResponseId: "resp_prev",
            metadata: ["topic": "summary"]
        )

        let requestData = try encoder.encode(request)
        let requestJSON = try decodeJSON(requestData)
        XCTAssertEqual(requestJSON["model"] as? String, "gpt-4o-mini")
        XCTAssertEqual(requestJSON["previous_response_id"] as? String, "resp_prev")

        let responseData = Data(ResponsesAPIFixtures.compactResponseJSON.utf8)
        let response = try decoder.decode(CompactResponse.self, from: responseData)
        XCTAssertEqual(response.status, .completed)
        XCTAssertEqual(response.usage.inputTokens, 200)
        XCTAssertEqual(response.output.first?.compactedItemCount, 5)
    }

    // MARK: - Helpers

    private func decodeJSON(_ data: Data) throws -> [String: Any] {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let json = jsonObject as? [String: Any] else {
            XCTFail("Expected dictionary JSON")
            return [:]
        }
        return json
    }
}
