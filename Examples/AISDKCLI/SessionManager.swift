//
//  SessionManager.swift
//  AISDKCLI
//
//  Manages conversation state and history
//

import Foundation
import AISDK

/// Manages conversation state and history
class SessionManager {
    /// Conversation messages
    private(set) var messages: [AIMessage] = []

    /// Token usage tracking
    private(set) var totalPromptTokens: Int = 0
    private(set) var totalCompletionTokens: Int = 0

    /// Session start time
    let startTime: Date = Date()

    /// Number of exchanges (user message + assistant response)
    private(set) var exchangeCount: Int = 0

    /// System prompt
    var systemPrompt: String {
        didSet {
            // Update system message if exists
            if !messages.isEmpty, messages[0].role == .system {
                messages[0] = .system(systemPrompt)
            }
        }
    }

    /// Maximum history to keep (to manage context window)
    var maxHistoryMessages: Int = 50

    init(systemPrompt: String = "You are a helpful AI assistant.") {
        self.systemPrompt = systemPrompt
        self.messages = [.system(systemPrompt)]
    }

    // MARK: - LegacyMessage Management

    /// Add a user message
    func addUserMessage(_ content: String) {
        messages.append(.user(content))
        trimHistoryIfNeeded()
    }

    /// Add a user message with multimodal content parts
    func addUserMessage(parts: [AIMessage.ContentPart]) {
        messages.append(AIMessage(role: .user, content: .parts(parts)))
        trimHistoryIfNeeded()
    }

    /// Add an assistant message
    func addAssistantMessage(
        _ content: String,
        toolCalls: [AIMessage.ToolCall]? = nil,
        countsAsExchange: Bool = true
    ) {
        if let toolCalls = toolCalls, !toolCalls.isEmpty {
            messages.append(.assistant(content, toolCalls: toolCalls))
        } else {
            messages.append(.assistant(content))
        }
        if countsAsExchange {
            exchangeCount += 1
        }
        trimHistoryIfNeeded()
    }

    /// Add a tool result message
    func addToolResult(_ result: String, toolCallId: String) {
        messages.append(.tool(result, toolCallId: toolCallId))
    }

    /// Apply a step result to the conversation history
    func applyStepResult(_ result: AIStepResult) {
        let toolCalls = result.toolCalls.map { call in
            AIMessage.ToolCall(id: call.id, name: call.name, arguments: call.arguments)
        }

        let shouldCount = result.toolCalls.isEmpty
        addAssistantMessage(result.text, toolCalls: toolCalls.isEmpty ? nil : toolCalls, countsAsExchange: shouldCount)

        for toolResult in result.toolResults {
            addToolResult(toolResult.result, toolCallId: toolResult.id)
        }
    }

    /// Remove the last message (used when API call fails)
    func removeLastMessage() {
        if messages.count > 1 {  // Keep at least the system message
            messages.removeLast()
        }
    }

    /// Update token usage
    func updateUsage(promptTokens: Int, completionTokens: Int) {
        totalPromptTokens += promptTokens
        totalCompletionTokens += completionTokens
    }

    /// Clear conversation history (keep system prompt)
    func clear() {
        messages = [.system(systemPrompt)]
        exchangeCount = 0
    }

    /// Trim history if it exceeds max
    private func trimHistoryIfNeeded() {
        guard messages.count > maxHistoryMessages else { return }

        // Keep system message and most recent messages
        let systemMessage = messages.first!
        let recentMessages = Array(messages.suffix(maxHistoryMessages - 1))
        messages = [systemMessage] + recentMessages
    }

    // MARK: - Session Statistics

    /// Get session statistics
    func getStatistics() -> SessionStatistics {
        let duration = Date().timeIntervalSince(startTime)
        return SessionStatistics(
            exchangeCount: exchangeCount,
            messageCount: messages.count,
            totalPromptTokens: totalPromptTokens,
            totalCompletionTokens: totalCompletionTokens,
            totalTokens: totalPromptTokens + totalCompletionTokens,
            durationSeconds: duration
        )
    }

    // MARK: - Save/Load

    /// Save conversation to file
    func save(to path: String) throws {
        let data = ConversationData(
            messages: messages.map { SerializableMessage(from: $0) },
            statistics: getStatistics()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)

        let expandedPath = NSString(string: path).expandingTildeInPath
        try jsonData.write(to: URL(fileURLWithPath: expandedPath))
    }

    /// Load conversation from file
    func load(from path: String) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let jsonData = try Data(contentsOf: URL(fileURLWithPath: expandedPath))

        let decoder = JSONDecoder()
        let data = try decoder.decode(ConversationData.self, from: jsonData)

        // Convert back to AIMessage
        messages = data.messages.compactMap { $0.toAIMessage() }

        // Ensure we have a system message
        if messages.isEmpty {
            messages.insert(.system(systemPrompt), at: 0)
        } else if messages[0].role == .system {
            // System message exists, update systemPrompt
            systemPrompt = messages[0].content.textValue
        } else {
            // No system message, insert one
            messages.insert(.system(systemPrompt), at: 0)
        }

        // Restore exchange count
        exchangeCount = messages.filter { $0.role == .assistant }.count
    }
}

// MARK: - Supporting Types

struct SessionStatistics: Codable {
    let exchangeCount: Int
    let messageCount: Int
    let totalPromptTokens: Int
    let totalCompletionTokens: Int
    let totalTokens: Int
    let durationSeconds: TimeInterval

    var formattedDuration: String {
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        return "\(minutes)m \(seconds)s"
    }
}

// MARK: - Serializable Types for Save/Load

private struct ConversationData: Codable {
    let messages: [SerializableMessage]
    let statistics: SessionStatistics
}

private struct SerializableMessage: Codable {
    let role: String
    let content: String
    let name: String?
    let toolCalls: [SerializableToolCall]?
    let toolCallId: String?

    init(from message: AIMessage) {
        self.role = message.role.rawValue
        self.content = message.content.textValue
        self.name = message.name
        self.toolCallId = message.toolCallId
        self.toolCalls = message.toolCalls?.map { SerializableToolCall(from: $0) }
    }

    func toAIMessage() -> AIMessage? {
        switch role {
        case "system":
            return .system(content)
        case "user":
            return .user(content)
        case "assistant":
            if let toolCalls = toolCalls, !toolCalls.isEmpty {
                return .assistant(content, toolCalls: toolCalls.map { $0.toToolCall() })
            }
            return .assistant(content)
        case "tool":
            if let toolCallId = toolCallId {
                return .tool(content, toolCallId: toolCallId)
            }
            return nil
        default:
            return nil
        }
    }
}

private struct SerializableToolCall: Codable {
    let id: String
    let name: String
    let arguments: String

    init(from toolCall: AIMessage.ToolCall) {
        self.id = toolCall.id
        self.name = toolCall.name
        self.arguments = toolCall.arguments
    }

    func toToolCall() -> AIMessage.ToolCall {
        AIMessage.ToolCall(id: id, name: name, arguments: arguments)
    }
}
