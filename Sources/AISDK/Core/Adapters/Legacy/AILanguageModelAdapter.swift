//
//  AILanguageModelAdapter.swift
//  AISDK
//
//  Adapter that wraps the legacy LLM protocol to conform to AILanguageModel
//  Provides backward compatibility for existing consumers
//

import Foundation

// MARK: - AILanguageModelAdapter

/// Adapter that wraps an existing LLM implementation to conform to the new AILanguageModel protocol.
/// This enables gradual migration from the legacy LLM protocol to the new unified interface.
///
/// Usage:
/// ```swift
/// let legacyLLM: LLM = OpenAIProvider(...)
/// let adapter = AILanguageModelAdapter(
///     llm: legacyLLM,
///     provider: "openai",
///     modelId: "gpt-4",
///     capabilities: [.text, .tools, .streaming]
/// )
/// let result = try await adapter.generateText(request: request)
/// ```
public final class AILanguageModelAdapter: AILanguageModel, @unchecked Sendable {
    // MARK: - Properties

    /// The wrapped legacy LLM instance
    private let llm: LLM

    /// The provider identifier
    public let provider: String

    /// The model identifier
    public let modelId: String

    /// The capabilities of this model
    public let capabilities: LLMCapabilities

    /// Default model to use if not specified in request
    private let defaultModel: String

    // MARK: - Initialization

    /// Creates an adapter wrapping a legacy LLM implementation
    /// - Parameters:
    ///   - llm: The legacy LLM to wrap
    ///   - provider: The provider name (e.g., "openai", "anthropic")
    ///   - modelId: The model identifier
    ///   - capabilities: The capabilities supported by this model
    ///   - defaultModel: The default model to use if not specified in requests
    public init(
        llm: LLM,
        provider: String,
        modelId: String,
        capabilities: LLMCapabilities = [.text, .streaming],
        defaultModel: String? = nil
    ) {
        self.llm = llm
        self.provider = provider
        self.modelId = modelId
        self.capabilities = capabilities
        self.defaultModel = defaultModel ?? modelId
    }

    // MARK: - AILanguageModel Implementation

    public func generateText(request: AITextRequest) async throws -> AITextResult {
        // Validate provider access based on sensitivity and allowedProviders
        try validateProviderAccess(request: request)

        // Convert AITextRequest to legacy ChatCompletionRequest
        let chatRequest = try convertToLegacyRequest(request, streaming: false)

        // Execute using legacy LLM
        let response = try await llm.sendChatCompletion(request: chatRequest)

        // Convert response to AITextResult
        return convertToTextResult(response)
    }

    public func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Validate provider access based on sensitivity and allowedProviders
                    try self.validateProviderAccess(request: request)

                    // Convert AITextRequest to legacy ChatCompletionRequest
                    let chatRequest = try convertToLegacyRequest(request, streaming: true)

                    // Emit start event
                    continuation.yield(.start(metadata: AIStreamMetadata(
                        requestId: UUID().uuidString,
                        model: chatRequest.model,
                        provider: self.provider
                    )))

                    // Execute streaming using legacy LLM
                    let stream = try await llm.sendChatCompletionStream(request: chatRequest)

                    var accumulatedText = ""
                    var accumulatedToolCalls: [String: (name: String, arguments: String)] = [:]
                    var lastUsage: AIUsage = .zero
                    var lastFinishReason: AIFinishReason = .unknown

                    for try await chunk in stream {
                        // Process each chunk and emit appropriate events
                        let events = convertChunkToEvents(
                            chunk,
                            accumulatedText: &accumulatedText,
                            accumulatedToolCalls: &accumulatedToolCalls,
                            lastUsage: &lastUsage,
                            lastFinishReason: &lastFinishReason
                        )

                        for event in events {
                            continuation.yield(event)
                        }
                    }

                    // Emit finish event
                    continuation.yield(.finish(finishReason: lastFinishReason, usage: lastUsage))
                    continuation.finish()

                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func generateObject<T: Codable & Sendable>(
        request: AIObjectRequest<T>
    ) async throws -> AIObjectResult<T> {
        // Validate PHI/provider access before any provider I/O
        try validateProviderAccess(request: request)

        // Convert to legacy request with JSON response format
        let messages = request.messages.map { convertToLegacyMessage($0) }

        let effectiveModel = request.model ?? defaultModel
        let chatRequest = ChatCompletionRequest(
            model: effectiveModel,
            messages: messages,
            metadata: request.metadata,
            maxTokens: request.maxTokens,
            responseFormat: .jsonSchema(
                name: String(describing: T.self),
                schemaBuilder: request.schema
            ),
            temperature: request.temperature,
            topP: request.topP
        )

        // Use the legacy generateObject method
        let object: T = try await llm.generateObject(request: chatRequest)

        // Encode the object to get rawJSON for debugging
        let encoder = JSONEncoder()
        let rawJSON = try? String(data: encoder.encode(object), encoding: .utf8)

        return AIObjectResult(
            object: object,
            usage: .zero,  // Legacy API doesn't provide usage in generateObject
            finishReason: .stop,
            model: effectiveModel,
            provider: provider,
            rawJSON: rawJSON
        )
    }

    public func streamObject<T: Codable & Sendable>(
        request: AIObjectRequest<T>
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // For legacy LLM, we don't have true object streaming
                    // Fall back to generating the full object and emitting it as a single event
                    let result = try await self.generateObject(request: request)

                    let encoder = JSONEncoder()
                    let data = try encoder.encode(result.object)

                    continuation.yield(.start(metadata: AIStreamMetadata(
                        model: request.model ?? self.defaultModel,
                        provider: self.provider
                    )))
                    continuation.yield(.objectDelta(data))
                    continuation.yield(.usage(result.usage))
                    continuation.yield(.finish(finishReason: result.finishReason, usage: result.usage))
                    continuation.finish()

                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// Validates that this provider can handle the request based on sensitivity and provider restrictions
    private func validateProviderAccess(request: AITextRequest) throws {
        try validateProviderAccessInternal(
            canUseProvider: request.canUseProvider(provider),
            allowedProviders: request.allowedProviders,
            sensitivity: request.sensitivity
        )
    }

    /// Validates that this provider can handle the object request based on sensitivity and provider restrictions
    private func validateProviderAccess<T>(request: AIObjectRequest<T>) throws {
        try validateProviderAccessInternal(
            canUseProvider: request.canUseProvider(provider),
            allowedProviders: request.allowedProviders,
            sensitivity: request.sensitivity
        )
    }

    /// Internal helper for provider access validation
    private func validateProviderAccessInternal(
        canUseProvider: Bool,
        allowedProviders: Set<String>?,
        sensitivity: DataSensitivity
    ) throws {
        // Check if this provider is in the allowlist (if specified)
        if !canUseProvider {
            throw AIProviderAccessError.providerNotAllowed(
                provider: provider,
                allowedProviders: allowedProviders ?? []
            )
        }

        // Validate sensitivity requirements
        switch sensitivity {
        case .standard:
            // Standard data can use any provider
            break
        case .sensitive, .phi:
            // Sensitive and PHI data require explicit provider allowlisting
            if allowedProviders == nil {
                throw AIProviderAccessError.sensitiveDataRequiresAllowlist(
                    sensitivity: sensitivity
                )
            }
        }
    }

    private func convertToLegacyRequest(_ request: AITextRequest, streaming: Bool) throws -> ChatCompletionRequest {
        let messages = request.messages.map { convertToLegacyMessage($0) }

        return ChatCompletionRequest(
            model: request.model ?? defaultModel,
            messages: messages,
            metadata: request.metadata,
            maxTokens: request.maxTokens,
            responseFormat: request.responseFormat,
            stop: request.stop,
            stream: streaming,
            temperature: request.temperature,
            topP: request.topP,
            tools: request.tools,
            toolChoice: request.toolChoice
        )
    }

    private func convertToLegacyMessage(_ message: AIMessage) -> Message {
        // Convert AIMessage to the legacy Message enum used by ChatCompletionRequest
        switch message.role {
        case .user:
            return .user(content: message.content.asUserContent, name: message.name)

        case .assistant:
            let legacyToolCalls: [ChatCompletionResponse.ToolCall]?
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                legacyToolCalls = toolCalls.map { call in
                    ChatCompletionResponse.ToolCall(
                        id: call.id,
                        type: "function",
                        function: ChatCompletionResponse.ToolFunctionCall(
                            name: call.name,
                            arguments: call.arguments
                        )
                    )
                }
            } else {
                legacyToolCalls = nil
            }
            return .assistant(
                content: message.content.asAssistantContent,
                name: message.name,
                toolCalls: legacyToolCalls
            )

        case .system:
            return .system(content: message.content.asSystemContent, name: message.name)

        case .tool:
            return .tool(
                content: message.content.textValue,
                name: message.name ?? "",
                toolCallId: message.toolCallId ?? ""
            )
        }
    }

    private func convertToTextResult(_ response: ChatCompletionResponse) -> AITextResult {
        guard let choice = response.choices.first else {
            return AITextResult(
                text: "",
                toolCalls: [],
                usage: AIUsage(legacy: response.usage),
                finishReason: .unknown,
                requestId: response.id,
                model: response.model,
                provider: provider
            )
        }

        let text = choice.message.content ?? ""
        let toolCalls = (choice.message.toolCalls ?? []).map { call in
            AIToolCallResult(
                id: call.id,
                name: call.function?.name ?? "",
                arguments: call.function?.arguments ?? ""
            )
        }

        return AITextResult(
            text: text,
            toolCalls: toolCalls,
            usage: AIUsage(legacy: response.usage),
            finishReason: AIFinishReason(legacyReason: choice.finishReason),
            requestId: response.id,
            model: response.model,
            provider: provider
        )
    }

