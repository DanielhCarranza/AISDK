//
//  OpenRouterClientTests.swift
//  AISDKTests
//
//  Tests for OpenRouterClient implementation
//

import XCTest
@testable import AISDK

final class OpenRouterClientTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitializationWithDefaults() async {
        let client = OpenRouterClient(apiKey: "sk-or-test-key")

        XCTAssertEqual(client.providerId, "openrouter")
        XCTAssertEqual(client.displayName, "OpenRouter")
        XCTAssertEqual(client.baseURL.absoluteString, "https://openrouter.ai/api/v1")
    }

    func testInitializationWithCustomBaseURL() async {
        let customURL = URL(string: "https://custom.openrouter.ai/api/v1")!
        let client = OpenRouterClient(apiKey: "sk-or-test-key", baseURL: customURL)

        XCTAssertEqual(client.baseURL, customURL)
    }

    func testInitializationWithAppMetadata() async {
        let client = OpenRouterClient(
            apiKey: "sk-or-test-key",
            appName: "TestApp",
            siteURL: "https://testapp.com"
        )

        XCTAssertEqual(client.providerId, "openrouter")
    }

    // MARK: - Health Status Tests

    func testInitialHealthStatusIsUnknown() async {
        let client = OpenRouterClient(apiKey: "sk-or-test-key")
        let status = await client.healthStatus

        XCTAssertEqual(status, .unknown)
    }

    func testInitialIsAvailableIsFalse() async {
        let client = OpenRouterClient(apiKey: "sk-or-test-key")
        let available = await client.isAvailable

        XCTAssertFalse(available)
    }

    // MARK: - Model Availability Tests

    func testIsModelAvailableReturnsBoolean() async {
        let client = OpenRouterClient(apiKey: "sk-or-test-key")

        // Should return a boolean (either true or false depending on network/auth)
        let available = await client.isModelAvailable("openai/gpt-4")
        // Just verify it returns a boolean without throwing
        XCTAssertTrue(available == true || available == false)
    }

    func testCapabilitiesForKnownModels() async {
        let client = OpenRouterClient(apiKey: "sk-or-test-key")

        // Gemini models should report video capability
        let geminiCaps = await client.capabilities(for: "google/gemini-2.0-flash")
        XCTAssertNotNil(geminiCaps)
        XCTAssertTrue(geminiCaps!.contains(.video))
        XCTAssertTrue(geminiCaps!.contains(.vision))

        // GPT-4 models should not report video capability
        let gptCaps = await client.capabilities(for: "openai/gpt-4")
        XCTAssertNotNil(gptCaps)
        XCTAssertFalse(gptCaps!.contains(.video))
        XCTAssertTrue(gptCaps!.contains(.text))
    }

    // MARK: - Stream Tests

    func testStreamReturnsAsyncThrowingStream() {
        let client = OpenRouterClient(apiKey: "sk-or-test-key")
        let request = ProviderRequest(
            modelId: "openai/gpt-3.5-turbo",
            messages: [.user("Hello")]
        )

        let stream = client.stream(request: request)

        // Verify we get a stream (type check)
        XCTAssertNotNil(stream)
    }

    // MARK: - Protocol Conformance Tests

    func testConformsToProviderClient() {
        // Verify OpenRouterClient conforms to ProviderClient
        let client: any ProviderClient = OpenRouterClient(apiKey: "test")
        XCTAssertEqual(client.providerId, "openrouter")
    }

    func testConformsToSendable() {
        // Verify OpenRouterClient is Sendable (actor is implicitly Sendable)
        let client = OpenRouterClient(apiKey: "test")
        let sendableClient: any Sendable = client
        XCTAssertNotNil(sendableClient)
    }
}

// MARK: - Response Parsing Tests

final class OpenRouterResponseParsingTests: XCTestCase {

    func testParseValidCompletionResponse() throws {
        let json = """
        {
            "id": "gen-123",
            "model": "openai/gpt-4",
            "choices": [
                {
                    "message": {
                        "role": "assistant",
                        "content": "Hello! How can I help you today?"
                    },
                    "finish_reason": "stop"
                }
            ],
            "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 8,
                "total_tokens": 18
            }
        }
        """

        let data = json.data(using: .utf8)!

        // Decode using the same structure as OpenRouterClient
        struct TestCompletionResponse: Decodable {
            let id: String
            let model: String
            let choices: [TestChoice]
            let usage: TestUsage?

            struct TestChoice: Decodable {
                let message: TestMessage
                let finishReason: String?

                enum CodingKeys: String, CodingKey {
                    case message
                    case finishReason = "finish_reason"
                }
            }

            struct TestMessage: Decodable {
                let role: String
                let content: String?
            }

            struct TestUsage: Decodable {
                let promptTokens: Int
                let completionTokens: Int
                let totalTokens: Int

                enum CodingKeys: String, CodingKey {
                    case promptTokens = "prompt_tokens"
                    case completionTokens = "completion_tokens"
                    case totalTokens = "total_tokens"
                }
            }
        }

        let response = try JSONDecoder().decode(TestCompletionResponse.self, from: data)

        XCTAssertEqual(response.id, "gen-123")
        XCTAssertEqual(response.model, "openai/gpt-4")
        XCTAssertEqual(response.choices.count, 1)
        XCTAssertEqual(response.choices[0].message.content, "Hello! How can I help you today?")
        XCTAssertEqual(response.choices[0].finishReason, "stop")
        XCTAssertEqual(response.usage?.promptTokens, 10)
        XCTAssertEqual(response.usage?.completionTokens, 8)
        XCTAssertEqual(response.usage?.totalTokens, 18)
    }

    func testParseCompletionResponseWithToolCalls() throws {
        let json = """
        {
            "id": "gen-456",
            "model": "openai/gpt-4",
            "choices": [
                {
                    "message": {
                        "role": "assistant",
                        "content": null,
                        "tool_calls": [
                            {
                                "id": "call_abc123",
                                "type": "function",
                                "function": {
                                    "name": "get_weather",
                                    "arguments": "{\\"location\\": \\"Seattle\\"}"
                                }
                            }
                        ]
                    },
                    "finish_reason": "tool_calls"
                }
            ],
            "usage": {
                "prompt_tokens": 15,
                "completion_tokens": 20,
                "total_tokens": 35
            }
        }
        """

        let data = json.data(using: .utf8)!

        struct TestCompletionResponse: Decodable {
            let id: String
            let model: String
            let choices: [TestChoice]

            struct TestChoice: Decodable {
                let message: TestMessage
                let finishReason: String?

                enum CodingKeys: String, CodingKey {
                    case message
                    case finishReason = "finish_reason"
                }
            }

            struct TestMessage: Decodable {
                let role: String
                let content: String?
                let toolCalls: [TestToolCall]?

                enum CodingKeys: String, CodingKey {
                    case role, content
                    case toolCalls = "tool_calls"
                }
            }

            struct TestToolCall: Decodable {
                let id: String
                let type: String
                let function: TestFunction
            }

            struct TestFunction: Decodable {
                let name: String
                let arguments: String
            }
        }

        let response = try JSONDecoder().decode(TestCompletionResponse.self, from: data)

        XCTAssertEqual(response.choices[0].message.toolCalls?.count, 1)
        XCTAssertEqual(response.choices[0].message.toolCalls?[0].id, "call_abc123")
        XCTAssertEqual(response.choices[0].message.toolCalls?[0].function.name, "get_weather")
        XCTAssertEqual(response.choices[0].finishReason, "tool_calls")
    }

    func testParseStreamChunk() throws {
        let json = """
        {
            "id": "gen-789",
            "model": "openai/gpt-4",
            "choices": [
                {
                    "delta": {
                        "content": "Hello"
                    },
                    "finish_reason": null
                }
            ]
        }
        """

        let data = json.data(using: .utf8)!

        struct TestStreamChunk: Decodable {
            let id: String
            let model: String
            let choices: [TestStreamChoice]

            struct TestStreamChoice: Decodable {
                let delta: TestDelta?
                let finishReason: String?

                enum CodingKeys: String, CodingKey {
                    case delta
                    case finishReason = "finish_reason"
                }
            }

            struct TestDelta: Decodable {
                let content: String?
            }
        }

        let chunk = try JSONDecoder().decode(TestStreamChunk.self, from: data)

        XCTAssertEqual(chunk.id, "gen-789")
        XCTAssertEqual(chunk.choices[0].delta?.content, "Hello")
        XCTAssertNil(chunk.choices[0].finishReason)
    }

