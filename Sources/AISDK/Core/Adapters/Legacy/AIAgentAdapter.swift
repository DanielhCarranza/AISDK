//
//  AIAgentAdapter.swift
//  AISDK
//
//  Adapter that wraps the legacy LegacyAgent class to conform to AIAgent
//  Provides backward compatibility for existing consumers
//

import Foundation

// MARK: - AIAgentAdapter

/// Adapter that wraps an existing LegacyAgent implementation to conform to the new AIAgent protocol.
/// This enables gradual migration from the legacy LegacyAgent class to the new unified interface.
///
/// Usage:
/// ```swift
/// let legacyAgent = LegacyAgent(llm: provider, tools: [WeatherTool.self])
/// let adapter = AIAgentAdapter(
///     agent: legacyAgent,
///     modelAdapter: AILanguageModelAdapter.fromOpenAI(provider)
/// )
/// let response = try await adapter.send("What's the weather?")
/// ```
public final class AIAgentAdapter: @unchecked Sendable {
    // MARK: - Properties

    /// The wrapped legacy LegacyAgent instance
    private let agent: LegacyAgent

    /// The language model adapter
    private let modelAdapter: AILanguageModel

    /// Unique identifier for this agent
    public let agentId: String

    /// Optional name for this agent
    public let name: String?

    /// Tool schemas available to this agent
    private let toolSchemas: [ToolSchema]

    /// Registered callbacks
    private var callbacks: [AIAgentCallbacks] = []

    /// Lock for thread-safe callback access
    private let callbackLock = NSLock()

    // MARK: - Initialization

    /// Creates an adapter wrapping a legacy LegacyAgent implementation
    /// - Parameters:
    ///   - agent: The legacy LegacyAgent to wrap
    ///   - modelAdapter: The AILanguageModel adapter for the underlying LegacyLLM
    ///   - name: Optional name for the agent
    ///   - agentId: Optional unique identifier (auto-generated if nil)
    public init(
        agent: LegacyAgent,
        modelAdapter: AILanguageModel,
        name: String? = nil,
        agentId: String? = nil
    ) {
        self.agent = agent
        self.modelAdapter = modelAdapter
        self.name = name
        self.agentId = agentId ?? UUID().uuidString
        self.toolSchemas = [] // Will be populated from agent's tools

        // Set up state change forwarding
        agent.onStateChange = { [weak self] legacyState in
            guard let self = self else { return }
            let newState = AIAgentState(from: legacyState)
            Task {
                await self.notifyStateChange(newState)
            }
        }
    }

    // MARK: - Callback Management

    /// Add a callback handler
    public func addCallback(_ callback: AIAgentCallbacks) {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        callbacks.append(callback)
    }

    /// Remove a callback handler
    public func removeCallback(_ callback: AIAgentCallbacks) {
        callbackLock.lock()
        defer { callbackLock.unlock() }
        callbacks.removeAll { $0 === callback }
    }

    private func notifyStateChange(_ state: AIAgentState) async {
        let currentCallbacks: [AIAgentCallbacks]
        callbackLock.lock()
        currentCallbacks = callbacks
        callbackLock.unlock()

        for callback in currentCallbacks {
            await callback.onStateChange(state: state)
        }
    }
}

// MARK: - AIAgent Conformance

extension AIAgentAdapter: AIAgent {
    public var state: AIAgentState {
        AIAgentState(from: agent.state)
    }

    public var messages: [AIMessage] {
        agent.messages.map { convertToAIMessage($0) }
    }

    public var tools: [ToolSchema] {
        toolSchemas
    }

    public var model: AILanguageModel {
        modelAdapter
    }

    public func send(_ message: String) async throws -> AIAgentResponse {
        // Send message through legacy agent
        let response = try await agent.send(message)

        // Convert response to AIAgentResponse
        return AIAgentResponse(
            text: response.displayContent,
            toolCalls: extractToolCalls(from: response),
            toolResults: extractToolResults(from: agent.messages),
            messages: agent.messages.map { convertToAIMessage($0) },
            usage: .zero, // Legacy agent doesn't track usage
            metadata: response.metadata
        )
    }

    public func sendStream(
        _ message: String,
        requiredTool: String?
    ) -> AsyncThrowingStream<AIAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Emit start event
                    continuation.yield(.start)

                    // Create LegacyChatMessage for the legacy agent
                    let chatMessage = LegacyChatMessage(message: .user(content: .text(message)))

                    // Get the stream from legacy agent
                    let stream = agent.sendStream(chatMessage, requiredTool: requiredTool)

                    var accumulatedText = ""

                    for try await chatMessage in stream {
                        // Emit state change
                        continuation.yield(.stateChange(AIAgentState(from: agent.state)))

                        // Convert and emit message event
                        let aiMessage = convertToAIMessage(chatMessage)

                        if chatMessage.isPending {
                            continuation.yield(.messageUpdated(aiMessage, isPending: true))
                        } else {
                            continuation.yield(.messageAdded(aiMessage))
                        }

                        // Emit text events for assistant messages
                        if case .assistant = chatMessage.message {
                            let text = chatMessage.displayContent
                            if text.count > accumulatedText.count {
                                let delta = String(text.dropFirst(accumulatedText.count))
                                continuation.yield(.textDelta(delta))
                            }
                            accumulatedText = text
                            continuation.yield(.text(accumulatedText))
                        }

                        // Emit tool events
                        if case .tool(let content, _, let toolCallId) = chatMessage.message {
                            continuation.yield(.toolResult(
                                id: toolCallId,
                                result: content,
                                metadata: chatMessage.metadata
                            ))
                        }

                        // Check for tool calls in assistant messages
                        if case .assistant(_, _, let toolCalls) = chatMessage.message,
                           let toolCalls = toolCalls {
                            for toolCall in toolCalls {
                                continuation.yield(.toolCall(
                                    id: toolCall.id,
                                    name: toolCall.function?.name ?? "",
                                    arguments: toolCall.function?.arguments ?? ""
                                ))
                            }
                        }
                    }

                    // Emit finish event
                    continuation.yield(.finish(text: accumulatedText, usage: .zero))
                    continuation.finish()

                } catch {
                    continuation.yield(.error(error))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func reset() {
        agent.setMessages([])
    }

    public func setMessages(_ messages: [AIMessage]) {
        let chatMessages = messages.map { convertToLegacyChatMessage($0) }
        agent.setMessages(chatMessages)
    }
}

// MARK: - Conversion Helpers

private extension AIAgentAdapter {
    func convertToAIMessage(_ chatMessage: LegacyChatMessage) -> AIMessage {
        switch chatMessage.message {
        case .user(let content, let name):
            return AIMessage(
                role: .user,
                content: convertUserContent(content),
                name: name
            )

        case .assistant(let content, let name, let toolCalls):
            let aiToolCalls: [AIMessage.ToolCall]?
            if let toolCalls = toolCalls {
                aiToolCalls = toolCalls.compactMap { call in
                    guard let function = call.function else { return nil }
                    return AIMessage.ToolCall(
                        id: call.id,
                        name: function.name,
                        arguments: function.arguments
                    )
                }
            } else {
                aiToolCalls = nil
            }

            return AIMessage(
                role: .assistant,
                content: convertAssistantContent(content),
                name: name,
                toolCalls: aiToolCalls
            )

        case .system(let content, let name):
            return AIMessage(
                role: .system,
                content: convertSystemContent(content),
                name: name
            )

        case .tool(let content, let name, let toolCallId):
            return AIMessage(
                role: .tool,
                content: .text(content),
                name: name,
                toolCallId: toolCallId
            )

        case .developer(let content, let name):
            // Map developer to system for now
            return AIMessage(
                role: .system,
                content: convertDeveloperContent(content),
                name: name
            )
        }
    }

    func convertToLegacyChatMessage(_ aiMessage: AIMessage) -> LegacyChatMessage {
        let message: LegacyMessage
        switch aiMessage.role {
        case .user:
            message = .user(content: convertToUserContent(aiMessage.content), name: aiMessage.name)
        case .assistant:
            let toolCalls: [ChatCompletionResponse.ToolCall]?
            if let aiToolCalls = aiMessage.toolCalls {
                toolCalls = aiToolCalls.map { call in
                    ChatCompletionResponse.ToolCall(
                        id: call.id,
                        type: "function",
                        function: ChatCompletionResponse.ToolFunctionCall(
                            name: call.name,
                            arguments: call.arguments
                        )
                    )
                }
            } else {
                toolCalls = nil
            }
            message = .assistant(
                content: convertToAssistantContent(aiMessage.content),
                name: aiMessage.name,
                toolCalls: toolCalls
            )
        case .system:
            message = .system(content: convertToSystemContent(aiMessage.content), name: aiMessage.name)
        case .tool:
            message = .tool(
                content: aiMessage.content.textValue,
                name: aiMessage.name ?? "",
                toolCallId: aiMessage.toolCallId ?? ""
            )
        }
        return LegacyChatMessage(message: message)
    }

    func convertUserContent(_ content: UserContent) -> AIMessage.Content {
        switch content {
        case .text(let text):
            return .text(text)
        case .parts(let parts):
            let aiParts = parts.map { part -> AIMessage.ContentPart in
                switch part {
                case .text(let text):
                    return .text(text)
                case .imageURL(let source, _):
                    switch source {
                    case .url(let url):
                        return .imageURL(url.absoluteString)
                    case .base64(let data):
                        return .image(data, mimeType: "image/png")
                    }
                }
            }
            return .parts(aiParts)
        }
    }

    func convertDeveloperContent(_ content: DeveloperContent) -> AIMessage.Content {
        switch content {
        case .text(let text):
            return .text(text)
        case .parts(let parts):
            return .text(parts.joined(separator: "\n"))
        }
    }

    func convertAssistantContent(_ content: AssistantContent) -> AIMessage.Content {
        switch content {
        case .text(let text):
            return .text(text)
        case .parts(let parts):
            return .text(parts.joined(separator: "\n"))
        }
    }

    func convertSystemContent(_ content: SystemContent) -> AIMessage.Content {
        switch content {
        case .text(let text):
            return .text(text)
        case .parts(let parts):
            return .text(parts.joined(separator: "\n"))
        }
    }

    func convertToUserContent(_ content: AIMessage.Content) -> UserContent {
        switch content {
        case .text(let text):
            return .text(text)
        case .parts(let parts):
            let userParts = parts.compactMap { part -> UserContent.Part? in
                switch part {
                case .text(let text):
                    return .text(text)
                case .image(let data, _):
                    return .imageURL(.base64(data), detail: .auto)
                case .imageURL(let urlString):
                    if let url = URL(string: urlString) {
                        return .imageURL(.url(url), detail: .auto)
                    }
                    return nil
                case .audio, .file:
                    // Not directly supported in legacy format
                    return nil
                }
            }
            return .parts(userParts)
        }
    }

    func convertToAssistantContent(_ content: AIMessage.Content) -> AssistantContent {
        switch content {
        case .text(let text):
            return .text(text)
        case .parts(let parts):
            let textParts = parts.compactMap { part -> String? in
                if case .text(let text) = part {
                    return text
                }
                return nil
            }
            return textParts.count == 1 ? .text(textParts[0]) : .parts(textParts)
        }
    }

    func convertToSystemContent(_ content: AIMessage.Content) -> SystemContent {
        switch content {
        case .text(let text):
            return .text(text)
        case .parts(let parts):
            let textParts = parts.compactMap { part -> String? in
                if case .text(let text) = part {
                    return text
                }
                return nil
            }
            return textParts.count == 1 ? .text(textParts[0]) : .parts(textParts)
        }
    }

    func extractToolCalls(from response: LegacyChatMessage) -> [AIToolCallResult] {
        guard case .assistant(_, _, let toolCalls) = response.message,
              let toolCalls = toolCalls else {
            return []
        }

        return toolCalls.compactMap { call in
            guard let function = call.function else { return nil }
            return AIToolCallResult(
                id: call.id,
                name: function.name,
                arguments: function.arguments
            )
        }
    }

    func extractToolResults(from messages: [LegacyChatMessage]) -> [AIToolResultData] {
        messages.compactMap { message in
            guard case .tool(let content, _, let toolCallId) = message.message else {
                return nil
            }
            return AIToolResultData(
                id: toolCallId,
                result: content,
                metadata: message.metadata
            )
        }
    }
}

// MARK: - AIAgentState Conversion

private extension AIAgentState {
    init(from legacyState: LegacyAgentState) {
        switch legacyState {
        case .idle:
            self = .idle
        case .thinking:
            self = .thinking
        case .executingTool(let name):
            self = .executingTool(name: name)
        case .responding:
            self = .responding
        case .error(let error):
            self = .error(error.detailedDescription)
        }
    }
}

// MARK: - Factory Methods

public extension AIAgentAdapter {
    /// Create an adapter from a legacy LegacyAgent with OpenAI provider
    /// - Parameters:
    ///   - agent: The legacy LegacyAgent to wrap
    ///   - model: The model identifier (default: "gpt-4")
    /// - Returns: An AIAgentAdapter wrapping the agent
    static func fromOpenAI(
        _ agent: LegacyAgent,
        model: String = "gpt-4"
    ) -> AIAgentAdapter {
        let modelAdapter = AILanguageModelAdapter(
            llm: agent.llm,
            provider: "openai",
            modelId: model,
            capabilities: [.text, .vision, .tools, .streaming, .functionCalling],
            defaultModel: model
        )

        return AIAgentAdapter(
            agent: agent,
            modelAdapter: modelAdapter
        )
    }

    /// Create an adapter from a legacy LegacyAgent with Anthropic provider
    /// - Parameters:
    ///   - agent: The legacy LegacyAgent to wrap
    ///   - model: The model identifier (default: "claude-3-opus")
    /// - Returns: An AIAgentAdapter wrapping the agent
    static func fromAnthropic(
        _ agent: LegacyAgent,
        model: String = "claude-3-opus"
    ) -> AIAgentAdapter {
        let modelAdapter = AILanguageModelAdapter(
            llm: agent.llm,
            provider: "anthropic",
            modelId: model,
            capabilities: [.text, .vision, .tools, .streaming],
            defaultModel: model
        )

        return AIAgentAdapter(
            agent: agent,
            modelAdapter: modelAdapter
        )
    }

    /// Create an adapter from a legacy LegacyAgent with a custom model adapter
    /// - Parameters:
    ///   - agent: The legacy LegacyAgent to wrap
    ///   - modelAdapter: A pre-configured AILanguageModel adapter
    ///   - name: Optional name for the agent
    /// - Returns: An AIAgentAdapter wrapping the agent
    static func from(
        _ agent: LegacyAgent,
        modelAdapter: AILanguageModel,
        name: String? = nil
    ) -> AIAgentAdapter {
        AIAgentAdapter(
            agent: agent,
            modelAdapter: modelAdapter,
            name: name
        )
    }
}

