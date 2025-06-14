//
//  MockOpenAIResponsesProvider.swift
//  AISDKTests
//
//  Created for AISDK Testing - OpenAI Responses API
//

import Foundation
@testable import AISDK

/// Mock provider for OpenAI Responses API testing
public class MockOpenAIResponsesProvider {
    
    // MARK: - Configuration
    
    public var shouldThrowError = false
    public var errorToThrow: Error = AISDKError.custom("Mock error")
    public var delay: TimeInterval = 0.1
    
    // MARK: - Mock Responses
    
    public var mockResponse: ResponseObject?
    public var mockStreamChunks: [ResponseChunk] = []
    
    // MARK: - Tracking
    
    public private(set) var lastRequest: ResponseRequest?
    public private(set) var requestCount = 0
    public private(set) var lastRetrieveId: String?
    public private(set) var lastCancelId: String?
    
    // MARK: - Initialization
    
    public init() {
        setupDefaultResponses()
    }
    
    // MARK: - Mock Methods
    
    public func createResponse(request: ResponseRequest) async throws -> ResponseObject {
        lastRequest = request
        requestCount += 1
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        return mockResponse ?? createDefaultResponse(for: request)
    }
    
    public func createResponseStream(request: ResponseRequest) -> AsyncThrowingStream<ResponseChunk, Error> {
        lastRequest = request
        requestCount += 1
        
        return AsyncThrowingStream { continuation in
            Task {
                if self.shouldThrowError {
                    continuation.finish(throwing: self.errorToThrow)
                    return
                }
                
                let chunks = self.mockStreamChunks.isEmpty ? self.createDefaultStreamChunks() : self.mockStreamChunks
                
                for chunk in chunks {
                    // Simulate streaming delay
                    try await Task.sleep(nanoseconds: UInt64(self.delay * 1_000_000_000))
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }
    
    public func retrieveResponse(id: String) async throws -> ResponseObject {
        lastRetrieveId = id
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        return mockResponse ?? createDefaultResponse(id: id)
    }
    
    public func cancelResponse(id: String) async throws -> ResponseObject {
        lastCancelId = id
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        var response = mockResponse ?? createDefaultResponse(id: id)
        // Update the response to show cancelled status
        response = ResponseObject(
            id: response.id,
            object: response.object,
            createdAt: response.createdAt,
            model: response.model,
            status: .cancelled,
            output: response.output,
            usage: response.usage,
            previousResponseId: response.previousResponseId,
            metadata: response.metadata,
            incompleteDetails: response.incompleteDetails,
            error: response.error,
            instructions: response.instructions,
            temperature: response.temperature,
            topP: response.topP,
            maxOutputTokens: response.maxOutputTokens,
            toolChoice: response.toolChoice,
            tools: response.tools,
            parallelToolCalls: response.parallelToolCalls,
            reasoning: response.reasoning,
            truncation: response.truncation,
            text: response.text,
            user: response.user,
            store: response.store,
            serviceTier: response.serviceTier
        )
        
        return response
    }
    
    // MARK: - Helper Methods
    
    public func reset() {
        requestCount = 0
        lastRequest = nil
        lastRetrieveId = nil
        lastCancelId = nil
        shouldThrowError = false
        setupDefaultResponses()
    }
    
    public func setMockResponse(_ response: ResponseObject) {
        mockResponse = response
    }
    
    public func setMockStreamChunks(_ chunks: [ResponseChunk]) {
        mockStreamChunks = chunks
    }
    
    // MARK: - Private Methods
    
    private func setupDefaultResponses() {
        mockResponse = nil
        mockStreamChunks = []
    }
    
    private func createDefaultResponse(for request: ResponseRequest? = nil, id: String? = nil) -> ResponseObject {
        let responseId = id ?? "mock-resp-\(UUID().uuidString.prefix(8))"
        
        // Extract text from input
        let inputText: String
        switch request?.input {
        case .string(let text):
            inputText = text
        case .items(let items):
            inputText = items.compactMap { item in
                if case .message(let message) = item {
                    return message.content.compactMap { content in
                        if case .inputText(let textContent) = content {
                            return textContent.text
                        }
                        return nil
                    }.joined(separator: " ")
                }
                return nil
            }.joined(separator: " ")
        case .none:
            inputText = "no input"
        }
        
        let responseText = "Mock response to: \(inputText)"
        
        return ResponseObject(
            id: responseId,
            object: "response",
            createdAt: Date().timeIntervalSince1970,
            model: request?.model ?? "gpt-4o",
            status: .completed,
            output: [
                .message(ResponseOutputMessage(
                    id: "msg-\(UUID().uuidString.prefix(8))",
                    role: "assistant",
                    content: [
                        .outputText(ResponseOutputText(text: responseText))
                    ]
                ))
            ],
            usage: ResponseUsage(
                inputTokens: inputText.count / 4, // Rough token estimate
                outputTokens: responseText.count / 4,
                totalTokens: (inputText.count + responseText.count) / 4,
                inputTokensDetails: nil,
                outputTokensDetails: nil
            ),
            previousResponseId: request?.previousResponseId,
            metadata: request?.metadata,
            incompleteDetails: nil,
            error: nil,
            instructions: request?.instructions,
            temperature: request?.temperature,
            topP: request?.topP,
            maxOutputTokens: request?.maxOutputTokens,
            toolChoice: request?.toolChoice,
            tools: request?.tools,
            parallelToolCalls: request?.parallelToolCalls,
            reasoning: request?.reasoning,
            truncation: request?.truncation,
            text: ResponseTextConfig(format: ResponseTextFormat(type: "text")),
            user: request?.user,
            store: request?.store,
            serviceTier: request?.serviceTier
        )
    }
    
    private func createDefaultStreamChunks() -> [ResponseChunk] {
        let words = ["Hello", "from", "the", "mock", "streaming", "response!"]
        
        return words.enumerated().map { index, word in
            ResponseChunk(
                id: "chunk-\(index)",
                object: "response.chunk",
                createdAt: Date().timeIntervalSince1970,
                model: "gpt-4o",
                status: index == words.count - 1 ? .completed : .inProgress,
                delta: ResponseDelta(
                    output: nil,
                    outputText: word,
                    reasoning: nil,
                    text: word
                ),
                usage: index == words.count - 1 ? ResponseUsage(
                    inputTokens: 5,
                    outputTokens: words.count,
                    totalTokens: 5 + words.count,
                    inputTokensDetails: nil,
                    outputTokensDetails: nil
                ) : nil,
                error: nil
            )
        }
    }
}

// MARK: - Test Data Factories

extension MockOpenAIResponsesProvider {
    
    /// Create a mock response with web search tool usage
    public static func createWebSearchResponse() -> ResponseObject {
        return ResponseObject(
            id: "resp-websearch-123",
            object: "response",
            createdAt: Date().timeIntervalSince1970,
            model: "gpt-4o",
            status: .completed,
            output: [
                .message(ResponseOutputMessage(
                    id: "msg-websearch-123",
                    role: "assistant",
                    content: [
                        .outputText(ResponseOutputText(text: "Based on my web search, here are the latest AI developments..."))
                    ]
                )),
                .webSearchCall(ResponseOutputWebSearchCall(
                    id: "ws-123",
                    query: "Latest AI news",
                    result: "Recent developments in AI include..."
                ))
            ],
            usage: ResponseUsage(inputTokens: 10, outputTokens: 50, totalTokens: 60, inputTokensDetails: nil, outputTokensDetails: nil),
            previousResponseId: nil,
            metadata: nil,
            incompleteDetails: nil,
            error: nil,
            instructions: nil,
            temperature: nil,
            topP: nil,
            maxOutputTokens: nil,
            toolChoice: nil,
            tools: [.webSearchPreview],
            parallelToolCalls: true,
            reasoning: nil,
            truncation: nil,
            text: ResponseTextConfig(format: ResponseTextFormat(type: "text")),
            user: nil,
            store: nil,
            serviceTier: nil
        )
    }
    
    /// Create a mock response with code interpreter usage
    public static func createCodeInterpreterResponse() -> ResponseObject {
        return ResponseObject(
            id: "resp-code-123",
            object: "response",
            createdAt: Date().timeIntervalSince1970,
            model: "gpt-4o",
            status: .completed,
            output: [
                .message(ResponseOutputMessage(
                    id: "msg-code-123",
                    role: "assistant",
                    content: [
                        .outputText(ResponseOutputText(text: "I've executed the code and generated the visualization."))
                    ]
                )),
                .codeInterpreterCall(ResponseOutputCodeInterpreterCall(
                    id: "ci-123",
                    code: "print('Hello, World!')",
                    result: "Hello, World!"
                ))
            ],
            usage: ResponseUsage(inputTokens: 15, outputTokens: 40, totalTokens: 55, inputTokensDetails: nil, outputTokensDetails: nil),
            previousResponseId: nil,
            metadata: nil,
            incompleteDetails: nil,
            error: nil,
            instructions: nil,
            temperature: nil,
            topP: nil,
            maxOutputTokens: nil,
            toolChoice: nil,
            tools: [.codeInterpreter],
            parallelToolCalls: true,
            reasoning: nil,
            truncation: nil,
            text: ResponseTextConfig(format: ResponseTextFormat(type: "text")),
            user: nil,
            store: nil,
            serviceTier: nil
        )
    }
    
    /// Create a mock response with function calling
    public static func createFunctionCallResponse() -> ResponseObject {
        return ResponseObject(
            id: "resp-func-123",
            object: "response",
            createdAt: Date().timeIntervalSince1970,
            model: "gpt-4o",
            status: .completed,
            output: [
                .message(ResponseOutputMessage(
                    id: "msg-func-123",
                    role: "assistant",
                    content: [
                        .outputText(ResponseOutputText(text: "The weather in San Francisco is 18°C and sunny."))
                    ]
                )),
                .functionCall(ResponseOutputFunctionCall(
                    id: "fc-123",
                    name: "get_weather",
                    arguments: "{\"location\": \"San Francisco\"}",
                    callId: "call-123"
                ))
            ],
            usage: ResponseUsage(inputTokens: 20, outputTokens: 30, totalTokens: 50, inputTokensDetails: nil, outputTokensDetails: nil),
            previousResponseId: nil,
            metadata: nil,
            incompleteDetails: nil,
            error: nil,
            instructions: nil,
            temperature: nil,
            topP: nil,
            maxOutputTokens: nil,
            toolChoice: nil,
            tools: nil,
            parallelToolCalls: true,
            reasoning: nil,
            truncation: nil,
            text: ResponseTextConfig(format: ResponseTextFormat(type: "text")),
            user: nil,
            store: nil,
            serviceTier: nil
        )
    }
} 