//
//  ReliableLanguageModelAdapter.swift
//  AISDKCLI
//
//  AILanguageModel adapter that executes via FailoverExecutor and emits pseudo-stream events
//

import Foundation
import AISDK

final class ReliableLanguageModelAdapter: AILanguageModel, @unchecked Sendable {
    private let executor: FailoverExecutor
    let modelId: String
    private let providerLabel: String
    let capabilities: LLMCapabilities

    var provider: String { providerLabel }

    init(
        executor: FailoverExecutor,
        modelId: String,
        providerLabel: String,
        capabilities: LLMCapabilities = [.text, .tools, .functionCalling, .streaming, .jsonMode]
    ) {
        self.executor = executor
        self.modelId = modelId
        self.providerLabel = providerLabel
        self.capabilities = capabilities
    }

    func generateText(request: AITextRequest) async throws -> AITextResult {
        let result = try await executor.executeRequest(request: request, modelId: modelId)
        return result.result.toAITextResult()
    }

    func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let execution = try await executor.executeRequest(request: request, modelId: modelId)
                    let result = execution.result.toAITextResult()

                    continuation.yield(.start(metadata: AIStreamMetadata(
                        requestId: nil,
                        model: modelId,
                        provider: execution.provider
                    )))

                    if !result.text.isEmpty {
                        continuation.yield(.textDelta(result.text))
                    }

                    for call in result.toolCalls {
                        continuation.yield(.toolCallFinish(id: call.id, name: call.name, arguments: call.arguments))
                    }

                    continuation.yield(.usage(result.usage))
                    continuation.yield(.finish(finishReason: result.finishReason, usage: result.usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
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

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await generateText(request: textRequest)
                    continuation.yield(.start(metadata: AIStreamMetadata(
                        requestId: nil,
                        model: modelId,
                        provider: provider
                    )))
                    if !result.text.isEmpty {
                        continuation.yield(.objectDelta(Data(result.text.utf8)))
                    }
                    continuation.yield(.usage(result.usage))
                    continuation.yield(.finish(finishReason: result.finishReason, usage: result.usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
