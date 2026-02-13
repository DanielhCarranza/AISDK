//
//  SessionCompactionService.swift
//  AISDK
//
//  Service for managing context window size through message compaction.
//

import Foundation

/// Service for compacting session messages when they exceed context limits.
///
/// Uses heuristic token estimation (4 chars/token + 15% safety margin)
/// and supports three compaction strategies: truncate, summarize, and sliding window.
public actor SessionCompactionService {
    private let llm: (any LLM)?

    /// Create a compaction service.
    /// - Parameter llm: An LLM to use for summarization strategy. Optional for truncate/slidingWindow.
    public init(llm: (any LLM)? = nil) {
        self.llm = llm
    }

    // MARK: - Token Estimation

    /// Estimate the token count for a set of messages.
    ///
    /// Uses heuristic: ~4 UTF-8 bytes per token + 15% safety margin + per-message overhead.
    public func estimateTokens(_ messages: [AIMessage]) -> Int {
        var total = 0
        for message in messages {
            total += 4 // per-message overhead
            let text = message.content.textValue
            let charCount = text.utf8.count
            total += Int(Double((charCount + 3) / 4) * 1.15)
            if let toolCalls = message.toolCalls {
                for call in toolCalls {
                    total += 4
                    total += Int(Double((call.name.utf8.count + call.arguments.utf8.count + 3) / 4) * 1.15)
                }
            }
        }
        total += 3 // assistant priming
        return total
    }

    // MARK: - Compaction Check

    /// Check if a session needs compaction based on the given policy.
    public func needsCompaction(_ messages: [AIMessage], policy: ContextPolicy) -> Bool {
        guard let maxTokens = policy.maxTokens else { return false }
        let estimated = estimateTokens(messages)
        let threshold = Int(Double(maxTokens) * policy.compactionThreshold)
        return estimated >= threshold
    }

    // MARK: - Compaction

    /// Compact messages according to the given policy.
    ///
    /// Returns a new message array that fits within the context budget.
    public func compact(_ messages: [AIMessage], policy: ContextPolicy) async throws -> [AIMessage] {
        switch policy.compactionStrategy {
        case .truncate:
            return truncate(messages, policy: policy)
        case .summarize:
            return try await summarize(messages, policy: policy)
        case .slidingWindow:
            return slidingWindow(messages, policy: policy)
        }
    }

    // MARK: - Strategies

    /// Truncate: keep system prompt + most recent messages.
    private func truncate(_ messages: [AIMessage], policy: ContextPolicy) -> [AIMessage] {
        guard messages.count > policy.minMessagesToKeep else { return messages }

        var result: [AIMessage] = []

        // Preserve system prompt if present and policy says so
        if policy.preserveSystemPrompt, let first = messages.first, first.role == .system {
            result.append(first)
        }

        // Keep the most recent messages
        let recentStart = max(messages.count - policy.minMessagesToKeep, result.count)
        result.append(contentsOf: messages[recentStart...])

        return result
    }

    /// Summarize: replace older messages with an LLM-generated summary.
    private func summarize(_ messages: [AIMessage], policy: ContextPolicy) async throws -> [AIMessage] {
        guard let llm = llm else {
            // Fallback to truncation if no LLM available
            return truncate(messages, policy: policy)
        }

        guard messages.count > policy.minMessagesToKeep else { return messages }

        var result: [AIMessage] = []

        // Preserve system prompt
        var systemMessage: AIMessage?
        let startIndex: Int
        if policy.preserveSystemPrompt, let first = messages.first, first.role == .system {
            systemMessage = first
            startIndex = 1
        } else {
            startIndex = 0
        }

        // Split into "to summarize" and "to keep"
        let keepStart = max(messages.count - policy.minMessagesToKeep, startIndex)
        let toSummarize = Array(messages[startIndex..<keepStart])
        let toKeep = Array(messages[keepStart...])

        guard !toSummarize.isEmpty else {
            return messages
        }

        // Build summary prompt
        let conversationText = toSummarize.map { msg in
            "\(msg.role.rawValue): \(msg.content.textValue)"
        }.joined(separator: "\n")

        let summaryPrompt = """
        Summarize the following conversation concisely, preserving key facts, decisions, \
        and context needed for continuation. Be brief but complete.

        \(conversationText)
        """

        let request = AITextRequest(messages: [.user(summaryPrompt)])
        let summaryResult = try await llm.generateText(request: request)

        // Build compacted messages
        if let sys = systemMessage { result.append(sys) }
        result.append(.system("[Previous conversation summary: \(summaryResult.text)]"))
        result.append(contentsOf: toKeep)

        return result
    }

    /// Sliding window: keep first N context messages + last M recent messages.
    private func slidingWindow(_ messages: [AIMessage], policy: ContextPolicy) -> [AIMessage] {
        guard messages.count > policy.minMessagesToKeep else { return messages }

        // Keep: system prompt (if present) + first 2 user/assistant turns + last minMessagesToKeep
        var headMessages: [AIMessage] = []
        var headCount = 0
        let maxHead = 2 // Keep first 2 exchanges for context

        var startIndex = 0
        if policy.preserveSystemPrompt, let first = messages.first, first.role == .system {
            headMessages.append(first)
            startIndex = 1
        }

        for i in startIndex..<messages.count {
            if headCount >= maxHead { break }
            headMessages.append(messages[i])
            if messages[i].role == .assistant { headCount += 1 }
        }

        // Keep most recent messages
        let tailStart = max(messages.count - policy.minMessagesToKeep, headMessages.count)
        let tailMessages = Array(messages[tailStart...])

        // Merge, avoiding duplicates
        var result = headMessages
        for msg in tailMessages {
            if !result.contains(where: { $0.id == msg.id }) {
                result.append(msg)
            }
        }

        return result
    }
}
