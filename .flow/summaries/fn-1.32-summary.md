## Done Summary

AIAgentActor implemented as a full Swift actor with:

1. **Actor-based isolation**: Full thread safety via Swift actor model
2. **Operation queue**: Serializes concurrent requests to prevent reentrancy
3. **ObservableAgentState**: MainActor-isolated class bridging actor state to SwiftUI
4. **Non-streaming execute**: `execute(messages:)` method runs the agent loop
5. **Stop conditions**: stepCount, noToolCalls, tokenBudget, and custom predicates
6. **Timeout integration**: TimeoutPolicy and TimeoutExecutor for operation timeouts
7. **Tool execution**: Schema lookup, parameter validation, and execution with error handling
8. **Conversation management**: reset() and setMessages(_:) methods

### Files Modified
- `Sources/AISDK/Agents/AIAgentActor.swift` - Core actor implementation
- `Tests/AISDKTests/Agents/AIAgentActorTests.swift` - Comprehensive test suite

### Test Coverage
15 test cases covering:
- Initialization with defaults and custom values
- Observable state access and updates
- Operation queue serialization
- Execute returns results
- Stop condition behaviors
- Reset clears state
- setMessages updates history
