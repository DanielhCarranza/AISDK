//
//  AISDKClient.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 29/12/24.
//


import Foundation
import Alamofire

/// An async-first AI SDK client for LLMs
public class AISDKClient {
    
    // MARK: - Properties
    
    private let apiKey: String
    private let baseUrl: String
    private let session: Session
    
    // MARK: - Init
    
    /// - Parameters:
    ///   - apiKey: Your OpenAI (or similar) API key.
    ///   - baseUrl: Base URL for your API (defaults to OpenAI).
    ///   - session: An optional custom Alamofire `Session`.
    public init(apiKey: String,
                baseUrl: String = "https://api.openai.com",
                session: Session = .default) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.session = session
    }
    
    // MARK: - 1) Create Chat Completion (Non-Streaming)
    /// Makes a POST /v1/chat/completions call, returning a `ChatCompletionResponse`.
    ///
    /// Example Usage:
    /// ```swift
    /// let request = ChatCompletionRequest(
    ///   model: "gpt-4o",
    ///   messages: [
    ///       ChatMessage(role: "user", content: .string("Hello!"))
    ///   ]
    /// )
    /// let response = try await client.createChatCompletion(request: request)
    /// print(response.choices.first?.message.content ?? "")
    /// ```
    public func createChatCompletion(
        request: ChatCompletionRequest
    ) async throws -> ChatCompletionResponse {
        // Build endpoint
        let endpoint = "\(baseUrl)/v1/chat/completions"
        
        // Make sure URL is valid
        guard let url = URL(string: endpoint) else {
            throw AISDKError.invalidURL
        }
        
        // Add request debugging
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let requestData = try? encoder.encode(request),
           let requestString = String(data: requestData, encoding: .utf8) {
            print("Request payload: \(requestString)")
        }
        
        print("Making request to: \(endpoint)")
        print("With headers: \(authorizationHeaders)")
        
        // Prepare and perform the request with Alamofire
        let dataTask = session.request(
            url,
            method: .post,
            parameters: request,
            encoder: JSONParameterEncoder.default,
            headers: authorizationHeaders
        )
        .validate()
        .responseData { response in
            if let data = response.data {
                print("Raw response: \(String(data: data, encoding: .utf8) ?? "none")")
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
            // For instance:
            print("Error: \(afError.localizedDescription)")
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
    /// Calls POST /v1/chat/completions with `stream = true`.
    /// Returns an `AsyncThrowingStream<ChatCompletionChunk, Error>` that yields chunks as they arrive.
    ///
    /// Example Usage:
    /// ```swift
    /// let request = ChatCompletionRequest(
    ///   model: "gpt-4o",
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
    public func createChatCompletionStream(
        request: ChatCompletionRequest
    ) -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        
        // We enforce `stream = true` before sending
        var streamingRequest = request
        streamingRequest.stream = true
        
        let endpoint = "\(baseUrl)/v1/chat/completions"
        
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
    
    // MARK: - Private Helpers
    
    private var authorizationHeaders: HTTPHeaders {
        [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
    }
}
