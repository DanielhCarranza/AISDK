//
//  OpenAIFileManager.swift
//  AISDK
//
//  File management operations for OpenAI Responses API
//  Supports upload, download, list, retrieve, and delete operations
//

import Foundation

// MARK: - OpenAIFileManager

/// Actor-based file manager for OpenAI file operations
///
/// Provides thread-safe file upload, download, and management operations
/// for use with the Responses API, code interpreter, and file search tools.
///
/// Example:
/// ```swift
/// let fileManager = OpenAIFileManager(apiKey: "sk-...")
///
/// // Upload a file for code interpreter
/// let fileData = "print('hello world')".data(using: .utf8)!
/// let uploadedFile = try await fileManager.upload(
///     file: fileData,
///     filename: "script.py",
///     purpose: .assistants,
///     expiresAfter: .daysAfterUpload(7)
/// )
///
/// // List files
/// let files = try await fileManager.list(purpose: .assistants)
///
/// // Download content
/// let content = try await fileManager.content(id: uploadedFile.id)
///
/// // Delete file
/// let status = try await fileManager.delete(id: uploadedFile.id)
/// ```
public actor OpenAIFileManager {
    private let baseURL = "https://api.openai.com/v1/files"
    private let apiKey: String
    private let session: URLSession
    private let decoder: JSONDecoder

    /// Maximum file size for in-memory upload (100MB)
    public static let maxInMemoryFileSize = 100 * 1024 * 1024

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Upload

    /// Upload a file to OpenAI
    ///
    /// - Parameters:
    ///   - file: The file data to upload
    ///   - filename: The name of the file
    ///   - purpose: The intended purpose of the file
    ///   - expiresAfter: Optional expiration policy
    /// - Returns: The uploaded file metadata
    /// - Throws: `AISDKErrorV2` if the upload fails
    public func upload(
        file: Data,
        filename: String,
        purpose: FilePurpose,
        expiresAfter: ExpirationPolicy? = nil
    ) async throws -> OpenAIFile {
        // Validate file size
        guard file.count <= Self.maxInMemoryFileSize else {
            throw AISDKErrorV2(
                code: .invalidRequest,
                message: "File size \(file.count) exceeds maximum allowed size of \(Self.maxInMemoryFileSize) bytes"
            )
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // SECURITY: Sanitize filename to prevent header injection
        let sanitizedFilename = sanitizeFilename(filename)

        var body = Data()

        // Add file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(sanitizedFilename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(file)
        body.append("\r\n".data(using: .utf8)!)

        // Add purpose
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"purpose\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(purpose.rawValue)\r\n".data(using: .utf8)!)

        // Add expiration if provided
        if let expires = expiresAfter {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"expires_after[anchor]\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(expires.anchor)\r\n".data(using: .utf8)!)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"expires_after[seconds]\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(expires.seconds)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(OpenAIFile.self, from: data)
    }

    // MARK: - Upload from URL

    /// Upload a file from a local file URL
    ///
    /// - Parameters:
    ///   - fileURL: The local file URL to upload
    ///   - purpose: The intended purpose of the file
    ///   - expiresAfter: Optional expiration policy
    /// - Returns: The uploaded file metadata
    /// - Throws: `AISDKErrorV2` if the upload fails
    public func upload(
        fileURL: URL,
        purpose: FilePurpose,
        expiresAfter: ExpirationPolicy? = nil
    ) async throws -> OpenAIFile {
        let data = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        return try await upload(file: data, filename: filename, purpose: purpose, expiresAfter: expiresAfter)
    }

    // MARK: - List

    /// List files with optional filtering
    ///
    /// - Parameters:
    ///   - purpose: Optional filter by purpose
    ///   - limit: Maximum number of files to return (default: 10000)
    ///   - after: Cursor for pagination
    ///   - order: Sort order (default: descending by creation time)
    /// - Returns: A list of files
    /// - Throws: `AISDKErrorV2` if the request fails
    public func list(
        purpose: FilePurpose? = nil,
        limit: Int = 10000,
        after: String? = nil,
        order: SortOrder = .desc
    ) async throws -> FileList {
        var components = URLComponents(string: baseURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order", value: order.rawValue)
        ]
        if let purpose = purpose {
            queryItems.append(URLQueryItem(name: "purpose", value: purpose.rawValue))
        }
        if let after = after {
            queryItems.append(URLQueryItem(name: "after", value: after))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(FileList.self, from: data)
    }

    // MARK: - Retrieve

    /// Retrieve file metadata by ID
    ///
    /// - Parameter id: The file ID
    /// - Returns: The file metadata
    /// - Throws: `AISDKErrorV2` if the request fails
    public func retrieve(id: String) async throws -> OpenAIFile {
        var request = URLRequest(url: URL(string: "\(baseURL)/\(id)")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(OpenAIFile.self, from: data)
    }

    // MARK: - Delete

    /// Delete a file by ID
    ///
    /// - Parameter id: The file ID to delete
    /// - Returns: The deletion status
    /// - Throws: `AISDKErrorV2` if the request fails
    public func delete(id: String) async throws -> DeletionStatus {
        var request = URLRequest(url: URL(string: "\(baseURL)/\(id)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try decoder.decode(DeletionStatus.self, from: data)
    }

    // MARK: - Content Download

    /// Download the content of a file
    ///
    /// - Parameter id: The file ID to download
    /// - Returns: The file content as Data
    /// - Throws: `AISDKErrorV2` if the request fails
    public func content(id: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(baseURL)/\(id)/content")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    // MARK: - Helpers

    /// Sanitizes filename to prevent header injection attacks
    /// - Removes or escapes dangerous characters
    /// - Enforces maximum length
    /// - Preserves file extension
    private func sanitizeFilename(_ filename: String) -> String {
        // Maximum filename length (reasonable limit)
        let maxLength = 255

        // Remove control characters and newlines (header injection prevention)
        var sanitized = filename.filter { char in
            !char.isNewline && char.asciiValue.map { $0 >= 32 } ?? true
        }

        // Replace quotes and backslashes which can break Content-Disposition
        sanitized = sanitized.replacingOccurrences(of: "\"", with: "_")
        sanitized = sanitized.replacingOccurrences(of: "\\", with: "_")
        sanitized = sanitized.replacingOccurrences(of: "/", with: "_")

        // Truncate if too long, preserving extension
        if sanitized.count > maxLength {
            let ext = (sanitized as NSString).pathExtension
            let nameLength = maxLength - ext.count - 1
            if nameLength > 0 {
                let name = String(sanitized.prefix(nameLength))
                sanitized = "\(name).\(ext)"
            } else {
                sanitized = String(sanitized.prefix(maxLength))
            }
        }

        // Ensure we have a valid filename
        if sanitized.isEmpty {
            sanitized = "file"
        }

        return sanitized
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
        // Try to decode OpenAI error format
        struct OpenAIError: Codable {
            let error: ErrorDetail
            struct ErrorDetail: Codable {
                let message: String
                let type: String?
                let code: String?
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
            return AISDKErrorV2(code: .invalidRequest, message: "File not found: \(message)")
        case 429:
            return AISDKErrorV2(code: .rateLimitExceeded, message: message)
        case 500...599:
            return AISDKErrorV2(code: .providerUnavailable, message: message)
        default:
            return AISDKErrorV2(code: .unknown, message: message)
        }
    }
}

// MARK: - File Purpose

/// Purpose for uploaded files
public enum FilePurpose: String, Codable, Sendable {
    case assistants
    case batch
    case fineTune = "fine-tune"
    case vision
    case userData = "user_data"
    case evals
}

// MARK: - Expiration Policy

/// Expiration policy for uploaded files
public struct ExpirationPolicy: Codable, Sendable, Equatable {
    public let anchor: String
    public let seconds: Int

    public init(anchor: String = "upload_time", seconds: Int) {
        self.anchor = anchor
        self.seconds = seconds
    }

    /// Create expiration policy for days after upload
    public static func daysAfterUpload(_ days: Int) -> ExpirationPolicy {
        ExpirationPolicy(anchor: "upload_time", seconds: days * 24 * 60 * 60)
    }

    /// Create expiration policy for hours after upload
    public static func hoursAfterUpload(_ hours: Int) -> ExpirationPolicy {
        ExpirationPolicy(anchor: "upload_time", seconds: hours * 60 * 60)
    }
}

// MARK: - OpenAI File

/// Metadata for an uploaded file
public struct OpenAIFile: Codable, Sendable, Equatable {
    public let id: String
    public let object: String
    public let bytes: Int
    public let createdAt: Int
    public let expiresAt: Int?
    public let filename: String
    public let purpose: String
    public let status: FileStatus?
    public let statusDetails: String?

    public enum FileStatus: String, Codable, Sendable {
        case uploaded
        case processed
        case error
    }

    public init(
        id: String,
        object: String = "file",
        bytes: Int,
        createdAt: Int,
        expiresAt: Int? = nil,
        filename: String,
        purpose: String,
        status: FileStatus? = nil,
        statusDetails: String? = nil
    ) {
        self.id = id
        self.object = object
        self.bytes = bytes
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.filename = filename
        self.purpose = purpose
        self.status = status
        self.statusDetails = statusDetails
    }
}

// MARK: - File List

/// Response from listing files
public struct FileList: Codable, Sendable {
    public let object: String
    public let data: [OpenAIFile]
    public let hasMore: Bool?
    public let firstId: String?
    public let lastId: String?

    public init(
        object: String = "list",
        data: [OpenAIFile],
        hasMore: Bool? = nil,
        firstId: String? = nil,
        lastId: String? = nil
    ) {
        self.object = object
        self.data = data
        self.hasMore = hasMore
        self.firstId = firstId
        self.lastId = lastId
    }
}

// MARK: - Deletion Status

/// Response from deleting a file
public struct DeletionStatus: Codable, Sendable {
    public let id: String
    public let object: String
    public let deleted: Bool

    public init(id: String, object: String = "file", deleted: Bool) {
        self.id = id
        self.object = object
        self.deleted = deleted
    }
}

// MARK: - Sort Order

/// Sort order for list operations
public enum SortOrder: String, Codable, Sendable {
    case asc
    case desc
}
