# fn-1.10 Task 1.7: AIError Taxonomy

## Description
Implement unified AIError taxonomy with PHI redaction enforcement for AISDK 2.0. This provides a consistent error interface across all SDK operations while ensuring healthcare compliance through automatic PHI protection in error messages and logs.

## Acceptance
- [x] AIErrorCode enum with 25+ error codes covering request, provider, content, stream, tool, network, PHI/security, and system errors
- [x] AIErrorContext struct for error context with PHI redaction support
- [x] AISDKErrorV2 unified error type with factory methods for all error categories
- [x] Error code properties: isRetryable, isClientError, isSecurityRelated
- [x] PHI redaction: redactedForLogging() and toLogDictionary() methods
- [x] Error conversion from legacy types: LLMError, AgentError, ToolError, AISDKError, AIProviderAccessError
- [x] LocalizedError and CustomStringConvertible conformance
- [x] Sendable and Equatable conformance for concurrency safety
- [x] Comprehensive test coverage (41 tests)
- [x] All tests passing

## Done summary
Created `Sources/AISDK/Core/Errors/AIError.swift` with:
- **AIErrorCode**: 25 error codes organized by category (request, provider, content, stream, tool, network, PHI/security, system) with `isRetryable`, `isClientError`, `isSecurityRelated` computed properties and `Codable` conformance
- **AIErrorContext**: Context struct with requestId, provider, model, statusCode, phiRedacted flag, and metadata dictionary. Includes `redacted()` method for PHI-safe copies
- **AISDKErrorV2**: Unified error type with:
  - 20+ factory methods for creating specific errors
  - PHI redaction enforcement (security-related errors auto-redact)
  - Conversion from all legacy error types (LLMError, AgentError, ToolError, etc.)
  - `redactedForLogging()` and `toLogDictionary()` for safe logging
  - Full LocalizedError, CustomStringConvertible, Sendable, Equatable conformance

Created `Tests/AISDKTests/Errors/AIErrorTests.swift` with 41 tests covering:
- Error code properties (retryable, client, security)
- Error context creation and redaction
- All factory methods
- Legacy error conversion
- PHI redaction utilities
- Protocol conformances

## Evidence
- Commits: (pending)
- Tests: Tests/AISDKTests/Errors/AIErrorTests.swift (41 tests, all passing)
- PRs: (pending)
