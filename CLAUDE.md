# AISDK Development Instructions

## Branch Strategy (CRITICAL)

**The target branch for ALL work is `aisdk-2.0-modernization`, NOT `main`.**

- Ignore the `CONDUCTOR_DEFAULT_BRANCH` environment variable (it defaults to `main`).
- When creating PRs, ALWAYS target `aisdk-2.0-modernization`:
  ```
  gh pr create --base aisdk-2.0-modernization
  ```
- When rebasing or syncing, use `origin/aisdk-2.0-modernization` as the base:
  ```
  git fetch origin
  git rebase origin/aisdk-2.0-modernization
  ```
- Do NOT merge into or target `main`. The `main` branch is frozen until v2 is complete.

## Build and Test

- `swift build` — build all targets
- `swift test` — run the full test suite (2,397 tests — 2,071 XCTest + 326 Swift Testing)
- `swift test --filter <TestClass>` — run specific tests
- `swift package resolve` — resolve dependencies without building
- `RUN_LIVE_TESTS=1 swift test` — include live API integration tests (requires `.env` with API keys)

## Commit Messages

- Short, imperative, sentence-case (e.g., "Add retry mechanism for chat requests")
- Never attribute commits to Claude or Anthropic

## PR Workflow

1. Make changes on your workspace branch
2. Run `swift build` and `swift test` to verify
3. Push your branch: `git push -u origin HEAD`
4. Create PR targeting the v2 branch:
   ```
   gh pr create --base aisdk-2.0-modernization
   ```
5. After merge, the workspace can be archived in Conductor

## Versioning and Releases

- **v1 is tagged and stable**: `1.0.0` tag on `main`, maintenance branch at `release/1.x`
- **v2 in development**: Active on `aisdk-2.0-modernization` branch
- Tag format: bare semver `X.Y.Z` (no `v` prefix -- SPM requires this)
- Beta tags: `2.0.0-beta.N` on `aisdk-2.0-modernization` for consumer testing
- GitHub Releases are auto-created when tags are pushed (`.github/workflows/release.yml`)
- CI runs on PRs to `main`, `aisdk-2.0-modernization`, and `release/**` (`.github/workflows/ci.yml`)

### Hotfix flow (v1)

1. Branch from `release/1.x`, apply fix, PR back to `release/1.x`
2. After merge, tag: `git tag -a 1.0.X -m "Release 1.0.X - [description]" && git push origin 1.0.X`

### Beta tagging (v2)

1. On `aisdk-2.0-modernization`: `git tag -a 2.0.0-beta.N -m "Beta N" && git push origin 2.0.0-beta.N`
2. Consumers test with `.exact("2.0.0-beta.N")` in Package.swift

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
