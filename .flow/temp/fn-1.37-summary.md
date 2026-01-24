## Summary
Implemented the redesigned AITool protocol at `Sources/AISDK/Tools/AITool.swift` with full Sendable compliance for actor-based agent execution. The protocol uses static properties and methods to ensure immutability, with per-tool timeout support and type-safe generic metadata.

Key components:
- `AITool` protocol with static properties (name, description, timeout) and static execute method
- `AIToolResult<M>` generic result type with content and optional metadata
- `AIToolMetadata` protocol for Sendable, Codable metadata types
- `EmptyMetadata` default type for tools that don't return metadata
- `AIToolExecutor` for executing tools with timeout enforcement and argument parsing
- `AnyAITool` type-erased wrapper for heterogeneous tool collections
- `AIToolRegistry` for managing and executing tools by name
- `AnyAIToolMetadata` type-erased metadata wrapper with decode support

## Changes
- Added `Sources/AISDK/Tools/AITool.swift` (397 lines)
- Added `Tests/AISDKTests/Tools/AIToolTests.swift` (400 lines)
- 26 tests, all passing
