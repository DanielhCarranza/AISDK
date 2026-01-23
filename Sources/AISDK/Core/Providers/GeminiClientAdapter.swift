//
//  GeminiClientAdapter.swift
//  AISDK
//
//  Direct Google Gemini provider client adapter for Phase 2 routing layer
//  Provides direct access to Google Gemini API as a ProviderClient
//

import Foundation

// MARK: - GeminiClientAdapter

/// Direct Google Gemini provider client for the Phase 2 routing layer
///
/// This adapter provides direct access to Google's Gemini API,
/// bypassing routers like OpenRouter or LiteLLM when direct provider access
/// is needed (e.g., for cost optimization, specific model access, or failover).
///
/// ## Features
/// - Direct Gemini API access
/// - Full streaming support with SSE parsing
/// - Tool calling (function calling) support
/// - System instruction support
/// - Health status tracking
///
/// ## Usage
/// ```swift
/// let client = GeminiClientAdapter(apiKey: "YOUR_API_KEY")
/// let request = ProviderRequest(modelId: "gemini-2.0-flash", messages: [...])
/// let response = try await client.execute(request: request)
/// ```
public actor GeminiClientAdapter: ProviderClient {
    // MARK: - Identity

    public nonisolated let providerId: String = "gemini"
    public nonisolated let displayName: String = "Google Gemini"
    public nonisolated let baseURL: URL

    // MARK: - Configuration

    private let apiKey: String
    private let session: URLSession

    // MARK: - State

    private var _healthStatus: ProviderHealthStatus = .unknown
    private var cachedModels: [String]?
    private var lastModelsFetch: Date?
    private let modelsCacheDuration: TimeInterval = 300 // 5 minutes

    // MARK: - Constants

    private static let defaultBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    // Known Gemini models
    private static let knownModels = [
        "gemini-2.5-pro-preview-05-06",
        "gemini-2.5-flash-preview-05-20",
        "gemini-2.5-flash",
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
        "gemini-1.5-pro",
        "gemini-1.5-flash",
        "gemini-1.5-flash-8b"
    ]

    // MARK: - Initialization

    /// Initialize GeminiClientAdapter with API key and optional configuration
    /// - Parameters:
    ///   - apiKey: Google AI API key
    ///   - baseURL: Optional custom base URL (defaults to https://generativelanguage.googleapis.com/v1beta)
    ///   - session: Optional URLSession for dependency injection
    public init(
        apiKey: String,
        baseURL: URL? = nil,
        session: URLSession? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL ?? Self.defaultBaseURL
        self.session = session ?? .shared
    }

    // MARK: - Health & Status

    public var healthStatus: ProviderHealthStatus {
        _healthStatus
    }

    public var isAvailable: Bool {
        _healthStatus.acceptsTraffic
    }

    /// Refresh health status by listing models
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

        let geminiResponse = try parseGenerateContentResponse(data)
        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Update health status on successful request
        _healthStatus = .healthy

        return try buildProviderResponse(from: geminiResponse, latencyMs: latencyMs)
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
        // Check if it's a known model or matches Gemini naming pattern
        return Self.knownModels.contains(modelId) || modelId.hasPrefix("gemini-")
    }

    public func capabilities(for modelId: String) async -> LLMCapabilities? {
        // Return known capabilities for Gemini models
        switch modelId {
        case let id where id.contains("2.5-pro"):
            return [.text, .vision, .tools, .streaming, .functionCalling, .reasoning, .longContext]
        case let id where id.contains("2.5-flash"):
            return [.text, .vision, .tools, .streaming, .functionCalling, .reasoning]
        case let id where id.contains("2.0-flash"):
            return [.text, .vision, .tools, .streaming, .functionCalling]
        case let id where id.contains("1.5-pro"):
            return [.text, .vision, .tools, .streaming, .functionCalling, .longContext]
        case let id where id.contains("1.5-flash"):
            return [.text, .vision, .tools, .streaming, .functionCalling]
        default:
            // Generic Gemini capabilities
            return [.text, .tools, .streaming, .functionCalling]
        }
    }

    // MARK: - Private Methods

    private func buildHTTPRequest(for request: ProviderRequest, streaming: Bool) throws -> URLRequest {
        let action = streaming ? "streamGenerateContent" : "generateContent"
        var endpoint = baseURL.appendingPathComponent("models/\(request.modelId):\(action)")

        // Add API key and SSE param for streaming
        var queryItems = [URLQueryItem(name: "key", value: apiKey)]
        if streaming {
            queryItems.append(URLQueryItem(name: "alt", value: "sse"))
        }

        var urlComponents = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = queryItems
        endpoint = urlComponents.url!

        var httpRequest = URLRequest(url: endpoint)
        httpRequest.httpMethod = "POST"
        httpRequest.timeoutInterval = request.timeout
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        let body = try buildRequestBody(from: request)
        httpRequest.httpBody = try JSONEncoder().encode(body)

        return httpRequest
    }

    private func buildRequestBody(from request: ProviderRequest) throws -> GCARequestBody {
        // Extract system instruction if present
        var systemInstruction: GCAContent?
        var nonSystemMessages: [AIMessage] = []

        for message in request.messages {
            if message.role == .system {
                // Gemini uses systemInstruction field
                let text = message.content.textValue
                if var existing = systemInstruction {
                    // Combine multiple system messages
                    if case .text(let existingText) = existing.parts.first {
                        existing.parts = [.text(existingText + "\n\n" + text)]
                        systemInstruction = existing
                    }
                } else {
                    systemInstruction = GCAContent(parts: [.text(text)])
                }
            } else {
                nonSystemMessages.append(message)
            }
        }

        // Convert messages to Gemini format
        let contents = try nonSystemMessages.map { message -> GCAContent in
            let parts: [GCAPart]

            switch message.content {
            case .text(let text):
                if message.role == .tool {
                    // Tool results use functionResponse part
                    guard let toolCallId = message.toolCallId, !toolCallId.isEmpty else {
                        throw ProviderError.invalidRequest("Tool message requires non-empty toolCallId")
                    }
                    // In Gemini, we use the tool name (stored in toolCallId for our purposes)
                    // The response is wrapped in a response object
                    parts = [.functionResponse(GCAFunctionResponse(
                        name: message.name ?? toolCallId,
                        response: ["result": .string(text)]
                    ))]
                } else {
                    parts = [.text(text)]
                }
            case .parts(let contentParts):
                parts = try contentParts.map { part -> GCAPart in
                    switch part {
                    case .text(let text):
                        return .text(text)
                    case .image(let data, let mimeType):
                        return .inlineData(GCAInlineData(
                            mimeType: mimeType,
                            data: data.base64EncodedString()
                        ))
                    case .imageURL:
                        throw ProviderError.invalidRequest("Gemini requires inline image data - URLs not supported directly")
                    case .audio(let data, let mimeType):
                        return .inlineData(GCAInlineData(
                            mimeType: mimeType,
                            data: data.base64EncodedString()
                        ))
                    case .file:
                        throw ProviderError.invalidRequest("File content not supported in this format")
                    }
                }
            }

            // Handle tool calls in assistant messages
            var finalParts = parts
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                for toolCall in toolCalls {
                    // Parse arguments JSON string to dictionary
                    var argsDict: [String: ProviderJSONValue] = [:]
                    if let argsData = toolCall.arguments.data(using: .utf8),
                       let parsedArgs = try? JSONDecoder().decode([String: ProviderJSONValue].self, from: argsData) {
                        argsDict = parsedArgs
                    }

                    finalParts.append(.functionCall(GCAFunctionCall(
                        name: toolCall.name,
                        args: argsDict
                    )))
                }
            }

            // Map roles: user -> user, assistant -> model, tool -> user (with functionResponse)
            let role: String
            switch message.role {
            case .user:
                role = "user"
            case .assistant:
                role = "model"
            case .tool:
                role = "user" // Function responses are sent as user role
            case .system:
                role = "user" // Should not happen as we filter above
            }

            return GCAContent(role: role, parts: finalParts)
        }

        var body = GCARequestBody(contents: contents)

        // System instruction
        body.systemInstruction = systemInstruction

        // Generation config
        var config = GCAGenerationConfig()
        config.maxOutputTokens = request.maxTokens
        config.temperature = request.temperature
        config.topP = request.topP
        config.stopSequences = request.stop
        body.generationConfig = config

        // Response format
        if let responseFormat = request.responseFormat {
            switch responseFormat {
            case .text:
                break // Default
            case .json:
                body.generationConfig?.responseMimeType = "application/json"
            case .jsonSchema(_, let schema):
                body.generationConfig?.responseMimeType = "application/json"
                // Parse schema string into ProviderJSONValue
                if let schemaData = schema.data(using: .utf8),
                   let parsedSchema = try? JSONDecoder().decode(ProviderJSONValue.self, from: schemaData) {
                    body.generationConfig?.responseSchema = parsedSchema
                }
            }
        }

        // Tools - convert from ProviderJSONValue to Gemini format
        var shouldOmitTools = false
        if let toolChoice = request.toolChoice {
            switch toolChoice {
            case .auto:
                body.toolConfig = GCAToolConfig(functionCallingConfig: GCAFunctionCallingConfig(mode: "AUTO"))
            case .none:
                body.toolConfig = GCAToolConfig(functionCallingConfig: GCAFunctionCallingConfig(mode: "NONE"))
                shouldOmitTools = true
            case .required:
                body.toolConfig = GCAToolConfig(functionCallingConfig: GCAFunctionCallingConfig(mode: "ANY"))
            case .tool(let name):
                body.toolConfig = GCAToolConfig(functionCallingConfig: GCAFunctionCallingConfig(
                    mode: "ANY",
                    allowedFunctionNames: [name]
                ))
            }
        }

        if !shouldOmitTools, let tools = request.tools {
            var functionDeclarations: [GCAFunctionDeclaration] = []
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

                // Convert parameters
                let parameters: [String: ProviderJSONValue]?
                if case .object(let params)? = functionDict["parameters"] {
                    parameters = params
                } else {
                    parameters = nil
                }

                functionDeclarations.append(GCAFunctionDeclaration(
                    name: name,
                    description: description,
                    parameters: parameters
                ))
            }
            if !functionDeclarations.isEmpty {
                body.tools = [GCATool(functionDeclarations: functionDeclarations)]
            }
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
                throw ProviderError.networkError("Cannot connect to Google AI")
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
        case 401, 403:
            let errorMessage = parseErrorMessage(from: data) ?? "Invalid API key"
            throw ProviderError.authenticationFailed(errorMessage)
        case 404:
            let errorMessage = parseErrorMessage(from: data) ?? "Resource not found"
            if errorMessage.lowercased().contains("model") {
                throw ProviderError.modelNotFound(errorMessage)
            }
            throw ProviderError.invalidRequest("Not found: \(errorMessage)")
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
                let code: Int?
                let status: String?
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
        if let status = error.status {
            message += " [status: \(status)]"
        }
        return message
    }

    private func parseGenerateContentResponse(_ data: Data) throws -> GCAGenerateContentResponse {
        do {
            return try JSONDecoder().decode(GCAGenerateContentResponse.self, from: data)
        } catch {
            throw ProviderError.parseError("Failed to parse generateContent response: \(error.localizedDescription)")
        }
    }

    private func buildProviderResponse(from response: GCAGenerateContentResponse, latencyMs: Int) throws -> ProviderResponse {
        guard let candidate = response.candidates?.first else {
            // Check if there's a prompt feedback block reason
            if let feedback = response.promptFeedback,
               let blockReason = feedback.blockReason {
                throw ProviderError.contentFiltered("Prompt blocked: \(blockReason)")
            }
            throw ProviderError.parseError("Response has no candidates")
        }

        var textContent = ""
        var toolCalls: [ProviderToolCall] = []

        for part in candidate.content.parts {
            switch part {
            case .text(let text):
                textContent += text
            case .functionCall(let fc):
                // Convert args dictionary to JSON string
                let encoder = JSONEncoder()
                let argsString: String
                if let argsData = try? encoder.encode(fc.args),
                   let argsStr = String(data: argsData, encoding: .utf8) {
                    argsString = argsStr
                } else {
                    argsString = "{}"
                }

                toolCalls.append(ProviderToolCall(
                    id: "call_\(fc.name)_\(UUID().uuidString.prefix(8))",
                    name: fc.name,
                    arguments: argsString
                ))
            case .functionResponse, .inlineData:
                // These shouldn't appear in model responses
                break
            }
        }

        let usage = response.usageMetadata.map { u in
            ProviderUsage(
                promptTokens: u.promptTokenCount ?? 0,
                completionTokens: u.candidatesTokenCount ?? 0,
                cachedTokens: u.cachedContentTokenCount
            )
        }

        let finishReason = ProviderFinishReason(providerReason: candidate.finishReason)

        return ProviderResponse(
            id: response.responseId ?? UUID().uuidString,
            model: response.modelVersion ?? "gemini",
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

        var responseId: String?
        var modelVersion: String?
        var totalUsage: ProviderUsage?
        var lastFinishReason: ProviderFinishReason?
        var decodeErrorCount = 0
        let maxDecodeErrors = 5

        for try await line in bytes.lines {
            // Skip empty lines
            guard !line.isEmpty else { continue }

            // Parse SSE data line
            guard line.hasPrefix("data:") else { continue }
            let jsonString = line.dropFirst(5).trimmingCharacters(in: .whitespaces)

            // Skip empty data
            if jsonString.isEmpty { continue }

            guard let chunkData = jsonString.data(using: .utf8) else { continue }

            do {
                let chunk = try JSONDecoder().decode(GCAGenerateContentResponse.self, from: chunkData)

                // Emit start event on first chunk
                if responseId == nil {
                    responseId = chunk.responseId ?? UUID().uuidString
                    modelVersion = chunk.modelVersion ?? "gemini"
                    continuation.yield(.start(id: responseId!, model: modelVersion!))
                }

                // Process usage
                if let usage = chunk.usageMetadata {
                    totalUsage = ProviderUsage(
                        promptTokens: usage.promptTokenCount ?? 0,
                        completionTokens: usage.candidatesTokenCount ?? 0,
                        cachedTokens: usage.cachedContentTokenCount
                    )
                    continuation.yield(.usage(totalUsage!))
                }

                // Process candidate content
                if let candidate = chunk.candidates?.first {
                    for part in candidate.content.parts {
                        switch part {
                        case .text(let text):
                            if !text.isEmpty {
                                continuation.yield(.textDelta(text))
                            }
                        case .functionCall(let fc):
                            let callId = "call_\(fc.name)_\(UUID().uuidString.prefix(8))"

                            // Emit start event
                            continuation.yield(.toolCallStart(id: callId, name: fc.name))

                            // Convert args to JSON string
                            let encoder = JSONEncoder()
                            let argsString: String
                            if let argsData = try? encoder.encode(fc.args),
                               let argsStr = String(data: argsData, encoding: .utf8) {
                                argsString = argsStr
                            } else {
                                argsString = "{}"
                            }

                            // Emit delta
                            continuation.yield(.toolCallDelta(id: callId, argumentsDelta: argsString))

                            // Emit finish
                            continuation.yield(.toolCallFinish(id: callId, name: fc.name, arguments: argsString))

                        case .functionResponse, .inlineData:
                            break
                        }
                    }

                    // Check for finish reason
                    if let finishReason = candidate.finishReason {
                        lastFinishReason = ProviderFinishReason(providerReason: finishReason)
                    }
                }

            } catch {
                decodeErrorCount += 1
                if decodeErrorCount >= maxDecodeErrors {
                    throw ProviderError.parseError("Too many SSE decode failures (\(decodeErrorCount)). Last line: \(jsonString.prefix(200))")
                }
                continue
            }
        }

        // Stream ended
        let reason = lastFinishReason ?? .stop
        continuation.yield(.finish(reason: reason, usage: totalUsage))
        continuation.finish()
    }

    private func fetchModels() async throws -> [String] {
        let endpoint = baseURL.appendingPathComponent("models")
        var urlComponents = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await performRequest(request, timeout: 30)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response type")
        }

        try validateHTTPResponse(httpResponse, data: data)

        struct ModelsResponse: Decodable {
            struct Model: Decodable {
                let name: String
                let displayName: String?
                let supportedGenerationMethods: [String]?
            }
            let models: [Model]
        }

        do {
            let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
            // Filter to models that support generateContent and extract short name
            return modelsResponse.models
                .filter { model in
                    model.supportedGenerationMethods?.contains("generateContent") ?? false
                }
                .compactMap { model -> String? in
                    // Extract model ID from "models/gemini-..." format
                    if model.name.hasPrefix("models/") {
                        return String(model.name.dropFirst(7))
                    }
                    return model.name
                }
        } catch {
            throw ProviderError.parseError("Failed to parse models response: \(error.localizedDescription)")
        }
    }
}

// MARK: - Gemini API Types (GCA prefix to avoid collision)

/// Gemini request body structure
private struct GCARequestBody: Encodable {
    let contents: [GCAContent]
    var systemInstruction: GCAContent?
    var generationConfig: GCAGenerationConfig?
    var tools: [GCATool]?
    var toolConfig: GCAToolConfig?

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction
        case generationConfig
        case tools
        case toolConfig
    }
}

private struct GCAContent: Codable {
    var role: String?
    var parts: [GCAPart]

    init(role: String? = nil, parts: [GCAPart]) {
        self.role = role
        self.parts = parts
    }
}

private enum GCAPart: Codable {
    case text(String)
    case inlineData(GCAInlineData)
    case functionCall(GCAFunctionCall)
    case functionResponse(GCAFunctionResponse)

    private enum CodingKeys: String, CodingKey {
        case text
        case inlineData
        case functionCall
        case functionResponse
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let text = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(text)
        } else if let inlineData = try container.decodeIfPresent(GCAInlineData.self, forKey: .inlineData) {
            self = .inlineData(inlineData)
        } else if let functionCall = try container.decodeIfPresent(GCAFunctionCall.self, forKey: .functionCall) {
            self = .functionCall(functionCall)
        } else if let functionResponse = try container.decodeIfPresent(GCAFunctionResponse.self, forKey: .functionResponse) {
            self = .functionResponse(functionResponse)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode GCAPart")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode(text, forKey: .text)
        case .inlineData(let data):
            try container.encode(data, forKey: .inlineData)
        case .functionCall(let fc):
            try container.encode(fc, forKey: .functionCall)
        case .functionResponse(let fr):
            try container.encode(fr, forKey: .functionResponse)
        }
    }
}

private struct GCAInlineData: Codable {
    let mimeType: String
    let data: String
}

private struct GCAFunctionCall: Codable {
    let name: String
    let args: [String: ProviderJSONValue]
}

private struct GCAFunctionResponse: Codable {
    let name: String
    let response: [String: ProviderJSONValue]
}

private struct GCAGenerationConfig: Codable {
    var maxOutputTokens: Int?
    var temperature: Double?
    var topP: Double?
    var topK: Int?
    var stopSequences: [String]?
    var responseMimeType: String?
    var responseSchema: ProviderJSONValue?
}

private struct GCATool: Codable {
    let functionDeclarations: [GCAFunctionDeclaration]
}

private struct GCAFunctionDeclaration: Codable {
    let name: String
    let description: String?
    let parameters: [String: ProviderJSONValue]?
}

private struct GCAToolConfig: Codable {
    let functionCallingConfig: GCAFunctionCallingConfig
}

private struct GCAFunctionCallingConfig: Codable {
    let mode: String
    var allowedFunctionNames: [String]?
}

// MARK: - Response Types

private struct GCAGenerateContentResponse: Decodable {
    let candidates: [GCACandidate]?
    let usageMetadata: GCAUsageMetadata?
    let promptFeedback: GCAPromptFeedback?
    let modelVersion: String?
    let responseId: String?
}

private struct GCACandidate: Decodable {
    let content: GCAContent
    let finishReason: String?
    let safetyRatings: [GCASafetyRating]?
}

private struct GCASafetyRating: Decodable {
    let category: String
    let probability: String
}

private struct GCAUsageMetadata: Decodable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    let cachedContentTokenCount: Int?
}

private struct GCAPromptFeedback: Decodable {
    let blockReason: String?
    let safetyRatings: [GCASafetyRating]?
}
