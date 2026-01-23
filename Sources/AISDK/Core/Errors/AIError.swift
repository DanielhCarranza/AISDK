//
//  AIError.swift
//  AISDK
//
//  Unified error taxonomy for AI SDK operations
//  Based on Vercel AI SDK 6.x error patterns with PHI redaction enforcement
//

import Foundation

// MARK: - AIErrorCode

/// Error codes for categorizing AI errors
///
/// Maps to Vercel AI SDK 6.x error categories while adding
/// healthcare-specific codes for PHI protection.
public enum AIErrorCode: String, Sendable, Codable, CaseIterable {
    // Request errors
    /// Invalid request parameters
    case invalidRequest = "invalid_request"
    /// Missing required parameters
    case missingParameter = "missing_parameter"
    /// Invalid model identifier
    case invalidModel = "invalid_model"
    /// Request validation failed
    case validationFailed = "validation_failed"

    // Provider errors
    /// Authentication failed
    case authenticationFailed = "authentication_failed"
    /// Rate limit exceeded
    case rateLimitExceeded = "rate_limit_exceeded"
    /// Provider service unavailable
    case providerUnavailable = "provider_unavailable"
    /// Model not available on provider
    case modelNotAvailable = "model_not_available"
    /// Provider quota exceeded
    case quotaExceeded = "quota_exceeded"

    // Content errors
    /// Content filtered by safety systems
    case contentFiltered = "content_filtered"
    /// Context length exceeded
    case contextLengthExceeded = "context_length_exceeded"
    /// Invalid response format
    case invalidResponse = "invalid_response"
    /// Response parsing failed
    case parsingFailed = "parsing_failed"

    // Stream errors
    /// Stream connection failed
    case streamConnectionFailed = "stream_connection_failed"
    /// Stream interrupted
    case streamInterrupted = "stream_interrupted"
    /// Stream timeout
    case streamTimeout = "stream_timeout"

    // Tool errors
    /// Tool execution failed
    case toolExecutionFailed = "tool_execution_failed"
    /// Tool not found
    case toolNotFound = "tool_not_found"
    /// Invalid tool arguments
    case invalidToolArguments = "invalid_tool_arguments"
    /// Tool timeout exceeded
    case toolTimeout = "tool_timeout"

    // Network errors
    /// Network connection failed
    case networkFailed = "network_failed"
    /// Request timeout
    case timeout = "timeout"

    // PHI/Security errors
    /// Provider not allowed for data sensitivity level
    case providerNotAllowed = "provider_not_allowed"
    /// PHI data requires explicit provider allowlist
    case phiRequiresAllowlist = "phi_requires_allowlist"
    /// Sensitive data exposure risk
    case sensitiveDataExposure = "sensitive_data_exposure"

    // System errors
    /// Internal SDK error
    case internalError = "internal_error"
    /// Operation cancelled
    case cancelled = "cancelled"
    /// Unknown error
    case unknown = "unknown"

    /// Whether this error is potentially recoverable via retry
    public var isRetryable: Bool {
        switch self {
        case .rateLimitExceeded, .providerUnavailable, .networkFailed,
             .timeout, .streamConnectionFailed, .streamInterrupted, .streamTimeout:
            return true
        default:
            return false
        }
    }

    /// Whether this error indicates a client-side issue (4xx-like)
    public var isClientError: Bool {
        switch self {
        case .invalidRequest, .missingParameter, .invalidModel, .validationFailed,
             .authenticationFailed, .quotaExceeded, .contextLengthExceeded,
             .invalidToolArguments, .providerNotAllowed, .phiRequiresAllowlist:
            return true
        default:
            return false
        }
    }

    /// Whether this error is PHI/security related
    public var isSecurityRelated: Bool {
        switch self {
        case .providerNotAllowed, .phiRequiresAllowlist, .sensitiveDataExposure, .authenticationFailed:
            return true
        default:
            return false
        }
    }
}

// MARK: - AIErrorContext

/// Context information for AI errors (with PHI redaction)
///
/// This struct captures error context while enforcing PHI redaction
/// to prevent sensitive data from leaking into logs or error reports.
public struct AIErrorContext: Sendable, Equatable {
    /// The request ID (trace ID) if available
    public let requestId: String?

    /// The provider that produced the error
    public let provider: String?

    /// The model that was requested
    public let model: String?

    /// HTTP status code if applicable
    public let statusCode: Int?

    /// Whether PHI redaction was applied
    public let phiRedacted: Bool

    /// Additional metadata (never contains PHI)
    public let metadata: [String: String]

    public init(
        requestId: String? = nil,
        provider: String? = nil,
        model: String? = nil,
        statusCode: Int? = nil,
        phiRedacted: Bool = false,
        metadata: [String: String] = [:]
    ) {
        self.requestId = requestId
        self.provider = provider
        self.model = model
        self.statusCode = statusCode
        self.phiRedacted = phiRedacted
        self.metadata = metadata
    }

    /// Empty context
    public static let empty = AIErrorContext()

    /// Create a redacted copy for PHI-safe logging
    public func redacted() -> AIErrorContext {
        AIErrorContext(
            requestId: requestId,
            provider: provider,
            model: model,
            statusCode: statusCode,
            phiRedacted: true,
            metadata: [:]  // Clear metadata when redacting
        )
    }
}

// MARK: - AISDKErrorV2

/// Unified error type for AISDK 2.0 operations
///
/// This error type provides a consistent interface across all SDK operations
/// while enforcing PHI redaction for healthcare compliance.
///
/// Example:
/// ```swift
/// do {
///     let result = try await model.generateText(request: request)
/// } catch let error as AISDKErrorV2 {
///     print("Error code: \(error.code)")
///     print("Message: \(error.message)")
///     if error.code.isRetryable {
///         // Attempt retry
///     }
/// }
/// ```
public struct AISDKErrorV2: Error, Sendable, Equatable {
    /// The error code categorizing this error
    public let code: AIErrorCode

    /// Human-readable error message (PHI-safe)
    public let message: String

    /// Error context with additional information
    public let context: AIErrorContext

    /// The underlying error if available (not included in Equatable)
    private let _underlyingError: UnderlyingErrorBox?

    /// Access the underlying error
    public var underlyingError: Error? {
        _underlyingError?.error
    }

    /// Wrapper to make underlying error Sendable-compatible
    private struct UnderlyingErrorBox: Sendable {
        // Using @unchecked because we store the error description, not the error itself
        // for cross-isolation boundary safety
        let error: Error
        let description: String

        init(_ error: Error) {
            self.error = error
            self.description = error.localizedDescription
        }
    }

    public init(
        code: AIErrorCode,
        message: String,
        context: AIErrorContext = .empty,
        underlyingError: Error? = nil
    ) {
        self.code = code
        self.message = message
        self.context = context
        self._underlyingError = underlyingError.map { UnderlyingErrorBox($0) }
    }

    // MARK: - Equatable

    public static func == (lhs: AISDKErrorV2, rhs: AISDKErrorV2) -> Bool {
        lhs.code == rhs.code &&
        lhs.message == rhs.message &&
        lhs.context == rhs.context
    }
}

// MARK: - AISDKErrorV2 LocalizedError

extension AISDKErrorV2: LocalizedError {
    public var errorDescription: String? {
        message
    }

    public var failureReason: String? {
        code.rawValue
    }

    public var recoverySuggestion: String? {
        if code.isRetryable {
            return "This error may be transient. Consider retrying the request."
        }
        return nil
    }
}

// MARK: - AISDKErrorV2 CustomStringConvertible

