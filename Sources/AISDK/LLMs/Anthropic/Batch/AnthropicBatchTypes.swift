import Foundation

// MARK: - Request Types

/// A single request item within a batch
public struct AnthropicBatchRequestItem: Codable, Sendable, Equatable {
    /// Unique identifier for tracking this request (1-64 characters)
    public let customId: String

    /// Standard message request parameters (stored as raw JSON)
    public let params: AnyCodable

    public init(customId: String, params: AnyCodable) {
        self.customId = customId
        self.params = params
    }

    public init(customId: String, params: AnthropicMessageRequestBody) throws {
        let data = try AnthropicHTTPClient.encoder.encode(params)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        self.customId = customId
        self.params = AnyCodable(json)
    }
}

/// Request body for creating a batch
public struct CreateBatchRequest: Codable, Sendable {
    public let requests: [AnthropicBatchRequestItem]

    public init(requests: [AnthropicBatchRequestItem]) {
        self.requests = requests
    }
}

// MARK: - Response Types

/// Batch processing status
public enum BatchProcessingStatus: String, Codable, Sendable {
    /// Batch is being processed
    case inProgress = "in_progress"

    /// Cancellation has been initiated
    case canceling = "canceling"

    /// Processing has ended (check request_counts for details)
    case ended = "ended"
}

/// Counts of requests in various states
public struct BatchRequestCounts: Codable, Sendable, Equatable {
    /// Requests that were canceled
    public let canceled: Int

    /// Requests that encountered errors
    public let errored: Int

    /// Requests that expired
    public let expired: Int

    /// Requests still being processed
    public let processing: Int

    /// Requests that completed successfully
    public let succeeded: Int

    /// Total requests in the batch
    public var total: Int {
        canceled + errored + expired + processing + succeeded
    }

    public init(
        canceled: Int = 0,
        errored: Int = 0,
        expired: Int = 0,
        processing: Int = 0,
        succeeded: Int = 0
    ) {
        self.canceled = canceled
        self.errored = errored
        self.expired = expired
        self.processing = processing
        self.succeeded = succeeded
    }
}

/// A batch of message requests
public struct AnthropicBatch: Codable, Sendable, Equatable {
    /// Unique batch identifier (e.g., "msgbatch_abc123")
    public let id: String

    /// ISO timestamp when batch was archived (if applicable)
    public let archivedAt: String?

    /// ISO timestamp when cancellation was initiated (if applicable)
    public let cancelInitiatedAt: String?

    /// ISO timestamp when batch was created
    public let createdAt: String

    /// ISO timestamp when processing ended (if applicable)
    public let endedAt: String?

    /// ISO timestamp when batch will expire
    public let expiresAt: String

    /// Current processing status
    public let processingStatus: BatchProcessingStatus

    /// Request counts by state
    public let requestCounts: BatchRequestCounts

    /// URL to download results (available when status is "ended")
    public let resultsUrl: String?

    /// Always "message_batch"
    public let type: String

    public init(
        id: String,
        archivedAt: String? = nil,
        cancelInitiatedAt: String? = nil,
        createdAt: String,
        endedAt: String? = nil,
        expiresAt: String,
        processingStatus: BatchProcessingStatus,
        requestCounts: BatchRequestCounts,
        resultsUrl: String? = nil,
        type: String = "message_batch"
    ) {
        self.id = id
        self.archivedAt = archivedAt
        self.cancelInitiatedAt = cancelInitiatedAt
        self.createdAt = createdAt
        self.endedAt = endedAt
        self.expiresAt = expiresAt
        self.processingStatus = processingStatus
        self.requestCounts = requestCounts
        self.resultsUrl = resultsUrl
        self.type = type
    }
}

// MARK: - Result Types

/// Type of batch result
public enum BatchResultType: String, Codable, Sendable {
    case succeeded = "succeeded"
    case errored = "errored"
    case canceled = "canceled"
    case expired = "expired"
}

/// Error details for a failed batch request
public struct BatchError: Codable, Sendable, Equatable {
    public let type: String
    public let message: String

    public init(type: String, message: String) {
        self.type = type
        self.message = message
    }
}

/// Content of a batch result
public struct BatchResultContent: Decodable, Sendable {
    public let type: BatchResultType
    public let message: AnthropicMessageResponseBody?
    public let error: BatchError?

    public init(
        type: BatchResultType,
        message: AnthropicMessageResponseBody? = nil,
        error: BatchError? = nil
    ) {
        self.type = type
        self.message = message
        self.error = error
    }
}

/// A single result from a batch
public struct AnthropicBatchResult: Decodable, Sendable {
    public let customId: String
    public let result: BatchResultContent

    public init(customId: String, result: BatchResultContent) {
        self.customId = customId
        self.result = result
    }
}

// MARK: - List Response

/// Response from listing batches
public struct BatchListResponse: Codable, Sendable {
    public let data: [AnthropicBatch]
    public let hasMore: Bool
    public let firstId: String?
    public let lastId: String?

    public init(
        data: [AnthropicBatch],
        hasMore: Bool = false,
        firstId: String? = nil,
        lastId: String? = nil
    ) {
        self.data = data
        self.hasMore = hasMore
        self.firstId = firstId
        self.lastId = lastId
    }
}

// MARK: - Validation

/// Validation helpers for batch requests
public enum BatchRequestValidation {
    /// Maximum number of requests per batch
    public static let maxRequests = 100_000

    /// Maximum total payload size in bytes (256 MB)
    public static let maxPayloadBytes = 256 * 1024 * 1024

    /// Minimum custom_id length
    public static let minCustomIdLength = 1

    /// Maximum custom_id length
    public static let maxCustomIdLength = 64

    /// Validate a batch request before submission
    public static func validate(requests: [AnthropicBatchRequestItem]) throws {
        guard requests.count <= maxRequests else {
            throw LLMError.invalidRequest(
                "Batch exceeds maximum of \(maxRequests) requests (got \(requests.count))"
            )
        }

        guard !requests.isEmpty else {
            throw LLMError.invalidRequest("Batch must contain at least one request")
        }

        let ids = requests.map { $0.customId }
        let uniqueIds = Set(ids)
        guard ids.count == uniqueIds.count else {
            throw LLMError.invalidRequest("Batch contains duplicate custom_id values")
        }

        for request in requests {
            let length = request.customId.count
            guard (minCustomIdLength...maxCustomIdLength).contains(length) else {
                throw LLMError.invalidRequest(
                    "custom_id must be \(minCustomIdLength)-\(maxCustomIdLength) characters " +
                    "(got \(length) for '\(request.customId)')"
                )
            }
        }
    }
}
