//
//  OpenAIContainerManager.swift
//  AISDK
//
//  Container management for OpenAI Responses API
//  Supports code interpreter container lifecycle management
//

import Foundation

// MARK: - OpenAIContainerManager

/// Actor-based container manager for OpenAI code interpreter containers
///
/// Provides thread-safe container management operations for use with
/// the code_interpreter tool in the Responses API.
///
/// Example:
/// ```swift
/// let containerManager = OpenAIContainerManager(apiKey: "sk-...")
///
/// // Create a container with files
/// let container = try await containerManager.create(
///     name: "Data Analysis Container",
///     fileIds: [fileId1, fileId2],
///     memoryLimit: .fourGigabytes,
///     expiresAfter: .afterInactivity(minutes: 60)
/// )
///
/// // Wait for the container to be ready
/// let readyContainer = try await containerManager.waitForReady(id: container.id)
///
/// // Delete the container when done
/// try await containerManager.delete(id: container.id)
/// ```
public actor OpenAIContainerManager {
    private let baseURL = "https://api.openai.com/v1/containers"
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

    /// Create a new container
    ///
    /// - Parameters:
    ///   - name: Name for the container
    ///   - fileIds: Optional list of file IDs to add
    ///   - memoryLimit: Memory limit for the container (default: 1GB)
    ///   - expiresAfter: Optional expiration policy
    ///   - metadata: Optional metadata key-value pairs
    /// - Returns: The created container
    /// - Throws: `AISDKErrorV2` if creation fails
    public func create(
        name: String,
        fileIds: [String]? = nil,
        memoryLimit: MemoryLimit = .oneGigabyte,
        expiresAfter: ContainerExpiration? = nil,
        metadata: [String: String]? = nil
    ) async throws -> Container {
        var request = makeRequest(url: URL(string: baseURL)!, method: "POST")

        let body = CreateContainerRequest(
            name: name,
            fileIds: fileIds,
            memoryLimit: memoryLimit.rawValue,
            expiresAfter: expiresAfter,
            metadata: metadata
        )
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(Container.self, from: data)
    }

    // MARK: - List

    /// List containers with pagination
    ///
    /// - Parameters:
    ///   - limit: Maximum number of results (default: 20)
    ///   - after: Cursor for forward pagination
    ///   - before: Cursor for backward pagination
    ///   - order: Sort order (default: descending by creation time)
    /// - Returns: List of containers
    /// - Throws: `AISDKErrorV2` if the request fails
    public func list(
        limit: Int = 20,
        after: String? = nil,
        before: String? = nil,
        order: SortOrder = .desc
    ) async throws -> ContainerList {
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
        return try decoder.decode(ContainerList.self, from: data)
    }

    // MARK: - Retrieve

    /// Retrieve a container by ID
    ///
    /// - Parameter id: The container ID
    /// - Returns: The container
    /// - Throws: `AISDKErrorV2` if not found or request fails
    public func retrieve(id: String) async throws -> Container {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(id)")!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(Container.self, from: data)
    }

    // MARK: - Update

    /// Update a container
    ///
    /// - Parameters:
    ///   - id: The container ID
    ///   - name: New name (optional)
    ///   - expiresAfter: New expiration policy (optional)
    ///   - metadata: New metadata (optional)
    /// - Returns: The updated container
    /// - Throws: `AISDKErrorV2` if update fails
    public func update(
        id: String,
        name: String? = nil,
        expiresAfter: ContainerExpiration? = nil,
        metadata: [String: String]? = nil
    ) async throws -> Container {
        var request = makeRequest(url: URL(string: "\(baseURL)/\(id)")!, method: "POST")

        let body = UpdateContainerRequest(
            name: name,
            expiresAfter: expiresAfter,
            metadata: metadata
        )
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(Container.self, from: data)
    }

    // MARK: - Delete

    /// Delete a container
    ///
    /// - Parameter id: The container ID to delete
    /// - Returns: Deletion status
    /// - Throws: `AISDKErrorV2` if deletion fails
    public func delete(id: String) async throws -> DeletionStatus {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(id)")!, method: "DELETE")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(DeletionStatus.self, from: data)
    }

    // MARK: - File Operations

    /// Add a file to a container
    ///
    /// - Parameters:
    ///   - containerId: The container ID
    ///   - fileId: The file ID to add
    /// - Returns: The container file reference
    /// - Throws: `AISDKErrorV2` if the operation fails
    public func addFile(containerId: String, fileId: String) async throws -> ContainerFile {
        var request = makeRequest(url: URL(string: "\(baseURL)/\(containerId)/files")!, method: "POST")

        let body = AddContainerFileRequest(fileId: fileId)
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(ContainerFile.self, from: data)
    }

    /// List files in a container
    ///
    /// - Parameters:
    ///   - containerId: The container ID
    ///   - limit: Maximum number of results (default: 20)
    ///   - after: Cursor for forward pagination
    ///   - order: Sort order (default: descending by creation time)
    /// - Returns: List of container files
    /// - Throws: `AISDKErrorV2` if the request fails
    public func listFiles(
        containerId: String,
        limit: Int = 20,
        after: String? = nil,
        order: SortOrder = .desc
    ) async throws -> ContainerFileList {
        var components = URLComponents(string: "\(baseURL)/\(containerId)/files")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order", value: order.rawValue)
        ]
        if let after = after { queryItems.append(URLQueryItem(name: "after", value: after)) }
        components.queryItems = queryItems

        let request = makeRequest(url: components.url!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(ContainerFileList.self, from: data)
    }

    /// Retrieve a file from a container
    ///
    /// - Parameters:
    ///   - containerId: The container ID
    ///   - fileId: The file ID
    /// - Returns: The container file reference
    /// - Throws: `AISDKErrorV2` if not found or request fails
    public func retrieveFile(containerId: String, fileId: String) async throws -> ContainerFile {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(containerId)/files/\(fileId)")!, method: "GET")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(ContainerFile.self, from: data)
    }

    /// Delete a file from a container
    ///
    /// - Parameters:
    ///   - containerId: The container ID
    ///   - fileId: The file ID to delete
    /// - Returns: Deletion status
    /// - Throws: `AISDKErrorV2` if deletion fails
    public func deleteFile(containerId: String, fileId: String) async throws -> DeletionStatus {
        let request = makeRequest(url: URL(string: "\(baseURL)/\(containerId)/files/\(fileId)")!, method: "DELETE")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(DeletionStatus.self, from: data)
    }

    // MARK: - Convenience Methods

    /// Wait for container to be ready (running status)
    ///
    /// - Parameters:
    ///   - id: The container ID
    ///   - timeout: Maximum time to wait (default: 60 seconds)
    ///   - pollInterval: Time between status checks (default: 1 second)
    /// - Returns: The container in running state
    /// - Throws: `AISDKErrorV2` if timeout or container is deleted
    public func waitForReady(
        id: String,
        timeout: TimeInterval = 60,
        pollInterval: TimeInterval = 1
    ) async throws -> Container {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            let container = try await retrieve(id: id)

            switch container.status {
            case .running:
                return container
            case .deleted:
                throw AISDKErrorV2(code: .invalidRequest, message: "Container was deleted")
            case .stopped:
                // Container may need to be started, continue polling
                break
            }

            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        throw AISDKErrorV2(code: .timeout, message: "Container did not become ready within \(Int(timeout)) seconds")
    }

    // MARK: - Helpers

    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            return AISDKErrorV2(code: .invalidRequest, message: "Container not found: \(message)")
        case 429:
            return AISDKErrorV2(code: .rateLimitExceeded, message: message)
        case 500...599:
            return AISDKErrorV2(code: .providerUnavailable, message: message)
        default:
            return AISDKErrorV2(code: .unknown, message: message)
        }
    }
}

// MARK: - Memory Limit

/// Memory limit options for code interpreter containers
public enum MemoryLimit: String, Codable, Sendable {
    case oneGigabyte = "1g"
    case fourGigabytes = "4g"

    /// Memory limit in bytes
    public var bytes: Int {
        switch self {
        case .oneGigabyte: return 1_073_741_824
        case .fourGigabytes: return 4_294_967_296
        }
    }
}

// MARK: - Container

/// Metadata for a code interpreter container
public struct Container: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let createdAt: Int
    public let name: String
    public let status: ContainerStatus
    public let memoryLimit: String
    public let expiresAfter: ContainerExpiration?
    public let lastActiveAt: Int
    public let metadata: [String: String]?

    public init(
        id: String,
        object: String = "container",
        createdAt: Int,
        name: String,
        status: ContainerStatus,
        memoryLimit: String,
        expiresAfter: ContainerExpiration? = nil,
        lastActiveAt: Int,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.object = object
        self.createdAt = createdAt
        self.name = name
        self.status = status
        self.memoryLimit = memoryLimit
        self.expiresAfter = expiresAfter
        self.lastActiveAt = lastActiveAt
        self.metadata = metadata
    }
}

// MARK: - Container Status

/// Status of a code interpreter container
public enum ContainerStatus: String, Codable, Sendable {
    case running
    case stopped
    case deleted
}

// MARK: - Container Expiration

/// Expiration policy for containers
public struct ContainerExpiration: Codable, Sendable, Equatable {
    public let anchor: String
    public let minutes: Int

    public init(anchor: String = "last_active_at", minutes: Int = 20) {
        self.anchor = anchor
        self.minutes = minutes
    }

    /// Default expiration: 20 minutes after last activity
    public static let `default` = ContainerExpiration(anchor: "last_active_at", minutes: 20)

    /// Expire after N minutes of inactivity
    public static func afterInactivity(minutes: Int) -> ContainerExpiration {
        ContainerExpiration(anchor: "last_active_at", minutes: minutes)
    }

    /// Expire after N hours of inactivity
    public static func afterInactivity(hours: Int) -> ContainerExpiration {
        ContainerExpiration(anchor: "last_active_at", minutes: hours * 60)
    }
}

// MARK: - Container List

/// Paginated list of containers
public struct ContainerList: Codable, Sendable {
    public let object: String
    public let data: [Container]
    public let firstId: String?
    public let lastId: String?
    public let hasMore: Bool

    public init(
        object: String = "list",
        data: [Container],
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

// MARK: - Container File

/// File reference within a container
public struct ContainerFile: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let createdAt: Int
    public let containerId: String
    public let path: String?

    public init(
        id: String,
        object: String = "container.file",
        createdAt: Int,
        containerId: String,
        path: String? = nil
    ) {
        self.id = id
        self.object = object
        self.createdAt = createdAt
        self.containerId = containerId
        self.path = path
    }
}

// MARK: - Container File List

/// Paginated list of container files
public struct ContainerFileList: Codable, Sendable {
    public let object: String
    public let data: [ContainerFile]
    public let firstId: String?
    public let lastId: String?
    public let hasMore: Bool

    public init(
        object: String = "list",
        data: [ContainerFile],
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

// MARK: - Request Types (internal)

struct CreateContainerRequest: Codable {
    let name: String
    let fileIds: [String]?
    let memoryLimit: String
    let expiresAfter: ContainerExpiration?
    let metadata: [String: String]?
}

struct UpdateContainerRequest: Codable {
    let name: String?
    let expiresAfter: ContainerExpiration?
    let metadata: [String: String]?
}

struct AddContainerFileRequest: Codable {
    let fileId: String
}
