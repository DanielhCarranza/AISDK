//
//  OpenAIProvider+AITextRequest.swift
//  AISDK
//
//  Extension to bridge AITextRequest to OpenAI Responses API
//  Enables provider-agnostic requests with OpenAI-specific features via providerOptions
//

import Foundation

// MARK: - AITextRequest Support

extension OpenAIProvider {

    // MARK: - Send Text Request

    /// Send a text request using the Responses API
    ///
    /// Converts `AITextRequest` to Responses API format, supporting:
    /// - System prompts mapped to `instructions`
    /// - Conversation chaining via `conversationId` -> `previousResponseId`
    /// - Built-in tools via `OpenAIRequestOptions` in `providerOptions`
    /// - Privacy-first defaults (`store: nil`)
    ///
    /// Example:
    /// ```swift
    /// var request = AITextRequest(
    ///     messages: [AIMessage(role: .user, content: .text("Hello"))],
    ///     model: "gpt-4o"
    /// )
    /// request.providerOptions = OpenAIRequestOptions.withWebSearch()
    ///
    /// let result = try await provider.sendTextRequest(request)
    /// // Use result.responseId for conversation chaining
    /// ```
    public func sendTextRequest(_ request: AITextRequest) async throws -> AITextResult {
        let responseRequest = try convertToResponseRequest(request)
        let response = try await createResponse(request: responseRequest)
        return convertToAITextResult(response)
    }

    // MARK: - Stream Text Request

