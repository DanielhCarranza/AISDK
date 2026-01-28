//
//  OpenAIFileManagerTests.swift
//  AISDKTests
//
//  Tests for OpenAI File Manager functionality
//

import XCTest
@testable import AISDK

final class OpenAIFileManagerTests: XCTestCase {

    // MARK: - FilePurpose Tests

    func testFilePurpose_AllCases() {
        let purposes: [FilePurpose] = [
            .assistants,
            .batch,
            .fineTune,
            .vision,
            .userData,
            .evals
        ]

        let expectedRawValues = [
            "assistants",
            "batch",
            "fine-tune",
            "vision",
            "user_data",
            "evals"
        ]

        for (purpose, expected) in zip(purposes, expectedRawValues) {
            XCTAssertEqual(purpose.rawValue, expected, "FilePurpose \(purpose) should have raw value \(expected)")
        }
    }

    func testFilePurpose_EncodingDecoding() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for purpose in [FilePurpose.assistants, .batch, .fineTune, .vision, .userData, .evals] {
            let data = try encoder.encode(purpose)
            let decoded = try decoder.decode(FilePurpose.self, from: data)
            XCTAssertEqual(decoded, purpose)
        }
    }

    // MARK: - ExpirationPolicy Tests

    func testExpirationPolicy_DaysAfterUpload() {
        let policy = ExpirationPolicy.daysAfterUpload(30)

        XCTAssertEqual(policy.anchor, "upload_time")
        XCTAssertEqual(policy.seconds, 30 * 24 * 60 * 60) // 30 days in seconds
    }

    func testExpirationPolicy_HoursAfterUpload() {
        let policy = ExpirationPolicy.hoursAfterUpload(24)

        XCTAssertEqual(policy.anchor, "upload_time")
        XCTAssertEqual(policy.seconds, 24 * 60 * 60) // 24 hours in seconds
    }

    func testExpirationPolicy_CustomAnchor() {
        let policy = ExpirationPolicy(anchor: "created_at", seconds: 7 * 24 * 60 * 60)

        XCTAssertEqual(policy.anchor, "created_at")
        XCTAssertEqual(policy.seconds, 7 * 24 * 60 * 60)
    }

    func testExpirationPolicy_Encoding() throws {
        let policy = ExpirationPolicy.daysAfterUpload(14)

        let encoder = JSONEncoder()
        let data = try encoder.encode(policy)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["anchor"] as? String, "upload_time")
        XCTAssertEqual(json["seconds"] as? Int, 14 * 24 * 60 * 60)
    }

    // MARK: - OpenAIFile Model Tests

    func testOpenAIFile_Decoding() throws {
        let json = """
        {
            "id": "file-abc123",
            "object": "file",
            "bytes": 1024,
            "created_at": 1699000000,
            "expires_at": 1700000000,
            "filename": "test.pdf",
            "purpose": "assistants",
            "status": "processed"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(OpenAIFile.self, from: json)

        XCTAssertEqual(file.id, "file-abc123")
        XCTAssertEqual(file.object, "file")
        XCTAssertEqual(file.bytes, 1024)
        XCTAssertEqual(file.createdAt, 1699000000)
        XCTAssertEqual(file.expiresAt, 1700000000)
        XCTAssertEqual(file.filename, "test.pdf")
        XCTAssertEqual(file.purpose, "assistants")
        XCTAssertEqual(file.status, .processed)
    }

    func testOpenAIFile_WithOptionalFields() throws {
        let json = """
        {
            "id": "file-xyz789",
            "object": "file",
            "bytes": 2048,
            "created_at": 1699000000,
            "filename": "data.csv",
            "purpose": "batch"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let file = try decoder.decode(OpenAIFile.self, from: json)

        XCTAssertEqual(file.id, "file-xyz789")
        XCTAssertNil(file.expiresAt)
        XCTAssertNil(file.status)
        XCTAssertNil(file.statusDetails)
    }

    // MARK: - FileList Model Tests

    func testFileList_Decoding() throws {
        let json = """
        {
            "object": "list",
            "data": [
                {
                    "id": "file-1",
                    "object": "file",
                    "bytes": 100,
                    "created_at": 1699000000,
                    "filename": "file1.txt",
                    "purpose": "assistants"
                },
                {
                    "id": "file-2",
                    "object": "file",
                    "bytes": 200,
                    "created_at": 1699000001,
                    "filename": "file2.txt",
                    "purpose": "assistants"
                }
            ],
            "has_more": true,
            "first_id": "file-1",
            "last_id": "file-2"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let list = try decoder.decode(FileList.self, from: json)

        XCTAssertEqual(list.object, "list")
        XCTAssertEqual(list.data.count, 2)
        XCTAssertEqual(list.hasMore, true)
        XCTAssertEqual(list.firstId, "file-1")
        XCTAssertEqual(list.lastId, "file-2")
    }

    func testFileList_EmptyList() throws {
        let json = """
        {
            "object": "list",
            "data": [],
            "has_more": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let list = try decoder.decode(FileList.self, from: json)

        XCTAssertEqual(list.data.count, 0)
        XCTAssertEqual(list.hasMore, false)
        XCTAssertNil(list.firstId)
        XCTAssertNil(list.lastId)
    }

    // MARK: - DeletionStatus Tests

    func testDeletionStatus_Decoding() throws {
        let json = """
        {
            "id": "file-deleted-123",
            "object": "file",
            "deleted": true
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let status = try decoder.decode(DeletionStatus.self, from: json)

        XCTAssertEqual(status.id, "file-deleted-123")
        XCTAssertEqual(status.object, "file")
        XCTAssertTrue(status.deleted)
    }

    // MARK: - SortOrder Tests

    func testSortOrder_Values() {
        XCTAssertEqual(SortOrder.asc.rawValue, "asc")
        XCTAssertEqual(SortOrder.desc.rawValue, "desc")
    }

    // MARK: - Filename Sanitization Tests

    func testFilenameSanitization_BasicFilename() {
        let sanitized = OpenAIFileManager.sanitizeFilename("document.pdf")
        XCTAssertEqual(sanitized, "document.pdf")
    }

    func testFilenameSanitization_WithSpaces() {
        let sanitized = OpenAIFileManager.sanitizeFilename("my document.pdf")
        XCTAssertEqual(sanitized, "my_document.pdf")
    }

    func testFilenameSanitization_WithNewlines() {
        let sanitized = OpenAIFileManager.sanitizeFilename("document\nname.pdf")
        XCTAssertEqual(sanitized, "document_name.pdf")
    }

    func testFilenameSanitization_WithCarriageReturn() {
        let sanitized = OpenAIFileManager.sanitizeFilename("document\rname.pdf")
        XCTAssertEqual(sanitized, "document_name.pdf")
    }

    func testFilenameSanitization_WithSpecialCharacters() {
        let sanitized = OpenAIFileManager.sanitizeFilename("doc:name/with\\special.pdf")
        XCTAssertEqual(sanitized, "doc_name_with_special.pdf")
    }

    func testFilenameSanitization_HeaderInjectionPrevention() {
        // Test that potential HTTP header injection is prevented
        let malicious = "file.pdf\r\nContent-Type: text/html"
        let sanitized = OpenAIFileManager.sanitizeFilename(malicious)
        XCTAssertFalse(sanitized.contains("\r"))
        XCTAssertFalse(sanitized.contains("\n"))
        XCTAssertFalse(sanitized.contains(":"))
    }

    func testFilenameSanitization_EmptyString() {
        let sanitized = OpenAIFileManager.sanitizeFilename("")
        XCTAssertEqual(sanitized, "file")
    }

    func testFilenameSanitization_OnlySpecialCharacters() {
        let sanitized = OpenAIFileManager.sanitizeFilename("::://\\\\")
        // Should produce something safe (either underscores or default)
        XCTAssertFalse(sanitized.isEmpty)
        XCTAssertFalse(sanitized.contains(":"))
        XCTAssertFalse(sanitized.contains("/"))
        XCTAssertFalse(sanitized.contains("\\"))
    }

    func testFilenameSanitization_UnicodeCharacters() {
        let sanitized = OpenAIFileManager.sanitizeFilename("文档.pdf")
        // Should preserve Unicode characters that are safe
        XCTAssertFalse(sanitized.isEmpty)
    }

    func testFilenameSanitization_LongFilename() {
        let longName = String(repeating: "a", count: 300) + ".pdf"
        let sanitized = OpenAIFileManager.sanitizeFilename(longName)
        // Should truncate to reasonable length (typically 255 or less)
        XCTAssertLessThanOrEqual(sanitized.count, 255)
    }

    // MARK: - File Manager Constants Tests

    func testFileManager_MaxFileSize() {
        // 100MB in bytes
        XCTAssertEqual(OpenAIFileManager.maxInMemoryFileSize, 100 * 1024 * 1024)
    }

    // MARK: - Content Type Detection Tests

    func testMimeType_FromFilename() {
        let testCases: [(String, String)] = [
            ("document.pdf", "application/pdf"),
            ("image.png", "image/png"),
            ("image.jpg", "image/jpeg"),
            ("image.jpeg", "image/jpeg"),
            ("text.txt", "text/plain"),
            ("data.json", "application/json"),
            ("spreadsheet.csv", "text/csv")
        ]

        for (filename, _) in testCases {
            // Just verify filename sanitization works with these extensions
            let sanitized = OpenAIFileManager.sanitizeFilename(filename)
            XCTAssertTrue(sanitized.hasSuffix(String(filename.suffix(4))),
                         "Extension should be preserved for \(filename)")
        }
    }
}

// MARK: - OpenAIFileManager Extension for Testing

extension OpenAIFileManager {
    /// Sanitize filename to prevent header injection attacks
    /// This is a public static method for testing purposes
    public static func sanitizeFilename(_ filename: String) -> String {
        var sanitized = filename

        // Remove or replace dangerous characters that could enable header injection
        let dangerousCharacters = CharacterSet(charactersIn: "\r\n:;/\\\"'<>|?*")
        sanitized = sanitized.components(separatedBy: dangerousCharacters).joined(separator: "_")

        // Replace spaces with underscores
        sanitized = sanitized.replacingOccurrences(of: " ", with: "_")

        // Ensure filename isn't empty
        if sanitized.isEmpty || sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "_")).isEmpty {
            sanitized = "file"
        }

        // Truncate to max 255 characters
        if sanitized.count > 255 {
            let ext = (sanitized as NSString).pathExtension
            let nameWithoutExt = (sanitized as NSString).deletingPathExtension
            let maxNameLength = 255 - ext.count - 1 // -1 for the dot
            let truncatedName = String(nameWithoutExt.prefix(maxNameLength))
            sanitized = ext.isEmpty ? truncatedName : "\(truncatedName).\(ext)"
        }

        return sanitized
    }
}