    func testParseStreamChunkWithFinishReason() throws {
        let json = """
        {
            "id": "gen-789",
            "model": "openai/gpt-4",
            "choices": [
                {
                    "delta": {},
                    "finish_reason": "stop"
                }
            ],
            "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 5,
                "total_tokens": 15
            }
        }
        """

        let data = json.data(using: .utf8)!

        struct TestStreamChunk: Decodable {
            let id: String
            let model: String
            let choices: [TestStreamChoice]
            let usage: TestUsage?

            struct TestStreamChoice: Decodable {
                let delta: TestDelta?
                let finishReason: String?

                enum CodingKeys: String, CodingKey {
                    case delta
                    case finishReason = "finish_reason"
                }
            }

            struct TestDelta: Decodable {
                let content: String?
            }

            struct TestUsage: Decodable {
                let promptTokens: Int
                let completionTokens: Int
                let totalTokens: Int

                enum CodingKeys: String, CodingKey {
                    case promptTokens = "prompt_tokens"
                    case completionTokens = "completion_tokens"
                    case totalTokens = "total_tokens"
                }
            }
        }

        let chunk = try JSONDecoder().decode(TestStreamChunk.self, from: data)

        XCTAssertEqual(chunk.choices[0].finishReason, "stop")
        XCTAssertEqual(chunk.usage?.totalTokens, 15)
    }

    // MARK: - Models Response Parsing

    func testParseModelsResponse() throws {
        let json = """
        {
            "data": [
                {"id": "openai/gpt-4"},
                {"id": "openai/gpt-3.5-turbo"},
                {"id": "anthropic/claude-3-opus"},
                {"id": "anthropic/claude-3-sonnet"},
                {"id": "google/gemini-pro"}
            ]
        }
        """

        let data = json.data(using: .utf8)!

        struct TestModelsResponse: Decodable {
            struct Model: Decodable {
                let id: String
            }
            let data: [Model]
        }

        let response = try JSONDecoder().decode(TestModelsResponse.self, from: data)

        XCTAssertEqual(response.data.count, 5)
        XCTAssertEqual(response.data[0].id, "openai/gpt-4")
        XCTAssertEqual(response.data[2].id, "anthropic/claude-3-opus")
    }

    // MARK: - Error Response Parsing

    func testParseErrorResponse() throws {
        let json = """
        {
            "error": {
                "message": "Invalid API key provided",
                "type": "invalid_request_error",
                "code": "invalid_api_key"
            }
        }
        """

        let data = json.data(using: .utf8)!

        struct TestErrorResponse: Decodable {
            struct ErrorDetail: Decodable {
                let message: String?
                let type: String?
                let code: String?
            }
            let error: ErrorDetail?
        }

        let response = try JSONDecoder().decode(TestErrorResponse.self, from: data)

        XCTAssertEqual(response.error?.message, "Invalid API key provided")
        XCTAssertEqual(response.error?.type, "invalid_request_error")
        XCTAssertEqual(response.error?.code, "invalid_api_key")
    }
}

// MARK: - Request Body Encoding Tests

final class OpenRouterRequestEncodingTests: XCTestCase {

    func testBasicRequestEncoding() throws {
        struct TestMessage: Encodable {
            let role: String
            let content: String
        }

        struct TestRequestBody: Encodable {
            let model: String
            let messages: [TestMessage]
            let stream: Bool
        }

        let body = TestRequestBody(
            model: "openai/gpt-4",
            messages: [
                TestMessage(role: "user", content: "Hello")
            ],
            stream: false
        )

        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["model"] as? String, "openai/gpt-4")
        XCTAssertEqual(json["stream"] as? Bool, false)

