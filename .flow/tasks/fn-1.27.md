# fn-1.27 Task 3.3: TimeoutPolicy

## Description
Configurable timeout policy for controlling request, connection, and stream timeouts. Provides separate timeout configuration for different phases of a request.

## Acceptance
- [x] Configurable connection timeout
- [x] Configurable request timeout
- [x] Configurable stream timeout (time between chunks)
- [x] Configurable operation timeout
- [x] Preset policies: default, none, aggressive, lenient, streaming
- [x] TimeoutError enum with descriptive error messages
- [x] TimeoutExecutor for automated timeout enforcement
- [x] Duration extension for seconds and timeInterval conversion
- [x] Comprehensive test coverage (27 tests)

## Done summary
Implemented TimeoutPolicy for Phase 3 reliability layer.

Key features:
- Separate timeouts for connection (default: 10s), request (default: 60s), stream (default: 30s), and operation (default: 120s)
- Preset policies: default, none (no timeouts), aggressive (shorter), lenient (longer), streaming (optimized for streams)
- Modifier methods for creating modified copies (withConnectionTimeout, withRequestTimeout, etc.)
- TimeoutError enum with connectionTimedOut, requestTimedOut, streamTimedOut, operationTimedOut cases
- TimeoutExecutor using withThrowingTaskGroup for timeout enforcement
- Duration extension with seconds and timeInterval properties
- 27 comprehensive tests across 6 test classes

## Evidence
- Commits: (pending commit)
- Tests: swift test --filter TimeoutPolicy (27 tests pass)
- PRs:
