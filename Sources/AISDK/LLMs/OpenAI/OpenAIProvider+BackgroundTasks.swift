//
//  OpenAIProvider+BackgroundTasks.swift
//  AISDK
//
//  Background task support for OpenAI Responses API
//  Enables long-running operations with polling and cancellation
//

import Foundation

// MARK: - Background Task Types

/// Response from initiating a background task
public struct BackgroundResponse: Sendable, Equatable {
    /// Unique ID for polling and cancellation
    public let id: String

    /// Current status of the background task
    public let status: BackgroundTaskStatus

    /// Unix timestamp when the task was created
    public let createdAt: Int

    /// Estimated completion time (if available)
    public let estimatedCompletionAt: Int?

    public init(
        id: String,
        status: BackgroundTaskStatus,
        createdAt: Int,
        estimatedCompletionAt: Int? = nil
    ) {
        self.id = id
        self.status = status
        self.createdAt = createdAt
        self.estimatedCompletionAt = estimatedCompletionAt
    }
}

/// Status of a background task
public enum BackgroundTaskStatus: String, Codable, Sendable {
    case queued
    case inProgress = "in_progress"
    case completed
    case failed
    case cancelled
    case incomplete
}

/// Result of checking a background task
public enum BackgroundResult: Sendable {
    /// Task completed successfully
    case completed(AITextResult)

    /// Task failed with error
    case failed(AISDKErrorV2)

    /// Task was cancelled
    case cancelled

    /// Task is still in progress
    case inProgress(BackgroundResponse)
}

/// Complexity level for auto-background mode decisions
public enum ComplexityLevel: Int, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: ComplexityLevel, rhs: ComplexityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Background Task Operations

extension OpenAIProvider {

    /// Send a request as a background task (returns immediately)
    ///
    /// Background tasks are ideal for:
    /// - Complex code interpreter executions
    /// - Large file processing
    /// - Multi-step reasoning tasks
    /// - Operations that may exceed typical timeout limits
    ///
    /// - Parameter request: The text request to send
    /// - Returns: Background response with task ID for polling
    /// - Throws: `AISDKErrorV2` if the request fails
    ///
    /// Example:
    /// ```swift
    /// let background = try await provider.sendBackgroundText(request: request)
    /// print("Task started: \(background.id), status: \(background.status)")
    ///
    /// // Poll for completion
    /// let result = try await provider.pollBackgroundResponse(id: background.id)
    /// ```
    public func sendBackgroundText(request: AITextRequest) async throws -> BackgroundResponse {
        var responseRequest = try convertToResponseRequest(request)
        responseRequest.background = true

        let response = try await createResponse(request: responseRequest)

        return BackgroundResponse(
            id: response.id,
            status: mapToBackgroundStatus(response.status),
            createdAt: Int(response.createdAt),
            estimatedCompletionAt: nil
        )
    }

    /// Get the current state of a background response
    ///
    /// - Parameter id: The response ID from sendBackgroundText
    /// - Returns: Current result if completed, or status if still in progress
    /// - Throws: `AISDKErrorV2` if the request fails
    ///
    /// Example:
    /// ```swift
    /// let result = try await provider.getBackgroundResponse(id: background.id)
    /// switch result {
    /// case .completed(let textResult):
    ///     print("Done: \(textResult.text)")
    /// case .inProgress(let status):
    ///     print("Still processing: \(status.status)")
    /// case .failed(let error):
    ///     print("Failed: \(error)")
    /// case .cancelled:
    ///     print("Cancelled")
    /// }
    /// ```
    public func getBackgroundResponse(id: String) async throws -> BackgroundResult {
        let response = try await retrieveResponse(id: id)

        switch response.status {
        case .completed:
            return .completed(convertToAITextResult(response))
        case .failed:
            let errorMessage = response.error?.message ?? "Background task failed"
            return .failed(AISDKErrorV2(code: .providerUnavailable, message: errorMessage))
        case .cancelled:
            return .cancelled
        case .incomplete:
            // Incomplete means partial result available
            return .completed(convertToAITextResult(response))
        case .queued, .inProgress:
            return .inProgress(BackgroundResponse(
                id: response.id,
                status: mapToBackgroundStatus(response.status),
                createdAt: Int(response.createdAt)
            ))
        }
    }

