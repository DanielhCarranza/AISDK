import Foundation

extension OpenAIProvider {
    /// Determines whether the provided error is transient and worth retrying.
    /// Transient errors include:
    ///  • HTTP 429 (rate-limit) and server-side 5xx errors
    ///  • Explicit `rateLimitExceeded` and generic network errors
    ///  • Low-level networking issues wrapped in `AISDKError.underlying`
    private func isTransientError(_ error: Error) -> Bool {
        // Handle LLM-level errors first
        if let llmError = error as? LLMError {
            switch llmError {
            case .rateLimitExceeded:
                return true
            case .networkError(let code, _):
                if let code = code {
                    return code == 429 || (500...599).contains(code)
                }
                return true // network error without status code
            case .underlying:
                return true
            default:
                break
            }
        }

        // Handle generic AISDK errors
        if let sdkError = error as? AISDKError {
            switch sdkError {
            case .httpError(let code, _):
                return code == 429 || (500...599).contains(code)
            case .underlying:
                return true
            default:
                break
            }
        }

        // Fall back to non-transient
        return false
    }

    /// Sends a chat completion request **with automatic retries**.
    /// - Parameters:
    ///   - request: The `ChatCompletionRequest` to send.
    ///   - maxRetries: Maximum number of retry attempts (default: 3).
    ///   - baseBackoff: Base back-off duration **in nanoseconds** for exponential back-off (default: 1 second).
    /// - Returns: A `ChatCompletionResponse` from OpenAI.
    /// - Throws: Rethrows the last encountered error if retries are exhausted or error is not transient.
    public func sendChatCompletion(
        request: ChatCompletionRequest,
        maxRetries: Int = 3,
        baseBackoff: UInt64 = 1_000_000_000 // 1s expressed in nanoseconds
    ) async throws -> ChatCompletionResponse {
        var attempt = 0

        while true {
            do {
                // Try the underlying non-retrying call
                return try await self.sendChatCompletion(request: request)
            } catch {
                // Decide whether to retry
                guard attempt < maxRetries, isTransientError(error) else {
                    throw error // give up
                }

                attempt += 1
                let backoff = baseBackoff * UInt64(pow(2.0, Double(attempt - 1)))
                let seconds = Double(backoff) / 1_000_000_000.0
                print("⚠️  ChatCompletion attempt \(attempt) failed – retrying in \(seconds)s …")
                try await Task.sleep(nanoseconds: backoff)
            }
        }
    }
} 