# fn-1.25 Task 3.1: AdaptiveCircuitBreaker

## Description
Implement an actor-based adaptive circuit breaker for provider reliability as part of the Phase 3 Reliability Layer. Uses monotonic time (ContinuousClock) for reliable timing and supports per-provider configuration.

## Acceptance
- [x] Actor-based implementation with Sendable conformance
- [x] Three states: closed, open, half-open with proper transitions
- [x] Monotonic time tracking using ContinuousClock for reliability
- [x] Per-provider configuration support via CircuitBreakerConfiguration
- [x] Configurable failure thresholds and recovery times
- [x] Sliding window failure rate calculation (optional)
- [x] CircuitBreakerRegistry for managing multiple provider breakers
- [x] Delegate protocol for state change notifications
- [x] Comprehensive test coverage (45 tests)

## Done summary
Implemented AdaptiveCircuitBreaker for Phase 3 reliability layer.

Key features:
- Actor-based implementation with full Sendable conformance
- Three-state circuit: closed -> open (after failures) -> half-open (after timeout) -> closed (after successes)
- ContinuousClock for monotonic timing (survives sleep/wake cycles)
- CircuitBreakerConfiguration with presets: default, aggressive, lenient
- Sliding window failure rate calculation for adaptive detection
- CircuitBreakerRegistry for per-provider breaker management
- CircuitBreakerDelegate protocol for state change notifications
- CircuitBreakerMetrics for observability
- 45 comprehensive tests across 5 test classes

## Evidence
- Commits: (pending commit)
- Tests: swift test --filter CircuitBreaker (45 tests pass)
- PRs:
