# AISDK Swift Modernization - Comprehensive Implementation Plan

Create a detailed, phased implementation plan for modernizing the AISDK Swift SDK to achieve feature parity with Vercel AI SDK 4.x while maintaining iOS/Swift best practices. This is for an AI doctor application requiring healthcare-grade reliability.

## Context

### Current State
The AISDK is a Swift SDK (iOS 17+, macOS 14+) with 66 core files providing multi-provider LLM abstraction. It has been largely unmaintained for 5-7 months and needs comprehensive modernization.

**Current Architecture:**
- 4 modules: AISDK (core), AISDKChat, AISDKVoice, AISDKVision
- 3 providers: OpenAI (82 models), Anthropic (10 models), Gemini (42 models)
- Agent system with tool execution and callbacks
- Basic streaming via AsyncThrowingStream
- Tool framework with @Parameter property wrapper and JSON schema generation

**Files to Read for Context (READ THESE FIRST):**

Architecture & Core:
- `docs/AISDK-ARCHITECTURE.md` - Comprehensive architecture documentation
- `Sources/AISDK/LLMs/LLMProtocol.swift` - Core LLM protocol (simple 3-method interface)
- `Sources/AISDK/LLMs/LLMModelProtocol.swift` - Model capability flags
- `Sources/AISDK/Agents/Agent.swift` - Main agent implementation (656 lines, handles streaming/tools)
- `Sources/AISDK/Agents/AgentState.swift` - State machine for agent
- `Sources/AISDK/Agents/AgentCallbacks.swift` - Callback protocol
- `Sources/AISDK/Tools/Tool.swift` - Tool protocol and @Parameter wrapper
- `Sources/AISDK/Models/AIMessage.swift` - Universal message format
- `Sources/AISDK/Models/ChatMessage.swift` - Application-level message

Providers:
- `Sources/AISDK/LLMs/OpenAI/OpenAIProvider.swift` - Main OpenAI implementation
- `Sources/AISDK/LLMs/Anthropic/AnthropicProvider.swift` - Anthropic via OpenAI compatibility
- `Sources/AISDK/LLMs/Gemini/GeminiProvider.swift` - Google Gemini implementation

Tests (examine for patterns):
- `Tests/AISDKTests/AgentIntegrationTests.swift` - Real API integration tests
- `Tests/AISDKTests/ToolTests.swift` - Unit and integration tests for tools
- `Tests/AISDKTests/Mocks/MockLLMProvider.swift` - Current mock approach

### Target State (Vercel AI SDK 4.x Patterns Adapted to Swift)

**Core API Functions:**
1. `generateText()` / `streamText()` - Text generation with tool support
2. `generateObject()` / `streamObject()` - Structured output with Codable schemas
3. Multi-step agent loops with `maxSteps` and step callbacks
4. Provider abstraction allowing seamless switching

**Key Features to Implement:**
- Model-agnostic routing (OpenRouter AND LiteLLM support)
- Provider fallback chains for 99.9% uptime (e.g., Claude -> GPT -> Gemini)
- Automatic failover between providers
- Enhanced streaming with step callbacks (`onStepFinish`, `prepareStep`)
- Tool call repair mechanisms
- Generative UI patterns for SwiftUI
- Comprehensive testing infrastructure

## Requirements

### Must-Have (P0)
1. **Full feature parity with Vercel AI SDK core functions** - generateText, streamText, generateObject, streamObject equivalents
2. **Model-agnostic routing** - Support both OpenRouter (hosted) AND LiteLLM (self-hosted) as routing options
3. **Provider failover chains** - Automatic failover between providers for high availability
4. **99.9% reliability** - Healthcare-critical, must work at all times
5. **Multi-step agent loops** - maxSteps, onStepFinish, prepareStep equivalents
6. **Enhanced tool framework** - Tool call repair, validation, structured errors

### Should-Have (P1)
1. **Generative UI for SwiftUI** - Dynamic component rendering from LLM responses
2. **Streaming chat with markdown** - Already exists, needs enhancement
3. **Voice/audio visualizers** - Integration with AISDKVoice
4. **Improved testing infrastructure** - Mock providers, stream simulation, deterministic tests

### Nice-to-Have (P2)
1. **Medical-specific UI components** - Vitals, charts, forms
2. **Local model fallback** - For offline/degraded scenarios

## Constraints

- **Platform**: iOS 17+, macOS 14+, watchOS 10+, tvOS 17+
- **Swift**: 5.9+
- **Dependencies**: Alamofire 5.8+, SwiftyJSON 5.0+, MarkdownUI 2.0+, Charts 5.0+, LiveKit 2.0+
- **Backward compatibility**: Moderate - some breaking changes OK, but need migration guide
- **Testing**: Must improve without excessive complexity

