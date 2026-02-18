//
//  OpenRouterClient.swift
//  AISDK
//
//  OpenRouter provider client implementation for Phase 2 routing layer
//  Primary production router with access to 200+ models
//

import Foundation

// MARK: - OpenRouterClient

/// OpenRouter provider client for routing to multiple AI providers
///
/// OpenRouter is a unified API that provides access to 200+ models from various providers
/// including OpenAI, Anthropic, Google, Meta, and many others through a single endpoint.
///
/// ## Features
/// - Single API key for all providers
/// - Automatic fallback and load balancing
/// - Cost-effective routing options
/// - Consistent API format (OpenAI-compatible)
///
/// ## Usage
/// ```swift
/// let client = OpenRouterClient(apiKey: "sk-or-...")
/// let request = ProviderRequest(modelId: "anthropic/claude-3-opus", messages: [...])
/// let response = try await client.execute(request: request)
/// ```
public actor OpenRouterClient: ProviderClient {
    // MARK: - Identity

    public nonisolated let providerId: String = "openrouter"
    public nonisolated let displayName: String = "OpenRouter"
    public nonisolated let baseURL: URL

    // MARK: - Configuration

    private let apiKey: String
    private let session: URLSession
    private let appName: String?
    private let siteURL: String?

    // MARK: - State

    private var _healthStatus: ProviderHealthStatus = .unknown
    private var cachedModels: [String]?
    private var lastModelsFetch: Date?
    private let modelsCacheDuration: TimeInterval = 300 // 5 minutes

    // MARK: - Constants

    private static let defaultBaseURL = URL(string: "https://openrouter.ai/api/v1")!
    private static let modelsEndpoint = "models"
    private static let chatCompletionsEndpoint = "chat/completions"

    // MARK: - Initialization

    /// Initialize OpenRouterClient with API key and optional configuration
    /// - Parameters:
    ///   - apiKey: OpenRouter API key (starts with "sk-or-")
    ///   - baseURL: Optional custom base URL (defaults to https://openrouter.ai/api/v1)
    ///   - session: Optional URLSession for dependency injection
    ///   - appName: Optional app name for OpenRouter's X-Title header (helps with analytics)
    ///   - siteURL: Optional site URL for OpenRouter's HTTP-Referer header (helps with analytics)
    public init(
        apiKey: String,
        baseURL: URL? = nil,
        session: URLSession? = nil,
        appName: String? = nil,
        siteURL: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.session = session ?? .shared
        self.appName = appName
        self.siteURL = siteURL
    }

    // MARK: - Health & Status

    public var healthStatus: ProviderHealthStatus {
        _healthStatus
    }

    public var isAvailable: Bool {
        _healthStatus.acceptsTraffic
    }

    /// Refresh health status by pinging the models endpoint
    public func refreshHealthStatus() async {
        do {
            _ = try await fetchModels()
            _healthStatus = .healthy
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
        // OpenRouter provides model metadata, but for now return nil
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

        // Required headers
        httpRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Optional OpenRouter-specific headers for analytics
        if let appName = appName {
            httpRequest.setValue(appName, forHTTPHeaderField: "X-Title")
        }
        if let siteURL = siteURL {
            httpRequest.setValue(siteURL, forHTTPHeaderField: "HTTP-Referer")
        }

        // Build request body
        let body = try buildRequestBody(from: request, streaming: streaming)
        httpRequest.httpBody = try JSONEncoder().encode(body)

        return httpRequest
    }

    private func buildRequestBody(from request: ProviderRequest, streaming: Bool) throws -> OpenRouterRequestBody {
        let messages = request.messages.map { message -> OpenRouterMessage in
            let content: OpenRouterContent
            switch message.content {
            case .text(let text):
                content = .text(text)
            case .parts(let parts):
                let openRouterParts = parts.map { part -> OpenRouterContentPart in
                    switch part {
                    case .text(let text):
                        return .text(text)
                    case .image(let data, let mimeType):
                        let base64 = data.base64EncodedString()
                        return .imageURL("data:\(mimeType);base64,\(base64)")
                    case .imageURL(let url):
                        return .imageURL(url)
                    case .audio, .file, .video, .videoURL:
                        // Video/audio not supported via OpenAI-compatible chat completions format
                        // Use Gemini provider for video support
                        return .text("[Unsupported content type]")
                    }
                }
                content = .parts(openRouterParts)
            }

            return OpenRouterMessage(
                role: message.role.rawValue,
                content: content,
                name: message.name,
                toolCalls: message.toolCalls?.map { tc in
                    OpenRouterToolCall(
                        id: tc.id,
                        type: "function",
                        function: OpenRouterFunctionCall(name: tc.name, arguments: tc.arguments)
                    )
                },
                toolCallId: message.toolCallId
            )
        }

        var body = OpenRouterRequestBody(
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
                body.toolChoice = .object(OpenRouterToolChoiceObject(type: "function", function: OpenRouterFunctionName(name: name)))
            }
        }

        // Response format
        if let responseFormat = request.responseFormat {
            switch responseFormat {
            case .text:
                body.responseFormat = OpenRouterResponseFormat(type: "text")
            case .json:
                body.responseFormat = OpenRouterResponseFormat(type: "json_object")
            case .jsonSchema(let name, let schema):
                // Parse schema string into JSON object
                let jsonSchema = try OpenRouterJSONSchema(name: name, schemaString: schema)
                body.responseFormat = OpenRouterResponseFormat(
                    type: "json_schema",
                    jsonSchema: jsonSchema
                )
            }
        }

        // Tools from providerOptions - validate all tools convert successfully
        if let tools = request.tools {
            var convertedTools: [OpenRouterTool] = []
            for (index, toolValue) in tools.enumerated() {
                // Convert ProviderJSONValue to OpenRouterTool
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

                convertedTools.append(OpenRouterTool(
                    type: "function",
                    function: OpenRouterFunctionDefinition(
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
                throw ProviderError.networkError("Cannot connect to OpenRouter")
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
            // OpenRouter can return 404 "Resource not found" for unavailable model variants.
            // Normalize this as modelNotFound so callers can handle availability drift deterministically.
            let normalized = errorMessage.lowercased()
            if normalized.contains("model")
                || (normalized.contains("resource") && normalized.contains("not found"))
                || (normalized.contains("not found") && normalized.contains("provider")) {
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

    /// Parse SSE error frame (OpenAI/OpenRouter style)
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

    private func parseCompletionResponse(_ data: Data) throws -> OpenRouterCompletionResponse {
        do {
            return try JSONDecoder().decode(OpenRouterCompletionResponse.self, from: data)
        } catch {
            throw ProviderError.parseError("Failed to parse completion response: \(error.localizedDescription)")
        }
    }

    private func buildProviderResponse(from response: OpenRouterCompletionResponse, latencyMs: Int) throws -> ProviderResponse {
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
        var accumulatedToolCalls: [Int: (id: String, name: String, arguments: String, startEmitted: Bool, pendingDeltas: [String])] = [:]
        // Track last seen delta per index to detect duplicates
        var lastArgsDelta: [Int: String] = [:]
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
                let chunk = try JSONDecoder().decode(OpenRouterStreamChunk.self, from: chunkData)

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

                        // Get the current argument delta
                        var argsDelta = toolCall.function?.arguments ?? ""

                        // Skip duplicate deltas (some providers may send the same delta multiple times)
                        if !argsDelta.isEmpty && argsDelta == lastArgsDelta[index] {
                            continue
                        }
                        if !argsDelta.isEmpty {
                            lastArgsDelta[index] = argsDelta
                        }

                        // Handle overlapping deltas: some providers send chunks that overlap
                        // with previous content. Detect and remove the overlap.
                        if !argsDelta.isEmpty && !existingArgs.isEmpty {
                            // Check if argsDelta starts with content that's at the end of existingArgs
                            let overlapCheckLength = min(argsDelta.count, existingArgs.count, 20)
                            for overlap in stride(from: overlapCheckLength, through: 1, by: -1) {
                                let existingEnd = String(existingArgs.suffix(overlap))
                                let deltaStart = String(argsDelta.prefix(overlap))
                                if existingEnd == deltaStart {
                                    // Found overlap, remove it from argsDelta
                                    argsDelta = String(argsDelta.dropFirst(overlap))
                                    break
                                }
                            }
                        }

                        // Debug: log what we're receiving
                        #if DEBUG
                        if !argsDelta.isEmpty {
                            FileHandle.standardError.write("[TOOL_DEBUG] idx=\(index) argsDelta='\(argsDelta.prefix(50))' existing='\(existingArgs.suffix(30))'\n".data(using: .utf8)!)
                        }
                        #endif

                        // Handle tool call state based on whether start has been emitted
                        if startEmitted {
                            // Start already emitted - just emit new deltas and accumulate
                            if !argsDelta.isEmpty {
                                continuation.yield(.toolCallDelta(id: stableId, argumentsDelta: argsDelta))
                            }
                            let allArgs = existingArgs + argsDelta
                            accumulatedToolCalls[index] = (id: stableId, name: name, arguments: allArgs, startEmitted: true, pendingDeltas: [])
                        } else if !name.isEmpty {
                            // Can emit start - we have a name
                            continuation.yield(.toolCallStart(id: stableId, name: name))
                            // Emit the argument delta if we have one
                            let allArgs = existingArgs + argsDelta
                            if !allArgs.isEmpty {
                                continuation.yield(.toolCallDelta(id: stableId, argumentsDelta: allArgs))
                            }
                            accumulatedToolCalls[index] = (id: stableId, name: name, arguments: allArgs, startEmitted: true, pendingDeltas: [])
                        } else {
                            // Buffer until we have a name to emit start
                            let allArgs = existingArgs + argsDelta
                            accumulatedToolCalls[index] = (id: stableId, name: name, arguments: allArgs, startEmitted: false, pendingDeltas: [])
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
}

// MARK: - OpenRouter API Types

/// OpenRouter request body structure
private struct OpenRouterRequestBody: Encodable {
    let model: String
    let messages: [OpenRouterMessage]
    let stream: Bool

    var maxTokens: Int?
    var temperature: Double?
    var topP: Double?
    var stop: [String]?
    var tools: [OpenRouterTool]?
    var toolChoice: OpenRouterToolChoice?
    var responseFormat: OpenRouterResponseFormat?

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

private struct OpenRouterMessage: Encodable {
    let role: String
    let content: OpenRouterContent
    let name: String?
    let toolCalls: [OpenRouterToolCall]?
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

private enum OpenRouterContent: Encodable {
    case text(String)
    case parts([OpenRouterContentPart])

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

private enum OpenRouterContentPart: Encodable {
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

private struct OpenRouterToolCall: Codable {
    let id: String
    let type: String
    let function: OpenRouterFunctionCall
}

private struct OpenRouterFunctionCall: Codable {
    let name: String
    let arguments: String
}

private struct OpenRouterTool: Encodable {
    let type: String
    let function: OpenRouterFunctionDefinition
}

private struct OpenRouterFunctionDefinition: Encodable {
    let name: String
    let description: String?
    let parameters: [String: ProviderJSONValue]?
}

private enum OpenRouterToolChoice: Encodable {
    case string(String)
    case object(OpenRouterToolChoiceObject)

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

private struct OpenRouterToolChoiceObject: Encodable {
    let type: String
    let function: OpenRouterFunctionName
}

private struct OpenRouterFunctionName: Encodable {
    let name: String
}

private struct OpenRouterResponseFormat: Encodable {
    let type: String
    let jsonSchema: OpenRouterJSONSchema?

    init(type: String, jsonSchema: OpenRouterJSONSchema? = nil) {
        self.type = type
        self.jsonSchema = jsonSchema
    }

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

private struct OpenRouterJSONSchema: Encodable {
    let name: String
    let schema: ProviderJSONValue  // Must be a JSON object, not a string

    /// Create from a JSON schema string (parses into ProviderJSONValue)
    init(name: String, schemaString: String) throws {
        self.name = name
        guard let data = schemaString.data(using: .utf8) else {
            throw ProviderError.invalidRequest("Invalid JSON schema encoding")
        }
        self.schema = try JSONDecoder().decode(ProviderJSONValue.self, from: data)
    }

    /// Create directly from ProviderJSONValue
    init(name: String, schema: ProviderJSONValue) {
        self.name = name
        self.schema = schema
    }
}

// MARK: - Response Types

private struct OpenRouterCompletionResponse: Decodable {
    let id: String
    let model: String
    let choices: [OpenRouterChoice]
    let usage: OpenRouterUsage?
}

private struct OpenRouterChoice: Decodable {
    let message: OpenRouterResponseMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct OpenRouterResponseMessage: Decodable {
    let role: String
    let content: String?
    let toolCalls: [OpenRouterToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

private struct OpenRouterUsage: Decodable {
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

private struct OpenRouterStreamChunk: Decodable {
    let id: String
    let model: String
    let choices: [OpenRouterStreamChoice]
    let usage: OpenRouterUsage?
}

private struct OpenRouterStreamChoice: Decodable {
    let delta: OpenRouterStreamDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

private struct OpenRouterStreamDelta: Decodable {
    let role: String?
    let content: String?
    let toolCalls: [OpenRouterStreamToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

private struct OpenRouterStreamToolCall: Decodable {
    let index: Int?
    let id: String?
    let type: String?
    let function: OpenRouterStreamFunctionCall?
}

private struct OpenRouterStreamFunctionCall: Decodable {
    let name: String?
    let arguments: String?
}
