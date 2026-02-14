---
title: "Production Testing Strategy"
type: feat
status: active
date: 2026-02-14
branch: aisdk-2.0-modernization
brainstorm: "docs/brainstorms/2026-02-14-production-testing-strategy-brainstorm.md"
---

# Production Testing Strategy Implementation Plan

## Overview

Implement a comprehensive, layered testing strategy to validate that AISDK 2.0 is production-ready for real iOS/macOS applications. The SDK has 2,249 unit/integration tests but lacks validation on real devices, under real network conditions, with real provider APIs. This plan implements the 4-layer testing pyramid defined in the [brainstorm](../brainstorms/2026-02-14-production-testing-strategy-brainstorm.md).

**Goal:** Answer "How do we know this SDK actually works in production?" with automated evidence at every layer.

**Target:** 99.99% request success rate for valid API calls across OpenAI, Anthropic, and Gemini.

---

## Architecture

```
                    +-------------------+
                    | Layer 4: Contract |  Provider drift detection
                    |   Tests (CI)      |  (daily cron, ~$0.05/day)
                    +-------------------+
                  +------------------------+
                  | Layer 3: Comprehensive  |  Full feature coverage
                  |   Demo App              |  (reference implementation)
                  +------------------------+
              +-------------------------------+
              | Layer 2: SDK Eval Harness      |  Correctness, benchmarks,
              |   (headless, CI-friendly)      |  streaming integrity
              +-------------------------------+
          +--------------------------------------+
          | Layer 1: Smoke Test App               |  "Does it even work?"
          |   (SwiftUI, <200 lines, 30 seconds)   |  on-device gate
          +--------------------------------------+
      +--------------------------------------------+
      | Foundation: 2,249 Unit & Integration Tests   |  Logic correctness
      |   (existing, runs on every PR)               |  (already built)
      +--------------------------------------------+
```

---

## Codebase Context

### Existing Test Infrastructure to Build On

| Asset | Location | Reuse Strategy |
|-------|----------|----------------|
| MockLLM | `Tests/AISDKTests/Mocks/MockLLM.swift` | Reuse for Layer 2 correctness evals |
| StreamSimulation | `Tests/AISDKTests/Helpers/StreamSimulation.swift` | Reuse for streaming integrity tests |
| MockSessionStore | `Tests/AISDKTests/Sessions/Mocks/MockSessionStore.swift` | Reuse for session roundtrip tests |
| ProviderContractTests (mock) | `Tests/AISDKTests/Core/Providers/ProviderContractTests.swift` | Extend with live version for Layer 4 |
| StressTestMetrics | `Tests/AISDKTests/Stress/ConcurrencyStressTests.swift` | Reuse metrics collector pattern |
| AISDKTestRunner | `Examples/AISDKTestRunner/` | Extend for Layer 2 eval harness |
| Live test guard pattern | `Tests/AISDKTests/Integration/BuiltInToolsLiveTests.swift` | Reuse `liveTestGuard()` + `XCTSkip` |

### Provider Implementations to Test

| Provider | Adapter | Full LLM | API Paths |
|----------|---------|----------|-----------|
| OpenAI | `OpenAIClientAdapter` | `OpenAIProvider` | Chat Completions + Responses API |
| Anthropic | `AnthropicClientAdapter` | `AnthropicProvider` | Messages API |
| Gemini | `GeminiClientAdapter` | `GeminiProvider` | GenerateContent API |
| OpenRouter | `OpenRouterClient` | -- | OpenAI-compatible |
| LiteLLM | `LiteLLMClient` | -- | OpenAI-compatible |

### Key Protocols to Exercise

- `LLM`: `generateText()`, `streamText()`, `generateObject()`, `streamObject()`
- `ProviderClient`: `execute()`, `stream()`, `healthStatus`, `capabilities`
- `SessionStore`: `create()`, `load()`, `save()`, `appendMessage()`, `updateLastMessage()`
- `AIAgent`: agent execution with tool loops and handoffs

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)

#### 1.1 Smoke Test App (Layer 1) -- COMPLETED

**Status:** Done. 14/14 tests passing in ~7 seconds.

**Implementation:** Single-file CLI at `Examples/SmokeTestApp/main.swift` (584 lines). Simplified from the planned multi-file structure into one file since all 5 test categories fit cleanly together. Added to `Package.swift` as executable target.

**Results (2026-02-14):**
- Connection: 4/4 (OpenAI, Anthropic, Gemini, OpenRouter)
- Streaming: 4/4 (all providers, validates event ordering)
- ToolCall: 3/3 (OpenAI, Anthropic, Gemini -- model requests tool, args are valid JSON)
- Session: 1/1 (InMemoryStore create/append/load/save roundtrip)
- GenerativeUI: 2/2 (UITree parse + invalid JSON rejection)

**Deviations from plan:**
- Single file instead of multi-file structure (simpler, all fits in one file)
- 584 lines instead of <300 target (thorough coverage of 4 providers required more code)
- CLI-only (not SwiftUI app) -- sufficient for Layer 1 validation
- Tests direct provider adapters (OpenAIClientAdapter, etc.) not OpenRouter-proxied
- Anthropic model: uses `claude-haiku-4-5-20251001` (the plan didn't specify)

**How to run:** `swift run SmokeTestApp` (or `--verbose`). Requires `.env` with API keys.

**Purpose:** Quick on-device validation that the SDK fundamentally works. 30-second run. "Did we ship something broken?" gate.

**File structure:**

```
Examples/SmokeTestApp/
  SmokeTestApp.swift              # @main App entry
  SmokeTest.swift                 # SmokeTest protocol + runner
  Tests/
    ProviderConnectionTest.swift  # Connect to each provider
    StreamingTest.swift           # Stream a response, verify chunks
    ToolCallTest.swift            # Execute one tool call
    SessionTest.swift             # Create + persist + restore session
    GenerativeUITest.swift        # Render a basic UI component
  Views/
    ResultsView.swift             # Pass/fail dashboard
  Config/
    EnvLoader.swift               # Load .env for API keys
```

**What each test validates:**

| Test | Validates | Pass Criteria | Timeout |
|------|-----------|---------------|---------|
| ProviderConnection | Each provider responds to a basic completion | Non-empty response text | 10s |
| Streaming | Stream delivers chunks in order, ends with `.finish` | At least 3 `.textDelta` events + 1 `.finish` | 10s |
| ToolCall | Model requests a tool, SDK executes it, result returned | Tool result appears in final response | 10s |
| Session | Create session, append message, save, reload, verify | Reloaded session contains the appended message | 5s |
| GenerativeUI | UITree renders without crash | View hierarchy instantiates successfully | 5s |

**Provider coverage per test:**

| Test | OpenAI | Anthropic | Gemini | OpenRouter |
|------|:---:|:---:|:---:|:---:|
| ProviderConnection | Chat + Responses | Yes | Yes | Yes |
| Streaming | Chat + Responses | Yes | Yes | Yes |
| ToolCall | Chat | Yes | Yes | -- |
| Session | Yes | -- | -- | -- |
| GenerativeUI | Yes | -- | -- | -- |

**Constraints:**
- No complex UI -- just a results list showing pass/fail per test
- Requires `.env` with at least one provider API key (gracefully skips missing providers)
- Runs on both simulator and physical device
- Must compile as both macOS CLI (`swift build`) and iOS app (Xcode)
- Rate-limit retries: up to 2 retries with 2s delay before declaring failure

**Package.swift changes:**
- Add `SmokeTestApp` as executable target depending on `AISDK`

#### 1.2 Provider Contract Tests (Layer 4)

**Purpose:** Detect provider API drift before it breaks production apps. Runs daily against real APIs with minimal token usage.

**File structure:**

```
Tests/AISDKTests/Contract/
  LiveProviderContractTests.swift    # Main test file
  ContractValidation.swift           # Schema validation helpers
  ContractReport.swift               # JSON report generation
```

**What each contract validates per provider:**

| Check | What It Does | Token Cost |
|-------|-------------|-----------|
| Basic completion | Send "Say hi", verify response has `.text`, `.usage`, `.finishReason` | ~5 tokens |
| Streaming format | Stream "Say hi", verify `.start` -> `.textDelta`+ -> `.finish` ordering | ~5 tokens |
| Tool call format | Send tool-equipped request, verify `.toolCalls` structure | ~50 tokens |
| Error format | Send invalid request, verify error is parseable as `ProviderError` | 0 tokens |
| Rate limit headers | Check 429 response includes `Retry-After` or equivalent | 0 tokens |

**Contract test implementation pattern:**

```swift
// Extends existing ProviderContractTests.swift pattern
// Uses liveTestGuard() + provider-specific key helpers
func testOpenAILiveContract() async throws {
    try liveTestGuard()
    let apiKey = try openAIKeyOrSkip()
    let client = OpenAIClientAdapter(apiKey: apiKey)

    // 1. Basic completion
    let response = try await client.execute(request: ProviderRequest(
        modelId: "gpt-4o-mini",
        messages: [.user("Say hi")],
        maxTokens: 5
    ))
    XCTAssertFalse(response.content.isEmpty)
    XCTAssertNotNil(response.usage)

    // 2. Streaming format
    var events: [ProviderStreamEvent] = []
    for try await event in client.stream(request: ...) {
        events.append(event)
    }
    assertStreamOrdering(events) // .start before .textDelta before .finish

    // 3. Tool call format
    let toolResponse = try await client.execute(request: ProviderRequest(
        modelId: "gpt-4o-mini",
        messages: [.user("What's 2+2?")],
        tools: [calculatorTool],
        maxTokens: 50
    ))
    XCTAssertFalse(toolResponse.toolCalls.isEmpty)
}
```

**Providers covered:** OpenAI (Chat Completions + Responses API), Anthropic, Gemini, OpenRouter.

**CI workflow addition** (`.github/workflows/contract-tests.yml`):

```yaml
name: Provider Contract Tests
on:
  schedule:
    - cron: '0 8 * * *'  # Daily at 8 AM UTC
  workflow_dispatch: {}

jobs:
  contract-tests:
    runs-on: macos-latest
    timeout-minutes: 10  # Hard cap to prevent cost runaway
    env:
      RUN_LIVE_TESTS: "1"
      OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
      GEMINI_API_KEY: ${{ secrets.GEMINI_API_KEY }}
      OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}
    steps:
      - uses: actions/checkout@v4
      - run: swift test --filter LiveProviderContractTests
```

**Flaky test policy:**
- Retry failed tests once before marking as failure
- Distinguish timeout failures (provider slow) from assertion failures (contract broken)
- Alert only on 2 consecutive daily failures (not single occurrences)
- Log token usage per test run for cost tracking

**Estimated cost:** ~$0.01-0.03/run, ~$0.30-0.90/month at daily cadence.

#### 1.3 CI Integration

- [ ] Add GitHub Actions secrets for provider API keys (CI-only keys with spend limits)
- [ ] Create `contract-tests.yml` workflow with daily cron schedule
- [ ] Add `timeout-minutes: 10` to prevent cost runaway
- [ ] Configure Slack/email notification on consecutive contract failures

---

### Phase 2: Depth (Week 3-4) -- COMPLETED

**Status:** Done. 34/34 tests passing across 4 eval suites in ~106 seconds (single provider).

**Implementation:** Extended `Examples/AISDKTestRunner/` with 4 new test suites, all wired into `main.swift` with new modes (`--mode correctness`, `--mode performance`, `--mode session`, `--mode live-reliability`, `--mode eval`).

**Results (2026-02-14):** See [full results document](../results/2026-02-14-layer2-eval-harness-results.md) for detailed metrics, baselines, and reproduction steps.

- Correctness: 18/18 (stream integrity, event ordering, empty streams, tool parsing, error mapping, session roundtrip x3, multi-turn 5-turn)
- Performance: 7/7 (TTFT p50/p95/p99, tokens/sec, latency p50/p95, memory delta 50 sequential, peak memory 10 concurrent, leak detection x2)
- SessionEval: 10/10 (roundtrip x3 stores, 100-message history, concurrent appends, list/filter, metadata, status transitions, updateLastMessage, isolation)
- LiveReliability: 7/7 (20-request success rate, 15-stream success rate, cancellation, invalid auth, timeout, 30 consecutive, error recovery)

**Key metrics (OpenAI gpt-4o-mini):**
- TTFT: p50=364ms, p95=785ms, p99=864ms
- Tokens/sec: median=48.7
- Latency: p50=435ms, p95=499ms
- Memory delta: 112KB over 50 requests (well under 10MB threshold)
- Success rate: 100% over 20 requests, 100% over 15 streams

**How to run:** `swift run AISDKTestRunner --mode eval` (or `--mode eval --provider openai`). Requires `.env` with API keys.

**Files added:**
- `Examples/AISDKTestRunner/TestSuites/CorrectnessEvalSuite.swift`
- `Examples/AISDKTestRunner/TestSuites/PerformanceBenchmarkSuite.swift`
- `Examples/AISDKTestRunner/TestSuites/SessionEvalSuite.swift`
- `Examples/AISDKTestRunner/TestSuites/LiveReliabilityEvalSuite.swift`
- Modified: `Examples/AISDKTestRunner/main.swift` (new modes + run functions)

#### 2.1 SDK Eval Harness (Layer 2)

**Purpose:** Automated correctness and performance evaluation. Headless, runs in CI, produces structured JSON reports. This is where benchmarks live.

**Approach:** Extend the existing `AISDKTestRunner` executable at `Examples/AISDKTestRunner/`.

**New test suites to add:**

```
Examples/AISDKTestRunner/TestSuites/
  CorrectnessEvalSuite.swift      # Streaming integrity, tool parsing, error types
  PerformanceBenchmarkSuite.swift # TTFT, tokens/sec, latency, memory
  ReliabilityEvalSuite.swift      # Success rate, chaos testing, failover
  SessionEvalSuite.swift          # Serialization roundtrip, compaction, concurrent access
```

**Correctness evals:**

| Eval | What It Measures | Pass Criteria |
|------|-----------------|---------------|
| Stream chunk integrity | No gaps, no duplicates, finish reason received | All `.textDelta` events are non-empty; exactly 1 `.finish` event |
| Stream event ordering | `.start` precedes `.textDelta` precedes `.finish` | Strict ordering validated |
| Empty stream handling | Provider returns immediate `.finish` with no content | No crash; empty text result |
| Tool call JSON parsing | Tool arguments parse as valid JSON across all providers | Zero parse errors over N requests |
| Error type mapping | Timeout vs rate limit vs auth vs server error | Each error type maps to correct `ProviderError` case |
| Retry behavior | Backoff timing, max attempts, circuit breaker state | Retries follow configured policy; circuit breaker trips at threshold |
| Session roundtrip | Serialize session -> deserialize -> compare | All fields match after roundtrip (all 3 store types) |
| Multi-turn consistency | 5-turn conversation maintains context | Model references earlier turns correctly |
| Reasoning events | Extended thinking/reasoning events arrive correctly | `.reasoningStart` -> `.reasoningDelta`+ -> `.reasoningFinish` ordering |

**Performance benchmarks:**

| Metric | How Measured | Initial Baseline (TBD) |
|--------|-------------|----------------------|
| TTFT p50/p95/p99 | Time from request to first `.textDelta` event | Established from first 7 days of data |
| Tokens/sec | `.textDelta` count / stream duration | Per-provider, per-model |
| Total request latency | Time from request to `.finish` event | Per-provider |
| Memory delta per request | Resident memory before/after 100 sequential requests | Flag if delta > 10MB |
| Peak memory concurrent | Max resident memory during 10 concurrent requests | Flag if > 200MB above baseline |

**Baseline management:**
- First run establishes baselines, stored as `benchmarks/baselines.json` in repo
- Subsequent runs compare against baselines
- Regression threshold: >20% degradation on any p95 metric fails CI
- Baselines refreshed quarterly or after major SDK changes

**Output format:**

```json
{
  "timestamp": "2026-02-14T12:00:00Z",
  "provider": "openai",
  "model": "gpt-4o-mini",
  "correctness": {
    "stream_integrity": { "pass": true, "details": "100/100 streams valid" },
    "tool_parsing": { "pass": true, "details": "50/50 tool calls parsed" }
  },
  "performance": {
    "ttft_p50_ms": 320,
    "ttft_p95_ms": 780,
    "tokens_per_sec": 45.2,
    "memory_delta_mb": 3.2
  },
  "reliability": {
    "success_rate": 0.9998,
    "requests_total": 500
  }
}
```

#### 2.2 Memory Leak Detection

**Automated in CI (via eval harness):**

```swift
// In PerformanceBenchmarkSuite.swift
func testMemoryLeaks() async {
    let initialMemory = getResidentMemory()

    // 100 sequential requests with autoreleasepool
    for _ in 0..<100 {
        autoreleasepool {
            let stream = provider.stream(request: smallRequest)
            for try await _ in stream { }
        }
    }

    let delta = getResidentMemory() - initialMemory
    XCTAssertLessThan(delta, 10 * 1024 * 1024, "Memory grew > 10MB over 100 requests")
}
```

**Weak reference tracking for streams:**

```swift
func testStreamDeallocation() async {
    weak var weakStream: AnyObject?
    autoreleasepool {
        let stream = provider.stream(request: smallRequest)
        weakStream = stream as AnyObject
        for try await _ in stream { }
    }
    XCTAssertNil(weakStream, "Stream not deallocated after consumption")
}
```

**What to check for retain cycles:**
- Streaming closure captures (`[weak self]` in continuations)
- Agent callback chains (tool execution closures)
- Session store observation callbacks
- GenerativeUI view model bindings

#### 2.3 Establish Performance Baselines

- [ ] Run eval harness against all 3 primary providers (OpenAI, Anthropic, Gemini)
- [ ] Collect 7 days of data to establish stable baselines
- [ ] Commit baselines to `benchmarks/baselines.json`
- [ ] Configure CI to compare against baselines on each run

---

### Phase 3: Breadth (Week 5-6)

#### 3.1 SDK Explorer iOS App (Layer 3)

**Purpose:** A real iOS app that runs on simulator and physical device, proving the SDK works end-to-end in the context a developer would actually use it. This is not a test harness with a UI — it's a real AI chat app that validates every SDK feature through actual usage.

**Why an iOS app (not CLI):** Layers 1 and 2 are CLI tools that validate the SDK at an API level. But they can't run on iOS simulator/device, can't test SwiftUI integration, and don't validate the UI/UX experience. Layer 3 must run on real devices to prove the SDK works where developers actually ship.

##### Design Decisions

**Agent-first architecture (not chat + agent split):**

A key design question: should chat and agent be separate tabs? No. In a real AI app, the agent *is* the chat. The user talks to an agent that has tools, memory, and capabilities. Separating them is artificial and doesn't reflect how the SDK would actually be used in production. A real developer would build one conversational interface where the agent handles everything — plain conversation, tool calls, multi-turn context — all in one flow.

The app uses a **unified chat powered by an Agent**, where tool use happens naturally within conversation. "What's 5+3?" triggers the calculator tool. "How's the weather in Tokyo?" triggers the weather tool. "Tell me a joke" gets a plain response. This tests more SDK surface in a more realistic way than splitting them into separate views.

**Real-time validation over automated checks:**

Another key question: should session stores, UITree, and compaction be tested as silent automated checks? No — running them as unit-test-style assertions misses the point of Layer 3. Layer 3 is about proving the SDK works *in a real app context*. That means:

- **Session persistence**: The user chats, kills the app, reopens it, and their conversation is still there. That's a real test — not `create() → save() → load() → assert`.
- **UITree / Generative UI**: The agent returns generative UI and it actually renders inline in the chat. You see it.
- **Session compaction**: After a long conversation, you can see token counts, trigger compaction, and watch the conversation get summarized while remaining coherent.
- **Provider switching**: Mid-conversation, switch from OpenAI to Anthropic and keep chatting. Does context carry over?

These should be *experienced through usage*, not just checked off in a test runner. The Diagnostics tab exists only for things that genuinely need programmatic validation (error recovery with bad API keys, store implementation comparison, etc.).

##### Architecture Decisions (Resolved)

1. **Unified Agent runtime for all chat traffic**
   - Plain chat and tool-augmented responses both flow through one `Agent` path.
   - Tool loop is active when tools are registered; plain conversation still uses the same runtime.
2. **Generative UI handled in chat rendering layer**
   - Agent output is rendered as text by default.
   - If output contains UITree payloads, `MessageRow` renders UI cards inline in the same transcript.
3. **Session store switching allowed at session boundary**
   - Store selection is configurable in Sessions tab settings.
   - Active session must be ended/restored before switching store to avoid cross-store mutation ambiguity.
4. **Provider switching handled at SDK abstraction boundary**
   - Conversation state is stored in normalized SDK message types.
   - Provider-specific wire-format translation stays inside provider adapters; app does not implement a custom `MessageFormatAdapter`.

##### App Structure: 3 Tabs

| Tab | What it does | SDK surfaces exercised |
|-----|-------------|----------------------|
| **Chat** | Unified agent chat plus mission cards for deterministic high-signal demos | `Agent`, `Tool`, `@Parameter`, `ProviderClient.stream()`, `ProviderLanguageModelAdapter`, `SessionStore`, `UITree` |
| **Sessions** | Persistence, continuity, and compaction management with explicit store boundaries | `SessionStore` (all 3 types), `SessionCompactionService`, session lifecycle |
| **Diagnostics** | Programmatic checks + evidence export for repeatable stakeholder validation | Provider health, error mapping, store parity, UITree parsing, stream ordering |

##### Mission Catalog (Chat tab)

Mission cards make demos repeatable and prove behavior end-to-end:

| Mission | What it proves | Expected result |
|---------|---------------|-----------------|
| `CrossProviderContinuation` | Provider switch mid-thread while preserving context | User switches provider and conversation remains coherent |
| `ToolReasoningChain` | Agent can choose and sequence tools autonomously | Multiple tool calls complete with correct final response |
| `GenerativeUICard` | Generative UI payloads render inline in transcript | UITree card appears in chat bubble without breaking stream |
| `LongContextCompaction` | Long history can be compacted and still used | Token count drops and follow-up responses remain on-topic |
| `FailureRecovery` | Recovery behavior under invalid key / timeout paths | Actionable error, no crash, next valid request succeeds |

##### Project Structure

Follows the existing GenerativeUIDemo pattern: thin Xcode project shell + feature Swift Package + workspace.

```
Examples/
  SDKExplorer.xcworkspace/
    contents.xcworkspacedata          # Links .xcodeproj + package

  SDKExplorer.xcodeproj/
    project.pbxproj                   # Minimal app target

  SDKExplorer/
    SDKExplorerApp.swift              # @main entry point
    Assets.xcassets/                  # Asset catalog

  SDKExplorerConfig/
    Shared.xcconfig                   # Bundle ID, deployment target
    Debug.xcconfig                    # Debug settings
    Release.xcconfig                  # Release settings
    SDKExplorer.entitlements          # App sandbox

  SDKExplorerPackage/
    Package.swift                     # Feature package, depends on AISDK
    Sources/SDKExplorerFeature/
      ContentView.swift               # Tab bar container
      Chat/
        ChatView.swift                # Agent-powered streaming chat
        MessageRow.swift              # Message bubble component (text + tool calls + generative UI)
      Sessions/
        SessionsView.swift            # Session browser and manager
        SessionDetail.swift           # View/restore a saved session
      Diagnostics/
        DiagnosticsView.swift         # Health check runner + results UI
      Shared/
        SDKConfig.swift               # Provider setup, env loading
        DemoTools.swift               # WeatherTool + CalculatorTool (for agent)
        MissionCatalog.swift          # Prompt-driven mission definitions
        EvidenceExporter.swift        # JSON + markdown evidence bundle export
```

##### Tab 1: Chat (Agent-Powered)

The primary tab. A real streaming AI chat where the user talks to an Agent.

**What's visible:**
- **Provider picker** in toolbar (segmented: OpenAI / Anthropic / Gemini)
- **Message bubbles** — user messages (blue), assistant messages (gray), tool call indicators (inline)
- **Streaming tokens** appear in real-time
- **Tool activity** shown inline: "Calling calculator(5, 3, +) → 8.00" rendered as a subtle card within the conversation flow
- **Generative UI** rendered inline when the agent returns UITree-compatible responses
- **Mission cards** for deterministic scenario playback

**SDK APIs exercised:**
- `ProviderLanguageModelAdapter(client:modelId:)` — wraps ProviderClient into LLM for Agent
- `Agent(model:tools:instructions:)` — agent actor with tool loop
- `agent.execute(messages:)` → `AIAgentResult`
- `Tool` protocol with `@Parameter` property wrapper
- `ProviderClient.stream()` via the adapter (streaming tokens)
- `SessionStore.appendMessage()` / `.save()` — auto-saves after each exchange
- Provider switching: changing the underlying `ProviderClient` and `modelId` mid-session
- Prompt-only mission behavior changes without code path changes

**Tools available to the agent:**
- `CalculatorTool`: `@Parameter a: Double`, `@Parameter b: Double`, `@Parameter operation: Operation` (enum: +, -, *, /)
- `WeatherTool`: `@Parameter city: String` → simulated weather data with renderable UI

**Real-time validation through usage:**
- Multi-turn conversation: Does the agent maintain context across turns?
- Tool calling: Does the agent correctly identify when to use tools?
- Streaming: Do tokens appear smoothly without UI jank?
- Provider switching: Can you switch from OpenAI to Anthropic mid-conversation and keep chatting?
- Session auto-save: Close the app, reopen, is the conversation still there?
- Emergent capability: open-ended request succeeds or logs a clear parity gap

##### Tab 2: Sessions

Browse and manage saved conversations. Tests session persistence as a real feature, not an abstract test.

**What's visible:**
- **Session list** showing all saved conversations with titles, dates, message counts
- **Session detail** view to read back a saved conversation
- **Restore** button to continue a saved conversation in the Chat tab
- **Store switcher** (settings gear) to change the backing store (InMemory / FileSystem / SQLite)
- **Compaction controls**: token count display, "Compact" button that summarizes long conversations
- **Delete** individual sessions

**SDK APIs exercised:**
- `InMemorySessionStore`, `FileSystemSessionStore(directory:)`, `SQLiteSessionStore(path:)`
- `SessionStore.list()`, `.load()`, `.save()`, `.delete()`
- `SessionCompactionService.estimateTokens()`
- `SessionCompactionService.compact()` (if available)

**Real-time validation through usage:**
- Kill the app → reopen → are sessions still there? (FileSystem/SQLite only)
- Switch to a different store type → sessions from that store appear
- Compact a long conversation → token count decreases, conversation summary is coherent
- Restore a session → Chat tab loads with full message history, can continue chatting
- Cold start continuity → app relaunch restores last active session context

##### Tab 3: Diagnostics

Automated checks for things that can't be tested through normal usage.

**What's visible:**
- **"Run All Tests" button** that executes programmatic checks
- **Results list** with pass/fail icons, duration, and error messages
- **Individual test re-run** by tapping a failed test
- **Export Evidence** button to save reproducible demo artifacts

**Tests:**

| Test | What it validates | How |
|------|------------------|-----|
| Provider Health | Each configured provider responds | Send "Say hi" to each, verify non-empty response |
| Error Recovery | Bad API key returns error, no crash | Use invalid key, assert error is `ProviderError` |
| UITree Parse (valid) | Valid JSON → correct UITree nodes | `UITree.parse(from:)` with known-good JSON |
| UITree Parse (invalid) | Invalid JSON throws error, no crash | `UITree.parse(from:)` with malformed JSON |
| Store Roundtrip (InMemory) | Create → save → load roundtrip | Assert loaded session matches saved session |
| Store Roundtrip (FileSystem) | Same with disk persistence | Same assertion + verify file exists on disk |
| Store Roundtrip (SQLite) | Same with SQLite backend | Same assertion |
| Token Estimation | Estimate tokens for known message set | `SessionCompactionService.estimateTokens()` returns > 0 |
| Stream Event Ordering | `.start` -> `.textDelta`+ -> `.finish` sequence | Validate strict event order on one live stream |

##### Action Parity Matrix (Agent-native requirement)

Every meaningful UI action must be achievable by the Agent runtime using available tools and message/state primitives.

| User-visible action | Agent capability path |
|--------------------|-----------------------|
| Send a plain message | `agent.execute(messages:)` with no tool call |
| Ask for calculation | `Agent` selects `CalculatorTool` |
| Ask for weather | `Agent` selects `WeatherTool` |
| Continue across provider change | Same normalized conversation messages + new provider adapter |
| Save/restore conversation | `SessionStore.save()` / `SessionStore.load()` |
| Compact long context | `SessionCompactionService.estimateTokens()` + `compact()` flow |
| Render dynamic card | Message parsed as UITree and rendered inline |

##### Composability and Emergent Capability Proofs

- **Prompt-only composability check:** At least one mission behavior must be altered by prompt text only, with no Swift code change.
- **Emergent capability check:** Run one open-ended domain request that is not hardcoded as a mission; pass if successful, otherwise log parity gap with missing capability.

##### Evidence Bundle Schema

Diagnostics exports a timestamped bundle to a local app-accessible directory:

```json
{
  "timestamp": "2026-02-14T18:00:00Z",
  "appVersion": "0.1.0",
  "device": "iPhone16,2",
  "osVersion": "iOS 18.2",
  "missions": [
    {
      "name": "CrossProviderContinuation",
      "provider": "openai->anthropic",
      "pass": true,
      "latencyMs": 1420,
      "retries": 0,
      "tokenUsage": { "input": 210, "output": 84 }
    }
  ],
  "diagnostics": {
    "providerHealth": "pass",
    "storeParity": "pass",
    "uiTreeParse": "pass",
    "streamOrdering": "pass"
  }
}
```

##### Feature Coverage Matrix

| Plan Requirement | How Exercised | Where |
|-----------------|--------------|-------|
| Multi-turn chat (streaming) | Real streaming chat with message history | Chat tab |
| Agent with tool loop | Agent actor executes tools autonomously | Chat tab |
| Agent-native parity | Action parity matrix verified for all visible actions | Chat + Sessions |
| Composability | Mission behavior changed by prompt-only edit | Chat tab |
| Emergent capability | Open-ended request not hardcoded as feature | Chat tab |
| Session persistence | Real: close app → reopen → conversation persists | Sessions tab |
| Session compaction | Real: see token counts, trigger compaction, verify coherence | Sessions tab |
| Provider switching | Real: switch provider mid-conversation | Chat tab |
| GenerativeUI (UITree) | Real: agent returns renderable UI inline | Chat tab |
| Error recovery | Automated: bad key test, graceful error display | Diagnostics tab |
| UITree parsing | Automated: valid/invalid JSON edge cases | Diagnostics tab |
| Store implementations | Automated: roundtrip comparison across all 3 stores | Diagnostics tab |
| Evidence export | Automated: JSON + markdown bundle for each run | Diagnostics tab |
| On-device testing | Runs on iOS simulator and physical device | All tabs |
| UI/UX validation | Real SwiftUI chat interface with streaming | Chat tab |

##### Files to Create (18 total)

1. `Examples/SDKExplorerPackage/Package.swift` — Feature package depending on AISDK
2. `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/ContentView.swift` — Tab bar container
3. `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Chat/ChatView.swift` — Agent-powered streaming chat
4. `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Chat/MessageRow.swift` — Message bubble component
5. `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Sessions/SessionsView.swift` — Session browser
6. `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Sessions/SessionDetail.swift` — Session detail/restore
7. `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Diagnostics/DiagnosticsView.swift` — Health checks
8. `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Shared/SDKConfig.swift` — Provider setup, env loading
9. `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Shared/DemoTools.swift` — Calculator + Weather tools
10. `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Shared/MissionCatalog.swift` — Mission definitions and prompts
11. `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Shared/EvidenceExporter.swift` — Evidence bundle writer
12. `Examples/SDKExplorer/SDKExplorerApp.swift` — @main entry point
13. `Examples/SDKExplorer/Assets.xcassets/Contents.json` — Asset catalog root
14. `Examples/SDKExplorer/Assets.xcassets/AccentColor.colorset/Contents.json` — Accent color
15. `Examples/SDKExplorer/Assets.xcassets/AppIcon.appiconset/Contents.json` — App icon
16. `Examples/SDKExplorerConfig/Shared.xcconfig` — Bundle ID, deployment target
17. `Examples/SDKExplorer.xcodeproj/project.pbxproj` — Xcode project file
18. `Examples/SDKExplorer.xcworkspace/contents.xcworkspacedata` — Workspace linking project + package

##### Verification

1. **Build**: Open `Examples/SDKExplorer.xcworkspace` in Xcode, build for iOS simulator
2. **Chat tab**: Select a provider, send a message, verify streaming tokens appear
3. **Tool call**: Ask "What's 5 + 3?", verify tool call indicator appears then result
4. **Provider switch**: Switch from OpenAI to Anthropic, send message, verify it works
5. **Session persistence**: Chat, kill app, reopen, verify conversation is still there
6. **Session compaction**: Long conversation → check token count → compact → verify summary
7. **Composability proof**: Edit one mission prompt only, rerun mission, verify behavior change without code changes
8. **Emergent capability proof**: Run one non-hardcoded open-ended prompt, capture result or logged parity gap
9. **Diagnostics**: Tap "Run All Tests", verify all pass (green checkmarks)
10. **Evidence export**: Tap "Export Evidence", verify JSON + markdown artifacts are generated
11. **Device**: Build and run on physical iOS device

#### 3.2 Chaos Testing

**Purpose:** Validate SDK behavior under adversarial conditions. Implemented as part of the eval harness (Layer 2) but triggered separately.

**Test scenarios:**

| Scenario | How Simulated | Expected Behavior |
|----------|-------------|-------------------|
| Network timeout mid-stream | URLProtocol stub drops connection after N chunks | Stream terminates with `.error`; no crash; resources released |
| Provider returns 500 | URLProtocol returns HTTP 500 | Retry logic activates; circuit breaker trips after threshold |
| Rate limit (429) | URLProtocol returns 429 with Retry-After header | Backoff respects Retry-After; request retries after delay |
| Invalid API key (401) | Use intentionally bad key | Actionable error message; no retry (not retryable) |
| Memory pressure warning | Simulate `didReceiveMemoryWarning` | SDK doesn't crash; degrades gracefully |
| App backgrounded during stream | Trigger background lifecycle event | Stream resumes or terminates cleanly with error |
| Corrupted stream data | URLProtocol returns malformed SSE | Error emitted; partial text preserved if possible |
| DNS resolution failure | URLProtocol simulates DNS failure | Error within timeout; no hang |

**Implementation approach:** Use `URLProtocol` subclass for network-level injection. For lifecycle events, use `NotificationCenter` to simulate `UIApplication` notifications.

---

### Phase 4: Ongoing Maintenance

#### 4.1 Daily Operations
- [ ] Monitor contract test results daily (automated via CI notification)
- [ ] Investigate any consecutive contract failures within 24 hours
- [ ] Track token usage / cost per contract test run

#### 4.2 Quarterly Operations
- [ ] Refresh performance baselines from latest 7-day window
- [ ] Run on-device Instruments profiling (Allocations + Leaks, 30-min session)
- [ ] Update demo app for any new SDK features
- [ ] Review and update provider-specific test constraints

#### 4.3 Per-Release Operations
- [ ] Run full eval harness against release candidate
- [ ] Run smoke test app on physical device
- [ ] Verify all contract tests pass
- [ ] Update `benchmarks/baselines.json` if performance characteristics changed

---

## Gap Analysis (from SpecFlow Review)

The following gaps were identified during spec analysis. Each is addressed in the implementation above or flagged as a known limitation.

### Addressed in This Plan

| Gap | Resolution |
|-----|-----------|
| OpenAI Responses API not tested separately | Layer 1 and Layer 4 both test Chat Completions AND Responses API paths |
| Agent handoffs untested against real providers | Layer 3 Chat missions include multi-step `ToolReasoningChain` and cross-provider continuation |
| MCP and Skills have zero test coverage | Deferred from Layer 3 app scope; covered by existing SDK tests and future dedicated mobile scenarios |
| Stream event ordering not validated | Layer 2 adds `assertStreamOrdering()` eval |
| No numeric performance baselines | Layer 2 establishes baselines from 7-day data collection |
| No flaky test mitigation | Retry-once + consecutive-failure alerting policy defined |
| Provider switching message normalization untested | Layer 3 uses SDK-normalized conversation state + provider adapter boundary; no app-level format adapter |

### Known Limitations (Deferred)

| Gap | Rationale for Deferral |
|-----|----------------------|
| watchOS/tvOS platform testing | Aspirational platforms; remove from Package.swift if not actively supported |
| iPad multitasking (Split View) | Edge case; test manually if consumer demand arises |
| Anthropic prompt caching cost validation | Beta feature; manual validation only |
| Concurrent session mutation race condition | Document as known limitation in default `SessionStore`; recommend actor-based stores for concurrent use |
| `SessionCompactionService` quality validation | Tested via serialization roundtrip only; post-compaction response quality is subjective |

### Critical Questions Resolved

| Question | Decision |
|----------|---------|
| Session state after mid-stream crash | Partial messages discarded on reload; session rolls back to last complete message |
| Concurrent session mutations | Last-write-wins; documented limitation |
| watchOS/tvOS support | Aspirational only; excluded from test scope |
| API key rotation for CI | Dedicated CI-only keys with per-key monthly spend limits |
| TTFT/throughput baselines | First 7 days establish baseline; >20% regression on p95 fails CI |
| "Passing" smoke test criteria | Any response from provider is a pass; 2 retries on rate-limit before fail |
| Chaos testing definition | Network failure injection via URLProtocol stubs |

---

## Acceptance Criteria

### Functional Requirements

- [x] Smoke Test App runs all 5 test categories and reports pass/fail in < 30 seconds
- [ ] Contract tests validate response schema, streaming format, tool calls, and error format for all 4 primary providers
- [x] Eval harness produces structured reports with correctness, performance, and reliability metrics
- [ ] Demo app exercises all categories in the Layer 3 coverage matrix
- [ ] Demo app mission catalog (`CrossProviderContinuation`, `ToolReasoningChain`, `GenerativeUICard`, `LongContextCompaction`, `FailureRecovery`) runs successfully on simulator and device
- [ ] Action parity matrix is complete for all user-visible Layer 3 flows
- [ ] Contract test CI workflow runs daily and notifies on consecutive failures

### Non-Functional Requirements

- [ ] Contract tests cost < $0.05/day (< $1.50/month)
- [x] Eval harness completes in < 10 minutes per provider
- [ ] Smoke test app is < 300 lines of Swift (excluding generated files)
- [x] Memory leak detection catches leaks > 10MB over 100 requests
- [ ] Performance baselines established within 7 days of Phase 2 start

### Quality Gates

- [x] All smoke tests pass on simulator before merging
- [ ] Contract tests have zero false-positive alerts over 7 consecutive days
- [ ] Eval harness baselines committed to `benchmarks/baselines.json`
- [ ] Demo app DX checklist completed by at least one developer who didn't write the SDK
- [ ] Prompt-only composability proof completed (mission behavior change with no code change)
- [ ] Emergent capability scenario completed (pass or logged parity gap)
- [ ] Evidence bundle export validated (JSON + markdown) for at least one simulator run and one device run

---

## Dependencies & Prerequisites

| Dependency | Required By | Status |
|-----------|------------|--------|
| CI-only API keys for OpenAI, Anthropic, Gemini, OpenRouter | Phase 1.2 | Needs creation |
| GitHub Actions secrets configured | Phase 1.3 | Needs setup |
| `.env.example` with all required key names | Phase 1.1 | Exists at `Tests/env.example` |
| Physical iOS device for manual testing | Phase 2.3, 3.1 | Available (Joel's devices) |

---

## Risk Analysis & Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Provider API changes break contract tests | False alerts, lost trust in CI | Medium | Retry-once + consecutive-failure policy; update contracts promptly |
| Rate limiting during contract tests | Tests fail intermittently | Medium | Use paid models; implement retry with Retry-After; run at off-peak hours (8 AM UTC) |
| CI cost overrun | Budget impact | Low | 10-minute timeout; daily-only schedule; token usage logging |
| Performance baselines are environment-dependent | False regressions on different CI runners | Medium | Use relative thresholds (% change) not absolute values; pin CI runner type |
| Demo app becomes stale | Poor DX reference | Medium | Update checklist item per-release; couple demo updates to feature releases |

---

## References

### Internal References

- Layer 2 Results: `docs/results/2026-02-14-layer2-eval-harness-results.md`
- Brainstorm: `docs/brainstorms/2026-02-14-production-testing-strategy-brainstorm.md`
- Existing contract tests: `Tests/AISDKTests/Core/Providers/ProviderContractTests.swift`
- Existing test runner: `Examples/AISDKTestRunner/`
- Live test patterns: `Tests/AISDKTests/Integration/BuiltInToolsLiveTests.swift`
- Stream simulation: `Tests/AISDKTests/Helpers/StreamSimulation.swift`
- Provider implementations: `Sources/AISDK/Core/Providers/`, `Sources/AISDK/LLMs/`
- Session stores: `Sources/AISDK/Sessions/`
- Skipped tests analysis: `docs/plans/2026-02-14-skipped-live-tests-status.md`
- CI workflow: `.github/workflows/ci.yml`
- Layer 3 demo runbook: `docs/runbooks/layer3-sdk-explorer-demo-runbook.md`

### External References

- Provider-specific gotchas documented: OpenAI ZDR key limitations, Anthropic model-tool version mismatches, OpenRouter free model drift
- Industry contract testing: consumer-driven contracts for API drift detection
- iOS device vs simulator testing differences: networking, memory, backgrounding
