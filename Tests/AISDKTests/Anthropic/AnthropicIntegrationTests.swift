import XCTest
import Alamofire
@testable import AISDK

final class AnthropicIntegrationTests: XCTestCase {
    private func makeSession() -> Session {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return Session(configuration: configuration)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testMessageRequestAddsThinkingAndBetaHeader() async throws {
        let session = makeSession()
        let service = AnthropicService(
            apiKey: "test-key",
            baseUrl: "https://example.com/v1",
            session: session,
            betaConfiguration: .init(extendedThinking: true, filesAPI: true)
        )

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-beta"), "files-api-2025-04-14")

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
                XCTAssertNotNil(body?["thinking"])
            }

            let responsePayload: [String: Any] = [
                "id": "msg_1",
                "type": "message",
                "role": "assistant",
                "model": "claude-sonnet-4-5-20250929",
                "content": [
                    ["type": "thinking", "thinking": "Plan", "signature": "sig"],
                    ["type": "text", "text": "Hi"]
                ],
                "stop_reason": "end_turn",
                "stop_sequence": NSNull(),
                "usage": ["input_tokens": 1, "output_tokens": 2]
            ]

            let data = try JSONSerialization.data(withJSONObject: responsePayload, options: [])
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }

        // maxTokens must be > thinking budget (which is max(1024, maxTokens/4))
        // With extendedThinking enabled, minimum is 1024+1 = 1025
        let request = AnthropicMessageRequestBody(
            maxTokens: 2048,
            messages: [AnthropicInputMessage(content: [.text("Hello")], role: .user)],
            model: "claude-sonnet-4-5-20250929"
        )

        let response = try await service.messageRequest(body: request)
        XCTAssertEqual(response.content.count, 2)
    }
}
