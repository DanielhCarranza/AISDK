# fn-1.35 Task 4.2: StopCondition

## Description
Implement the `StopCondition` enum for controlling when the AI agent loop should stop execution. The stop condition includes:
- `.stepCount(Int)` - Stop after a maximum number of steps
- `.noToolCalls` - Stop when no tool calls are made
- `.tokenBudget(maxTokens: Int)` - Stop when token budget is exceeded (new from spec)
- `.custom(@Sendable (AIStepResult) -> Bool)` - Custom stop condition predicate

## Acceptance
- [x] StopCondition enum with all 4 cases defined and Sendable-compliant
- [x] shouldStop() method in AIAgentActor handles all stop conditions
- [x] tokenBudget condition accumulates tokens across stepHistory
- [x] Unit tests for all StopCondition cases including tokenBudget integration test
- [x] Code compiles without errors

## Done summary
Task 4.2 StopCondition complete. The StopCondition enum with all 4 cases (.stepCount, .noToolCalls, .tokenBudget, .custom) was verified in AIAgentActor.swift. Added comprehensive integration test for tokenBudget condition that verifies the agent loop stops when accumulated tokens exceed the budget. Implementation review feedback addressed.
## Evidence
- Commits: 2a58f5fd9b0291cfcd2b742defbb4bf94bca1ba8, c5f2ccf79902bba854dab59a4d2b6d4daa59d55a
- Tests: swift test --filter StopConditionTests
- PRs: