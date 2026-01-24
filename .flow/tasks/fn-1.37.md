# fn-1.37 Task 4.4: AITool Protocol (Redesigned)

## Description
Implement the redesigned AITool protocol with immutable, Sendable-compliant design for concurrent tool execution in actor-based agents. The new protocol uses static properties and methods instead of mutable instances, enabling full thread safety for Swift 6 concurrency.

Key components:
- `AITool` protocol with static properties (name, description, timeout) and static execute method
- `AIToolResult<M>` generic result type with content and optional metadata
- `AIToolMetadata` protocol for Sendable, Codable metadata types
- `EmptyMetadata` default type for tools that don't return metadata
- `AIToolExecutor` for executing tools with timeout enforcement and argument parsing
- `AnyAITool` type-erased wrapper for heterogeneous tool collections
- `AIToolRegistry` for managing and executing tools by name
- `AnyAIToolMetadata` type-erased metadata wrapper with decode support

## Acceptance
- [x] AITool protocol is Sendable-compliant with static properties and methods
- [x] Per-tool timeout is configurable via static `timeout` property (default 60s)
- [x] AIToolResult supports generic metadata types
- [x] EmptyMetadata provides default for tools without metadata
- [x] AIToolExecutor enforces timeout and handles argument parsing
- [x] AnyAITool enables heterogeneous tool collections
- [x] AIToolRegistry provides thread-safe tool management
- [x] All tests pass (26 tests)
- [x] Build succeeds with no errors

## Done summary
Implemented the redesigned AITool protocol at `Sources/AISDK/Tools/AITool.swift` with full Sendable compliance for actor-based agent execution. The protocol uses static properties and methods to ensure immutability, with per-tool timeout support and type-safe generic metadata. Includes executor for timeout enforcement, type-erased wrappers for heterogeneous collections, and a thread-safe registry for tool management.

## Evidence
- Commits: (pending commit)
- Tests: Tests/AISDKTests/Tools/AIToolTests.swift (26 tests, all passing)
- PRs:
