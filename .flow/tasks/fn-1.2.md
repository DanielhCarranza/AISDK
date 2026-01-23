# fn-1.2 Task 0.2: AIAgentAdapter

## Description
Wrap existing `Agent` class to conform to new `AIAgent` protocol. This adapter enables gradual migration from the legacy Agent class to the new unified interface, similar to how AILanguageModelAdapter wraps the LLM protocol.

## Acceptance
- [x] AIAgent protocol defined with send, sendStream, reset, setMessages methods
- [x] AIAgentState enum for idle, thinking, executingTool, responding, error states
- [x] AIAgentResponse type for non-streaming agent results
- [x] AIAgentEvent enum for streaming events (state changes, messages, text, tools)
- [x] AIAgentConfiguration for agent creation options
- [x] AIAgentCallbacks protocol for monitoring agent execution
- [x] AIAgentError enum for agent-specific errors
- [x] AIAgentAdapter wraps legacy Agent implementations
- [x] Bidirectional message conversion between AIMessage and ChatMessage
- [x] State forwarding from legacy AgentState to AIAgentState
- [x] Factory methods for OpenAI and Anthropic providers
- [x] Build passes without errors

## Done summary
Created the AIAgent protocol and AIAgentAdapter that wraps the existing Agent class for backward compatibility. The implementation includes:

1. **AIAgent.swift** (`Sources/AISDK/Core/Protocols/`)
   - AIAgent protocol with send, sendStream, reset, setMessages
   - AIAgentState enum mirroring legacy AgentState
   - AIAgentResponse for non-streaming results
   - AIAgentEvent enum for 12 streaming event types
   - AIAgentConfiguration for agent setup
   - AIAgentCallbacks protocol for execution monitoring
   - AIAgentError enum for agent-specific errors

2. **AIAgentAdapter.swift** (`Sources/AISDK/Core/Adapters/Legacy/`)
   - Wraps any Agent implementation
   - Converts AIMessage to/from ChatMessage
   - Converts AIAgentState from legacy AgentState
   - Handles streaming with proper event emission
   - State change forwarding via onStateChange callback
   - Factory methods: fromOpenAI, fromAnthropic, from(generic)

## Evidence
- Commits: (pending)
- Tests: swift build
- PRs:
