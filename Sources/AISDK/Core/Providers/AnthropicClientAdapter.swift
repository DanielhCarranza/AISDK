//
//  AnthropicClientAdapter.swift
//  AISDK
//
//  Direct Anthropic provider client adapter for Phase 2 routing layer
//  Provides direct access to Anthropic API as a ProviderClient
//

import Foundation

// MARK: - AnthropicClientAdapter

/// Direct Anthropic provider client for the Phase 2 routing layer
///
/// This adapter provides direct access to Anthropic's Messages API,
/// bypassing routers like OpenRouter or LiteLLM when direct provider access
/// is needed (e.g., for cost optimization, specific model access, or failover).
///
/// ## Features
/// - Direct Anthropic API access
/// - Full streaming support with SSE parsing
/// - Tool calling support
/// - Health status tracking
/// - Thinking delta passthrough (when enabled via beta headers externally)
///
/// ## Usage
/// ```swift
/// let client = AnthropicClientAdapter(apiKey: "sk-ant-...")
/// let request = ProviderRequest(modelId: "claude-sonnet-4-20250514", messages: [...])
/// let response = try await client.execute(request: request)
/// ```
public actor AnthropicClientAdapter: ProviderClient {
    // MARK: - Identity

    public nonisolated let providerId: String = "anthropic"
    public nonisolated let displayName: String = "Anthropic"
    public nonisolated let baseURL: URL

    // MARK: - Configuration

    private let apiKey: String
    private let session: URLSession
    private let anthropicVersion: String

    // MARK: - State

    private var _healthStatus: ProviderHealthStatus = .unknown

    // MARK: - Constants

    private static let defaultBaseURL = URL(string: "https://api.anthropic.com")!
    private static let messagesEndpoint = "v1/messages"
    private static let defaultAnthropicVersion = "2023-06-01"

    // Known Claude models (Anthropic doesn't have a models endpoint)
    private static let knownModels = [
        "claude-opus-4-20250514",
        "claude-sonnet-4-20250514",
        "claude-3-5-sonnet-20241022",
        "claude-3-5-sonnet-20240620",
        "claude-3-5-haiku-20241022",
        "claude-3-opus-20240229",
        "claude-3-sonnet-20240229",
        "claude-3-haiku-20240307"
    ]

    // MARK: - Initialization

    /// Initialize AnthropicClientAdapter with API key and optional configuration
    /// - Parameters:
    ///   - apiKey: Anthropic API key (starts with "sk-ant-")
    ///   - baseURL: Optional custom base URL (defaults to https://api.anthropic.com)
    ///   - session: Optional URLSession for dependency injection
    ///   - anthropicVersion: API version string (defaults to 2023-06-01)
    public init(
        apiKey: String,
        baseURL: URL? = nil,
        session: URLSession? = nil,
        anthropicVersion: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.session = session ?? .shared
        self.anthropicVersion = anthropicVersion ?? Self.defaultAnthropicVersion
    }

    // MARK: - Health & Status

    public var healthStatus: ProviderHealthStatus {
        _healthStatus
    }

    public var isAvailable: Bool {
        _healthStatus.acceptsTraffic
    }

    /// Refresh health status by making a lightweight API call
    public func refreshHealthStatus() async {
        do {
            // Anthropic doesn't have a health endpoint, so we try a minimal message
            // Using a simple request to verify API key and connectivity
            let testRequest = ProviderRequest(
                modelId: "claude-3-haiku-20240307",
                messages: [.user("Hi")],
                maxTokens: 1,
                timeout: 10
            )
            let httpRequest = try buildHTTPRequest(for: testRequest, streaming: false)
            let (data, response) = try await performRequest(httpRequest, timeout: 10)

            guard let httpResponse = response as? HTTPURLResponse else {
                _healthStatus = .unhealthy(reason: "Invalid response type")
                return
            }

            // Any 2xx or even 4xx (except auth) means the API is reachable
            switch httpResponse.statusCode {
            case 200..<300:
                _healthStatus = .healthy
            case 401, 403:
                let errorMessage = parseErrorMessage(from: data) ?? "Authentication failed"
                _healthStatus = .unhealthy(reason: errorMessage)
            case 429:
                _healthStatus = .degraded(reason: "Rate limited")
            case 500..<600:
                let errorMessage = parseErrorMessage(from: data) ?? "Server error"
                _healthStatus = .unhealthy(reason: errorMessage)
            default:
                _healthStatus = .healthy // API is reachable
            }
        } catch let error as ProviderError {
            switch error {
            case .authenticationFailed:
                _healthStatus = .unhealthy(reason: "Authentication failed")
            case .rateLimited:
                _healthStatus = .degraded(reason: "Rate limited")
            case .serverError(let statusCode, let message):
                _healthStatus = .unhealthy(reason: "Server error \(statusCode): \(message)")
            case .networkError(let message):
                _healthStatus = .unhealthy(reason: "Network error: \(message)")
            default:
                _healthStatus = .unhealthy(reason: error.localizedDescription)
            }
        } catch {
            _healthStatus = .unhealthy(reason: error.localizedDescription)
        }
    }

    // MARK: - Request Execution

    public func execute(request: ProviderRequest) async throws -> ProviderResponse {
        let startTime = Date()
        let httpRequest = try buildHTTPRequest(for: request, streaming: false)

        let (data, response) = try await performRequest(httpRequest, timeout: request.timeout)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response type")
        }

        try validateHTTPResponse(httpResponse, data: data)

        let messageResponse = try parseMessageResponse(data)
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Update health status on successful request
        _healthStatus = .healthy

        return buildProviderResponse(from: messageResponse, latencyMs: latencyMs)
    }

    public nonisolated func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.performStreaming(request: request, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            // Cancel the producer task when the consumer cancels
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Model Information

    public var availableModels: [String] {
        get async throws {
            // Anthropic doesn't have a models endpoint, return known models
            return Self.knownModels
        }
    }

    public func isModelAvailable(_ modelId: String) async -> Bool {
        // Check if it's a known model or matches Claude naming pattern
        return Self.knownModels.contains(modelId) || modelId.hasPrefix("claude-")
    }

    public func capabilities(for modelId: String) async -> LLMCapabilities? {
        // Return known capabilities for Claude models
        switch modelId {
        case let id where id.contains("opus"):
            return [.text, .vision, .tools, .streaming, .functionCalling, .reasoning, .longContext]
        case let id where id.contains("sonnet"):
            return [.text, .vision, .tools, .streaming, .functionCalling, .longContext]
        case let id where id.contains("haiku"):
            return [.text, .vision, .tools, .streaming, .functionCalling]
        default:
            // Generic Claude capabilities
            return [.text, .tools, .streaming, .functionCalling]
        }
    }

    // MARK: - Private Methods

    private func buildHTTPRequest(for request: ProviderRequest, streaming: Bool) throws -> URLRequest {
        let endpoint = baseURL.appendingPathComponent(Self.messagesEndpoint)
        var httpRequest = URLRequest(url: endpoint)
        httpRequest.httpMethod = "POST"
        httpRequest.timeoutInterval = request.timeout

        // Required headers for Anthropic API
        httpRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        httpRequest.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Accept header for streaming
        if streaming {
            httpRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        // Build request body
        let body = try buildRequestBody(from: request, streaming: streaming)
        httpRequest.httpBody = try JSONEncoder().encode(body)

        return httpRequest
    }

    private func buildRequestBody(from request: ProviderRequest, streaming: Bool) throws -> ACARequestBody {
        // Extract system message if present (Anthropic handles system separately)
        var systemContent: String?
        var nonSystemMessages: [AIMessage] = []

        for message in request.messages {
            if message.role == .system {
                // Combine multiple system messages
                let text = message.content.textValue
                if let existing = systemContent {
                    systemContent = existing + "\n\n" + text
                } else {
                    systemContent = text
                }
            } else {
                nonSystemMessages.append(message)
            }
        }

        // Convert messages to Anthropic format
        let messages = try nonSystemMessages.map { message -> ACAMessage in
            let content: [ACAContentBlock]

            switch message.content {
            case .text(let text):
                if message.role == .tool {
                    // Tool results use tool_result content type - require toolCallId
                    guard let toolCallId = message.toolCallId, !toolCallId.isEmpty else {
                        throw ProviderError.invalidRequest("Tool message requires non-empty toolCallId")
                    }
                    content = [.toolResult(ACAToolResultContent(
                        type: "tool_result",
                        toolUseId: toolCallId,
                        content: text
                    ))]
                } else {
                    content = [.text(ACATextContent(type: "text", text: text))]
                }
            case .parts(let parts):
                content = try parts.map { part -> ACAContentBlock in
                    switch part {
                    case .text(let text):
                        return .text(ACATextContent(type: "text", text: text))
                    case .image(let data, let mimeType):
                        let base64 = data.base64EncodedString()
                        return .image(ACAImageContent(
                            type: "image",
                            source: ACAImageSource(
                                type: "base64",
                                mediaType: mimeType,
                                data: base64
                            )
                        ))
                    case .imageURL:
                        // Anthropic requires base64 images, URLs not supported
                        throw ProviderError.invalidRequest("Anthropic does not support image URLs - provide base64 image data instead")
                    case .audio:
                        throw ProviderError.invalidRequest("Anthropic does not support audio content")
                    case .file:
                        throw ProviderError.invalidRequest("Anthropic does not support file content in this format")
                    }
                }
            }

            // Handle tool calls in assistant messages
            var finalContent = content
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                for toolCall in toolCalls {
                    // Parse arguments JSON string to dictionary
                    var inputDict: [String: ProviderJSONValue] = [:]
                    if let argsData = toolCall.arguments.data(using: .utf8),
                       let parsedArgs = try? JSONDecoder().decode([String: ProviderJSONValue].self, from: argsData) {
                        inputDict = parsedArgs
                    }

                    finalContent.append(.toolUse(ACAToolUseContent(
                        type: "tool_use",
                        id: toolCall.id,
                        name: toolCall.name,
                        input: inputDict
                    )))
                }
            }

            return ACAMessage(
                role: message.role == .assistant ? "assistant" : "user",
                content: finalContent
            )
        }

        var body = ACARequestBody(
            model: request.modelId,
            messages: messages,
            maxTokens: request.maxTokens ?? 4096 // Anthropic requires max_tokens
        )

        // Optional parameters
        body.system = systemContent
        body.temperature = request.temperature
        body.topP = request.topP
        body.stopSequences = request.stop
        body.stream = streaming

        // Tool choice - handle before tools conversion
        var shouldOmitTools = false
        if let toolChoice = request.toolChoice {
            switch toolChoice {
            case .auto:
                body.toolChoice = ACAToolChoice(type: "auto")
            case .none:
                // Anthropic doesn't have explicit "none" - omit tools entirely
                shouldOmitTools = true
            case .required:
                body.toolChoice = ACAToolChoice(type: "any")
            case .tool(let name):
                body.toolChoice = ACAToolChoice(type: "tool", name: name)
            }
        }

        // Tools - convert from ProviderJSONValue to Anthropic format (unless toolChoice is .none)
        if !shouldOmitTools, let tools = request.tools {
            var convertedTools: [ACATool] = []
            for (index, toolValue) in tools.enumerated() {
                guard case .object(let toolDict) = toolValue else {
                    throw ProviderError.invalidRequest("Tool at index \(index) is not an object")
                }
                guard case .object(let functionDict)? = toolDict["function"] else {
                    throw ProviderError.invalidRequest("Tool at index \(index) missing function definition")
                }
                guard case .string(let name)? = functionDict["name"], !name.isEmpty else {
                    throw ProviderError.invalidRequest("Tool at index \(index) missing function name")
                }

                let description: String?
                if case .string(let desc)? = functionDict["description"] {
                    description = desc
                } else {
                    description = nil
                }

                // Convert parameters (input_schema in Anthropic)
                let inputSchema: [String: ProviderJSONValue]?
                if case .object(let params)? = functionDict["parameters"] {
                    inputSchema = params
                } else {
                    inputSchema = nil
                }

                convertedTools.append(ACATool(
                    name: name,
                    description: description,
                    inputSchema: inputSchema ?? ["type": .string("object")]
                ))
            }
            body.tools = convertedTools
        }

        return body
    }

    private func performRequest(_ request: URLRequest, timeout: TimeInterval) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .timedOut:
                throw ProviderError.timeout(timeout)
            case .notConnectedToInternet, .networkConnectionLost:
                throw ProviderError.networkError("No internet connection")
            case .cannotFindHost, .cannotConnectToHost:
                throw ProviderError.networkError("Cannot connect to Anthropic")
            default:
                throw ProviderError.networkError(error.localizedDescription)
            }
        }
    }

    private func validateHTTPResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 400:
            let errorMessage = parseErrorMessage(from: data) ?? "Bad request"
            throw ProviderError.invalidRequest(errorMessage)
        case 401:
            let errorMessage = parseErrorMessage(from: data) ?? "Invalid API key"
            throw ProviderError.authenticationFailed(errorMessage)
        case 403:
            let errorMessage = parseErrorMessage(from: data) ?? "Access forbidden"
            throw ProviderError.authenticationFailed(errorMessage)
        case 404:
            let errorMessage = parseErrorMessage(from: data) ?? "Resource not found"
            if errorMessage.lowercased().contains("model") {
                throw ProviderError.modelNotFound(errorMessage)
            }
            throw ProviderError.invalidRequest("Not found: \(errorMessage)")
        case 422:
            let errorMessage = parseErrorMessage(from: data) ?? "Unprocessable entity"
            throw ProviderError.invalidRequest(errorMessage)
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                .flatMap { TimeInterval($0) }
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        case 500..<600:
            let errorMessage = parseErrorMessage(from: data) ?? "Server error"
            throw ProviderError.serverError(statusCode: response.statusCode, message: errorMessage)
        default:
            let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"
            throw ProviderError.unknown("HTTP \(response.statusCode): \(errorMessage)")
        }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        struct ErrorResponse: Decodable {
            struct ErrorDetail: Decodable {
                let message: String?
                let type: String?
            }
            let error: ErrorDetail?
            let type: String?
            let message: String?
        }

        guard let response = try? JSONDecoder().decode(ErrorResponse.self, from: data) else {
            return nil
        }

        // Anthropic can return error in either format
        if let error = response.error {
            var message = error.message ?? "Unknown error"
            if let type = error.type {
                message += " [type: \(type)]"
            }
            return message
        } else if let message = response.message {
            var result = message
            if let type = response.type {
                result += " [type: \(type)]"
            }
            return result
        }

        return nil
    }

    private func parseMessageResponse(_ data: Data) throws -> ACAMessageResponse {
        do {
            return try JSONDecoder().decode(ACAMessageResponse.self, from: data)
        } catch {
            throw ProviderError.parseError("Failed to parse message response: \(error.localizedDescription)")
        }
    }

    private func buildProviderResponse(from response: ACAMessageResponse, latencyMs: Int) -> ProviderResponse {
        // Extract text content
        var textContent = ""
        var toolCalls: [ProviderToolCall] = []

        for block in response.content {
            switch block {
            case .text(let textBlock):
                textContent += textBlock.text
            case .toolUse(let toolUseBlock):
                // Convert input dictionary to JSON string
                let encoder = JSONEncoder()
                let argsString: String
                if let argsData = try? encoder.encode(toolUseBlock.input),
                   let argsStr = String(data: argsData, encoding: .utf8) {
                    argsString = argsStr
                } else {
                    argsString = "{}"
                }

                toolCalls.append(ProviderToolCall(
                    id: toolUseBlock.id,
                    name: toolUseBlock.name,
                    arguments: argsString
                ))
            case .toolResult, .image:
                // These shouldn't appear in responses
                break
            }
        }

        let usage = ProviderUsage(
            promptTokens: response.usage.inputTokens,
            completionTokens: response.usage.outputTokens,
            cachedTokens: response.usage.cacheReadInputTokens
        )

        let finishReason = ProviderFinishReason(providerReason: response.stopReason)

        return ProviderResponse(
            id: response.id,
            model: response.model,
            provider: providerId,
            content: textContent,
            toolCalls: toolCalls,
            usage: usage,
            finishReason: finishReason,
            latencyMs: latencyMs
        )
    }

    private func performStreaming(
        request: ProviderRequest,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async throws {
        let httpRequest = try buildHTTPRequest(for: request, streaming: true)

        let (bytes, response) = try await session.bytes(for: httpRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response type")
        }

        // Handle non-2xx responses
        guard (200..<300).contains(httpResponse.statusCode) else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            try validateHTTPResponse(httpResponse, data: errorData)
            return
        }

        // Track tool calls by content block index (not by tool_use_id) since Anthropic
        // sends deltas and stop events by index. Map index -> tool state.
        struct ToolCallState {
            var id: String
            var name: String
            var arguments: String
            var startEmitted: Bool
        }
        var toolCallsByIndex: [Int: ToolCallState] = [:]
        var totalUsage: ProviderUsage?
        var lastFinishReason: ProviderFinishReason?
        var decodeErrorCount = 0
        let maxDecodeErrors = 5

        for try await line in bytes.lines {
            // Skip empty lines and comments
            guard !line.isEmpty, !line.hasPrefix(":") else { continue }

            // Parse SSE event type
            if line.hasPrefix("event:") {
                // We handle events implicitly based on data content
                continue
            }

            // Parse SSE data line
            guard line.hasPrefix("data:") else { continue }
            let jsonString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)

            guard let chunkData = jsonString.data(using: .utf8) else { continue }

            do {
                let event = try JSONDecoder().decode(ACAStreamEvent.self, from: chunkData)

                switch event.type {
                case "message_start":
                    if let message = event.message {
                        continuation.yield(.start(id: message.id, model: message.model))

                        // Emit initial usage if present
                        if let usage = message.usage {
                            totalUsage = ProviderUsage(
                                promptTokens: usage.inputTokens ?? 0,
                                completionTokens: usage.outputTokens ?? 0
                            )
                        }
                    }

                case "content_block_start":
                    if let contentBlock = event.contentBlock, let index = event.index {
                        switch contentBlock {
                        case .toolUse(let toolUse):
                            // Start of a tool call - track by index
                            toolCallsByIndex[index] = ToolCallState(
                                id: toolUse.id,
                                name: toolUse.name,
                                arguments: "",
                                startEmitted: true
                            )
                            continuation.yield(.toolCallStart(id: toolUse.id, name: toolUse.name))
                        case .text:
                            // Text block starting, nothing special needed
                            break
                        }
                    }

                case "content_block_delta":
                    if let delta = event.delta {
                        switch delta {
                        case .textDelta(let textDelta):
                            continuation.yield(.textDelta(textDelta.text))
                        case .inputJsonDelta(let jsonDelta):
                            // Tool call argument delta - look up by index
                            if let index = event.index, var toolCall = toolCallsByIndex[index] {
                                toolCall.arguments += jsonDelta.partialJson
                                toolCallsByIndex[index] = toolCall
                                continuation.yield(.toolCallDelta(id: toolCall.id, argumentsDelta: jsonDelta.partialJson))
                            }
                        case .thinkingDelta(let thinking):
                            continuation.yield(.reasoningDelta(thinking.thinking))
                        case .messageDelta:
                            // Message delta shouldn't appear in content_block_delta, but handle gracefully
                            break
                        }
                    }

                case "content_block_stop":
                    // End of a content block - emit tool call finish only if this index was a tool_use block
                    if let index = event.index, let toolCall = toolCallsByIndex[index] {
                        if toolCall.startEmitted {
                            continuation.yield(.toolCallFinish(
                                id: toolCall.id,
                                name: toolCall.name,
                                arguments: toolCall.arguments
                            ))
                        }
                    }

                case "message_delta":
                    if let delta = event.delta,
                       case .messageDelta(let msgDelta) = delta {
                        if let stopReason = msgDelta.stopReason {
                            lastFinishReason = ProviderFinishReason(providerReason: stopReason)
                        }
                    }

                    if let usage = event.usage {
                        totalUsage = ProviderUsage(
                            promptTokens: usage.inputTokens ?? totalUsage?.promptTokens ?? 0,
                            completionTokens: usage.outputTokens ?? 0
                        )
                        continuation.yield(.usage(totalUsage!))
                    }

                case "message_stop":
                    // Stream complete
                    let reason = lastFinishReason ?? .stop
                    continuation.yield(.finish(reason: reason, usage: totalUsage))
                    continuation.finish()
                    return

                case "error":
                    if let error = event.error {
                        throw ProviderError.serverError(
                            statusCode: 0,
                            message: "\(error.type): \(error.message)"
                        )
                    }

                case "ping":
                    // Keep-alive, ignore
                    break

                default:
                    // Unknown event type, ignore
                    break
                }
            } catch let error as ProviderError {
                throw error
            } catch {
                decodeErrorCount += 1
                if decodeErrorCount >= maxDecodeErrors {
                    throw ProviderError.parseError("Too many SSE decode failures (\(decodeErrorCount)). Last line: \(jsonString.prefix(200))")
                }
                continue
            }
        }

        // Stream ended without message_stop
        continuation.yield(.finish(reason: lastFinishReason ?? .unknown, usage: totalUsage))
        continuation.finish()
    }
}

// MARK: - AnthropicClientAdapter API Types (ACA prefix to avoid collision with existing types)

/// Anthropic request body structure for AnthropicClientAdapter
private struct ACARequestBody: Encodable {
    let model: String
    let messages: [ACAMessage]
    let maxTokens: Int

    var system: String?
    var temperature: Double?
    var topP: Double?
    var stopSequences: [String]?
    var stream: Bool?
    var tools: [ACATool]?
    var toolChoice: ACAToolChoice?

    enum CodingKeys: String, CodingKey {
        case model, messages, system, temperature, stream, tools
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case stopSequences = "stop_sequences"
        case toolChoice = "tool_choice"
    }
}

private struct ACAMessage: Encodable {
    let role: String
    let content: [ACAContentBlock]
}

private enum ACAContentBlock: Encodable {
    case text(ACATextContent)
    case image(ACAImageContent)
    case toolUse(ACAToolUseContent)
    case toolResult(ACAToolResultContent)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let content):
            try container.encode(content)
        case .image(let content):
            try container.encode(content)
        case .toolUse(let content):
            try container.encode(content)
        case .toolResult(let content):
            try container.encode(content)
        }
    }
}

private struct ACATextContent: Codable {
    let type: String
    let text: String
}

private struct ACAImageContent: Encodable {
    let type: String
    let source: ACAImageSource
}

