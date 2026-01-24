# fn-1.38 Task 4.5: AgentState Observable

## Description
Add an `AsyncStream<AgentState>` to ObservableAgentState for reactive UI integration. This allows consumers to subscribe to real-time state updates from agents without relying on SwiftUI's @Observable mechanism. The stream provides a reactive way to observe agent state changes programmatically.

Key components:
- `stateStream` property on ObservableAgentState returning AsyncStream<AgentState>
- Thread-safe state broadcasting using SafeAsyncStream patterns
- Proper cleanup when stream consumers stop listening
- Integration with existing state update paths in AIAgentActor

## Acceptance
- [ ] ObservableAgentState has `stateStream` property returning AsyncStream<AgentState>
- [ ] Stream emits current state immediately upon subscription
- [ ] Stream emits state changes as they occur during agent execution
- [ ] Multiple subscribers can listen concurrently
- [ ] Stream properly terminates when observableState is deallocated
- [ ] No memory leaks from stream subscriptions
- [ ] Unit tests verify stream behavior
- [ ] Code compiles without errors

## Done summary
TBD

## Evidence
- Commits:
- Tests:
- PRs:
