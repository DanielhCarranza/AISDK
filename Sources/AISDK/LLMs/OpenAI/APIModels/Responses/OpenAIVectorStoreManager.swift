//
//  OpenAIVectorStoreManager.swift
//  AISDK
//
//  Vector store management for OpenAI Responses API
//  Supports CRUD operations and semantic search for RAG workflows
//

import Foundation

// MARK: - OpenAIVectorStoreManager

/// Actor-based vector store manager for OpenAI vector store operations
///
/// Provides thread-safe vector store management operations for use with
/// the file_search tool in the Responses API.
///
/// Example:
/// ```swift
/// let vectorStoreManager = OpenAIVectorStoreManager(apiKey: "sk-...")
///
/// // Create a vector store with files
/// let vectorStore = try await vectorStoreManager.create(
///     name: "Swift Documentation",
///     fileIds: [fileId1, fileId2],
///     expiresAfter: .afterInactivity(days: 30)
/// )
///
/// // Search the vector store
/// let results = try await vectorStoreManager.search(
///     id: vectorStore.id,
///     query: .text("How do I create a SwiftUI view?"),
///     maxNumResults: 5
/// )
///
/// // Delete the vector store
/// try await vectorStoreManager.delete(id: vectorStore.id)
/// ```
public actor OpenAIVectorStoreManager {
    private let baseURL = "https://api.openai.com/v1/vector_stores"
    private let apiKey: String
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Create

    /// Create a new vector store
    ///
    /// - Parameters:
    ///   - name: Optional name for the vector store
    ///   - description: Optional description
    ///   - fileIds: Optional list of file IDs to add
    ///   - chunkingStrategy: Optional chunking strategy for file processing
    ///   - expiresAfter: Optional expiration policy
    ///   - metadata: Optional metadata key-value pairs
    /// - Returns: The created vector store
    /// - Throws: `AISDKErrorV2` if creation fails
    public func create(
        name: String? = nil,
        description: String? = nil,
        fileIds: [String]? = nil,
        chunkingStrategy: ChunkingStrategy? = nil,
        expiresAfter: VectorStoreExpiration? = nil,
        metadata: [String: String]? = nil
    ) async throws -> VectorStore {
        var request = makeRequest(url: URL(string: baseURL)!, method: "POST")

        let body = CreateVectorStoreRequest(
            name: name,
            description: description,
            fileIds: fileIds,
            chunkingStrategy: chunkingStrategy,
            expiresAfter: expiresAfter,
            metadata: metadata
        )
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(VectorStore.self, from: data)
    }

    // MARK: - List

    /// List vector stores with pagination
    ///
    /// - Parameters:
    ///   - limit: Maximum number of results (default: 20)
    ///   - after: Cursor for forward pagination
    ///   - before: Cursor for backward pagination
    ///   - order: Sort order (default: descending by creation time)
    /// - Returns: List of vector stores
    /// - Throws: `AISDKErrorV2` if the request fails
    public func list(
        limit: Int = 20,
        after: String? = nil,
        before: String? = nil,
        order: SortOrder = .desc
    ) async throws -> VectorStoreList {
        var components = URLComponents(string: baseURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order", value: order.rawValue)
        ]
        if let after = after { queryItems.append(URLQueryItem(name: "after", value: after)) }
        if let before = before { queryItems.append(URLQueryItem(name: "before", value: before)) }
        components.queryItems = queryItems

        let request = makeRequest(url: components.url!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(VectorStoreList.self, from: data)
    }

    // MARK: - Retrieve

    /// Retrieve a vector store by ID
    ///
    /// - Parameter id: The vector store ID
    /// - Returns: The vector store
    /// - Throws: `AISDKErrorV2` if not found or request fails
    public func retrieve(id: String) async throws -> VectorStore {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(id)")!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(VectorStore.self, from: data)
    }

    // MARK: - Update

    /// Update a vector store
    ///
    /// - Parameters:
    ///   - id: The vector store ID
    ///   - name: New name (optional)
    ///   - description: New description (optional)
    ///   - expiresAfter: New expiration policy (optional)
    ///   - metadata: New metadata (optional)
    /// - Returns: The updated vector store
    /// - Throws: `AISDKErrorV2` if update fails
    public func update(
        id: String,
        name: String? = nil,
        description: String? = nil,
        expiresAfter: VectorStoreExpiration? = nil,
        metadata: [String: String]? = nil
    ) async throws -> VectorStore {
        var request = makeRequest(url: URL(string: "\(baseURL)/\(id)")!, method: "POST")

        let body = UpdateVectorStoreRequest(
            name: name,
            description: description,
            expiresAfter: expiresAfter,
            metadata: metadata
        )
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(VectorStore.self, from: data)
    }

    // MARK: - Delete

    /// Delete a vector store
    ///
    /// - Parameter id: The vector store ID to delete
    /// - Returns: Deletion status
    /// - Throws: `AISDKErrorV2` if deletion fails
    public func delete(id: String) async throws -> DeletionStatus {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(id)")!, method: "DELETE")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(DeletionStatus.self, from: data)
    }

    // MARK: - Search

    /// Search a vector store for relevant content
    ///
    /// - Parameters:
    ///   - id: The vector store ID
    ///   - query: Text or vector query
    ///   - maxNumResults: Maximum results to return (default: 10)
    ///   - filters: Optional filters for narrowing results
    ///   - rankingOptions: Optional ranking configuration
    ///   - rewriteQuery: Whether to let OpenAI optimize the query (default: false)
    /// - Returns: Search results with relevance scores
    /// - Throws: `AISDKErrorV2` if search fails
    public func search(
        id: String,
        query: VectorStoreQuery,
        maxNumResults: Int = 10,
        filters: VectorStoreFilters? = nil,
        rankingOptions: RankingOptions? = nil,
        rewriteQuery: Bool = false
    ) async throws -> VectorStoreSearchResults {
        var request = makeRequest(url: URL(string: "\(baseURL)/\(id)/search")!, method: "POST")

        let body = VectorStoreSearchRequest(
            query: query,
            maxNumResults: maxNumResults,
            filters: filters,
            rankingOptions: rankingOptions,
            rewriteQuery: rewriteQuery
        )
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(VectorStoreSearchResults.self, from: data)
    }

    // MARK: - File Operations

    /// Add a file to a vector store
    ///
    /// - Parameters:
    ///   - vectorStoreId: The vector store ID
    ///   - fileId: The file ID to add
    ///   - chunkingStrategy: Optional chunking strategy
    /// - Returns: The vector store file object
    /// - Throws: `AISDKErrorV2` if the operation fails
    public func addFile(
        vectorStoreId: String,
        fileId: String,
        chunkingStrategy: ChunkingStrategy? = nil
    ) async throws -> VectorStoreFile {
        var request = makeRequest(url: URL(string: "\(baseURL)/\(vectorStoreId)/files")!, method: "POST")

        let body = AddFileRequest(fileId: fileId, chunkingStrategy: chunkingStrategy)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(VectorStoreFile.self, from: data)
    }

    /// List files in a vector store
    ///
    /// - Parameters:
    ///   - vectorStoreId: The vector store ID
    ///   - limit: Maximum results (default: 20)
    ///   - after: Cursor for forward pagination
    ///   - before: Cursor for backward pagination
    ///   - order: Sort order (default: descending)
    ///   - filter: Optional status filter
    /// - Returns: List of vector store files
    /// - Throws: `AISDKErrorV2` if the request fails
    public func listFiles(
        vectorStoreId: String,
        limit: Int = 20,
        after: String? = nil,
        before: String? = nil,
        order: SortOrder = .desc,
        filter: VectorStoreFileStatus? = nil
    ) async throws -> VectorStoreFileList {
        var components = URLComponents(string: "\(baseURL)/\(vectorStoreId)/files")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order", value: order.rawValue)
        ]
        if let after = after { queryItems.append(URLQueryItem(name: "after", value: after)) }
        if let before = before { queryItems.append(URLQueryItem(name: "before", value: before)) }
        if let filter = filter { queryItems.append(URLQueryItem(name: "filter", value: filter.rawValue)) }
        components.queryItems = queryItems

        let request = makeRequest(url: components.url!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(VectorStoreFileList.self, from: data)
    }

    /// Retrieve a specific file from a vector store
    ///
    /// - Parameters:
    ///   - vectorStoreId: The vector store ID
    ///   - fileId: The file ID
    /// - Returns: The vector store file object
    /// - Throws: `AISDKErrorV2` if not found
    public func retrieveFile(vectorStoreId: String, fileId: String) async throws -> VectorStoreFile {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(vectorStoreId)/files/\(fileId)")!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(VectorStoreFile.self, from: data)
    }

    /// Remove a file from a vector store
    ///
    /// - Parameters:
    ///   - vectorStoreId: The vector store ID
    ///   - fileId: The file ID to remove
    /// - Returns: Deletion status
    /// - Throws: `AISDKErrorV2` if deletion fails
    public func deleteFile(vectorStoreId: String, fileId: String) async throws -> DeletionStatus {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(vectorStoreId)/files/\(fileId)")!, method: "DELETE")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(DeletionStatus.self, from: data)
    }

    // MARK: - Batch File Operations

    /// Create a batch of files to add to a vector store
    ///
    /// - Parameters:
    ///   - vectorStoreId: The vector store ID
    ///   - fileIds: List of file IDs to add
    ///   - chunkingStrategy: Optional chunking strategy for all files
    /// - Returns: The file batch object
    /// - Throws: `AISDKErrorV2` if the operation fails
    public func createFileBatch(
        vectorStoreId: String,
        fileIds: [String],
        chunkingStrategy: ChunkingStrategy? = nil
    ) async throws -> VectorStoreFileBatch {
        var request = makeRequest(url: URL(string: "\(baseURL)/\(vectorStoreId)/file_batches")!, method: "POST")

        let body = CreateFileBatchRequest(fileIds: fileIds, chunkingStrategy: chunkingStrategy)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(VectorStoreFileBatch.self, from: data)
    }

    /// Retrieve a file batch status
    ///
    /// - Parameters:
    ///   - vectorStoreId: The vector store ID
    ///   - batchId: The batch ID
    /// - Returns: The file batch object with status
    /// - Throws: `AISDKErrorV2` if not found
    public func retrieveFileBatch(vectorStoreId: String, batchId: String) async throws -> VectorStoreFileBatch {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(vectorStoreId)/file_batches/\(batchId)")!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(VectorStoreFileBatch.self, from: data)
    }

    /// Cancel a file batch operation
    ///
    /// - Parameters:
    ///   - vectorStoreId: The vector store ID
    ///   - batchId: The batch ID to cancel
    /// - Returns: The cancelled file batch object
    /// - Throws: `AISDKErrorV2` if cancellation fails
    public func cancelFileBatch(vectorStoreId: String, batchId: String) async throws -> VectorStoreFileBatch {
        var request = makeRequest(url: URL(string: "\(baseURL)/\(vectorStoreId)/file_batches/\(batchId)/cancel")!, method: "POST")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(VectorStoreFileBatch.self, from: data)
    }

    // MARK: - Helpers

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("assistants=v2", forHTTPHeaderField: "OpenAI-Beta")
        return request
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AISDKErrorV2(code: .networkFailed, message: "Invalid response type")
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"
            throw mapHTTPError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        struct OpenAIError: Codable {
            let error: ErrorDetail
            struct ErrorDetail: Codable {
                let message: String
            }
        }

        if let error = try? JSONDecoder().decode(OpenAIError.self, from: data) {
            return error.error.message
        }
        return String(data: data, encoding: .utf8)
    }

    private func mapHTTPError(statusCode: Int, message: String) -> AISDKErrorV2 {
        switch statusCode {
        case 400:
            return AISDKErrorV2(code: .invalidRequest, message: message)
        case 401:
            return AISDKErrorV2(code: .authenticationFailed, message: message)
        case 404:
            return AISDKErrorV2(code: .invalidRequest, message: "Vector store not found: \(message)")
        case 429:
            return AISDKErrorV2(code: .rateLimitExceeded, message: message)
        case 500...599:
            return AISDKErrorV2(code: .providerUnavailable, message: message)
        default:
            return AISDKErrorV2(code: .unknown, message: message)
        }
    }
}

// MARK: - Vector Store

/// Metadata for a vector store
public struct VectorStore: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let createdAt: Int
    public let name: String?
    public let description: String?
    public let usageBytes: Int?
    public let lastActiveAt: Int?
    public let status: VectorStoreStatus
    public let fileCounts: FileCounts
    public let expiresAfter: VectorStoreExpiration?
    public let expiresAt: Int?
    public let metadata: [String: String]?

    public enum VectorStoreStatus: String, Codable, Sendable {
        case expired
        case inProgress = "in_progress"
        case completed
    }

    public struct FileCounts: Codable, Sendable, Equatable {
        public let inProgress: Int
        public let completed: Int
        public let failed: Int
        public let cancelled: Int
        public let total: Int

        public init(
            inProgress: Int = 0,
            completed: Int = 0,
            failed: Int = 0,
            cancelled: Int = 0,
            total: Int = 0
        ) {
            self.inProgress = inProgress
            self.completed = completed
            self.failed = failed
            self.cancelled = cancelled
            self.total = total
        }
    }

    public init(
        id: String,
        object: String = "vector_store",
        createdAt: Int,
        name: String? = nil,
        description: String? = nil,
        usageBytes: Int? = nil,
        lastActiveAt: Int? = nil,
        status: VectorStoreStatus,
        fileCounts: FileCounts,
        expiresAfter: VectorStoreExpiration? = nil,
        expiresAt: Int? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.object = object
        self.createdAt = createdAt
        self.name = name
        self.description = description
        self.usageBytes = usageBytes
        self.lastActiveAt = lastActiveAt
        self.status = status
        self.fileCounts = fileCounts
        self.expiresAfter = expiresAfter
        self.expiresAt = expiresAt
        self.metadata = metadata
    }
}

// MARK: - Vector Store Expiration

/// Expiration policy for vector stores
public struct VectorStoreExpiration: Codable, Sendable, Equatable {
    public let anchor: String
    public let days: Int

    public init(anchor: String = "last_active_at", days: Int) {
        self.anchor = anchor
        self.days = days
    }

    /// Expire after N days of inactivity
    public static func afterInactivity(days: Int) -> VectorStoreExpiration {
        VectorStoreExpiration(anchor: "last_active_at", days: days)
    }
}

// MARK: - Chunking Strategy

/// Chunking strategy for file processing in vector stores
public enum ChunkingStrategy: Codable, Sendable, Equatable {
    case auto
    case `static`(maxChunkSizeTokens: Int, chunkOverlapTokens: Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "auto":
            self = .auto
        case "static":
            let staticConfig = try container.decode(StaticConfig.self, forKey: .staticKey)
            self = .static(
                maxChunkSizeTokens: staticConfig.maxChunkSizeTokens,
                chunkOverlapTokens: staticConfig.chunkOverlapTokens
            )
        default:
            self = .auto
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .auto:
            try container.encode("auto", forKey: .type)
        case .static(let maxSize, let overlap):
            try container.encode("static", forKey: .type)
            try container.encode(StaticConfig(
                maxChunkSizeTokens: maxSize,
                chunkOverlapTokens: overlap
            ), forKey: .staticKey)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case staticKey = "static"
    }

    private struct StaticConfig: Codable {
        let maxChunkSizeTokens: Int
        let chunkOverlapTokens: Int
    }
}

// MARK: - Vector Store Query

/// Query type for vector store search
public enum VectorStoreQuery: Codable, Sendable {
    case text(String)
    case vector([Double])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else if let vector = try? container.decode([Double].self) {
            self = .vector(vector)
        } else {
            throw DecodingError.typeMismatch(
                VectorStoreQuery.self,
                DecodingError.Context(codingPath: [], debugDescription: "Expected String or [Double]")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .vector(let vector):
            try container.encode(vector)
        }
    }
}

// MARK: - Vector Store Filters

/// Filters for vector store search
public struct VectorStoreFilters: Codable, Sendable {
    public let type: String  // "and", "or"
    public let filters: [Filter]

    public struct Filter: Codable, Sendable {
        public let type: String  // "eq", "ne", "gt", "gte", "lt", "lte"
        public let key: String
        public let value: String

        public init(type: String, key: String, value: String) {
            self.type = type
            self.key = key
            self.value = value
        }
    }

    public init(type: String, filters: [Filter]) {
        self.type = type
        self.filters = filters
    }

    public static func and(_ filters: [Filter]) -> VectorStoreFilters {
        VectorStoreFilters(type: "and", filters: filters)
    }

    public static func or(_ filters: [Filter]) -> VectorStoreFilters {
        VectorStoreFilters(type: "or", filters: filters)
    }
}

// MARK: - Ranking Options

/// Ranking configuration for vector store search
public struct RankingOptions: Codable, Sendable, Equatable {
    public let ranker: String
    public let scoreThreshold: Double?

    public init(ranker: String = "default_2024_11_15", scoreThreshold: Double? = nil) {
        self.ranker = ranker
        self.scoreThreshold = scoreThreshold
    }
}

// MARK: - Search Results

/// Results from vector store search
public struct VectorStoreSearchResults: Codable, Sendable {
    public let object: String
    public let data: [SearchResult]
    public let searchQuery: String?

    public struct SearchResult: Codable, Sendable {
        public let fileId: String
        public let filename: String
        public let score: Double
        public let content: [ContentChunk]
        public let attributes: [String: String]?

        public struct ContentChunk: Codable, Sendable {
            public let type: String
            public let text: String

            public init(type: String, text: String) {
                self.type = type
                self.text = text
            }
        }

        public init(
            fileId: String,
            filename: String,
            score: Double,
            content: [ContentChunk],
            attributes: [String: String]? = nil
        ) {
            self.fileId = fileId
            self.filename = filename
            self.score = score
            self.content = content
            self.attributes = attributes
        }
    }

    public init(object: String = "list", data: [SearchResult], searchQuery: String? = nil) {
        self.object = object
        self.data = data
        self.searchQuery = searchQuery
    }
}

// MARK: - Vector Store File

/// A file within a vector store
public struct VectorStoreFile: Codable, Sendable {
    public let id: String
    public let object: String
    public let createdAt: Int
    public let vectorStoreId: String
    public let status: VectorStoreFileStatus
    public let lastError: LastError?
    public let usageBytes: Int?
    public let chunkingStrategy: ChunkingStrategy?

    public struct LastError: Codable, Sendable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public init(
        id: String,
        object: String = "vector_store.file",
        createdAt: Int,
        vectorStoreId: String,
        status: VectorStoreFileStatus,
        lastError: LastError? = nil,
        usageBytes: Int? = nil,
        chunkingStrategy: ChunkingStrategy? = nil
    ) {
        self.id = id
        self.object = object
        self.createdAt = createdAt
        self.vectorStoreId = vectorStoreId
        self.status = status
        self.lastError = lastError
        self.usageBytes = usageBytes
        self.chunkingStrategy = chunkingStrategy
    }
}

/// Status of a file in a vector store
public enum VectorStoreFileStatus: String, Codable, Sendable {
    case inProgress = "in_progress"
    case completed
    case failed
    case cancelled
}

// MARK: - List Types

/// Response from listing vector stores
public struct VectorStoreList: Codable, Sendable {
    public let object: String
    public let data: [VectorStore]
    public let firstId: String?
    public let lastId: String?
    public let hasMore: Bool

    public init(
        object: String = "list",
        data: [VectorStore],
        firstId: String? = nil,
        lastId: String? = nil,
        hasMore: Bool = false
    ) {
        self.object = object
        self.data = data
        self.firstId = firstId
        self.lastId = lastId
        self.hasMore = hasMore
    }
}

/// Response from listing vector store files
public struct VectorStoreFileList: Codable, Sendable {
    public let object: String
    public let data: [VectorStoreFile]
    public let firstId: String?
    public let lastId: String?
    public let hasMore: Bool

    public init(
        object: String = "list",
        data: [VectorStoreFile],
        firstId: String? = nil,
        lastId: String? = nil,
        hasMore: Bool = false
    ) {
        self.object = object
        self.data = data
        self.firstId = firstId
        self.lastId = lastId
        self.hasMore = hasMore
    }
}

// MARK: - File Batch

/// A batch of files being added to a vector store
public struct VectorStoreFileBatch: Codable, Sendable {
    public let id: String
    public let object: String
    public let createdAt: Int
    public let vectorStoreId: String
    public let status: BatchStatus
    public let fileCounts: VectorStore.FileCounts

    public enum BatchStatus: String, Codable, Sendable {
        case inProgress = "in_progress"
        case completed
        case failed
        case cancelled
    }

    public init(
        id: String,
        object: String = "vector_store.files_batch",
        createdAt: Int,
        vectorStoreId: String,
        status: BatchStatus,
        fileCounts: VectorStore.FileCounts
    ) {
        self.id = id
        self.object = object
        self.createdAt = createdAt
        self.vectorStoreId = vectorStoreId
        self.status = status
        self.fileCounts = fileCounts
    }
}

// MARK: - Request Types (internal)

struct CreateVectorStoreRequest: Codable {
    let name: String?
    let description: String?
    let fileIds: [String]?
    let chunkingStrategy: ChunkingStrategy?
    let expiresAfter: VectorStoreExpiration?
    let metadata: [String: String]?
}

struct UpdateVectorStoreRequest: Codable {
    let name: String?
    let description: String?
    let expiresAfter: VectorStoreExpiration?
    let metadata: [String: String]?
}

struct VectorStoreSearchRequest: Codable {
    let query: VectorStoreQuery
    let maxNumResults: Int
    let filters: VectorStoreFilters?
    let rankingOptions: RankingOptions?
    let rewriteQuery: Bool
}

struct AddFileRequest: Codable {
    let fileId: String
    let chunkingStrategy: ChunkingStrategy?
}

struct CreateFileBatchRequest: Codable {
    let fileIds: [String]
    let chunkingStrategy: ChunkingStrategy?
}
