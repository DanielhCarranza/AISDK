import Foundation

/// Structured error response from the Anthropic API
///
/// Anthropic returns errors in this format:
/// ```json
/// {
///   "type": "error",
///   "error": {
///     "type": "invalid_request_error",
///     "message": "max_tokens: 8192 > 4096, which is the maximum..."
///   }
/// }
/// ```
public struct AnthropicAPIError: Error, Codable, Sendable, Equatable {
    /// Always "error"
    public let type: String

    /// The error details
    public let error: ErrorDetail

    /// Detailed error information
    public struct ErrorDetail: Codable, Sendable, Equatable {
        /// Error type (e.g., "invalid_request_error", "authentication_error")
        public let type: String

        /// Human-readable error message
        public let message: String

        public init(type: String, message: String) {
            self.type = type
            self.message = message
        }
    }

    public init(type: String = "error", errorType: String, message: String) {
        self.type = type
        self.error = ErrorDetail(type: errorType, message: message)
    }
}

extension AnthropicAPIError: LocalizedError {
    public var errorDescription: String? {
        "\(error.type): \(error.message)"
    }
}

// MARK: - Error Type Constants

extension AnthropicAPIError {
    /// Common Anthropic API error types
    public enum ErrorType: String {
        /// Invalid request parameters
        case invalidRequest = "invalid_request_error"

        /// Authentication failed
        case authentication = "authentication_error"

        /// Permission denied
        case permission = "permission_error"

        /// Resource not found
        case notFound = "not_found_error"

        /// Request entity too large
        case requestTooLarge = "request_too_large"

        /// Rate limit exceeded
        case rateLimitError = "rate_limit_error"

        /// Internal server error
        case apiError = "api_error"

        /// Service temporarily overloaded
        case overloaded = "overloaded_error"
    }

    /// Check if this is a specific error type
    public func isErrorType(_ type: ErrorType) -> Bool {
        error.type == type.rawValue
    }

    /// Check if this error is retryable
    public var isRetryable: Bool {
        isErrorType(.rateLimitError) || isErrorType(.overloaded) || isErrorType(.apiError)
    }
}
