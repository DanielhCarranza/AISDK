//
//  OpenAIProvider.swift
//  HealthCompanion
//
//  Created by Abhigael Mendez Carranza on 03/01/25.
//

import Foundation
import Alamofire

public class OpenAIProvider: LLM {
        
    // MARK: - Properties
    
    internal let apiKey: String
    internal let baseUrl: String
    internal let session: Session
    
    /// The selected model for this provider instance
    public let model: LLMModelProtocol
    
    // MARK: - Init
    
    /// Model-aware initializer with smart default
    /// - Parameters:
    ///   - model: The OpenAI model to use (defaults to GPT-4o)
    ///   - apiKey: Your OpenAI API key (falls back to environment variable)
    ///   - baseUrl: Base URL for your API (defaults to OpenAI)
    ///   - session: An optional custom Alamofire Session
    public init(model: LLMModelProtocol? = nil,
                apiKey: String? = nil,
                baseUrl: String = "https://api.openai.com",
                session: Session = .default) {
        // Use provided model or default to OpenAI's best general-purpose model
        self.model = model ?? OpenAIModels.gpt4o
        
        // API key resolution: parameter → environment → empty (will throw later)
        self.apiKey = apiKey 
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"] 
            ?? ""
        
        self.baseUrl = baseUrl
        self.session = session
    }
    
