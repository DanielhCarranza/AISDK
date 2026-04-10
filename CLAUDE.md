# AISDK Development Instructions

Read `.claude/soul.md` at session start. Review `tasks/lessons.md` for known patterns.

## Project Identity

AISDK is a single-import Swift SDK for multi-provider LLM integration on Apple platforms (iOS 17+, macOS 14+, watchOS 10+, tvOS 17+). It provides agents, tool calling, streaming, structured output, generative UI, and session management.

**Vision:** The definitive AI SDK for iOS/macOS development — multimodal, supporting all frontier models (OpenAI, Anthropic, Gemini) with model routing via LiteLLM and OpenRouter. One import, any model, any modality.

**Current state:** `2.0.0-beta.6` on `main`. Active development toward stable v2 release.

**Key abstractions:**
- `LLM` protocol — unified interface for all providers (`generateText`, `streamText`, `generateObject`)
- `Agent` actor — Swift 6 concurrency, configurable stop conditions, `@Observable` state
- `AILanguageModelAdapter` — bridges legacy providers to v2 `LLM` protocol
- `ProviderLanguageModelAdapter` — wraps v2 provider clients (OpenRouter, LiteLLM)

## Branch Strategy

- **`main`** is the active development branch. All PRs target `main`.
- **`release/1.x`** for v1 maintenance hotfixes only.
- Tag format: bare semver `X.Y.Z` (no `v` prefix — SPM requires this).
- Beta tags: `2.0.0-beta.N` on `main` for consumer testing.
- Consumers use `.exact("2.0.0-beta.N")` in Package.swift (SPM won't resolve pre-release with ranges).
- GitHub Releases auto-created when tags are pushed (`.github/workflows/release.yml`).
- CI runs on PRs to `main` and `release/**` (`.github/workflows/ci.yml`).

### Hotfix flow (v1)
1. Branch from `release/1.x`, apply fix, PR back to `release/1.x`
2. Tag: `git tag -a 1.0.X -m "Release 1.0.X - [description]" && git push origin 1.0.X`

## Build and Test

- `swift build` — build all targets
- `swift test` — run the full test suite (2,397 tests — 2,071 XCTest + 326 Swift Testing)
- `swift test --filter <TestClass>` — run specific tests
- `swift package resolve` — resolve dependencies without building
- `RUN_LIVE_TESTS=1 swift test` — include live API integration tests (requires `.env` with API keys)
- `swift run BasicChatDemo` — run CLI chat demo
- `swift run ToolDemo` — run tool calling demo

## Commit Messages and PRs

- Short, imperative, sentence-case (e.g., "Add retry mechanism for chat requests")
- Never attribute commits to Claude or Anthropic
- PR workflow:
  1. Make changes on your workspace branch
  2. Run `swift build` and `swift test` to verify
  3. Push: `git push -u origin HEAD`
  4. Create PR: `gh pr create --base main`

## Compound Engineering Workflows

For complex tasks, use the compound engineering plugin workflows. These follow a **brainstorm → plan → work → review** pipeline.

### When to use each

**`/workflows:brainstorm`** — Start here for new features or significant decisions. Explores the problem space, surfaces trade-offs, generates options. Free-form and divergent.
- Output lands in `docs/brainstorms/`
- Use when: starting something new, facing a design decision, multiple valid approaches exist

**`/workflows:plan`** — After brainstorm, transform into a structured implementation plan. Detailed, actionable, with acceptance criteria.
- Output lands in `docs/plans/`
- Use when: you know what to build but need to sequence the work

**`/workflows:work`** — Execute the plan. Handles git workflow, task tracking, quality checks, commits.
- Use when: plan is approved and ready to implement

**`/workflows:review`** — Multi-agent code review with deep analysis. Run before merge.
- Use when: implementation is complete, PR is ready

**`/workflows:compound`** — After solving a hard problem, document it for the team's knowledge.
- Use when: you learned something non-obvious that future sessions should know

### Decision heuristic

If the task touches 3+ files or involves an architectural choice → start with brainstorm or plan.
If it's a focused bug fix or small change → just do it.
If you solved something hard → compound it.

## Workflow Orchestration

### 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions).
- If something goes sideways, STOP and re-plan immediately — don't keep pushing.
- Use plan mode for verification steps, not just building.
- Write detailed specs upfront to reduce ambiguity.

### 2. Subagent Strategy
- Use subagents liberally to keep main context window clean.
- Offload research, exploration, and parallel analysis to subagents.
- For complex problems, throw more compute at it via subagents.
- One task per subagent for focused execution.

### 3. Self-Improvement Loop
- After ANY correction from the user: update `tasks/lessons.md` with the pattern.
- Write rules for yourself that prevent the same mistake.
- Ruthlessly iterate on these lessons until mistake rate drops.
- Review lessons at session start for relevant project.

### 4. Verification Before Done
- Never mark a task complete without proving it works.
- Diff behavior between main and your changes when relevant.
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness.
- **Document the feature**: After tests pass, update docs (`docs/api-reference/`, tutorials, CLAUDE.md providers table) before marking done. A feature without docs is not done. If a feature was changed, update existing docs to stay current.

### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution."
- Skip this for simple, obvious fixes — don't over-engineer.
- Challenge your own work before presenting it.

### 6. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding.
- Point at logs, errors, failing tests — then resolve them.
- Zero context switching required from the user.
- Go fix failing CI tests without being told how.

## Task Management

1. **Plan First**: Write plan to `tasks/todo.md` with checkable items.
2. **Verify Plan**: Check in before starting implementation.
3. **Track Progress**: Mark items complete as you go.
4. **Explain Changes**: High-level summary at each step.
5. **Capture Lessons**: Update `tasks/lessons.md` after corrections.

## Architecture Quick Reference

### Module map
| Module | Status | Purpose |
|--------|--------|---------|
| `AISDK` | Active | Core — LLM protocol, Agent, providers, reliability, sessions, MCP, generative UI |
| `AISDKChat` | Commented out | Pre-built chat UI components (SwiftUI) |
| `AISDKVoice` | Commented out | Speech recognition, TTS, voice UI |
| `AISDKVision` | Commented out | LiveKit video streaming, camera management |

### Key directories
```
Sources/AISDK/          — Core SDK source
Tests/AISDKTests/       — Test suite
Examples/               — Demo apps (BasicChatDemo, ToolDemo, OpenRouterDemo, AISDKCLI, etc.)
docs/                   — Architecture, API reference, tutorials, migration guide
docs/api-reference/     — Public API docs
docs/tutorials/         — Getting started through sessions
```

### Providers
| Provider | Client (ProviderClient) | v2 Wrapper | API Endpoint |
|----------|------------------------|------------|--------------|
| OpenAI (Responses) | `OpenAIResponsesClientAdapter` | `ProviderLanguageModelAdapter` (native v2) | `POST /v1/responses` |
| OpenAI (Chat Completions) | `OpenAIClientAdapter` | `ProviderLanguageModelAdapter` (native v2) | `POST /v1/chat/completions` |
| OpenAI (Legacy) | `OpenAIProvider` | `AILanguageModelAdapter` | Both endpoints |
| Anthropic (v2) | `AnthropicClientAdapter` (actor) | `ProviderLanguageModelAdapter` (native v2) | Messages API |
| Anthropic (Legacy) | `AnthropicProvider` | `AILanguageModelAdapter` | Messages API |
| Gemini (v2) | `GeminiClientAdapter` (actor) | `ProviderLanguageModelAdapter` (native v2) | Gemini API |
| Gemini (Legacy) | `GeminiProvider` | `AILanguageModelAdapter` | Gemini API |
| OpenRouter | `OpenRouterClient` (actor) | `ProviderLanguageModelAdapter` (native v2) | OpenAI-compatible |
| LiteLLM | `LiteLLMClient` (actor) | `ProviderLanguageModelAdapter` (native v2) | OpenAI-compatible |

**Factory methods:** `ProviderLanguageModelAdapter.openAIResponses(apiKey:modelId:)` (recommended), `.openAIChatCompletions(apiKey:modelId:)`, `.anthropic(apiKey:modelId:)`, `.gemini(apiKey:modelId:)` for quick setup.

## Security

- Never commit `.env` files or API keys.
- Use `Tests/env.example` as template for local `.env`.
- Integration tests auto-skip in CI when keys are absent (`XCTSkip`).

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.
