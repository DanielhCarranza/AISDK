import XCTest
@testable import AISDK

final class AnthropicBatchServiceTests: XCTestCase {
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

    func testCreateBatch() async throws {
        let client = makeHTTPClient()
        let service = AnthropicBatchService(httpClient: client)

        let requestBody = AnthropicMessageRequestBody(
            maxTokens: 1,
            messages: [AnthropicInputMessage(content: [.text("Hi")], role: .user)],
            model: "claude-sonnet-4-5-20250929"
        )

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/messages/batches")

            // URLProtocol may convert httpBody to httpBodyStream, so read from stream if needed
            var bodyData: Data?
            if let httpBody = request.httpBody {
                bodyData = httpBody
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: 4096)
                    if read > 0 {
                        data.append(buffer, count: read)
                    }
                }
                bodyData = data
            }

            if let bodyData = bodyData, !bodyData.isEmpty {
                let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                let requests = body?["requests"] as? [[String: Any]]
                XCTAssertEqual(requests?.count, 1)
            }

            let responseBody = AnthropicBatch(
                id: "msgbatch_1",
                createdAt: "2025-01-01T00:00:00Z",
                expiresAt: "2025-01-02T00:00:00Z",
                processingStatus: .inProgress,
                requestCounts: BatchRequestCounts(processing: 1)
            )

            let data = try AnthropicHTTPClient.encoder.encode(responseBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let item = try AnthropicBatchRequestItem(customId: "req-1", params: requestBody)
        let batch = try await service.createBatch(requests: [item])
        XCTAssertEqual(batch.id, "msgbatch_1")
        XCTAssertEqual(batch.processingStatus, .inProgress)
    }

    func testListBatches() async throws {
        let client = makeHTTPClient()
        let service = AnthropicBatchService(httpClient: client)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/v1/messages/batches")

            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []
            XCTAssertTrue(queryItems.contains { $0.name == "limit" && $0.value == "5" })
            XCTAssertTrue(queryItems.contains { $0.name == "after_id" && $0.value == "after" })

            let responseBody = BatchListResponse(
                data: [
                    AnthropicBatch(
                        id: "msgbatch_1",
                        createdAt: "2025-01-01T00:00:00Z",
                        expiresAt: "2025-01-02T00:00:00Z",
                        processingStatus: .ended,
                        requestCounts: BatchRequestCounts(succeeded: 1)
                    )
                ],
                hasMore: false
            )

            let data = try AnthropicHTTPClient.encoder.encode(responseBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let response = try await service.listBatches(limit: 5, afterId: "after")
        XCTAssertEqual(response.data.count, 1)
        XCTAssertEqual(response.data.first?.id, "msgbatch_1")
    }

    func testCancelBatch() async throws {
        let client = makeHTTPClient()
        let service = AnthropicBatchService(httpClient: client)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/messages/batches/msgbatch_1/cancel")

            let responseBody = AnthropicBatch(
                id: "msgbatch_1",
                createdAt: "2025-01-01T00:00:00Z",
                expiresAt: "2025-01-02T00:00:00Z",
                processingStatus: .canceling,
                requestCounts: BatchRequestCounts(processing: 1)
            )

            let data = try AnthropicHTTPClient.encoder.encode(responseBody)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let batch = try await service.cancelBatch(id: "msgbatch_1")
        XCTAssertEqual(batch.processingStatus, .canceling)
    }
}
