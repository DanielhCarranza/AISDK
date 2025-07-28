import XCTest
@testable import AISDK

/// Simple metadata types declared only in the test target – simulates client-side extensions
private struct Source: ToolMetadata {
    let title: String
    let url: URL
    let publishDate: Date?
    let authors: [String]?
}

private struct MedicalEvidence: ToolMetadata {
    let sources: [Source]
    let evidenceLevel: String
    let confidenceScore: Double?
    let lastUpdated: Date
}

final class ToolMetadataAutoSupportTests: XCTestCase {
    func testRoundTripSource() throws {
        let original = Source(title: "Article", url: URL(string: "https://example.com")!, publishDate: nil, authors: ["Doe"])        
        let wrapper = AnyToolMetadata(original)

        let encoder = JSONEncoder()
        let data = try encoder.encode(wrapper)

        let decoder = JSONDecoder()
        let decodedWrapper = try decoder.decode(AnyToolMetadata.self, from: data)

        guard let decoded = decodedWrapper.metadata as? Source else {
            XCTFail("Decoded metadata is not Source")
            return
        }
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.url, original.url)
        XCTAssertEqual(decoded.authors ?? [], original.authors ?? [])
    }

    func testRoundTripMedicalEvidence() throws {
        let now = Date()
        let src = Source(title: "Study", url: URL(string: "https://example.org")!, publishDate: now, authors: nil)
        let original = MedicalEvidence(sources: [src], evidenceLevel: "high", confidenceScore: 0.9, lastUpdated: now)
        let wrapper = AnyToolMetadata(original)

        let data = try JSONEncoder().encode(wrapper)
        let decoded = try JSONDecoder().decode(AnyToolMetadata.self, from: data)

        guard let evidence = decoded.metadata as? MedicalEvidence else {
            XCTFail("Decoded metadata is not MedicalEvidence")
            return
        }
        XCTAssertEqual(evidence.evidenceLevel, original.evidenceLevel)
        XCTAssertEqual(evidence.sources.first?.title, src.title)
    }
} 