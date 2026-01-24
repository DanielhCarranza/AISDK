# fn-1.36 Task 4.3: ToolCallRepair

## Description
TBD

## Acceptance
- [ ] TBD

## Done summary
# fn-1.36: ToolCallRepair Implementation Summary

## Changes Made
- Created `Sources/AISDK/Tools/ToolCallRepair.swift` with LLM-assisted tool argument repair mechanism
- Created `Tests/AISDKTests/Tools/ToolCallRepairTests.swift` with 24 comprehensive tests

## Implementation Details

### ToolCallRepair.Strategy enum
- `.strict` - No repair, errors propagate immediately
- `.autoRepairOnce` - Single repair attempt using LLM
- `.autoRepairMax(Int)` - Up to n repair attempts
- `.custom(closure)` - Custom repair logic with full control

### Key Methods
- `repair(toolCall:error:model:toolSchema:)` - Core repair method that asks LLM to fix arguments
- `attemptRepair(toolCall:error:model:strategy:toolSchema:)` - Strategy-aware repair with RepairResult

### Features
- Constructs repair prompts with error context and optional tool schema
- Parses and validates JSON from model responses
- Handles markdown code block responses
- RepairResult enum for tracking outcomes (repaired, failed, notAttempted)

## Test Coverage
All 24 tests passing covering:
- Strategy properties (allowsRepair, maxAttempts)
- Strategy equality
- RepairResult equality
- Core repair method with various responses
- attemptRepair with all strategies
- Tool schema integration
## Evidence
- Commits: 442979dd0a07a1bbddca019ace3a6a602f387caf
- Tests:
- PRs: