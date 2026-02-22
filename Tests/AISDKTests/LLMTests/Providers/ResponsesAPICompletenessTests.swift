//
//  ResponsesAPICompletenessTests.swift
//  AISDKTests
//
//  Tests for Responses API completeness: refusal content, polymorphic annotations,
//  expanded input file modes, enriched tool configs, reasoning/MCP output items,
//  web search actions, and code interpreter structured outputs.
//

import XCTest
@testable import AISDK

final class ResponsesAPICompletenessTests: XCTestCase {

    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    // MARK: - Refusal Content

    func testDecodeRefusalContent() throws {
        let json = """
        {
            "id": "resp_refusal",
            "object": "response",
            "created_at": 1704067200,
            "status": "completed",
            "model": "gpt-4o",
            "output": [
                {
                    "type": "message",
                    "id": "msg_1",
                    "role": "assistant",
                    "content": [
                        {"type": "refusal", "refusal": "I cannot help with that request."}
                    ]
                }
            ],
            "parallel_tool_calls": true,
            "store": false,
            "temperature": 1.0,
            "top_p": 1.0,
            "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ResponseObject.self, from: json)
        XCTAssertNil(response.outputText, "Refusal should not appear as outputText")
        if case .message(let msg) = response.output.first {
            if case .refusal(let refusal) = msg.content.first {
                XCTAssertEqual(refusal.refusal, "I cannot help with that request.")
            } else {
                XCTFail("Expected refusal content")
            }
        } else {
            XCTFail("Expected message output")
        }
    }

    func testDecodeUnknownContentType() throws {
        let json = """
        {
            "id": "resp_unknown",
            "object": "response",
            "created_at": 1704067200,
            "status": "completed",
            "model": "gpt-4o",
            "output": [
                {
                    "type": "message",
                    "id": "msg_1",
                    "role": "assistant",
                    "content": [
                        {"type": "future_content_type", "data": "something"}
                    ]
                }
            ],
            "parallel_tool_calls": true,
            "store": false,
            "temperature": 1.0,
            "top_p": 1.0,
            "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ResponseObject.self, from: json)
        if case .message(let msg) = response.output.first {
            if case .unknown(let typeName) = msg.content.first {
                XCTAssertEqual(typeName, "future_content_type")
            } else {
                XCTFail("Expected unknown content type")
            }
        } else {
            XCTFail("Expected message output")
        }
    }

    func testOutputTextSkipsRefusal() throws {
        let json = """
        {
            "id": "resp_mixed",
            "object": "response",
            "created_at": 1704067200,
            "status": "completed",
            "model": "gpt-4o",
            "output": [
                {
                    "type": "message",
                    "id": "msg_1",
                    "role": "assistant",
                    "content": [
                        {"type": "refusal", "refusal": "Cannot do that."},
                        {"type": "output_text", "text": "Here is safe content."}
                    ]
                }
            ],
            "parallel_tool_calls": true,
            "store": false,
            "temperature": 1.0,
            "top_p": 1.0,
            "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ResponseObject.self, from: json)
        XCTAssertEqual(response.outputText, "Here is safe content.")
    }

    // MARK: - Polymorphic Annotations

    func testDecodeURLCitationAnnotation() throws {
        let json = """
        {
            "id": "resp_cite",
            "object": "response",
            "created_at": 1704067200,
            "status": "completed",
            "model": "gpt-4o",
            "output": [
                {
                    "type": "message",
                    "id": "msg_1",
                    "role": "assistant",
                    "content": [
                        {
                            "type": "output_text",
                            "text": "According to the source...",
                            "annotations": [
                                {
                                    "type": "url_citation",
                                    "url": "https://example.com/article",
                                    "title": "Example Article",
                                    "start_index": 0,
                                    "end_index": 25
                                }
                            ]
                        }
                    ]
                }
            ],
            "parallel_tool_calls": true,
            "store": false,
            "temperature": 1.0,
            "top_p": 1.0,
            "usage": {"input_tokens": 10, "output_tokens": 5, "total_tokens": 15}
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ResponseObject.self, from: json)
        if case .message(let msg) = response.output.first,
           case .outputText(let text) = msg.content.first,
           let annotation = text.annotations?.first,
           case .urlCitation(let citation) = annotation {
            XCTAssertEqual(citation.url, "https://example.com/article")
            XCTAssertEqual(citation.title, "Example Article")
            XCTAssertEqual(citation.startIndex, 0)
            XCTAssertEqual(citation.endIndex, 25)
            // Backward-compatible computed properties
            XCTAssertEqual(annotation.type, "url_citation")
            XCTAssertEqual(annotation.startIndex, 0)
            XCTAssertEqual(annotation.endIndex, 25)
        } else {
            XCTFail("Expected url_citation annotation")
        }
    }

    func testDecodeFileCitationAnnotation() throws {
        let json = """
        {"type": "file_citation", "file_id": "file_abc", "filename": "report.pdf", "index": 42}
        """.data(using: .utf8)!

        let annotation = try decoder.decode(ResponseAnnotation.self, from: json)
        if case .fileCitation(let citation) = annotation {
            XCTAssertEqual(citation.fileId, "file_abc")
            XCTAssertEqual(citation.filename, "report.pdf")
            XCTAssertEqual(citation.index, 42)
        } else {
            XCTFail("Expected file_citation annotation")
        }
    }

    func testDecodeContainerFileCitationAnnotation() throws {
        let json = """
        {"type": "container_file_citation", "container_id": "ctr_1", "file_id": "file_2", "filename": "data.csv", "start_index": 10, "end_index": 50}
        """.data(using: .utf8)!

        let annotation = try decoder.decode(ResponseAnnotation.self, from: json)
        if case .containerFileCitation(let citation) = annotation {
            XCTAssertEqual(citation.containerId, "ctr_1")
            XCTAssertEqual(citation.fileId, "file_2")
            XCTAssertEqual(citation.filename, "data.csv")
            XCTAssertEqual(citation.startIndex, 10)
            XCTAssertEqual(citation.endIndex, 50)
        } else {
            XCTFail("Expected container_file_citation annotation")
        }
    }

    func testDecodeFilePathAnnotation() throws {
        let json = """
        {"type": "file_path", "file_id": "file_xyz", "index": 7}
        """.data(using: .utf8)!

        let annotation = try decoder.decode(ResponseAnnotation.self, from: json)
        if case .filePath(let fp) = annotation {
            XCTAssertEqual(fp.fileId, "file_xyz")
            XCTAssertEqual(fp.index, 7)
        } else {
            XCTFail("Expected file_path annotation")
        }
    }

    func testDecodeUnknownAnnotationType() throws {
        let json = """
        {"type": "future_annotation_type", "data": "value"}
        """.data(using: .utf8)!

        let annotation = try decoder.decode(ResponseAnnotation.self, from: json)
        if case .unknown(let typeName) = annotation {
            XCTAssertEqual(typeName, "future_annotation_type")
        } else {
            XCTFail("Expected unknown annotation type")
        }
    }

    // MARK: - Input File Variants

    func testEncodeInputFileWithFileId() throws {
        let file = ResponseInputFile(fileId: "file_123")
        let data = try encoder.encode(file)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["file_id"] as? String, "file_123")
        XCTAssertNil(json["file_data"])
        XCTAssertNil(json["file_url"])
    }