private struct ACAImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }
}

private struct ACAToolUseContent: Codable {
    let type: String
    let id: String
    let name: String
    let input: [String: ProviderJSONValue]
}

private struct ACAToolResultContent: Encodable {
    let type: String
    let toolUseId: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
    }
}

private struct ACATool: Encodable {
    let name: String
    let description: String?
    let inputSchema: [String: ProviderJSONValue]

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

private struct ACAToolChoice: Encodable {
    let type: String
    let name: String?

    init(type: String, name: String? = nil) {
        self.type = type
        self.name = name
    }
}

// MARK: - Response Types

private struct ACAMessageResponse: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [ACAResponseContentBlock]
    let model: String
    let stopReason: String?
    let usage: ACAUsage

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model, usage
        case stopReason = "stop_reason"
    }
}

private enum ACAResponseContentBlock: Decodable {
    case text(ACATextContent)
    case toolUse(ACAToolUseContent)
    case toolResult(ACAToolResultContent)
    case image(ACAImageContent)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try ACATextContent(from: decoder))
        case "tool_use":
            self = .toolUse(try ACAToolUseContent(from: decoder))
        case "tool_result":
            self = .toolResult(try ACAToolResultContentDecodable(from: decoder).toContent())
        default:
            // Default to empty text for unknown types
            self = .text(ACATextContent(type: type, text: ""))
        }
    }
}

