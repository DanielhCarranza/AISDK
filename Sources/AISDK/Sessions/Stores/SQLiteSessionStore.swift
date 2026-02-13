//
//  SQLiteSessionStore.swift
//  AISDK
//
//  SQLite-based session store using the system SQLite3 library.
//

#if canImport(SQLite3)
import Foundation
import SQLite3

/// SQLite-based session store for local persistence.
///
/// Uses a single table with JSON message storage for simplicity.
/// Supports efficient queries by userId, status, and timestamps.
/// Thread-safe via actor isolation with WAL mode for concurrent reads.
public actor SQLiteSessionStore: SessionStore {
    private let dbPath: String
    private var db: OpaquePointer?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // Prepared statement cache
    private var insertStmt: OpaquePointer?
    private var selectStmt: OpaquePointer?
    private var updateStmt: OpaquePointer?
    private var deleteStmt: OpaquePointer?
    private var selectMessagesStmt: OpaquePointer?
    private var updateMessagesStmt: OpaquePointer?

    /// Create a SQLite session store.
    /// - Parameter path: Path to SQLite database file. Use `:memory:` for in-memory database.
    public init(path: String = ":memory:") throws {
        self.dbPath = path
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        try openDatabase()
        try createSchema()
        try prepareStatements()
    }

    deinit {
        finalizeStatements()
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - CRUD Operations

    public func create(_ session: AISession) async throws -> AISession {
        // Check for duplicate
        if let existing = try await load(id: session.id), existing.id == session.id {
            throw SessionStoreError.alreadyExists(sessionId: session.id)
        }
        try insertSession(session)
        return session
    }

    public func load(id: String) async throws -> AISession? {
        guard let stmt = selectStmt else {
            throw SessionStoreError.unavailable(reason: "Database not initialized")
        }

        defer { sqlite3_reset(stmt) }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return try decodeSession(from: stmt)
    }

    public func save(_ session: AISession) async throws {
        // Upsert: delete then insert
        try deleteRow(id: session.id)
        try insertSession(session)
    }

    public func delete(id: String) async throws {
        guard let stmt = deleteStmt else {
            throw SessionStoreError.unavailable(reason: "Database not initialized")
        }

        defer { sqlite3_reset(stmt) }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)

        guard sqlite3_changes(db) > 0 else {
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
        // Build dynamic query
        var sql = "SELECT * FROM sessions WHERE user_id = ?"
        var params: [String] = [userId]

        if let status = status {
            sql += " AND status = ?"
            params.append(status.rawValue)
        }

        // Count total
        let countSQL = sql.replacingOccurrences(of: "SELECT *", with: "SELECT COUNT(*)")
        let totalCount = try executeCount(sql: countSQL, params: params)

        // Order
        let (orderColumn, orderDir) = orderClause(for: orderBy)
        let tiebreaker = orderDir == "ASC" ? "ASC" : "DESC"
        sql += " ORDER BY \(orderColumn) \(orderDir), id \(tiebreaker)"

        // Fetch all matching rows to handle cursor-based pagination
        sql += " LIMIT ?"
        params.append(String(totalCount))

        var allSessions = try executeQuery(sql: sql, params: params)

        // Apply cursor
        var startIndex = 0
        if let cursor = cursor,
           let cursorIdx = allSessions.firstIndex(where: { $0.id == cursor }) {
            startIndex = allSessions.distance(from: allSessions.startIndex, to: cursorIdx) + 1
        }

        let endIndex = min(startIndex + limit, allSessions.count)
        guard startIndex < allSessions.count else {
            return SessionListResult(sessions: [], nextCursor: nil, totalCount: totalCount)
        }

        let page = Array(allSessions[startIndex..<endIndex])
        let nextCursor = endIndex < allSessions.count ? page.last?.id : nil

        return SessionListResult(
            sessions: page.map { $0.summary },
            nextCursor: nextCursor,
            totalCount: totalCount
        )
    }

    // MARK: - Incremental Updates

    public func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws {
        guard var messages = try loadMessages(sessionId: sessionId) else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        messages.append(message)
        try updateMessages(messages, sessionId: sessionId)
        try updateLastActivity(sessionId: sessionId)
    }

    public func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws {
        guard var messages = try loadMessages(sessionId: sessionId) else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
        guard !messages.isEmpty else { return }
        messages[messages.count - 1] = message
        try updateMessages(messages, sessionId: sessionId)
        try updateLastActivity(sessionId: sessionId)
    }

    public func updateStatus(_ status: SessionStatus, forSession sessionId: String) async throws {
        let sql = "UPDATE sessions SET status = ?, last_activity_at = ? WHERE id = ?"
        try executeUpdate(sql: sql, params: [status.rawValue, iso8601String(Date()), sessionId])
        guard sqlite3_changes(db) > 0 else {
            throw SessionStoreError.notFound(sessionId: sessionId)
        }
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
        try deleteRow(id: sessionId)
        try insertSession(session)
    }

    // MARK: - Database Setup

    private func openDatabase() throws {
        // Create parent directory if needed (not for :memory:)
        if dbPath != ":memory:" {
            let dir = (dbPath as NSString).deletingLastPathComponent
            if !dir.isEmpty {
                try FileManager.default.createDirectory(
                    atPath: dir,
                    withIntermediateDirectories: true
                )
            }
        }

        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw SessionStoreError.unavailable(reason: "Cannot open database: \(msg)")
        }

        // Enable WAL mode for concurrent reads
        try execute("PRAGMA journal_mode=WAL")
        // Enable foreign keys
        try execute("PRAGMA foreign_keys=ON")
    }

    private func createSchema() throws {
        let createTable = """
        CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            agent_id TEXT,
            title TEXT,
            status TEXT NOT NULL DEFAULT 'active',
            created_at TEXT NOT NULL,
            last_activity_at TEXT NOT NULL,
            messages_json BLOB NOT NULL,
            checkpoints_json BLOB,
            metadata_json TEXT,
            tags_json TEXT,
            schema_version INTEGER NOT NULL DEFAULT 1,
            is_last_message_complete INTEGER NOT NULL DEFAULT 1,
            last_checkpoint_index INTEGER
        )
        """
        try execute(createTable)
        try execute("CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id)")
        try execute("CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(user_id, status)")
        try execute("CREATE INDEX IF NOT EXISTS idx_sessions_last_activity ON sessions(user_id, last_activity_at DESC)")
    }

    private func prepareStatements() throws {
        insertStmt = try prepare("""
            INSERT INTO sessions (
                id, user_id, agent_id, title, status, created_at, last_activity_at,
                messages_json, checkpoints_json, metadata_json, tags_json,
                schema_version, is_last_message_complete, last_checkpoint_index
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """)

        selectStmt = try prepare("SELECT * FROM sessions WHERE id = ?")
        deleteStmt = try prepare("DELETE FROM sessions WHERE id = ?")
        selectMessagesStmt = try prepare("SELECT messages_json FROM sessions WHERE id = ?")
        updateMessagesStmt = try prepare("UPDATE sessions SET messages_json = ? WHERE id = ?")
    }

    private func finalizeStatements() {
        [insertStmt, selectStmt, updateStmt, deleteStmt, selectMessagesStmt, updateMessagesStmt]
            .compactMap { $0 }
            .forEach { sqlite3_finalize($0) }
    }

    // MARK: - Row Operations

    private func insertSession(_ session: AISession) throws {
        guard let stmt = insertStmt else {
            throw SessionStoreError.unavailable(reason: "Database not initialized")
        }

        defer { sqlite3_reset(stmt) }

        let messagesData = try encoder.encode(session.messages)
        let checkpointsData = try encoder.encode(session.checkpoints)
        let metadataJSON = session.metadata.flatMap { try? encoder.encode($0) }
        let tagsJSON = session.tags.flatMap { try? encoder.encode($0) }

        sqlite3_bind_text(stmt, 1, (session.id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (session.userId as NSString).utf8String, -1, nil)
        bindOptionalText(stmt, 3, session.agentId)
        bindOptionalText(stmt, 4, session.title)
        sqlite3_bind_text(stmt, 5, (session.status.rawValue as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (iso8601String(session.createdAt) as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 7, (iso8601String(session.lastActivityAt) as NSString).utf8String, -1, nil)
        bindBlob(stmt, 8, messagesData)
        bindBlob(stmt, 9, checkpointsData)
        bindOptionalBlob(stmt, 10, metadataJSON)
        bindOptionalBlob(stmt, 11, tagsJSON)
        sqlite3_bind_int(stmt, 12, Int32(session.schemaVersion))
        sqlite3_bind_int(stmt, 13, session.isLastMessageComplete ? 1 : 0)
        if let idx = session.lastCheckpointIndex {
            sqlite3_bind_int(stmt, 14, Int32(idx))
        } else {
            sqlite3_bind_null(stmt, 14)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown"
            throw SessionStoreError.invalidData(reason: "Insert failed: \(msg)")
        }
    }

    private func decodeSession(from stmt: OpaquePointer) throws -> AISession {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let userId = String(cString: sqlite3_column_text(stmt, 1))
        let agentId = columnOptionalText(stmt, 2)
        let title = columnOptionalText(stmt, 3)
        let statusRaw = String(cString: sqlite3_column_text(stmt, 4))
        let createdAtStr = String(cString: sqlite3_column_text(stmt, 5))
        let lastActivityStr = String(cString: sqlite3_column_text(stmt, 6))

        let messagesData = columnBlob(stmt, 7)
        let checkpointsData = columnBlob(stmt, 8)
        let metadataData = columnOptionalBlob(stmt, 9)
        let tagsData = columnOptionalBlob(stmt, 10)
        let schemaVersion = Int(sqlite3_column_int(stmt, 11))
        let isLastMessageComplete = sqlite3_column_int(stmt, 12) != 0
        let lastCheckpointIndex: Int? = sqlite3_column_type(stmt, 13) == SQLITE_NULL
            ? nil
            : Int(sqlite3_column_int(stmt, 13))

        let messages = try decoder.decode([AIMessage].self, from: messagesData)
        let checkpoints = try decoder.decode([SessionCheckpoint].self, from: checkpointsData)
        let metadata: [String: String]? = metadataData.flatMap { try? decoder.decode([String: String].self, from: $0) }
        let tags: [String]? = tagsData.flatMap { try? decoder.decode([String].self, from: $0) }

        let status = SessionStatus(rawValue: statusRaw) ?? .active
        let createdAt = iso8601Date(createdAtStr) ?? Date()
        let lastActivityAt = iso8601Date(lastActivityStr) ?? Date()

        // Reconstruct using Codable round-trip data
        var session = AISession(
            id: id,
            userId: userId,
            agentId: agentId,
            title: title,
            messages: messages,
            metadata: metadata,
            tags: tags
        )

        // Override computed fields with stored values
        session.status = status
        session.checkpoints = checkpoints
        session.lastCheckpointIndex = lastCheckpointIndex
        session.isLastMessageComplete = isLastMessageComplete
        // createdAt and lastActivityAt are let properties set in init, so we need
        // a different approach — use Codable round-trip
        return try reconstructSession(
            id: id, userId: userId, agentId: agentId, title: title,
            status: status, createdAt: createdAt, lastActivityAt: lastActivityAt,
            messages: messages, checkpoints: checkpoints,
            metadata: metadata, tags: tags,
            schemaVersion: schemaVersion,
            isLastMessageComplete: isLastMessageComplete,
            lastCheckpointIndex: lastCheckpointIndex
        )
    }

    /// Reconstruct a session preserving all stored fields including `let` properties
    private func reconstructSession(
        id: String, userId: String, agentId: String?, title: String?,
        status: SessionStatus, createdAt: Date, lastActivityAt: Date,
        messages: [AIMessage], checkpoints: [SessionCheckpoint],
        metadata: [String: String]?, tags: [String]?,
        schemaVersion: Int, isLastMessageComplete: Bool, lastCheckpointIndex: Int?
    ) throws -> AISession {
        // Encode as JSON then decode — this preserves createdAt as a let property
        let json: [String: Any?] = [
            "id": id,
            "userId": userId,
            "agentId": agentId,
            "title": title,
            "status": status.rawValue,
            "createdAt": iso8601String(createdAt),
            "lastActivityAt": iso8601String(lastActivityAt),
            "schemaVersion": schemaVersion,
            "isLastMessageComplete": isLastMessageComplete,
            "lastCheckpointIndex": lastCheckpointIndex
        ]

        // For complex fields, encode them separately and compose
        let messagesData = try encoder.encode(messages)
        let checkpointsData = try encoder.encode(checkpoints)

        var dict = json.compactMapValues { $0 }
        // We'll use a different approach - encode/decode via the existing Codable
        let sessionData = try encoder.encode(
            CodableSessionProxy(
                id: id, userId: userId, agentId: agentId,
                createdAt: createdAt, lastActivityAt: lastActivityAt,
                title: title, tags: tags, metadata: metadata,
                messages: messages, status: status,
                checkpoints: checkpoints,
                lastCheckpointIndex: lastCheckpointIndex,
                isLastMessageComplete: isLastMessageComplete,
                schemaVersion: schemaVersion
            )
        )
        return try decoder.decode(AISession.self, from: sessionData)
    }

    // MARK: - Messages Operations

    private func loadMessages(sessionId: String) throws -> [AIMessage]? {
        guard let stmt = selectMessagesStmt else { return nil }
        defer { sqlite3_reset(stmt) }

        sqlite3_bind_text(stmt, 1, (sessionId as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let data = columnBlob(stmt, 0)
        return try decoder.decode([AIMessage].self, from: data)
    }

    private func updateMessages(_ messages: [AIMessage], sessionId: String) throws {
        guard let stmt = updateMessagesStmt else { return }
        defer { sqlite3_reset(stmt) }

        let data = try encoder.encode(messages)
        bindBlob(stmt, 1, data)
        sqlite3_bind_text(stmt, 2, (sessionId as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    private func updateLastActivity(sessionId: String) throws {
        try executeUpdate(
            sql: "UPDATE sessions SET last_activity_at = ? WHERE id = ?",
            params: [iso8601String(Date()), sessionId]
        )
    }

    // MARK: - SQL Helpers

    private func execute(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK else {
            let msg = errMsg.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errMsg)
            throw SessionStoreError.unavailable(reason: "SQL error: \(msg)")
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown"
            throw SessionStoreError.unavailable(reason: "Prepare failed: \(msg)")
        }
        return stmt
    }

    private func executeCount(sql: String, params: [String]) throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        for (i, param) in params.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (param as NSString).utf8String, -1, nil)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func executeQuery(sql: String, params: [String]) throws -> [AISession] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            return []
        }
        for (i, param) in params.enumerated() {
            sqlite3_bind_text(s, Int32(i + 1), (param as NSString).utf8String, -1, nil)
        }

        var results: [AISession] = []
        while sqlite3_step(s) == SQLITE_ROW {
            if let session = try? decodeSession(from: s) {
                results.append(session)
            }
        }
        return results
    }

    private func executeUpdate(sql: String, params: [String]) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown"
            throw SessionStoreError.unavailable(reason: "Prepare failed: \(msg)")
        }
        for (i, param) in params.enumerated() {
            sqlite3_bind_text(s, Int32(i + 1), (param as NSString).utf8String, -1, nil)
        }
        sqlite3_step(s)
    }

    private func deleteRow(id: String) throws {
        guard let stmt = deleteStmt else { return }
        defer { sqlite3_reset(stmt) }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }

    private func orderClause(for orderBy: SessionOrderBy) -> (String, String) {
        switch orderBy {
        case .createdAtAsc: return ("created_at", "ASC")
        case .createdAtDesc: return ("created_at", "DESC")
        case .lastActivityAtAsc: return ("last_activity_at", "ASC")
        case .lastActivityAtDesc: return ("last_activity_at", "DESC")
        }
    }

    // MARK: - SQLite Binding Helpers

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value = value {
            sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func bindBlob(_ stmt: OpaquePointer?, _ index: Int32, _ data: Data) {
        _ = data.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, index, ptr.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }

    private func bindOptionalBlob(_ stmt: OpaquePointer?, _ index: Int32, _ data: Data?) {
        if let data = data {
            bindBlob(stmt, index, data)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func columnOptionalText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return String(cString: sqlite3_column_text(stmt, index))
    }

    private func columnBlob(_ stmt: OpaquePointer, _ index: Int32) -> Data {
        let bytes = sqlite3_column_blob(stmt, index)
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard let bytes = bytes, count > 0 else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    private func columnOptionalBlob(_ stmt: OpaquePointer, _ index: Int32) -> Data? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return columnBlob(stmt, index)
    }

    // MARK: - Date Helpers

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func iso8601String(_ date: Date) -> String {
        Self.iso8601Formatter.string(from: date)
    }

    private func iso8601Date(_ string: String) -> Date? {
        Self.iso8601Formatter.date(from: string)
    }
}

// MARK: - Codable Proxy for Session Reconstruction

/// Internal proxy used to reconstruct AISession from SQLite columns,
/// preserving `let` properties like `createdAt`.
private struct CodableSessionProxy: Codable {
    let id: String
    let userId: String
    let agentId: String?
    let createdAt: Date
    let lastActivityAt: Date
    let title: String?
    let tags: [String]?
    let metadata: [String: String]?
    let messages: [AIMessage]
    let status: SessionStatus
    let checkpoints: [SessionCheckpoint]
    let lastCheckpointIndex: Int?
    let isLastMessageComplete: Bool
    let schemaVersion: Int
}

#endif
