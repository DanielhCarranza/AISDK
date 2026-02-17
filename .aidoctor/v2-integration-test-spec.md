# AISDK v2 Integration Test in AIDoctor — Refined Spec

> Captured from interview on 2026-02-16. 9 questions asked, all key decisions resolved.

---

## Problem Statement

AISDK v2 has passed its own production evaluation (2,397 tests, 8 subsystems scored 4.1/5 average, verdict: GO). But it has never been tested inside AIDoctor — the real production app that depends on it across ~45 files. Until v2 works in AIDoctor, we cannot confidently ship it.

## Goal

Validate that AISDK v2 works as a drop-in replacement for v1 in the AIDoctor iOS app, using the adapter-first strategy, then progressively migrate to native v2 APIs. Produce a prioritized test matrix and a v1-to-v2 migration document.

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Dependency strategy** | Local path first, then beta tag | Fastest iteration for urgent timeline |
| **Migration strategy** | Adapter-first, then incremental native v2 | Minimizes initial blast radius; validates quickly |
| **Tool migration** | Migrate ALL tools to AITool | Clean break; document every change |
| **AIDoctor branch** | `feat/aisdk-v2-migration-test` | Isolate from main; safe experimentation |
| **Testing environment** | Simulator first, then physical device | Start fast, verify on hardware later |
| **Firebase** | Emulator (not production) | Safe testing |
| **Existing Firestore sessions** | New sessions only for now | v1 ChatMessage → v2 AIMessage migration deferred |
| **v2 new features** | Also evaluate (Generative UI, Sessions, Reliability) | Not just backward compat — explore new capabilities |
| **Migration doc location** | In the AIDoctor repo | App-specific migration knowledge |
| **Voice** | EXCLUDED | Disabled, will be added later |

---

## AIDoctor Setup

