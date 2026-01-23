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
The StopCondition enum was already implemented in `AIAgentActor.swift` (lines 809-821) with all required cases including the new `.tokenBudget(maxTokens: Int)` case. The `shouldStop()` method (lines 657-669) correctly evaluates each condition. Added comprehensive integration test `test_tokenBudget_condition_stops_when_budget_exceeded` to verify the tokenBudget condition actually stops the agent loop when accumulated tokens exceed the budget.

## Evidence
- Commits: To be added after commit
- Tests: `Tests/AISDKTests/Agents/AIAgentActorTests.swift` - StopConditionTests class with tests for all 4 condition types including new tokenBudget integration test
- PRs:
