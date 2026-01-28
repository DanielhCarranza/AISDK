import XCTest
@testable import AISDK

final class AnthropicFilesServiceTests: XCTestCase {
    private func makeHTTPClient() -> AnthropicHTTPClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return AnthropicHTTPClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            session: session
        )
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testUploadFile() async throws {
        let client = makeHTTPClient()
        let service = AnthropicFilesService(httpClient: client)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/files")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "files-api-2025-04-14")

            let responseBody = AnthropicFile(
                id: "file_123",
                filename: "test.txt",
                purpose: .messageAttachment,
                createdAt: "2025-01-01T00:00:00Z",
                bytes: 5,
                mimeType: "text/plain"
            )

            let data = try AnthropicHTTPClient.encoder.encode(responseBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let file = try await service.uploadFile(
            data: Data("hello".utf8),
            filename: "test.txt",
            purpose: .messageAttachment,
            mimeType: "text/plain"
        )

        XCTAssertEqual(file.id, "file_123")
        XCTAssertEqual(file.filename, "test.txt")
    }

    func testListFiles() async throws {
        let client = makeHTTPClient()
        let service = AnthropicFilesService(httpClient: client)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/files")

            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []
            XCTAssertTrue(queryItems.contains { $0.name == "purpose" && $0.value == "message_attachment" })

            let responseBody = FileListResponse(
                data: [
                    AnthropicFile(
                        id: "file_123",
                        filename: "test.txt",
                        purpose: .messageAttachment,
                        createdAt: "2025-01-01T00:00:00Z",
                        bytes: 5
                    )
                ],
                hasMore: false
            )

            let data = try AnthropicHTTPClient.encoder.encode(responseBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let response = try await service.listFiles(purpose: .messageAttachment)
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data.first?.id, "file_123")
    }

    func testDeleteFile() async throws {
        let client = makeHTTPClient()
        let service = AnthropicFilesService(httpClient: client)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/v1/files/file_123")

            let responseBody = FileDeleteResponse(id: "file_123", deleted: true)
            let data = try AnthropicHTTPClient.encoder.encode(responseBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let response = try await service.deleteFile(id: "file_123")
        XCTAssertTrue(response.deleted)
    }
}
