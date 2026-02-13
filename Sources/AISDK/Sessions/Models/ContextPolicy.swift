//
//  ContextPolicy.swift
//  AISDK
//
//  Policy for managing session context size and automatic compaction.
//

import Foundation

/// Policy for managing session context size.
///
/// When the estimated token count exceeds the threshold, the session
/// is automatically compacted using the specified strategy.
public struct ContextPolicy: Codable, Sendable {
    /// Maximum tokens before compaction triggers (nil = unlimited)
    public var maxTokens: Int?

    /// Trigger compaction at this percentage of max tokens (default: 0.9)
    public var compactionThreshold: Double

    /// Strategy for reducing context size
    public var compactionStrategy: CompactionStrategy

    /// Always preserve the system prompt during compaction
    public var preserveSystemPrompt: Bool

    /// Minimum number of recent messages to keep after compaction
    public var minMessagesToKeep: Int

    public init(
        maxTokens: Int? = nil,
        compactionThreshold: Double = 0.9,
        compactionStrategy: CompactionStrategy = .truncate,
        preserveSystemPrompt: Bool = true,
        minMessagesToKeep: Int = 4
    ) {
        self.maxTokens = maxTokens
        self.compactionThreshold = compactionThreshold
        self.compactionStrategy = compactionStrategy
        self.preserveSystemPrompt = preserveSystemPrompt
        self.minMessagesToKeep = minMessagesToKeep
    }

    /// Default policy with no limits
    public static let unlimited = ContextPolicy()

    /// Conservative policy for models with smaller context windows
    public static func conservative(maxTokens: Int) -> ContextPolicy {
        ContextPolicy(
            maxTokens: maxTokens,
            compactionThreshold: 0.8,
            compactionStrategy: .slidingWindow,
            preserveSystemPrompt: true,
            minMessagesToKeep: 6
        )
    }
}

/// Strategy for reducing context size during compaction
public enum CompactionStrategy: String, Codable, Sendable {
    /// Remove oldest messages (keep system prompt + recent messages)
    case truncate

    /// Summarize older messages using LLM
    case summarize

    /// Keep first N and last M messages with a sliding window
    case slidingWindow
}
