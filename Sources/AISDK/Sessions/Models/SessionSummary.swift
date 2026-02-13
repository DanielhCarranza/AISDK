//
//  SessionSummary.swift
//  AISDK
//
//  Lightweight session types for listing and pagination.
//

import Foundation

/// Sort order for session listing
public enum SessionOrderBy: String, Codable, Sendable {
    case createdAtAsc
    case createdAtDesc
    case lastActivityAtAsc
    case lastActivityAtDesc
}

/// Paginated session list result
public struct SessionListResult: Codable, Sendable {
    /// Session summaries (not full message history)
    public let sessions: [SessionSummary]

    /// Cursor for next page (nil if no more results)
    public let nextCursor: String?

    /// Total count (if available)
    public let totalCount: Int?

    public init(sessions: [SessionSummary], nextCursor: String? = nil, totalCount: Int? = nil) {
        self.sessions = sessions
        self.nextCursor = nextCursor
        self.totalCount = totalCount
    }
}

/// Lightweight session summary for listing
public struct SessionSummary: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let userId: String
    public let title: String?
    public let status: SessionStatus
    public let createdAt: Date
    public let lastActivityAt: Date
    public let messageCount: Int
    public let tags: [String]?

    public init(
        id: String,
        userId: String,
        title: String?,
        status: SessionStatus,
        createdAt: Date,
        lastActivityAt: Date,
        messageCount: Int,
        tags: [String]?
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.status = status
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.messageCount = messageCount
        self.tags = tags
    }
}

// MARK: - AISession -> SessionSummary Conversion

extension AISession {
    /// Create a lightweight summary from this session
    public var summary: SessionSummary {
        SessionSummary(
            id: id,
            userId: userId,
            title: title,
            status: status,
            createdAt: createdAt,
            lastActivityAt: lastActivityAt,
            messageCount: messages.count,
            tags: tags
        )
    }
}
