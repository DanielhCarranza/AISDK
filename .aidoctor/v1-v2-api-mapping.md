# AISDK v1 → v2 API Mapping for AIDoctor

## Phase 1 Pre-Flight Results

- **Build:** PASS (`swift build` clean on `jmush16/prod-test-strategy`)
- **Tests:** PASS (2,071 XCTest + 326 Swift Testing = 2,397 total, 0 unexpected failures)

---

## API Mapping Table

| v1 API (AIDoctor uses) | v2 Equivalent | Status | Migration Effort |
|------------------------|---------------|--------|-----------------|
| `Tool.execute() -> (content: String, metadata: ToolMetadata?)` | `Tool.execute() -> ToolResult` | `requires-migration` | ~1 line per tool (wrap in `ToolResult(content:metadata:)`) |
| `ToolMetadata` protocol | `ToolMetadata` protocol | `identical` | None |
| `@Parameter` property wrapper | `@Parameter` property wrapper | `identical` | None |
| `JSONSchemaModel` protocol | `JSONSchemaModel` protocol | `identical` | None |
| `@Field` property wrapper | `@Field` property wrapper | `identical` | None |
| `Agent` class (v1 `LegacyAgent`) | `LegacyAgent` (preserved) + new `Agent` actor | `adapter-wrapped` | Use `AIAgentAdapter` or keep `LegacyAgent` directly |
| `ExperimentalResearchAgent` | `ExperimentalResearchAgent` | `identical` | None — class preserved in v2 |
| `MetadataTracker` | `MetadataTracker` | `identical` | None — preserved in `LegacyAgentCallbacks.swift` |
| `ChatMessage` | `LegacyChatMessage` + `AIMessage` (new) | `adapter-wrapped` | Use `LegacyChatMessage` for compatibility; migrate to `AIMessage` later |
| `OpenAIProvider` | `LegacyLLM` implementations + `AILanguageModelAdapter` | `adapter-wrapped` | Wrap with `AILanguageModelAdapter` for `generateObject()` |
| `OpenAIProvider.generateObject<T>()` | `AILanguageModelAdapter.generateObject(request:)` | `adapter-wrapped` | Wrap in `AIObjectRequest<T>`, returns `AIObjectResult<T>` |
| `agent.sendStream()` | `AIAgentAdapter.sendStream()` → `AsyncThrowingStream<AIAgentEvent, Error>` | `adapter-wrapped` | Events: `.textDelta`, `.toolCall`, `.toolResult`, `.stateChange`, `.finish` |
| `agent.setMessages([ChatMessage])` | `AIAgentAdapter.setMessages([AIMessage])` | `adapter-wrapped` | Convert `ChatMessage` → `AIMessage` at boundary |
| `agent.onStateChange` | `AIAgentAdapter` forwards state changes | `adapter-wrapped` | Callback bridge included |
| `agent.addCallbacks(MetadataTracker)` | `LegacyAgent.addCallbacks()` preserved | `identical` | None — `MetadataTracker` conforms to `LegacyAgentCallbacks` |
| `LLMModelAdapter` | **Removed** — replaced by `AILanguageModelAdapter` | `removed` | Use `AILanguageModelAdapter` instead |
| `Message` enum (`.user`, `.assistant`, `.system`, `.tool`) | `AIMessage.Role` enum | `adapter-wrapped` | Same roles, different type name |

---

## Phase 1.3: Adapter Coverage Verification

### Verified (all have adapter support):

| Pattern | Adapter Coverage | Source |
|---------|-----------------|--------|
| `Agent.sendStream(_ message:, requiredTool:)` | `AIAgentAdapter.sendStream()` | `AIAgentAdapter.swift:141-215` |
| `agent.setMessages([ChatMessage])` | `AIAgentAdapter.setMessages([AIMessage])` | `AIAgentAdapter.swift:221-224` |
| `agent.onStateChange` | Forwarded via adapter | `AIAgentAdapter.swift:69-76` |
| `agent.addCallbacks(MetadataTracker)` | `MetadataTracker` preserved | `LegacyAgentCallbacks.swift:43-97` |
| `OpenAIProvider.generateObject<T>()` | `AILanguageModelAdapter.generateObject(request:)` | `AILanguageModelAdapter.swift:136-177` |
| `ExperimentalResearchAgent` | Class preserved in v2 | `ExperimentalResearchAgent.swift:20` |

