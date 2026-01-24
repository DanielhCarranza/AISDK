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
All 34 tests passing covering:
- Strategy properties (allowsRepair, maxAttempts)
- Strategy matching (replaces equality for closures)
- RepairResult equality
- RequestContext creation and preservation
- Core repair method with various responses
- Generic Error type acceptance
- JSON array rejection (only objects valid)
- attemptRepair with all strategies
- autoRepairMax with 0/negative guards
- Tool schema integration

## Evidence
- Commits: 442979dd0a07a1bbddca019ace3a6a602f387caf, 08d17b69a4e3f9111d494bf95a365cd7676f7d9f
- Tests: swift test --filter ToolCallRepairTests (34 tests passing)
- PRs: