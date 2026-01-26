import XCTest
@testable import AISDK

final class WebSearchToolTests: XCTestCase {
    func testWebSearchToolFormatsResultsAndMetadata() async throws {
        let mockClient = MockWebSearchClient(results: [
            WebSearchSource(title: "Result One", url: "https://example.com/1", snippet: "First snippet"),
            WebSearchSource(title: "Result Two", url: "https://example.com/2", snippet: "Second snippet")
        ])

        var tool = WebSearchTool(client: mockClient)
        let arguments = """
        {"query":"Swift AI","num_results":2}
        """
        tool = try tool.validateAndSetParameters(Data(arguments.utf8))
        let (content, metadata) = try await tool.execute()

        XCTAssertTrue(content.contains("Web search results for: \"Swift AI\""))
        XCTAssertTrue(content.contains("[1] Result One"))
        XCTAssertTrue(content.contains("https://example.com/1"))
        XCTAssertTrue(content.contains("[2] Result Two"))

        guard let searchMetadata = metadata as? WebSearchMetadata else {
            XCTFail("Expected WebSearchMetadata")
            return
        }
        XCTAssertEqual(searchMetadata.query, "Swift AI")
        XCTAssertEqual(searchMetadata.sources.count, 2)
        XCTAssertEqual(searchMetadata.sources.first?.title, "Result One")
    }

    func testTavilyWebSearchClientBuildsRequest() async throws {
        let response = """
        {
          "results": [
            {
              "title": "Example Result",
              "url": "https://example.com",
              "content": "Snippet",
              "score": 0.9,
              "published_date": "2024-01-01"
            }
          ]
        }
        """
        let mockHTTP = MockWebSearchHTTPClient(responseData: Data(response.utf8))
        let client = TavilyWebSearchClient(
            session: mockHTTP,
            apiKey: "test-key",
            baseURL: URL(string: "https://api.test")!
        )

        let sources = try await client.search(query: "Swift", maxResults: 3)

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.title, "Example Result")
        XCTAssertEqual(sources.first?.url, "https://example.com")

        guard let request = mockHTTP.lastRequest else {
            XCTFail("Expected request to be captured")
            return
        }
        XCTAssertEqual(request.url?.absoluteString, "https://api.test/search")
        XCTAssertEqual(request.httpMethod, "POST")

        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            XCTFail("Expected JSON body")
            return
        }

        XCTAssertEqual(json["api_key"] as? String, "test-key")
        XCTAssertEqual(json["query"] as? String, "Swift")
        XCTAssertEqual(json["max_results"] as? Int, 3)
    }
}

private struct MockWebSearchClient: WebSearchClient {
    let results: [WebSearchSource]

    func search(query: String, maxResults: Int) async throws -> [WebSearchSource] {
        Array(results.prefix(maxResults))
    }
}

private final class MockWebSearchHTTPClient: WebSearchHTTPClient {
    let responseData: Data
    var lastRequest: URLRequest?

    init(responseData: Data) {
        self.responseData = responseData
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.test/search")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}
