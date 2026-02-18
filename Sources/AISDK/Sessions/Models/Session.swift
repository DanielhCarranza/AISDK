//
//  Session.swift
//  AISDK
//
//  A conversation session containing all state for an agent interaction.
//

import Foundation

/// A conversation session containing all state for an agent interaction.
///
/// Sessions are the primary unit of persistence in AISDK. They contain:
/// - Complete message history (including tool calls and results)
/// - Metadata (title, tags, timestamps)
/// - Checkpoint information for resume/rewind
/// - Agent attribution for multi-agent scenarios
public struct AISession: Codable, Sendable, Identifiable, Hashable, Equatable {
    // MARK: - Identity

    /// Unique identifier for this session
    public let id: String

    /// User who owns this session (required for multi-session support)
    public let userId: String

    /// Optional agent identifier (for multi-agent attribution)
    public var agentId: String?

    // MARK: - Timestamps

    /// When the session was created
    public let createdAt: Date

    /// Last activity timestamp (updated on each message)
    public var lastActivityAt: Date

    // MARK: - Metadata

    /// Human-readable title (auto-generated on first user message)
    public var title: String?

    /// Optional tags for organization
    public var tags: [String]?

    /// Arbitrary metadata for application use
    public var metadata: [String: String]?

    // MARK: - Content

    /// Complete message history including tool calls and results.
    /// This is the canonical conversation state.
    public var messages: [AIMessage]

    // MARK: - State

    /// Current session status
    public var status: SessionStatus

    /// Checkpoints for resume/rewind
    public var checkpoints: [SessionCheckpoint]

    /// Index of the last complete checkpoint (for resume)
    public var lastCheckpointIndex: Int?

    /// Whether the last assistant message is complete
    public var isLastMessageComplete: Bool

    // MARK: - Versioning

    /// Schema version for migration support
    public let schemaVersion: Int

    // MARK: - Initialization

    public init(
        id: String = UUID().uuidString,
        userId: String,
        agentId: String? = nil,
        title: String? = nil,
        messages: [AIMessage] = [],
        metadata: [String: String]? = nil,
        tags: [String]? = nil
    ) {
        self.id = id
        self.userId = userId
        self.agentId = agentId
        self.createdAt = Date()
        self.lastActivityAt = Date()
        self.title = title
        self.messages = messages
        self.metadata = metadata
        self.tags = tags
        self.status = .active
        self.checkpoints = []
        self.lastCheckpointIndex = nil
        self.isLastMessageComplete = true
        self.schemaVersion = 1
    }

    // MARK: - Hashable (uses id only for identity)

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: AISession, rhs: AISession) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - CodingKeys

    private enum CodingKeys: String, CodingKey {
        case id, userId, agentId, createdAt, lastActivityAt
        case title, tags, metadata, messages, status
        case checkpoints, lastCheckpointIndex, isLastMessageComplete
        case schemaVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.lastActivityAt = try container.decode(Date.self, forKey: .lastActivityAt)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags)
        self.metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
        self.messages = try container.decodeIfPresent([AIMessage].self, forKey: .messages) ?? []
        self.status = try container.decodeIfPresent(SessionStatus.self, forKey: .status) ?? .active
        self.checkpoints = try container.decodeIfPresent([SessionCheckpoint].self, forKey: .checkpoints) ?? []
        self.lastCheckpointIndex = try container.decodeIfPresent(Int.self, forKey: .lastCheckpointIndex)
        self.isLastMessageComplete = try container.decodeIfPresent(Bool.self, forKey: .isLastMessageComplete) ?? true
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}

// MARK: - Factory Methods

extension AISession {
    /// Create and persist a new session
    public static func create(
        userId: String,
        store: SessionStore,
        agentId: String? = nil,
        title: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> AISession {
        let session = AISession(
            userId: userId,
            agentId: agentId,
            title: title,
            metadata: metadata
        )
        return try await store.create(session)
    }

    /// Load an existing session
    public static func load(id: String, store: SessionStore) async throws -> AISession? {
        try await store.load(id: id)
    }
}

// MARK: - Checkpoint Management

extension AISession {
    /// Create a checkpoint at the current message position
    public mutating func createCheckpoint(type: CheckpointType, label: String? = nil) {
        let checkpoint = SessionCheckpoint(
            index: checkpoints.count,
            messageIndex: messages.count - 1,
            createdAt: Date(),
            type: type,
            label: label
        )
        checkpoints.append(checkpoint)
        lastCheckpointIndex = checkpoint.index

        // Mark the message as a checkpoint
        if messages.indices.contains(checkpoint.messageIndex) {
            messages[checkpoint.messageIndex].isCheckpoint = true
            messages[checkpoint.messageIndex].checkpointIndex = checkpoint.index
        }
    }

    /// Get messages up to a specific checkpoint
    public func messagesAtCheckpoint(_ checkpointIndex: Int) -> [AIMessage] {
        guard let checkpoint = checkpoints.first(where: { $0.index == checkpointIndex }),
              checkpoint.messageIndex >= 0,
              checkpoint.messageIndex < messages.count else {
            return messages
        }
        return Array(messages.prefix(checkpoint.messageIndex + 1))
    }

    /// Rewind session to a checkpoint
    public mutating func rewind(to checkpointIndex: Int) {
        guard let checkpoint = checkpoints.first(where: { $0.index == checkpointIndex }),
              checkpoint.messageIndex >= 0,
              checkpoint.messageIndex < messages.count else { return }

        messages = Array(messages.prefix(checkpoint.messageIndex + 1))
        // Remove checkpoints after the rewind point
        checkpoints = checkpoints.filter { $0.index <= checkpointIndex }
        lastCheckpointIndex = checkpointIndex
        isLastMessageComplete = true
        lastActivityAt = Date()
    }

    /// Fork this session for a handoff (creates a new session with copied messages)
    public func fork(newUserId: String? = nil) -> AISession {
        var forked = AISession(
            userId: newUserId ?? userId,
            agentId: agentId,
            title: title.map { "\($0) (fork)" },
            messages: messages,
            metadata: metadata,
            tags: tags
        )
        forked.checkpoints = checkpoints
        forked.lastCheckpointIndex = lastCheckpointIndex
        return forked
    }
}

// MARK: - SessionStatus

/// Status of a session
public enum SessionStatus: String, Codable, Sendable {
    /// Session is active and accepting messages
    case active

    /// Session completed normally
    case completed

    /// Session paused (can be resumed)
    case paused

    /// Session ended with an error
    case error

    /// Session archived (read-only)
    case archived
}

// MARK: - SessionCheckpoint

/// Represents a restorable point in the conversation
public struct SessionCheckpoint: Codable, Sendable, Hashable {
    /// Index of this checkpoint
    public let index: Int

    /// Message index in the session
    public let messageIndex: Int

    /// Timestamp when checkpoint was created
    public let createdAt: Date

    /// Type of checkpoint
    public let type: CheckpointType

    /// Optional label for the checkpoint
    public var label: String?

    public init(
        index: Int,
        messageIndex: Int,
        createdAt: Date = Date(),
        type: CheckpointType,
        label: String? = nil
    ) {
        self.index = index
        self.messageIndex = messageIndex
        self.createdAt = createdAt
        self.type = type
        self.label = label
    }
}

/// Type of checkpoint
public enum CheckpointType: String, Codable, Sendable {
    case userMessage
    case toolCallComplete
    case assistantComplete
    case manual
}
