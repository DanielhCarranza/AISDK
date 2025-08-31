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

// App-specific metadata structures matching user's shapes
private struct AppSource: ToolMetadata {
    let title: String
    let content: String?
    let url: String
    let evidenceType: String

    enum CodingKeys: String, CodingKey {
        case title
        case content
        case url
        case evidenceType = "evidence_type"
    }
}

private struct AppSources: ToolMetadata {
    let results: [AppSource]
}

private struct AppMedicalEvidence: ToolMetadata {
    let sources: [AppSource]
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

    func testUnknownMetadataFallsBackToRawToolMetadata() throws {
        // Construct AnyToolMetadata JSON with an unknown type
        let unknownType = "com.example.UnknownMetadata"
        let payload: [String: Any] = [
            "foo": "bar",
            "count": 1
        ]
        let root: [String: Any] = [
            "type": unknownType,
            "metadata": payload
        ]

        let data = try JSONSerialization.data(withJSONObject: root, options: [])

        let decoded = try JSONDecoder().decode(AnyToolMetadata.self, from: data)
        guard let raw = decoded.metadata as? RawToolMetadata else {
            XCTFail("Expected RawToolMetadata fallback for unknown type")
            return
        }
        XCTAssertEqual(raw.originalType, unknownType)

        // Validate payload content
        switch raw.payload {
        case .object(let obj):
            if let foo = obj["foo"] {
                switch foo {
                case .string("bar"): break
                default: XCTFail("Expected foo == 'bar'")
                }
            } else {
                XCTFail("Missing key 'foo'")
            }
            if let count = obj["count"] {
                switch count {
                case .int(1): break
                case .double(let d) where Int(d) == 1: break
                default: XCTFail("Expected count == 1")
                }
            } else {
                XCTFail("Missing key 'count'")
            }
        default:
            XCTFail("Expected object payload in RawToolMetadata")
        }
    }

    func testRegisteredMetadataTypeDecodesViaRegistry() throws {
        // Arrange: register the private test type `Source`
        ToolMetadataDecoderRegistry.register(Source.self)

        // Build JSON that matches AnyToolMetadata for the registered type
        let typeKey = String(reflecting: Source.self)
        let metadata: [String: Any] = [
            "title": "Article",
            "url": "https://example.com",
            // omit publishDate (optional)
            "authors": ["Doe"]
        ]
        let root: [String: Any] = [
            "type": typeKey,
            "metadata": metadata
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [])

        // Act
        let decoded = try JSONDecoder().decode(AnyToolMetadata.self, from: data)

        // Assert
        guard let typed = decoded.metadata as? Source else {
            XCTFail("Expected metadata to decode as Source after registration")
            return
        }
        XCTAssertEqual(typed.title, "Article")
        XCTAssertEqual(typed.url, URL(string: "https://example.com")!)
        XCTAssertEqual(typed.authors ?? [], ["Doe"])
    }

    func testAppSourceRoundTrip() throws {
        let original = AppSource(title: "Title",
                                 content: "Body",
                                 url: "https://example.com",
                                 evidenceType: "paper")
        let wrapper = AnyToolMetadata(original)
        let data = try JSONEncoder().encode(wrapper)
        let decoded = try JSONDecoder().decode(AnyToolMetadata.self, from: data)
        guard let result = decoded.metadata as? AppSource else {
            XCTFail("Decoded metadata is not AppSource")
            return
        }
        XCTAssertEqual(result.title, original.title)
        XCTAssertEqual(result.content, original.content)
        XCTAssertEqual(result.url, original.url)
        XCTAssertEqual(result.evidenceType, original.evidenceType)
    }

    func testAppSourcesRoundTrip() throws {
        let s1 = AppSource(title: "A", content: nil, url: "u1", evidenceType: "web")
        let s2 = AppSource(title: "B", content: "c", url: "u2", evidenceType: "paper")
        let original = AppSources(results: [s1, s2])
        let wrapper = AnyToolMetadata(original)
        let data = try JSONEncoder().encode(wrapper)
        let decoded = try JSONDecoder().decode(AnyToolMetadata.self, from: data)
        guard let result = decoded.metadata as? AppSources else {
            XCTFail("Decoded metadata is not AppSources")
            return
        }
        XCTAssertEqual(result.results.count, 2)
        XCTAssertEqual(result.results[0].title, "A")
        XCTAssertNil(result.results[0].content)
        XCTAssertEqual(result.results[1].content, "c")
    }

    func testAppMedicalEvidenceRoundTrip() throws {
        let src = AppSource(title: "Study", content: nil, url: "https://e.org", evidenceType: "report")
        let now = Date()
        let original = AppMedicalEvidence(sources: [src], evidenceLevel: "high", confidenceScore: 0.95, lastUpdated: now)
        let wrapper = AnyToolMetadata(original)
        let data = try JSONEncoder().encode(wrapper)
        let decoded = try JSONDecoder().decode(AnyToolMetadata.self, from: data)
        guard let result = decoded.metadata as? AppMedicalEvidence else {
            XCTFail("Decoded metadata is not AppMedicalEvidence")
            return
        }
        XCTAssertEqual(result.evidenceLevel, "high")
        XCTAssertEqual(result.sources.first?.title, "Study")
        XCTAssertEqual(result.confidenceScore, 0.95)
    }
} 