extension AISDKErrorV2: CustomStringConvertible {
    public var description: String {
        var parts = ["[\(code.rawValue)] \(message)"]

        if let provider = context.provider {
            parts.append("provider: \(provider)")
        }
        if let model = context.model {
            parts.append("model: \(model)")
        }
        if let statusCode = context.statusCode {
            parts.append("status: \(statusCode)")
        }
        if context.phiRedacted {
            parts.append("(PHI redacted)")
        }

        return parts.joined(separator: " | ")
    }
}

// MARK: - Factory Methods

public extension AISDKErrorV2 {
    // MARK: Request Errors

    /// Create an invalid request error
    static func invalidRequest(
        _ message: String,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(code: .invalidRequest, message: message, context: context)
    }

    /// Create a missing parameter error
    static func missingParameter(
        _ parameter: String,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(
            code: .missingParameter,
            message: "Missing required parameter: \(parameter)",
            context: context
        )
    }

    /// Create an invalid model error
    static func invalidModel(
        _ model: String,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(
            code: .invalidModel,
            message: "Invalid model identifier: \(model)",
            context: context
        )
    }

    // MARK: Provider Errors

    /// Create an authentication failed error
    static func authenticationFailed(
        provider: String,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        let ctx = AIErrorContext(
            requestId: context.requestId,
            provider: provider,
            model: context.model,
            statusCode: 401,
            phiRedacted: context.phiRedacted,
            metadata: context.metadata
        )
        return AISDKErrorV2(
            code: .authenticationFailed,
            message: "Authentication failed for provider: \(provider). Check your API key.",
            context: ctx
        )
    }

    /// Create a rate limit exceeded error
    static func rateLimitExceeded(
        provider: String,
        retryAfter: TimeInterval? = nil,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        var message = "Rate limit exceeded for provider: \(provider)"
        if let retryAfter = retryAfter {
            message += ". Retry after \(Int(retryAfter)) seconds."
        }
        let ctx = AIErrorContext(
            requestId: context.requestId,
            provider: provider,
            model: context.model,
            statusCode: 429,
            phiRedacted: context.phiRedacted,
            metadata: context.metadata
        )
        return AISDKErrorV2(code: .rateLimitExceeded, message: message, context: ctx)
    }

    /// Create a provider unavailable error
    static func providerUnavailable(
        provider: String,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        let ctx = AIErrorContext(
            requestId: context.requestId,
            provider: provider,
            model: context.model,
            statusCode: 503,
            phiRedacted: context.phiRedacted,
            metadata: context.metadata
        )
        return AISDKErrorV2(
            code: .providerUnavailable,
            message: "Provider '\(provider)' is currently unavailable",
            context: ctx
        )
    }

    /// Create a model not available error
    static func modelNotAvailable(
        model: String,
        provider: String? = nil,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        var message = "Model '\(model)' is not available"
        if let provider = provider {
            message += " on provider '\(provider)'"
        }
        let ctx = AIErrorContext(
            requestId: context.requestId,
            provider: provider ?? context.provider,
            model: model,
            statusCode: context.statusCode,
            phiRedacted: context.phiRedacted,
            metadata: context.metadata
        )
        return AISDKErrorV2(code: .modelNotAvailable, message: message, context: ctx)
    }

    // MARK: Content Errors

    /// Create a content filtered error
    static func contentFiltered(
        reason: String? = nil,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        var message = "Content was filtered by safety systems"
        if let reason = reason {
            message += ": \(reason)"
        }
        return AISDKErrorV2(code: .contentFiltered, message: message, context: context)
    }

    /// Create a context length exceeded error
    static func contextLengthExceeded(
        tokenCount: Int? = nil,
        maxTokens: Int? = nil,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        var message = "Request exceeds the model's context length"
        if let tokenCount = tokenCount, let maxTokens = maxTokens {
            message = "Request (\(tokenCount) tokens) exceeds model limit (\(maxTokens) tokens)"
        }
        return AISDKErrorV2(code: .contextLengthExceeded, message: message, context: context)
    }

    /// Create a parsing failed error
    static func parsingFailed(
        _ details: String,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(
            code: .parsingFailed,
            message: "Failed to parse response: \(details)",
            context: context
        )
    }

    // MARK: Stream Errors

    /// Create a stream connection failed error
    static func streamConnectionFailed(
        reason: String? = nil,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        var message = "Failed to establish stream connection"
        if let reason = reason {
            message += ": \(reason)"
        }
        return AISDKErrorV2(code: .streamConnectionFailed, message: message, context: context)
    }

    /// Create a stream interrupted error
    static func streamInterrupted(
        reason: String? = nil,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        var message = "Stream was interrupted"
        if let reason = reason {
            message += ": \(reason)"
        }
        return AISDKErrorV2(code: .streamInterrupted, message: message, context: context)
    }

    /// Create a stream timeout error
    static func streamTimeout(
        after: TimeInterval,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(
            code: .streamTimeout,
            message: "Stream timed out after \(Int(after)) seconds",
            context: context
        )
    }

    // MARK: Tool Errors

    /// Create a tool execution failed error
    static func toolExecutionFailed(
        tool: String,
        reason: String,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(
            code: .toolExecutionFailed,
            message: "Tool '\(tool)' execution failed: \(reason)",
            context: context
        )
    }

    /// Create a tool not found error
    static func toolNotFound(
        _ tool: String,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(
            code: .toolNotFound,
            message: "Tool '\(tool)' not found in registry",
            context: context
        )
    }

    /// Create a tool timeout error
    static func toolTimeout(
        tool: String,
        after: TimeInterval,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(
            code: .toolTimeout,
            message: "Tool '\(tool)' timed out after \(Int(after)) seconds",
            context: context
        )
    }

    // MARK: Network Errors

    /// Create a network failed error
    static func networkFailed(
        _ reason: String,
        underlyingError: Error? = nil,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(
            code: .networkFailed,
            message: "Network request failed: \(reason)",
            context: context,
            underlyingError: underlyingError
        )
    }

    /// Create a timeout error
    static func timeout(
        after: TimeInterval,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(
            code: .timeout,
            message: "Request timed out after \(Int(after)) seconds",
            context: context
        )
    }

    // MARK: PHI/Security Errors

    /// Create a provider not allowed error (PHI protection)
    static func providerNotAllowed(
        provider: String,
        allowedProviders: Set<String>,
        sensitivity: DataSensitivity,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        let allowedList = allowedProviders.isEmpty ? "(none)" : allowedProviders.sorted().joined(separator: ", ")
        let ctx = AIErrorContext(
            requestId: context.requestId,
            provider: provider,
            model: context.model,
            statusCode: context.statusCode,
            phiRedacted: true,  // Always mark PHI-related errors as redacted
            metadata: [:]
        )
        return AISDKErrorV2(
            code: .providerNotAllowed,
            message: "Provider '\(provider)' not allowed for \(sensitivity.rawValue) data. Allowed: \(allowedList)",
            context: ctx
        )
    }

    /// Create a PHI requires allowlist error
    static func phiRequiresAllowlist(
        sensitivity: DataSensitivity,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        let ctx = context.redacted()
        return AISDKErrorV2(
            code: .phiRequiresAllowlist,
            message: "Requests with \(sensitivity.rawValue) data require explicit provider allowlisting via allowedProviders",
            context: ctx
        )
    }

    // MARK: System Errors

    /// Create an internal error
    static func internalError(
        _ message: String,
        underlyingError: Error? = nil,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(
            code: .internalError,
            message: "Internal error: \(message)",
            context: context,
            underlyingError: underlyingError
        )
    }

    /// Create a cancelled error
    static func cancelled(
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        AISDKErrorV2(
            code: .cancelled,
            message: "Operation was cancelled",
            context: context
        )
    }

