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
# FaultInjector Implementation Summary (fn-1.31)

## Overview
Implemented FaultInjector as an actor-based testing utility for injecting faults into provider operations, enabling chaos testing and reliability validation.

## Components Added

### FaultInjector.swift
- **FaultType enum**: 9 fault types (error, delay, timeout, randomFailure, intermittent, latencyJitter, rateLimited, serverError, corruptResponse)
- **FaultRule struct**: Configurable rules with provider/model filtering and activation state
- **FaultInjector actor**: Thread-safe fault injection with metrics tracking
- **FaultInjectorDelegate**: Protocol for injection notifications
- **Convenience builders**: chaosTest(), providerDown(), rateLimited()
- **Testing assertions**: assertFaultsInjected(), assertFaultCount()

### FaultInjectorTests.swift
- 58 comprehensive tests covering all functionality
- FaultTypeTests (10 tests)
- FaultRuleTests (5 tests)  
- FaultInjectorTests (41 tests)
- FaultInjectorErrorTests (2 tests)

## Integration
Integrates with existing reliability components (AdaptiveCircuitBreaker, RetryPolicy, FailoverExecutor) to enable comprehensive chaos testing scenarios.
## Evidence
- Commits: 21414d6c8d00b043cae5012d4a1fd9a1b5e251e1
- Tests: swift test --filter FaultInjector
- PRs: