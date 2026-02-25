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

        var builtInToolsByKind: [String: [ResponseTool]] = [:]
        var builtInKindOrder: [String] = []

        func insertBuiltInTools(kind: String, tools newTools: [ResponseTool], preferOrder: Bool) {
            if builtInToolsByKind[kind] != nil {
                builtInToolsByKind[kind] = newTools
                if preferOrder, let index = builtInKindOrder.firstIndex(of: kind) {
                    builtInKindOrder.remove(at: index)
                    builtInKindOrder.append(kind)
                }
            } else {
                builtInToolsByKind[kind] = newTools
                builtInKindOrder.append(kind)
            }
        }

        // Add built-in tools from provider options
        if let webConfig = openAIOptions?.webSearch, webConfig.enabled {
            insertBuiltInTools(kind: "webSearch", tools: [.webSearchPreview()], preferOrder: false)
        }

        if let fileConfig = openAIOptions?.fileSearch, fileConfig.enabled {
            let fileTools = [ResponseTool.fileSearch(ResponseFileSearchTool(vectorStoreIds: fileConfig.vectorStoreIds))]
            insertBuiltInTools(kind: "fileSearch", tools: fileTools, preferOrder: false)
        }

        if let codeConfig = openAIOptions?.codeInterpreter, codeConfig.enabled {
            insertBuiltInTools(kind: "codeExecution", tools: [.codeInterpreter()], preferOrder: false)
        }

        // Add built-in tools from core request, deduping by kind (core takes precedence)
        if let builtInTools = request.builtInTools {
            for tool in builtInTools {
                switch tool {
                case .webSearch, .webSearchDefault:
                    insertBuiltInTools(kind: tool.kind, tools: [.webSearchPreview()], preferOrder: true)
                case .codeExecution, .codeExecutionDefault:
                    insertBuiltInTools(kind: tool.kind, tools: [.codeInterpreter()], preferOrder: true)
                case .fileSearch(let config):
                    guard !config.vectorStoreIds.isEmpty else {
                        throw ProviderError.invalidRequest("fileSearch requires at least one vectorStoreId for OpenAI.")
                    }
                    let fileTools = [ResponseTool.fileSearch(ResponseFileSearchTool(vectorStoreIds: config.vectorStoreIds))]
                    insertBuiltInTools(kind: tool.kind, tools: fileTools, preferOrder: true)
                case .imageGeneration(let config):
                    insertBuiltInTools(
                        kind: tool.kind,
                        tools: [.imageGeneration(ResponseImageGenerationTool(partialImages: config.partialImages))],
                        preferOrder: true
                    )
                case .imageGenerationDefault:
                    insertBuiltInTools(kind: tool.kind, tools: [.imageGeneration()], preferOrder: true)
                case .computerUse(let config):
                    insertBuiltInTools(kind: tool.kind, tools: [
                        .computerUsePreview(ResponseComputerUseTool(
                            displayWidth: config.displayWidth,
                            displayHeight: config.displayHeight,
                            environment: config.environment?.rawValue
                        ))
                    ], preferOrder: true)
                case .computerUseDefault:
                    insertBuiltInTools(kind: tool.kind, tools: [
                        .computerUsePreview(ResponseComputerUseTool(displayWidth: 1024, displayHeight: 768, environment: "browser"))
                    ], preferOrder: true)
                case .urlContext:
                    throw ProviderError.invalidRequest("urlContext is not supported by OpenAI.")
                }
            }
        }

        for kind in builtInKindOrder {
            if let builtInTools = builtInToolsByKind[kind] {
                tools.append(contentsOf: builtInTools)
            }
        }

        // Convert reasoning config (provider-specific overrides unified)
        let reasoning: ResponseReasoning?
        if let reasoningConfig = openAIOptions?.reasoning {
            reasoning = ResponseReasoning(
                effort: reasoningConfig.effort?.rawValue,
                summary: reasoningConfig.summary?.rawValue
            )
        } else if let reasoningConfig = request.reasoning, reasoningConfig.effort != nil {
            reasoning = ResponseReasoning(
                effort: reasoningConfig.effort?.rawValue,
                summary: reasoningConfig.summary?.rawValue ?? "auto"
            )
        } else {
            reasoning = nil
        }

        // Auto-enable truncation for computer use (OpenAI requirement)
        let hasComputerUse = tools.contains(where: {
            if case .computerUsePreview = $0 { return true }
            return false
        })
        let truncation: String? = hasComputerUse ? "auto" : nil

        // Convert response format to Responses API text config
        let textConfig: ResponseTextConfig?
        if let responseFormat = request.responseFormat {
            textConfig = convertResponseFormat(responseFormat)
        } else {
            textConfig = nil
        }

        // Auto-set include for web search sources when web search tools are present
        let hasWebSearch = tools.contains(where: {
            if case .webSearchPreview = $0 { return true }
            return false
        })
        let include: [String]? = hasWebSearch ? ["web_search_call.results"] : nil

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
            include: include,
            store: openAIOptions?.store,  // Privacy-first: nil by default
            reasoning: reasoning,
            parallelToolCalls: true,
            serviceTier: openAIOptions?.serviceTier?.rawValue,
            user: nil,
            truncation: truncation,
            text: textConfig
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
        // Use flatMap to allow a single message to expand into multiple input items
        // (e.g., an assistant message with computer use tool calls becomes a message + computer_call items)
        let items = messages.flatMap { convertMessageToInputItems($0) }
        return .items(items)
    }

    /// Convert a single message to one or more ResponseInputItems.
    ///
    /// An assistant message with computer use tool calls expands into:
    /// 1. The assistant message (text content only, if any)
    /// 2. A `computer_call` item for each `__computer_use__` tool call
    private func convertMessageToInputItems(_ message: AIMessage) -> [ResponseInputItem] {
        // For assistant messages with computer use tool calls, emit computer_call items
        if message.role == .assistant, let toolCalls = message.toolCalls {
            let cuCalls = toolCalls.filter { $0.name == "__computer_use__" }
            if !cuCalls.isEmpty {
                var items: [ResponseInputItem] = []

                // Include the assistant text message if it has content
                let text: String
                switch message.content {
                case .text(let t): text = t
                case .parts(let parts):
                    text = parts.compactMap { if case .text(let t) = $0 { return t }; return nil }.joined()
                }
                if !text.isEmpty {
                    items.append(.message(ResponseMessage(role: "assistant", content: [.inputText(ResponseInputText(text: text))])))
                }

                // Emit a computer_call item for each CU tool call
                for tc in cuCalls {
                    if let data = tc.arguments.data(using: .utf8),
                       let payload = try? JSONDecoder().decode(ComputerUseOpenAIPayload.self, from: data) {
                        let action = ResponseOutputComputerCall.ComputerCallAction(
                            type: payload.actionType,
                            x: payload.x, y: payload.y,
                            button: payload.button, text: payload.text,
                            keys: payload.keys,
                            scrollX: payload.scrollX, scrollY: payload.scrollY,
                            path: payload.path?.map { ResponseOutputComputerCall.ComputerCallAction.PathPoint(x: $0["x"] ?? 0, y: $0["y"] ?? 0) },
                            ms: payload.ms
                        )
                        items.append(.computerCall(ResponseInputComputerCall(
                            id: payload.responseItemId ?? tc.id,
                            callId: payload.callId ?? tc.id,
                            action: action
                        )))
                    }
                }
                return items
            }
        }

        // Default: delegate to single-item conversion
        if let item = convertMessageToSingleInputItem(message) {
            return [item]
        }
        return []
    }

    /// Convert a single message to a single ResponseInputItem (original logic).
    private func convertMessageToSingleInputItem(_ message: AIMessage) -> ResponseInputItem? {
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

            // Check for computer use result payload
            if output.contains("\"__computer_use_result__\""),
               let payloadData = output.data(using: .utf8),
               let payload = try? JSONDecoder().decode(ComputerUseResultPayload.self, from: payloadData),
               payload.type == "__computer_use_result__" {
                let imageUrl: String?
                if let screenshot = payload.screenshot, let mediaType = payload.mediaType {
                    imageUrl = "data:\(mediaType);base64,\(screenshot)"
                } else {
                    imageUrl = nil
                }
                // TODO: Forward safety checks from the original computer_call when available
                return .computerCallOutput(ResponseComputerCallOutput(
                    callId: payload.callId ?? toolCallId,
                    output: ResponseComputerCallOutput.ComputerCallOutputContent(
                        type: "computer_screenshot",
                        imageUrl: imageUrl
                    ),
                    acknowledgedSafetyChecks: []
                ))
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

    /// Convert ResponseFormat to Responses API text configuration
    private func convertResponseFormat(_ format: ResponseFormat) -> ResponseTextConfig {
        switch format {
        case .text:
            return ResponseTextConfig(format: ResponseTextFormat(type: "text"))
        case .jsonObject:
            return ResponseTextConfig(format: ResponseTextFormat(type: "json_object"))
        case .jsonSchema(let name, _, let schemaBuilder, let strict):
            let schema = schemaBuilder.build()
            // Encode JSONSchema to [String: Any] for ResponseJSONSchema
            var schemaDict: [String: Any]?
            if let data = try? JSONEncoder().encode(schema),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                schemaDict = dict
            }
            let jsonSchema = ResponseJSONSchema(
                name: name,
                schema: schemaDict,
                strict: strict
            )
            return ResponseTextConfig(
                format: ResponseTextFormat(type: "json_schema", jsonSchema: jsonSchema)
            )
        }
    }

    // MARK: - Response Conversion

    /// Convert ResponseObject to AITextResult
    internal func convertToAITextResult(_ response: ResponseObject) -> AITextResult {
        // Extract text from message outputs
        var text = ""
        var toolCalls: [ToolCallResult] = []
        var sources: [AISource] = []

        for item in response.output {
            switch item {
            case .message(let message):
                for content in message.content {
                    switch content {
                    case .outputText(let outputText):
                        text += outputText.text
                        // Extract citation sources from annotations
                        if let annotations = outputText.annotations {
                            for annotation in annotations {
                                switch annotation {
                                case .urlCitation(let citation):
                                    let snippet = outputText.text.citedText(
                                        startIndex: citation.startIndex,
                                        endIndex: citation.endIndex
                                    )
                                    sources.append(AISource(
                                        id: citation.url,
                                        url: citation.url,
                                        title: citation.title,
                                        snippet: snippet,
                                        startIndex: citation.startIndex,
                                        endIndex: citation.endIndex,
                                        sourceType: .web
                                    ))
                                case .fileCitation(let citation):
                                    sources.append(AISource(
                                        id: citation.fileId,
                                        url: nil,
                                        title: citation.filename,
                                        sourceType: .file
                                    ))
                                case .containerFileCitation(let citation):
                                    sources.append(AISource(
                                        id: "\(citation.containerId)/\(citation.fileId)",
                                        url: nil,
                                        title: citation.filename,
                                        startIndex: citation.startIndex,
                                        endIndex: citation.endIndex,
                                        sourceType: .containerFile
                                    ))
                                case .filePath, .unknown:
                                    break
                                }
                            }
                        }
                    case .outputImage:
                        // Image outputs could be handled if needed
                        break
                    case .refusal:
                        // Content policy refusals are not extractable text
                        break
                    case .unknown:
                        // Unrecognized content types are silently skipped
                        break
                    }
                }
            case .functionCall(let call):
                toolCalls.append(ToolCallResult(
                    id: call.callId,
                    name: call.name,
                    arguments: call.arguments
                ))
            case .computerCall(let call):
                // Convert OpenAI computer_call to a sentinel tool call for Agent routing
                let action = call.action
                let safetyChecks = call.pendingSafetyChecks ?? []
                let payload = ComputerUseOpenAIPayload(
                    actionType: action.type,
                    x: action.x, y: action.y,
                    button: action.button,
                    text: action.text,
                    keys: action.keys,
                    scrollX: action.scrollX, scrollY: action.scrollY,
                    path: action.path?.map { ["x": $0.x, "y": $0.y] },
                    ms: action.ms,
                    safetyChecks: safetyChecks.map {
                        ["id": $0.id, "code": $0.code, "message": $0.message]
                    },
                    callId: call.callId,
                    responseItemId: call.id
                )
                let argsData = (try? JSONEncoder().encode(payload)) ?? Data()
                let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                toolCalls.append(ToolCallResult(
                    id: call.callId,
                    name: "__computer_use__",
                    arguments: argsString
                ))
            case .functionCallOutput, .webSearchCall, .imageGenerationCall, .codeInterpreterCall, .mcpApprovalRequest:
                // These are handled via streaming events or are outputs
                break
            case .reasoning:
                // Reasoning items are metadata, not extractable text
                break
            case .mcpCall, .mcpListTools:
                // MCP execution results are metadata
                break
            case .unknown:
                // Unrecognized output types are silently skipped
                break
            }
        }

        // Map usage (Responses API uses input/output tokens, AIUsage uses prompt/completion)
        let usage = AIUsage(
            promptTokens: response.usage?.inputTokens ?? 0,
            completionTokens: response.usage?.outputTokens ?? 0,
            reasoningTokens: response.usage?.outputTokensDetails?.reasoningTokens,
            cachedTokens: response.usage?.inputTokensDetails?.cachedTokens
        )

        return AITextResult(
            text: text,
            toolCalls: toolCalls,
            usage: usage,
            finishReason: mapFinishReason(response.status),
            requestId: response.id,
            model: response.model,
            provider: "openai",
            responseId: response.id,  // Expose for conversation chaining
            sources: sources
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
            return .length  // Incomplete means max_output_tokens was hit (token truncation)
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
