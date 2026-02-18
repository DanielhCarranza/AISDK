//
//  SessionListViewModel.swift
//  AISDK
//
//  Observable ViewModel for listing and managing sessions.
//

import Foundation

/// Observable ViewModel for browsing, creating, and deleting sessions.
///
/// Provides pagination, filtering, and CRUD operations for session lists.
@Observable
@MainActor
public final class SessionListViewModel {
    // MARK: - Published State

    /// Current page of session summaries
    public private(set) var sessions: [SessionSummary] = []

    /// Total number of sessions matching the current filter
    public private(set) var totalCount: Int = 0

    /// Whether a load operation is in progress
    public private(set) var isLoading: Bool = false

    /// Whether more pages are available
    public private(set) var hasMore: Bool = false

    /// The most recent error
    public private(set) var error: Error?

    // MARK: - Dependencies

    private let store: any SessionStore
    private let userId: String
    private let pageSize: Int

    private var nextCursor: String?
    private var currentStatus: SessionStatus?
    private var currentOrderBy: SessionOrderBy = .lastActivityAtDesc

    // MARK: - Initialization

    /// Create a session list ViewModel.
    /// - Parameters:
    ///   - store: The session store to query.
    ///   - userId: The user whose sessions to list.
    ///   - pageSize: Number of sessions per page (default: 20).
    public init(store: any SessionStore, userId: String, pageSize: Int = 20) {
        self.store = store
        self.userId = userId
        self.pageSize = pageSize
    }

    // MARK: - Loading

    /// Load the first page of sessions.
    public func loadSessions(
        status: SessionStatus? = nil,
        orderBy: SessionOrderBy = .lastActivityAtDesc
    ) async {
        currentStatus = status
        currentOrderBy = orderBy
        nextCursor = nil
        sessions = []
        error = nil

        await fetchPage()
    }

    /// Load the next page of sessions (if available).
    public func loadMore() async {
        guard hasMore, !isLoading else { return }
        await fetchPage()
    }

    /// Refresh the current list from scratch.
    public func refresh() async {
        await loadSessions(status: currentStatus, orderBy: currentOrderBy)
    }

    // MARK: - CRUD

    /// Create a new session.
    @discardableResult
    public func createSession(title: String? = nil, metadata: [String: String]? = nil) async throws -> AISession {
        let session = AISession(userId: userId, title: title, metadata: metadata)
        let created = try await store.create(session)
        await refresh()
        return created
    }

    /// Delete a session by ID.
    public func deleteSession(id: String) async throws {
        try await store.delete(id: id)
        sessions.removeAll { $0.id == id }
        totalCount = max(totalCount - 1, 0)
    }

    // MARK: - Private

    private func fetchPage() async {
        isLoading = true
        error = nil

        do {
            let result = try await store.list(
                userId: userId,
                status: currentStatus,
                limit: pageSize,
                cursor: nextCursor,
                orderBy: currentOrderBy
            )

            sessions.append(contentsOf: result.sessions)
            totalCount = result.totalCount ?? sessions.count
            nextCursor = result.nextCursor
            hasMore = result.nextCursor != nil
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