// Helper for decoding tool_result which has different encoding/decoding shapes
private struct ACAToolResultContentDecodable: Decodable {
    let type: String
    let toolUseId: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
    }

    func toContent() -> ACAToolResultContent {
        ACAToolResultContent(type: type, toolUseId: toolUseId, content: content)
    }
}

private struct ACAUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

// MARK: - Streaming Types

private struct ACAStreamEvent: Decodable {
    let type: String
    let message: ACAStreamMessage?
    let index: Int?
    let contentBlock: ACAStreamContentBlock?
    let delta: ACAStreamDelta?
    let usage: ACAStreamUsage?
    let error: ACAStreamError?

    enum CodingKeys: String, CodingKey {
        case type, message, index, delta, usage, error
        case contentBlock = "content_block"
    }
}

private struct ACAStreamMessage: Decodable {
    let id: String
    let type: String
    let role: String
    let model: String
    let usage: ACAStreamUsage?
}

private enum ACAStreamContentBlock: Decodable {
    case text(ACATextContent)
    case toolUse(ACAStreamToolUse)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try ACATextContent(from: decoder))
        case "tool_use":
            self = .toolUse(try ACAStreamToolUse(from: decoder))
        default:
            self = .text(ACATextContent(type: type, text: ""))
        }
    }
}