    private func convertChunkToEvents(
        _ chunk: ChatCompletionChunk,
        accumulatedText: inout String,
        accumulatedToolCalls: inout [String: (name: String, arguments: String)],
        lastUsage: inout AIUsage,
        lastFinishReason: inout AIFinishReason
    ) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []

        guard let choice = chunk.choices.first else {
            return events
        }

        // Handle text delta
        let delta = choice.delta
        if let content = delta.content, !content.isEmpty {
            accumulatedText += content
            events.append(.textDelta(content))
        }

        // Handle tool calls
        if let toolCalls = delta.toolCalls {
            for toolCall in toolCalls {
                let callId = toolCall.id ?? ""

                if let name = toolCall.function?.name, !name.isEmpty {
                    // New tool call starting
                    accumulatedToolCalls[callId] = (name: name, arguments: "")
                    events.append(.toolCallStart(id: callId, name: name))
                }

                if let args = toolCall.function?.arguments, !args.isEmpty {
                    // Tool call arguments delta
                    if var existing = accumulatedToolCalls[callId] {
                        existing.arguments += args
                        accumulatedToolCalls[callId] = existing
                    }
                    events.append(.toolCallDelta(id: callId, argumentsDelta: args))
                }
            }
        }

        // Handle finish reason
        if let finishReason = choice.finishReason {
            lastFinishReason = AIFinishReason(legacyReason: finishReason)

            // Emit completed tool calls
            for (callId, toolCall) in accumulatedToolCalls {
                events.append(.toolCall(id: callId, name: toolCall.name, arguments: toolCall.arguments))
            }
        }

        // Handle usage
        if let usage = chunk.usage {
            lastUsage = AIUsage(
                promptTokens: usage.promptTokens ?? 0,
                completionTokens: usage.completionTokens ?? 0,
                totalTokens: usage.totalTokens ?? 0
            )
            events.append(.usage(lastUsage))
        }

        return events
    }
}

// MARK: - AIMessage Content Extension

private extension AIMessage.Content {
    /// Convert to legacy UserContent format
    var asUserContent: UserContent {
        switch self {
        case .text(let text):
            return .text(text)
        case .parts(let parts):
            let legacyParts = parts.compactMap { part -> UserContent.Part? in
                switch part {
                case .text(let text):
                    return .text(text)
                case .image(let data, _):
                    return .imageURL(.base64(data), detail: .auto)
                case .imageURL(let urlString):
                    if let url = URL(string: urlString) {
                        return .imageURL(.url(url), detail: .auto)
                    }
                    return nil
                case .file, .audio:
                    // Not supported in legacy format
                    return nil
                }
            }
            return .parts(legacyParts)
        }
    }

    /// Convert to legacy AssistantContent format
    var asAssistantContent: AssistantContent {
        switch self {
        case .text(let text):
            return .text(text)
        case .parts(let parts):
            let textParts = parts.compactMap { part -> String? in
                if case .text(let text) = part {
                    return text
                }
                return nil
            }
            return textParts.count == 1 ? .text(textParts[0]) : .parts(textParts)
        }
    }

    /// Convert to legacy SystemContent format
    var asSystemContent: SystemContent {
        switch self {
        case .text(let text):
            return .text(text)
        case .parts(let parts):
            let textParts = parts.compactMap { part -> String? in
                if case .text(let text) = part {
                    return text
                }
                return nil
            }
            return textParts.count == 1 ? .text(textParts[0]) : .parts(textParts)
        }
    }
}

// MARK: - Factory Methods

public extension AILanguageModelAdapter {
    /// Create an adapter from an OpenAI provider
    static func fromOpenAI(
        _ provider: OpenAIProvider,
        model: String = "gpt-4"
    ) -> AILanguageModelAdapter {
        AILanguageModelAdapter(
            llm: provider,
            provider: "openai",
            modelId: model,
            capabilities: [.text, .vision, .tools, .streaming, .functionCalling],
            defaultModel: model
        )
    }

    /// Create an adapter from an Anthropic provider
    static func fromAnthropic(
        _ provider: AnthropicProvider,
        model: String = "claude-3-opus"
    ) -> AILanguageModelAdapter {
        AILanguageModelAdapter(
            llm: provider,
            provider: "anthropic",
            modelId: model,
            capabilities: [.text, .vision, .tools, .streaming],
            defaultModel: model
        )
    }

    /// Create an adapter from any LLM provider
    /// - Parameters:
    ///   - llm: The LLM provider to wrap
    ///   - provider: The provider name (e.g., "openai", "anthropic", "google")
    ///   - model: The model identifier
    ///   - capabilities: The capabilities of the model
    /// - Returns: An AILanguageModelAdapter wrapping the provider
    static func from(
        _ llm: LLM,
        provider: String,
        model: String,
        capabilities: LLMCapabilities = [.text, .streaming]
    ) -> AILanguageModelAdapter {
        AILanguageModelAdapter(
            llm: llm,
            provider: provider,
            modelId: model,
            capabilities: capabilities,
            defaultModel: model
        )
    }
}