    /// Stream a text request using the Responses API
    ///
    /// Returns an `AsyncThrowingStream` of `ResponseChunk` events.
    /// Supports all features of `sendTextRequest` plus real-time streaming.
    ///
    /// Example:
    /// ```swift
    /// let request = AITextRequest(
    ///     messages: [AIMessage(role: .user, content: .text("Tell me a story"))],
    ///     model: "gpt-4o"
    /// )
    ///
    /// for try await chunk in provider.streamTextRequest(request) {
    ///     if let text = chunk.delta?.outputText {
    ///         print(text, terminator: "")
    ///     }
    /// }
    /// ```
    public func streamTextRequest(_ request: AITextRequest) -> AsyncThrowingStream<ResponseChunk, Error> {
        do {
            let responseRequest = try convertToResponseRequest(request, streaming: true)
            return createResponseStream(request: responseRequest)
        } catch {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Request Conversion

    /// Convert AITextRequest to ResponseRequest
    internal func convertToResponseRequest(_ request: AITextRequest, streaming: Bool = false) throws -> ResponseRequest {
        // Extract system prompt from messages -> instructions
        var instructions: String?
        var nonSystemMessages: [AIMessage] = []

        for message in request.messages {
            if message.role == .system {
                // Collect system messages into instructions
                if case .text(let text) = message.content {
                    if instructions == nil {
                        instructions = text
                    } else {
                        instructions! += "\n\n" + text
                    }
                }
            } else {
                nonSystemMessages.append(message)
            }
        }

        // Convert messages to ResponseInput
        let input = convertMessagesToInput(nonSystemMessages)

        // Convert custom tools
        var tools: [ResponseTool] = request.tools?.compactMap { convertToolSchema($0) } ?? []

        // Extract OpenAI-specific options
        let openAIOptions = request.providerOptions as? OpenAIRequestOptions

        // Add built-in tools from provider options
        if let webConfig = openAIOptions?.webSearch, webConfig.enabled {
            tools.append(.webSearchPreview)
        }

        if let fileConfig = openAIOptions?.fileSearch, fileConfig.enabled {
            // Add file search for each vector store
            for vectorStoreId in fileConfig.vectorStoreIds {
                tools.append(.fileSearch(vectorStoreId: vectorStoreId))
            }
        }

        if let codeConfig = openAIOptions?.codeInterpreter, codeConfig.enabled {
            tools.append(.codeInterpreter)
        }

        // Convert reasoning config
        let reasoning: ResponseReasoning?
        if let reasoningConfig = openAIOptions?.reasoning {
            reasoning = ResponseReasoning(
                effort: reasoningConfig.effort?.rawValue,
                summary: reasoningConfig.summary?.rawValue
            )
        } else {
            reasoning = nil
        }

        // Build the request
        return ResponseRequest(
            model: request.model ?? model.name,
            input: input,
            instructions: instructions,
            tools: tools.isEmpty ? nil : tools,
            toolChoice: convertToolChoice(request.toolChoice),
            metadata: request.metadata,
            temperature: request.temperature,
            topP: request.topP,
            maxOutputTokens: request.maxTokens,
            stream: streaming,
            background: openAIOptions?.background,
            previousResponseId: request.conversationId,  // Explicit, no shared state
            include: nil,
            store: openAIOptions?.store,  // Privacy-first: nil by default
            reasoning: reasoning,
            parallelToolCalls: true,
            serviceTier: openAIOptions?.serviceTier?.rawValue,
            user: nil,
            truncation: nil,
            text: nil
        )
    }

    /// Convert messages to ResponseInput
    private func convertMessagesToInput(_ messages: [AIMessage]) -> ResponseInput {
        if messages.isEmpty {
            return .string("")
        }

        // Single user message with text content -> simple string input
        if messages.count == 1,
           let first = messages.first,
           first.role == .user,
           case .text(let text) = first.content {
            return .string(text)
        }

        // Multiple messages or complex content -> items array
        let items = messages.compactMap { convertMessageToInputItem($0) }
        return .items(items)
    }

    /// Convert a single message to ResponseInputItem
    private func convertMessageToInputItem(_ message: AIMessage) -> ResponseInputItem? {
        // Handle tool results
        if message.role == .tool, let toolCallId = message.toolCallId {
            let output: String
            switch message.content {
            case .text(let text):
                output = text
            case .parts(let parts):
                output = parts.compactMap { part in
                    if case .text(let text) = part { return text }
                    return nil
                }.joined(separator: "\n")
            }
            return .functionCallOutput(ResponseFunctionCallOutput(callId: toolCallId, output: output))
        }

        // Map role
        let role: String
        switch message.role {
        case .user:
            role = "user"
        case .assistant:
            role = "assistant"
        case .system:
            return nil  // System messages handled as instructions
        case .tool:
            return nil  // Tool messages handled above
        }

        // Convert content
        let contentItems: [ResponseContentItem]
        switch message.content {
        case .text(let text):
            contentItems = [.inputText(ResponseInputText(text: text))]
        case .parts(let parts):
            contentItems = parts.compactMap { convertMessageContentPart($0) }
        }

        return .message(ResponseMessage(role: role, content: contentItems))
    }

    /// Convert AIMessage.ContentPart to ResponseContentItem
    private func convertMessageContentPart(_ part: AIMessage.ContentPart) -> ResponseContentItem? {
        switch part {
        case .text(let text):
            return .inputText(ResponseInputText(text: text))
        case .image(let data, let mimeType):
            // Convert data-based images to base64 data URL
            let base64 = data.base64EncodedString()
            let mediaType = mimeType.replacingOccurrences(of: "image/", with: "")
            return .inputImage(ResponseInputImage(imageUrl: "data:image/\(mediaType);base64,\(base64)"))
        case .imageURL(let url):
            return .inputImage(ResponseInputImage(imageUrl: url))
        case .audio, .file, .video, .videoURL:
            // Audio/video/file content types are not directly supported by Responses API input
            // Use Gemini provider for video support
            return nil
        }
    }

    /// Convert ToolSchema to ResponseTool
    private func convertToolSchema(_ schema: ToolSchema) -> ResponseTool? {
        guard let function = schema.function else { return nil }
        return .function(function)
    }

    /// Convert ToolChoice
    private func convertToolChoice(_ choice: ToolChoice?) -> ToolChoice? {
        // ToolChoice is already compatible, just pass through
        return choice
    }

    // MARK: - Response Conversion

    /// Convert ResponseObject to AITextResult
    internal func convertToAITextResult(_ response: ResponseObject) -> AITextResult {
        // Extract text from message outputs
        var text = ""
        var toolCalls: [ToolCallResult] = []

        for item in response.output {
            switch item {
            case .message(let message):
                for content in message.content {
                    switch content {
                    case .outputText(let outputText):
                        text += outputText.text
                    case .outputImage:
                        // Image outputs could be handled if needed
                        break
                    }
                }
            case .functionCall(let call):
                toolCalls.append(ToolCallResult(
                    id: call.callId,
                    name: call.name,
                    arguments: call.arguments
                ))
            case .functionCallOutput, .webSearchCall, .imageGenerationCall, .codeInterpreterCall, .mcpApprovalRequest:
                // These are handled via streaming events or are outputs
                break
            }
        }

        // Map usage (Responses API uses input/output tokens, AIUsage uses prompt/completion)
        let usage = AIUsage(
            promptTokens: response.usage?.inputTokens ?? 0,
            completionTokens: response.usage?.outputTokens ?? 0
        )

        return AITextResult(
            text: text,
            toolCalls: toolCalls,
            usage: usage,
            finishReason: mapFinishReason(response.status),
            requestId: response.id,
            model: response.model,
            provider: "openai",
            responseId: response.id  // Expose for conversation chaining
        )
    }

    /// Map ResponseStatus to AIFinishReason
    private func mapFinishReason(_ status: ResponseStatus) -> AIFinishReason {
        switch status {
        case .completed:
            return .stop
        case .failed:
            return .error
        case .cancelled:
            return .cancelled
        case .incomplete:
            return .contentFilter  // Incomplete typically means content was truncated
        case .inProgress, .queued:
            return .unknown
        }
    }
}

// MARK: - Conversation Chaining Example
/*
 Example: Conversation Chaining with Responses API

 let provider = OpenAIProvider(apiKey: "sk-...")

 // First request
 var request1 = AITextRequest(
     messages: [AIMessage(role: .user, content: .text("My name is Alice"))],
     model: "gpt-4o"
 )
 let result1 = try await provider.sendTextRequest(request1)
 print("Response ID: \(result1.responseId ?? "none")")

 // Second request - pass responseId as conversationId
 var request2 = AITextRequest(
     messages: [AIMessage(role: .user, content: .text("What is my name?"))],
     model: "gpt-4o"
 )
 request2 = request2.withConversationId(result1.responseId)
 let result2 = try await provider.sendTextRequest(request2)
 // result2.text will contain "Alice" because context is preserved

 // With built-in tools
 var request3 = AITextRequest(
     messages: [AIMessage(role: .user, content: .text("Search for latest news about Swift"))],
     model: "gpt-4o"
 )
 request3 = request3.withProviderOptions(OpenAIRequestOptions.withWebSearch())
 let result3 = try await provider.sendTextRequest(request3)
 */