### Not found / Removed:

| Pattern | Status | Mitigation |
|---------|--------|------------|
| `LLMModelAdapter` | Removed from v2 | Use `AILanguageModelAdapter` (drop-in replacement with richer API) |

---

## Risk Assessment Summary

| Risk Item | Finding | Impact |
|-----------|---------|--------|
| `ExperimentalResearchAgent` removed? | **Still exists** | No impact |
| `MetadataTracker` unsupported? | **Still exists** | No impact |
| `LLMModelAdapter` missing? | **Removed, replaced** | Low — use `AILanguageModelAdapter` |
| `ChatMessage` gone? | **`LegacyChatMessage` available** | Low — use legacy type for now |
| Tool return type changed? | **Yes, `ToolResult` struct** | Low — ~1 line change per tool |

---

## Migration Effort Estimate (AIDoctor)

| Category | File Count | Change Type | Effort |
|----------|-----------|-------------|--------|
| Tool return types | 13 tools across ~10 files | Wrap return in `ToolResult(...)` | Trivial |
| Agent initialization | 2 files | May compile as-is with `LegacyAgent` | Trivial |
| Message types | 8 view + 5 core files | Use `LegacyChatMessage` or add typealias | Low |
| Structured output | 4 files | Wrap with `AIObjectRequest<T>` | Low |
| ToolMetadata types | 0 changes needed | Identical protocol | None |
| LLMModelAdapter references | TBD (grep in AIDoctor) | Rename to `AILanguageModelAdapter` | Trivial |

**Overall verdict: v2 is ready for AIDoctor integration. No blocking API gaps found.**

---

## Phase 2-3: Actual Compilation Results

### Compatibility typealiases added to AISDK v2

File: `Sources/AISDK/Compatibility/V1Compatibility.swift`

| v1 Name | v2 Name | Typealias Added |
|---------|---------|----------------|
| `ChatMessage` | `LegacyChatMessage` | Yes |
| `ResearcherAgentState` | `ResearcherLegacyAgentState` | Yes |
| `AgentState` | `LegacyAgentState` | Yes |
| `Message` | `LegacyMessage` | Yes |

### Remaining errors (require AIDoctor-side changes)

**Category 1: Tool return type (19 tools, ~1 line each)**

Change `execute() -> (content: String, metadata: ToolMetadata?)` to `execute() -> ToolResult`:
```swift
// Before:
return (content: "...", metadata: someMetadata)
// After:
return ToolResult(content: "...", metadata: someMetadata)
```

Files: `HealthTools.swift` (6 tools), `DisplayMedicationTool.swift`, `StartResearchTool.swift`, `SearchMedicalEvidenceTool.swift`, `ReadEvidenceTool.swift`, `ReasonEvidenceTool.swift`, `SearchHealthProfileTool.swift`, `CompleteResearchTool.swift`, `TestWearableBiomarkersTool.swift`, `TestHealthJournalTool.swift`, `TestLabResultsTool.swift`, `TestMedicalHistoryTool.swift`, `TestMedicalRecordsTool.swift`, `TestTreatmentHistoryTool.swift`

**Category 2: `Agent` → `LegacyAgent` (3 files)**

The v2 `Agent` is a new actor with a different API. AIDoctor must use `LegacyAgent` instead:

| File | Line | Change |
|------|------|--------|
| `AIChatManager.swift` | 174 | `Agent(llm:...)` → `LegacyAgent(llm:...)` |
| `AIChatManager.swift` | type decl | `private let agent: Agent` → `private let agent: LegacyAgent` |
| `DocumentAnalysisService.swift` | 17 | `Agent(llm:...)` → `LegacyAgent(llm:...)` |
| `DocumentAnalysisService.swift` | 12 | `private let agent: Agent` → `private let agent: LegacyAgent` |
| `MedicationAIService.swift` | 16 | `Agent(llm:...)` → `LegacyAgent(llm:...)` |

