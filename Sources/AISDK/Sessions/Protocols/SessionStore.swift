//
//  SessionStore.swift
//  AISDK
//
//  Protocol for session persistence backends.
//

import Foundation

/// Protocol for session persistence backends.
///
/// Implementations must be thread-safe and handle concurrent access.
/// All operations are async to support network-backed stores.
public protocol SessionStore: Sendable {
    // MARK: - CRUD Operations

    /// Create a new session
    /// - Parameter session: The session to create
    /// - Returns: The created session (may have server-generated fields)
    func create(_ session: AISession) async throws -> AISession

    /// Load a session by ID
    /// - Parameter id: Session identifier
    /// - Returns: The session if found, nil otherwise
    func load(id: String) async throws -> AISession?

    /// Save (update) an existing session
    /// - Parameter session: The session to save
    func save(_ session: AISession) async throws

    /// Delete a session
    /// - Parameter id: Session identifier
    func delete(id: String) async throws

    // MARK: - Query Operations

    /// List sessions with filtering and pagination
    func list(
        userId: String,
        status: SessionStatus?,
        limit: Int,
        cursor: String?,
        orderBy: SessionOrderBy
    ) async throws -> SessionListResult

    // MARK: - Incremental Updates (for streaming)

    /// Append a message to a session (optimized for streaming)
    func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws

    /// Update the last message in a session (for streaming deltas)
    func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws

    /// Update session status
    func updateStatus(_ status: SessionStatus, forSession sessionId: String) async throws

    /// Update session metadata (title, tags, etc.)
    func updateMetadata(_ updates: SessionMetadataUpdate, forSession sessionId: String) async throws

    // MARK: - Real-time (optional)

    /// Subscribe to session changes (for real-time UI updates)
    /// Returns nil if observation is not supported by this store.
    func observe(sessionId: String) -> AsyncThrowingStream<AISession, Error>?
}

// MARK: - Default Implementations

/// Default implementations reduce burden on simple store implementers.
/// Optimized stores should override these with native implementations.
extension SessionStore {
    public func observe(sessionId: String) -> AsyncThrowingStream<AISession, Error>? {
        nil
    }

    public func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws {
        guard var session = try await load(id: sessionId) else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        session.messages.append(message)
        session.lastActivityAt = Date()
        try await save(session)
    }

    public func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws {
        guard var session = try await load(id: sessionId) else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        guard !session.messages.isEmpty else { return }
        session.messages[session.messages.count - 1] = message
        session.lastActivityAt = Date()
        try await save(session)
    }

    public func updateStatus(_ status: SessionStatus, forSession sessionId: String) async throws {
        guard var session = try await load(id: sessionId) else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        session.status = status
        session.lastActivityAt = Date()
        try await save(session)
    }

    public func updateMetadata(_ updates: SessionMetadataUpdate, forSession sessionId: String) async throws {
        guard var session = try await load(id: sessionId) else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        if let title = updates.title { session.title = title }
        if let tags = updates.tags { session.tags = tags }
        if let metadata = updates.metadata { session.metadata = metadata }
        if let status = updates.status { session.status = status }
        session.lastActivityAt = Date()
        try await save(session)
    }
}
