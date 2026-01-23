//
//  StreamSimulation.swift
//  AISDKTests
//
//  Stream simulation helpers for testing AI streaming behavior
//  Provides factory methods for creating realistic stream event sequences
//

import Foundation
@testable import AISDK

// MARK: - StreamSimulation

/// Factory for creating simulated stream event sequences for testing
///
/// Provides methods to generate realistic `AIStreamEvent` sequences that
/// mimic actual AI provider streaming behavior. Useful for testing:
/// - Stream consumption logic
/// - Event handling
/// - Error recovery
/// - Cancellation behavior
/// - Timeout handling
///
/// Example usage:
/// ```swift
/// // Create a simple text stream
/// let events = StreamSimulation.textStream("Hello, world!")
/// for event in events {
///     print(event)
/// }
///
/// // Create a stream with tool calls
/// let toolEvents = StreamSimulation.toolCallStream(
///     toolName: "get_weather",
///     arguments: #"{"city": "NYC"}"#
/// )
/// ```
public enum StreamSimulation {
    // MARK: - Configuration

    /// Default model identifier for simulated streams
    public static let defaultModel = "gpt-4"

    /// Default provider identifier for simulated streams
    public static let defaultProvider = "openai"

    // MARK: - Text Stream Simulation

    /// Create a simulated text stream from a complete response
    ///
    /// Generates events in the order:
    /// 1. start
    /// 2. textDelta (one per word)
    /// 3. textCompletion
    /// 4. usage
    /// 5. finish
    ///
    /// - Parameters:
    ///   - text: The complete text to stream
    ///   - model: Model identifier (default: gpt-4)
    ///   - provider: Provider identifier (default: openai)
    ///   - chunkByWords: If true, chunks by words; if false, chunks by characters
    /// - Returns: Array of stream events
    public static func textStream(
        _ text: String,
        model: String = defaultModel,
        provider: String = defaultProvider,
        chunkByWords: Bool = true
    ) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []

        // Start event
        events.append(.start(metadata: AIStreamMetadata(
            requestId: UUID().uuidString,
            model: model,
            provider: provider
        )))

        // Text deltas
        if chunkByWords {
            let words = text.split(separator: " ", omittingEmptySubsequences: false)
            for (index, word) in words.enumerated() {
                let delta = index == 0 ? String(word) : " " + String(word)
                events.append(.textDelta(delta))
            }
        } else {
            // Character-by-character for fine-grained testing
            for char in text {
                events.append(.textDelta(String(char)))
            }
        }

        // Text completion
        events.append(.textCompletion(text))

        // Usage (ensure prompt tokens are at least 1)
        let usage = AIUsage(
            promptTokens: max(1, estimateTokens(text) / 2),
            completionTokens: estimateTokens(text)
        )
        events.append(.usage(usage))

        // Finish
        events.append(.finish(finishReason: .stop, usage: usage))

        return events
    }

    // MARK: - Tool Call Stream Simulation

    /// Create a simulated stream with a tool call
    ///
    /// Generates events in the order:
    /// 1. start
    /// 2. toolCallStart
    /// 3. toolCallDelta (chunked arguments)
    /// 4. toolCallFinish
    /// 5. usage
    /// 6. finish
    ///
    /// - Parameters:
    ///   - toolName: The name of the tool being called
    ///   - arguments: JSON string of tool arguments
    ///   - toolId: Optional tool call ID (auto-generated if nil)
    ///   - model: Model identifier
    ///   - provider: Provider identifier
    /// - Returns: Array of stream events
    public static func toolCallStream(
        toolName: String,
        arguments: String,
        toolId: String? = nil,
        model: String = defaultModel,
        provider: String = defaultProvider
    ) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        let id = toolId ?? "call_\(UUID().uuidString.prefix(8))"

        // Start event
        events.append(.start(metadata: AIStreamMetadata(
            requestId: UUID().uuidString,
            model: model,
            provider: provider
        )))

        // Tool call start
        events.append(.toolCallStart(id: id, name: toolName))

        // Tool call deltas (chunk the arguments)
        let chunks = chunkString(arguments, chunkSize: 10)
        for chunk in chunks {
            events.append(.toolCallDelta(id: id, argumentsDelta: chunk))
        }

        // Tool call finish
        events.append(.toolCallFinish(id: id, name: toolName, arguments: arguments))

        // Usage
        let usage = AIUsage(promptTokens: 50, completionTokens: 30)
        events.append(.usage(usage))

        // Finish with tool calls reason
        events.append(.finish(finishReason: .toolCalls, usage: usage))

        return events
    }

    /// Create a simulated stream with multiple tool calls
    ///
    /// - Parameters:
    ///   - toolCalls: Array of (name, arguments) tuples
    ///   - model: Model identifier
    ///   - provider: Provider identifier
    /// - Returns: Array of stream events
    public static func multiToolCallStream(
        toolCalls: [(name: String, arguments: String)],
        model: String = defaultModel,
        provider: String = defaultProvider
    ) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []

        // Start event
        events.append(.start(metadata: AIStreamMetadata(
            requestId: UUID().uuidString,
            model: model,
            provider: provider
        )))

        // Each tool call
        for (name, arguments) in toolCalls {
            let id = "call_\(UUID().uuidString.prefix(8))"
            events.append(.toolCallStart(id: id, name: name))
            events.append(.toolCallFinish(id: id, name: name, arguments: arguments))
        }

        // Usage
        let usage = AIUsage(promptTokens: 50, completionTokens: 30 * toolCalls.count)
        events.append(.usage(usage))

        // Finish
        events.append(.finish(finishReason: .toolCalls, usage: usage))

        return events
    }

    // MARK: - Mixed Stream Simulation

    /// Create a simulated stream with text followed by a tool call
    ///
    /// This simulates models that emit some text before calling a tool.
    ///
    /// - Parameters:
    ///   - text: Initial text to emit
    ///   - toolName: Tool to call
    ///   - arguments: Tool arguments
    ///   - model: Model identifier
    ///   - provider: Provider identifier
    /// - Returns: Array of stream events
    public static func textThenToolStream(
        text: String,
        toolName: String,
        arguments: String,
        model: String = defaultModel,
        provider: String = defaultProvider
    ) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        let toolId = "call_\(UUID().uuidString.prefix(8))"

        // Start event
        events.append(.start(metadata: AIStreamMetadata(
            requestId: UUID().uuidString,
            model: model,
            provider: provider
        )))

        // Text deltas
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in words.enumerated() {
            let delta = index == 0 ? String(word) : " " + String(word)
            events.append(.textDelta(delta))
        }
        events.append(.textCompletion(text))

        // Tool call
        events.append(.toolCallStart(id: toolId, name: toolName))
        events.append(.toolCallFinish(id: toolId, name: toolName, arguments: arguments))

        // Usage
        let usage = AIUsage(
            promptTokens: 50,
            completionTokens: estimateTokens(text) + 30
        )
        events.append(.usage(usage))

        // Finish
        events.append(.finish(finishReason: .toolCalls, usage: usage))

        return events
    }

    // MARK: - Reasoning Stream Simulation

    /// Create a simulated stream with reasoning/thinking (for o1/o3 models)
    ///
    /// Generates events in the order:
    /// 1. start
    /// 2. reasoningStart
    /// 3. reasoningDelta (chunked)
    /// 4. reasoningFinish
    /// 5. textDelta
    /// 6. textCompletion
    /// 7. usage
    /// 8. finish
    ///
    /// - Parameters:
    ///   - reasoning: The reasoning/thinking text
    ///   - response: The final response text
    ///   - model: Model identifier
    ///   - provider: Provider identifier
    /// - Returns: Array of stream events
    public static func reasoningStream(
        reasoning: String,
        response: String,
        model: String = "o1",
        provider: String = defaultProvider
    ) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []

        // Start event
        events.append(.start(metadata: AIStreamMetadata(
            requestId: UUID().uuidString,
            model: model,
            provider: provider
        )))

        // Reasoning phase
        events.append(.reasoningStart)

        let reasoningWords = reasoning.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in reasoningWords.enumerated() {
            let delta = index == 0 ? String(word) : " " + String(word)
            events.append(.reasoningDelta(delta))
        }

        events.append(.reasoningFinish(reasoning))

        // Response phase
        let responseWords = response.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in responseWords.enumerated() {
            let delta = index == 0 ? String(word) : " " + String(word)
            events.append(.textDelta(delta))
        }
        events.append(.textCompletion(response))

        // Usage (reasoning tokens tracked separately for o1/o3 models)
        let reasoningTokenCount = estimateTokens(reasoning)
        let responseTokenCount = estimateTokens(response)
        let usage = AIUsage(
            promptTokens: 100,
            completionTokens: reasoningTokenCount + responseTokenCount,
            reasoningTokens: reasoningTokenCount
        )
        events.append(.usage(usage))

        // Finish
        events.append(.finish(finishReason: .stop, usage: usage))

        return events
    }

    // MARK: - Error Stream Simulation

    /// Create a simulated stream that fails with an error
    ///
    /// - Parameters:
    ///   - error: The error to emit
    ///   - afterEvents: Number of successful events before the error
    ///   - model: Model identifier
    ///   - provider: Provider identifier
    /// - Returns: Array of stream events ending with error
    public static func errorStream(
        error: Error,
        afterEvents: Int = 0,
        model: String = defaultModel,
        provider: String = defaultProvider
    ) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []

        // Start event
        events.append(.start(metadata: AIStreamMetadata(
            requestId: UUID().uuidString,
            model: model,
            provider: provider
        )))

        // Emit some successful events first if requested
        for i in 0..<afterEvents {
            events.append(.textDelta("word\(i) "))
        }

        // Error event
        events.append(.error(error))

        return events
    }

    /// Create a simulated stream that fails mid-stream
    ///
    /// Simulates a partial response followed by an error, useful for
    /// testing error recovery and partial content handling.
    ///
    /// - Parameters:
    ///   - partialText: Text to emit before the error
    ///   - error: The error that occurs
    ///   - model: Model identifier
    ///   - provider: Provider identifier
    /// - Returns: Array of stream events
    public static func partialThenErrorStream(
        partialText: String,
        error: Error,
        model: String = defaultModel,
        provider: String = defaultProvider
    ) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []

        // Start event
        events.append(.start(metadata: AIStreamMetadata(
            requestId: UUID().uuidString,
            model: model,
            provider: provider
        )))

        // Partial text
        let words = partialText.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in words.enumerated() {
            let delta = index == 0 ? String(word) : " " + String(word)
            events.append(.textDelta(delta))
        }

        // Error (no textCompletion since it's partial)
        events.append(.error(error))

        return events
    }

    // MARK: - Multi-Step Stream Simulation

    /// Create a simulated multi-step stream
    ///
    /// Simulates an agent executing multiple steps.
    ///
    /// - Parameters:
    ///   - steps: Array of step results
    ///   - model: Model identifier
    ///   - provider: Provider identifier
    /// - Returns: Array of stream events
    public static func multiStepStream(
        steps: [AIStepResult],
        model: String = defaultModel,
        provider: String = defaultProvider
    ) -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []

        // Start event
        events.append(.start(metadata: AIStreamMetadata(
            requestId: UUID().uuidString,
            model: model,
            provider: provider
        )))

        // Each step - use result.stepIndex for consistency
        for result in steps {
            events.append(.stepStart(stepIndex: result.stepIndex))

            // Emit text for the step if present
            if !result.text.isEmpty {
                let words = result.text.split(separator: " ", omittingEmptySubsequences: false)
                for (wordIndex, word) in words.enumerated() {
                    let delta = wordIndex == 0 ? String(word) : " " + String(word)
                    events.append(.textDelta(delta))
                }
            }

            events.append(.stepFinish(stepIndex: result.stepIndex, result: result))
        }

        // Final usage (sum of all steps, preserving optional fields)
        let totalUsage = steps.map(\.usage).reduce(.zero, +)
        events.append(.usage(totalUsage))

        // Finish
        let finalReason = steps.last?.finishReason ?? .stop
        events.append(.finish(finishReason: finalReason, usage: totalUsage))

        return events
    }

    // MARK: - Heartbeat Stream Simulation

    /// Create a simulated stream with heartbeats
    ///
    /// Simulates long-running operations that emit heartbeats for keepalive.
    ///
    /// - Parameters:
    ///   - text: The response text
    ///   - heartbeatCount: Number of heartbeats to emit during the stream (must be >= 0)
    ///   - model: Model identifier
    ///   - provider: Provider identifier
    /// - Returns: Array of stream events with exactly `heartbeatCount` heartbeats interspersed
    public static func heartbeatStream(
        text: String,
        heartbeatCount: Int = 3,
        model: String = defaultModel,
        provider: String = defaultProvider
    ) -> [AIStreamEvent] {
        // Guard against negative heartbeat counts
        let safeHeartbeatCount = max(0, heartbeatCount)
        var events: [AIStreamEvent] = []

        // Start event
        events.append(.start(metadata: AIStreamMetadata(
            requestId: UUID().uuidString,
            model: model,
            provider: provider
        )))

        // Split text into chunks and intersperse heartbeats
        let words = text.split(separator: " ", omittingEmptySubsequences: false)

        // Track heartbeats emitted to guarantee exactly safeHeartbeatCount
        var heartbeatsEmitted = 0

        // Calculate insertion points - use array to allow multiple heartbeats at same point if needed
        var heartbeatCountPerIndex: [Int: Int] = [:]
        if safeHeartbeatCount > 0 && words.count > 0 {
            // Distribute heartbeats evenly across valid insertion points (after each word except last)
            let validInsertPoints = max(1, words.count - 1)
            for i in 0..<safeHeartbeatCount {
                let insertAfter = i % validInsertPoints
                heartbeatCountPerIndex[insertAfter, default: 0] += 1
            }
        }

        for (index, word) in words.enumerated() {
            let delta = index == 0 ? String(word) : " " + String(word)
            events.append(.textDelta(delta))

            // Insert heartbeat(s) at computed indices
            if let count = heartbeatCountPerIndex[index], index < words.count - 1 {
                for _ in 0..<count {
                    events.append(.heartbeat(timestamp: Date()))
                    heartbeatsEmitted += 1
                }
            }
        }

        // If we still need more heartbeats (edge case: single word), append them
        while heartbeatsEmitted < safeHeartbeatCount {
            events.append(.heartbeat(timestamp: Date()))
            heartbeatsEmitted += 1
        }

        // Text completion
        events.append(.textCompletion(text))

        // Usage
        let promptTokens = max(1, estimateTokens(text) / 2)
        let usage = AIUsage(
            promptTokens: promptTokens,
            completionTokens: estimateTokens(text)
        )
        events.append(.usage(usage))

        // Finish
        events.append(.finish(finishReason: .stop, usage: usage))

        return events
    }

    // MARK: - Async Stream Creation

    /// Convert an event array to an AsyncThrowingStream
    ///
    /// Creates a stream that emits events with optional delays between them.
    /// Delays are applied only between events, not after the last event.
    ///
    /// - Parameters:
    ///   - events: The events to stream
    ///   - delay: Optional delay between events (not after last event)
    /// - Returns: An AsyncThrowingStream that emits the events
    public static func asStream(
        _ events: [AIStreamEvent],
        delay: Duration = .zero
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        SafeAsyncStream.make { continuation in
            for (index, event) in events.enumerated() {
                guard !continuation.isTerminated else { break }

                // Check if this is an error event - if so, emit then throw
                if case .error(let error) = event {
                    continuation.yield(event)
                    continuation.finish(throwing: error)
                    return
                }

                continuation.yield(event)

                // Apply delay only between events (not after the last one)
                let isLastEvent = index == events.count - 1
                if delay > .zero && !isLastEvent {
                    try await Task.sleep(for: delay)
                }
            }
            continuation.finish()
        }
    }

    /// Create an AsyncThrowingStream directly from text
    ///
    /// Convenience method combining textStream and asStream.
    ///
    /// - Parameters:
    ///   - text: The text to stream
    ///   - delay: Optional delay between events
    ///   - model: Model identifier
    ///   - provider: Provider identifier
    /// - Returns: An AsyncThrowingStream of text events
    public static func simulateTextStream(
        _ text: String,
        delay: Duration = .zero,
        model: String = defaultModel,
        provider: String = defaultProvider
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        asStream(textStream(text, model: model, provider: provider), delay: delay)
    }

    /// Create an AsyncThrowingStream for a tool call
    ///
    /// - Parameters:
    ///   - toolName: The tool name
    ///   - arguments: Tool arguments
    ///   - delay: Optional delay between events
    /// - Returns: An AsyncThrowingStream of tool call events
    public static func simulateToolStream(
        toolName: String,
        arguments: String,
        delay: Duration = .zero
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        asStream(toolCallStream(toolName: toolName, arguments: arguments), delay: delay)
    }

    // MARK: - Private Helpers

    /// Estimate token count from text (rough approximation)
    private static func estimateTokens(_ text: String) -> Int {
        // Rough estimate: ~4 characters per token on average
        max(1, text.count / 4)
    }

    /// Chunk a string into smaller pieces
    private static func chunkString(_ string: String, chunkSize: Int) -> [String] {
        guard chunkSize > 0 else { return [string] }

        var chunks: [String] = []
        var index = string.startIndex

        while index < string.endIndex {
            let endIndex = string.index(index, offsetBy: chunkSize, limitedBy: string.endIndex) ?? string.endIndex
            chunks.append(String(string[index..<endIndex]))
            index = endIndex
        }

        // Return empty array for empty input to avoid spurious empty deltas
        return chunks
    }
}

