//
//  OpenAIProvider+Compaction.swift
//  AISDK
//
//  Compaction support for OpenAI Responses API
//  Enables efficient context window management for long conversations
//

import Foundation
import Alamofire

// MARK: - Compaction Operations

extension OpenAIProvider {

    /// Compact a conversation to reduce token usage
    ///
    /// Compaction performs a loss-aware compression pass over prior conversation state,
    /// returning encrypted, opaque items that preserve task-relevant information while
    /// dramatically reducing token footprint.
    ///
    /// - Parameters:
    ///   - model: The model to use (should match the conversation's model)
    ///   - previousResponseId: Response ID to compact from (uses conversation history)
    ///   - instructions: Optional instructions for guiding compaction
    /// - Returns: Compacted conversation that can be used in subsequent requests
    /// - Throws: `AISDKErrorV2` if compaction fails
    ///
    /// Example:
    /// ```swift
    /// // After many conversation turns
    /// let compacted = try await provider.compactConversation(
    ///     model: "gpt-4.1",
    ///     previousResponseId: lastResponseId,
    ///     instructions: "Preserve key facts about the discussion"
    /// )
    ///
    /// print("Saved \(compacted.tokensSaved ?? 0) tokens")
    /// print("Compression ratio: \(Int((compacted.compressionRatio ?? 0) * 100))%")
    /// ```
    public func compactConversation(
        model: String,
        previousResponseId: String,
        instructions: String? = nil
    ) async throws -> CompactedConversation {
        let request = CompactRequest(
            model: model,
            instructions: instructions,
            previousResponseId: previousResponseId
        )

        let response = try await compactResponse(request: request)

        // Calculate total token counts from all compacted items
        let originalTokenCount = response.output.compactMap { $0.originalTokenCount }.reduce(0, +)
        let compactedTokenCount = response.output.compactMap { $0.compactedTokenCount }.reduce(0, +)

        return CompactedConversation(
            id: response.id,
            compactedItems: response.output,
            usage: AIUsage(
                promptTokens: response.usage.inputTokens,
                completionTokens: response.usage.outputTokens
            ),
            originalTokenCount: originalTokenCount > 0 ? originalTokenCount : nil,
            compactedTokenCount: compactedTokenCount > 0 ? compactedTokenCount : nil
        )
    }

    /// Compact specific input messages
    ///
    /// - Parameters:
    ///   - model: The model to use
    ///   - input: Input messages to compact
    ///   - instructions: Optional instructions for guiding compaction
    /// - Returns: Compacted conversation
    /// - Throws: `AISDKErrorV2` if compaction fails
    public func compactInput(
        model: String,
        input: ResponseInput,
        instructions: String? = nil
    ) async throws -> CompactedConversation {
        let request = CompactRequest(
            model: model,
            input: input,
            instructions: instructions
        )

        let response = try await compactResponse(request: request)

        let originalTokenCount = response.output.compactMap { $0.originalTokenCount }.reduce(0, +)
        let compactedTokenCount = response.output.compactMap { $0.compactedTokenCount }.reduce(0, +)

        return CompactedConversation(
            id: response.id,
            compactedItems: response.output,
            usage: AIUsage(
                promptTokens: response.usage.inputTokens,
                completionTokens: response.usage.outputTokens
            ),
            originalTokenCount: originalTokenCount > 0 ? originalTokenCount : nil,
            compactedTokenCount: compactedTokenCount > 0 ? compactedTokenCount : nil
        )
    }

    /// Continue a conversation using compacted history
    ///
    /// Uses the compacted items from a previous compaction as context
    /// for the new request.
    ///
    /// - Parameters:
    ///   - request: The new request to send
    ///   - compactedConversation: Previously compacted conversation
    /// - Returns: Result of the request
    /// - Throws: `AISDKErrorV2` on failure
    ///
    /// Example:
    /// ```swift
    /// let compacted = try await provider.compactConversation(
    ///     model: "gpt-4.1",
    ///     previousResponseId: conversationId
    /// )
    ///
    /// let result = try await provider.sendTextWithCompactedHistory(
    ///     request: AITextRequest(
    ///         messages: [AIMessage(role: .user, content: .text("Summarize our discussion"))],
    ///         model: "gpt-4.1"
    ///     ),
    ///     compactedConversation: compacted
    /// )
    /// ```
    public func sendTextWithCompactedHistory(
        request: AITextRequest,
        compactedConversation: CompactedConversation
    ) async throws -> AITextResult {
        // Build input that includes compacted item references and new messages
        var inputItems: [ResponseInputItem] = []

        // Add compacted items as references
        for item in compactedConversation.compactedItems {
            inputItems.append(.itemReference(ResponseItemReference(id: item.id)))
        }

        // Add new message(s) from the request
        for message in request.messages {
            if let inputItem = convertMessageToCompactionInputItem(message) {
                inputItems.append(inputItem)
            }
        }

        // Extract system instructions
        let systemInstructions = request.messages
            .first { $0.role == .system }
            .flatMap { message -> String? in
                if case .text(let text) = message.content {
                    return text
                }
                return nil
            }

        // Resolve model - use request model or provider default
        let resolvedModel = request.model ?? model.name

        // Build the request
        var responseRequest = ResponseRequest(
            model: resolvedModel,
            input: .items(inputItems),
            instructions: systemInstructions,
            temperature: request.temperature,
            topP: request.topP,
            maxOutputTokens: request.maxTokens,
            stream: false
        )

        // Add tools if present - convert ToolSchema to ResponseTool
        if let tools = request.tools {
            responseRequest.tools = tools.compactMap { convertToolSchemaForCompaction($0) }
        }

        // Add provider options
        if let options = request.providerOptions as? OpenAIRequestOptions {
            responseRequest.store = options.store
            responseRequest.serviceTier = options.serviceTier?.rawValue
        }

        let response = try await createResponse(request: responseRequest)
        return convertToAITextResult(response)
    }

    /// Send text with automatic compaction when approaching token limits
    ///
    /// Automatically compacts the conversation when the estimated token count
    /// exceeds a threshold.
    ///
    /// - Parameters:
    ///   - request: The request to send
    ///   - conversationId: Current conversation's response ID
    ///   - tokenLimit: Maximum tokens before compaction (default: 100,000)
    ///   - compactionThreshold: Percentage of limit to trigger compaction (default: 0.8)
    /// - Returns: Tuple of result and whether compaction occurred
    /// - Throws: `AISDKErrorV2` on failure
    ///
    /// Example:
    /// ```swift
    /// let (result, didCompact) = try await provider.sendTextWithAutoCompaction(
    ///     request: request,
    ///     conversationId: conversationId,
    ///     tokenLimit: 100_000,
    ///     compactionThreshold: 0.8
    /// )
    ///
    /// if didCompact {
    ///     print("Conversation was automatically compacted")
    /// }
    /// ```
    public func sendTextWithAutoCompaction(
        request: AITextRequest,
        conversationId: String?,
        tokenLimit: Int = 100_000,
        compactionThreshold: Double = 0.8
    ) async throws -> (result: AITextResult, didCompact: Bool, compactedConversation: CompactedConversation?) {
        guard let conversationId = conversationId else {
            // No conversation to compact, send normally
            let result = try await sendTextRequest(request)
            return (result, false, nil)
        }

        // Estimate current token usage from the conversation
        let estimatedTokens = estimateTokensFromMessages(request.messages)

        let thresholdTokens = Int(Double(tokenLimit) * compactionThreshold)

        if estimatedTokens > thresholdTokens {
            // Compact before sending - use request model or provider default
            let resolvedModel = request.model ?? model.name
            let compacted = try await compactConversation(
                model: resolvedModel,
                previousResponseId: conversationId
            )

            let result = try await sendTextWithCompactedHistory(
                request: request,
                compactedConversation: compacted
            )

            return (result, true, compacted)
        }

        // Normal send with conversation continuation
        var requestWithConversation = request
        requestWithConversation.conversationId = conversationId
        let result = try await sendTextRequest(requestWithConversation)
        return (result, false, nil)
    }

    // MARK: - Private Helpers

