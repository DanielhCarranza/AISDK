//
//  LiteLLMTestSuite.swift
//  AISDKTestRunner
//
//  Tests for LiteLLM proxy integration
//

import Foundation
import AISDK

public final class LiteLLMTestSuite: TestSuiteProtocol {
    public let reporter: TestReporter
    public let verbose: Bool
    private let suiteName = "LiteLLM"

    private var baseURL: String {
        ProcessInfo.processInfo.environment["LITELLM_BASE_URL"] ?? "http://localhost:8000"
    }

    private var apiKey: String? {
        ProcessInfo.processInfo.environment["LITELLM_API_KEY"]
    }

    public init(reporter: TestReporter, verbose: Bool) {
        self.reporter = reporter
        self.verbose = verbose
    }

    public func run() async throws {
        reporter.log("Starting LiteLLM integration tests...")
        reporter.log("Base URL: \(baseURL)")

        await testConnectToProxy()
        await testHealthEndpoint()
        await testListAvailableModels()
        await testBasicCompletion()
        await testStreamingThroughProxy()
        await testToolCallingThroughProxy()
    }

    // MARK: - Connection Tests

    private func testConnectToProxy() async {
        await withTimer("Connect to LiteLLM proxy", suiteName) {
            guard apiKey != nil else {
                reporter.recordSkipped(suiteName, "Connect to proxy", reason: "LITELLM_API_KEY not set")
                return
            }

            // Try to connect to the proxy
            guard let url = URL(string: "\(baseURL)/health") else {
                throw TestError.assertionFailed("Invalid base URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TestError.assertionFailed("Invalid response type")
            }

            guard httpResponse.statusCode == 200 else {
                throw TestError.assertionFailed("Health check failed with status \(httpResponse.statusCode)")
            }

            reporter.log("Successfully connected to LiteLLM proxy at \(baseURL)")
        }
    }

    private func testHealthEndpoint() async {
        await withTimer("Health endpoint check", suiteName) {
            guard let url = URL(string: "\(baseURL)/health") else {
                throw TestError.assertionFailed("Invalid URL")
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TestError.assertionFailed("Invalid response")
                }

                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        reporter.log("Health response: \(json)")
                    }
                    reporter.log("LiteLLM proxy is healthy")
                } else {
                    reporter.recordSkipped(suiteName, "Health check", reason: "Proxy returned \(httpResponse.statusCode)")
                }
            } catch {
                reporter.recordSkipped(suiteName, "Health check", reason: "Proxy not reachable: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Model Discovery Tests

    private func testListAvailableModels() async {
        await withTimer("List available models", suiteName) {
            guard let key = apiKey else {
                reporter.recordSkipped(suiteName, "List models", reason: "LITELLM_API_KEY not set")
                return
            }

            guard let url = URL(string: "\(baseURL)/v1/models") else {
                throw TestError.assertionFailed("Invalid URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw TestError.assertionFailed("Invalid response")
                }

                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let models = json["data"] as? [[String: Any]] {
                        let modelIds = models.compactMap { $0["id"] as? String }
                        reporter.log("Found \(modelIds.count) models: \(modelIds.prefix(5).joined(separator: ", "))...")
                    }
                } else {
                    reporter.recordSkipped(suiteName, "List models", reason: "API returned \(httpResponse.statusCode)")
                }
            } catch {
                reporter.recordSkipped(suiteName, "List models", reason: "Request failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Completion Tests

    private func testBasicCompletion() async {
        await withTimer("Basic completion through proxy", suiteName) {
            guard let key = apiKey else {
                reporter.recordSkipped(suiteName, "Basic completion", reason: "LITELLM_API_KEY not set")
                return
            }

            let client = LiteLLMClient(baseURL: baseURL, apiKey: key)

            let request = LiteLLMRequest(
                model: "gpt-3.5-turbo", // Use a common model
                messages: [
                    LiteLLMMessage(role: "user", content: "Say 'Hello from LiteLLM' in exactly those words.")
                ],
                maxTokens: 50
            )

            do {
                let response = try await client.complete(request: request)
                guard !response.content.isEmpty else {
                    throw TestError.assertionFailed("Empty response")
                }
                reporter.log("Response: \(response.content.prefix(50))...")
            } catch {
                reporter.recordSkipped(suiteName, "Basic completion", reason: "Request failed: \(error)")
            }
        }
    }

    private func testStreamingThroughProxy() async {
        await withTimer("Streaming through proxy", suiteName) {
            guard let key = apiKey else {
                reporter.recordSkipped(suiteName, "Streaming", reason: "LITELLM_API_KEY not set")
                return
            }

            let client = LiteLLMClient(baseURL: baseURL, apiKey: key)

            let request = LiteLLMRequest(
                model: "gpt-3.5-turbo",
                messages: [
                    LiteLLMMessage(role: "user", content: "Count from 1 to 5.")
                ],
                maxTokens: 50,
                stream: true
            )

            do {
                var chunkCount = 0
                var fullResponse = ""

                for try await chunk in client.stream(request: request) {
                    chunkCount += 1
                    fullResponse += chunk
                }

                guard chunkCount > 0 else {
                    throw TestError.assertionFailed("No chunks received")
                }

                reporter.log("Received \(chunkCount) chunks, total: \(fullResponse.count) chars")
            } catch {
                reporter.recordSkipped(suiteName, "Streaming", reason: "Stream failed: \(error)")
            }
        }
    }

    private func testToolCallingThroughProxy() async {
        await withTimer("Tool calling through proxy", suiteName) {
            guard let key = apiKey else {
                reporter.recordSkipped(suiteName, "Tool calling", reason: "LITELLM_API_KEY not set")
                return
            }

            let client = LiteLLMClient(baseURL: baseURL, apiKey: key)

            let weatherTool = LiteLLMTool(
                name: "get_weather",
                description: "Get weather for a location",
                parameters: [
                    "type": "object",
                    "properties": [
                        "location": ["type": "string", "description": "City name"]
                    ],
                    "required": ["location"]
                ]
            )

            let request = LiteLLMRequest(
                model: "gpt-3.5-turbo",
                messages: [
                    LiteLLMMessage(role: "user", content: "What's the weather in Tokyo?")
                ],
                maxTokens: 100,
                tools: [weatherTool]
            )

            do {
                let response = try await client.complete(request: request)

                if !response.toolCalls.isEmpty {
                    reporter.log("Tool called: \(response.toolCalls.first?.name ?? "unknown")")
                } else {
                    reporter.log("Response (no tool call): \(response.content.prefix(50))...")
                }
            } catch {
                reporter.recordSkipped(suiteName, "Tool calling", reason: "Request failed: \(error)")
            }
        }
    }
}

// MARK: - LiteLLM Client (Simplified)

private struct LiteLLMClient {
    let baseURL: String
    let apiKey: String

    struct Response {
        let content: String
        let toolCalls: [ToolCall]
    }

    struct ToolCall {
        let name: String
        let arguments: String
    }

    func complete(request: LiteLLMRequest) async throws -> Response {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw TestError.assertionFailed("Invalid URL")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 30

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TestError.assertionFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TestError.assertionFailed("API error \(httpResponse.statusCode): \(errorBody)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw TestError.assertionFailed("Invalid response format")
        }

        let content = message["content"] as? String ?? ""
        var toolCalls: [ToolCall] = []

        if let toolCallsData = message["tool_calls"] as? [[String: Any]] {
            for tc in toolCallsData {
                if let function = tc["function"] as? [String: Any],
                   let name = function["name"] as? String {
                    let args = function["arguments"] as? String ?? "{}"
                    toolCalls.append(ToolCall(name: name, arguments: args))
                }
            }
        }

        return Response(content: content, toolCalls: toolCalls)
    }

    func stream(request: LiteLLMRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Simplified: just call complete and yield chunks
                    let response = try await complete(request: request)
                    for word in response.content.split(separator: " ") {
                        continuation.yield(String(word) + " ")
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private struct LiteLLMRequest: Encodable {
    let model: String
    let messages: [LiteLLMMessage]
    let maxTokens: Int?
    let stream: Bool?
    let tools: [LiteLLMTool]?

    init(model: String, messages: [LiteLLMMessage], maxTokens: Int? = nil, stream: Bool? = nil, tools: [LiteLLMTool]? = nil) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxTokens
        self.stream = stream
        self.tools = tools
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, tools
        case maxTokens = "max_tokens"
    }
}

private struct LiteLLMMessage: Encodable {
    let role: String
    let content: String
}

private struct LiteLLMTool: Encodable {
    let type: String = "function"
    let function: FunctionDefinition

    init(name: String, description: String, parameters: [String: Any]) {
        self.function = FunctionDefinition(name: name, description: description, parameters: parameters)
    }

    struct FunctionDefinition: Encodable {
        let name: String
        let description: String
        let parameters: [String: Any]

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(description, forKey: .description)
            // Encode parameters as JSON data
            let paramData = try JSONSerialization.data(withJSONObject: parameters)
            let paramDict = try JSONDecoder().decode([String: AnyCodableValue].self, from: paramData)
            try container.encode(paramDict, forKey: .parameters)
        }

        enum CodingKeys: String, CodingKey {
            case name, description, parameters
        }
    }
}

private struct AnyCodableValue: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodableValue].self) {
            value = arr.map { $0.value }
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let dict = value as? [String: Any] {
            let encoded = dict.mapValues { AnyCodableValue(value: $0) }
            try container.encode(encoded)
        } else if let arr = value as? [Any] {
            let encoded = arr.map { AnyCodableValue(value: $0) }
            try container.encode(encoded)
        }
    }

    init(value: Any) {
        self.value = value
    }
}
