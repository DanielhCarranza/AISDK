//
//  InMemorySessionStore.swift
//  AISDK
//
//  In-memory session store for testing, prototyping, and ephemeral use cases.
//

import Foundation

/// In-memory session store for testing and development.
///
/// All data is lost when the process terminates.
/// Thread-safe via actor isolation.
public actor InMemorySessionStore: SessionStore {
    private var sessions: [String: AISession] = [:]

    public init() {}

    // MARK: - CRUD Operations

    public func create(_ session: AISession) async throws -> AISession {
        guard sessions[session.id] == nil else {
            throw SessionStoreError.alreadyExists(sessionId: session.id)
        }
        sessions[session.id] = session
        return session
    }

    public func load(id: String) async throws -> AISession? {
        sessions[id]
    }

    public func save(_ session: AISession) async throws {
        sessions[session.id] = session
    }

    public func delete(id: String) async throws {
        guard sessions.removeValue(forKey: id) != nil else {
            throw SessionStoreError.notFound(sessionId: id)
        }
    }

    // MARK: - Query Operations

    public func list(
        userId: String,
        status: SessionStatus?,
        limit: Int,
        cursor: String?,
        orderBy: SessionOrderBy
    ) async throws -> SessionListResult {
        var filtered = sessions.values.filter { $0.userId == userId }

        if let status = status {
            filtered = filtered.filter { $0.status == status }
        }

        // Sort (with id tiebreaker for deterministic ordering)
        switch orderBy {
        case .createdAtAsc:
            filtered.sort { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
        case .createdAtDesc:
            filtered.sort { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
        case .lastActivityAtAsc:
            filtered.sort { $0.lastActivityAt == $1.lastActivityAt ? $0.id < $1.id : $0.lastActivityAt < $1.lastActivityAt }
        case .lastActivityAtDesc:
            filtered.sort { $0.lastActivityAt == $1.lastActivityAt ? $0.id > $1.id : $0.lastActivityAt > $1.lastActivityAt }
        }

        // Pagination
        var startIndex = 0
        if let cursor = cursor,
           let cursorIndex = filtered.firstIndex(where: { $0.id == cursor }) {
            startIndex = filtered.distance(from: filtered.startIndex, to: cursorIndex) + 1
        }

        let endIndex = min(startIndex + limit, filtered.count)
        guard startIndex < filtered.count else {
            return SessionListResult(sessions: [], nextCursor: nil, totalCount: filtered.count)
        }

        let page = Array(filtered[startIndex..<endIndex])
        let nextCursor = endIndex < filtered.count ? page.last?.id : nil

        return SessionListResult(
            sessions: page.map { $0.summary },
            nextCursor: nextCursor,
            totalCount: filtered.count
        )
    }

    // MARK: - Incremental Updates (optimized, no load+save round-trip)

    public func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws {
        guard sessions[sessionId] != nil else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        sessions[sessionId]!.messages.append(message)
        sessions[sessionId]!.lastActivityAt = Date()
    }

    public func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws {
        guard sessions[sessionId] != nil else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        guard !sessions[sessionId]!.messages.isEmpty else { return }
        sessions[sessionId]!.messages[sessions[sessionId]!.messages.count - 1] = message
        sessions[sessionId]!.lastActivityAt = Date()
    }

    public func updateStatus(_ status: SessionStatus, forSession sessionId: String) async throws {
        guard sessions[sessionId] != nil else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        sessions[sessionId]!.status = status
        sessions[sessionId]!.lastActivityAt = Date()
    }

    public func updateMetadata(_ updates: SessionMetadataUpdate, forSession sessionId: String) async throws {
        guard sessions[sessionId] != nil else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        if let title = updates.title { sessions[sessionId]!.title = title }
        if let tags = updates.tags { sessions[sessionId]!.tags = tags }
        if let metadata = updates.metadata { sessions[sessionId]!.metadata = metadata }
        if let status = updates.status { sessions[sessionId]!.status = status }
        sessions[sessionId]!.lastActivityAt = Date()
    }
}
