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
- **2,249 tests** across 205 suites (1,997 XCTest + 252 Swift Testing), 100% pass rate.
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
- `release/1.x` branch: v1 maintenance only. `aisdk-2.0-modernization`: active v2 development.

## CI/CD
- CI runs `swift build` + `swift test` (macOS) and `xcodebuild build` (iOS Simulator) on PRs.
- Integration tests auto-skip in CI when API keys are absent (uses `XCTSkip`).
- Pushing a semver tag triggers the release workflow (build, test, create GitHub Release).

## Security & Configuration
- Never commit `.env` files or API keys; keep secrets local and documented in `Tests/env.example`.

## Architecture References
- Start with `docs/AISDK-ARCHITECTURE.md` for module relationships and data flow.