- **Repo**: Separate GitHub repo (`DanielhCarranza/AISDK` for SDK, separate repo for AIDoctor)
- **Project type**: Xcode project (`.xcodeproj`) with SPM dependencies via Xcode
- **Current AISDK ref**: `https://github.com/DanielhCarranza/AISDK.git` pinned to version `1.0.0` tag
- **Product linked**: `AISDK` core only (no optional modules)
- **Deployment target**: iOS 17+ (aligned with AISDK v2)
- **Alamofire**: Already used (5.10.2, compatible with AISDK v2's 5.8+ requirement)
- **SwiftyJSON**: Not used — will be added as transitive dependency (no conflict)
- **AIDoctor path on machine**: `~/conductor/workspaces/AIDoctoriOSApp/chengdu` (branch: `jmush16/chengdu`)

---

## Test Flow Matrix (Priority Order)

| # | Feature | v1 Surface | v2 Surface (via adapter) | v2 Native Surface | Verification Method |
|---|---------|-----------|------------------------|-------------------|-------------------|
| 1 | **AI Chat Streaming** | `Agent.sendStream()` → `ChatMessage` with `isPending` | `AIAgentAdapter.streamExecute()` → `AIStreamEvent` | `AIAgentActor.streamExecute()` → `AIStreamEvent` | Send message, verify tokens stream incrementally, response completes |
| 2 | **Tool Calling** | `Tool` protocol, `@Parameter`, `execute() → (String, ToolMetadata?)` | N/A (migrate directly) | `AITool`, `@AIParameter`, `execute() → AIToolResult` | Trigger tool call (e.g., ThinkTool), verify execution and result |
| 3 | **Agent State Observation** | `agent.onStateChange: (AgentState) → Void` | Adapter maps to v2 events | `AIAgentActor` state via `@Observable` | Verify UI shows thinking → tool executing → responding → idle |
| 4 | **Structured Output** | `generateObject<T: JSONSchemaModel>()` with `@Field` | `AILanguageModelAdapter.generateObject()` | `AILanguageModel.generateObject()` | Medication lookup returns typed `MedicationInformation` |
| 5 | **Multimodal (Vision)** | `ChatMessage(.user(.parts([.text, .imageURL(.base64)])))` | Adapter converts to `AIMessage` parts | `AIMessage.user(content: .parts([.text, .image]))` | Submit medication photo, verify extraction |
| 6 | **Suggested Questions** | `ChatCompletionRequest` + `JSONSchemaModel` | Via `AILanguageModelAdapter` | `AITextRequest` + `AIObjectRequest` | After chat, verify 3 follow-up questions generated |
| 7 | **Health Profile Context** | `ChatMessage(.system(.text(healthContext)))` | Adapter converts system message | `AIMessage.system(healthContext)` | Verify personalized responses reference user health data |
| 8 | **Session Persistence** | App-managed Firestore `ChatSession` with `[ChatMessage]` | Map `AIMessage` ↔ Firestore | v2 `SessionStore` (optional upgrade) | Start session, send messages, restart app, verify session loads |
| 9 | **Error Handling** | `AgentState.error(AIError)` | Adapter maps errors | v2 `AIError` taxonomy | Force error (bad API key), verify error card shows |
| 10 | **Research Mode** | `ExperimentalResearchAgent` + 12 specialized tools | Adapter wrapping | Native v2 agent + migrated tools | Run research query, verify evidence collection |
| 11 | **Document Analysis** | AISDK types for structured extraction | Via adapter | Native v2 types | Upload medical document, verify biomarker extraction |
| 12 | **Health Profile Summaries** | `OpenAIProvider` + `ChatCompletionRequest` | `AILanguageModelAdapter` | `AILanguageModel.generateText()` | Generate summary, verify output |
| 13 | **Generative UI (NEW v2)** | N/A (didn't exist in v1) | N/A | `GenerativeUIView` + `UICatalog` | Explore adding Generative UI components to AIDoctor |
| 14 | **Reliability (NEW v2)** | N/A | N/A | `RetryPolicy` + `CircuitBreaker` + `FailoverExecutor` | Verify retry behavior on transient failures |
| 15 | **Context Compaction (NEW v2)** | N/A | N/A | `SessionCompactionService` | Long conversation triggers compaction, verify quality |

---

## Critical Migration Items to Document

1. **ChatMessage → AIMessage**: Different structure. Firestore sessions saved with v1 format won't decode as v2. **Deferred** — new sessions only for now. Must be solved before production release.
2. **Tool protocol change**: `Tool` with `@Parameter` → `AITool` with `@AIParameter`. Return type changes from `(String, ToolMetadata?)` to `AIToolResult`. Every tool must be migrated.
3. **Agent initialization**: `Agent(llm:tools:instructions:)` → `AIAgentActor(model:tools:systemPrompt:)`. Provider wrapping required.
4. **Streaming model change**: `for await message in agent.sendStream()` (yields `ChatMessage`) → `for await event in agent.streamExecute()` (yields typed `AIStreamEvent`). Entire streaming handler in `AIChatManager` must be rewritten.
5. **State observation**: `agent.onStateChange` closure → `@Observable` pattern. UI bindings need updating.
6. **Provider initialization**: `OpenAIProvider(model:apiKey:)` → `AILanguageModelAdapter.fromOpenAI()` (adapter) or `OpenRouterClient(apiKey:)` (native).
7. **LLMModelAdapter**: v1 has detailed model capability descriptions. v2 uses `LLMCapabilities`. Mapping needed.
8. **MetadataTracker / ToolMetadata**: v1 callback-based metadata accumulation. v2 tool results are structured differently. Research mode depends heavily on this.

---

## Execution Plan (High-Level)

### Phase A: Setup (AISDK repo)
1. Verify AISDK v2 builds cleanly on `aisdk-2.0-modernization`
2. Identify any v2 public API gaps that would block AIDoctor integration
3. Create v1→v2 API mapping document

### Phase B: AIDoctor Integration
1. Create branch `feat/aisdk-v2-migration-test` in AIDoctor repo
2. Script the dependency swap (remote URL → local path to AISDK v2)
3. Attempt compilation — catalog all errors
4. Apply adapters (`AILanguageModelAdapter`, `AIAgentAdapter`) to fix compilation
5. Migrate all tools from `Tool` → `AITool`
6. Fix remaining compilation errors

### Phase C: Feature Testing (follow test matrix above)
1. Work through test matrix items 1-12 in order
2. Document pass/fail for each
3. Fix SDK-side issues discovered during testing

### Phase D: New v2 Features
1. Evaluate Generative UI, Reliability, Context Compaction in AIDoctor context
2. Prototype one new feature integration

### Phase E: Beta Tag + Documentation
1. Tag AISDK v2 as `2.0.0-beta.1`
2. Switch AIDoctor dependency from local path to beta tag
3. Verify clean resolution
4. Write migration document in AIDoctor repo

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| v2 adapter layer has gaps for AIDoctor's specific usage patterns | Medium | High | Discover early in Phase B compilation; fix in SDK |
| Tool migration breaks side effects (Firestore writes, etc.) | Low | Medium | Test each tool individually against emulator |
| Streaming event model mismatch causes UI bugs | Medium | High | Compare v1 vs v2 streaming behavior side-by-side |
| SwiftyJSON transitive dependency conflicts | Low | Low | Already confirmed no conflict |
| Firestore ChatMessage format incompatibility | Known | High | Deferred — new sessions only for now |

---

## Out of Scope

- Voice mode (AISDKVoice) — disabled, will be added later
- v1 Firestore session migration — deferred to production release phase
- AISDKChat, AISDKVision, AISDKResearch optional modules — not currently used
- Pushing changes to AIDoctor main branch
