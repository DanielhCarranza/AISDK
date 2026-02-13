//
//  AgentHandoff.swift
//  AISDK
//
//  Types for multi-agent session handoffs and subagent configuration.
//

import Foundation

/// Configuration for handing off a session between agents.
///
/// Supports three modes: shared (same session), forked (copy), or independent (new session).
public struct AgentHandoff: Codable, Sendable {
    /// The agent to hand off to
    public let targetAgentId: String

    /// How the session is transferred
    public let mode: HandoffMode

    /// Optional message to include with the handoff
    public let message: String?

    /// Metadata to pass along with the handoff
    public let metadata: [String: String]?

    public init(
        targetAgentId: String,
        mode: HandoffMode = .shared,
        message: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.targetAgentId = targetAgentId
        self.mode = mode
        self.message = message
        self.metadata = metadata
    }
}

/// Mode for session handoff between agents
public enum HandoffMode: String, Codable, Sendable {
    /// Both agents share the same session
    case shared

    /// The session is forked (copied) for the target agent
    case forked

    /// A new independent session is created for the target agent
    case independent
}

/// Configuration for subagent execution within a session.
public struct SubagentOptions: Codable, Sendable {
    /// How the subagent's session relates to the parent
    public let sessionMode: HandoffMode

    /// Maximum number of steps the subagent can take
    public let maxSteps: Int?

    /// Whether to include the subagent's messages in the parent session
    public let includeMessagesInParent: Bool

    public init(
        sessionMode: HandoffMode = .forked,
        maxSteps: Int? = nil,
        includeMessagesInParent: Bool = true
    ) {
        self.sessionMode = sessionMode
        self.maxSteps = maxSteps
        self.includeMessagesInParent = includeMessagesInParent
    }
}
