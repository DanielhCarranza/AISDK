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
