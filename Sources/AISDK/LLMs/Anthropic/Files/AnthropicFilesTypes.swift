import Foundation

// MARK: - File Purpose

/// Purpose of an uploaded file
public enum AnthropicFilePurpose: String, Codable, Sendable {
    /// File for use as a message attachment
    case messageAttachment = "message_attachment"

    /// File for upload to a container
    case containerUpload = "container_upload"
}

// MARK: - File Metadata

/// Metadata for an uploaded file
/// Note: The API returns size_bytes which is auto-converted to sizeBytes by the decoder
public struct AnthropicFile: Codable, Sendable, Equatable {
    /// Unique file identifier (e.g., "file_abc123")
    public let id: String

    /// Original filename
    public let filename: String

    /// File purpose (optional in responses)
    public let purpose: AnthropicFilePurpose?

    /// ISO timestamp when file was created (auto-converted from created_at)
    public let createdAt: String

    /// File size in bytes (auto-converted from size_bytes)
    public let sizeBytes: Int

    /// MIME type of the file (auto-converted from mime_type)
    public let mimeType: String?

    /// Always "file"
    public let type: String

    /// Whether the file is downloadable
    public let downloadable: Bool?

    /// Convenience accessor for backwards compatibility
    public var bytes: Int { sizeBytes }

    public init(
        id: String,
        filename: String,
        purpose: AnthropicFilePurpose? = nil,
        createdAt: String,
        sizeBytes: Int,
        mimeType: String? = nil,
        type: String = "file",
        downloadable: Bool? = nil
    ) {
        self.id = id
        self.filename = filename
        self.purpose = purpose
        self.createdAt = createdAt
        self.sizeBytes = sizeBytes
        self.mimeType = mimeType
        self.type = type
        self.downloadable = downloadable
    }
}

// MARK: - File Content Sources

/// Source for referencing a file as an image in messages
public struct FileImageSource: Codable, Sendable, Equatable {
    /// Always "file"
    public let type: String

    /// ID of the uploaded file
    public let fileId: String

    public init(fileId: String) {
        self.type = "file"
        self.fileId = fileId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case fileId = "file_id"
    }
}

/// Source for referencing a file as a document in messages
public struct FileDocumentSource: Codable, Sendable, Equatable {
    /// Always "file"
    public let type: String

    /// ID of the uploaded file
    public let fileId: String

    public init(fileId: String) {
        self.type = "file"
        self.fileId = fileId
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case fileId = "file_id"
    }
}

// MARK: - List Response

/// Response from listing files
/// Note: Uses auto snake_case conversion from decoder
public struct FileListResponse: Codable, Sendable {
    public let data: [AnthropicFile]
    public let hasMore: Bool
    public let firstId: String?
    public let lastId: String?

    public init(
        data: [AnthropicFile],
        hasMore: Bool = false,
        firstId: String? = nil,
        lastId: String? = nil
    ) {
        self.data = data
        self.hasMore = hasMore
        self.firstId = firstId
        self.lastId = lastId
    }
}

// MARK: - Delete Response

/// Response from deleting a file
public struct FileDeleteResponse: Codable, Sendable {
    public let id: String
    public let type: String
    public let deleted: Bool

    public init(id: String, deleted: Bool = true) {
        self.id = id
        self.type = "file_deleted"
        self.deleted = deleted
    }
}

// MARK: - Supported File Types

public enum AnthropicFileTypes {
    public static let supportedImageTypes: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp"
    ]

    public static let supportedDocumentTypes: Set<String> = [
        "application/pdf",
        "text/plain",
        "text/csv",
        "text/html",
        "application/json"
    ]

    public static let maxAttachmentSize = 32 * 1024 * 1024
    public static let maxContainerUploadSize = 100 * 1024 * 1024

    public static func isImageSupported(_ mimeType: String) -> Bool {
        supportedImageTypes.contains(mimeType.lowercased())
    }

    public static func isDocumentSupported(_ mimeType: String) -> Bool {
        supportedDocumentTypes.contains(mimeType.lowercased())
    }

    public static func mimeType(forFilename filename: String) -> String? {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "csv": return "text/csv"
        case "html", "htm": return "text/html"
        case "json": return "application/json"
        default: return nil
        }
    }
}

// MARK: - Content Block Extensions

/// File-based image source for use in content blocks
public struct AnthropicFileImageContent: Codable, Sendable, Equatable {
    public let type: String
    public let source: FileImageSource

    public init(fileId: String) {
        self.type = "image"
        self.source = FileImageSource(fileId: fileId)
    }
}

/// File-based document content for use in content blocks
public struct AnthropicFileDocumentContent: Codable, Sendable, Equatable {
    public let type: String
    public let source: FileDocumentSource
    public let title: String?
    public let context: String?

    public init(fileId: String, title: String? = nil, context: String? = nil) {
        self.type = "document"
        self.source = FileDocumentSource(fileId: fileId)
        self.title = title
        self.context = context
    }
}
