//
//  OpenAIClientAdapter.swift
//  AISDK
//
//  Direct OpenAI provider client adapter for Phase 2 routing layer
//  Provides direct access to OpenAI API as a ProviderClient
//

import Foundation

// MARK: - OpenAIClientAdapter

/// Direct OpenAI provider client for the Phase 2 routing layer
///
/// This adapter provides direct access to OpenAI's Chat Completions API,
/// bypassing routers like OpenRouter or LiteLLM when direct provider access
/// is needed (e.g., for cost optimization, specific model access, or failover).
///
/// ## Features
/// - Direct OpenAI API access
/// - Full streaming support with SSE parsing
/// - Tool calling support
/// - Response format (JSON mode, JSON schema) support
/// - Health status tracking
///
/// ## Usage
/// ```swift
/// let client = OpenAIClientAdapter(apiKey: "sk-...")
/// let request = ProviderRequest(modelId: "gpt-4o", messages: [...])
/// let response = try await client.execute(request: request)
/// ```
public actor OpenAIClientAdapter: ProviderClient {
    // MARK: - Identity

    public nonisolated let providerId: String = "openai"
    public nonisolated let displayName: String = "OpenAI"
    public nonisolated let baseURL: URL

    // MARK: - Configuration

    private let apiKey: String
    private let session: URLSession
    private let organization: String?
    private let retryPolicy: RetryPolicy

    // MARK: - State

    private var _healthStatus: ProviderHealthStatus = .unknown
    private var cachedModels: [String]?
    private var lastModelsFetch: Date?
    private let modelsCacheDuration: TimeInterval = 300 // 5 minutes

    // MARK: - Constants

    private static let defaultBaseURL = URL(string: "https://api.openai.com/v1")!
    private static let modelsEndpoint = "models"
    private static let chatCompletionsEndpoint = "chat/completions"

    // MARK: - Initialization

    /// Initialize OpenAIClientAdapter with API key and optional configuration
    /// - Parameters:
    ///   - apiKey: OpenAI API key (starts with "sk-")
    ///   - baseURL: Optional custom base URL (defaults to https://api.openai.com/v1)
    ///   - session: Optional URLSession for dependency injection
    ///   - organization: Optional organization ID for multi-org accounts
    ///   - retryPolicy: Retry policy for transient failures (default: 3 retries with exponential backoff)
    public init(
        apiKey: String,
        baseURL: URL? = nil,
        session: URLSession? = nil,
        organization: String? = nil,
        retryPolicy: RetryPolicy = .default
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.session = session ?? .shared
        self.organization = organization
        self.retryPolicy = retryPolicy
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

        let (data, response) = try await RetryExecutor(policy: retryPolicy).execute {
            try await self.performRequest(httpRequest, timeout: request.timeout)
        }

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
        // Return known capabilities for common OpenAI models
        switch modelId {
        case let id where id.hasPrefix("gpt-4o"):
            return [.text, .vision, .tools, .streaming, .functionCalling, .jsonMode]
        case let id where id.hasPrefix("gpt-4-turbo"):
            return [.text, .vision, .tools, .streaming, .functionCalling, .jsonMode]
        case let id where id.hasPrefix("gpt-4"):
            return [.text, .tools, .streaming, .functionCalling]
        case let id where id.hasPrefix("gpt-3.5"):
            return [.text, .tools, .streaming, .functionCalling]
        case let id where id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4"):
            return [.text, .tools, .streaming, .reasoning]
        default:
            return nil
        }
    }

    // MARK: - Private Methods

    private static func supportsReasoning(for modelId: String) -> Bool {
        modelId.hasPrefix("o1") || modelId.hasPrefix("o3") || modelId.hasPrefix("o4")
    }

    private func buildHTTPRequest(for request: ProviderRequest, streaming: Bool) throws -> URLRequest {
        let endpoint = baseURL.appendingPathComponent(Self.chatCompletionsEndpoint)
        var httpRequest = URLRequest(url: endpoint)
        httpRequest.httpMethod = "POST"
        httpRequest.timeoutInterval = request.timeout

        // Required headers
        httpRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Accept header for streaming (improves compatibility with some proxies)
        if streaming {
            httpRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        // Optional organization header
        if let organization = organization {
            httpRequest.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
        }

        // Build request body
        let body = try buildRequestBody(from: request, streaming: streaming)
        httpRequest.httpBody = try JSONEncoder().encode(body)

        return httpRequest
    }

    private func buildRequestBody(from request: ProviderRequest, streaming: Bool) throws -> OpenAIRequestBody {
        let messages = try request.messages.map { message -> OpenAIMessage in
            let content: OpenAIContent
            switch message.content {
            case .text(let text):
                content = .text(text)
            case .parts(let parts):
                let openAIParts = try parts.map { part -> OpenAIContentPart in
                    switch part {
                    case .text(let text):
                        return .text(text)
                    case .image(let data, let mimeType):
                        let base64 = data.base64EncodedString()
                        return .imageURL("data:\(mimeType);base64,\(base64)")
                    case .imageURL(let url):
                        return .imageURL(url)
                    case .video, .videoURL:
                        throw ProviderError.unsupportedModality(
                            modality: "video",
                            provider: "OpenAI",
                            supportedProviders: ["Gemini"]
                        )
                    case .audio:
                        throw ProviderError.unsupportedModality(
                            modality: "audio",
                            provider: "OpenAI",
                            supportedProviders: ["Gemini"]
                        )
                    case .file:
                        throw ProviderError.unsupportedModality(
                            modality: "file",
                            provider: "OpenAI",
                            supportedProviders: ["Anthropic (PDF only)", "Gemini"]
                        )
                    }
                }
                content = .parts(openAIParts)
            }

            return OpenAIMessage(
                role: message.role.rawValue,
                content: content,
                name: message.name,
                toolCalls: message.toolCalls?.map { tc in
                    OpenAIToolCall(
                        id: tc.id,
                        type: "function",
                        function: OpenAIFunctionCall(name: tc.name, arguments: tc.arguments)
                    )
                },
                toolCallId: message.toolCallId
            )
        }

        var body = OpenAIRequestBody(
            model: request.modelId,
            messages: messages,
            stream: streaming
        )

        if let builtInTools = request.builtInTools, !builtInTools.isEmpty {
            throw ProviderError.invalidRequest(
                "Built-in tools are not supported via OpenAI Chat Completions API. " +
                    "Use the OpenAI Responses API (OpenAIProvider) instead."
            )
        }

        // Optional parameters — o-series models require max_completion_tokens instead of max_tokens
        if Self.supportsReasoning(for: request.modelId) {
            body.maxCompletionTokens = request.maxTokens
        } else {
            body.maxTokens = request.maxTokens
        }
        if Self.supportsReasoning(for: request.modelId) {
            if request.temperature == 1 {
                body.temperature = 1
            } else {
                body.temperature = nil
            }
        } else {
            body.temperature = request.temperature
        }
        body.topP = request.topP
        body.stop = request.stop

        if Self.supportsReasoning(for: request.modelId),
           let effort = request.reasoning?.effort {
            body.reasoningEffort = effort.rawValue
        }

        // Stream options to include usage in streaming responses
        if streaming {
            body.streamOptions = OpenAIStreamOptions(includeUsage: true)
        }

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
                body.toolChoice = .object(OpenAIToolChoiceObject(type: "function", function: OpenAIFunctionName(name: name)))
            }
        }

        // Response format
        if let responseFormat = request.responseFormat {
            switch responseFormat {
            case .text:
                body.responseFormat = OpenAIResponseFormat(type: "text")
            case .json:
                body.responseFormat = OpenAIResponseFormat(type: "json_object")
            case .jsonSchema(let name, let schema):
                // Parse schema string into JSON object
                let jsonSchema = try OpenAIJSONSchema(name: name, schemaString: schema)
                body.responseFormat = OpenAIResponseFormat(
                    type: "json_schema",
                    jsonSchema: jsonSchema
                )
            }
        }

        // Tools - validate all tools convert successfully
        if let tools = request.tools {
            var convertedTools: [OpenAITool] = []
            for (index, toolValue) in tools.enumerated() {
                // Convert ProviderJSONValue to OpenAITool
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

                convertedTools.append(OpenAITool(
                    type: "function",
                    function: OpenAIFunctionDefinition(
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
                throw ProviderError.networkError("Cannot connect to OpenAI")
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

    /// Parse SSE error frame (OpenAI style)
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

    private func parseCompletionResponse(_ data: Data) throws -> OpenAICompletionResponse {
        do {
            return try JSONDecoder().decode(OpenAICompletionResponse.self, from: data)
        } catch {
            throw ProviderError.parseError("Failed to parse completion response: \(error.localizedDescription)")
        }
    }

    private func buildProviderResponse(from response: OpenAICompletionResponse, latencyMs: Int) throws -> ProviderResponse {
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
                reasoningTokens: u.reasoningTokens
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

        let streamRetry = RetryPolicy(maxRetries: 1, baseDelay: .milliseconds(500))
        let (bytes, response) = try await RetryExecutor(policy: streamRetry).execute {
            try await self.session.bytes(for: httpRequest)
        }

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
        // Use simpler pattern like LiteLLMClient - accumulate args as string, not separate deltas
        var accumulatedToolCalls: [Int: (id: String?, name: String, arguments: String, startEmitted: Bool)] = [:]
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
                    guard let id = toolCall.id else { continue }
                    if !toolCall.startEmitted, !toolCall.name.isEmpty {
                        continuation.yield(.toolCallStart(id: id, name: toolCall.name))
                        if !toolCall.arguments.isEmpty {
                            continuation.yield(.toolCallDelta(id: id, argumentsDelta: toolCall.arguments))
                        }
                    }
                    continuation.yield(.toolCallFinish(id: id, name: toolCall.name, arguments: toolCall.arguments))
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
                let chunk = try JSONDecoder().decode(OpenAIStreamChunk.self, from: chunkData)

                // Emit start event on first chunk
                if responseId == nil {
                    responseId = chunk.id
                    continuation.yield(.start(id: chunk.id, model: chunk.model))
                }

                // Process usage first (can come in chunks without choices/delta)
                if let usage = chunk.usage {
                    totalUsage = ProviderUsage(
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens,
                        cachedTokens: usage.cachedTokens,
                        reasoningTokens: usage.reasoningTokens
                    )
                    continuation.yield(.usage(totalUsage!))
                }

                // Handle delta content (may be nil for usage-only chunks)
                if let delta = chunk.choices.first?.delta {
                    // Text content
                    if let content = delta.content, !content.isEmpty {
                        continuation.yield(.textDelta(content))
                    }

                    // Tool calls - key by index to handle multiple concurrent tool calls
                    // Follow LiteLLMClient pattern for correct event sequencing
                    if let toolCalls = delta.toolCalls {
                        for toolCall in toolCalls {
                            let index = toolCall.index ?? 0
                            // Use real ID if provided, else use existing or generate stable one
                            let existing = accumulatedToolCalls[index]
                            let id = toolCall.id ?? existing?.id
                            let name = toolCall.function?.name ?? existing?.name ?? ""
                            let argsDelta = toolCall.function?.arguments ?? ""
                            let existingArgs = existing?.arguments ?? ""
                            let startEmitted = existing?.startEmitted ?? false
                            let combinedArgs = existingArgs + argsDelta

                            // Only emit start once we have a stable id and name
                            if !startEmitted, let id = id, !name.isEmpty {
                                continuation.yield(.toolCallStart(id: id, name: name))
                                if !existingArgs.isEmpty {
                                    continuation.yield(.toolCallDelta(id: id, argumentsDelta: existingArgs))
                                }
                                if !argsDelta.isEmpty {
                                    continuation.yield(.toolCallDelta(id: id, argumentsDelta: argsDelta))
                                }
                                accumulatedToolCalls[index] = (id: id, name: name, arguments: combinedArgs, startEmitted: true)
                            } else if startEmitted, let id = id {
                                if !argsDelta.isEmpty {
                                    continuation.yield(.toolCallDelta(id: id, argumentsDelta: argsDelta))
                                }
                                accumulatedToolCalls[index] = (id: id, name: name, arguments: combinedArgs, startEmitted: true)
                            } else {
                                // Buffer until we have both id + name to emit start
                                accumulatedToolCalls[index] = (id: id, name: name, arguments: combinedArgs, startEmitted: false)
                            }
                        }
                    }
                }

                // Check for finish reason (can be on a chunk with or without delta)
                if let finishReason = chunk.choices.first?.finishReason {
                    let reason = ProviderFinishReason(providerReason: finishReason)
                    lastFinishReason = reason

                    // Emit tool call finish events
                    for (_, toolCall) in accumulatedToolCalls.sorted(by: { $0.key < $1.key }) {
                        guard let id = toolCall.id else { continue }
                        if !toolCall.startEmitted, !toolCall.name.isEmpty {
                            continuation.yield(.toolCallStart(id: id, name: toolCall.name))
                            if !toolCall.arguments.isEmpty {
                                continuation.yield(.toolCallDelta(id: id, argumentsDelta: toolCall.arguments))
                            }
                        }
                        continuation.yield(.toolCallFinish(id: id, name: toolCall.name, arguments: toolCall.arguments))
                    }
                    accumulatedToolCalls.removeAll()

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
            guard let id = toolCall.id else { continue }
            if !toolCall.startEmitted, !toolCall.name.isEmpty {
                continuation.yield(.toolCallStart(id: id, name: toolCall.name))
                if !toolCall.arguments.isEmpty {
                    continuation.yield(.toolCallDelta(id: id, argumentsDelta: toolCall.arguments))
                }
            }
            continuation.yield(.toolCallFinish(id: id, name: toolCall.name, arguments: toolCall.arguments))
        }

        continuation.yield(.finish(reason: lastFinishReason ?? .unknown, usage: totalUsage))
        continuation.finish()
    }

    private func fetchModels() async throws -> [String] {
        let endpoint = baseURL.appendingPathComponent(Self.modelsEndpoint)
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let organization = organization {
            request.setValue(organization, forHTTPHeaderField: "OpenAI-Organization")
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
            // Filter to only include chat models (GPT series)
            return modelsResponse.data
                .map { $0.id }
                .filter { id in
                    id.hasPrefix("gpt-") ||
                    id.hasPrefix("o1") ||
                    id.hasPrefix("o3") ||
                    id.hasPrefix("o4") ||
                    id.hasPrefix("chatgpt")
                }
        } catch {
            throw ProviderError.parseError("Failed to parse models response: \(error.localizedDescription)")
        }
    }
}

// MARK: - OpenAI API Types

/// OpenAI request body structure
private struct OpenAIRequestBody: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let stream: Bool

    var maxTokens: Int?
    var maxCompletionTokens: Int?
    var temperature: Double?
    var topP: Double?
    var stop: [String]?
    var tools: [OpenAITool]?
    var toolChoice: OpenAIToolChoice?
    var responseFormat: OpenAIResponseFormat?
    var streamOptions: OpenAIStreamOptions?
    var reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case temperature
        case topP = "top_p"
        case stop, tools
        case toolChoice = "tool_choice"
        case responseFormat = "response_format"
        case streamOptions = "stream_options"
        case reasoningEffort = "reasoning_effort"
    }
}

private struct OpenAIStreamOptions: Encodable {
    let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

private struct OpenAIMessage: Encodable {
    let role: String
    let content: OpenAIContent
    let name: String?
    let toolCalls: [OpenAIToolCall]?
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

private enum OpenAIContent: Encodable {
    case text(String)
    case parts([OpenAIContentPart])

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

private enum OpenAIContentPart: Encodable {
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

private struct OpenAIToolCall: Codable {
    let id: String
    let type: String
    let function: OpenAIFunctionCall
}

private struct OpenAIFunctionCall: Codable {
    let name: String
    let arguments: String
}

private struct OpenAITool: Encodable {
    let type: String
    let function: OpenAIFunctionDefinition
}

private struct OpenAIFunctionDefinition: Encodable {
    let name: String
    let description: String?
    let parameters: [String: ProviderJSONValue]?
}

private enum OpenAIToolChoice: Encodable {
    case string(String)
    case object(OpenAIToolChoiceObject)

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

private struct OpenAIToolChoiceObject: Encodable {
    let type: String
    let function: OpenAIFunctionName
}

private struct OpenAIFunctionName: Encodable {
    let name: String
}

private struct OpenAIResponseFormat: Encodable {
    let type: String
    let jsonSchema: OpenAIJSONSchema?

    init(type: String, jsonSchema: OpenAIJSONSchema? = nil) {
        self.type = type
        self.jsonSchema = jsonSchema
    }

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

private struct OpenAIJSONSchema: Encodable {
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

private struct OpenAICompletionResponse: Decodable {
    let id: String
    let model: String
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

private struct OpenAIChoice: Decodable {
    let message: OpenAIResponseMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case finishReason = "finish_reason"
    }
}

private struct OpenAIResponseMessage: Decodable {
    let role: String
    let content: String?
    let toolCalls: [OpenAIToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

private struct OpenAIUsage: Decodable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let cachedTokens: Int?
    let reasoningTokens: Int?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case completionTokensDetails = "completion_tokens_details"
        case cachedTokens = "cached_tokens"
        case reasoningTokens = "reasoning_tokens"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try container.decode(Int.self, forKey: .promptTokens)
        completionTokens = try container.decode(Int.self, forKey: .completionTokens)
        totalTokens = try container.decode(Int.self, forKey: .totalTokens)

        struct PromptTokensDetails: Decodable {
            let cachedTokens: Int?
            enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
            }
        }

        struct CompletionTokensDetails: Decodable {
            let reasoningTokens: Int?
            enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        // Prefer nested details objects (standard OpenAI format), fall back to top-level keys
        if let promptDetails = try? container.decode(PromptTokensDetails.self, forKey: .promptTokensDetails) {
            cachedTokens = promptDetails.cachedTokens
        } else {
            cachedTokens = try container.decodeIfPresent(Int.self, forKey: .cachedTokens)
        }

        if let completionDetails = try? container.decode(CompletionTokensDetails.self, forKey: .completionTokensDetails) {
            reasoningTokens = completionDetails.reasoningTokens
        } else {
            reasoningTokens = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens)
        }
    }
}

// MARK: - Streaming Response Types

private struct OpenAIStreamChunk: Decodable {
    let id: String
    let model: String
    let choices: [OpenAIStreamChoice]
    let usage: OpenAIUsage?
}

private struct OpenAIStreamChoice: Decodable {
    let delta: OpenAIStreamDelta?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case delta
        case finishReason = "finish_reason"
    }
}

private struct OpenAIStreamDelta: Decodable {
    let role: String?
    let content: String?
    let toolCalls: [OpenAIStreamToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
    }
}

private struct OpenAIStreamToolCall: Decodable {
    let index: Int?
    let id: String?
    let type: String?
    let function: OpenAIStreamFunctionCall?
}

private struct OpenAIStreamFunctionCall: Decodable {
    let name: String?
    let arguments: String?
}
