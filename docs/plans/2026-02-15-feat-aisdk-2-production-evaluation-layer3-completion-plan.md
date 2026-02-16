---
title: "AISDK 2.0 Production Evaluation & Layer 3 Completion"
type: feat
status: active
date: 2026-02-15
---

# AISDK 2.0 Production Evaluation & Layer 3 Completion

## Overview

Complete the Layer 3 SDK Explorer iOS app verification, then conduct a comprehensive production-readiness evaluation of AISDK 2.0 across 7 axes, culminating in a structured evaluation report with scorecards, gap analysis, and recommendations.

**Branch:** `jmush16/prod-test-strategy`
**PR Target:** `aisdk-2.0-modernization`

## Problem Statement

AISDK 2.0 adds 45,197 lines (21,237 source + 23,960 tests) with 8 new subsystems. While the foundation layer (2,250 unit tests), Layer 1 (smoke tests), and Layer 2 (eval harness) are complete, the following remain unvalidated:

1. The SDK Explorer iOS app (Layer 3) has a toolbar bug and hasn't been exercised with the full test question bank
2. No systematic evaluation has been conducted to determine if all 8 subsystems are production-ready
3. No evaluation report exists documenting readiness, gaps, and risks

## Proposed Solution

A 3-phase approach: fix and verify the Layer 3 app with XcodeBuildMCP-driven automation, evaluate the SDK across 7 dimensions, then produce a structured report.

---

## Technical Approach

### Automation Strategy (XcodeBuildMCP-First)

Use XcodeBuildMCP as the primary execution layer for Layer 3 evaluation to reduce manual drift and produce reproducible artifacts.

1. Store scenario definitions in repo-local config: `.xcodebuildmcp/evaluation-config.yaml`
2. Initialize session defaults from config (project, scheme, simulator, configuration)
3. Execute deterministic scenarios (`smoke`, `layer3-full`, `generative-ui-regression`, `reasoning-tool-flow`)
4. Capture artifacts per scenario:
   - Screenshots
   - Simulator app logs
   - Question-level pass/fail records
5. Apply standardized failure categories:
   - `infra` (tooling/simulator/network)
   - `provider` (model/provider behavior)
   - `app_regression` (SDK Explorer behavior)
   - `assertion_mismatch` (expectation/evidence mismatch)

### Phase 1: Complete Layer 3 Verification

#### 1.1 Fix Toolbar Buttons Not Appearing

**Root Cause Analysis:**

The toolbar buttons (chat history clock icon + new chat pencil icon) are defined in `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Chat/ChatView.swift:24-38` using `NavigationStack > .toolbar > ToolbarItem(placement: .topBarLeading/.topBarTrailing)`.

The `ContentView.swift` wraps `ChatView` inside a `TabView` (lines 9-24). This is a known SwiftUI issue on iOS 18.0: when `NavigationStack` is nested inside `TabView`, toolbar items with `.topBarLeading` and `.topBarTrailing` placements can fail to render.

**Fix Approaches (try in order):**

1. **Add `.navigationBarTitleDisplayMode(.inline)` to ChatView** — This forces the navigation bar to render in inline mode, which reliably shows toolbar items inside TabView.
2. **Change placement to `.navigationBarLeading` / `.navigationBarTrailing`** — Older placement values that may be more reliable inside TabView on iOS 18.0.
3. **Wrap the TabView in NavigationStack at ContentView level** — Move NavigationStack from ChatView to ContentView, wrapping the entire TabView. This is less ideal (shared navigation state) but guarantees toolbar rendering.

**Files to modify:**
- `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Chat/ChatView.swift`
- Potentially `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/ContentView.swift`

**Verification:** Build and run on simulator. Both toolbar buttons (clock icon leading, pencil icon trailing) must be visible. Tap clock icon -> ChatHistorySheet appears. Tap pencil icon -> new chat starts.

#### 1.2 Handle API Keys and Uncommitted Changes

**Before testing:**

1. Strip API keys from `Examples/SDKExplorer.xcodeproj/xcshareddata/xcschemes/SDKExplorer.xcscheme` — replace hardcoded values with `$(OPENAI_API_KEY)` / `$(ANTHROPIC_API_KEY)` / `$(GOOGLE_API_KEY)` environment variable references
2. Verify `.env` at repo root contains valid keys for all 3 providers
3. Commit all 7 modified files + 2 untracked directories with message: "Prepare Layer 3 SDK Explorer for production evaluation"

**Files:**
- `Examples/SDKExplorer.xcodeproj/xcshareddata/xcschemes/SDKExplorer.xcscheme`
- All 5 modified SDKExplorerPackage files
- `docs/references/layer3-test-questions.md`
- `docs/references/model-selection-guide.md`

#### 1.3 Run Test Question Bank (Q1-Q16)

Execute all 16 test questions across 3 providers following the sequence in `docs/references/layer3-test-questions.md`:

**Execution Order:**
1. **OpenAI** (gpt-4.1-mini): Q1-Q10 in order (Q7 after Q2/Q3), then Q11-O, Q12-O
2. **Anthropic** (claude-haiku-4-5-20251001): New session, Q1-Q10, then Q13-A, Q14-A
3. **Gemini** (gemini-2.5-flash): New session, Q1-Q10, then Q15-G, Q16-G
4. **Cross-provider test**: On OpenAI ask Q1-Q3, switch to Anthropic via provider picker, ask Q7

**Pass/Fail Criteria per Question:**

| Question | PASS criteria | FAIL criteria |
|----------|--------------|---------------|
| Q1 | Tokens stream incrementally (3+ textDelta events); persona maintained | No streaming or generic "AI assistant" response |
| Q2 | Calculator tool called; result is exactly 714; narrated in character | Wrong result, no tool call, or crash |
| Q3 | 3 sequential tool calls producing 42, 126, 18 | Missing steps or wrong intermediate results |
| Q4 | JSON in message + rendered Card with Metric/Badge/Progress visible | No UITree render or crash during parsing |
| Q5 | Bar chart renders with 4 bars and Q1-Q4 labels | No chart render or wrong data |
| Q6 | 2 weather_lookup calls; coherent comparison response | Missing tool calls or no comparison |
| Q7 | Correctly recalls "714" and "18" from Q2/Q3 | Cannot recall or wrong numbers |
| Q8 | Calculator fires (8760); rendered Card with Metric visible | Missing tool call or no UITree render |
| Q9 | Tool returns division-by-zero error; agent handles gracefully | Crash or unhandled error |
| Q10 | Nested Card > Stack > Grid > 4 Metrics all render | Partial render or crash |
| Q11-O | Exactly 5 cities with name/country/threat level format | Wrong count or missing fields |
| Q12-O | ~500 words stream without interruption | Stream stalls (>5s gap) or truncates |
| Q13-A | Correct Bayesian answer (2/3); reasoning steps shown | Wrong answer or no reasoning |
| Q14-A | Stays in KillgraveAI character; no safety hedging | Breaks character or refuses |
| Q15-G | Sequential tool calls with thinking; correct answer (3hrs, 180mi) | Wrong answer or no thinking |
| Q16-G | PieChart renders with 5 slices and legend | No chart or wrong percentages |

**Dependency handling:** If Q2 or Q3 fails, mark Q7 as `SKIP (dependency failed)`.

#### 1.3a Automated Scenario Execution via XcodeBuildMCP

Run all Layer 3 evaluation scenarios using XcodeBuildMCP-driven flows defined in `.xcodebuildmcp/evaluation-config.yaml`.

**Scenario set:**
1. `smoke`: build + launch + baseline screenshot + log capture sanity
2. `layer3-full`: execute Q1-Q16 matrix across providers with checkpoint screenshots
3. `generative-ui-regression`: dedicated Q4/Q5/Q8/Q10/Q16 visual and parser checks
4. `reasoning-tool-flow`: dedicated reasoning -> tool call lifecycle -> final response checks (Q13-A, Q15-G plus one chained-tools prompt)

**Required artifacts per scenario:**
- Scenario summary markdown with pass/fail and failure category
- Screenshot set under `docs/results/layer3/artifacts/screenshots/<scenario>/`
- Logs under `docs/results/layer3/artifacts/logs/<scenario>/`

#### 1.3b Generative UI Regression Track

Expand current Generative UI checks into a dedicated matrix covering:

1. **Render correctness:** expected components and layout appear for each question
2. **Parser resilience:** raw JSON, fenced JSON, and extracted JSON-slice fallback all validated
3. **Interaction readiness:** interactive UI action trace is captured (where components expose actions)
4. **Chart integrity:** bar/line/pie chart data labeling and value mapping are visually correct

Record each check with explicit evidence links (screenshot + corresponding log snippet).

#### 1.4 Physical Device Verification

Run a subset on physical device to validate on-device behavior:
- Q1 (streaming), Q2 (tool calling), Q4 (Generative UI) on one provider (OpenAI recommended — cheapest after Gemini but most reliable)
- Verify app launches, tab navigation works, toolbar buttons visible

#### 1.5 Document Results

Create `docs/results/layer3-test-results.md` with columns:
- Question ID, Provider, Pass/Fail, Duration (ms), Token Usage, Error Message, Notes

