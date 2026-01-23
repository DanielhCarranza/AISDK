# fn-1.31 Task 3.7: FaultInjector

## Description
Implement FaultInjector - an actor-based testing utility for injecting faults into provider operations. This enables chaos testing and reliability validation for the AISDK reliability layer (circuit breaker, retry, failover).

## Acceptance
- [x] FaultInjector actor implemented with rule-based fault injection
- [x] FaultType enum supports: error, delay, timeout, randomFailure, intermittent, latencyJitter, rateLimited, serverError, corruptResponse
- [x] FaultRule supports provider/model filtering and activation state
- [x] Metrics tracking for evaluations, injected faults, and fault types
- [x] FaultInjectorDelegate protocol for injection notifications
- [x] Convenience builders: chaosTest, providerDown, rateLimited
- [x] Testing assertions: assertFaultsInjected, assertFaultCount
- [x] Comprehensive test suite with 58 tests (FaultTypeTests: 10, FaultRuleTests: 5, FaultInjectorTests: 41, FaultInjectorErrorTests: 2)
- [x] All tests passing

## Done summary
Implemented FaultInjector as an actor-based testing utility for injecting faults into provider operations. The implementation includes:

1. **FaultType enum** - 9 different fault types for simulating various failure scenarios
2. **FaultRule struct** - Configurable rules with provider/model filtering
3. **FaultInjector actor** - Thread-safe fault injection with metrics tracking
4. **Convenience builders** - Quick setup for common chaos testing scenarios
5. **Testing integration** - Assertion methods for test validation

The FaultInjector integrates with the existing reliability components (AdaptiveCircuitBreaker, RetryPolicy, FailoverExecutor) to enable comprehensive chaos testing.

## Evidence
- Commits: Add FaultInjector for Phase 3.7 reliability layer
- Tests: FaultInjectorTests.swift (58 tests passing)
- PRs:
