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

### Phase 2: Depth (Week 3-4) -- NOT STARTED

**Starting point for next agent:**
- Layer 1 is complete at `Examples/SmokeTestApp/main.swift` (14/14 tests passing)
- Layer 2 extends the existing `Examples/AISDKTestRunner/` -- add new test suites there
- The TestRunner already has `TestReporter`, `TestSuiteProtocol`, and `withTimer()` helpers
- Key files to read first: `Examples/AISDKTestRunner/main.swift`, `Examples/AISDKTestRunner/Utilities/TestReporter.swift`, `Examples/AISDKTestRunner/TestSuites/ProviderTestSuite.swift`
- Provider clients to use: `OpenAIClientAdapter`, `AnthropicClientAdapter`, `GeminiClientAdapter` (direct, not OpenRouter)
- Anthropic model: `claude-haiku-4-5-20251001` (cheapest, confirmed working in Layer 1)
- `.env` file with all 4 provider keys is at project root (copied from `dublin/` workspace)
- The `ProviderStreamEvent` enum is in `Sources/AISDK/Core/Providers/ProviderClient.swift` -- events are `.start`, `.textDelta`, `.finish`, etc.
- Session stores: `InMemorySessionStore`, `FileSystemSessionStore`, `SQLiteSessionStore`

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

#### 3.1 Comprehensive Demo App (Layer 3)

**Purpose:** Full-featured reference app exercising every SDK surface. Doubles as developer documentation and the closest thing to testing in a real app.

**File structure:**

```
Examples/DemoApp/
  DemoApp.swift                     # @main App entry
  Features/
    ChatView.swift                  # Multi-turn streaming chat
    AgentView.swift                 # Agent with tools and handoffs
    GenerativeUIView.swift          # UITree rendering and interaction
    MCPView.swift                   # MCP server connections
    SessionView.swift               # Session management (create/restore/export)
    ProviderPicker.swift            # Switch providers mid-conversation
    BenchmarkView.swift             # Run benchmarks on-device
    SkillsView.swift                # Skills system demo
  Shared/
    SDKSetup.swift                  # Provider configuration from .env
    ErrorHandling.swift             # Error display patterns
    MessageFormatAdapter.swift      # Provider switching message normalization
  Resources/
    SampleSkills/                   # Example skills for testing
```

**Feature coverage matrix:**

| Feature | SDK Surface Exercised | Layer 3 Test |
|---------|----------------------|-------------|
| Multi-turn chat (streaming) | `LLM.streamText()`, message history | ChatView |
| Agent with tool loop | `Agent.execute()`, `maxSteps`, tool execution | AgentView |
| Agent handoffs | `AgentHandoff` (shared/forked/independent modes) | AgentView |
| Generative UI | `GenerativeUIViewModel`, `GenerativeUIView`, `UITree` | GenerativeUIView |
| MCP connections | `MCPClient`, `MCPServerConfiguration` | MCPView |
| Session persistence | `SessionStore` (all 3 implementations) | SessionView |
| Session compaction | `SessionCompactionService` | SessionView |
| Skills system | `SkillRegistry`, `SkillParser`, `SkillPromptBuilder` | SkillsView |
| Provider switching | Changing LLM mid-conversation, message normalization | ProviderPicker |
| Error recovery | Network errors during stream, retry UI | ErrorHandling |
| Background/foreground | Stream interruption on app background | All views |
| Network transitions | WiFi to cellular during stream | All views |

**DX validation checklist (manual, run with a fresh developer):**

- [ ] Can a new developer get the app running in < 5 minutes?
- [ ] Are error messages actionable (not just "request failed")?
- [ ] Is provider switching intuitive?
- [ ] Does streaming feel smooth (no UI jank)?
- [ ] Is the API surface predictable (no surprising behaviors)?
- [ ] Does autocomplete/documentation appear correctly in Xcode?

**Package.swift changes:**
- Add `DemoApp` as executable target depending on `AISDK`

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
| Agent handoffs untested against real providers | Layer 3 Demo App includes AgentView with handoff demos |
| MCP and Skills have zero test coverage | Layer 3 adds MCPView and SkillsView |
| Stream event ordering not validated | Layer 2 adds `assertStreamOrdering()` eval |
| No numeric performance baselines | Layer 2 establishes baselines from 7-day data collection |
| No flaky test mitigation | Retry-once + consecutive-failure alerting policy defined |
| Provider switching message normalization untested | Layer 3 ProviderPicker + MessageFormatAdapter |

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
- [ ] Eval harness produces JSON reports with correctness, performance, and reliability metrics
- [ ] Demo App exercises all 12 feature categories from the coverage matrix
- [ ] Contract test CI workflow runs daily and notifies on consecutive failures

### Non-Functional Requirements

- [ ] Contract tests cost < $0.05/day (< $1.50/month)
- [ ] Eval harness completes in < 10 minutes per provider
- [ ] Smoke test app is < 300 lines of Swift (excluding generated files)
- [ ] Memory leak detection catches leaks > 10MB over 100 requests
- [ ] Performance baselines established within 7 days of Phase 2 start

### Quality Gates

- [x] All smoke tests pass on simulator before merging
- [ ] Contract tests have zero false-positive alerts over 7 consecutive days
- [ ] Eval harness baselines committed to `benchmarks/baselines.json`
- [ ] Demo app DX checklist completed by at least one developer who didn't write the SDK

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

- Brainstorm: `docs/brainstorms/2026-02-14-production-testing-strategy-brainstorm.md`
- Existing contract tests: `Tests/AISDKTests/Core/Providers/ProviderContractTests.swift`
- Existing test runner: `Examples/AISDKTestRunner/`
- Live test patterns: `Tests/AISDKTests/Integration/BuiltInToolsLiveTests.swift`
- Stream simulation: `Tests/AISDKTests/Helpers/StreamSimulation.swift`
- Provider implementations: `Sources/AISDK/Core/Providers/`, `Sources/AISDK/LLMs/`
- Session stores: `Sources/AISDK/Sessions/`
- Skipped tests analysis: `docs/plans/2026-02-14-skipped-live-tests-status.md`
- CI workflow: `.github/workflows/ci.yml`

### External References

- Provider-specific gotchas documented: OpenAI ZDR key limitations, Anthropic model-tool version mismatches, OpenRouter free model drift
- Industry contract testing: consumer-driven contracts for API drift detection
- iOS device vs simulator testing differences: networking, memory, backgrounding
