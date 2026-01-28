import XCTest
@testable import AISDK

final class AnthropicFilesTypesTests: XCTestCase {
    func testMimeTypeDetection() {
        XCTAssertEqual(AnthropicFileTypes.mimeType(forFilename: "image.jpg"), "image/jpeg")
        XCTAssertEqual(AnthropicFileTypes.mimeType(forFilename: "doc.PDF"), "application/pdf")
        XCTAssertNil(AnthropicFileTypes.mimeType(forFilename: "unknown.bin"))
    }

    func testSupportedTypeChecks() {
        XCTAssertTrue(AnthropicFileTypes.isImageSupported("image/png"))
        XCTAssertFalse(AnthropicFileTypes.isImageSupported("application/pdf"))

        XCTAssertTrue(AnthropicFileTypes.isDocumentSupported("application/pdf"))
        XCTAssertFalse(AnthropicFileTypes.isDocumentSupported("image/webp"))
    }

    func testFileSourceEncodingUsesFileId() throws {
        let source = FileImageSource(fileId: "file_123")
        let data = try JSONEncoder().encode(source)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "file")
        XCTAssertEqual(json?["file_id"] as? String, "file_123")
    }
}
