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
- `swift test` — run the full test suite
- `swift test --filter <TestClass>` — run specific tests
- `swift package resolve` — resolve dependencies without building

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
