//
//  AIObjectResult.swift
//  AISDK
//
//  Result model for structured object generation operations
//  Based on Vercel AI SDK 6.x patterns
//

import Foundation

/// Result from structured object generation
public struct AIObjectResult<T: Codable & Sendable>: Sendable {
    /// The generated object
    public let object: T

    /// Token usage information
    public let usage: AIUsage

    /// Reason for completion
    public let finishReason: AIFinishReason

    /// Request ID for tracing
    public let requestId: String?

    /// Model used for generation
    public let model: String?

    /// Provider that handled the request
    public let provider: String?

    /// Raw JSON string of the generated object (useful for debugging)
    public let rawJSON: String?

    public init(
        object: T,
        usage: AIUsage = .zero,
        finishReason: AIFinishReason = .stop,
        requestId: String? = nil,
        model: String? = nil,
        provider: String? = nil,
        rawJSON: String? = nil
    ) {
        self.object = object
        self.usage = usage
        self.finishReason = finishReason
        self.requestId = requestId
        self.model = model
        self.provider = provider
        self.rawJSON = rawJSON
    }
}

// MARK: - AIObjectResult Extensions

public extension AIObjectResult {
    /// Check if generation completed normally (not due to length or error)
    var completedNormally: Bool {
        finishReason == .stop
    }

    /// Check if generation was truncated due to token limit
    var wasTruncated: Bool {
        finishReason == .length
    }

    /// Total tokens consumed (prompt + completion)
    var totalTokens: Int {
        usage.totalTokens
    }

    /// Map the result object to a different type
    /// Note: rawJSON is cleared since it no longer matches the transformed object
    func map<U: Codable & Sendable>(_ transform: (T) throws -> U) rethrows -> AIObjectResult<U> {
        AIObjectResult<U>(
            object: try transform(object),
            usage: usage,
            finishReason: finishReason,
            requestId: requestId,
            model: model,
            provider: provider,
            rawJSON: nil  // Cleared since it no longer matches the transformed object
        )
    }
}

// MARK: - AIObjectResult Equatable

extension AIObjectResult: Equatable where T: Equatable {
    public static func == (lhs: AIObjectResult<T>, rhs: AIObjectResult<T>) -> Bool {
        lhs.object == rhs.object &&
        lhs.usage == rhs.usage &&
        lhs.finishReason == rhs.finishReason &&
        lhs.requestId == rhs.requestId &&
        lhs.model == rhs.model &&
        lhs.provider == rhs.provider &&
        lhs.rawJSON == rhs.rawJSON
    }
}