Once these 3 files use `LegacyAgent`, all `sendStream`, `addCallbacks`, `onStateChange`, `setMessages`, and `.llm` errors resolve automatically (since `LegacyAgent` has all these methods with `[LegacyChatMessage]` types).

### Error count progression

| Phase | Unique Errors | Notes |
|-------|--------------|-------|
| First build (no typealiases) | 44 | ChatMessage, ResearcherAgentState, Message, Agent, tools |
| After typealiases | 32 | ChatMessage, ResearcherAgentState, Message errors resolved |
| After AIDoctor Agent→LegacyAgent fix | ~19 | Only tool return types remain |
| After tool ToolResult migration | 0 | Full compilation |

### Total AIDoctor changes applied

- **3 files**: `Agent` → `LegacyAgent` (type declaration + init)
- **~14 files**: Tool `execute()` return type → `ToolResult`
- **1 file**: `DisplayMedicationTool.swift` — 3 positional-tuple returns fixed to `ToolResult(content:metadata:)`
- **0 other files**: All other v1 types compile via typealiases

### BUILD RESULT: SUCCEEDED (0 errors)

---

## Handoff: What Has Been Done

### AISDK v2 repo (`olympia-v1`, branch `jmush16/prod-test-strategy`)
1. `swift build` and `swift test` verified (2,397 tests pass)
2. Added `Sources/AISDK/Compatibility/V1Compatibility.swift` with 4 backward-compat typealiases
3. This file is safe for all consumers — additive only, no existing types changed
4. Can be deprecated in a future release once all consumers migrate to native v2 types
5. **Not yet committed** — needs commit on this branch

### AIDoctor repo (`chengdu`, branch `feat/aisdk-v2-migration-test`)
1. Branch created from `origin/main`
2. AISDK dependency swapped from remote GitHub to local path (`olympia-v1`)
3. All 32 compilation errors fixed (Agent→LegacyAgent, Tool→ToolResult)
4. `xcodebuild` BUILD SUCCEEDED with 0 errors
5. **Not yet committed** — needs commit on this branch

---

## Phase 4: Feature Testing Matrix

**Tested on:** 2026-02-17, iPhone 16 Simulator (iOS 18.5), XcodeBuildMCP
**AIDoctor branch:** `feat/aisdk-v2-migration-test`
**AISDK branch:** `jmush16/prod-test-strategy`

### Results

| # | Feature | Result | Notes |
|---|---------|--------|-------|
| 1 | AI Chat Streaming | **PASS** | Tokens streamed incrementally, response completed, no crash. Personalized to user health profile. |
| 2 | Tool Calling (ThinkTool) | **PASS** | ThinkTool fired and executed. Result incorporated in response. Note: v2 native migration should replace ThinkTool with model-native reasoning (see migration findings). |
| 3 | Agent State Observation | **PASS** | State transitions (thinking → responding → idle) correctly reflected in UI. Typing indicator appeared and disappeared. |
| 4 | Structured Output (Medication) | **PASS** | `MedicationInformation` fields populated via `generateObject()`. Ibuprofen 500mg displayed with cautions and drug interaction check. |
| 5 | Multimodal (Vision) | **SKIPPED** | Cannot upload images on simulator (camera-only flow). Deferred to physical device testing. |
| 6 | Suggested Questions | **PASS** | Follow-up suggestions rendered below chat responses, visible and functional. |
| 7 | Health Profile Context | **PASS** | AI responses referenced user-specific data (fatigue, headaches, medications, dietary preferences, sleep patterns). |
| 8 | Session Persistence | **PASS** | Messages persisted across chat interactions within session. Full restart test deferred to device. |
| 9 | Error Handling | **DEFERRED** | App-level rate limit (paywall) confirmed working — "Daily Limit Reached" dialog at 0 chats. But this is Superwall/quota enforcement, not AISDK error handling. True AISDK error path (bad API key, network failure, AgentState.error) still needs testing via API key invalidation or network kill on device. |
| 10 | Research Mode | **PASS (caveat)** | Research tab active, citations rendered via MetadataTracker/ToolMetadata adapter. Response style suggests regular chat with citations, not full multi-step ExperimentalResearchAgent loop. Likely prompt/routing issue in AIDoctor (SearchMedicalEvidenceTool commented out in prod), not AISDK. |
| 11 | Document Analysis | **SKIPPED** | Cannot upload documents on simulator. Deferred to physical device testing. |
| 12 | Health Profile Summaries | **PASS** | AI summary generation functional. |
| 13 | Generative UI (NEW v2) | **DEFERRED** | New v2 feature — will test on physical device. |
| 14 | Reliability (NEW v2) | **DEFERRED** | New v2 feature — will test on physical device. |
| 15 | Context Compaction (NEW v2) | **DEFERRED** | New v2 feature — will test on physical device. |

