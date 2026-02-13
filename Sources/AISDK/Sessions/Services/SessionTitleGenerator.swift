//
//  SessionTitleGenerator.swift
//  AISDK
//
//  Protocol and default implementation for automatic session title generation.
//

import Foundation

/// Protocol for generating session titles from conversation context.
public protocol SessionTitleGenerator: Sendable {
    /// Generate a title from session messages.
    /// - Parameter messages: The conversation messages to derive a title from.
    /// - Returns: A short, descriptive title.
    func generateTitle(from messages: [AIMessage]) async throws -> String
}

/// Default title generator using an LLM to create concise session titles.
///
/// Uses the first few messages of a conversation to generate a 3-8 word title.
/// Falls back to "New Conversation" on error.
public actor DefaultTitleGenerator: SessionTitleGenerator {
    private let llm: any LLM
    private let maxContextMessages: Int
    private let fallbackTitle: String

    /// Create a title generator.
    /// - Parameters:
    ///   - llm: The LLM to use for title generation.
    ///   - maxContextMessages: Maximum number of messages to use as context (default: 6).
    ///   - fallbackTitle: Title to use if generation fails (default: "New Conversation").
    public init(
        llm: any LLM,
        maxContextMessages: Int = 6,
        fallbackTitle: String = "New Conversation"
    ) {
        self.llm = llm
        self.maxContextMessages = maxContextMessages
        self.fallbackTitle = fallbackTitle
    }

    public func generateTitle(from messages: [AIMessage]) async throws -> String {
        let contextMessages = Array(messages.prefix(maxContextMessages))

        guard !contextMessages.isEmpty else {
            return fallbackTitle
        }

        // Filter to user and assistant messages for cleaner context
        let relevantMessages = contextMessages.filter {
            $0.role == .user || $0.role == .assistant
        }

        guard !relevantMessages.isEmpty else {
            return fallbackTitle
        }

        let conversationText = relevantMessages.map { msg in
            "\(msg.role == .user ? "User" : "Assistant"): \(msg.content.textValue)"
        }.joined(separator: "\n")

        let prompt = """
        Generate a short title (3-8 words) for this conversation. \
        Return ONLY the title, no quotes or punctuation.

        \(conversationText)
        """

        do {
            let request = AITextRequest(messages: [.user(prompt)])
            let result = try await llm.generateText(request: request)
            let title = result.text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            return title.isEmpty ? fallbackTitle : title
        } catch {
            return fallbackTitle
        }
    }
}
