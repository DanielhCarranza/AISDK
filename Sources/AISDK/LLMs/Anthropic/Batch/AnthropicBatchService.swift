import Foundation

/// Service for Anthropic Batch API operations
public actor AnthropicBatchService {

    // MARK: - Properties

    private let httpClient: AnthropicHTTPClient

    // MARK: - Initialization

    /// Create a batch service
    public init(
        apiKey: String,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!
    ) {
        self.httpClient = AnthropicHTTPClient(apiKey: apiKey, baseURL: baseURL)
    }

    /// Create a batch service with a shared HTTP client
    public init(httpClient: AnthropicHTTPClient) {
        self.httpClient = httpClient
    }

    // MARK: - Create Batch

    public func createBatch(
        requests: [AnthropicBatchRequestItem]
    ) async throws -> AnthropicBatch {
        try BatchRequestValidation.validate(requests: requests)

        let body = CreateBatchRequest(requests: requests)
        return try await httpClient.post(
            path: "messages/batches",
            body: body
        )
    }

    // MARK: - Get Batch

    public func getBatch(id: String) async throws -> AnthropicBatch {
        return try await httpClient.get(path: "messages/batches/\(id)")
    }

    // MARK: - List Batches

    public func listBatches(
        limit: Int? = nil,
        afterId: String? = nil,
        beforeId: String? = nil
    ) async throws -> BatchListResponse {
        var queryItems: [URLQueryItem] = []

        if let limit {
            queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        if let afterId {
            queryItems.append(URLQueryItem(name: "after_id", value: afterId))
        }
        if let beforeId {
            queryItems.append(URLQueryItem(name: "before_id", value: beforeId))
        }

        return try await httpClient.get(
            path: "messages/batches",
            queryItems: queryItems.isEmpty ? nil : queryItems
        )
    }

    // MARK: - Cancel Batch

    public func cancelBatch(id: String) async throws -> AnthropicBatch {
        return try await httpClient.post(
            path: "messages/batches/\(id)/cancel",
            body: nil as CreateBatchRequest?
        )
    }

    // MARK: - Stream Results

    public func streamResults(
        batchId: String
    ) -> AsyncThrowingStream<AnthropicBatchResult, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let batch = try await getBatch(id: batchId)

                    guard batch.processingStatus == .ended else {
                        continuation.finish(throwing: LLMError.invalidRequest(
                            "Batch is not complete (status: \(batch.processingStatus))"
                        ))
                        return
                    }

                    guard let resultsUrl = batch.resultsUrl else {
                        continuation.finish(throwing: LLMError.invalidRequest(
                            "Batch has no results URL"
                        ))
                        return
                    }

                    let (bytes, _) = try await httpClient.streamGet(path: resultsUrl)

                    for try await line in bytes.lines {
                        guard !line.isEmpty else { continue }

                        let data = Data(line.utf8)
                        let result = try AnthropicHTTPClient.decoder.decode(
                            AnthropicBatchResult.self,
                            from: data
                        )
                        continuation.yield(result)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Convenience Methods

    public func waitForBatch(
        id: String,
        pollInterval: Duration = .seconds(30),
        timeout: Duration = .seconds(24 * 3600)
    ) async throws -> AnthropicBatch {
        let startTime = ContinuousClock.now

        while true {
            let batch = try await getBatch(id: id)

            if batch.processingStatus == .ended {
                return batch
            }

            let elapsed = ContinuousClock.now - startTime
            if elapsed > timeout {
                throw LLMError.networkError(nil, "Timeout waiting for batch completion")
            }

            try await Task.sleep(for: pollInterval)
        }
    }

    public func getAllResults(batchId: String) async throws -> [AnthropicBatchResult] {
        var results: [AnthropicBatchResult] = []

        for try await result in streamResults(batchId: batchId) {
            results.append(result)
        }

        return results
    }
}
