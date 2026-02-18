//
//  LiteLLMClient.swift
//  AISDK
//
//  LiteLLM provider client implementation for Phase 2 routing layer
//  Secondary/fallback router for self-hosted deployments
//

import Foundation

// MARK: - LiteLLMClient

/// LiteLLM provider client for self-hosted AI routing
///
/// LiteLLM is an open-source proxy that provides a unified OpenAI-compatible API
/// for 100+ LegacyLLM providers. It's designed for self-hosted deployments where you need
/// full control over routing and cost management.
///
/// ## Features
/// - Self-hosted deployment option
/// - OpenAI-compatible API format
/// - Support for local models and custom endpoints
/// - Cost tracking and rate limiting
///
/// ## Usage
/// ```swift
/// let client = LiteLLMClient(baseURL: URL(string: "http://localhost:4000")!)
/// let request = ProviderRequest(modelId: "gpt-4", messages: [...])
/// let response = try await client.execute(request: request)
/// ```
public actor LiteLLMClient: ProviderClient {
    // MARK: - Identity

    public nonisolated let providerId: String = "litellm"
    public nonisolated let displayName: String = "LiteLLM"
    public nonisolated let baseURL: URL

    // MARK: - Configuration

    private let apiKey: String?
    private let session: URLSession

    // MARK: - State

    private var _healthStatus: ProviderHealthStatus = .unknown
    private var cachedModels: [String]?
    private var lastModelsFetch: Date?
    private let modelsCacheDuration: TimeInterval = 300 // 5 minutes

    // MARK: - Constants

    private static let defaultBaseURL = URL(string: "http://localhost:4000")!
    private static let modelsEndpoint = "models"
    private static let chatCompletionsEndpoint = "chat/completions"
    private static let healthEndpoint = "health"

    // MARK: - Initialization

    /// Initialize LiteLLMClient with optional base URL and API key
    /// - Parameters:
    ///   - baseURL: LiteLLM server URL (defaults to http://localhost:4000)
    ///   - apiKey: Optional API key for authenticated deployments
    ///   - session: Optional URLSession for dependency injection
    public init(
        baseURL: URL? = nil,
        apiKey: String? = nil,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.apiKey = apiKey
        self.session = session ?? .shared
    }

    // MARK: - Health & Status

    public var healthStatus: ProviderHealthStatus {
        _healthStatus
    }

    public var isAvailable: Bool {
        _healthStatus.acceptsTraffic
    }

    /// Refresh health status by pinging the health endpoint
    public func refreshHealthStatus() async {
        do {
            let isHealthy = try await checkHealth()
            if isHealthy {
                _healthStatus = .healthy
            } else {
                _healthStatus = .unhealthy(reason: "Health check returned non-2xx status")
            }
        } catch let error as ProviderError {
            switch error {
            case .authenticationFailed(let message):
                _healthStatus = .unhealthy(reason: "Authentication failed: \(message)")
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

        let completionResponse = try parseCompletionResponse(data)
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Update health status on successful request
        _healthStatus = .healthy

        return try buildProviderResponse(from: completionResponse, latencyMs: latencyMs)
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
            // Return cached models if still valid
            if let cached = cachedModels,
               let lastFetch = lastModelsFetch,
               Date().timeIntervalSince(lastFetch) < modelsCacheDuration {
                return cached
            }

            let models = try await fetchModels()
            cachedModels = models
            lastModelsFetch = Date()
            return models
        }
    }

    public func isModelAvailable(_ modelId: String) async -> Bool {
        do {
            let models = try await availableModels
            return models.contains(modelId)
        } catch {
            return false
        }
    }

    public func capabilities(for modelId: String) async -> LLMCapabilities? {
        // LiteLLM can provide model metadata, but for now return nil
        // This can be enhanced in a future task to parse model capabilities
        // from the /models endpoint response
        return nil
    }

    // MARK: - Private Methods

    private func buildHTTPRequest(for request: ProviderRequest, streaming: Bool) throws -> URLRequest {
        let endpoint = baseURL.appendingPathComponent(Self.chatCompletionsEndpoint)
        var httpRequest = URLRequest(url: endpoint)
        httpRequest.httpMethod = "POST"
        httpRequest.timeoutInterval = request.timeout

        // Headers
        if let apiKey = apiKey {
            httpRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // For streaming requests, set Accept header for SSE
        if streaming {
            httpRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        // Build request body
        let body = try buildRequestBody(from: request, streaming: streaming)
        httpRequest.httpBody = try JSONEncoder().encode(body)

        return httpRequest
    }

    private func buildRequestBody(from request: ProviderRequest, streaming: Bool) throws -> LiteLLMRequestBody {
        let messages = request.messages.map { message -> LiteLLMMessage in
            let content: LiteLLMContent
            switch message.content {
            case .text(let text):
                content = .text(text)
            case .parts(let parts):
                let litellmParts = parts.map { part -> LiteLLMContentPart in
                    switch part {
                    case .text(let text):
                        return .text(text)
                    case .image(let data, let mimeType):
                        let base64 = data.base64EncodedString()
                        return .imageURL("data:\(mimeType);base64,\(base64)")
                    case .imageURL(let url):
                        return .imageURL(url)
                    case .audio, .file, .video, .videoURL:
                        // Not directly supported, fall back to text description
                        return .text("[Unsupported content type]")
                    }
                }
                content = .parts(litellmParts)
            }

            return LiteLLMMessage(
                role: message.role.rawValue,
                content: content,
                name: message.name,
                toolCalls: message.toolCalls?.map { tc in
                    LiteLLMToolCall(
                        id: tc.id,
                        type: "function",
                        function: LiteLLMFunctionCall(name: tc.name, arguments: tc.arguments)
                    )
                },
                toolCallId: message.toolCallId
            )
        }

        var body = LiteLLMRequestBody(
            model: request.modelId,
            messages: messages,
            stream: streaming
        )

        // Optional parameters
        body.maxTokens = request.maxTokens
        body.temperature = request.temperature
        body.topP = request.topP
        body.stop = request.stop

        // Tool choice
        if let toolChoice = request.toolChoice {
            switch toolChoice {
            case .auto:
                body.toolChoice = .string("auto")
            case .none:
                body.toolChoice = .string("none")
            case .required:
                body.toolChoice = .string("required")
            case .tool(let name):
                body.toolChoice = .object(LiteLLMToolChoiceObject(type: "function", function: LiteLLMFunctionName(name: name)))
            }
        }

        // Response format
        if let responseFormat = request.responseFormat {
            switch responseFormat {
            case .text:
                body.responseFormat = LiteLLMResponseFormat(type: "text")
            case .json:
                body.responseFormat = LiteLLMResponseFormat(type: "json_object")
            case .jsonSchema(let name, let schema):
                // Parse schema string into JSON object
                let jsonSchema = try LiteLLMJSONSchema(name: name, schemaString: schema)
                body.responseFormat = LiteLLMResponseFormat(
                    type: "json_schema",
                    jsonSchema: jsonSchema
                )
            }
        }

        // Tools - validate all tools convert successfully
        if let tools = request.tools {
            var convertedTools: [LiteLLMTool] = []
            for (index, toolValue) in tools.enumerated() {
                // Convert ProviderJSONValue to LiteLLMTool
                guard case .object(let toolDict) = toolValue else {
                    throw ProviderError.invalidRequest("Tool at index \(index) is not an object")
                }
                guard case .string(let type)? = toolDict["type"], type == "function" else {
                    throw ProviderError.invalidRequest("Tool at index \(index) missing type:'function'")
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

                // Convert parameters
                let parameters: [String: ProviderJSONValue]?
                if case .object(let params)? = functionDict["parameters"] {
                    parameters = params
                } else {
                    parameters = nil
                }

                convertedTools.append(LiteLLMTool(
                    type: "function",
                    function: LiteLLMFunctionDefinition(
                        name: name,
                        description: description,
                        parameters: parameters
                    )
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
                throw ProviderError.networkError("Cannot connect to LiteLLM server at \(baseURL.absoluteString)")
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
            // Check if it's a model not found error vs endpoint error
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
                let code: String?
                let type: String?
            }
            let error: ErrorDetail?
        }

        guard let response = try? JSONDecoder().decode(ErrorResponse.self, from: data),
              let error = response.error else {
            return nil
        }

        var message = error.message ?? "Unknown error"
        if let code = error.code {
            message += " (code: \(code))"
        }
        if let type = error.type {
            message += " [type: \(type)]"
        }
        return message
    }

    /// Parse SSE error frame (OpenAI/LiteLLM style)
    private func parseSSEErrorFrame(from data: Data) throws -> String? {
        struct SSEErrorFrame: Decodable {
            struct ErrorDetail: Decodable {
                let message: String?
                let code: String?
                let type: String?
            }
            let error: ErrorDetail?
        }

        let frame = try JSONDecoder().decode(SSEErrorFrame.self, from: data)
        guard let error = frame.error else { return nil }

        var message = error.message ?? "Stream error"
        if let code = error.code {
            message += " (code: \(code))"
        }
        if let type = error.type {
            message += " [type: \(type)]"
        }
        return message
    }

    private func parseCompletionResponse(_ data: Data) throws -> LiteLLMCompletionResponse {
        do {
            return try JSONDecoder().decode(LiteLLMCompletionResponse.self, from: data)
        } catch {
            throw ProviderError.parseError("Failed to parse completion response: \(error.localizedDescription)")
        }
    }

    private func buildProviderResponse(from response: LiteLLMCompletionResponse, latencyMs: Int) throws -> ProviderResponse {
        guard let choice = response.choices.first else {
            throw ProviderError.parseError("Response has no choices")
        }

        let content = choice.message.content ?? ""

        let toolCalls = choice.message.toolCalls?.map { tc in
            ProviderToolCall(
                id: tc.id,
                name: tc.function.name,
                arguments: tc.function.arguments
            )
        } ?? []

        let usage = response.usage.map { u in
            ProviderUsage(
                promptTokens: u.promptTokens,
                completionTokens: u.completionTokens,
                cachedTokens: u.cachedTokens,
                reasoningTokens: nil
            )
        }

        let finishReason = ProviderFinishReason(providerReason: choice.finishReason)

        return ProviderResponse(
            id: response.id,
            model: response.model,
            provider: providerId,
            content: content,
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

        // For streaming, we need to handle errors differently
        // because the response comes as SSE
        guard (200..<300).contains(httpResponse.statusCode) else {
            // Collect error data
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            try validateHTTPResponse(httpResponse, data: errorData)
            return
        }

        var responseId: String?
        // Key by index for accumulation; store (id, name, arguments, startEmitted)
        // When startEmitted=false, arguments accumulates pending deltas
        // When startEmitted=true, arguments is the full accumulated string so far
        var accumulatedToolCalls: [Int: (id: String, name: String, arguments: String, startEmitted: Bool)] = [:]
        var totalUsage: ProviderUsage?
        var lastFinishReason: ProviderFinishReason?
        var decodeErrorCount = 0
        let maxDecodeErrors = 5

        for try await line in bytes.lines {
            // Skip empty lines and comments
            guard !line.isEmpty, !line.hasPrefix(":") else { continue }

            // Parse SSE data line - accept "data:" with optional whitespace
            guard line.hasPrefix("data:") else { continue }
            let jsonString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)

            // Check for stream end - trim and compare
            if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                // Emit pending tool call finish events
                for (_, toolCall) in accumulatedToolCalls.sorted(by: { $0.key < $1.key }) {
                    if toolCall.startEmitted {
                        continuation.yield(.toolCallFinish(id: toolCall.id, name: toolCall.name, arguments: toolCall.arguments))
                    }
                }

                // Use last observed finish reason or default to .stop
                let reason = lastFinishReason ?? .stop
                continuation.yield(.finish(reason: reason, usage: totalUsage))
                continuation.finish()
                return
            }

            // Parse chunk
            guard let chunkData = jsonString.data(using: .utf8) else { continue }

            do {
                let chunk = try JSONDecoder().decode(LiteLLMStreamChunk.self, from: chunkData)

                // Emit start event on first chunk
                if responseId == nil {
                    responseId = chunk.id
                    continuation.yield(.start(id: chunk.id, model: chunk.model))
                }

                guard let delta = chunk.choices.first?.delta else { continue }

                // Text content
                if let content = delta.content, !content.isEmpty {
                    continuation.yield(.textDelta(content))
                }

                // Tool calls - key by index to handle multiple concurrent tool calls
                // Use stable index-based IDs until we can emit start with real ID
                if let toolCalls = delta.toolCalls {
                    for toolCall in toolCalls {
                        let index = toolCall.index ?? 0
                        // Use real ID if provided, else use existing or generate stable one
                        let stableId = toolCall.id ?? accumulatedToolCalls[index]?.id ?? "tool_call_\(index)"
                        let newName = toolCall.function?.name
                        let existingArgs = accumulatedToolCalls[index]?.arguments ?? ""
                        let existingName = accumulatedToolCalls[index]?.name ?? ""
                        let startEmitted = accumulatedToolCalls[index]?.startEmitted ?? false
                        let name = newName ?? existingName

                        // Get new argument delta (may be empty)
                        let argsDelta = toolCall.function?.arguments ?? ""

                        // Can we emit start? Need a name
                        if !startEmitted && !name.isEmpty {
                            continuation.yield(.toolCallStart(id: stableId, name: name))
                            // Now flush all buffered args as a single delta, then the new delta
                            if !existingArgs.isEmpty {
                                continuation.yield(.toolCallDelta(id: stableId, argumentsDelta: existingArgs))
                            }
                            if !argsDelta.isEmpty {
                                continuation.yield(.toolCallDelta(id: stableId, argumentsDelta: argsDelta))
                            }
                            accumulatedToolCalls[index] = (id: stableId, name: name, arguments: existingArgs + argsDelta, startEmitted: true)
                        } else if startEmitted {
                            // Already emitted start, emit delta directly
                            if !argsDelta.isEmpty {
                                continuation.yield(.toolCallDelta(id: stableId, argumentsDelta: argsDelta))
                            }
                            accumulatedToolCalls[index] = (id: stableId, name: name, arguments: existingArgs + argsDelta, startEmitted: true)
                        } else {
                            // Buffer until we can emit start (no name yet)
                            accumulatedToolCalls[index] = (id: stableId, name: name, arguments: existingArgs + argsDelta, startEmitted: false)
                        }
                    }
                }

                // Check for finish reason
                if let finishReason = chunk.choices.first?.finishReason {
                    let reason = ProviderFinishReason(providerReason: finishReason)
                    lastFinishReason = reason

                    // Emit tool call finish events
                    for (_, toolCall) in accumulatedToolCalls.sorted(by: { $0.key < $1.key }) {
                        if toolCall.startEmitted {
                            continuation.yield(.toolCallFinish(id: toolCall.id, name: toolCall.name, arguments: toolCall.arguments))
                        }
                    }
                    accumulatedToolCalls.removeAll()

                    // Parse usage if present
                    if let usage = chunk.usage {
                        totalUsage = ProviderUsage(
                            promptTokens: usage.promptTokens,
                            completionTokens: usage.completionTokens,
                            cachedTokens: usage.cachedTokens,
                            reasoningTokens: nil
                        )
                        continuation.yield(.usage(totalUsage!))
                    }

                    continuation.yield(.finish(reason: reason, usage: totalUsage))
                    continuation.finish()
                    return
                }
            } catch {
                // Check if this is an error frame from the provider
                if let errorFrame = try? parseSSEErrorFrame(from: chunkData) {
                    throw ProviderError.serverError(statusCode: 0, message: errorFrame)
                }

                // Track decode failures - fail after threshold
                decodeErrorCount += 1
                if decodeErrorCount >= maxDecodeErrors {
                    throw ProviderError.parseError("Too many SSE decode failures (\(decodeErrorCount)). Last line: \(jsonString.prefix(200))")
                }
                // Continue for occasional malformed lines
                continue
            }
        }

        // Stream ended without [DONE] or finish_reason
        // Flush pending tool calls
        for (_, toolCall) in accumulatedToolCalls.sorted(by: { $0.key < $1.key }) {
            if toolCall.startEmitted {
                continuation.yield(.toolCallFinish(id: toolCall.id, name: toolCall.name, arguments: toolCall.arguments))
            }
        }

        continuation.yield(.finish(reason: lastFinishReason ?? .unknown, usage: totalUsage))
        continuation.finish()
    }

    private func fetchModels() async throws -> [String] {
        let endpoint = baseURL.appendingPathComponent(Self.modelsEndpoint)
        var request = URLRequest(url: endpoint)
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 30

        let (data, response) = try await performRequest(request, timeout: 30)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response type")
        }

        try validateHTTPResponse(httpResponse, data: data)

        struct ModelsResponse: Decodable {
            struct Model: Decodable {
                let id: String
            }
            let data: [Model]
        }

        do {
            let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
            return modelsResponse.data.map { $0.id }
        } catch {
            throw ProviderError.parseError("Failed to parse models response: \(error.localizedDescription)")
        }
    }

    private func checkHealth() async throws -> Bool {
        let endpoint = baseURL.appendingPathComponent(Self.healthEndpoint)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        // Include API key for authenticated deployments
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await performRequest(request, timeout: 10)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response type")
        }

        // Validate response and throw appropriate errors for 4xx/5xx
        try validateHTTPResponse(httpResponse, data: data)

        return true
    }
}

// MARK: - LiteLLM API Types

/// LiteLLM request body structure (OpenAI-compatible format)
private struct LiteLLMRequestBody: Encodable {
    let model: String
    let messages: [LiteLLMMessage]
    let stream: Bool

    var maxTokens: Int?
    var temperature: Double?
    var topP: Double?
    var stop: [String]?
    var tools: [LiteLLMTool]?
    var toolChoice: LiteLLMToolChoice?
    var responseFormat: LiteLLMResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case stop, tools
        case toolChoice = "tool_choice"
        case responseFormat = "response_format"
    }
}

private struct LiteLLMMessage: Encodable {
    let role: String
    let content: LiteLLMContent
    let name: String?
    let toolCalls: [LiteLLMToolCall]?
    let toolCallId: String?

    enum CodingKeys: String, CodingKey {
        case role, content, name
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
    }
}

private enum LiteLLMContent: Encodable {
    case text(String)
    case parts([LiteLLMContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

private enum LiteLLMContentPart: Encodable {
    case text(String)
    case imageURL(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURL(url: url), forKey: .imageURL)
        }
    }

    private struct ImageURL: Encodable {
        let url: String
    }

    private enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }
}

private struct LiteLLMToolCall: Codable {
    let id: String
    let type: String
    let function: LiteLLMFunctionCall
}

private struct LiteLLMFunctionCall: Codable {
    let name: String
    let arguments: String
}

private struct LiteLLMTool: Encodable {
    let type: String
    let function: LiteLLMFunctionDefinition
}

private struct LiteLLMFunctionDefinition: Encodable {
    let name: String
    let description: String?
    let parameters: [String: ProviderJSONValue]?
}

private enum LiteLLMToolChoice: Encodable {
    case string(String)
    case object(LiteLLMToolChoiceObject)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .object(let obj):
            try container.encode(obj)
        }
    }
}

