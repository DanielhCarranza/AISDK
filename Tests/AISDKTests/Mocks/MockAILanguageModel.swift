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

    // MARK: - Configuration (Thread-Safe)
    // All configuration properties are private and accessed via thread-safe setters/getters

    private var _responseText: String
    private var _toolCalls: [AIToolCallResult]
    private var _streamEvents: [AIStreamEvent]
    private var _usage: AIUsage
    private var _finishReason: AIFinishReason
    private var _delay: Duration
    private var _interEventDelay: Duration
    private var _autoEmitStart: Bool
    private var _errorToThrow: Error?

    /// The response text to return for generateText calls
    public var responseText: String {
        get { lock.lock(); defer { lock.unlock() }; return _responseText }
        set { lock.lock(); defer { lock.unlock() }; _responseText = newValue }
    }

    /// Tool calls to include in responses
    public var toolCalls: [AIToolCallResult] {
        get { lock.lock(); defer { lock.unlock() }; return _toolCalls }
        set { lock.lock(); defer { lock.unlock() }; _toolCalls = newValue }
    }

    /// Stream events to emit for streaming calls
    public var streamEvents: [AIStreamEvent] {
        get { lock.lock(); defer { lock.unlock() }; return _streamEvents }
        set { lock.lock(); defer { lock.unlock() }; _streamEvents = newValue }
    }

    /// Usage stats to return
    public var usage: AIUsage {
        get { lock.lock(); defer { lock.unlock() }; return _usage }
        set { lock.lock(); defer { lock.unlock() }; _usage = newValue }
    }

    /// Finish reason to return
    public var finishReason: AIFinishReason {
        get { lock.lock(); defer { lock.unlock() }; return _finishReason }
        set { lock.lock(); defer { lock.unlock() }; _finishReason = newValue }
    }

    /// Delay before responding (for timeout testing)
    public var delay: Duration {
        get { lock.lock(); defer { lock.unlock() }; return _delay }
        set { lock.lock(); defer { lock.unlock() }; _delay = newValue }
    }

    /// Delay between stream events (default: zero for fast tests)
    public var interEventDelay: Duration {
        get { lock.lock(); defer { lock.unlock() }; return _interEventDelay }
        set { lock.lock(); defer { lock.unlock() }; _interEventDelay = newValue }
    }

    /// Whether to auto-emit start event in streams (default: true)
    /// Set to false when using custom streamEvents that include .start
    public var autoEmitStart: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _autoEmitStart }
        set { lock.lock(); defer { lock.unlock() }; _autoEmitStart = newValue }
    }

    /// Error to throw instead of returning a response
    public var errorToThrow: Error? {
        get { lock.lock(); defer { lock.unlock() }; return _errorToThrow }
        set { lock.lock(); defer { lock.unlock() }; _errorToThrow = newValue }
    }

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
        self._responseText = "Mock response"
        self._toolCalls = []
        self._streamEvents = []
        self._usage = AIUsage(promptTokens: 10, completionTokens: 20)
        self._finishReason = .stop
        self._delay = .zero
        self._interEventDelay = .zero
        self._autoEmitStart = true
        self._errorToThrow = nil
    }

    // MARK: - Configuration Snapshot

    /// Configuration snapshot for thread-safe reading
    private struct ConfigSnapshot {
        let responseText: String
        let toolCalls: [AIToolCallResult]
        let streamEvents: [AIStreamEvent]
        let usage: AIUsage
        let finishReason: AIFinishReason
        let delay: Duration
        let interEventDelay: Duration
        let autoEmitStart: Bool
        let errorToThrow: Error?
    }

    /// Atomically snapshot the current configuration
    private func snapshotConfig() -> ConfigSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return ConfigSnapshot(
            responseText: _responseText,
            toolCalls: _toolCalls,
            streamEvents: _streamEvents,
            usage: _usage,
            finishReason: _finishReason,
            delay: _delay,
            interEventDelay: _interEventDelay,
            autoEmitStart: _autoEmitStart,
            errorToThrow: _errorToThrow
        )
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

        // Snapshot config atomically
        let config = snapshotConfig()

        // Apply delay if configured
        if config.delay > .zero {
            try await Task.sleep(for: config.delay)
        }

        // Check for cancellation after delay
        try Task.checkCancellation()

        // Throw error if configured
        if let error = config.errorToThrow {
            throw error
        }

        return AITextResult(
            text: config.responseText,
            toolCalls: config.toolCalls,
            usage: config.usage,
            finishReason: config.finishReason,
            requestId: "mock-request-\(UUID().uuidString.prefix(8))",
            model: request.model ?? modelId,
            provider: provider
        )
    }

    public func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        recordTextRequest(request)

        // Snapshot config atomically
        let config = snapshotConfig()

        // If error is configured, emit error event then fail
        if let error = config.errorToThrow {
            return SafeAsyncStream.makeSync { continuation in
                continuation.yield(.error(error))
                continuation.finish(throwing: error)
            }
        }

        // Use custom stream events if provided, otherwise generate from responseText
        let events: [AIStreamEvent]
        if !config.streamEvents.isEmpty {
            events = config.streamEvents
        } else {
            events = generateStreamEvents(from: config.responseText, toolCalls: config.toolCalls, usage: config.usage, finishReason: config.finishReason)
        }

        return SafeAsyncStream.make { continuation in
            // Apply delay if configured
            if config.delay > .zero {
                try await Task.sleep(for: config.delay)
            }

            // Emit stream start (unless disabled or custom events already include it)
            let hasStartEvent = events.contains { if case .start = $0 { return true }; return false }
            if config.autoEmitStart && !hasStartEvent {
                continuation.yield(.start(metadata: AIStreamMetadata(
                    requestId: "mock-stream-\(UUID().uuidString.prefix(8))",
                    model: request.model ?? self.modelId,
                    provider: self.provider
                )))
            }

            // Emit events
            for event in events {
                guard !continuation.isTerminated else { break }
                continuation.yield(event)
                // Apply inter-event delay if configured
                if config.interEventDelay > .zero {
                    try await Task.sleep(for: config.interEventDelay)
                }
            }

            continuation.finish()
        }
    }

    public func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T> {
        recordObjectRequest(T.self)

        // Snapshot config atomically
        let config = snapshotConfig()

        // Apply delay if configured
        if config.delay > .zero {
            try await Task.sleep(for: config.delay)
        }

        // Check for cancellation after delay
        try Task.checkCancellation()

        // Throw error if configured
        if let error = config.errorToThrow {
            throw error
        }

        // Parse responseText as JSON
        guard let data = config.responseText.data(using: .utf8) else {
            throw AISDKError.parsingError("Mock response is not valid UTF-8")
        }

        let object = try JSONDecoder().decode(T.self, from: data)

        return AIObjectResult(
            object: object,
            usage: config.usage,
            finishReason: config.finishReason,
            requestId: "mock-object-\(UUID().uuidString.prefix(8))",
            model: request.model ?? modelId,
            provider: provider,
            rawJSON: config.responseText
        )
    }

    public func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
        recordObjectRequest(T.self)

        // Snapshot config atomically
        let config = snapshotConfig()

        // If error is configured, emit error event then fail
        if let error = config.errorToThrow {
            return SafeAsyncStream.makeSync { continuation in
                continuation.yield(.error(error))
                continuation.finish(throwing: error)
            }
        }

        return SafeAsyncStream.make { continuation in
            // Apply delay if configured
            if config.delay > .zero {
                try await Task.sleep(for: config.delay)
            }

            // Emit stream start
            continuation.yield(.start(metadata: AIStreamMetadata(
                requestId: "mock-object-stream-\(UUID().uuidString.prefix(8))",
                model: request.model ?? self.modelId,
                provider: self.provider
            )))

            // Emit the JSON as objectDelta events (chunk by chunk)
            if let data = config.responseText.data(using: .utf8) {
                let chunkSize = max(1, data.count / 5)
                var offset = 0
                while offset < data.count {
                    guard !continuation.isTerminated else { break }
                    let end = min(offset + chunkSize, data.count)
                    let chunk = data.subdata(in: offset..<end)
                    continuation.yield(.objectDelta(chunk))
                    offset = end
                    // Apply inter-event delay if configured
                    if config.interEventDelay > .zero {
                        try await Task.sleep(for: config.interEventDelay)
                    }
                }
            }

            // Emit usage and finish
            continuation.yield(.usage(config.usage))
            continuation.yield(.finish(finishReason: config.finishReason, usage: config.usage))
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

        // Only emit text events if there's actual text content
        if !text.isEmpty {
            // Split text into words for streaming simulation
            let words = text.split(separator: " ", omittingEmptySubsequences: false)
            for (index, word) in words.enumerated() {
                let delta = index == 0 ? String(word) : " " + String(word)
                events.append(.textDelta(delta))
            }

            // Add text completion
            events.append(.textCompletion(text))
        }

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
///
/// Note: If initialized with an empty array, methods will return an empty string
/// for text operations. This enables testing edge cases.
public final class SequentialMockAILanguageModel: AILanguageModel, @unchecked Sendable {
    public let provider: String = "mock-sequential"
    public let modelId: String = "mock-sequential-model"
    public let capabilities: LLMCapabilities = [.text, .tools, .streaming, .structuredOutputs]

    private var responses: [String]
    private var currentIndex: Int = 0
    private let lock = NSLock()

    public private(set) var requestCount: Int = 0

    /// Creates a sequential mock with the given responses
    ///
    /// - Parameter responses: Array of responses to return sequentially.
    ///   If empty, text methods return an empty string.
    init(responses: [String]) {
        self.responses = responses
    }

    private func nextResponse() -> String {
        lock.lock()
        defer { lock.unlock() }
        requestCount += 1
        // Handle empty responses array gracefully
        guard !responses.isEmpty else {
            return ""
        }
        let response = responses[min(currentIndex, responses.count - 1)]
        currentIndex += 1
        return response
    }

    public func generateText(request: AITextRequest) async throws -> AITextResult {
        let usage = AIUsage(promptTokens: 10, completionTokens: 20)
        return AITextResult(
            text: nextResponse(),
            usage: usage,
            finishReason: .stop,
            model: request.model ?? modelId,
            provider: provider
        )
    }

    public func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let response = nextResponse()
        let usage = AIUsage(promptTokens: 10, completionTokens: 20)
        let effectiveModel = request.model ?? modelId
        return SafeAsyncStream.from([
            .start(metadata: AIStreamMetadata(model: effectiveModel, provider: provider)),
            .textDelta(response),
            .textCompletion(response),
            .usage(usage),
            .finish(finishReason: .stop, usage: usage)
        ])
    }

    public func generateObject<T: Codable & Sendable>(request: AIObjectRequest<T>) async throws -> AIObjectResult<T> {
        let response = nextResponse()
        guard let data = response.data(using: .utf8) else {
            throw AISDKError.parsingError("Response is not valid UTF-8")
        }
        let object = try JSONDecoder().decode(T.self, from: data)
        let usage = AIUsage(promptTokens: 10, completionTokens: 20)
        return AIObjectResult(
            object: object,
            usage: usage,
            finishReason: .stop,
            model: request.model ?? modelId,
            provider: provider,
            rawJSON: response
        )
    }

    public func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
        let response = nextResponse()
        let usage = AIUsage(promptTokens: 10, completionTokens: 20)
        let effectiveModel = request.model ?? modelId
        return SafeAsyncStream.from([
            .start(metadata: AIStreamMetadata(model: effectiveModel, provider: provider)),
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
