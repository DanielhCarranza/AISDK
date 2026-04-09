# AISDK v2 — Hardening & App-Readiness Tasks

> These tasks ensure the SDK is production-ready AND easy to integrate into AIDoctor.
> The SDK agent is not done until the app agent confirms integration was smooth.

## CRITICAL: Branch Rules

**NEVER commit directly to `main`.** Every piece of work gets its own branch.

### Workflow
1. **Create a feature branch** for each major task: `git checkout -b feat/<task-name>`
   - Example: `feat/video-modality-hardening`, `feat/session-storage-polish`, `feat/reasoning-edge-cases`
2. **Work and commit atomically** on the feature branch
3. **Run `swift test`** — all 2,397 tests must pass on the branch
4. **Push the branch** — `git push -u origin HEAD`
5. **Do NOT merge to main.** The branch is handed off to the app agent for integration testing.
6. **Only merge to main after:**
   - App agent confirms integration works (builds clean, app tests pass)
   - Joel approves the merge
7. **Only tag after merge to main** — never tag a feature branch

### Branch Naming
| Task | Branch Name |
|------|------------|
| Video modality fixes | `feat/video-modality-hardening` |
| Reasoning edge cases | `feat/reasoning-controls-polish` |
| Skills protocol cleanup | `feat/agentic-skills-polish` |
| Built-in tools hardening | `feat/builtin-tools-hardening` |
| Sessions & storage | `feat/session-storage-polish` |
| Computer use cleanup | `feat/computer-use-polish` |
| Caching improvements | `feat/prompt-caching-polish` |
| Integration polish (Phase 2) | `feat/integration-polish` |

### What the App Agent Tests Against
The app agent pins to a specific branch or commit SHA — NOT main, NOT a tag — until the feature is verified. Example in the app's Package.swift or Xcode project:
```
branch: "feat/video-modality-hardening"
```
Only after both sides confirm does it move to a tag on main.

---

## Gate: All 2,397 tests must pass before ANY push

Run `swift test` and fix any failures first.

---

## Phase 1: Verify & Harden Existing Features

### 1.1 Video Modality
- [ ] Verify all 6 VideoModalityTests pass
- [ ] OpenAI: Replace silent `[Unsupported content type]` text with a proper `ProviderError.unsupportedModality(.video)` error
- [ ] Add `LLMCapabilities` check helper: `model.supports(.video)` should be documented in usage examples
- [ ] Write a usage example in `Examples/` showing: check capability → route to Gemini → handle video response
- [ ] Ensure OpenRouter/LiteLLM correctly report video capability when underlying model is Gemini

### 1.2 Reasoning Controls
- [ ] Verify AIReasoningConfigTests + E2E tests pass
- [ ] Write usage example: configure reasoning for each provider in 3 lines
- [ ] Verify Anthropic budget clamping edge case: what happens when maxTokens < 1024?
- [ ] Document which models support reasoning in a comment or doc (not just ModelRegistry flags)

### 1.3 Agentic Skills Protocol
- [ ] Verify all 7 skill test files pass
- [ ] Write a minimal example skill (SKILL.md) for AIDoctor's use case (health research agent)
- [ ] Ensure skill discovery paths are configurable (AIDoctor uses `.aidoctor/skills/`)
- [ ] Verify skill activation doesn't leak memory in long agent sessions

### 1.4 Built-in Tools (Web Search, Code Exec, etc.)
- [ ] Verify all 100+ BuiltInTool tests pass
- [ ] Write usage example: agent with web search + code execution in 5 lines
- [ ] Verify WebSearchTool returns structured citations (AIDoctor needs citation metadata)
- [ ] Test: what happens when you request a built-in tool the provider doesn't support? Error message should be actionable

### 1.5 Sessions & Storage
- [ ] Verify all 100+ session tests pass
- [ ] Write `SessionStore` protocol conformance guide for custom backends (AIDoctor uses Firebase)
- [ ] Ensure `SQLiteSessionStore` handles concurrent reads/writes safely
- [ ] Add session migration helper if schema changes between betas
- [ ] Write usage example: create session, append messages during streaming, load later

### 1.6 Computer Use
- [ ] Verify all 60+ ComputerUse tests pass
- [ ] Write usage example showing handler pattern with screenshot capture
- [ ] Document clearly: "App must implement the actual screenshot/click logic via handler"
- [ ] Ensure handler errors propagate cleanly (not swallowed)

### 1.7 Prompt Caching
- [ ] Verify AICacheConfigTests pass
- [ ] Write usage example: enable caching for Anthropic (most impactful for cost)
- [ ] Document per-provider caching behavior differences in one table

---

## Phase 2: Integration Polish

### 2.1 Provider-Agnostic Convenience
- [ ] Audit: Can an app developer switch from OpenAI to Anthropic by changing ONE line (model ID)?
- [ ] List any API surface where provider-specific knowledge leaks to the consumer
- [ ] Fix any leaks found

### 2.2 Error Messages
- [ ] Audit all `ProviderError` messages — are they actionable for an app developer?
- [ ] Unsupported features should say WHAT is unsupported and WHICH providers support it
- [ ] Network errors should be distinguishable from API errors

### 2.3 Migration Guide
- [ ] Update `docs/` migration guide with final beta.7 API surface
- [ ] List every breaking change from beta.6 → beta.7

---

## Phase 3: Merge & Tag (ONLY after app agent confirms)

- [ ] All feature branches have been tested by app agent
- [ ] App agent confirms: builds clean, tests pass, integration is smooth
- [ ] Joel approves merge
- [ ] Merge each verified feature branch to `main` (fast-forward or squash)
- [ ] Run `swift test` on `main` one final time — all 2,397 tests pass
- [ ] Tag `2.0.0-beta.7` on `main`
- [ ] Push tag: `git push origin 2.0.0-beta.7`
- [ ] App agent updates dependency pin from branch to `exact: 2.0.0-beta.7`
- [ ] Final app build + test verification

---

## Feedback Loop

When the app agent reports integration friction, add items here:

### From App Agent
<!-- App agent will append feedback here -->