    /// Compact a conversation using the /responses/compact endpoint
    private func compactResponse(request: CompactRequest) async throws -> CompactResponse {
        let endpoint = "\(baseUrl)/v1/responses/compact"

        guard let url = URL(string: endpoint) else {
            throw AISDKErrorV2(code: .invalidRequest, message: "Invalid compact endpoint URL")
        }

        let dataTask = session.request(
            url,
            method: .post,
            parameters: request,
            encoder: JSONParameterEncoder.default,
            headers: authorizationHeaders
        )
        .validate()
        .serializingDecodable(CompactResponse.self)

        let result = await dataTask.result

        switch result {
        case .success(let response):
            return response
        case .failure(let afError):
            throw mapAFError(afError)
        }
    }

    /// Map Alamofire error to AISDKErrorV2
    private func mapAFError(_ afError: AFError) -> AISDKErrorV2 {
        if let responseCode = afError.responseCode {
            return mapHTTPError(statusCode: responseCode, message: afError.localizedDescription)
        }
        return AISDKErrorV2(code: .networkFailed, message: afError.localizedDescription)
    }

    /// Convert an AIMessage to a ResponseInputItem (for compaction)
    private func convertMessageToCompactionInputItem(_ message: AIMessage) -> ResponseInputItem? {
        let role: String
        switch message.role {
        case .user:
            role = "user"
        case .assistant:
            role = "assistant"
        case .system:
            return nil // System messages become instructions
        case .tool:
            // Tool messages need special handling
            if case .text(let output) = message.content {
                return .functionCallOutput(ResponseFunctionCallOutput(
                    callId: message.toolCallId ?? "",
                    output: output
                ))
            }
            return nil
        }

        switch message.content {
        case .text(let text):
            return .message(ResponseMessage(
                role: role,
                content: [.inputText(ResponseInputText(text: text))]
            ))
        case .parts(let parts):
            let contentParts: [ResponseContentItem] = parts.compactMap { part in
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
                    // Audio and file content types are not directly supported
                    return nil
                }
            }
            return .message(ResponseMessage(
                role: role,
                content: contentParts
            ))
        }
    }

    /// Convert a ToolSchema to a ResponseTool (for compaction)
    private func convertToolSchemaForCompaction(_ schema: ToolSchema) -> ResponseTool? {
        guard let function = schema.function else { return nil }
        return .function(function)
    }

    /// Rough token estimation from messages
    private func estimateTokensFromMessages(_ messages: [AIMessage]) -> Int {
        var totalChars = 0
        for message in messages {
            switch message.content {
            case .text(let text):
                totalChars += text.count
            case .parts(let parts):
                for part in parts {
                    switch part {
                    case .text(let text):
                        totalChars += text.count
                    case .image:
                        totalChars += 500 // Rough estimate for image tokens
                    case .imageURL:
                        totalChars += 500 // Rough estimate for image tokens
                    case .audio:
                        totalChars += 200 // Base overhead for audio
                    case .file:
                        totalChars += 100 // Base overhead for files
                    case .video:
                        totalChars += 1000 // Base overhead for video
                    case .videoURL:
                        totalChars += 1000 // Base overhead for video
                    }
                }
            }
            // Add tool call overhead if present
            if let toolCalls = message.toolCalls {
                for call in toolCalls {
                    totalChars += call.name.count + call.arguments.count
                }
            }
            totalChars += 50 // Overhead per message
        }
        // Rough estimate: ~4 characters per token
        return totalChars / 4
    }

    /// Map HTTP status code to AISDKErrorV2
    private func mapHTTPError(statusCode: Int, message: String) -> AISDKErrorV2 {
        switch statusCode {
        case 400:
            return AISDKErrorV2(code: .invalidRequest, message: message)
        case 401:
            return AISDKErrorV2(code: .authenticationFailed, message: message)
        case 404:
            return AISDKErrorV2(code: .invalidRequest, message: "Endpoint not found: \(message)")
        case 429:
            return AISDKErrorV2(code: .rateLimitExceeded, message: message)
        case 500...599:
            return AISDKErrorV2(code: .providerUnavailable, message: message)
        default:
            return AISDKErrorV2(code: .unknown, message: message)
        }
    }
}
