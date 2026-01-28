import Foundation

/// Shared HTTP client for all Anthropic API calls
///
/// Provides consistent behavior for:
/// - JSON encoding/decoding with snake_case conversion
/// - API authentication headers
/// - Beta feature headers
/// - Rate limit handling
/// - Error response parsing
public actor AnthropicHTTPClient {

    // MARK: - Properties

    private let apiKey: String
    private let baseURL: URL
    private let session: URLSession
    private let anthropicVersion: String

    // MARK: - Shared Encoder/Decoder

    /// JSON encoder configured for Anthropic API (snake_case)
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    /// JSON decoder configured for Anthropic API (snake_case)
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    // MARK: - Initialization

    /// Create an HTTP client for Anthropic API
    ///
    /// - Parameters:
    ///   - apiKey: Anthropic API key
    ///   - baseURL: Base URL for API calls (default: https://api.anthropic.com/v1)
    ///   - session: URLSession to use (default: .shared)
    ///   - anthropicVersion: API version header value (default: 2023-06-01)
    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        session: URLSession = .shared,
        anthropicVersion: String = "2023-06-01"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.session = session
        self.anthropicVersion = anthropicVersion
    }

    // MARK: - Request Methods

    /// Perform a GET request
    public func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        betaHeaders: String? = nil
    ) async throws -> T {
        let request = try buildRequest(
            path: path,
            method: "GET",
            queryItems: queryItems,
            betaHeaders: betaHeaders
        )
        return try await execute(request)
    }

    /// Perform a POST request
    public func post<T: Decodable, B: Encodable>(
        path: String,
        body: B?,
        betaHeaders: String? = nil
    ) async throws -> T {
        var request = try buildRequest(
            path: path,
            method: "POST",
            betaHeaders: betaHeaders
        )

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        return try await execute(request)
    }

    /// Perform a POST request without response body
    public func postNoResponse<B: Encodable>(
        path: String,
        body: B?,
        betaHeaders: String? = nil
    ) async throws {
        var request = try buildRequest(
            path: path,
            method: "POST",
            betaHeaders: betaHeaders
        )

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    /// Perform a DELETE request
    public func delete(
        path: String,
        betaHeaders: String? = nil
    ) async throws {
        let request = try buildRequest(
            path: path,
            method: "DELETE",
            betaHeaders: betaHeaders
        )

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    /// Perform a DELETE request with response
    public func delete<T: Decodable>(
        path: String,
        betaHeaders: String? = nil
    ) async throws -> T {
        let request = try buildRequest(
            path: path,
            method: "DELETE",
            betaHeaders: betaHeaders
        )
        return try await execute(request)
    }

    // MARK: - Streaming

    /// Perform a streaming GET request
    public func streamGet(
        path: String,
        betaHeaders: String? = nil
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        let request = try buildRequest(
            path: path,
            method: "GET",
            betaHeaders: betaHeaders
        )

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError(nil, "Invalid response type")
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap { Int($0) } ?? 60
            throw LLMError.rateLimitExceeded(retryAfter: retryAfter)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.networkError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
        }

        return (bytes, httpResponse)
    }

    // MARK: - Multipart Upload

    /// Upload a file using multipart form data
    public func uploadMultipart<T: Decodable>(
        path: String,
        formFields: [(name: String, value: String)],
        fileData: Data,
        filename: String,
        fileFieldName: String = "file",
        mimeType: String = "application/octet-stream",
        betaHeaders: String? = nil
    ) async throws -> T {
        let boundary = UUID().uuidString
        var request = try buildRequest(
            path: path,
            method: "POST",
            betaHeaders: betaHeaders
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()

        for (name, value) in formFields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        return try await execute(request)
    }

    // MARK: - Private Helpers

    private func buildRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem]? = nil,
        betaHeaders: String? = nil
    ) throws -> URLRequest {
        let base: URL
        if let absolute = URL(string: path), absolute.scheme != nil, absolute.host != nil {
            base = absolute
        } else {
            base = baseURL.appendingPathComponent(path)
        }

        var components = URLComponents(
            url: base,
            resolvingAgainstBaseURL: false
        )

        if let queryItems, !queryItems.isEmpty {
            components?.queryItems = queryItems
        }

        guard let url = components?.url else {
            throw LLMError.invalidRequest("Invalid URL: \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        if let betaHeaders {
            request.setValue(betaHeaders, forHTTPHeaderField: "anthropic-beta")
        }

        return request
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw LLMError.parsingError("Failed to decode response: \(error.localizedDescription)")
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError(nil, "Invalid response type")
        }

        if httpResponse.statusCode == 429 {
            let retryAfter = httpResponse.value(forHTTPHeaderField: "retry-after")
                .flatMap { Int($0) } ?? 60
            throw LLMError.rateLimitExceeded(retryAfter: retryAfter)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let data, let apiError = try? Self.decoder.decode(AnthropicAPIError.self, from: data) {
                throw apiError
            }

            throw LLMError.networkError(httpResponse.statusCode, "HTTP \(httpResponse.statusCode)")
        }
    }
}

// MARK: - Rate Limit Helper

public extension LLMError {
    /// Rate limit exceeded with retry delay
    static func rateLimitExceeded(retryAfter: Int) -> LLMError {
        .networkError(429, "Rate limit exceeded. Retry after \(retryAfter) seconds.")
    }
}
