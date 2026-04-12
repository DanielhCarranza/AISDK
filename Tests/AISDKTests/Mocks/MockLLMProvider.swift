//
//  MockLLMProvider.swift
//  AISDKTests
//
//  Created for AISDK Testing
//

import Foundation
@testable import AISDK

/// Mock LegacyLLM provider for testing without making real API calls
public class MockLLMProvider: LegacyLLM {
    
    // MARK: - Configuration
    
    public var shouldThrowError = false
    public var errorToThrow: Error = AISDKError.custom("Mock error")
    public var delay: TimeInterval = 0.1
    
    // MARK: - Mock Responses
    
    public var mockChatResponse: ChatCompletionResponse?
    public var mockStreamChunks: [ChatCompletionChunk] = []
    
    // MARK: - Tracking
    //
    // `requestCount` and `lastRequest` are written from inside the async
    // provider methods, which `StreamingChatTests.testConcurrentStreaming`
    // invokes from multiple child tasks concurrently. Guard them behind a
    // lock so the writes are serialized and any post-run reads see a
    // consistent value. See #49.

    private let stateLock = NSLock()
    private var _lastRequest: ChatCompletionRequest?
    private var _requestCount = 0

    public var lastRequest: ChatCompletionRequest? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _lastRequest
    }

    public var requestCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _requestCount
    }

    private func recordRequest(_ request: ChatCompletionRequest) {
        stateLock.lock()
        defer { stateLock.unlock() }
        _lastRequest = request
        _requestCount += 1
    }

    // MARK: - Initialization

    public init() {
        setupDefaultResponses()
    }

    // MARK: - LegacyLLM Protocol Implementation

    public func sendChatCompletion(request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        recordRequest(request)

        if shouldThrowError {
            throw errorToThrow
        }

        // Simulate network delay
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        return mockChatResponse ?? createDefaultResponse(for: request)
    }

    public func sendChatCompletionStream(request: ChatCompletionRequest) async throws -> AsyncThrowingStream<ChatCompletionChunk, Error> {
        recordRequest(request)

        if shouldThrowError {
            throw errorToThrow
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                for chunk in mockStreamChunks.isEmpty ? createDefaultStreamChunks() : mockStreamChunks {
                    // Simulate streaming delay
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }
    
    public func generateObject<T: Decodable>(request: ChatCompletionRequest) async throws -> T {
        let response = try await sendChatCompletion(request: request)
        
        guard let content = response.choices.first?.message.content,
              let data = content.data(using: .utf8) else {
            throw AISDKError.parsingError("No content in response")
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AISDKError.parsingError("Failed to decode object: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    public func reset() {
        stateLock.lock()
        _requestCount = 0
        _lastRequest = nil
        stateLock.unlock()
        shouldThrowError = false
        setupDefaultResponses()
    }
    
    public func setMockResponse(_ response: ChatCompletionResponse) {
        mockChatResponse = response
    }
    
    public func setMockStreamChunks(_ chunks: [ChatCompletionChunk]) {
        mockStreamChunks = chunks
    }
    
    // MARK: - Private Methods
    
    private func setupDefaultResponses() {
        // Don't set mockChatResponse by default - let it use createDefaultResponse
        mockChatResponse = nil
        mockStreamChunks = createDefaultStreamChunks()
    }
    
    private func createDefaultResponse(for request: ChatCompletionRequest) -> ChatCompletionResponse {
        let lastMessage = request.messages.last
        
        // Extract actual text content from the message
        let messageText: String
        if let message = lastMessage {
            switch message {
            case .user(let content, _):
                switch content {
                case .text(let text):
                    messageText = text
                case .parts(let parts):
                    messageText = parts.compactMap { part in
                        if case .text(let text) = part { return text }
                        return nil
                    }.joined(separator: " ")
                }
            case .assistant(let content, _, _):
                switch content {
                case .text(let text):
                    messageText = text
                case .parts(let parts):
                    messageText = parts.joined(separator: " ")
                }
            case .system(let content, _):
                switch content {
                case .text(let text):
                    messageText = text
                case .parts(let parts):
                    messageText = parts.joined(separator: " ")
                }
            case .tool(let content, _, _):
                messageText = content
            case .developer(let content, _):
                switch content {
                case .text(let text):
                    messageText = text
                case .parts(let parts):
                    messageText = parts.joined(separator: " ")
                }
            }
        } else {
            messageText = "no message"
        }
        
        let responseContent = "Mock response to: \(messageText)"
        
        return ChatCompletionResponse(
            id: "mock-\(UUID().uuidString)",
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: request.model,
            systemFingerprint: "mock-fingerprint",
            serviceTier: nil,
            choices: [
                ChatCompletionResponse.Choice(
                    index: 0,
                    message: ChatCompletionResponse.LegacyMessage(
                        role: "assistant",
                        content: responseContent,
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 10,
                completionTokens: responseContent.count,
                totalTokens: 10 + responseContent.count,
                completionTokensDetails: nil
            )
        )
    }
    
    private func createDefaultStreamChunks() -> [ChatCompletionChunk] {
        let words = ["This", " is", " a", " mock", " streaming", " response", " for", " testing", "."]
        
        return words.enumerated().map { index, word in
            ChatCompletionChunk(
                id: "mock-chunk-\(index)",
                object: "chat.completion.chunk",
                created: Int(Date().timeIntervalSince1970),
                model: "mock-model",
                systemFingerprint: nil,
                serviceTier: nil,
                choices: [
                    ChatCompletionChunk.Choice(
                        index: 0,
                        delta: ChatCompletionChunk.Delta(
                            role: index == 0 ? "assistant" : nil,
                            content: word,
                            toolCalls: nil
                        ),
                        finishReason: index == words.count - 1 ? "stop" : nil
                    )
                ],
                usage: nil
            )
        }
    }
}

// MARK: - Mock Response Builders

extension MockLLMProvider {
    
    /// Creates a mock tool calling response
    public static func mockToolCallResponse(toolName: String, arguments: String) -> ChatCompletionResponse {
        return ChatCompletionResponse(
            id: "mock-tool-call-id",
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: "mock-model",
            systemFingerprint: nil,
            serviceTier: nil,
            choices: [
                ChatCompletionResponse.Choice(
                    index: 0,
                    message: ChatCompletionResponse.LegacyMessage(
                        role: "assistant",
                        content: nil,
                        toolCalls: [
                            ChatCompletionResponse.ToolCall(
                                id: "mock-tool-call-id",
                                type: "function",
                                function: ChatCompletionResponse.ToolFunctionCall(
                                    name: toolName,
                                    arguments: arguments
                                )
                            )
                        ],
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "tool_calls"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 10,
                completionTokens: 5,
                totalTokens: 15,
                completionTokensDetails: nil
            )
        )
    }
    
    /// Creates a mock JSON response
    public static func mockJSONResponse(jsonContent: String) -> ChatCompletionResponse {
        return ChatCompletionResponse(
            id: "mock-json-id",
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: "mock-model",
            systemFingerprint: nil,
            serviceTier: nil,
            choices: [
                ChatCompletionResponse.Choice(
                    index: 0,
                    message: ChatCompletionResponse.LegacyMessage(
                        role: "assistant",
                        content: jsonContent,
                        toolCalls: nil,
                        refusal: nil
                    ),
                    logprobs: nil,
                    finishReason: "stop"
                )
            ],
            usage: ChatCompletionResponse.Usage(
                promptTokens: 8,
                completionTokens: jsonContent.count,
                totalTokens: 8 + jsonContent.count,
                completionTokensDetails: nil
            )
        )
    }
} 