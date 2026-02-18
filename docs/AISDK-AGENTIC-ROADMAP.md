# AISDK Agentic Roadmap (SOTA Parity)

Date: 2026-01-29
Status: Draft
Owner: Engineering

## 1) Executive Summary

AISDK already contains most of the foundational building blocks (actor-based agents, tool system, streaming, MCP integration, reliability layer, generative UI). However, the current usage surface and examples are inconsistent (old `Agent` vs `AIAgentActor`, mixed streaming styles, unsafe `try!` usage). SOTA agentic SDKs emphasize three things that are underrepresented in AISDK usage and docs today:

1) A single, ergonomic streaming event model that handles text, tool calls, and steps consistently.
2) Explicit tool permissions, approvals, and guardrails (including MCP tool allowlists).
3) Traceability and evaluation as first-class concerns, not optional add-ons.

This roadmap aligns AISDK usage, docs, and APIs with these best practices while preserving Swift-native ergonomics and safety.

## 2) Current AISDK Usage Audit (Examples + Docs)

### 2.0 Deprecations already defined (from Migration Guide)
- **Deprecated**: `Agent` (class-based), `LLM` protocol, legacy `Message` types, legacy `Tool` with `@Parameter`, callback-style streaming.
- **Preferred**: `AIAgentActor`, `AILanguageModel`, `AIMessage`, `AITool`, `AsyncThrowingStream<AIStreamEvent, Error>`.
- **Adapters available**: `AILanguageModelAdapter`, `AIAgentAdapter` for incremental migration.

### 2.1 Strengths already present
- Actor-based `AIAgentActor` with streaming events exists and is documented in tutorials.
- MCP is implemented with namespacing and tool routing through `AIAgentActor`.
- Reliability patterns (circuit breaker, failover, timeouts) are implemented.
- Generative UI pipeline exists and is documented.

### 2.2 Usage issues and risks

1) **Unsafe initialization patterns**
   - Multiple docs use `try! Agent(...)` or implicit force-try patterns (crash risk).
   - This violates safe SDK usage expectations for production apps.

2) **Deprecated APIs still featured in top-level docs**
   - `Agent` (class-based) examples are still common in Getting Started even though 2.0 deprecates it.
   - `AIAgentActor` (actor-based) is the 2.0 replacement and should be the primary usage path.
   - Keeping both in top-level docs conflicts with the Migration Guide and slows adoption.

3) **Two incompatible streaming approaches**
   - Some docs stream `ChatMessage` objects (with pending state mutation).
   - Other docs stream `AIStreamEvent` from `AIAgentActor`.
   - This mismatch makes tool calls, steps, and reasoning harder to handle consistently.

4) **Tool permissions not surfaced in usage**
   - MCP integration exists, but examples do not demonstrate allowlists, approvals, or permission modes.
   - No examples show user confirmation flows or sensitive tool safeguards.

5) **Observability and evaluation are invisible to users**
   - AISDKObserver and tracing patterns are not featured in top-level usage docs.
   - There are no examples of trace capture, replay, or evaluation workflows.

6) **Context management guidance is minimal**
   - No standard patterns for auto-trimming, context windows, or memory policies are highlighted.

## 3) SOTA Agentic Best Practices (What We Should Match)

These themes are repeatedly emphasized in top agent SDKs:

- **Streaming-first, structured events**: Streaming should surface tool calls and steps, not just text deltas.
- **Tool permissions and approvals**: Explicit allow/deny, permission modes, and runtime approval hooks.
- **Handoffs and multi-agent workflows**: Agents can delegate tasks to specialized sub-agents.
- **Guardrails**: Input/output checks and tool guardrails that can block or mutate tool calls.
- **Traceability and evals**: Persisted traces, grading/evals, and replay to measure quality.
- **Modular, software-like agent development**: Make agents composable, testable, and deployable.

## 4) Product Direction for AISDK

### 4.1 North-star developer experience
"A senior iOS engineer can integrate streaming, tools, MCP, and tracing in under 30 minutes with safe defaults, no crashes, and deterministic behavior."

### 4.2 Principles
- One primary agent API with a single streaming event model.
- Safe defaults: no forced crashes, explicit permissions, bounded streams.
- Opinionated demos that show correct usage.
- Strong observability: traces and eval hooks integrated by default.
- Swift-native ergonomics, concurrency, and SwiftUI-first examples.

## 5) Roadmap (Detailed)

### Phase 0 (Week 0-1): API and Docs Alignment
**Goal**: Make the recommended usage unambiguous and safe.

Deliverables:
- Update Getting Started to use `AIAgentActor` as the canonical agent API (per Migration Guide).
- Remove `try!` usage from docs/examples; use `do/catch` or `Result` patterns.
- Publish a single canonical streaming example based on `AIStreamEvent`.
- Move legacy `Agent`/`LLM`/`Message`/legacy `Tool` examples into the Migration Guide only.

Acceptance criteria:
- No `try!` in official docs or demos.
- Only one recommended agent entry point in docs.

### Phase 1 (Weeks 2-3): Unified Streaming + Tool Orchestration
**Goal**: One event stream for text, tool calls, and step boundaries.

Deliverables:
- Consolidate streaming into `AIStreamEvent` for both providers and agent flows.
- Provide a lightweight streaming UI helper that collects deltas and handles tool events.
- Add an automated multi-step tool loop (like "steps" in other SDKs) that removes manual tool orchestration.

Acceptance criteria:
- A single streaming pattern for app developers.
- Tools are observable in-stream with clear begin/end events.

### Phase 2 (Weeks 3-4): Tool Safety, Permissions, Approvals
**Goal**: Explicit permissions and approval flows for MCP and native tools.

Deliverables:
- Add permission policies to AISDK configuration (allowlist/denylist, permission mode).
- Implement an approval handler for tool calls (including MCP tools).
- Provide a "safe tools" guide with examples and UX patterns.

Acceptance criteria:
- Tool calls can be blocked or approved at runtime.
- MCP tools are explicitly authorized in examples.

### Phase 3 (Weeks 5-6): Tracing and Evaluations
**Goal**: Make traces and evals first-class for production.

Deliverables:
- Promote `AISDKObserver` in docs with a full tracing example.
- Provide an on-disk trace format and a CLI helper to export traces.
- Add a lightweight eval harness with deterministic fixtures.

Acceptance criteria:
- Developers can capture and replay traces.
- Evals can be run locally with deterministic outputs.

### Phase 4 (Weeks 7-8): Multi-Agent + Handoff Patterns
**Goal**: Enable scalable agent workflows.

Deliverables:
- Add handoff APIs (agents as tools) with explicit delegation rules.
- Provide examples of specialized agents (e.g., Planner, Tool-Runner, Summarizer).
- Add cross-agent trace continuity.

Acceptance criteria:
- Handoff is supported and documented as a first-class feature.

### Phase 5 (Weeks 9-10): Memory + Context Management
**Goal**: Safe long-lived conversations and state.

Deliverables:
- Built-in context window policy (token/turn-based auto-trim).
- Pluggable memory store protocol with at least one reference implementation.
- Example: memory-based task continuation across app restarts.

Acceptance criteria:
- Long-running chats stay bounded without manual pruning.

### Phase 6 (Weeks 11-12): Polishing and Release Readiness
**Goal**: SOTA parity with a polished Swift-native experience.

Deliverables:
- End-to-end demo app: streaming + tools + MCP + generative UI + tracing.
- Document migration notes and compatibility matrix.
- Release checklist with test matrix and reliability targets.

Acceptance criteria:
- A single demo showcases full agentic workflow in under 5 minutes.

## 6) Prioritized Backlog (ROI / Priority / Difficulty)

Legend: Priority P0 (must), P1 (should), P2 (could). Difficulty 1-5.

| Item | ROI | Priority | Difficulty | Notes |
| --- | --- | --- | --- | --- |
| Remove `try!` from docs/examples | High | P0 | 1 | Reduces crash risk immediately |
| Finish doc migration to `AIAgentActor` | High | P0 | 2 | Aligns with already-deprecated APIs |
| Unified streaming event model | High | P0 | 4 | Enables tool + step streaming |
| Tool permission policies + approvals | High | P0 | 4 | Required for MCP safety |
| Tracing + eval hooks in docs | High | P1 | 3 | Essential for production workflows |
| Multi-agent handoffs | Med | P1 | 4 | Matches SOTA orchestration |
| Memory + context management | Med | P1 | 3 | Enables long-running sessions |
| Generative UI showcase demo | Med | P1 | 3 | Differentiator for Swift |

## 7) Key Decisions Needed

1) How long do we support the legacy adapters (`AIAgentAdapter`, `AILanguageModelAdapter`) in docs and examples?
2) Do we treat tool permissions as mandatory for all tools, or only for MCP + sensitive tools?
3) What is the minimum OS target (iOS 17 vs 18) for the new agent UX?
4) What is the beta reliability target (99.9% vs 99.99%)?

## 8) Immediate Next Steps (This Week)

- Align Getting Started and tutorials with `AIAgentActor` and 2.0 types only.
- Replace all `try!` usage in docs/examples.
- Write a single "correct" streaming example that handles tool events and finish states.
- Add a short "tool safety" section (allowlist + approval handler) to Getting Started.
