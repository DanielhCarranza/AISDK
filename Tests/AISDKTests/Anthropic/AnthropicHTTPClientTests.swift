import XCTest
@testable import AISDK

final class AnthropicHTTPClientTests: XCTestCase {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeClient() -> AnthropicHTTPClient {
        AnthropicHTTPClient(
            apiKey: "test-key",
            baseURL: URL(string: "https://example.com/v1")!,
            session: makeSession(),
            anthropicVersion: "2023-06-01"
        )
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testGetAddsHeadersAndDecodes() async throws {
        struct DummyResponse: Codable, Equatable {
            let name: String
        }

        let expected = DummyResponse(name: "ok")
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/models")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "files-api-2025-04-14")

            let data = try JSONEncoder().encode(expected)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, data)
        }

        let client = makeClient()
        let response: DummyResponse = try await client.get(
            path: "models",
            betaHeaders: "files-api-2025-04-14"
        )

        XCTAssertEqual(response, expected)
    }

    func testPostEncodesSnakeCase() async throws {
        struct DummyBody: Codable {
            let maxTokens: Int
            let requestId: String
        }

        struct DummyResponse: Codable {
            let ok: Bool
        }

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")

            // URLProtocol may convert httpBody to httpBodyStream, so read from stream if needed
            var bodyData: Data?
            if let httpBody = request.httpBody {
                bodyData = httpBody
            } else if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var data = Data()
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
                defer { buffer.deallocate() }
                while stream.hasBytesAvailable {
                    let read = stream.read(buffer, maxLength: 1024)
                    if read > 0 {
                        data.append(buffer, count: read)
                    }
                }
                bodyData = data
            }

            if let bodyData = bodyData, !bodyData.isEmpty {
                let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
                XCTAssertEqual(body?["max_tokens"] as? Int, 42)
                XCTAssertEqual(body?["request_id"] as? String, "abc")
            }

            let data = try JSONEncoder().encode(DummyResponse(ok: true))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = makeClient()
        let response: DummyResponse = try await client.post(
            path: "tests",
            body: DummyBody(maxTokens: 42, requestId: "abc")
        )
        XCTAssertTrue(response.ok)
    }

    func testErrorDecodesAnthropicAPIError() async {
        let errorPayload = AnthropicAPIError(
            errorType: "invalid_request_error",
            message: "Bad request"
        )

        MockURLProtocol.requestHandler = { request in
            let data = try JSONEncoder().encode(errorPayload)
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = makeClient()

        do {
            let _: [String: String] = try await client.get(path: "broken")
            XCTFail("Expected AnthropicAPIError")
        } catch let error as AnthropicAPIError {
            XCTAssertTrue(error.isErrorType(.invalidRequest))
            XCTAssertEqual(error.error.message, "Bad request")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRateLimitErrorIncludesRetryAfter() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["retry-after": "120"]
            )!
            return (response, Data())
        }

        let client = makeClient()

        do {
            let _: [String: String] = try await client.get(path: "rate-limited")
            XCTFail("Expected rate limit error")
        } catch let error as LLMError {
            switch error {
            case .networkError(let code, let message):
                XCTAssertEqual(code, 429)
                XCTAssertTrue(message.contains("Retry after 120"))
            default:
                XCTFail("Expected networkError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUploadMultipartBuildsRequest() async throws {
        struct DummyResponse: Codable {
            let id: String
        }

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            XCTAssertTrue(contentType.contains("multipart/form-data; boundary="))

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
                let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
                XCTAssertTrue(bodyString.contains("name=\"purpose\""), "Body should contain purpose field")
                XCTAssertTrue(bodyString.contains("message_attachment"), "Body should contain message_attachment")
                XCTAssertTrue(bodyString.contains("filename=\"test.txt\""), "Body should contain filename")
            }

            let data = try JSONEncoder().encode(DummyResponse(id: "file_123"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        let client = makeClient()
        let response: DummyResponse = try await client.uploadMultipart(
            path: "files",
            formFields: [(name: "purpose", value: "message_attachment")],
            fileData: Data("hello".utf8),
            filename: "test.txt",
            mimeType: "text/plain"
        )

        XCTAssertEqual(response.id, "file_123")
    }
}