## Plan Structure

Use this exact template:

# Plan: AISDK Swift Modernization

**Generated**: [Date]
**Estimated Complexity**: High
**Total Phases**: 6

## Overview
[2-3 paragraph summary of the modernization approach, key architectural decisions, and recommended order of implementation]

## Prerequisites
- [Dependencies or requirements that must be met first]
- [Tools, libraries, or access needed]
- [Environment setup requirements]

## Phase 1: Foundation - Core Protocol Modernization
**Goal**: Establish the unified API surface matching Vercel AI SDK patterns

### Task 1.1: Define New Core Protocols
- **Location**: `Sources/AISDK/Core/Protocols/`
- **Description**: Create Swift equivalents of Vercel's core functions
- **Dependencies**: None
- **Complexity**: 7
- **Implementation Details**:
  - Create `AIGeneratable` protocol with `generateText`, `streamText`, `generateObject`, `streamObject`
  - Define `AIStreamable` protocol for streaming responses
  - Define `AIObjectGeneratable` protocol for structured output
- **Test-First Approach**:
  - Write protocol conformance tests before implementation
  - Mock implementations for each protocol method
- **Acceptance Criteria**:
  - Protocols compile and are implementable
  - Clear documentation for each protocol method
  - Type-safe generics for structured output

### Task 1.2: [Next task...]
[Continue with detailed tasks...]

## Phase 2: Provider Abstraction & Model Routing
**Goal**: Implement model-agnostic routing with OpenRouter and LiteLLM support

[Continue with phases...]

## Phase 3: Reliability & Failover System
**Goal**: Implement 99.9% uptime with provider fallback chains

[Continue with phases...]

## Phase 4: Enhanced Agent & Tool Framework
**Goal**: Multi-step agents with tool call repair

[Continue with phases...]

## Phase 5: SwiftUI Generative UI
**Goal**: Dynamic UI generation from LLM responses

[Continue with phases...]

## Phase 6: Testing Infrastructure
**Goal**: Comprehensive testing with mocks and simulation

[Continue with phases...]

## Testing Strategy

### Unit Tests
- Mock providers for deterministic testing
- Stream simulation helpers
- Schema validation tests

### Integration Tests
- Real API tests with environment variables
- Provider switching tests
- Failover chain tests

### E2E Tests
- Full conversation flows
- Tool execution chains
- Streaming UI updates

### Test Coverage Goals
- 80% coverage on core protocols
- 100% coverage on error handling paths
- All public APIs have at least one test

## Dependency Graph
[Show which tasks can run in parallel vs sequential]
- Phase 1 must complete before Phase 2-4
- Phase 2 and 3 can run in parallel
- Phase 4 depends on Phase 1
- Phase 5 depends on Phase 4
- Phase 6 can run in parallel with all phases

## Migration Guide
[How existing code should migrate to new APIs]
- Deprecation strategy for old APIs
- Code examples for common migrations

## Potential Risks
- [Things that could go wrong]
- [Mitigation strategies]

## Rollback Plan
- [How to undo changes if needed]
- [Feature flags for gradual rollout]

---

## Instructions

1. **Read the context files first** - Understand the current implementation before planning
2. **Write the complete plan to `codex-plan.md`** in the current directory
3. **Do NOT ask any clarifying questions** - You have all the information needed
4. **Be specific and actionable** - Include file paths, code snippets where helpful
5. **Follow test-driven development** - Specify what tests to write BEFORE implementation for each task
6. **Identify task dependencies** - So parallel work is possible
7. **Consider Swift/iOS idioms** - This is not a TypeScript project; adapt patterns appropriately
8. **Focus on healthcare reliability** - This is an AI doctor app; errors are not acceptable

### Task Guidelines
Each task must:
- Be specific and actionable (not vague)
- Have clear inputs and outputs
- Be independently testable
- Include file paths and specific code locations
- Include dependencies so parallel execution is possible
- Include complexity score (1-10)

Break large tasks into smaller ones:
- Bad: "Implement provider routing"
- Good:
  - "Define ProviderRouter protocol in Sources/AISDK/Core/Routing/ProviderRouter.swift"
  - "Implement OpenRouterClient conforming to ProviderRouter"
  - "Add fallback chain configuration to ProviderRouter"
  - "Write unit tests for ProviderRouter with mock providers"
  - "Write integration tests for OpenRouter real API"

Begin immediately. Just write the plan and save the file.