    /// Create an unknown error from any Error
    static func unknown(
        _ error: Error,
        context: AIErrorContext = .empty
    ) -> AISDKErrorV2 {
        // Redact context for unknown errors to be safe
        AISDKErrorV2(
            code: .unknown,
            message: "Unknown error occurred",
            context: context.redacted(),
            underlyingError: error
        )
    }
}

// MARK: - Error Conversion

public extension AISDKErrorV2 {
    /// Convert from any Error to AISDKErrorV2
    ///
    /// This provides a safe conversion that ensures PHI redaction
    /// for unknown error types.
    static func from(_ error: Error, context: AIErrorContext = .empty) -> AISDKErrorV2 {
        // If already an AISDKErrorV2, return as-is
        if let aiError = error as? AISDKErrorV2 {
            return aiError
        }

        // Convert legacy AIProviderAccessError
        if let accessError = error as? AIProviderAccessError {
            switch accessError {
            case .providerNotAllowed(let provider, let allowed):
                return .providerNotAllowed(
                    provider: provider,
                    allowedProviders: allowed,
                    sensitivity: .standard,
                    context: context
                )
            case .sensitiveDataRequiresAllowlist(let sensitivity):
                return .phiRequiresAllowlist(sensitivity: sensitivity, context: context)
            }
        }

        // Convert legacy LLMError
        if let llmError = error as? LLMError {
            return convertLLMError(llmError, context: context)
        }

        // Convert legacy AgentError
        if let agentError = error as? AgentError {
            return convertAgentError(agentError, context: context)
        }

        // Convert legacy ToolError
        if let toolError = error as? ToolError {
            return convertToolError(toolError, context: context)
        }

        // Convert legacy AISDKError
        if let sdkError = error as? AISDKError {
            return convertAISDKError(sdkError, context: context)
        }

        // Handle CancellationError
        if error is CancellationError {
            return .cancelled(context: context)
        }

        // Handle URLError
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout(after: 0, context: context)
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkFailed("No network connection", underlyingError: urlError, context: context)
            default:
                return .networkFailed(urlError.localizedDescription, underlyingError: urlError, context: context)
            }
        }

        // Default: wrap as unknown with redaction
        return .unknown(error, context: context)
    }

    // MARK: Private Conversion Helpers

    private static func convertLLMError(_ error: LLMError, context: AIErrorContext) -> AISDKErrorV2 {
        switch error {
        case .invalidRequest(let details):
            return .invalidRequest(details, context: context)
        case .networkError(let code, let message):
            let ctx = AIErrorContext(
                requestId: context.requestId,
                provider: context.provider,
                model: context.model,
                statusCode: code,
                phiRedacted: context.phiRedacted,
                metadata: context.metadata
            )
            return .networkFailed(message, context: ctx)
        case .parsingError(let details):
            return .parsingFailed(details, context: context)
        case .streamError(let details):
            return .streamInterrupted(reason: details, context: context)
        case .invalidResponse(let details):
            return AISDKErrorV2(code: .invalidResponse, message: details, context: context)
        case .rateLimitExceeded:
            return .rateLimitExceeded(provider: context.provider ?? "unknown", context: context)
        case .authenticationError:
            return .authenticationFailed(provider: context.provider ?? "unknown", context: context)
        case .modelNotAvailable:
            return .modelNotAvailable(model: context.model ?? "unknown", context: context)
        case .contextLengthExceeded:
            return .contextLengthExceeded(context: context)
        case .underlying(let underlyingError):
            return .from(underlyingError, context: context)
        }
    }

    private static func convertAgentError(_ error: AgentError, context: AIErrorContext) -> AISDKErrorV2 {
        switch error {
        case .invalidModel:
            return .invalidModel(context.model ?? "unknown", context: context)
        case .missingAPIKey:
            return .authenticationFailed(provider: context.provider ?? "unknown", context: context)
        case .toolExecutionFailed(let message):
            return .toolExecutionFailed(tool: "unknown", reason: message, context: context)
        case .invalidToolResponse:
            return AISDKErrorV2(
                code: .invalidResponse,
                message: "Invalid tool response",
                context: context
            )
        case .conversationLimitExceeded:
            return .contextLengthExceeded(context: context)
        case .invalidParameterType(let parameter):
            return .invalidRequest("Invalid parameter type: \(parameter)", context: context)
        case .invalidConfiguration(let details):
            return .invalidRequest("Invalid configuration: \(details)", context: context)
        case .streamingError(let details):
            return .streamInterrupted(reason: details, context: context)
        case .underlying(let underlyingError):
            return .from(underlyingError, context: context)
        case .operationCancelled:
            return .cancelled(context: context)
        }
    }

    private static func convertToolError(_ error: ToolError, context: AIErrorContext) -> AISDKErrorV2 {
        switch error {
        case .invalidParameters(let message):
            return AISDKErrorV2(
                code: .invalidToolArguments,
                message: "Invalid tool parameters: \(message)",
                context: context
            )
        case .executionFailed(let message):
            return .toolExecutionFailed(tool: "unknown", reason: message, context: context)
        case .validationFailed(let message):
            return AISDKErrorV2(
                code: .validationFailed,
                message: "Tool validation failed: \(message)",
                context: context
            )
        case .unsupportedOperation(let message):
            return AISDKErrorV2(
                code: .invalidRequest,
                message: "Unsupported operation: \(message)",
                context: context
            )
        }
    }

    private static func convertAISDKError(_ error: AISDKError, context: AIErrorContext) -> AISDKErrorV2 {
        switch error {
        case .invalidURL:
            return .invalidRequest("Invalid URL configuration", context: context)
        case .underlying(let underlyingError):
            return .from(underlyingError, context: context)
        case .httpError(let code, let message):
            let ctx = AIErrorContext(
                requestId: context.requestId,
                provider: context.provider,
                model: context.model,
                statusCode: code,
                phiRedacted: context.phiRedacted,
                metadata: context.metadata
            )
            return AISDKErrorV2(
                code: .networkFailed,
                message: "HTTP Error \(code): \(message)",
                context: ctx
            )
        case .parsingError(let details):
            return .parsingFailed(details, context: context)
        case .custom(let message):
            return AISDKErrorV2(code: .unknown, message: message, context: context)
        case .streamError(let details):
            return .streamInterrupted(reason: details, context: context)
        }
    }
}

// MARK: - PHI Redaction Utilities

public extension AISDKErrorV2 {
    /// Create a PHI-safe version of this error for logging
    ///
    /// This method ensures no PHI is present in error messages
    /// by redacting context and using generic messages where needed.
    func redactedForLogging() -> AISDKErrorV2 {
        AISDKErrorV2(
            code: code,
            message: code.isSecurityRelated ? genericSecurityMessage() : message,
            context: context.redacted(),
            underlyingError: nil  // Don't include underlying error in logs
        )
    }

    /// Get a dictionary representation safe for logging
    func toLogDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "code": code.rawValue,
            "message": code.isSecurityRelated ? genericSecurityMessage() : message,
            "isRetryable": code.isRetryable,
            "isClientError": code.isClientError
        ]

        if let requestId = context.requestId {
            dict["requestId"] = requestId
        }
        if let provider = context.provider {
            dict["provider"] = provider
        }
        if let model = context.model {
            dict["model"] = model
        }
        if let statusCode = context.statusCode {
            dict["statusCode"] = statusCode
        }

        dict["phiRedacted"] = true  // Always mark as redacted for safety

        return dict
    }

    private func genericSecurityMessage() -> String {
        switch code {
        case .providerNotAllowed:
            return "Provider access denied for data sensitivity level"
        case .phiRequiresAllowlist:
            return "Sensitive data requires explicit provider configuration"
        case .sensitiveDataExposure:
            return "Potential sensitive data exposure prevented"
        case .authenticationFailed:
            return "Authentication failed"
        default:
            return "Security-related error occurred"
        }
    }
}
