//
//  MockAILanguageModel.swift
//  AISDKTests
//
//  Mock implementation of AILanguageModel for testing
//  Supports configurable responses, tool calls, streaming, and error injection
//

import Foundation
@testable import AISDK

/// Mock implementation of AILanguageModel for comprehensive testing
///
/// Provides factory methods for common test scenarios:
/// - `withResponse(_:)` - Fixed text response
/// - `withToolCall(_:arguments:)` - Tool call response
/// - `withSlowResponse(delay:response:)` - Delayed response for timeout testing
/// - `failing(with:)` - Error injection
/// - `withStreamEvents(_:)` - Custom stream events
///
/// Example usage:
/// ```swift
/// let mock = MockAILanguageModel.withResponse("Hello, world!")
/// let result = try await mock.generateText(request: AITextRequest(messages: [.user("Hi")]))
/// XCTAssertEqual(result.text, "Hello, world!")
/// ```
public final class MockAILanguageModel: AILanguageModel, @unchecked Sendable {
    // MARK: - AILanguageModel Protocol

    public let provider: String
    public let modelId: String
    public let capabilities: LLMCapabilities

    // MARK: - Configuration

    /// The response text to return for generateText calls
    public var responseText: String

    /// Tool calls to include in responses
    public var toolCalls: [AIToolCallResult]

    /// Stream events to emit for streaming calls
    public var streamEvents: [AIStreamEvent]

    /// Usage stats to return
    public var usage: AIUsage

    /// Finish reason to return
    public var finishReason: AIFinishReason

    /// Delay before responding (for timeout testing)
    public var delay: Duration

    /// Error to throw instead of returning a response
    public var errorToThrow: Error?

    // MARK: - Tracking

    /// Number of requests received
    public private(set) var requestCount: Int = 0

    /// The last text request received
    public private(set) var lastTextRequest: AITextRequest?

    /// The last object request type name received
    public private(set) var lastObjectRequestType: String?

    /// Lock for thread-safe state access
    private let lock = NSLock()

    // MARK: - Initialization

    /// Create a mock with default configuration
    ///
    /// - Parameters:
    ///   - providerId: Provider identifier (default: "mock")
    ///   - modelId: Model identifier (default: "mock-model")
    ///   - capabilities: Model capabilities (default: text + tools + streaming)
    public init(
        providerId: String = "mock",
        modelId: String = "mock-model",
        capabilities: LLMCapabilities = [.text, .tools, .streaming, .structuredOutputs]
    ) {
        self.provider = providerId
        self.modelId = modelId
        self.capabilities = capabilities
        self.responseText = "Mock response"
        self.toolCalls = []
        self.streamEvents = []
        self.usage = AIUsage(promptTokens: 10, completionTokens: 20)
        self.finishReason = .stop
        self.delay = .zero
        self.errorToThrow = nil
    }

    // MARK: - Private State Update

    private func recordTextRequest(_ request: AITextRequest) {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        lastTextRequest = request
    }

    private func recordObjectRequest<T>(_ type: T.Type) {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        lastObjectRequestType = String(describing: type)
    }

    // MARK: - AILanguageModel Protocol Methods

    public func generateText(request: AITextRequest) async throws -> AITextResult {
        recordTextRequest(request)

        // Apply delay if configured
        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        // Check for cancellation after delay
        try Task.checkCancellation()

        // Throw error if configured
        if let error = errorToThrow {
            throw error
        }

        return AITextResult(
            text: responseText,
            toolCalls: toolCalls,
            usage: usage,
            finishReason: finishReason,
            requestId: "mock-request-\(UUID().uuidString.prefix(8))",
            model: request.model ?? modelId,
            provider: provider
        )
    }

    public func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        recordTextRequest(request)

        // If error is configured, return a failing stream
        if let error = errorToThrow {
            return SafeAsyncStream.fail(with: error)
        }

        // Use custom stream events if provided, otherwise generate from responseText
        let events: [AIStreamEvent]
        if !streamEvents.isEmpty {
            events = streamEvents
        } else {
            events = generateStreamEvents(from: responseText, toolCalls: toolCalls, usage: usage, finishReason: finishReason)
        }

        let capturedDelay = delay