    /// Cancel a background task
    ///
    /// - Parameter id: The response ID to cancel
    /// - Returns: Updated background response
    /// - Throws: `AISDKErrorV2` if cancellation fails
    ///
    /// Example:
    /// ```swift
    /// let cancelled = try await provider.cancelBackgroundResponse(id: background.id)
    /// print("Task cancelled: \(cancelled.status)")
    /// ```
    public func cancelBackgroundResponse(id: String) async throws -> BackgroundResponse {
        let response = try await cancelResponse(id: id)

        return BackgroundResponse(
            id: response.id,
            status: mapToBackgroundStatus(response.status),
            createdAt: Int(response.createdAt)
        )
    }

    /// Poll a background task until completion
    ///
    /// - Parameters:
    ///   - id: The response ID to poll
    ///   - pollInterval: Time between polls (default: 1 second)
    ///   - timeout: Maximum time to wait (default: 5 minutes)
    ///   - onProgress: Optional callback for status updates
    /// - Returns: Final result when completed
    /// - Throws: `AISDKErrorV2` on failure, cancellation, or timeout
    ///
    /// Example:
    /// ```swift
    /// let result = try await provider.pollBackgroundResponse(
    ///     id: background.id,
    ///     pollInterval: 2.0,
    ///     timeout: 300.0
    /// ) { status in
    ///     print("Status update: \(status)")
    /// }
    /// ```
    public func pollBackgroundResponse(
        id: String,
        pollInterval: TimeInterval = 1.0,
        timeout: TimeInterval = 300.0,
        onProgress: ((BackgroundTaskStatus) -> Void)? = nil
    ) async throws -> AITextResult {
        let startTime = Date()
        var lastStatus: BackgroundTaskStatus?

        while Date().timeIntervalSince(startTime) < timeout {
            // Check for cancellation
            try Task.checkCancellation()

            let result = try await getBackgroundResponse(id: id)

            switch result {
            case .completed(let textResult):
                return textResult

            case .failed(let error):
                throw error

            case .cancelled:
                throw AISDKErrorV2(code: .cancelled, message: "Background task was cancelled")

            case .inProgress(let status):
                // Notify progress if status changed
                if status.status != lastStatus {
                    lastStatus = status.status
                    onProgress?(status.status)
                }

                // Wait before next poll
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }

        throw AISDKErrorV2(
            code: .timeout,
            message: "Background task did not complete within \(Int(timeout)) seconds"
        )
    }

    /// Poll with exponential backoff for long-running tasks
    ///
    /// Uses exponential backoff to reduce polling frequency for very long tasks,
    /// which is more efficient for complex code interpreter or file processing operations.
    ///
    /// - Parameters:
    ///   - id: The response ID to poll
    ///   - initialInterval: Starting interval between polls (default: 1 second)
    ///   - maxInterval: Maximum interval cap (default: 30 seconds)
    ///   - timeout: Maximum time to wait (default: 10 minutes)
    ///   - onProgress: Optional callback for status updates
    /// - Returns: Final result when completed
    /// - Throws: `AISDKErrorV2` on failure, cancellation, or timeout
    ///
    /// Example:
    /// ```swift
    /// // For very long-running tasks
    /// let result = try await provider.pollBackgroundResponseWithBackoff(
    ///     id: background.id,
    ///     initialInterval: 1.0,
    ///     maxInterval: 30.0,
    ///     timeout: 600.0
    /// )
    /// ```
    public func pollBackgroundResponseWithBackoff(
        id: String,
        initialInterval: TimeInterval = 1.0,
        maxInterval: TimeInterval = 30.0,
        timeout: TimeInterval = 600.0,
        onProgress: ((BackgroundTaskStatus) -> Void)? = nil
    ) async throws -> AITextResult {
        let startTime = Date()
        var currentInterval = initialInterval
        var lastStatus: BackgroundTaskStatus?

        while Date().timeIntervalSince(startTime) < timeout {
            try Task.checkCancellation()

            let result = try await getBackgroundResponse(id: id)

            switch result {
            case .completed(let textResult):
                return textResult

            case .failed(let error):
                throw error

            case .cancelled:
                throw AISDKErrorV2(code: .cancelled, message: "Background task was cancelled")

            case .inProgress(let status):
                if status.status != lastStatus {
                    lastStatus = status.status
                    onProgress?(status.status)
                }

                // Exponential backoff with cap
                try await Task.sleep(nanoseconds: UInt64(currentInterval * 1_000_000_000))
                currentInterval = min(currentInterval * 1.5, maxInterval)
            }
        }

        throw AISDKErrorV2(
            code: .timeout,
            message: "Background task did not complete within \(Int(timeout)) seconds"
        )
    }

    /// Send request with automatic background mode for long operations
    ///
    /// Automatically uses background mode if the request seems complex.
    /// Complexity is estimated based on:
    /// - Code interpreter with files (high complexity)
    /// - File search with many vector stores (medium complexity)
    /// - Long content or many messages (medium complexity)
    ///
    /// - Parameters:
    ///   - request: The text request to send
    ///   - complexityThreshold: Minimum complexity to trigger background mode (default: .high)
    ///   - pollInterval: Time between polls if using background mode (default: 2 seconds)
    ///   - timeout: Maximum time to wait if using background mode (default: 10 minutes)
    /// - Returns: The text result
    /// - Throws: `AISDKErrorV2` on failure
    ///
    /// Example:
    /// ```swift
    /// let result = try await provider.sendTextWithAutoBackground(
    ///     request: request,
    ///     complexityThreshold: .medium
    /// )
    /// // Automatically uses background mode if code interpreter + files detected
    /// ```
    public func sendTextWithAutoBackground(
        request: AITextRequest,
        complexityThreshold: ComplexityLevel = .high,
        pollInterval: TimeInterval = 2.0,
        timeout: TimeInterval = 600.0
    ) async throws -> AITextResult {
        let complexity = estimateComplexity(request)

        if complexity >= complexityThreshold {
            // Use background mode
            let background = try await sendBackgroundText(request: request)
            return try await pollBackgroundResponse(
                id: background.id,
                pollInterval: pollInterval,
                timeout: timeout
            )
        } else {
            // Normal synchronous request
            return try await sendTextRequest(request)
        }
    }

    // MARK: - Private Helpers

    private func mapToBackgroundStatus(_ status: ResponseStatus) -> BackgroundTaskStatus {
        switch status {
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        case .incomplete: return .incomplete
        case .inProgress: return .inProgress
        case .queued: return .queued
        }
    }

    private func estimateComplexity(_ request: AITextRequest) -> ComplexityLevel {
        let options = request.providerOptions as? OpenAIRequestOptions

        // Code interpreter with files is high complexity
        if let codeConfig = options?.codeInterpreter, codeConfig.enabled {
            if let fileIds = codeConfig.fileIds, !fileIds.isEmpty {
                return .high
            }
            return .medium
        }

        // File search with many vector stores is medium complexity
        if let fileConfig = options?.fileSearch, fileConfig.enabled {
            if fileConfig.vectorStoreIds.count > 2 {
                return .medium
            }
        }

        // Long system prompts or many messages suggest complexity
        let totalContentLength = request.messages.reduce(0) { total, message in
            switch message.content {
            case .text(let text): return total + text.count
            case .parts(let parts): return total + parts.count * 100
            }
        }

        if totalContentLength > 10000 {
            return .medium
        }

        return .low
    }
}
