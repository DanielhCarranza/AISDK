//
//  SearchableSessionStore.swift
//  AISDK
//
//  Protocol for session stores that support full-text search.
//

import Foundation

/// Protocol for session stores that support full-text search.
///
/// Extends `SessionStore` with search capabilities. Implementations
/// should use efficient text indexing (e.g., SQLite FTS5).
public protocol SearchableSessionStore: SessionStore {
    /// Search sessions by query string.
    ///
    /// - Parameters:
    ///   - query: The search query string.
    ///   - userId: Filter results to this user.
    ///   - limit: Maximum number of results to return.
    /// - Returns: Array of search results with relevance info.
    func search(
        query: String,
        userId: String,
        limit: Int
    ) async throws -> [SessionSearchResult]
}

/// A search result with relevance information.
public struct SessionSearchResult: Codable, Sendable {
    /// The matching session summary
    public let session: SessionSummary

    /// Text snippet showing the match context
    public let snippet: String?

    /// Relevance score (higher = more relevant)
    public let relevanceScore: Double?

    public init(session: SessionSummary, snippet: String? = nil, relevanceScore: Double? = nil) {
        self.session = session
        self.snippet = snippet
        self.relevanceScore = relevanceScore
    }
}