Add scenario-level section:
- Scenario Name, Runs, Pass Rate, Flake Rate, Failure Categories, Artifact Paths

---

### Phase 2: Comprehensive SDK Evaluation

#### Evaluation Methodology

For each of the 8 subsystems, evaluate using a combination of:
1. **Code review** — Does the code exist, is it wired up, is it well-structured?
2. **Test coverage** — What percentage of the subsystem has test coverage? Are failure paths tested?
3. **Runtime validation** — Does it actually work when exercised (via Layer 1-3 or direct testing)?
4. **DX assessment** — Is the API intuitive, documented, and consistent?

#### Scoring Rubric (1-5)

| Score | Label | Criteria |
|-------|-------|----------|
| 5 | Production-ready | Feature complete, excellent test coverage, great DX, no known issues |
| 4 | Good | Works well, good test coverage, minor DX rough edges |
| 3 | Works with issues | Core functionality works, some test gaps, DX acceptable but not great |
| 2 | Partially working | Significant gaps, thin test coverage, confusing DX |
| 1 | Broken/not wired up | Non-functional, no meaningful tests, unusable |

#### A. Feature Completeness — Do All 8 Subsystems Work?

For each subsystem, map declared features (from `docs/WHATS_NEW_AISDK_2.md`) against working code:

| # | Subsystem | Validation Method | Key Files |
|---|-----------|------------------|-----------|
| 1 | Actor-Based Agent System | Layer 3 missions + Q2/Q3/Q6 results | `Sources/AISDK/Agent/` |
| 2 | Provider Adapters | Q1-Q10 across all 3 providers | `Sources/AISDK/Providers/` |
| 3 | Reliability Layer | Code review + existing unit tests + `Tests/AISDKTests/Reliability/` | `Sources/AISDK/Reliability/` |
| 4 | Generative UI | Q4/Q5/Q8/Q10/Q16 + dedicated regression matrix | `Sources/AISDK/GenerativeUI/` |
| 5 | Session Persistence | Sessions tab + Q7 context recall | `Sources/AISDK/Session/` |
| 6 | Context Management | Code review + compaction tests | `Sources/AISDK/Context/` |
| 7 | Telemetry | Code review only (no Layer 3 coverage) | `Sources/AISDK/Telemetry/` |
| 8 | Tool System | Q2/Q3/Q6/Q8/Q9 results | `Sources/AISDK/Tools/` |

**For each subsystem, document:**
- Features declared vs features verified working
- Test coverage (count tests, identify gaps)
- Integration status (standalone component vs wired into SDK)
- Known issues or limitations

#### B. API Ergonomics — Can a Developer Use This?

Evaluate by attempting to answer: "Can a developer go from zero to working chat app in 30 minutes using SDK docs?"

**Checklist:**
- [ ] Public API surface is consistent (naming conventions, parameter patterns)
- [ ] Xcode autocomplete surfaces the right types and methods
- [ ] Error messages are actionable (not just "request failed")
- [ ] Migration Guide (`docs/MIGRATION-GUIDE.md`) is accurate and complete
- [ ] `docs/WHATS_NEW_AISDK_2.md` code examples compile and work
- [ ] Provider switching requires minimal code changes
- [ ] No hidden gotchas (implicit state, required initialization order, etc.)

**Key files to review:**
- `Sources/AISDK/` public API surface
- `docs/MIGRATION-GUIDE.md`
- `docs/WHATS_NEW_AISDK_2.md`

#### C. Test Coverage — Where Are the Gaps?

1. Run `swift test` and verify 2,250 tests pass
2. Categorize tests by subsystem and type (unit / integration / live)
3. Identify subsystems with thin coverage
4. Check if reliability tests actually test failure scenarios (not just happy paths)
5. Check if Generative UI tests cover all 25 components or just Core 8
6. Check MCP and Skills test coverage (known to be zero per production testing plan)

**Key directory:** `Tests/AISDKTests/`

#### D. Provider Compatibility — Cross-Provider Behavior

Use Phase 1 Q1-Q10 results (same questions across all 3 providers) to identify:
- Feature parity (do all providers support all tested features?)
- Behavioral differences (response format, error shapes, tool call patterns)
- Provider-specific bugs or workarounds needed
- Known quirks documented in `docs/references/model-selection-guide.md`

**Already-known issues (from handoff):**
1. Anthropic wraps JSON in markdown fences -> 3-step parseTree fallback
2. Anthropic sends "+" for calculator Operation -> flexible decoder
3. OpenAI rejects requests after tool calls if tool_calls stored in history

#### E. Reliability Layer — Real or Aspirational?

**Critical question:** Are these standalone components or wired into the SDK?

1. **Code review:** Check if `AdaptiveCircuitBreaker`, `FailoverExecutor`, `RetryPolicy`, `TimeoutPolicy`, `ProviderHealthMonitor` are instantiated in provider clients
2. **Test review:** Analyze `Tests/AISDKTests/Reliability/` — do tests cover:
   - Circuit breaker tripping after N failures?
   - Failover switching to alternate provider?
   - Retry with exponential backoff?
   - Timeout enforcement?
3. **FaultInjector:** Does chaos testing actually work? Can you inject faults and observe recovery?
4. **Integration check:** Trace the code path from `AILanguageModel.streamText()` — does it go through reliability middleware?

#### F. Session & Context Management — Production-Ready?

1. **3 Session Stores:** Verify InMemory, FileSystem, SQLite all pass roundtrip serialization
2. **StreamingPersistenceBuffer:** Does it buffer streaming events and persist them?
3. **Context Compaction:** Does truncate/summarize/sliding window actually work? Quality of compacted output?
4. **Session Export/Import:** Can sessions be exported and re-imported?
5. **SearchableSessionStore:** Does search work across sessions?

**Test using:** Sessions tab in SDK Explorer + existing unit tests in `Tests/AISDKTests/Session/`

#### G. Visualization & Agent UX — Thought -> Tool -> Response

Evaluate whether SDK Explorer demonstrates the expected agent interaction paradigm in a way that is observable and debuggable.

**Capability audit targets:**
- `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Shared/SDKConfig.swift`
- `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Chat/ChatView.swift`
- `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Chat/MessageRow.swift`
- `Sources/AISDK/Core/Models/AIStreamEvent.swift`

**Required checks:**
1. Reasoning lifecycle visibility (`reasoningStart`, `reasoningDelta`, `reasoningFinish`)
2. Tool lifecycle visibility (`toolCallStart`, `toolCallDelta`, `toolCall/toolCallFinish`, `toolResult`)
3. Final response ordering and coherence after tool execution
4. Evidence quality: each claim must include screenshot + event/log excerpt

**Output format:**
- Mark each capability as `Implemented`, `Partial`, or `Missing`
- Provide release recommendation impact per missing/partial item

---

### Phase 3: Produce Evaluation Report

Create `docs/results/aisdk-2.0-evaluation-report.md` with the following structure:

#### Report Structure

```markdown
# AISDK 2.0 Production Evaluation Report
Date: 2026-02-15
Evaluator: [name]
Branch: jmush16/prod-test-strategy

## Executive Summary
- Overall readiness assessment (1 paragraph)
- Top 3 risks
- Go/no-go recommendation

## Scorecard
| Subsystem | Score (1-5) | Rationale |
|-----------|:-----------:|-----------|
| Agent System | X | ... |
| Provider Adapters | X | ... |
| Reliability Layer | X | ... |
| Generative UI | X | ... |
| Session Persistence | X | ... |
| Context Management | X | ... |
| Telemetry | X | ... |
| Tool System | X | ... |

## Test Results Matrix
| Q# | OpenAI | Anthropic | Gemini | Notes |
|----|:------:|:---------:|:------:|-------|
| Q1 | P/F | P/F | P/F | ... |
...

## Gap Analysis
### Critical Gaps (block release)
### Important Gaps (should fix before release)
### Nice-to-Have (fix post-release)

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|:----------:|:------:|------------|

## Developer Experience Analysis
- DX score: X/10
- Key findings from API ergonomics review
- Migration Guide accuracy assessment

## Automation Reliability
- Scenario pass rates and rerun stability
- Flake analysis and root-cause categories
- Deterministic rerun assessment

## Agent UX Visibility
- Reasoning visibility score
- Tool lifecycle visibility score
- Final response ordering/completeness score
- Thought -> tool -> response parity verdict

## Generative UI Regression
- Component family coverage summary
- Parser fallback behavior summary
- Chart rendering regression outcomes

## Recommendations (Prioritized)
1. [Highest priority]
2. ...

## Appendices
- Full test execution logs
- Screenshots of Generative UI rendering
```

---

## Implementation Phases

### Phase 1: Layer 3 Completion (Steps 1.1-1.5)

| Step | Task | Effort | Dependencies |
|------|------|--------|-------------|
| 1.1 | Fix toolbar buttons | Small | None |
| 1.2 | Handle API keys + commit changes | Small | None |
| 1.3 | Run Q1-Q16 across 3 providers | Medium | 1.1, 1.2 |
| 1.3a | Run XcodeBuildMCP scenarios | Medium | 1.1, 1.2 |
| 1.3b | Run Generative UI regression track | Medium | 1.3 |
| 1.4 | Physical device verification | Small | 1.3, 1.3a |
| 1.5 | Document results | Small | 1.3, 1.3a, 1.3b, 1.4 |

### Phase 2: SDK Evaluation (Steps A-G)

| Step | Evaluation Axis | Effort | Dependencies |
|------|----------------|--------|-------------|
| A | Feature Completeness | Medium | Phase 1 results inform scoring |
| B | API Ergonomics | Medium | None (can run in parallel with A) |
| C | Test Coverage | Small | None (can run in parallel) |
| D | Provider Compatibility | Small | Phase 1 Q1-Q10 results |
| E | Reliability Layer | Medium | None (code review) |
| F | Session & Context Mgmt | Medium | None (can run in parallel) |
| G | Visualization & Agent UX | Medium | Phase 1 + capability audit |

### Phase 3: Report (Single deliverable)

| Step | Task | Effort | Dependencies |
|------|------|--------|-------------|
| 3.1 | Write evaluation report | Medium | All of Phase 1 + Phase 2 |

---

## Acceptance Criteria

### Functional Requirements

- [ ] Toolbar buttons visible and functional in SDK Explorer on iOS 18.0 simulator
- [ ] API keys removed from xcscheme, loaded from .env only
- [ ] All uncommitted changes committed to `jmush16/prod-test-strategy`
- [ ] Q1-Q16 executed across all 3 providers with documented pass/fail
- [ ] XcodeBuildMCP scenarios executed with stored artifacts
- [ ] Generative UI regression matrix executed and documented
- [ ] Cross-provider context test (Q7) executed
- [ ] Physical device test subset completed
- [ ] All 8 subsystems evaluated with 1-5 scores
- [ ] API ergonomics assessment completed
- [ ] Test coverage gaps identified and documented
- [ ] Provider compatibility matrix documented
- [ ] Reliability layer integration verified (wired up or not)
- [ ] Session management stores tested
- [ ] Thought -> tool call -> final response capability audit completed (`Implemented`/`Partial`/`Missing`)

### Quality Gates

- [ ] `swift test` passes (2,250 tests)
- [ ] `swift build` succeeds
- [ ] No API keys in committed code
- [ ] Evaluation report follows defined structure
- [ ] All scorecard ratings have evidence-based rationale
- [ ] Automation rerun reproducibility demonstrated (same config, same branch)
- [ ] No critical regression in agent UX visibility or Generative UI rendering

## Dependencies & Prerequisites

- Valid API keys in `.env` for OpenAI, Anthropic, Gemini
- Booted iOS 18.0 simulator (iPhone 16 Pro, device ID: E1AE9D7A-0FF6-4395-88E3-E6A96C74EC28)
- `.xcodebuildmcp/evaluation-config.yaml` is present and validated
- Physical iOS device available for 1.4
- Existing Layer 1 (smoke test) and Layer 2 (eval harness) results for cross-reference

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|:----------:|:------:|------------|
| API keys exhausted mid-testing | Low | High | Use cheapest models (Gemini first), monitor spend |
| Provider API downtime during testing | Medium | Medium | Test providers independently, retry later if down |
| Toolbar fix requires ContentView restructure | Low | Medium | Try 3 approaches in order; worst case is NavigationStack wrapping TabView |
| Reliability layer found to be aspirational only | Medium | High | Document honestly in report; recommend integration tasks |
| Test question bank reveals SDK bugs | Medium | Medium | Document bugs in report, file follow-up issues |

## References

### Internal References
- Brainstorm: `docs/brainstorms/2026-02-14-production-testing-strategy-brainstorm.md`
- Master plan: `docs/plans/2026-02-14-feat-production-testing-strategy-plan.md`
- Test questions: `docs/references/layer3-test-questions.md`
- Model guide: `docs/references/model-selection-guide.md`
- Demo runbook: `docs/runbooks/layer3-sdk-explorer-demo-runbook.md`
- Architecture: `docs/AISDK-ARCHITECTURE.md`
- What's new: `docs/WHATS_NEW_AISDK_2.md`
- Migration guide: `docs/MIGRATION-GUIDE.md`

### Key Source Files
- `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Chat/ChatView.swift` — Toolbar bug location
- `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/ContentView.swift` — TabView wrapper
- `Examples/SDKExplorerPackage/Sources/SDKExplorerFeature/Shared/SDKConfig.swift` — Runtime configuration
- `Sources/AISDK/Reliability/` — Reliability layer to verify
- `Tests/AISDKTests/` — Test suite to analyze