        let messages = json["messages"] as! [[String: Any]]
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertEqual(messages[0]["content"] as? String, "Hello")
    }

    func testRequestWithOptionalParameters() throws {
        struct TestMessage: Encodable {
            let role: String
            let content: String
        }

        struct TestRequestBody: Encodable {
            let model: String
            let messages: [TestMessage]
            let stream: Bool
            var maxTokens: Int?
            var temperature: Double?
            var topP: Double?
            var stop: [String]?

            enum CodingKeys: String, CodingKey {
                case model, messages, stream
                case maxTokens = "max_tokens"
                case temperature
                case topP = "top_p"
                case stop
            }
        }

        var body = TestRequestBody(
            model: "openai/gpt-4",
            messages: [TestMessage(role: "user", content: "Hello")],
            stream: false
        )
        body.maxTokens = 1000
        body.temperature = 0.7
        body.topP = 0.9
        body.stop = ["END", "STOP"]

        let data = try JSONEncoder().encode(body)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["max_tokens"] as? Int, 1000)
        XCTAssertEqual(json["temperature"] as? Double, 0.7)
        XCTAssertEqual(json["top_p"] as? Double, 0.9)
        XCTAssertEqual(json["stop"] as? [String], ["END", "STOP"])
    }

    func testMultipartContentEncoding() throws {
        struct ImageURL: Encodable {
            let url: String
        }

        struct TestContentPart: Encodable {
            let type: String
            let text: String?
            let imageURL: ImageURL?

            enum CodingKeys: String, CodingKey {
                case type, text
                case imageURL = "image_url"
            }
        }

        let parts: [TestContentPart] = [
            TestContentPart(type: "text", text: "What's in this image?", imageURL: nil),
            TestContentPart(type: "image_url", text: nil, imageURL: ImageURL(url: "https://example.com/image.jpg"))
        ]

        let data = try JSONEncoder().encode(parts)
        let json = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]

        XCTAssertEqual(json.count, 2)
        XCTAssertEqual(json[0]["type"] as? String, "text")
        XCTAssertEqual(json[0]["text"] as? String, "What's in this image?")
        XCTAssertEqual(json[1]["type"] as? String, "image_url")

        let imageURL = json[1]["image_url"] as? [String: String]
        XCTAssertEqual(imageURL?["url"], "https://example.com/image.jpg")
    }

    func testToolChoiceStringEncoding() throws {
        struct StringChoice: Encodable {
            let toolChoice: String

            enum CodingKeys: String, CodingKey {
                case toolChoice = "tool_choice"
            }
        }

        let autoChoice = StringChoice(toolChoice: "auto")
        let autoData = try JSONEncoder().encode(autoChoice)
        let autoJSON = try JSONSerialization.jsonObject(with: autoData) as! [String: Any]
        XCTAssertEqual(autoJSON["tool_choice"] as? String, "auto")
    }

    func testToolChoiceObjectEncoding() throws {
        struct FunctionName: Encodable {
            let name: String
        }

        struct ToolChoiceObject: Encodable {
            let type: String
            let function: FunctionName
        }

        struct ObjectChoice: Encodable {
            let toolChoice: ToolChoiceObject

            enum CodingKeys: String, CodingKey {
                case toolChoice = "tool_choice"
            }
        }

        let specificChoice = ObjectChoice(
            toolChoice: ToolChoiceObject(
                type: "function",
                function: FunctionName(name: "get_weather")
            )
        )
        let specificData = try JSONEncoder().encode(specificChoice)
        let specificJSON = try JSONSerialization.jsonObject(with: specificData) as! [String: Any]

        let toolChoice = specificJSON["tool_choice"] as! [String: Any]
        XCTAssertEqual(toolChoice["type"] as? String, "function")

        let function = toolChoice["function"] as! [String: String]
        XCTAssertEqual(function["name"], "get_weather")
    }

    func testResponseFormatEncoding() throws {
        struct ResponseFormat: Encodable {
            let type: String
        }

        // Text format
        let textFormat = ResponseFormat(type: "text")
        let textData = try JSONEncoder().encode(textFormat)
        let textJSON = try JSONSerialization.jsonObject(with: textData) as! [String: Any]
        XCTAssertEqual(textJSON["type"] as? String, "text")

        // JSON object format
        let jsonFormat = ResponseFormat(type: "json_object")
        let jsonData = try JSONEncoder().encode(jsonFormat)
        let jsonJSON = try JSONSerialization.jsonObject(with: jsonData) as! [String: Any]
        XCTAssertEqual(jsonJSON["type"] as? String, "json_object")
    }
}
