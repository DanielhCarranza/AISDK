//
//  WebSearchTool.swift
//  AISDK
//
//  Tavily-backed web search tool with citation metadata
//

import Foundation

// MARK: - Web Search Metadata

public struct WebSearchSource: Codable, Sendable, Equatable {
    public let title: String
    public let url: String
    public let snippet: String?
    public let score: Double?
    public let publishedDate: String?

    public init(
        title: String,
        url: String,
        snippet: String? = nil,
        score: Double? = nil,
        publishedDate: String? = nil
    ) {
        self.title = title
        self.url = url
        self.snippet = snippet
        self.score = score
        self.publishedDate = publishedDate
    }
}

public struct WebSearchMetadata: ToolMetadata, Codable, Sendable, Equatable {
    public let query: String
    public let sources: [WebSearchSource]

    public init(query: String, sources: [WebSearchSource]) {
        self.query = query
        self.sources = sources
    }
}

// MARK: - Tavily Client

public protocol WebSearchHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: WebSearchHTTPClient {}

public protocol WebSearchClient: Sendable {
    func search(query: String, maxResults: Int) async throws -> [WebSearchSource]
}

public struct TavilyWebSearchClient: WebSearchClient, Sendable {
    private let session: WebSearchHTTPClient
    private let apiKey: String?
    private let baseURL: URL

    public init(
        session: WebSearchHTTPClient = URLSession.shared,
        apiKey: String? = nil,
        baseURL: URL = URL(string: "https://api.tavily.com")!
    ) {
        self.session = session
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public func search(query: String, maxResults: Int) async throws -> [WebSearchSource] {
        let apiKey = try resolveAPIKey()
        let clampedResults = max(1, min(maxResults, 10))

        let requestURL = baseURL.appendingPathComponent("search")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30  // 30 second timeout to prevent hanging
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = TavilySearchRequest(
            apiKey: apiKey,
            query: query,
            maxResults: clampedResults,
            searchDepth: "basic",
            includeAnswer: false,
            includeRawContent: false,
            includeImages: false
        )
        request.httpBody = try JSONEncoder().encode(body)

        // Debug: Log request start
        let startTime = Date()
        FileHandle.standardError.write("[WebSearch] Starting request to \(requestURL) for query: \"\(query)\"\n".data(using: .utf8)!)

        let (data, response) = try await session.data(for: request)

        // Debug: Log response received
        let elapsed = Date().timeIntervalSince(startTime)
        if let http = response as? HTTPURLResponse {
            FileHandle.standardError.write("[WebSearch] Response received in \(String(format: "%.2f", elapsed))s - Status: \(http.statusCode)\n".data(using: .utf8)!)
        }

        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(TavilySearchResponse.self, from: data)
        return decoded.results.map { result in
            WebSearchSource(
                title: result.title,
                url: result.url,
                snippet: result.content,
                score: result.score,
                publishedDate: result.publishedDate
            )
        }
    }

    private func resolveAPIKey() throws -> String {
        if let apiKey = apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return apiKey
        }
        if let envKey = ProcessInfo.processInfo.environment["TAVILY_API_KEY"],
           !envKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return envKey
        }
        throw WebSearchError.missingAPIKey
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw WebSearchError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WebSearchError.httpError(statusCode: http.statusCode, body: body)
        }
    }
}

private struct TavilySearchRequest: Encodable {
    let apiKey: String
    let query: String
    let maxResults: Int
    let searchDepth: String
    let includeAnswer: Bool
    let includeRawContent: Bool
    let includeImages: Bool

    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case query
        case maxResults = "max_results"
        case searchDepth = "search_depth"
        case includeAnswer = "include_answer"
        case includeRawContent = "include_raw_content"
        case includeImages = "include_images"
    }
}

private struct TavilySearchResponse: Decodable {
    let results: [TavilySearchResult]
}

private struct TavilySearchResult: Decodable {
    let title: String
    let url: String
    let content: String?
    let score: Double?
    let publishedDate: String?

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case content
        case score
        case publishedDate = "published_date"
    }
}

public enum WebSearchError: Error, LocalizedError, Sendable {
    case missingAPIKey
    case invalidResponse
    case httpError(statusCode: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing TAVILY_API_KEY for web search."
        case .invalidResponse:
            return "Invalid response from web search provider."
        case .httpError(let statusCode, let body):
            return "Web search failed with HTTP \(statusCode): \(body)"
        }
    }
}

// MARK: - Tool

public struct WebSearchTool: Tool {
    public let name = "web_search"
    public let description = "Search the web for information on a given query. Returns relevant results with titles, snippets, and URLs."

    @Parameter(description: "The search query")
    public var query: String = ""

    @Parameter(
        description: "Number of results to return (1-10, default 5)",
        validation: ["minimum": 1.0, "maximum": 10.0]
    )
    public var numResults: Int = 5

    private let client: any WebSearchClient

    public init() {
        self._query = Parameter(wrappedValue: "", description: "The search query")
        self._numResults = Parameter(
            wrappedValue: 5,
            description: "Number of results to return (1-10, default 5)",
            validation: ["minimum": 1.0, "maximum": 10.0]
        )
        self.client = TavilyWebSearchClient()
    }

    public init(client: any WebSearchClient) {
        self._query = Parameter(wrappedValue: "", description: "The search query")
        self._numResults = Parameter(
            wrappedValue: 5,
            description: "Number of results to return (1-10, default 5)",
            validation: ["minimum": 1.0, "maximum": 10.0]
        )
        self.client = client
    }

    public func execute() async throws -> (content: String, metadata: ToolMetadata?) {
        let clamped = max(1, min(numResults, 10))
        let sources = try await client.search(query: query, maxResults: clamped)
        let metadata = WebSearchMetadata(query: query, sources: sources)
        let content = formatSearchResults(query: query, sources: sources)
        return (content, metadata)
    }

    private func formatSearchResults(query: String, sources: [WebSearchSource]) -> String {
        var output = "Web search results for: \"\(query)\"\n"
        output += "Use [n] to cite sources by index.\n"
        output += String(repeating: "─", count: 50) + "\n\n"

        for (index, source) in sources.enumerated() {
            let title = source.title.isEmpty ? source.url : source.title
            output += "[\(index + 1)] \(title)\n"
            if let snippet = source.snippet, !snippet.isEmpty {
                output += "    \(snippet)\n"
            }
            output += "    \(source.url)\n\n"
        }

        if sources.isEmpty {
            output += "No results returned."
        }

        return output
    }
}
