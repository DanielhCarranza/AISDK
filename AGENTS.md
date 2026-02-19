# Repository Guidelines

## Project Structure & Module Organization
- `Package.swift` defines SwiftPM products, targets, and platform support (iOS/macOS/watchOS/tvOS).
- `Sources/` contains modules: `AISDK` (core), plus optional feature targets like `AISDKChat`, `AISDKVoice`, `AISDKVision`, and `AISDKResearch`.
- `Examples/` hosts runnable demo executables (for example, `BasicChatDemo`, `ToolDemo`).
- `Tests/` contains XCTest suites and fixtures; provider scripts live under `Tests/AISDKTests/LLMTests/Providers`.
- `docs/` and `Sources/AISDK/docs/` hold architecture and usage documentation.

## Build, Test, and Development Commands
- `swift build` — build all SwiftPM targets.
- `swift test` — run the full XCTest suite.
- `swift test --filter AgentIntegrationTests` — run a focused test class.
- `swift run BasicChatDemo` — run the CLI demo for chat and tool flows.
- `swift run ToolDemo` — run the tool calling demo.

## Coding Style & Naming Conventions
- Swift 5.9 conventions with 4-space indentation and braces on the same line.
- Types use `PascalCase` (for example, `AIMessage`); methods and variables use `camelCase`.
- Test methods follow `test...` naming, grouped by feature in `Tests/AISDKTests`.
- No enforced formatter or linter is configured; match existing file style in the touched module.

## Testing Guidelines
- XCTest and Swift Testing are the standard frameworks (see `Tests/AISDKTests/README.md`).
- **2,397 tests** (2,071 XCTest + 326 Swift Testing), 100% pass rate.
- Use `Tests/env.example` as the template for a local `.env` with API keys.
- Mock-based tests run without keys; provider integration tests require valid credentials.
- Set `RUN_LIVE_TESTS=1` to enable live API tests (e.g., `BuiltInToolsLiveTests`).

## Commit & Pull Request Guidelines
- Commit messages in git history are short, imperative, sentence case (for example, “Add automatic retry mechanism…”).
- PRs should include: a concise summary, test results (command + outcome), and linked issues.
- If you touch UI in `AISDKChat`/`AISDKVision`, include screenshots or screen recordings.
- Update relevant docs in `docs/` or `Sources/AISDK/docs/` when behavior changes.

## Versioning
- Follow [Semantic Versioning](https://semver.org/) (semver.org).
- Tag format: `X.Y.Z` or `X.Y.Z-prerelease` (no `v` prefix -- SPM requires bare semver).
- CHANGELOG follows [Keep a Changelog](https://keepachangelog.com/) format.
- `main` branch: active v2 development. `release/1.x` branch: v1 maintenance only.

## CI/CD
- CI runs `swift build` + `swift test` (macOS) and `xcodebuild build` (iOS Simulator) on PRs.
- Integration tests auto-skip in CI when API keys are absent (uses `XCTSkip`).
- Pushing a semver tag triggers the release workflow (build, test, create GitHub Release).

## Security & Configuration
- Never commit `.env` files or API keys; keep secrets local and documented in `Tests/env.example`.

## Architecture References
- Start with `docs/AISDK-ARCHITECTURE.md` for module relationships and data flow.

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
5. **Document Results**: Add review section to `tasks/todo.md`.
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections.

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.