private struct LiteLLMToolChoiceObject: Encodable {
    let type: String
    let function: LiteLLMFunctionName
}

private struct LiteLLMFunctionName: Encodable {
    let name: String
}

private struct LiteLLMResponseFormat: Encodable {
    let type: String
    let jsonSchema: LiteLLMJSONSchema?

    init(type: String, jsonSchema: LiteLLMJSONSchema? = nil) {
        self.type = type
        self.jsonSchema = jsonSchema
    }

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

private struct LiteLLMJSONSchema: Encodable {
    let name: String
    let schema: ProviderJSONValue  // Must be a JSON object, not a string

    /// Create from a JSON schema string (parses into ProviderJSONValue)
    init(name: String, schemaString: String) throws {
        self.name = name
        guard let data = schemaString.data(using: .utf8) else {
            throw ProviderError.invalidRequest("Invalid JSON schema encoding")
        }
        let decoded = try JSONDecoder().decode(ProviderJSONValue.self, from: data)
        // Validate that the schema is a JSON object
        guard case .object = decoded else {
            throw ProviderError.invalidRequest("JSON schema must be an object, not \(type(of: decoded))")
        }
        self.schema = decoded
    }

    /// Create directly from ProviderJSONValue (validates it's an object)
    init(name: String, schema: ProviderJSONValue) throws {
        guard case .object = schema else {
            throw ProviderError.invalidRequest("JSON schema must be an object")
        }
        self.name = name
        self.schema = schema
    }
}

// MARK: - Response Types

private struct LiteLLMCompletionResponse: Decodable {
    let id: String
    let model: String
    let choices: [LiteLLMChoice]
    let usage: LiteLLMUsage?
}

private struct LiteLLMChoice: Decodable {
    let message: LiteLLMResponseMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct LiteLLMResponseMessage: Decodable {
    let role: String
    let content: String?
    let toolCalls: [LiteLLMToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

private struct LiteLLMUsage: Decodable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let cachedTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case cachedTokens = "cached_tokens"
    }
}

// MARK: - Streaming Response Types

private struct LiteLLMStreamChunk: Decodable {
    let id: String
    let model: String
    let choices: [LiteLLMStreamChoice]
    let usage: LiteLLMUsage?
}

private struct LiteLLMStreamChoice: Decodable {
    let delta: LiteLLMStreamDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

private struct LiteLLMStreamDelta: Decodable {
    let role: String?
    let content: String?
    let toolCalls: [LiteLLMStreamToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

private struct LiteLLMStreamToolCall: Decodable {
    let index: Int?
    let id: String?
    let type: String?
    let function: LiteLLMStreamFunctionCall?
}

private struct LiteLLMStreamFunctionCall: Decodable {
    let name: String?
    let arguments: String?
}
