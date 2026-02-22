//
//  ProviderLanguageModelAdapter.swift
//  AISDK
//
//  Adapter that bridges ProviderClient to the LLM protocol.
//

import Foundation

/// Adapter that wraps a ProviderClient for use with Agent.
public final class ProviderLanguageModelAdapter: LLM, @unchecked Sendable {
    private let client: any ProviderClient
    public let provider: String
    public let modelId: String
    public let capabilities: LLMCapabilities

    public init(
        client: any ProviderClient,
        modelId: String,
        capabilities: LLMCapabilities = [.text, .tools, .functionCalling, .streaming, .jsonMode]
    ) {
        self.client = client
        self.modelId = modelId
        self.provider = client.providerId
        self.capabilities = capabilities
    }

    public func generateText(request: AITextRequest) async throws -> AITextResult {
        let providerRequest = try request.toProviderRequest(modelId: modelId, stream: false)
        let response = try await client.execute(request: providerRequest)
        return response.toAITextResult()
    }

    public func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        do {
            let providerRequest = try request.toProviderRequest(modelId: modelId, stream: true)
            return client.stream(request: providerRequest).map { $0.toAIStreamEvent() }
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    public func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let responseFormat = ResponseFormat.jsonSchema(
            name: request.effectiveSchemaName,
            schemaBuilder: request.schema,
            strict: request.strict
        )
        let textRequest = AITextRequest(
            messages: request.messages,
            model: request.model,
            maxTokens: request.maxTokens,
            temperature: request.temperature,
            topP: request.topP,
            responseFormat: responseFormat,
            allowedProviders: request.allowedProviders,
            sensitivity: request.sensitivity,
            bufferPolicy: request.bufferPolicy,
            metadata: request.metadata
        )

        let providerRequest: ProviderRequest
        do {
            providerRequest = try textRequest.toProviderRequest(modelId: modelId, stream: true)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in client.stream(request: providerRequest) {
                        switch event {
                        case .start(let id, let model):
                            continuation.yield(.start(metadata: AIStreamMetadata(requestId: id, model: model, provider: provider)))
                        case .textDelta(let text):
                            continuation.yield(.objectDelta(Data(text.utf8)))
                        case .usage(let usage):
                            continuation.yield(.usage(usage.toAIUsage()))
                        case .finish(let reason, let usage):
                            continuation.yield(.finish(finishReason: reason.toAIFinishReason(), usage: usage?.toAIUsage() ?? .zero))
                            continuation.finish()
                        default:
                            break
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Factory Methods

extension ProviderLanguageModelAdapter {
    /// Create an adapter using OpenAI's Responses API (recommended for new projects).
    ///
    /// Supports built-in tools (web search, file search, code interpreter, image generation,
    /// computer use), server-side conversation chaining, and improved cache utilization.
    ///
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - modelId: Model identifier (default: "gpt-4o")
    ///   - store: Whether to store responses server-side (default: `false` for privacy)
    /// - Returns: A configured `ProviderLanguageModelAdapter`
    public static func openAIResponses(
        apiKey: String,
        modelId: String = "gpt-4o",
        store: Bool = false
    ) -> ProviderLanguageModelAdapter {
        let client = OpenAIResponsesClientAdapter(apiKey: apiKey, store: store)
        return ProviderLanguageModelAdapter(
            client: client,
            modelId: modelId,
            capabilities: [.text, .vision, .tools, .functionCalling, .streaming, .jsonMode, .webSearch, .reasoning]
        )
    }

    /// Create an adapter using OpenAI's Chat Completions API.
    ///
    /// Use this for ZDR compatibility, OpenRouter/LiteLLM endpoints, or when
    /// the Responses API's features are not needed.
    ///
    /// - Parameters:
    ///   - apiKey: OpenAI API key
    ///   - modelId: Model identifier (default: "gpt-4o")
    /// - Returns: A configured `ProviderLanguageModelAdapter`
    public static func openAIChatCompletions(
        apiKey: String,
        modelId: String = "gpt-4o"
    ) -> ProviderLanguageModelAdapter {
        let client = OpenAIClientAdapter(apiKey: apiKey)
        return ProviderLanguageModelAdapter(
            client: client,
            modelId: modelId,
            capabilities: [.text, .vision, .tools, .functionCalling, .streaming, .jsonMode]
        )
    }
}

private extension AsyncThrowingStream where Element == ProviderStreamEvent, Failure == Error {
    func map(_ transform: @escaping (ProviderStreamEvent) -> AIStreamEvent) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream<AIStreamEvent, Error> { continuation in
            Task {
                do {
                    for try await event in self {
                        continuation.yield(transform(event))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
