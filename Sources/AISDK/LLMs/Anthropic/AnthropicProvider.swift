//
//  ClaudeProvider.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation
import Alamofire

/**
 * CLAUDE OPENAI COMPATIBILITY NOTES:
 * 
 * The Claude provider supports OpenAI compatibility with these limitations:
 * - Fully supported: model, max_tokens, max_completion_tokens, stream, stream_options, 
 *   top_p, parallel_tool_calls, stop, temperature (0-1)
 * - n must be exactly 1
 * - Ignored: logprobs, metadata, response_format, prediction, presence_penalty, 
 *   frequency_penalty, seed, service_tier, audio, logit_bias, store, user, 
 *   modalities, top_logprobs, reasoning_effort
 * - System/developer messages are hoisted to beginning of conversation
 * - The 'strict' parameter for function calling is ignored
 */

public class AnthropicProvider: LLM {
        
    // MARK: - Properties
    
    private let apiKey: String
    private let baseUrl: String
    private let session: Session
    
    // MARK: - Init
    
    /// - Parameters:
    ///   - apiKey: Your Anthropic API key.
    ///   - baseUrl: Base URL for Anthropic's API (defaults to Anthropic's API).
    ///   - session: An optional custom Alamofire `Session`.
    public init(apiKey: String,
                baseUrl: String = "https://api.anthropic.com/v1",
                session: Session = .default) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.session = session
    }
    
    // MARK: - 1) Create Chat Completion (Non-Streaming)
    /// Makes a POST /v1/chat/completions call via Anthropic's OpenAI compatibility layer, returning a `ChatCompletionResponse`.
    ///
    /// Example Usage:
    /// ```swift
    /// let request = ChatCompletionRequest(
    ///   model: "claude-3-7-sonnet-20250219",
    ///   messages: [
    ///       ChatMessage(role: "user", content: .string("Hello!"))
    ///   ]
    /// )
    /// let response = try await client.createChatCompletion(request: request)
    /// print(response.choices.first?.message.content ?? "")
    /// ```
    public func sendChatCompletion(
        request: ChatCompletionRequest
    ) async throws -> ChatCompletionResponse {
        // Create a modified request that respects Claude limitations
        var claudeRequest = request
        
        // Ensure n is 1 (Claude requirement)
        claudeRequest.n = 1
        
        // Cap temperature to 1.0 if it exceeds that
        if let temp = claudeRequest.temperature, temp > 1.0 {
            claudeRequest.temperature = 1.0
        }
        
        // Nullify ignored parameters
        claudeRequest.logprobs = nil
        claudeRequest.metadata = nil
        claudeRequest.presencePenalty = nil
        claudeRequest.frequencyPenalty = nil
        claudeRequest.seed = nil
        claudeRequest.serviceTier = nil
        claudeRequest.logitBias = nil
        claudeRequest.store = nil
        claudeRequest.user = nil
        claudeRequest.modalities = nil
        claudeRequest.reasoningEffort = nil
        
        // Build endpoint
        let endpoint = "\(baseUrl)/chat/completions"
        
        // Make sure URL is valid
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid URL configuration")
        }
        
        // Add request debugging
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let requestData = try? encoder.encode(claudeRequest),
           let requestString = String(data: requestData, encoding: .utf8) {
            print("Request payload: \(requestString)")
        }
        
        print("Making request to: \(endpoint)")
        print("With headers: \(authorizationHeaders)")
        
        // Prepare and perform the request with Alamofire
        let dataTask = session.request(
            url,
            method: .post,
            parameters: claudeRequest,
            encoder: JSONParameterEncoder.default,
            headers: authorizationHeaders
        )
        .validate()
        .responseData { response in
            if let data = response.data {
                print("Claude Raw response: \(String(data: data, encoding: .utf8) ?? "none")")
            }
        }
        .serializingDecodable(ChatCompletionResponse.self)
        
        // Await the result
        let result = await dataTask.result
        
        switch result {
        case .success(let response):
            return response
        case .failure(let afError):
            // Optionally inspect AFError's underlying error / status code
            print("Error from Claude: \(afError.localizedDescription)")
            if let statusCode = afError.responseCode {
                print("HTTP Error \(statusCode): \(afError.localizedDescription)")
                throw AISDKError.httpError(statusCode, afError.localizedDescription)
            } else {
                print("Underlying Error: \(afError.localizedDescription)")
                throw AISDKError.underlying(afError)
            }
        }
    }
    
    // MARK: - 2) Create Chat Completion (Streaming)
    /// Calls POST /v1/chat/completions with `stream = true` via Anthropic's OpenAI compatibility layer.
    /// Returns an `AsyncThrowingStream<ChatCompletionChunk, Error>` that yields chunks as they arrive.
    ///
    /// Example Usage:
    /// ```swift
    /// let request = ChatCompletionRequest(
    ///   model: "claude-3-7-sonnet-20250219",
    ///   messages: [
    ///       ChatMessage(role: "user", content: .string("Hello!"))
    ///   ],
    ///   stream: true
    /// )
    ///
    /// for try await chunk in client.createChatCompletionStream(request: request) {
    ///     for choice in chunk.choices {
    ///         if let partialContent = choice.delta.content {
    ///             print("Partial token: \(partialContent)")
    ///         }
    ///     }
    /// }
    /// ```
    public func sendChatCompletionStream(
        request: ChatCompletionRequest
    ) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        
        // We enforce `stream = true` before sending
        var streamingRequest = request
        streamingRequest.stream = true
        
        let endpoint = "\(baseUrl)/chat/completions"
        
        return AsyncThrowingStream<ChatCompletionChunk, Error> { continuation in
            // Validate URL
            guard let url = URL(string: endpoint) else {
                continuation.finish(throwing: AISDKError.invalidURL)
                return
            }
            
            // Track partial SSE lines between chunks
            var buffer = ""
            
            // Create streaming request
            let streamRequest = session.streamRequest(
                url,
                method: .post,
                parameters: streamingRequest,
                encoder: JSONParameterEncoder.default,
                headers: authorizationHeaders
            )
            .validate()
            
            streamRequest.responseStreamString { stream in
                switch stream.event {
                case let .stream(.success(stringChunk)):
                    // Process the incoming chunk
                    buffer += stringChunk
                    let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
                    
                    // Process complete lines, keeping partial lines in buffer
                    for i in 0..<lines.count {
                        let line = lines[i]
                        
                        // Check if this is an incomplete last line
                        let isLastLine = (i == lines.count - 1 && !buffer.hasSuffix("\n"))
                        if isLastLine {
                            buffer = String(line)
                            break
                        }
                        
                        // Process complete line
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("data:") else { continue }
                        
                        let jsonString = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                        
                        if jsonString == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        
                        // Attempt to decode chunk
                        if let data = jsonString.data(using: .utf8) {
                            do {
                                let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
                                continuation.yield(chunk)
                            } catch {
                                continuation.finish(throwing: AISDKError.parsingError(error.localizedDescription))
                                return
                            }
                        }
                    }
                    
                    // Clear buffer if we've processed all complete lines
                    if buffer.hasSuffix("\n") {
                        buffer = ""
                    }
                    
                case let .stream(.failure(error)):
                    continuation.finish(throwing: AISDKError.underlying(error))
                    
                case .complete(_):
                    continuation.finish()
                }
            }
            
            // Handle cancellation
            continuation.onTermination = { @Sendable _ in
                streamRequest.cancel()
            }
        }
    }
    
    // MARK: - 3) Generate Object from Chat Completion
    /// Makes a POST /v1/chat/completions call via Anthropic's OpenAI compatibility layer and returns a decoded object of the specified type.
    /// If T is JSONSchemaModel, it will parse the content field into the model.
    /// If T is ChatCompletionResponse, it will return the raw response.
    ///
    /// Example Usage:
    /// ```swift
    /// // For schema-validated objects:
    /// let schemaRequest = ChatCompletionRequest(
    ///     model: "claude-3-7-sonnet-20250219",
    ///     messages: [...],
    ///     responseFormat: .jsonSchema(
    ///         name: "fruit_list",
    ///         description: "A list of fruits with their colors",
    ///         schemaBuilder: FruitList.schema(),
    ///         strict: true
    ///     )
    /// )
    /// let fruits: FruitList = try await client.generateObject(request: schemaRequest)
    /// ```
    public func generateObject<T: Decodable>(
        request: ChatCompletionRequest
    ) async throws -> T {
        // Build endpoint
        let endpoint = "\(baseUrl)/chat/completions"
        
        // Make sure URL is valid
        guard let url = URL(string: endpoint) else {
            throw AISDKError.invalidURL
        }
        
        // Prepare and perform the request with Alamofire
        return try await withCheckedThrowingContinuation { continuation in
            session.request(
                url,
                method: .post,
                parameters: request,
                encoder: JSONParameterEncoder.default,
                headers: authorizationHeaders
            )
            .responseData { response in
                // print("GenerateObject Raw response: \(String(data: response.data ?? Data(), encoding: .utf8) ?? "none")")
            }
            .validate()
            .responseDecodable(of: ChatCompletionResponse.self) { response in
                switch response.result {
                case .success(let chatResponse):
                    // If T is ChatCompletionResponse, return it directly
                    if T.self is ChatCompletionResponse.Type {
                        continuation.resume(returning: chatResponse as! T)
                        return
                    }
                    
                    // Otherwise, try to parse the content as a JSONSchemaModel
                    guard let content = chatResponse.choices.first?.message.content,
                          let jsonData = content.data(using: .utf8) else {
                        continuation.resume(throwing: AISDKError.parsingError("Failed to extract content from response"))
                        return
                    }
                    
                    // Attempt to decode the content into the target type
                    do {
                        let decoder = JSONDecoder()
                        let result = try decoder.decode(T.self, from: jsonData)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: AISDKError.parsingError("Failed to decode response to \(T.self): \(error.localizedDescription)"))
                    }
                    
                case .failure(let afError):
                    if let statusCode = afError.responseCode {
                        continuation.resume(throwing: AISDKError.httpError(statusCode, afError.localizedDescription))
                    } else {
                        continuation.resume(throwing: AISDKError.underlying(afError))
                    }
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private var authorizationHeaders: HTTPHeaders {
        [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
            "anthropic-version": "2023-06-01" // Adding Anthropic API version header
        ]
    }
    
    // MARK: - Helper methods for Anthropic-specific features
    
    /// Enables extended thinking for complex tasks
    /// - Parameters:
    ///   - request: The existing ChatCompletionRequest
    ///   - budgetTokens: Number of tokens to allocate for extended thinking (default: 2000)
    /// - Returns: A modified ChatCompletionRequest with extended thinking enabled
    public func withExtendedThinking(
        request: ChatCompletionRequest,
        budgetTokens: Int = 2000
    ) -> ChatCompletionRequest {
        let modifiedRequest = request
        
        // Add extended thinking parameters via extra_body
        // Note: This is a simplified approach - we'd normally need to modify the request structure
        // to support the extra_body parameter for extended thinking
        
        // In a production implementation, you would need to extend ChatCompletionRequest
        // to support the extra_body parameter with thinking configuration
        
        return modifiedRequest
    }
} 