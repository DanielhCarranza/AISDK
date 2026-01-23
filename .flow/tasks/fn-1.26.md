# fn-1.26 Task 3.2: RetryPolicy

## Description
Implement a configurable retry policy with exponential backoff and jitter for provider resilience. Integrates with AdaptiveCircuitBreaker for comprehensive reliability.

## Acceptance
- [x] Exponential backoff with configurable base delay and max delay
- [x] Random jitter to prevent thundering herd
- [x] Configurable max retries
- [x] Retryable error detection via RetryableError protocol
- [x] Integration with ProviderError (rate limits, timeouts, network errors)
- [x] RetryExecutor for automated retry with circuit breaker integration
- [x] Preset policies: default, none, aggressive, conservative, immediate
- [x] Respect retry-after headers from rate limit errors
- [x] Comprehensive test coverage (35 tests)

## Done summary
Implemented RetryPolicy for Phase 3 reliability layer.

Key features:
- Exponential backoff with configurable base (default: 1s) and max delay (default: 30s)
- Random jitter factor (0.0-1.0) to prevent thundering herd
- RetryableError protocol for custom error classification
- ProviderError and CircuitBreakerError conformance to RetryableError
- RetryExecutor for automated retry execution with circuit breaker integration
- Preset policies: default (3 retries), none, aggressive (5 retries), conservative (2 retries), immediate (testing)
- Respects retry-after headers from rate limit responses
- 35 comprehensive tests across 7 test classes

## Evidence
- Commits: (pending commit)
- Tests: swift test --filter RetryPolicy (35 tests pass)
- PRs:
