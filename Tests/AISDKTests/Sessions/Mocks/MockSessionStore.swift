//
//  MockSessionStore.swift
//  AISDKTests
//
//  Mock session store for testing with operation recording.
//

import Foundation
@testable import AISDK

/// Mock session store for testing with operation recording
public actor MockSessionStore: SessionStore {
    // MARK: - Recorded Operations

    public private(set) var createCalls: [(AISession, Date)] = []
    public private(set) var loadCalls: [(String, Date)] = []
    public private(set) var saveCalls: [(AISession, Date)] = []
    public private(set) var deleteCalls: [(String, Date)] = []
    public private(set) var appendMessageCalls: [(AIMessage, String, Date)] = []
    public private(set) var updateLastMessageCalls: [(AIMessage, String, Date)] = []
    public private(set) var updateStatusCalls: [(SessionStatus, String, Date)] = []
    public private(set) var updateMetadataCalls: [(SessionMetadataUpdate, String, Date)] = []

    // MARK: - Configurable Behavior

    /// Sessions to return from load()
    public var sessions: [String: AISession] = [:]

    /// Error to throw on next operation (then cleared)
    public var nextError: Error?

    /// Delay to add to operations (for testing async behavior)
    public var operationDelay: Duration?

    // MARK: - Convenience Accessors

    public var saveCount: Int { saveCalls.count }
    public var lastSavedSession: AISession? { saveCalls.last?.0 }
    public var lastLoadedId: String? { loadCalls.last?.0 }

    public init() {}

    // MARK: - SessionStore Implementation

    public func create(_ session: AISession) async throws -> AISession {
        try await applyDelayAndError()
        createCalls.append((session, Date()))
        sessions[session.id] = session
        return session
    }

    public func load(id: String) async throws -> AISession? {
        try await applyDelayAndError()
        loadCalls.append((id, Date()))
        return sessions[id]
    }

    public func save(_ session: AISession) async throws {
        try await applyDelayAndError()
        saveCalls.append((session, Date()))
        sessions[session.id] = session
    }

    public func delete(id: String) async throws {
        try await applyDelayAndError()
        deleteCalls.append((id, Date()))
        sessions.removeValue(forKey: id)
    }

    public func list(
        userId: String,
        status: SessionStatus?,
        limit: Int,
        cursor: String?,
        orderBy: SessionOrderBy
    ) async throws -> SessionListResult {
        try await applyDelayAndError()
        let filtered = sessions.values
            .filter { $0.userId == userId }
            .filter { status == nil || $0.status == status }
            .map { $0.summary }
        return SessionListResult(sessions: Array(filtered.prefix(limit)))
    }

    public func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws {
        try await applyDelayAndError()
        appendMessageCalls.append((message, sessionId, Date()))
        sessions[sessionId]?.messages.append(message)
    }

    public func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws {
        try await applyDelayAndError()
        updateLastMessageCalls.append((message, sessionId, Date()))
        guard let count = sessions[sessionId]?.messages.count, count > 0 else { return }
        sessions[sessionId]?.messages[count - 1] = message
    }

    public func updateStatus(_ status: SessionStatus, forSession sessionId: String) async throws {
        try await applyDelayAndError()
        updateStatusCalls.append((status, sessionId, Date()))
        sessions[sessionId]?.status = status
    }

    public func updateMetadata(_ updates: SessionMetadataUpdate, forSession sessionId: String) async throws {
        try await applyDelayAndError()
        updateMetadataCalls.append((updates, sessionId, Date()))
        if let title = updates.title { sessions[sessionId]?.title = title }
        if let tags = updates.tags { sessions[sessionId]?.tags = tags }
        if let metadata = updates.metadata { sessions[sessionId]?.metadata = metadata }
        if let status = updates.status { sessions[sessionId]?.status = status }
    }

    // MARK: - Test Helpers

    /// Set a session directly (for test setup)
    public func setSession(_ session: AISession) {
        sessions[session.id] = session
    }

    /// Set the next error to throw
    public func setNextError(_ error: Error) {
        nextError = error
    }

    /// Reset all recorded operations
    public func reset() {
        createCalls = []
        loadCalls = []
        saveCalls = []
        deleteCalls = []
        appendMessageCalls = []
        updateLastMessageCalls = []
        updateStatusCalls = []
        updateMetadataCalls = []
        sessions = [:]
        nextError = nil
    }

    // MARK: - Private

    private func applyDelayAndError() async throws {
        if let delay = operationDelay {
            try await Task.sleep(for: delay)
        }
        if let error = nextError {
            nextError = nil
            throw error
        }
    }
}
