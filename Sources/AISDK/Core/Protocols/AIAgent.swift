//
//  AIAgent.swift
//  AISDK
//
//  Core protocol for unified AI agent interface
//  Based on Vercel AI SDK 6.x agent patterns
//

import Foundation

// MARK: - AIAgent Protocol

/// Unified protocol for AI agents that coordinate LegacyLLM calls with tool execution.
/// This protocol provides a consistent interface for agent implementations across
/// different backing implementations.
public protocol AIAgent: Sendable {
    /// The agent's unique identifier
    var agentId: String { get }

    /// The name of this agent
    var name: String? { get }

    /// The current state of the agent
    var state: AIAgentState { get }

    /// The conversation history
    var messages: [AIMessage] { get }

    /// Available tools for this agent
    var tools: [ToolSchema] { get }

    /// The underlying language model
    var model: LLM { get }

    /// Send a message and get a response (non-streaming)
    /// - Parameter message: The user's message
    /// - Returns: The agent's response
    func send(_ message: String) async throws -> AIAgentResponse

    /// Send a message and stream the response
    /// - Parameters:
    ///   - message: The user's message
    ///   - requiredTool: Optional tool name that must be called
    /// - Returns: An async stream of agent events
    func sendStream(_ message: String, requiredTool: String?) -> AsyncThrowingStream<AIAgentEvent, Error>

    /// Reset the agent's conversation history
    func reset()

    /// Set the conversation history
    /// - Parameter messages: The new message history
    func setMessages(_ messages: [AIMessage])
}

// MARK: - Default Implementations

public extension AIAgent {
    func sendStream(_ message: String) -> AsyncThrowingStream<AIAgentEvent, Error> {
        sendStream(message, requiredTool: nil)
    }
}

// MARK: - AIAgentState

/// Represents the current state of an AI agent
public enum AIAgentState: Sendable, Equatable {
    /// LegacyAgent is idle and ready for input
    case idle

    /// LegacyAgent is thinking/processing
    case thinking

    /// LegacyAgent is executing a tool
    case executingTool(name: String)

    /// LegacyAgent is generating a response
    case responding

    /// LegacyAgent encountered an error
    case error(String)

    /// Whether the agent is currently processing
    public var isProcessing: Bool {
        switch self {
        case .idle, .error:
            return false
        case .thinking, .executingTool, .responding:
            return true
        }
    }

    /// A human-readable status message
    public var statusMessage: String {
        switch self {
        case .idle:
            return ""
        case .thinking:
            return "Thinking..."
        case .executingTool(let name):
            return "Executing \(name)..."
        case .responding:
            return "Formulating response..."
        case .error(let message):
            return message
        }
    }
}

// MARK: - AIAgentResponse

/// The result of a non-streaming agent call
public struct AIAgentResponse: Sendable {
    /// The text response from the agent
    public let text: String

    /// Tool calls made during processing
    public let toolCalls: [ToolCallResult]

    /// Tool results from executed tools
    public let toolResults: [AIToolResultData]

    /// The updated conversation messages
    public let messages: [AIMessage]

    /// Token usage information
    public let usage: AIUsage

    /// Optional metadata from tool execution
    public let metadata: ToolMetadata?

    public init(
        text: String,
        toolCalls: [ToolCallResult] = [],
        toolResults: [AIToolResultData] = [],
        messages: [AIMessage] = [],
        usage: AIUsage = .zero,
        metadata: ToolMetadata? = nil
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.messages = messages
        self.usage = usage
        self.metadata = metadata
    }
}

// MARK: - AIAgentEvent

/// Events emitted during streaming agent operations
public enum AIAgentEvent: Sendable {
    // MARK: - State Events

    /// LegacyAgent state changed
    case stateChange(AIAgentState)

    // MARK: - Message Events

    /// A new message was added to the conversation
    case messageAdded(AIMessage)

    /// A message was updated (e.g., streaming content)
    case messageUpdated(AIMessage, isPending: Bool)

    // MARK: - Text Events

    /// Text delta received during streaming
    case textDelta(String)

    /// Full text accumulated so far
    case text(String)

    // MARK: - Tool Events

    /// Tool call started
    case toolCallStart(id: String, name: String)

    /// Tool call arguments delta
    case toolCallDelta(id: String, argumentsDelta: String)

    /// Tool call completed
    case toolCall(id: String, name: String, arguments: String)

    /// Tool execution result
    case toolResult(id: String, result: String, metadata: ToolMetadata?)

    // MARK: - Lifecycle Events

    /// Stream has started
    case start

    /// Stream has finished
    case finish(text: String, usage: AIUsage)

    /// An error occurred
    case error(Error)
}

// MARK: - AIAgentConfiguration

/// Configuration options for creating an AI agent
public struct AIAgentConfiguration: Sendable {
    /// The language model to use
    public let model: LLM

    /// Available tools
    public let tools: [ToolSchema]

    /// System instructions for the agent
    public let instructions: String?

    /// Initial conversation history
    public let initialMessages: [AIMessage]

    /// Maximum number of tool execution rounds
    public let maxToolRounds: Int

    /// Data sensitivity for PHI protection
    public let sensitivity: DataSensitivity

    /// Optional agent name
    public let name: String?

    public init(
        model: LLM,
        tools: [ToolSchema] = [],
        instructions: String? = nil,
        initialMessages: [AIMessage] = [],
        maxToolRounds: Int = 10,
        sensitivity: DataSensitivity = .standard,
        name: String? = nil
    ) {
        self.model = model
        self.tools = tools
        self.instructions = instructions
        self.initialMessages = initialMessages
        self.maxToolRounds = maxToolRounds
        self.sensitivity = sensitivity
        self.name = name
    }
}

// MARK: - AIAgentCallbacks

/// Callbacks for monitoring agent execution
public protocol AIAgentCallbacks: AnyObject, Sendable {
    /// Called when the agent state changes
    func onStateChange(state: AIAgentState) async

    /// Called when a message is received
    func onMessageReceived(message: AIMessage) async -> AIAgentCallbackResult

    /// Called before a tool is executed
    func onBeforeToolExecution(name: String, arguments: String) async -> AIAgentCallbackResult

    /// Called after a tool is executed
    func onAfterToolExecution(name: String, result: String, metadata: ToolMetadata?) async -> AIAgentCallbackResult

    /// Called when a tool execution fails
    func onToolError(name: String, error: Error) async -> AIAgentCallbackResult

    /// Called when streaming content is received
    func onStreamChunk(text: String) async -> AIAgentCallbackResult
}

/// Default implementations for AIAgentCallbacks
public extension AIAgentCallbacks {
    func onStateChange(state: AIAgentState) async {}
    func onMessageReceived(message: AIMessage) async -> AIAgentCallbackResult { .continue }
    func onBeforeToolExecution(name: String, arguments: String) async -> AIAgentCallbackResult { .continue }
    func onAfterToolExecution(name: String, result: String, metadata: ToolMetadata?) async -> AIAgentCallbackResult { .continue }
    func onToolError(name: String, error: Error) async -> AIAgentCallbackResult { .continue }
    func onStreamChunk(text: String) async -> AIAgentCallbackResult { .continue }
}

/// Result of an agent callback
public enum AIAgentCallbackResult: Sendable {
    /// Continue normal execution
    case `continue`

    /// Cancel the current operation
    case cancel

    /// Replace the response with custom content
    case replace(AIMessage)
}

// MARK: - AIAgentError

/// Errors that can occur during agent operations
public enum AIAgentError: Error, Sendable {
    /// Operation was cancelled by a callback
    case operationCancelled

    /// Tool execution failed
    case toolExecutionFailed(String)

    /// Invalid tool response
    case invalidToolResponse

    /// Maximum tool rounds exceeded
    case maxToolRoundsExceeded

    /// No response from LLM
    case noResponse

    /// Stream error
    case streamError(String)

    /// Configuration error
    case configurationError(String)

    /// Generic error wrapper
    case underlying(Error)

    public var localizedDescription: String {
        switch self {
        case .operationCancelled:
            return "Operation was cancelled"
        case .toolExecutionFailed(let message):
            return "Tool execution failed: \(message)"
        case .invalidToolResponse:
            return "Invalid tool response"
        case .maxToolRoundsExceeded:
            return "Maximum tool execution rounds exceeded"
        case .noResponse:
            return "No response from language model"
        case .streamError(let message):
            return "Stream error: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}
