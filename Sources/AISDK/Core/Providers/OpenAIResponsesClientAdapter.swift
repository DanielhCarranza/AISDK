//
//  OpenAIResponsesClientAdapter.swift
//  AISDK
//
//  OpenAI Responses API provider client adapter for Phase 2 routing layer.
//  Routes requests through POST /v1/responses instead of /v1/chat/completions.
//

import Foundation

// MARK: - OpenAIResponsesClientAdapter

/// OpenAI provider client that routes through the Responses API (`/v1/responses`).
///
/// This adapter wraps `OpenAIProvider` and provides access to the Responses API's
/// full feature set: built-in tools (web search, file search, code interpreter,
/// image generation, computer use), server-side conversation chaining, and
/// improved cache utilization (~80% vs ~40% for Chat Completions).
///
/// ## When to use this vs `OpenAIClientAdapter`
/// - **Use this** for new projects, built-in tools, agentic workflows, structured output
/// - **Use `OpenAIClientAdapter`** for Chat Completions compatibility (OpenRouter, LiteLLM, ZDR)
///
/// ## Privacy
/// Defaults to `store: false` (privacy-first). Forces `store: false` for PHI sensitivity.
///
/// ## Usage
/// ```swift
/// let client = OpenAIResponsesClientAdapter(apiKey: "sk-...")
/// let model = ProviderLanguageModelAdapter(client: client, modelId: "gpt-4o")
/// let agent = Agent(model: model, builtInTools: [.webSearchDefault])
/// ```
public actor OpenAIResponsesClientAdapter: ProviderClient {
    // MARK: - Identity

    public nonisolated let providerId: String = "openai-responses"
    public nonisolated let displayName: String = "OpenAI (Responses API)"
    public nonisolated let baseURL: URL

    // MARK: - Configuration

    private let provider: OpenAIProvider
    private let defaultStore: Bool
    private let retryPolicy: RetryPolicy

    // MARK: - State

    private var _healthStatus: ProviderHealthStatus = .unknown

    // MARK: - Initialization

    /// Initialize with API key and optional configuration.
    ///
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - baseURL: Optional custom base URL (defaults to `https://api.openai.com`)
    ///   - store: Whether to store responses server-side (default: `false` for privacy)
    ///   - organization: Optional organization ID
    ///   - retryPolicy: Retry policy for transient failures
    public init(
        apiKey: String,
        baseURL: URL? = nil,
        store: Bool = false,
        organization: String? = nil,
        retryPolicy: RetryPolicy = .default
    ) {
        let base = baseURL?.absoluteString ?? "https://api.openai.com"
        self.baseURL = URL(string: base)!
        self.provider = OpenAIProvider(apiKey: apiKey, baseUrl: base)
        self.defaultStore = store
        self.retryPolicy = retryPolicy
    }

    // MARK: - Health & Status

    public var healthStatus: ProviderHealthStatus {
        _healthStatus
    }

    public var isAvailable: Bool {
        _healthStatus.acceptsTraffic
    }

    public func refreshHealthStatus() async {
        do {
            let testRequest = AITextRequest(
                messages: [AIMessage(role: .user, content: .text("ping"))],
                model: "gpt-4o-mini",
                maxTokens: 1
            )
            _ = try await provider.sendTextRequest(testRequest)
            _healthStatus = .healthy
        } catch {
            _healthStatus = .unhealthy(reason: error.localizedDescription)
        }
    }

    // MARK: - Request Execution

    public func execute(request: ProviderRequest) async throws -> ProviderResponse {
        let startTime = Date()
        let aiRequest = convertToAITextRequest(from: request)

        let result = try await RetryExecutor(policy: retryPolicy).execute {
            try await self.provider.sendTextRequest(aiRequest)
        }

        let latencyMs = Int(Date().timeIntervalSince(startTime) * 1000)
        _healthStatus = .healthy

        return buildProviderResponse(from: result, latencyMs: latencyMs)
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
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Model Information

    public var availableModels: [String] {
        get async throws {
            [
                "gpt-4o", "gpt-4o-mini", "gpt-4o-audio-preview",
                "gpt-4-turbo", "gpt-4",
                "o1", "o1-mini", "o1-pro",
                "o3", "o3-mini", "o3-pro",
                "o4-mini",
                "chatgpt-4o-latest"
            ]
        }
    }

    public func capabilities(for modelId: String) async -> LLMCapabilities? {
        switch modelId {
        case let id where id.hasPrefix("gpt-4o"):
            return [.text, .vision, .tools, .streaming, .functionCalling, .jsonMode, .webSearch]
        case let id where id.hasPrefix("gpt-4"):
            return [.text, .tools, .streaming, .functionCalling, .jsonMode]
        case let id where id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4"):
            return [.text, .tools, .streaming, .reasoning, .webSearch]
        default:
            return [.text, .tools, .streaming, .functionCalling]
        }
    }

    // MARK: - Private: Request Conversion

    /// Convert `ProviderRequest` → `AITextRequest` for the Responses API bridge.
    private nonisolated func convertToAITextRequest(from request: ProviderRequest) -> AITextRequest {
        // Determine store value: providerOptions override > default
        let store: Bool
        if let storeOption = request.providerOptions?["store"], case .bool(let v) = storeOption {
            store = v
        } else {
            store = defaultStore
        }

        var openAIOptions = OpenAIRequestOptions()
        openAIOptions.store = store

        // Force store: false for PHI sensitivity (passed as providerOption by the adapter layer)
        if let sensitivityValue = request.providerOptions?["sensitivity"],
           case .string(let s) = sensitivityValue,
           s == "phi" {
            openAIOptions.store = false
        }

        // Extract conversation ID from provider options for server-side chaining
        var conversationId: String?
        if let convId = request.providerOptions?["conversationId"],
           case .string(let id) = convId {
            conversationId = id
        }
        if let prevId = request.providerOptions?["previousResponseId"],
           case .string(let id) = prevId {
            conversationId = id
        }

        // Convert ProviderJSONValue tools back to ToolSchema via round-trip encoding
        let toolSchemas: [ToolSchema]? = request.tools?.compactMap { toolValue -> ToolSchema? in
            guard let data = try? JSONEncoder().encode(toolValue),
                  let schema = try? JSONDecoder().decode(ToolSchema.self, from: data) else {
                return nil
            }
            return schema
        }

        // Convert ProviderToolChoice back to ToolChoice
        let toolChoice: ToolChoice? = request.toolChoice.map { choice -> ToolChoice in
            switch choice {
            case .auto: return .auto
            case .none: return .none
            case .required: return .required
            case .tool(let name): return .function(ToolChoice.FunctionChoice(name: name))
            }
        }

        // Convert ProviderResponseFormat back to ResponseFormat for structured output
        let responseFormat: ResponseFormat?
        if let format = request.responseFormat {
            switch format {
            case .text:
                responseFormat = .text
            case .json:
                responseFormat = .jsonObject
            case .jsonSchema(let name, let schema):
                responseFormat = .jsonSchema(
                    name: name,
                    schemaBuilder: RawJSONSchemaBuilder(schemaString: schema),
                    strict: true
                )
            }
        } else {
            responseFormat = nil
        }

        return AITextRequest(
            messages: request.messages,
            model: request.modelId,
            maxTokens: request.maxTokens.map { max($0, 16) },
            temperature: request.temperature,
            topP: request.topP,
            stop: request.stop,
            tools: toolSchemas,
            toolChoice: toolChoice,
            builtInTools: request.builtInTools,
            responseFormat: responseFormat,
            reasoning: request.reasoning,
            caching: request.caching,
            metadata: request.metadata,
            conversationId: conversationId,
            providerOptions: openAIOptions
        )
    }

    // MARK: - Private: Response Conversion

    /// Convert `AITextResult` → `ProviderResponse`.
    private nonisolated func buildProviderResponse(from result: AITextResult, latencyMs: Int) -> ProviderResponse {
        let toolCalls = result.toolCalls.map { tc in
            ProviderToolCall(id: tc.id, name: tc.name, arguments: tc.arguments)
        }

        let usage = ProviderUsage(
            promptTokens: result.usage.promptTokens,
            completionTokens: result.usage.completionTokens,
            cachedTokens: result.usage.cachedTokens,
            reasoningTokens: result.usage.reasoningTokens
        )

        let finishReason: ProviderFinishReason
        switch result.finishReason {
        case .stop: finishReason = .stop
        case .length: finishReason = .length
        case .toolCalls: finishReason = .toolCalls
        case .contentFilter: finishReason = .contentFilter
        default: finishReason = .unknown
        }

        // Preserve responseId in metadata for conversation chaining
        var metadata: [String: String] = [:]
        if let responseId = result.responseId {
            metadata["responseId"] = responseId
        }

        return ProviderResponse(
            id: result.requestId ?? UUID().uuidString,
            model: result.model ?? "",
            provider: providerId,
            content: result.text,
            toolCalls: toolCalls,
            usage: usage,
            finishReason: finishReason,
            latencyMs: latencyMs,
            metadata: metadata.isEmpty ? nil : metadata
        )
    }

    // MARK: - Private: Streaming

    private func performStreaming(
        request: ProviderRequest,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async throws {
        let aiRequest = convertToAITextRequest(from: request)
        let stream = provider.streamTextRequest(aiRequest)

        var startEmitted = false
        // Track active function call for incremental argument streaming
        var activeFunctionCallId: String?

        for try await chunk in stream {
            // Emit start on first chunk
            if !startEmitted {
                continuation.yield(.start(id: chunk.id, model: chunk.model))
                startEmitted = true
            }

            // Text content delta
            if let text = chunk.delta?.outputText, !text.isEmpty {
                continuation.yield(.textDelta(text))
            }

            // Function call argument deltas (incremental streaming)
            if let argDelta = chunk.delta?.functionCallArgumentsDelta, !argDelta.isEmpty {
                if let callId = activeFunctionCallId {
                    continuation.yield(.toolCallDelta(id: callId, argumentsDelta: argDelta))
                }
            }

            // Reasoning summary deltas
            if let reasoning = chunk.delta?.reasoning, let summary = reasoning.summary, !summary.isEmpty {
                continuation.yield(.reasoningDelta(summary))
            }

            // Process output items for tool calls, citations, and function call tracking
            if let outputs = chunk.delta?.output {
                for item in outputs {
                    switch item {
                    case .functionCall(let call):
                        let id = call.callId
                        if call.arguments.isEmpty && call.status != "completed" {
                            // Function call just started (from output_item.added) — track it
                            activeFunctionCallId = id
                            continuation.yield(.toolCallStart(id: id, name: call.name))
                        } else if activeFunctionCallId == id {
                            // Function call completed (from output_item.done) after incremental deltas
                            continuation.yield(.toolCallFinish(id: id, name: call.name, arguments: call.arguments))
                            activeFunctionCallId = nil
                        } else {
                            // Complete function call arrived at once
                            continuation.yield(.toolCallStart(id: id, name: call.name))
                            if !call.arguments.isEmpty {
                                continuation.yield(.toolCallDelta(id: id, argumentsDelta: call.arguments))
                            }
                            continuation.yield(.toolCallFinish(id: id, name: call.name, arguments: call.arguments))
                        }

                    case .message(let msg):
                        // Extract URL citation annotations and emit as .source events
                        for content in msg.content {
                            if case .outputText(let textContent) = content,
                               let annotations = textContent.annotations {
                                for annotation in annotations {
                                    if case .urlCitation(let citation) = annotation {
                                        continuation.yield(.source(AISource(
                                            id: citation.url,
                                            url: citation.url,
                                            title: citation.title
                                        )))
                                    }
                                }
                            }
                        }

                    default:
                        break
                    }
                }
            }

            // Usage information
            if let usage = chunk.usage {
                let providerUsage = ProviderUsage(
                    promptTokens: usage.inputTokens,
                    completionTokens: usage.outputTokens,
                    cachedTokens: usage.inputTokensDetails?.cachedTokens,
                    reasoningTokens: usage.outputTokensDetails?.reasoningTokens
                )
                continuation.yield(.usage(providerUsage))
            }

            // Final status — emit finish and close stream
            if let status = chunk.status, status.isFinal {
                let reason: ProviderFinishReason
                switch status {
                case .completed: reason = .stop
                case .incomplete: reason = .length
                default: reason = .unknown
                }

                let finalUsage: ProviderUsage?
                if let usage = chunk.usage {
                    finalUsage = ProviderUsage(
                        promptTokens: usage.inputTokens,
                        completionTokens: usage.outputTokens,
                        cachedTokens: usage.inputTokensDetails?.cachedTokens,
                        reasoningTokens: usage.outputTokensDetails?.reasoningTokens
                    )
                } else {
                    finalUsage = nil
                }

                continuation.yield(.finish(reason: reason, usage: finalUsage))
                continuation.finish()
                return
            }
        }

        // Stream ended without a final status
        continuation.yield(.finish(reason: .unknown, usage: nil))
        continuation.finish()
    }
}

// MARK: - RawJSONSchemaBuilder

/// A schema builder that wraps a raw JSON schema string for round-tripping
/// through the `ProviderResponseFormat.jsonSchema` → `ResponseFormat.jsonSchema` conversion.
struct RawJSONSchemaBuilder: SchemaBuilding {
    let schemaString: String

    func build() -> JSONSchema {
        guard let data = schemaString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return JSONSchema(rawValue: [:])
        }
        // Convert [String: Any] to [String: AnyEncodable]
        return JSONSchema(rawValue: convertToAnyEncodable(dict))
    }

    private func convertToAnyEncodable(_ dict: [String: Any]) -> [String: AnyEncodable] {
        dict.mapValues { value -> AnyEncodable in
            switch value {
            case let str as String:
                return AnyEncodable(str)
            case let num as NSNumber:
                // Check if it's a boolean
                if CFBooleanGetTypeID() == CFGetTypeID(num) {
                    return AnyEncodable(num.boolValue)
                }
                if num.doubleValue == Double(num.intValue) {
                    return AnyEncodable(num.intValue)
                }
                return AnyEncodable(num.doubleValue)
            case let arr as [Any]:
                return AnyEncodable(arr.map { convertAnyToEncodable($0) })
            case let nested as [String: Any]:
                return AnyEncodable(convertToAnyEncodable(nested))
            case is NSNull:
                return AnyEncodable("")  // NSNull maps to empty string for schema encoding
            default:
                return AnyEncodable(String(describing: value))
            }
        }
    }

    private func convertAnyToEncodable(_ value: Any) -> AnyEncodable {
        switch value {
        case let str as String:
            return AnyEncodable(str)
        case let num as NSNumber:
            if CFBooleanGetTypeID() == CFGetTypeID(num) {
                return AnyEncodable(num.boolValue)
            }
            if num.doubleValue == Double(num.intValue) {
                return AnyEncodable(num.intValue)
            }
            return AnyEncodable(num.doubleValue)
        case let arr as [Any]:
            return AnyEncodable(arr.map { convertAnyToEncodable($0) })
        case let dict as [String: Any]:
            return AnyEncodable(convertToAnyEncodable(dict))
        default:
            return AnyEncodable(String(describing: value))
        }
    }
}