    /// Legacy initializer - maintained for backward compatibility
    /// - Parameters:
    ///   - apiKey: Your OpenAI (or similar) API key
    ///   - baseUrl: Base URL for your API (defaults to OpenAI)
    ///   - session: An optional custom Alamofire Session
    public init(apiKey: String,
                baseUrl: String = "https://api.openai.com",
                session: Session = .default) {
        self.model = OpenAIModels.gpt4o // Default model for legacy usage
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
    public func sendChatCompletion(
        request: ChatCompletionRequest
    ) async throws -> ChatCompletionResponse {
        // Build endpoint
        let endpoint = "\(baseUrl)/v1/chat/completions"
        
        // Make sure URL is valid
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid URL configuration")
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
            // Simple error logging
            print("DEBUG: AFError occurred - \(afError.localizedDescription)")
            if let responseCode = afError.responseCode {
                print("DEBUG: HTTP Status Code: \(responseCode)")
            }
            throw LLMError.from(afError)
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
    public func sendChatCompletionStream(
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
    
    // MARK: - 3) Generate Object from Chat Completion
    /// Makes a POST /v1/chat/completions call and returns a decoded object of the specified type.
    /// If T is JSONSchemaModel, it will parse the content field into the model.
    /// If T is ChatCompletionResponse, it will return the raw response.
    ///
    /// Example Usage:
    /// ```swift
    /// // For schema-validated objects:
    /// let schemaRequest = ChatCompletionRequest(
    ///     model: "gpt-4",
    ///     messages: [...],
    ///     responseFormat: .jsonSchema(
    ///         name: "fruit_list",
    ///         description: "A list of fruits with their colors",
    ///         schemaBuilder: FruitList.schema(),
    ///         strict: true
    ///     )
    /// )
    /// let fruits: FruitList = try await client.generateObject(request: schemaRequest)
    ///
    /// // For raw responses:
    /// let request = ChatCompletionRequest(model: "gpt-4", messages: [...])
    /// let response: ChatCompletionResponse = try await client.generateObject(request: request)
    /// ```
    public func generateObject<T: Decodable>(
        request: ChatCompletionRequest
    ) async throws -> T {
        // Build endpoint
        let endpoint = "\(baseUrl)/v1/chat/completions"
        
        // Make sure URL is valid
        guard let url = URL(string: endpoint) else {
            throw AISDKError.invalidURL
        }
        
        // Add detailed request logging for debugging
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let requestData = try? encoder.encode(request),
           let requestString = String(data: requestData, encoding: .utf8) {
            print("🔍 GenerateObject Request Details:")
            print("Endpoint: \(endpoint)")
            print("Request Body: \(requestString)")
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
                // Always log the raw response for debugging
                if let data = response.data, let responseString = String(data: data, encoding: .utf8) {
                    print("🔍 GenerateObject Raw Response:")
                    print("Status Code: \(response.response?.statusCode ?? -1)")
                    print("Response Body: \(responseString)")
                }
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
                        let errorMsg = """
                        ❌ Failed to extract content from OpenAI response
                        Response: \(chatResponse)
                        Choices: \(chatResponse.choices)
                        """
                        continuation.resume(throwing: AISDKError.parsingError(errorMsg))
                        return
                    }
                    
                    // Attempt to decode the content into the target type
                    do {
                        let decoder = JSONDecoder()
                        let result = try decoder.decode(T.self, from: jsonData)
                        print("✅ GenerateObject Success: Decoded \(T.self)")
                        continuation.resume(returning: result)
                    } catch {
                        let errorMsg = """
                        ❌ Failed to decode OpenAI response to \(T.self)
                        Raw JSON Content: \(content)
                        Decoding Error: \(error)
                        """
                        continuation.resume(throwing: AISDKError.parsingError(errorMsg))
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
    
    // MARK: - 4) Responses API Methods
    
    /// Creates a response using OpenAI's Responses API
    /// POST /v1/responses
    public func createResponse(request: ResponseRequest) async throws -> ResponseObject {
        let endpoint = "\(baseUrl)/v1/responses"
        
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid URL configuration")
        }
        
        // Debug logging to see what we're sending
        if let requestData = try? JSONEncoder().encode(request),
           let requestString = String(data: requestData, encoding: .utf8) {
            print("DEBUG: Sending request to \(endpoint)")
            print("DEBUG: Request body: \(requestString)")
        }
        
        let dataTask = session.request(
            url,
            method: .post,
            parameters: request,
            encoder: JSONParameterEncoder.default,
            headers: authorizationHeaders
        )
        .validate()
        .serializingDecodable(ResponseObject.self)
        
        let result = await dataTask.result
        
        switch result {
        case .success(let response):
            return response
        case .failure(let afError):
            // Simple error logging
            print("DEBUG: AFError occurred - \(afError.localizedDescription)")
            if let responseCode = afError.responseCode {
                print("DEBUG: HTTP Status Code: \(responseCode)")
            }
            throw LLMError.from(afError)
        }
    }
    
    /// Creates a streaming response using OpenAI's Responses API
    /// POST /v1/responses with stream=true
    public func createResponseStream(request: ResponseRequest) -> AsyncThrowingStream<ResponseChunk, Error> {
        // Create a new request with streaming enabled
        let streamingRequest = ResponseRequest(
            model: request.model,
            input: request.input,
            instructions: request.instructions,
            tools: request.tools,
            toolChoice: request.toolChoice,
            metadata: request.metadata,
            temperature: request.temperature,
            topP: request.topP,
            maxOutputTokens: request.maxOutputTokens,
            stream: true, // Force streaming
            background: request.background,
            previousResponseId: request.previousResponseId,
            include: request.include,
            store: request.store,
            reasoning: request.reasoning,
            parallelToolCalls: request.parallelToolCalls,
            serviceTier: request.serviceTier,
            user: request.user,
            truncation: request.truncation,
            text: request.text
        )
        
        let endpoint = "\(baseUrl)/v1/responses"
        
        return AsyncThrowingStream<ResponseChunk, Error> { continuation in
            guard let url = URL(string: endpoint) else {
                continuation.finish(throwing: LLMError.invalidRequest("Invalid URL"))
                return
            }
            
            var buffer = ""
            var accumulatedResponse: ResponseObject?
            var lineCount = 0
            var eventCount = 0
            var chunkCount = 0
            

            
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
                    buffer += stringChunk
                    
                    // Process complete lines
                    while let newlineRange = buffer.range(of: "\n") {
                        let line = String(buffer[..<newlineRange.lowerBound])
                        buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                        lineCount += 1
                        
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        
                        // Skip empty lines
                        if trimmed.isEmpty {
                            continue
                        }
                        
                        // Handle event: lines
                        if trimmed.hasPrefix("event:") {
                            continue
                        }
                        
                        // Process data: lines
                        if trimmed.hasPrefix("data:") {
                            let jsonString = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
                            eventCount += 1
                            
                            // Check for stream end
                            if jsonString == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            
                            // Parse the JSON data
                            if let data = jsonString.data(using: .utf8) {
                                do {
                                    let streamEvent = try JSONDecoder().decode(ResponseStreamEvent.self, from: data)
                                    
                                    // Update accumulated response for response-level events
                                    if let response = streamEvent.response {
                                        accumulatedResponse = response
                                    }
                                    
                                    // Convert stream event to ResponseChunk
                                    if let chunk = ResponseChunk.from(event: streamEvent, accumulatedResponse: accumulatedResponse) {
                                        chunkCount += 1
                                        continuation.yield(chunk)
                                    }
                                    
                                } catch {
                                    // Try to decode as a complete response object (non-streaming format)
                                    if let response = try? JSONDecoder().decode(ResponseObject.self, from: data) {
                                        let chunk = ResponseChunk(
                                            id: response.id,
                                            object: "response.chunk",
                                            createdAt: response.createdAt,
                                            model: response.model,
                                            status: response.status,
                                            delta: ResponseDelta(output: nil, outputText: response.outputText, reasoning: nil, text: response.outputText),
                                            usage: response.usage,
                                            error: response.error
                                        )
                                        chunkCount += 1
                                        continuation.yield(chunk)
                                    } else {
                                        continuation.finish(throwing: LLMError.parsingError("Failed to parse streaming event: \(error.localizedDescription)"))
                                        return
                                    }
                                }
                            }
                        }
                    }
                    
                case let .stream(.failure(error)):
                    continuation.finish(throwing: LLMError.underlying(error))
                    
                case .complete(_):
                    continuation.finish()
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                streamRequest.cancel()
            }
        }
    }
    
    /// Convenience method for creating a response with web search
    public func createResponseWithWebSearch(
        model: String,
        text: String,
        instructions: String? = nil
    ) async throws -> ResponseObject {
        let request = ResponseRequest(
            model: model,
            input: .string(text),
            instructions: instructions,
            tools: [.webSearchPreview]
        )
        
        return try await createResponse(request: request)
    }
    
    /// Convenience method for creating a response with code interpreter
    public func createResponseWithCodeInterpreter(
        model: String,
        text: String,
        instructions: String? = nil
    ) async throws -> ResponseObject {
        let request = ResponseRequest(
            model: model,
            input: .string(text),
            instructions: instructions,
            tools: [.codeInterpreter]
        )
        
        return try await createResponse(request: request)
    }
    
    /// Convenience method for creating a simple text response
    public func createTextResponse(
        model: String,
        text: String,
        maxOutputTokens: Int? = nil
    ) async throws -> ResponseObject {
        let request = ResponseRequest(
            model: model,
            input: .string(text),
            maxOutputTokens: maxOutputTokens
        )
        
        return try await createResponse(request: request)
    }
    
    /// Convenience method for creating a streaming text response
    public func createTextResponseStream(
        model: String,
        text: String,
        maxOutputTokens: Int? = nil
    ) -> AsyncThrowingStream<ResponseChunk, Error> {
        let request = ResponseRequest(
            model: model,
            input: .string(text),
            maxOutputTokens: maxOutputTokens,
            stream: true
        )
        
        return createResponseStream(request: request)
    }
    
    /// Retrieve a response by ID
    /// GET /v1/responses/{response_id}
    public func retrieveResponse(id: String) async throws -> ResponseObject {
        let endpoint = "\(baseUrl)/v1/responses/\(id)"
        
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid URL configuration")
        }
        
        let dataTask = session.request(
            url,
            method: .get,
            headers: authorizationHeaders
        )
        .validate()
        .serializingDecodable(ResponseObject.self)
        
        let result = await dataTask.result
        
        switch result {
        case .success(let response):
            return response
        case .failure(let afError):
            throw LLMError.from(afError)
        }
    }
    
    /// Cancel a response by ID
    /// POST /v1/responses/{response_id}/cancel
    public func cancelResponse(id: String) async throws -> ResponseObject {
        let endpoint = "\(baseUrl)/v1/responses/\(id)/cancel"
        
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidRequest("Invalid URL configuration")
        }
        
        let dataTask = session.request(
            url,
            method: .post,
            headers: authorizationHeaders
        )
        .validate()
        .serializingDecodable(ResponseObject.self)
        
        let result = await dataTask.result
        
        switch result {
        case .success(let response):
            return response
        case .failure(let afError):
            throw LLMError.from(afError)
        }
    }
    

    
    // MARK: - Private Helpers
    
    internal var authorizationHeaders: HTTPHeaders {
        [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
    }
}