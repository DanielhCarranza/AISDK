# fn-1.16 Task 1.13: simulateStream Helper

## Description
Implement stream simulation helpers for testing AI streaming behavior. The `StreamSimulation` enum provides factory methods for creating realistic `AIStreamEvent` sequences that mimic actual AI provider streaming behavior.

## Acceptance
- [x] StreamSimulation enum with factory methods for common stream patterns
- [x] Text stream simulation with word/character chunking
- [x] Tool call stream simulation with argument chunking
- [x] Mixed stream simulation (text + tool calls)
- [x] Reasoning stream simulation (for o1/o3 models)
- [x] Error stream simulation (immediate and partial errors)
- [x] Multi-step stream simulation
- [x] Heartbeat stream simulation
- [x] AsyncThrowingStream creation helpers with delay support
- [x] Pattern-based event generation for assertion testing
- [x] Comprehensive test coverage (19 tests)

## Done summary
Created `StreamSimulation` helper at `Tests/AISDKTests/Helpers/StreamSimulation.swift` providing:
- Factory methods for text, tool call, reasoning, and error streams
- Configurable chunking (word vs character level)
- Inter-event delay support for timing tests
- Pattern-based event generation for quick test setup
- Integration with `SafeAsyncStream` for proper cancellation handling
- Full test coverage in `StreamSimulationTests.swift`

## Evidence
- Commits: (pending)
- Tests: `swift test --filter StreamSimulationTests` - 19 tests pass
- PRs: (pending)