// MARK: - StreamSimulation Extensions for Testing

extension StreamSimulation {
    /// Create events that match a specific pattern for assertion testing
    ///
    /// - Parameter pattern: Pattern description (e.g., "start,text,finish")
    /// - Returns: Array of events matching the pattern
    public static func eventsForPattern(_ pattern: String) -> [AIStreamEvent] {
        let components = pattern.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var events: [AIStreamEvent] = []

        for component in components {
            switch component.lowercased() {
            case "start":
                events.append(.start(metadata: AIStreamMetadata(
                    requestId: "test",
                    model: defaultModel,
                    provider: defaultProvider
                )))
            case "text":
                events.append(.textDelta("test"))
                events.append(.textCompletion("test"))
            case "tool":
                events.append(.toolCallStart(id: "test", name: "test_tool"))
                events.append(.toolCallFinish(id: "test", name: "test_tool", arguments: "{}"))
            case "reasoning":
                events.append(.reasoningStart)
                events.append(.reasoningDelta("thinking"))
                events.append(.reasoningFinish("thinking"))
            case "usage":
                events.append(.usage(AIUsage(promptTokens: 10, completionTokens: 20)))
            case "finish":
                events.append(.finish(
                    finishReason: .stop,
                    usage: AIUsage(promptTokens: 10, completionTokens: 20)
                ))
            case "error":
                events.append(.error(AISDKError.custom("test error")))
            case "heartbeat":
                events.append(.heartbeat(timestamp: Date()))
            default:
                // Fail fast on unknown pattern components to catch typos
                assertionFailure("Unknown pattern component: '\(component)'. Valid components: start, text, tool, reasoning, usage, finish, error, heartbeat")
            }
        }

        return events
    }
}
