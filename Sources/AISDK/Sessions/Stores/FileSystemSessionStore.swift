//
//  FileSystemSessionStore.swift
//  AISDK
//
//  File-based session store using one JSON file per session.
//

import Foundation

/// File-based session store for CLI tools and single-user apps.
///
/// Sessions are stored as individual JSON files in a directory.
/// Uses atomic writes for crash safety. Thread-safe via actor isolation.
public actor FileSystemSessionStore: SessionStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Create a file system session store.
    /// - Parameter directory: Directory to store session JSON files. Created automatically if needed.
    public init(directory: URL) throws {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - CRUD Operations

    public func create(_ session: AISession) async throws -> AISession {
        let fileURL = fileURL(for: session.id)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SessionStoreError.alreadyExists(sessionId: session.id)
        }
        try writeSession(session)
        return session
    }

    public func load(id: String) async throws -> AISession? {
        let fileURL = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(AISession.self, from: data)
        } catch {
            // Corrupted file — return nil rather than crashing
            return nil
        }
    }

    public func save(_ session: AISession) async throws {
        try writeSession(session)
    }

    public func delete(id: String) async throws {
        let fileURL = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SessionStoreError.notFound(sessionId: id)
        }
        try FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Query Operations

    public func list(
        userId: String,
        status: SessionStatus?,
        limit: Int,
        cursor: String?,
        orderBy: SessionOrderBy
    ) async throws -> SessionListResult {
        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ).filter { $0.pathExtension == "json" }

        // Decode all sessions (skip corrupted files)
        var sessions: [AISession] = fileURLs.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(AISession.self, from: data)
        }

        // Filter
        sessions = sessions.filter { $0.userId == userId }
        if let status = status {
            sessions = sessions.filter { $0.status == status }
        }

        // Sort (with id tiebreaker for deterministic ordering)
        switch orderBy {
        case .createdAtAsc:
            sessions.sort { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt }
        case .createdAtDesc:
            sessions.sort { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
        case .lastActivityAtAsc:
            sessions.sort { $0.lastActivityAt == $1.lastActivityAt ? $0.id < $1.id : $0.lastActivityAt < $1.lastActivityAt }
        case .lastActivityAtDesc:
            sessions.sort { $0.lastActivityAt == $1.lastActivityAt ? $0.id > $1.id : $0.lastActivityAt > $1.lastActivityAt }
        }

        // Pagination
        var startIndex = 0
        if let cursor = cursor,
           let cursorIdx = sessions.firstIndex(where: { $0.id == cursor }) {
            startIndex = sessions.distance(from: sessions.startIndex, to: cursorIdx) + 1
        }

        let totalCount = sessions.count
        let endIndex = min(startIndex + limit, totalCount)
        guard startIndex < totalCount else {
            return SessionListResult(sessions: [], nextCursor: nil, totalCount: totalCount)
        }

        let page = Array(sessions[startIndex..<endIndex])
        let nextCursor = endIndex < totalCount ? page.last?.id : nil

        return SessionListResult(
            sessions: page.map { $0.summary },
            nextCursor: nextCursor,
            totalCount: totalCount
        )
    }

    // MARK: - Incremental Updates

    public func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws {
        guard var session = try await load(id: sessionId) else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        session.messages.append(message)
        session.lastActivityAt = Date()
        try writeSession(session)
    }

    public func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws {
        guard var session = try await load(id: sessionId) else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        guard !session.messages.isEmpty else { return }
        session.messages[session.messages.count - 1] = message
        session.lastActivityAt = Date()
        try writeSession(session)
    }

    public func updateStatus(_ status: SessionStatus, forSession sessionId: String) async throws {
        guard var session = try await load(id: sessionId) else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        session.status = status
        session.lastActivityAt = Date()
        try writeSession(session)
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
        try writeSession(session)
    }

    // MARK: - Private

    private func fileURL(for sessionId: String) -> URL {
        directory.appendingPathComponent("\(sessionId).json")
    }

    private func writeSession(_ session: AISession) throws {
        let data = try encoder.encode(session)
        try data.write(to: fileURL(for: session.id), options: [.atomic])
    }
}