private struct ACAStreamToolUse: Decodable {
    let type: String
    let id: String
    let name: String
}

private enum ACAStreamDelta: Decodable {
    case textDelta(ACATextDelta)
    case inputJsonDelta(ACAInputJsonDelta)
    case thinkingDelta(ACAThinkingDelta)
    case messageDelta(ACAMessageDelta)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text_delta":
            self = .textDelta(try ACATextDelta(from: decoder))
        case "input_json_delta":
            self = .inputJsonDelta(try ACAInputJsonDelta(from: decoder))
        case "thinking_delta":
            self = .thinkingDelta(try ACAThinkingDelta(from: decoder))
        case "message_delta":
            self = .messageDelta(try ACAMessageDelta(from: decoder))
        default:
            // Default to empty text delta for unknown types
            self = .textDelta(ACATextDelta(type: type, text: ""))
        }
    }
}

private struct ACATextDelta: Decodable {
    let type: String
    let text: String
}

private struct ACAInputJsonDelta: Decodable {
    let type: String
    let partialJson: String

    enum CodingKeys: String, CodingKey {
        case type
        case partialJson = "partial_json"
    }
}

private struct ACAThinkingDelta: Decodable {
    let type: String
    let thinking: String
}

private struct ACAMessageDelta: Decodable {
    let type: String
    let stopReason: String?
    let stopSequence: String?

    enum CodingKeys: String, CodingKey {
        case type
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
    }
}

private struct ACAStreamUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

private struct ACAStreamError: Decodable {
    let type: String
    let message: String
}