    func testEncodeInputFileWithUrl() throws {
        let file = ResponseInputFile(fileUrl: "https://example.com/file.pdf", filename: "doc.pdf")
        let data = try encoder.encode(file)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["file_url"] as? String, "https://example.com/file.pdf")
        XCTAssertEqual(json["filename"] as? String, "doc.pdf")
        XCTAssertNil(json["file_id"])
    }

    func testEncodeInputFileWithData() throws {
        let file = ResponseInputFile(fileData: "base64data==", filename: "image.png")
        let data = try encoder.encode(file)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["file_data"] as? String, "base64data==")
        XCTAssertEqual(json["filename"] as? String, "image.png")
    }

    func testInputFileRoundTrip() throws {
        let original = ResponseInputFile(fileId: "file_abc")
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ResponseInputFile.self, from: data)
        XCTAssertEqual(decoded.fileId, "file_abc")
    }

    // MARK: - Web Search Tool Config

    func testEncodeWebSearchToolWithConfig() throws {
        let tool = ResponseTool.webSearchPreview(ResponseWebSearchTool(
            searchContextSize: "high",
            userLocation: WebSearchUserLocation(city: "San Francisco", country: "US", timezone: "America/Los_Angeles"),
            filters: WebSearchFilters(allowedDomains: ["example.com", "docs.example.com"])
        ))
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "web_search_preview")
        XCTAssertEqual(json["search_context_size"] as? String, "high")
        let loc = json["user_location"] as? [String: Any]
        XCTAssertEqual(loc?["city"] as? String, "San Francisco")
        let filters = json["filters"] as? [String: Any]
        XCTAssertEqual((filters?["allowed_domains"] as? [String])?.count, 2)
    }

    // MARK: - File Search Tool Config

    func testEncodeFileSearchToolWithRanking() throws {
        let tool = ResponseTool.fileSearch(ResponseFileSearchTool(
            vectorStoreIds: ["vs_1"],
            maxNumResults: 20,
            rankingOptions: ResponseFileSearchRankingOptions(ranker: "auto", scoreThreshold: 0.5)
        ))
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "file_search")
        XCTAssertEqual(json["max_num_results"] as? Int, 20)
        let ranking = json["ranking_options"] as? [String: Any]
        XCTAssertEqual(ranking?["ranker"] as? String, "auto")
        XCTAssertEqual(ranking?["score_threshold"] as? Double, 0.5)
    }

    // MARK: - Image Generation Tool Config

    func testEncodeImageGenerationToolFull() throws {
        let tool = ResponseTool.imageGeneration(ResponseImageGenerationTool(
            partialImages: 3,
            background: "transparent",
            model: "gpt-image-1",
            outputFormat: "png",
            quality: "high",
            size: "1024x1024"
        ))
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "image_generation")
        XCTAssertEqual(json["partial_images"] as? Int, 3)
        XCTAssertEqual(json["background"] as? String, "transparent")
        XCTAssertEqual(json["quality"] as? String, "high")
        XCTAssertEqual(json["size"] as? String, "1024x1024")
    }

    // MARK: - Code Interpreter Container Variants

    func testEncodeCodeInterpreterContainerAuto() throws {
        let tool = ResponseTool.codeInterpreter(ResponseCodeInterpreterTool(
            container: .auto(fileIds: ["file_1", "file_2"])
        ))
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "code_interpreter")
        let container = json["container"] as? [String: Any]
        XCTAssertEqual(container?["type"] as? String, "auto")
        XCTAssertEqual((container?["file_ids"] as? [String])?.count, 2)
    }

    func testEncodeCodeInterpreterContainerId() throws {
        let tool = ResponseTool.codeInterpreter(ResponseCodeInterpreterTool(
            container: .id("ctr_existing_123")
        ))
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "code_interpreter")
        XCTAssertEqual(json["container"] as? String, "ctr_existing_123")
    }

    func testDecodeCodeInterpreterContainerString() throws {
        let json = """
        {"type": "code_interpreter", "container": "ctr_abc"}
        """.data(using: .utf8)!
        let tool = try decoder.decode(ResponseTool.self, from: json)
        if case .codeInterpreter(let ciTool) = tool,
           case .id(let containerId) = ciTool.container {
            XCTAssertEqual(containerId, "ctr_abc")
        } else {
            XCTFail("Expected code_interpreter with string container ID")
        }
    }

    // MARK: - MCP Tool Config

    func testEncodeMCPToolWithConnector() throws {
        let tool = ResponseTool.mcp(ResponseMCPTool(
            serverLabel: "my-mcp",
            connectorId: "conn_123",
            serverDescription: "My MCP connector"
        ))
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "mcp")
        XCTAssertEqual(json["server_label"] as? String, "my-mcp")
        XCTAssertEqual(json["connector_id"] as? String, "conn_123")
        XCTAssertNil(json["server_url"])
    }

    func testEncodeMCPToolWithAllowedTools() throws {
        let tool = ResponseTool.mcp(ResponseMCPTool(
            serverLabel: "server",
            serverUrl: "https://mcp.example.com",
            allowedTools: ["tool_a", "tool_b"]
        ))
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((json["allowed_tools"] as? [String])?.count, 2)
    }

    // MARK: - Reasoning Output Item

    func testDecodeReasoningOutputItem() throws {
        let json = """
        {
            "id": "resp_reasoning",
            "object": "response",
            "created_at": 1704067200,
            "status": "completed",
            "model": "o1",
            "output": [
                {
                    "type": "reasoning",
                    "id": "rs_1",
                    "summary": [
                        {"type": "summary_text", "text": "The model considered multiple approaches..."}
                    ],
                    "encrypted_content": "enc_abc123"
                },
                {
                    "type": "message",
                    "id": "msg_1",
                    "role": "assistant",
                    "content": [
                        {"type": "output_text", "text": "The answer is 42."}
                    ]
                }
            ],
            "parallel_tool_calls": true,
            "store": false,
            "temperature": 1.0,
            "top_p": 1.0,
            "usage": {"input_tokens": 10, "output_tokens": 50, "total_tokens": 60}
        }
        """.data(using: .utf8)!

        let response = try decoder.decode(ResponseObject.self, from: json)
        XCTAssertEqual(response.output.count, 2)
        if case .reasoning(let reasoning) = response.output[0] {
            XCTAssertEqual(reasoning.id, "rs_1")
            XCTAssertEqual(reasoning.summary?.first?.text, "The model considered multiple approaches...")
            XCTAssertEqual(reasoning.encryptedContent, "enc_abc123")
        } else {
            XCTFail("Expected reasoning output item")
        }
        XCTAssertEqual(response.outputText, "The answer is 42.")
    }

    // MARK: - MCP Call Output Item

    func testDecodeMCPCallOutputItem() throws {
        let json = """
        {
            "type": "mcp_call",
            "id": "mcp_1",
            "name": "search_documents",
            "arguments": "{\\"query\\": \\"test\\"}",
            "server_label": "my-server",
            "output": "Found 3 results",
            "status": "completed"
        }
        """.data(using: .utf8)!

        let item = try decoder.decode(ResponseOutputItem.self, from: json)
        if case .mcpCall(let call) = item {
            XCTAssertEqual(call.name, "search_documents")
            XCTAssertEqual(call.serverLabel, "my-server")
            XCTAssertEqual(call.output, "Found 3 results")
        } else {
            XCTFail("Expected mcp_call output item")
        }
    }

    // MARK: - MCP List Tools Output Item

    func testDecodeMCPListToolsOutputItem() throws {
        let json = """
        {
            "type": "mcp_list_tools",
            "id": "mlt_1",
            "server_label": "my-server",
            "tools": [
                {"name": "search", "description": "Search documents"},
                {"name": "create", "description": "Create document"}
            ]
        }
        """.data(using: .utf8)!

        let item = try decoder.decode(ResponseOutputItem.self, from: json)
        if case .mcpListTools(let listTools) = item {
            XCTAssertEqual(listTools.serverLabel, "my-server")
            XCTAssertEqual(listTools.tools?.count, 2)
            XCTAssertEqual(listTools.tools?.first?.name, "search")
        } else {
            XCTFail("Expected mcp_list_tools output item")
        }
    }

    // MARK: - Web Search With Action

    func testDecodeWebSearchWithAction() throws {
        let json = """
        {
            "type": "web_search_call",
            "id": "ws_1",
            "query": "AI news 2025",
            "status": "completed",
            "action": {
                "type": "search",
                "query": "AI news 2025",
                "sources": [
                    {"type": "url", "url": "https://news.example.com/ai"},
                    {"type": "url", "url": "https://blog.example.com/ai-update"}
                ]
            }
        }
        """.data(using: .utf8)!

        let item = try decoder.decode(ResponseOutputItem.self, from: json)
        if case .webSearchCall(let ws) = item {
            XCTAssertEqual(ws.query, "AI news 2025")
            XCTAssertNotNil(ws.action)
            XCTAssertEqual(ws.action?.type, "search")
            XCTAssertEqual(ws.action?.sources?.count, 2)
            XCTAssertEqual(ws.action?.sources?.first?.url, "https://news.example.com/ai")
        } else {
            XCTFail("Expected web_search_call output item")
        }
    }

    // MARK: - Code Interpreter With Outputs

    func testDecodeCodeInterpreterWithOutputs() throws {
        let json = """
        {
            "type": "code_interpreter_call",
            "id": "ci_1",
            "code": "import matplotlib\\nprint('hello')",
            "status": "completed",
            "container_id": "ctr_abc",
            "outputs": [
                {"type": "logs", "logs": "hello"},
                {"type": "image", "url": "https://files.example.com/chart.png"}
            ]
        }
        """.data(using: .utf8)!

        let item = try decoder.decode(ResponseOutputItem.self, from: json)
        if case .codeInterpreterCall(let ci) = item {
            XCTAssertEqual(ci.containerId, "ctr_abc")
            XCTAssertEqual(ci.outputs?.count, 2)
            if case .logs(let logOutput) = ci.outputs?[0] {
                XCTAssertEqual(logOutput.logs, "hello")
            } else {
                XCTFail("Expected logs output")
            }
            if case .image(let imageOutput) = ci.outputs?[1] {
                XCTAssertEqual(imageOutput.url, "https://files.example.com/chart.png")
            } else {
                XCTFail("Expected image output")
            }
        } else {
            XCTFail("Expected code_interpreter_call output item")
        }
    }

    // MARK: - Backward Compatibility

    func testWebSearchToolDefaultStillWorks() throws {
        let tool = ResponseTool.webSearchPreview()
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "web_search_preview")
    }

    func testCodeInterpreterDefaultStillWorks() throws {
        let tool = ResponseTool.codeInterpreter()
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "code_interpreter")
    }

    func testImageGenerationDefaultStillWorks() throws {
        let tool = ResponseTool.imageGeneration()
        let data = try encoder.encode(tool)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "image_generation")
    }

    func testInputFileBackwardCompat() throws {
        let file = ResponseInputFile(fileId: "file_old")
        XCTAssertEqual(file.fileId, "file_old")
        XCTAssertNil(file.fileData)
        XCTAssertNil(file.fileUrl)
        XCTAssertNil(file.filename)
    }
}
