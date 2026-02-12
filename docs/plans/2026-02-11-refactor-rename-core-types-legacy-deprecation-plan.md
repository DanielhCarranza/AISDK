---
title: "Rename core types to legacy names + deprecate old 1.x APIs"
type: refactor
date: 2026-02-11
issue: "#13"
branch: aisdk-2.0-modernization
---

# Rename Core Types to Legacy Names + Deprecate Old 1.x APIs

## Overview

Rename AISDK 2.0 core types back to their canonical short names (`Agent`, `LLM`, `Tool`, `@Parameter`), moving the old 1.x types to `Legacy*` names with deprecation annotations. This establishes the v2 API surface as the primary interface while preserving backward compatibility for any code referencing old names.

## Problem Statement

The v2 branch introduced new types with `AI` prefixes (`AIAgentActor`, `AILanguageModel`, `AITool`, `@AIParameter`) to avoid collisions with the v1 types that still exist in the codebase. Now that v2 is maturing and there are no production adopters, we can safely reclaim the shorter canonical names for v2, pushing v1 types to `Legacy*` deprecation.

## Proposed Solution

A **3-phase approach** executed on the `aisdk-2.0-modernization` branch:

1. **Phase 1**: Rename all v1 legacy types to `Legacy*` names (clear the namespace)
2. **Phase 2**: Rename v2 types to take the freed canonical names
3. **Phase 3**: Add deprecated typealiases, update documentation and examples

Each phase must leave the project in a compilable, test-passing state.

## Technical Approach

### Architecture

The codebase is a **single Swift module** (`AISDK`) containing both v1 and v2 types. All types are exported from one module, so renames must be coordinated atomically within each phase.

**Established deprecation pattern** (from existing codebase):
```swift
/// - Note: Use `NewTypeName` instead.
@available(*, deprecated, renamed: "NewTypeName", message: "Use NewTypeName instead")
public typealias OldTypeName = NewTypeName
```

### Critical Design Decisions

#### Decision 1: AIInputMessage / AIMessage Merge

**Problem**: Two distinct message structs exist with different structures:

| | `AIInputMessage` (Models/AIMessage.swift) | `AIMessage` (Core/Protocols/AILanguageModel.swift) |
|---|---|---|
| Role | `AIMessageRole` (standalone enum) | `AIMessage.Role` (nested enum) |
| Content | `[AIContentPart]` (array) | `Content` enum (`.text(String)` or `.parts([ContentPart])`) |
| ToolCall args | `[String: Any]` | `String` |
| Multimodal | Full (image, audio, video, file, json, html, markdown) | Basic (text, image, imageURL, audio, file) |

**Recommendation**: Keep `AIMessage` as the canonical type (it's the v2 protocol-layer type used by `AIAgentActor`, `AIAgent`, and all adapters). Add a deprecated `typealias AIInputMessage = AIMessage`. Provider conversion extensions currently on `AIInputMessage` should be migrated to `AIMessage` extensions. The richer multimodal content from `AIInputMessage` should be ported into `AIMessage.ContentPart` if not already present.

**Note**: This merge requires careful attention to the `ToolCall.arguments` type difference (`[String: Any]` vs `String`). The v2 `String` type is the correct one (JSON-encoded arguments string).

#### Decision 2: 3-Phase Typealias Strategy

**Problem**: If Phase 1 adds `typealias Agent = LegacyAgent`, Phase 2 cannot rename `AIAgentActor` to `Agent` because the typealias already claims the name.

**Solution**:
- Phase 1: Rename types only. NO typealiases.
- Phase 2: Rename types only. NO typealiases.
- Phase 3: Add ALL deprecated typealiases pointing old names to final locations.

#### Decision 3: AIAgent Protocol Naming

**Problem**: If `AIAgentActor` becomes `Agent`, the `AIAgent` protocol sitting alongside it is confusingly named.

**Recommendation**: Leave `AIAgent` protocol as-is for this PR. It can be addressed in a follow-up if needed. The protocol and actor serve different purposes (protocol = interface, actor = concrete implementation) and the `AI` prefix on the protocol helps distinguish it.

#### Decision 4: AIAgentState vs AgentState

**Problem**: v1 `AgentState` and v2 `AIAgentState` have different error types (`.error(AIError)` vs `.error(String)`).

**Recommendation**: Only rename v1 `AgentState` to `LegacyAgentState`. Leave v2 `AIAgentState` as-is for now. Renaming `AIAgentState` to `AgentState` would be a subtle behavioral change. Address in a follow-up.

#### Decision 5: Tool.swift File Naming Conflict

**Problem**: `Tool.swift` currently contains `Parameter<Value>`, `ToolMetadata`, and related types. `AITool.swift` needs to become `Tool.swift`.

**Solution**: Rename existing `Tool.swift` to `Parameter.swift` (since its primary content is the `Parameter` property wrapper), then rename `AITool.swift` to `Tool.swift`.

#### Decision 6: Scope Boundary for AI* Types

**Recommendation**: Only rename the types explicitly listed in Issue #13. These related types are OUT OF SCOPE for this PR but noted for future work:
- `AIAgentResult`, `AIAgentResponse`, `AIAgentEvent` (follow Agent naming)
- `AIAgentState`, `AIAgentCallbacks`, `AIAgentError` (follow Agent naming)
- `AIToolExecutionResult`, `AIToolCallResult` (follow Tool naming)
- `AIStreamEvent`, `AITextRequest`, `AITextResult` (protocol-layer types)
- `AIObjectRequest`, `AIObjectResult`, `AIUsage` (protocol-layer types)

### Implementation Phases

#### Phase 1: Clear the Namespace (Legacy Renames)

Rename all v1 types to `Legacy*` names. Update all references. Verify build + tests.

**Type Renames:**

| Current Name | New Name | File | File Rename |
|---|---|---|---|
| `Agent` (class) | `LegacyAgent` | `Sources/AISDK/Agents/Agent.swift` | `LegacyAgent.swift` |
| `LLM` (protocol) | `LegacyLLM` | `Sources/AISDK/LLMs/LLMProtocol.swift` | `LegacyLLM.swift` |
| `Message` (enum) | `LegacyMessage` | `Sources/AISDK/LLMs/OpenAI/APIModels/ChatCompletion/Message.swift` | `LegacyMessage.swift` |
| `AgentState` (enum) | `LegacyAgentState` | `Sources/AISDK/Agents/AgentState.swift` | `LegacyAgentState.swift` |
| `ChatMessage` (class) | `LegacyChatMessage` | `Sources/AISDK/Models/ChatMessage.swift` | `LegacyChatMessage.swift` |
| `AgentCallbacks` (protocol) | `LegacyAgentCallbacks` | `Sources/AISDK/Agents/AgentCallbacks.swift` | `LegacyAgentCallbacks.swift` |
| `ToolRegistry` (class, if exists) | `LegacyToolRegistry` | `Sources/AISDK/Tools/ToolRegistry.swift` | `LegacyToolRegistry.swift` (if exists) |

**Files requiring reference updates (Phase 1):**

Sources (~20 files):
- `Sources/AISDK/Agents/Agent.swift` (definition + internal refs)
- `Sources/AISDK/Agents/AgentState.swift` (definition)
- `Sources/AISDK/Agents/AgentCallbacks.swift` (definition)
- `Sources/AISDK/Agents/ResponseAgent.swift` (may reference Agent/AgentState)
- `Sources/AISDK/Agents/ResearchAgent/Agent/ExperimentalResearchAgent.swift` (uses LLM, AgentState, ChatMessage)
- `Sources/AISDK/Core/Adapters/Legacy/AIAgentAdapter.swift` (wraps Agent, uses AgentState, ChatMessage, Message)
- `Sources/AISDK/Core/Adapters/Legacy/AILanguageModelAdapter.swift` (wraps LLM, uses Message)
- `Sources/AISDK/Core/Adapters/Legacy/AIUsage+Legacy.swift` (legacy usage conversion)
- `Sources/AISDK/LLMs/LLMProtocol.swift` (LLM definition)
- `Sources/AISDK/LLMs/OpenAI/OpenAIProvider.swift` (implements LLM)
- `Sources/AISDK/LLMs/Anthropic/AnthropicProvider.swift` (implements LLM)
- `Sources/AISDK/LLMs/Anthropic/AnthropicService.swift` (implements LLM)
- `Sources/AISDK/LLMs/OpenAI/APIModels/ChatCompletion/Message.swift` (Message definition)
- `Sources/AISDK/LLMs/OpenAI/APIModels/ChatCompletion/ChatCompletionRequest.swift` (uses Message)
- `Sources/AISDK/Models/ChatMessage.swift` (ChatMessage definition, wraps Message)
- `Sources/AISDKChat/Manager/AIChatManager.swift` (uses Agent, LLM, ChatMessage, AgentState)
- `Sources/AISDKVision/Providers/ChatContext.swift` (uses Agent, LLM)

Tests (~15 files):
- `Tests/AISDKTests/AgentIntegrationTests.swift`
- `Tests/AISDKTests/AgentToolTests.swift`
- `Tests/AISDKTests/ResponseAgentIntegrationTests.swift`
- `Tests/AISDKTests/MCPIntegrationTests.swift`
- `Tests/AISDKTests/Memory/StreamMemoryTests.swift`
- `Tests/AISDKTests/Mocks/MockLLMProvider.swift`

Examples (~8 files):
- `Examples/Demos/ChatDemoView.swift`
- `Examples/Demos/AgentDemoView.swift`
- `Examples/BasicChatDemo/main.swift`
- `Examples/AISDKCLI/CLIController.swift`
- `Examples/ToolDemo/main.swift`

#### Phase 2: Claim Canonical Names (v2 Renames)

Rename v2 types to their canonical short names. Update all references. Verify build + tests.

**Type Renames:**

| Current Name | New Name | File | File Rename |
|---|---|---|---|
| `AIAgentActor` (actor) | `Agent` | `Sources/AISDK/Agents/AIAgentActor.swift` | `Agent.swift` |
| `AILanguageModel` (protocol) | `LLM` | `Sources/AISDK/Core/Protocols/AILanguageModel.swift` | `LLM.swift` |
| `AITool` (protocol) | `Tool` | `Sources/AISDK/Tools/AITool.swift` | `Tool.swift` |
| `AIToolRegistry` (class) | `ToolRegistry` | `Sources/AISDK/Tools/AITool.swift` | (same file as Tool) |
| `AIToolResult` (struct) | `ToolResult` | `Sources/AISDK/Tools/AITool.swift` | (same file as Tool) |
| `AIToolExecutionResult` (struct) | `ToolExecutionResult` | `Sources/AISDK/Tools/AITool.swift` | (same file as Tool) |

**Pre-requisite file rename:**
- Rename existing `Tool.swift` (containing `Parameter`, `ToolMetadata`) to `Parameter.swift` BEFORE renaming `AITool.swift` to `Tool.swift`.

**Parameter handling:**
- Remove `@AIParameter` typealias from `AIParameter.swift`
- `@Parameter` remains as the canonical property wrapper (it already is)
- Rename `AIParameter.swift` to `ParameterSchema.swift` (reflects its actual content: validation, schema generation)

**Files requiring reference updates (Phase 2):**

Sources (~30 files):
- `Sources/AISDK/Agents/AIAgentActor.swift` (definition, 292 self-references)
- `Sources/AISDK/Core/Protocols/AILanguageModel.swift` (definition)
- `Sources/AISDK/Core/Protocols/AIAgent.swift` (references AILanguageModel)
- `Sources/AISDK/Tools/AITool.swift` (AITool, AIToolRegistry, AIToolResult definitions)
- `Sources/AISDK/Tools/AIParameter.swift` (AIParameter typealias removal)
- `Sources/AISDK/Tools/WebSearchTool.swift` (implements AITool)
- `Sources/AISDK/Tools/ToolCallRepair.swift` (uses AILanguageModel, AITool)
- `Sources/AISDK/Core/Adapters/Legacy/AIAgentAdapter.swift` (uses AILanguageModel)
- `Sources/AISDK/Core/Adapters/Legacy/AILanguageModelAdapter.swift` (conforms to AILanguageModel)
- `Sources/AISDK/Core/Adapters/Provider/ProviderLanguageModelAdapter.swift` (conforms to AILanguageModel)
- `Sources/AISDK/Core/Providers/ProviderClient.swift` (references AILanguageModel)
- `Sources/AISDK/Core/Providers/OpenAIClientAdapter.swift`
- `Sources/AISDK/Core/Providers/AnthropicClientAdapter.swift`
- `Sources/AISDK/Core/Providers/GeminiClientAdapter.swift`
- `Sources/AISDK/Core/Reliability/CapabilityAwareFailover.swift`
- `Sources/AISDK/MCP/MCPServerConfiguration.swift` (doc comments)
- `Sources/AISDK/Skills/SkillConfiguration.swift` (doc comments)
- All provider conversion extensions (`AIMessage+*Conversions.swift`)

Tests (~20 files):
- `Tests/AISDKTests/Agents/AIAgentActorTests.swift` (50+ refs)
- `Tests/AISDKTests/Mocks/MockAILanguageModel.swift` (40+ refs, rename file to `MockLLM.swift`)
- `Tests/AISDKTests/Mocks/MockAILanguageModelTests.swift` (rename to `MockLLMTests.swift`)
- `Tests/AISDKTests/Tools/AIToolTests.swift` (rename to `ToolTests.swift` - check for collision)
- `Tests/AISDKTests/Tools/AIParameterTests.swift` (rename to `ParameterTests.swift`)
- `Tests/AISDKTests/Tools/ToolCallRepairTests.swift`
- `Tests/AISDKTests/Tools/WebSearchToolTests.swift`
- `Tests/AISDKTests/AgentIntegrationTests.swift`
- `Tests/AISDKTests/Core/Providers/*AdapterTests.swift` (multiple files)

#### Phase 3: Typealiases, Documentation, and Examples

Add all deprecated typealiases and update all documentation.

**Deprecated Typealiases (add to a `Sources/AISDK/Deprecated.swift` file):**

```swift
// MARK: - v2 Name Compatibility (for early v2 adopters)

@available(*, deprecated, renamed: "Agent")
public typealias AIAgentActor = Agent

@available(*, deprecated, renamed: "LLM")
public typealias AILanguageModel = LLM

@available(*, deprecated, renamed: "Tool")
public typealias AITool = Tool

@available(*, deprecated, renamed: "ToolRegistry")
public typealias AIToolRegistry = ToolRegistry

@available(*, deprecated, renamed: "ToolResult")
public typealias AIToolResult = ToolResult

@available(*, deprecated, renamed: "ToolExecutionResult")
public typealias AIToolExecutionResult = ToolExecutionResult

@available(*, deprecated, renamed: "Parameter")
public typealias AIParameter<Value: Codable> = Parameter<Value>

@available(*, deprecated, renamed: "AIMessage")
public typealias AIInputMessage = AIMessage

// MARK: - v1 Legacy Compatibility

@available(*, deprecated, renamed: "LegacyAgent", message: "Use Agent (v2 actor) or LegacyAgent (v1 class)")
public typealias _V1Agent = LegacyAgent

@available(*, deprecated, renamed: "LegacyLLM", message: "Use LLM (v2 protocol) or LegacyLLM (v1 protocol)")
public typealias _V1LLM = LegacyLLM

@available(*, deprecated, renamed: "LegacyParameter", message: "Use @Parameter instead")
public typealias LegacyParameter<Value: Codable> = Parameter<Value>
```

**Documentation Updates (all files):**

| File | Changes |
|---|---|
| `docs/MIGRATION-GUIDE.md` | Update all type name references, fix `systemPrompt:` → `instructions:` on line 276 |
| `docs/WHATS_NEW_AISDK_2.md` | Update type name references |
| `docs/AISDK-ARCHITECTURE.md` | Update type name references |
| `docs/api-reference/agents.md` | AIAgentActor → Agent |
| `docs/api-reference/core-protocols.md` | AILanguageModel → LLM |
| `docs/api-reference/tools.md` | AITool → Tool, @AIParameter → @Parameter |
| `docs/api-reference/models.md` | AIInputMessage → AIMessage |
| `docs/api-reference/providers.md` | Adapter name updates |
| `docs/tutorials/01-getting-started.md` | Update type references |
| `docs/tutorials/02-streaming-basics.md` | Update type references |
| `docs/tutorials/03-tool-creation.md` | AITool → Tool, @AIParameter → @Parameter |
| `docs/tutorials/04-multi-step-agents.md` | AIAgentActor → Agent |
| `docs/tutorials/05-generative-ui.md` | Update references |
| `docs/tutorials/06-reliability-patterns.md` | Update references |
| `docs/tutorials/07-testing-strategies.md` | MockAILanguageModel → MockLLM |
| `Sources/AISDK/docs/**` | Sweep all bundled docs |

**Example App Updates:**

| File | Changes |
|---|---|
| `Examples/Demos/ChatDemoView.swift` | LegacyAgent/LegacyLLM usage or migrate to Agent/LLM |
| `Examples/Demos/AgentDemoView.swift` | Same |
| `Examples/Demos/DemoTools.swift` | AITool → Tool, @AIParameter → @Parameter |
| `Examples/BasicChatDemo/main.swift` | Update all type references |
| `Examples/AISDKCLI/CLIController.swift` | Update all type references |
| `Examples/AISDKCLI/Tools/*.swift` | AITool → Tool |
| `Examples/ToolDemo/main.swift` | Update all type references |

## Acceptance Criteria

### Functional Requirements

- [ ] Canonical public API names are `Agent`, `LLM`, `Tool`, `@Parameter` (with v2 implementations)
- [ ] Legacy 1.x APIs remain available under `Legacy*` names with `@available(*, deprecated)` annotations
- [ ] Deprecated typealiases exist for old v2 names (`AIAgentActor`, `AILanguageModel`, `AITool`, `@AIParameter`)
- [ ] Deprecated typealias exists for `AIInputMessage` pointing to `AIMessage`
- [ ] `AIMessage` struct is unchanged (as specified in Issue #13)
- [ ] `@Parameter` property wrapper is unchanged (shared by both APIs)

### Non-Functional Requirements

- [ ] `swift build` succeeds after each phase
- [ ] `swift test` passes after each phase (all 117 test files)
- [ ] No new compiler warnings except intentional deprecation warnings
- [ ] All documentation references updated to use new canonical names

### Quality Gates

- [ ] Grep for orphaned references: `AIAgentActor`, `AILanguageModel`, `AITool` (should only appear in deprecated typealiases)
- [ ] Grep for unmigrated legacy references: bare `Agent`, `LLM`, `Tool` in contexts that should say `LegacyAgent`, `LegacyLLM`, etc.
- [ ] MIGRATION-GUIDE.md accurately reflects the new naming model

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| File naming collision (`Tool.swift`) | Certain | Build failure | Rename existing `Tool.swift` to `Parameter.swift` before `AITool.swift` to `Tool.swift` |
| AIInputMessage/AIMessage merge breaks provider conversions | Medium | Compile errors in 12+ files | Test after merge, update conversion extensions incrementally |
| Missed references cause compile errors | Low | Build failure | Use `swift build` after each batch of renames, use grep to find orphans |
| Subtle semantic change in AgentState | Low | Runtime behavior change | Leave `AIAgentState` as-is; only rename v1 `AgentState` to `LegacyAgentState` |
| Scope creep into all `AI*` types | Medium | Delayed delivery | Strict scope boundary: only types listed in Issue #13 |

## Out of Scope (Future Work)

These types are NOT renamed in this PR but may be addressed later:

- `AIAgent` protocol (stays as-is)
- `AIAgentState`, `AIAgentResponse`, `AIAgentEvent`, `AIAgentCallbacks` (stay as-is)
- `AIAgentResult` (stays as-is)
- `AIStreamEvent`, `AITextRequest`, `AITextResult` (stay as-is)
- `AIObjectRequest`, `AIObjectResult`, `AIUsage` (stay as-is)
- `AIFinishReason` (stays as-is)
- Adapter class renames (`AIAgentAdapter`, `AILanguageModelAdapter`)
- Commented-out module sources (`AISDKChat`, `AISDKVoice`, `AISDKVision`)

## Dependencies & Prerequisites

- Must be on `aisdk-2.0-modernization` branch
- No open PRs touching the same files (coordinate with team)
- `swift build` and `swift test` pass on current branch before starting

## References & Research

### Internal References

- Issue: #13 (DO BEFORE SKILLS CREATION: Rename core types to legacy names + deprecate old 1.x APIs)
- Existing deprecation pattern: `Sources/AISDK/Agents/ResponseAgent.swift:938-946`
- Existing typealias pattern: `Sources/AISDK/Tools/AIParameter.swift:191`
- Adapter layer: `Sources/AISDK/Core/Adapters/Legacy/`
- Migration guide: `docs/MIGRATION-GUIDE.md`

### Key File Locations

| Type | Current Location |
|---|---|
| `AIAgentActor` | `Sources/AISDK/Agents/AIAgentActor.swift:44` |
| `AILanguageModel` | `Sources/AISDK/Core/Protocols/AILanguageModel.swift:233` |
| `AITool` | `Sources/AISDK/Tools/AITool.swift:13` |
| `AIToolRegistry` | `Sources/AISDK/Tools/AITool.swift:78` |
| `@AIParameter` | `Sources/AISDK/Tools/AIParameter.swift:191` (typealias) |
| `@Parameter` | `Sources/AISDK/Tools/Tool.swift:23` (actual class) |
| `AIInputMessage` | `Sources/AISDK/Models/AIMessage.swift:14` |
| `AIMessage` | `Sources/AISDK/Core/Protocols/AILanguageModel.swift:15` |
| `Agent` (v1) | `Sources/AISDK/Agents/Agent.swift:12` |
| `LLM` (v1) | `Sources/AISDK/LLMs/LLMProtocol.swift:11` |
| `Message` (v1) | `Sources/AISDK/LLMs/OpenAI/APIModels/ChatCompletion/Message.swift:4` |
| `AgentState` (v1) | `Sources/AISDK/Agents/AgentState.swift` |
| `ChatMessage` (v1) | `Sources/AISDK/Models/ChatMessage.swift` |
| `AgentCallbacks` (v1) | `Sources/AISDK/Agents/AgentCallbacks.swift` |

## MVP Task Checklist

### Phase 1: Clear the Namespace

- [ ] Rename `Agent` class to `LegacyAgent` (file + all references)
- [ ] Rename `AgentState` enum to `LegacyAgentState` (file + all references)
- [ ] Rename `AgentCallbacks` protocol to `LegacyAgentCallbacks` (file + all references)
- [ ] Rename `LLM` protocol to `LegacyLLM` (file + all references)
- [ ] Rename `Message` enum to `LegacyMessage` (file + all references)
- [ ] Rename `ChatMessage` class to `LegacyChatMessage` (file + all references)
- [ ] Update `ObservableAgentState.state` type reference if it uses v1 `AgentState`
- [ ] Run `swift build` - verify compilation
- [ ] Run `swift test` - verify all tests pass
- [ ] Commit: "Rename v1 legacy types to Legacy* names"

### Phase 2: Claim Canonical Names

- [ ] Rename `Tool.swift` to `Parameter.swift` (file rename only, no code changes)
- [ ] Rename `AITool` protocol to `Tool` (file `AITool.swift` → `Tool.swift` + all references)
- [ ] Rename `AIToolRegistry` class to `ToolRegistry` (same file + all references)
- [ ] Rename `AIToolResult` struct to `ToolResult` (same file + all references)
- [ ] Rename `AIToolExecutionResult` struct to `ToolExecutionResult` (same file + all references)
- [ ] Rename `AIAgentActor` actor to `Agent` (file `AIAgentActor.swift` → `Agent.swift` + all references)
- [ ] Rename `AILanguageModel` protocol to `LLM` (file `AILanguageModel.swift` → `LLM.swift` + all references)
- [ ] Remove `@AIParameter` typealias from `AIParameter.swift`
- [ ] Rename `AIParameter.swift` to `ParameterSchema.swift`
- [ ] Merge `AIInputMessage` into `AIMessage` (add deprecated typealias)
- [ ] Update mock files: `MockAILanguageModel.swift` → `MockLLM.swift`
- [ ] Update test files: `AIAgentActorTests.swift` → `AgentTests.swift`, `AIToolTests.swift` → `ToolTests.swift`, etc.
- [ ] Run `swift build` - verify compilation
- [ ] Run `swift test` - verify all tests pass
- [ ] Commit: "Rename v2 types to canonical names"

### Phase 3: Typealiases, Docs, and Examples

- [ ] Create `Sources/AISDK/Deprecated.swift` with all deprecated typealiases
- [ ] Add `@available(*, deprecated)` annotations on all `Legacy*` types
- [ ] Update `docs/MIGRATION-GUIDE.md` (all references + fix systemPrompt → instructions)
- [ ] Update `docs/WHATS_NEW_AISDK_2.md`
- [ ] Update `docs/AISDK-ARCHITECTURE.md`
- [ ] Update `docs/api-reference/*.md` (8 files)
- [ ] Update `docs/tutorials/*.md` (7 files)
- [ ] Update `Sources/AISDK/docs/**` (bundled docs)
- [ ] Update `Examples/**` (6+ example apps)
- [ ] Run `swift build` - final verification
- [ ] Run `swift test` - final verification
- [ ] Grep for orphaned `AIAgentActor`, `AILanguageModel`, `AITool` references
- [ ] Commit: "Add deprecated typealiases and update documentation"
- [ ] Push and create PR targeting `aisdk-2.0-modernization`