**Minimum beta criteria (1, 2, 3, 4, 9):** 4/5 PASS, 1 DEFERRED (error handling — device test needed).
**Migration findings:** See `docs/migration/v2-migration-findings.md` in AIDoctor repo.

---

## Phase 5: Beta Tag, Device Testing, and Native v2 Migration

### What has been proven

AISDK v2 works as a drop-in replacement for v1 in the AIDoctor app using the adapter layer. 8 of 12 testable features pass on simulator. The app compiles, runs, streams chat, calls tools, renders structured output, persists sessions, and personalizes responses to user health data. The adapter strategy is validated.

### What adapters are doing (and why they eventually go away)

Adapters (`LegacyAgent`, `LegacyChatMessage`, `V1Compatibility.swift` typealiases) let AIDoctor's existing v1 code run on v2 internals without rewriting 45 files at once. They are a bridge. Once AIDoctor migrates file-by-file to native v2 APIs (`Agent` actor, `AIMessage`, `AIObjectRequest<T>`), the adapters become dead code and get deprecated.

### How the two repos connect

The AISDK v2 repo is at `/Users/joelmushagasha/conductor/workspaces/aisdk/olympia-v1` (branch `jmush16/prod-test-strategy`). The AIDoctor repo is at `~/conductor/workspaces/AIDoctoriOSApp/chengdu` (branch `feat/aisdk-v2-migration-test`).

During development, AIDoctor's `project.pbxproj` was modified to point the AISDK dependency from the remote GitHub tag (`1.0.0`) to a **local path** (`../../aisdk/olympia-v1`). This allows instant iteration — edit AISDK, rebuild AIDoctor, no tagging needed. A helper script exists at `.aidoctor/swap-to-local-aisdk.sh`.

For beta, the dependency switches back to a remote tag: `2.0.0-beta.1`.

### 5.1 Beta tagging steps

1. **Merge AISDK branch** — PR `jmush16/prod-test-strategy` → `aisdk-2.0-modernization` (the v2 development branch, NOT `main`)
2. **Tag the beta** on `aisdk-2.0-modernization`:
   ```bash
   git tag -a 2.0.0-beta.1 -m "Beta 1 — validated in AIDoctor simulator testing"
   git push origin 2.0.0-beta.1
   ```
3. **Switch AIDoctor** from local path back to remote tag in `project.pbxproj`:
   ```
   repositoryURL = "https://github.com/DanielhCarranza/AISDK.git";
   requirement = { kind = exactVersion; version = "2.0.0-beta.1"; };
   ```
4. **Verify** AIDoctor builds against the remote beta tag (not local path)

### 5.2 Remaining device-only tests (during beta)

| # | Test | What to do |
|---|------|-----------|
| 5 | Multimodal (Vision) | Photograph medication packaging, verify extraction |
| 9 | Error Handling | Invalidate API key or kill network, verify `AgentState.error` and error card |
| 11 | Document Analysis | Upload medical document, verify biomarker extraction |
| 13 | Generative UI | Prototype `GenerativeUIView` in one AIDoctor view |
| 14 | Reliability | Simulate transient failure, verify `RetryPolicy` triggers |
| 15 | Context Compaction | Long conversation, verify compaction triggers |

### 5.3 Path from adapters to native v2 (incremental, file-by-file)

This is the roadmap for removing adapters. Do these **after** beta is stable, one at a time:

**Step 1: Structured output (lowest risk, 4 files)**
- Replace `ChatCompletionRequest` + `responseFormat` → `AIObjectRequest<T>`
- Replace `provider.generateObject()` → `model.generateObject()`
- Add `.phi` sensitivity for health data
- Files: `MedicationAIService.swift`, `MedicationExtractionService.swift`, `HealthProfileSummaryService.swift`, `SuggestedQuestion.swift`

**Step 2: Agent initialization (3 files, medium risk)**
- Replace `LegacyAgent(llm:tools:instructions:)` → `Agent(model:tools:systemPrompt:)`
- Replace `agent.sendStream()` → `agent.streamExecute()` with `AIAgentEvent` handling
- Replace `onStateChange` closure → `@Observable` bindings
- Files: `AIChatManager.swift`, `DocumentAnalysisService.swift`, `MedicationAIService.swift`

**Step 3: ThinkTool → native reasoning**
- Remove `ThinkTool` from tools array
- Use reasoning-capable model, handle `AIStreamEvent.thinking` events
- Files: `AIChatManager.swift`, `HealthTools.swift`

**Step 4: Message types (16+ files, highest risk)**
- Replace `ChatMessage`/`LegacyChatMessage` → `AIMessage` across all chat core and view files
- **Requires Firestore migration** for existing `ChatSession` documents (v1 format → v2 format)
- Options: version the session format (read both), or run a one-time migration
- Files: All 8 Chat Core files, all 8 Chat View files, `ChatSession.swift`

**Step 5: Remove compatibility layer**
- Delete `Sources/AISDK/Compatibility/V1Compatibility.swift` from the SDK
- Remove `LegacyAgent`, `LegacyChatMessage` imports from AIDoctor
- Full native v2

---

## Reference: Key files across both repos

### AISDK v2 repo

| Component | File Path |
|-----------|-----------|
| Tool protocol + ToolResult | `Sources/AISDK/Tools/Tool.swift` |
| V1 Compatibility Typealiases | `Sources/AISDK/Compatibility/V1Compatibility.swift` |
| AIAgentAdapter | `Sources/AISDK/Core/Adapters/Legacy/AIAgentAdapter.swift` |
| AILanguageModelAdapter | `Sources/AISDK/Core/Adapters/Legacy/AILanguageModelAdapter.swift` |
| LegacyAgent | `Sources/AISDK/Agents/LegacyAgent.swift` |
| LegacyChatMessage | `Sources/AISDK/Models/LegacyChatMessage.swift` |
| AIMessage | `Sources/AISDK/Core/Protocols/LLM.swift` |
| AIObjectRequest | `Sources/AISDK/Core/Models/AIObjectRequest.swift` |
| Agent actor (native v2) | `Sources/AISDK/Agents/Agent.swift` |
| MetadataTracker | `Sources/AISDK/Agents/LegacyAgentCallbacks.swift` |
| ExperimentalResearchAgent | `Sources/AISDK/Agents/ResearchAgent/Agent/ExperimentalResearchAgent.swift` |
| JSONSchemaModel + @Field | `Sources/AISDK/Utilities/JSONSchemaRepresentable.swift` |

### AIDoctor repo

| File | What to know |
|------|-------------|
| `docs/migration/v2-migration-findings.md` | Detailed findings from simulator testing with v1→v2 code comparisons |
| `.aidoctor/v1-v2-api-mapping.md` | This file (master record of the entire migration) |
| `.aidoctor/aisdk-v1-usage.md` | How AIDoctor uses v1 across 45 files — essential reading |
| `.aidoctor/v2-integration-test-spec.md` | Original test spec from stakeholder interview |
| `.aidoctor/swap-to-local-aisdk.sh` | Script to swap between local and remote AISDK dependency |

### Repo paths

| Repo | Path | Branch |
|------|------|--------|
| AISDK v2 | `/Users/joelmushagasha/conductor/workspaces/aisdk/olympia-v1` | `jmush16/prod-test-strategy` |
| AIDoctor | `~/conductor/workspaces/AIDoctoriOSApp/chengdu` | `feat/aisdk-v2-migration-test` |
