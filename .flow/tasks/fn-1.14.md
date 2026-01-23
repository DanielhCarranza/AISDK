# fn-1.14 Task 1.11: SafeAsyncStream Utility

## Description
Memory-safe stream creation utility with proper cancellation handling. Provides:
- Bounded buffering to prevent memory exhaustion (default 1000 elements)
- Proper cancellation propagation (consumer cancellation cancels producer task)
- Clean continuation lifecycle management with idempotent finish
- Integration with StreamBufferPolicy for configurable buffering
- Convenience methods for common stream patterns (empty, fail, just, from sequence)
- Both async and sync build closures supported

## Acceptance
- [x] SafeAsyncStream enum with static factory methods
- [x] make() for async stream creation with cancellation handling
- [x] makeSync() for synchronous stream creation
- [x] Continuation wrapper with yield/finish methods
- [x] isTerminated property for checking stream state
- [x] Idempotent finish() (safe to call multiple times)
- [x] Integration with StreamBufferPolicy (bounded, dropOldest, dropNewest)
- [x] Default bounded policy with 1000 capacity
- [x] Invalid capacity validation (falls back to default)
- [x] LockedState for thread-safe state tracking
- [x] Convenience methods: empty(), fail(), just(), from()
- [x] Producer task cancellation on consumer cancellation
- [x] withTaskCancellationHandler for proper cleanup
- [x] Comprehensive test coverage (20 tests)
- [x] Builds without errors

## Done summary
Implemented SafeAsyncStream at Sources/AISDK/Core/Utilities/SafeAsyncStream.swift providing:
- Memory-safe AsyncThrowingStream factory with bounded buffering (default 1000)
- Continuation wrapper with isTerminated property and idempotent finish
- Producer task cancellation when consumer cancels (via onTermination + Task.cancel)
- withTaskCancellationHandler for graceful cancellation cleanup
- StreamBufferPolicy integration with capacity validation
- Both async (make) and sync (makeSync) stream creation methods
- Convenience methods: empty(), fail(), just(), from() for common patterns
- LockedState helper for thread-safe state management
- Full Sendable compliance for concurrency safety
- 20 comprehensive unit tests covering all functionality

**Review fixes applied:**
- Fixed cancellation propagation: consumer cancel now cancels producer Task
- Replaced misleading `isCancelled` with `isTerminated` property
- Added idempotent finish() with state guard
- Added buffer capacity validation with default fallback
- Renamed ManagedAtomic to LockedState with accurate documentation
- Added comprehensive test suite (20 tests)

## Evidence
- Commits: 4e9305c
- Tests: swift test --filter SafeAsyncStreamTests (20 tests), swift test --filter AISDKTests (138 tests)
- PRs:
