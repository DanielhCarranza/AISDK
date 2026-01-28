import Foundation

/// Service for Anthropic Files API operations
public actor AnthropicFilesService {

    // MARK: - Constants

    /// Beta header required for Files API
    private static let betaHeader = "files-api-2025-04-14"

    // MARK: - Properties

    private let httpClient: AnthropicHTTPClient

    // MARK: - Initialization

    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!
    ) {
        self.httpClient = AnthropicHTTPClient(apiKey: apiKey, baseURL: baseURL)
    }

    public init(httpClient: AnthropicHTTPClient) {
        self.httpClient = httpClient
    }

    // MARK: - Upload

    public func uploadFile(
        data: Data,
        filename: String,
        purpose: AnthropicFilePurpose,
        mimeType: String? = nil
    ) async throws -> AnthropicFile {
        let maxSize = purpose == .messageAttachment
            ? AnthropicFileTypes.maxAttachmentSize
            : AnthropicFileTypes.maxContainerUploadSize

        guard data.count <= maxSize else {
            throw LLMError.invalidRequest(
                "File size \(data.count) exceeds maximum \(maxSize) bytes for \(purpose.rawValue)"
            )
        }

        let contentType = mimeType
            ?? AnthropicFileTypes.mimeType(forFilename: filename)
            ?? "application/octet-stream"

        return try await httpClient.uploadMultipart(
            path: "files",
            formFields: [("purpose", purpose.rawValue)],
            fileData: data,
            filename: filename,
            mimeType: contentType,
            betaHeaders: Self.betaHeader
        )
    }

    public func uploadFile(
        from fileURL: URL,
        purpose: AnthropicFilePurpose
    ) async throws -> AnthropicFile {
        let data = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent

        return try await uploadFile(
            data: data,
            filename: filename,
            purpose: purpose
        )
    }

    // MARK: - Get File

    public func getFile(id: String) async throws -> AnthropicFile {
        return try await httpClient.get(
            path: "files/\(id)",
            betaHeaders: Self.betaHeader
        )
    }

    public func getFileContent(id: String) async throws -> Data {
        let (bytes, _) = try await httpClient.streamGet(
            path: "files/\(id)/content",
            betaHeaders: Self.betaHeader
        )

        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    // MARK: - List Files

    public func listFiles(
        purpose: AnthropicFilePurpose? = nil,
        limit: Int? = nil,
        afterId: String? = nil,
        beforeId: String? = nil
    ) async throws -> FileListResponse {
        var queryItems: [URLQueryItem] = []

        if let purpose {
            queryItems.append(URLQueryItem(name: "purpose", value: purpose.rawValue))
        }
        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let afterId {
            queryItems.append(URLQueryItem(name: "after_id", value: afterId))
        }
        if let beforeId {
            queryItems.append(URLQueryItem(name: "before_id", value: beforeId))
        }

        return try await httpClient.get(
            path: "files",
            queryItems: queryItems.isEmpty ? nil : queryItems,
            betaHeaders: Self.betaHeader
        )
    }

    // MARK: - Delete File

    public func deleteFile(id: String) async throws -> FileDeleteResponse {
        return try await httpClient.delete(
            path: "files/\(id)",
            betaHeaders: Self.betaHeader
        )
    }

    // MARK: - Convenience Methods

    public func uploadFiles(
        _ files: [(data: Data, filename: String)],
        purpose: AnthropicFilePurpose
    ) async throws -> [AnthropicFile] {
        var results: [AnthropicFile] = []

        for (data, filename) in files {
            let file = try await uploadFile(
                data: data,
                filename: filename,
                purpose: purpose
            )
            results.append(file)
        }

        return results
    }

    public func getAllFiles(purpose: AnthropicFilePurpose? = nil) async throws -> [AnthropicFile] {
        var allFiles: [AnthropicFile] = []
        var afterId: String? = nil

        repeat {
            let response = try await listFiles(
                purpose: purpose,
                limit: 100,
                afterId: afterId
            )

            allFiles.append(contentsOf: response.data)

            if response.hasMore {
                afterId = response.lastId
            } else {
                break
            }
        } while true

        return allFiles
    }

    public func deleteAllFiles(purpose: AnthropicFilePurpose? = nil) async throws -> Int {
        let files = try await getAllFiles(purpose: purpose)
        var deletedCount = 0

        for file in files {
            let result = try await deleteFile(id: file.id)
            if result.deleted {
                deletedCount += 1
            }
        }

        return deletedCount
    }
}