        return SafeAsyncStream.make { continuation in
            // Apply delay if configured
            if capturedDelay > .zero {
                try await Task.sleep(for: capturedDelay)
            }

            // Emit stream start
            continuation.yield(.start(metadata: AIStreamMetadata(
                requestId: "mock-stream-\(UUID().uuidString.prefix(8))",
                model: request.model ?? self.modelId,
                provider: self.provider
            )))

            // Emit events
            for event in events {
                guard !continuation.isTerminated else { break }
                continuation.yield(event)
                // Small delay between events to simulate streaming
                try await Task.sleep(for: .milliseconds(1))
            }

            continuation.finish()
        }
    }

    public func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T> {
        recordObjectRequest(T.self)

        // Apply delay if configured
        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        // Check for cancellation after delay
        try Task.checkCancellation()

        // Throw error if configured
        if let error = errorToThrow {
            throw error
        }

        // Parse responseText as JSON
        guard let data = responseText.data(using: .utf8) else {
            throw AISDKError.parsingError("Mock response is not valid UTF-8")
        }

        let object = try JSONDecoder().decode(T.self, from: data)

        return AIObjectResult(
            object: object,
            usage: usage,
            finishReason: finishReason,
            requestId: "mock-object-\(UUID().uuidString.prefix(8))",
            model: request.model ?? modelId,
            provider: provider,
            rawJSON: responseText
        )
    }

    public func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
        recordObjectRequest(T.self)

        // If error is configured, return a failing stream
        if let error = errorToThrow {
            return SafeAsyncStream.fail(with: error)
        }

        let capturedDelay = delay
        let capturedResponse = responseText
        let capturedUsage = usage
        let capturedFinishReason = finishReason

        return SafeAsyncStream.make { continuation in
            // Apply delay if configured
            if capturedDelay > .zero {
                try await Task.sleep(for: capturedDelay)
            }

            // Emit stream start
            continuation.yield(.start(metadata: AIStreamMetadata(
                requestId: "mock-object-stream-\(UUID().uuidString.prefix(8))",
                model: request.model ?? self.modelId,
                provider: self.provider
            )))

            // Emit the JSON as objectDelta events (chunk by chunk)
            if let data = capturedResponse.data(using: .utf8) {
                let chunkSize = max(1, data.count / 5)
                var offset = 0
                while offset < data.count {
                    guard !continuation.isTerminated else { break }
                    let end = min(offset + chunkSize, data.count)
                    let chunk = data.subdata(in: offset..<end)
                    continuation.yield(.objectDelta(chunk))
                    offset = end
                    try await Task.sleep(for: .milliseconds(1))
                }
            }

            // Emit usage and finish
            continuation.yield(.usage(capturedUsage))
            continuation.yield(.finish(finishReason: capturedFinishReason, usage: capturedUsage))
            continuation.finish()
        }
    }

    // MARK: - Private Helpers

    private func generateStreamEvents(
        from text: String,
        toolCalls: [AIToolCallResult],
        usage: AIUsage,
        finishReason: AIFinishReason
    ) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []

        // Split text into words for streaming simulation
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in words.enumerated() {
            let delta = index == 0 ? String(word) : " " + String(word)
            events.append(.textDelta(delta))
        }

        // Add text completion
        events.append(.textCompletion(text))

        // Add tool calls if present
        for toolCall in toolCalls {
            events.append(.toolCallStart(id: toolCall.id, name: toolCall.name))
            events.append(.toolCallFinish(id: toolCall.id, name: toolCall.name, arguments: toolCall.arguments))
        }

        // Add usage and finish
        events.append(.usage(usage))
        events.append(.finish(finishReason: finishReason, usage: usage))

        return events
    }

    // MARK: - Reset

    /// Reset all tracking state
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        requestCount = 0
        lastTextRequest = nil
        lastObjectRequestType = nil
    }
}

// MARK: - Factory Methods

extension MockAILanguageModel {
    /// Create a mock that returns a fixed text response
    ///
    /// - Parameter text: The text to return
    /// - Returns: A configured MockAILanguageModel
    public static func withResponse(_ text: String) -> MockAILanguageModel {
        let mock = MockAILanguageModel()
        mock.responseText = text
        return mock
    }

    /// Create a mock that returns a tool call
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool to call
    ///   - arguments: JSON arguments for the tool
    /// - Returns: A configured MockAILanguageModel
    public static func withToolCall(_ toolName: String, arguments: String) -> MockAILanguageModel {
        let mock = MockAILanguageModel()
        mock.responseText = ""
        mock.toolCalls = [
            AIToolCallResult(
                id: "mock-tool-call-\(UUID().uuidString.prefix(8))",
                name: toolName,
                arguments: arguments
            )
        ]
        mock.finishReason = .toolCalls
        return mock
    }

    /// Create a mock that returns multiple tool calls
    ///
    /// - Parameter toolCalls: Array of tuples (name, arguments) for each tool call
    /// - Returns: A configured MockAILanguageModel
    public static func withToolCalls(_ toolCalls: [(name: String, arguments: String)]) -> MockAILanguageModel {
        let mock = MockAILanguageModel()
        mock.responseText = ""
        mock.toolCalls = toolCalls.map { name, arguments in
            AIToolCallResult(
                id: "mock-tool-call-\(UUID().uuidString.prefix(8))",
                name: name,
                arguments: arguments
            )
        }
        mock.finishReason = .toolCalls
        return mock
    }

    /// Create a mock with a delayed response
    ///
    /// - Parameters:
    ///   - delay: The delay before responding
    ///   - response: The response text (default: "Mock response")
    /// - Returns: A configured MockAILanguageModel
    public static func withSlowResponse(delay: Duration, response: String = "Mock response") -> MockAILanguageModel {
        let mock = MockAILanguageModel()
        mock.responseText = response
        mock.delay = delay
        return mock
    }

    /// Create a mock that fails with an error
    ///
    /// - Parameter error: The error to throw
    /// - Returns: A configured MockAILanguageModel
    public static func failing(with error: Error) -> MockAILanguageModel {
        let mock = MockAILanguageModel()
        mock.errorToThrow = error
        return mock
    }

    /// Create a mock that fails with an AISDKError
    ///
    /// - Parameter error: The AISDKError to throw
    /// - Returns: A configured MockAILanguageModel
    public static func failing(with error: AISDKError) -> MockAILanguageModel {
        let mock = MockAILanguageModel()
        mock.errorToThrow = error
        return mock
    }

    /// Create a mock with custom stream events
    ///
    /// - Parameter events: The stream events to emit
    /// - Returns: A configured MockAILanguageModel
    public static func withStreamEvents(_ events: [AIStreamEvent]) -> MockAILanguageModel {
        let mock = MockAILanguageModel()
        mock.streamEvents = events
        return mock
    }

    /// Create a mock that returns structured JSON output
    ///
    /// - Parameters:
    ///   - object: The Codable object to return
    ///   - encoder: JSON encoder (default: standard encoder)
    /// - Returns: A configured MockAILanguageModel
    public static func withObject<T: Codable>(_ object: T, encoder: JSONEncoder = JSONEncoder()) throws -> MockAILanguageModel {
        let mock = MockAILanguageModel()
        let data = try encoder.encode(object)
        mock.responseText = String(data: data, encoding: .utf8) ?? "{}"
        return mock
    }

    /// Create a mock with a specific provider ID
    ///
    /// - Parameter providerId: The provider identifier
    /// - Returns: A configured MockAILanguageModel
    public static func withProvider(_ providerId: String) -> MockAILanguageModel {
        MockAILanguageModel(providerId: providerId)
    }
}

// MARK: - Sequence Mocking

extension MockAILanguageModel {
    /// Create a mock that returns different responses for sequential calls
    ///
    /// - Parameter responses: Array of responses, one for each call
    /// - Returns: A configured MockAILanguageModel
    public static func withSequence(_ responses: [String]) -> SequentialMockAILanguageModel {
        SequentialMockAILanguageModel(responses: responses)
    }
}

/// Mock that returns different responses for sequential calls
public final class SequentialMockAILanguageModel: AILanguageModel, @unchecked Sendable {
    public let provider: String = "mock-sequential"
    public let modelId: String = "mock-sequential-model"
    public let capabilities: LLMCapabilities = [.text, .tools, .streaming]

    private var responses: [String]
    private var currentIndex: Int = 0
    private let lock = NSLock()

    public private(set) var requestCount: Int = 0

    init(responses: [String]) {
        self.responses = responses
    }

    private func nextResponse() -> String {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        let response = responses[min(currentIndex, responses.count - 1)]
        currentIndex += 1
        return response
    }

    public func generateText(request: AITextRequest) async throws -> AITextResult {
        AITextResult(
            text: nextResponse(),
            usage: AIUsage(promptTokens: 10, completionTokens: 20),
            finishReason: .stop,
            model: modelId,
            provider: provider
        )
    }

    public func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let response = nextResponse()
        return SafeAsyncStream.from([
            .start(metadata: AIStreamMetadata(model: modelId, provider: provider)),
            .textDelta(response),
            .textCompletion(response),
            .finish(finishReason: .stop, usage: AIUsage(promptTokens: 10, completionTokens: 20))
        ])
    }

    public func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T> {
        let response = nextResponse()
        guard let data = response.data(using: .utf8) else {
            throw AISDKError.parsingError("Response is not valid UTF-8")
        }
        let object = try JSONDecoder().decode(T.self, from: data)
        return AIObjectResult(
            object: object,
            usage: AIUsage(promptTokens: 10, completionTokens: 20),
            finishReason: .stop,
            model: modelId,
            provider: provider,
            rawJSON: response
        )
    }

    public func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let response = nextResponse()
        let usage = AIUsage(promptTokens: 10, completionTokens: 20)
        return SafeAsyncStream.from([
            .start(metadata: AIStreamMetadata(model: modelId, provider: provider)),
            .objectDelta(response.data(using: .utf8) ?? Data()),
            .usage(usage),
            .finish(finishReason: .stop, usage: usage)
        ])
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        currentIndex = 0
        requestCount = 0
    }
}
