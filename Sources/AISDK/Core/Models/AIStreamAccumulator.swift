//
//  AIStreamAccumulator.swift
//  AISDK
//
//  Accumulates AIStreamEvent into structured AIMessagePart array.
//  Modeled after Vercel AI SDK's useChat hook state management.
//

import Foundation

// MARK: - AIStreamAccumulator

/// Accumulates `AIStreamEvent` into an ordered `[AIMessagePart]` array
/// for structured rendering of agent activity.
///
/// Feed events from `Agent.streamExecute()` and the accumulator builds
/// a parts array suitable for SwiftUI rendering with thinking, tool calls,
/// and text in interleaved order.
///
/// ## Usage
/// ```swift
/// let accumulator = AIStreamAccumulator()
/// for try await event in agent.streamExecute(messages: messages) {
///     await accumulator.process(event)
/// }
/// // Use accumulator.parts for rendering
/// // Use accumulator.summary for collapsed view
/// ```
@MainActor @Observable
public final class AIStreamAccumulator: @unchecked Sendable {
    /// Ordered message parts, updated incrementally as events arrive
    public private(set) var parts: [AIMessagePart] = []

    /// Whether the stream has finished
    public private(set) var isComplete: Bool = false

    /// Current step index in the agent loop
    public private(set) var currentStepIndex: Int = 0

    // Internal tracking
    private var thinkingStartTime: ContinuousClock.Instant?
    private var toolStartTimes: [String: ContinuousClock.Instant] = [:]
    private var currentTextPartId: String?

    public init() {}

    // MARK: - Public API

    /// Process a single stream event, updating the parts array.
    public func process(_ event: AIStreamEvent) {
        switch event {
        case .reasoningStart:
            let id = "thinking-\(parts.count)"
            parts.append(.thinking(id: id, text: "", durationSeconds: nil))
            thinkingStartTime = ContinuousClock.now

        case .reasoningDelta(let text):
            guard let lastIndex = parts.indices.last,
                  case .thinking(let id, let existing, _) = parts[lastIndex] else { return }
            parts[lastIndex] = .thinking(id: id, text: existing + text, durationSeconds: nil)

        case .reasoningFinish(let text):
            let duration: TimeInterval? = thinkingStartTime.map {
                (ContinuousClock.now - $0).timeInterval
            }
            if let lastIndex = parts.indices.last,
               case .thinking(let id, _, _) = parts[lastIndex] {
                let finalText = text.isEmpty ? thinkingText(at: lastIndex) : text
                parts[lastIndex] = .thinking(id: id, text: finalText, durationSeconds: duration)
            }
            thinkingStartTime = nil

        case .toolCallStart(let id, let name):
            let partId = "tool-\(id)"
            let call = AIToolCallPart(
                toolCallId: id,
                toolName: name,
                state: .inputStreaming
            )
            parts.append(.toolCall(id: partId, call: call))
            toolStartTimes[id] = ContinuousClock.now
            currentTextPartId = nil

        case .toolCallDelta(let id, let argumentsDelta):
            guard let index = toolCallIndex(for: id),
                  case .toolCall(let partId, var call) = parts[index] else { return }
            call.input += argumentsDelta
            parts[index] = .toolCall(id: partId, call: call)

        case .toolCall(let id, _, let arguments),
             .toolCallFinish(let id, _, let arguments):
            guard let index = toolCallIndex(for: id),
                  case .toolCall(let partId, var call) = parts[index] else { return }
            call.input = arguments
            call.state = .inputAvailable
            parts[index] = .toolCall(id: partId, call: call)

        case .toolResult(let id, let result, _):
            guard let index = toolCallIndex(for: id),
                  case .toolCall(let partId, var call) = parts[index] else { return }
            call.state = .outputAvailable
            call.output = result
            call.durationSeconds = toolStartTimes[id].map {
                (ContinuousClock.now - $0).timeInterval
            }
            parts[index] = .toolCall(id: partId, call: call)
            toolStartTimes.removeValue(forKey: id)

        case .textDelta(let text):
            if let textId = currentTextPartId,
               let index = parts.firstIndex(where: { $0.id == textId }),
               case .text(let id, let existing) = parts[index] {
                parts[index] = .text(id: id, text: existing + text)
            } else {
                let id = "text-\(parts.count)"
                parts.append(.text(id: id, text: text))
                currentTextPartId = id
            }

        case .source(let source):
            let id = "source-\(parts.count)"
            parts.append(.source(id: id, source: source))

        case .file(let file):
            let id = "file-\(parts.count)"
            parts.append(.file(id: id, file: file))

        case .stepStart(let stepIndex):
            currentStepIndex = stepIndex

        case .stepFinish:
            break

        case .finish:
            isComplete = true

        case .error:
            // Mark any in-progress tool calls as errored
            for i in parts.indices {
                if case .toolCall(let partId, var call) = parts[i],
                   call.state == .inputStreaming || call.state == .inputAvailable {
                    call.state = .outputError
                    call.errorText = "Stream error"
                    parts[i] = .toolCall(id: partId, call: call)
                }
            }
            isComplete = true

        default:
            break
        }
    }

    /// Reset for a new message
    public func reset() {
        parts = []
        isComplete = false
        currentStepIndex = 0
        thinkingStartTime = nil
        toolStartTimes = [:]
        currentTextPartId = nil
    }

    // MARK: - Computed Summaries

    /// Total thinking duration across all thinking parts, if any
    public var thinkingDuration: TimeInterval? {
        let durations = parts.compactMap { part -> TimeInterval? in
            if case .thinking(_, _, let d) = part { return d }
            return nil
        }
        return durations.isEmpty ? nil : durations.reduce(0, +)
    }

    /// Number of tool calls in this message
    public var toolCallCount: Int {
        parts.filter {
            if case .toolCall = $0 { return true }
            return false
        }.count
    }

    /// Human-readable summary for collapsed view (e.g. "Thought for 2.3s, called 2 tools")
    public var summary: String {
        var components: [String] = []

        if let duration = thinkingDuration {
            if duration < 1 {
                components.append("Thought for <1s")
            } else {
                components.append("Thought for \(String(format: "%.1f", duration))s")
            }
        }

        let count = toolCallCount
        if count > 0 {
            let toolNames = parts.compactMap { part -> String? in
                if case .toolCall(_, let call) = part { return call.toolName }
                return nil
            }
            let unique = Array(Set(toolNames))
            if unique.count == 1 {
                components.append("called \(unique[0]) \(count) \(count == 1 ? "time" : "times")")
            } else {
                components.append("called \(count) \(count == 1 ? "tool" : "tools")")
            }
        }

        return components.isEmpty ? "" : components.joined(separator: ", ")
    }

    /// Whether there is any non-text activity (thinking or tool calls)
    public var hasActivity: Bool {
        parts.contains { part in
            switch part {
            case .thinking, .toolCall: return true
            default: return false
            }
        }
    }

    // MARK: - Private Helpers

    private func toolCallIndex(for toolCallId: String) -> Int? {
        let searchId = "tool-\(toolCallId)"
        return parts.firstIndex { $0.id == searchId }
    }

    private func thinkingText(at index: Int) -> String {
        if case .thinking(_, let text, _) = parts[index] { return text }
        return ""
    }
}

