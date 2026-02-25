//
//  AIMessagePart.swift
//  AISDK
//
//  Typed message parts for structured agent activity rendering.
//  Modeled after Vercel AI SDK's UIMessage.parts pattern.
//

import Foundation

// MARK: - AIMessagePart

/// A typed part of an assistant message, preserving interleaved order.
///
/// When an agent streams a response, it may produce reasoning, tool calls,
/// and text in an interleaved sequence. `AIMessagePart` captures each piece
/// with its type and lifecycle state, enabling structured rendering.
///
/// ## Usage
/// ```swift
/// let accumulator = AIStreamAccumulator()
/// for try await event in agent.streamExecute(messages: messages) {
///     await accumulator.process(event)
/// }
/// // accumulator.parts now contains the ordered sequence
/// ```
public enum AIMessagePart: Identifiable, Sendable {
    /// Text content from the model
    case text(id: String, text: String)

    /// Reasoning/thinking content (provider-dependent: Anthropic, Gemini)
    case thinking(id: String, text: String, durationSeconds: TimeInterval?)

    /// A tool call with lifecycle state
    case toolCall(id: String, call: AIToolCallPart)

    /// Source/citation reference
    case source(id: String, source: AISource)

    /// File content (e.g. generated images)
    case file(id: String, file: AIFileEvent)

    /// Web search activity (searching → completed with sources)
    case webSearch(id: String, query: String, sources: [AISource])

    public var id: String {
        switch self {
        case .text(let id, _): id
        case .thinking(let id, _, _): id
        case .toolCall(let id, _): id
        case .source(let id, _): id
        case .file(let id, _): id
        case .webSearch(let id, _, _): id
        }
    }
}

// MARK: - AIToolCallState

/// Lifecycle state for a tool call, matching Vercel AI SDK's tool state machine.
public enum AIToolCallState: String, Sendable, Codable {
    /// Tool arguments are being streamed from the model
    case inputStreaming

    /// Tool arguments are complete, tool is executing
    case inputAvailable

    /// Tool execution completed successfully
    case outputAvailable

    /// Tool execution failed
    case outputError
}

// MARK: - AIToolCallPart

/// Structured data for a single tool call with lifecycle tracking.
public struct AIToolCallPart: Sendable {
    /// The tool call ID from the provider
    public let toolCallId: String

    /// The name of the tool being called
    public let toolName: String

    /// Current lifecycle state
    public var state: AIToolCallState

    /// JSON arguments (accumulated from deltas)
    public var input: String

    /// Result text from tool execution (nil until outputAvailable)
    public var output: String?

    /// Error description if tool execution failed
    public var errorText: String?

    /// Duration of tool execution in seconds
    public var durationSeconds: TimeInterval?

    public init(
        toolCallId: String,
        toolName: String,
        state: AIToolCallState = .inputStreaming,
        input: String = "",
        output: String? = nil,
        errorText: String? = nil,
        durationSeconds: TimeInterval? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.state = state
        self.input = input
        self.output = output
        self.errorText = errorText
        self.durationSeconds = durationSeconds
    }
}
