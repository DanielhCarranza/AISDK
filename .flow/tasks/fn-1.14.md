# fn-1.14 Task 1.11: SafeAsyncStream Utility

## Description
Memory-safe stream creation utility with proper cancellation handling. Provides:
- Bounded buffering to prevent memory exhaustion (default 1000 elements)
- Proper cancellation propagation via onTermination
- Clean continuation lifecycle management with atomic state tracking
- Integration with StreamBufferPolicy for configurable buffering
- Convenience methods for common stream patterns (empty, fail, just, from sequence)
- Both async and sync build closures supported

## Acceptance
- [x] SafeAsyncStream enum with static factory methods
- [x] make() for async stream creation with cancellation handling
- [x] makeSync() for synchronous stream creation
- [x] Continuation wrapper with yield/finish methods
- [x] Integration with StreamBufferPolicy (bounded, dropOldest, dropNewest)
- [x] Default bounded policy with 1000 capacity
- [x] ManagedAtomic for thread-safe state tracking
- [x] Convenience methods: empty(), fail(), just(), from()
- [x] Comprehensive documentation and usage examples
- [x] Builds without errors

## Done summary
Implemented SafeAsyncStream at Sources/AISDK/Core/Utilities/SafeAsyncStream.swift providing:
- Memory-safe AsyncThrowingStream factory with bounded buffering (default 1000)
- Continuation wrapper with automatic finish handling and cancellation propagation
- StreamBufferPolicy integration for configurable buffering behavior
- Both async (make) and sync (makeSync) stream creation methods
- Convenience methods: empty(), fail(), just(), from() for common patterns
- Internal ManagedAtomic type for thread-safe stream state tracking
- Full Sendable compliance for concurrency safety

## Evidence
- Commits: (pending)
- Tests: All 138 existing tests pass (swift test --filter AISDKTests)
- PRs:
