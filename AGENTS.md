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
- XCTest is the standard framework (see `Tests/AISDKTests/README.md`).
- Use `Tests/env.example` as the template for a local `.env` with API keys.
- Mock-based tests run without keys; provider integration tests require valid credentials.

## Commit & Pull Request Guidelines
- Commit messages in git history are short, imperative, sentence case (for example, “Add automatic retry mechanism…”).
- PRs should include: a concise summary, test results (command + outcome), and linked issues.
- If you touch UI in `AISDKChat`/`AISDKVision`, include screenshots or screen recordings.
- Update relevant docs in `docs/` or `Sources/AISDK/docs/` when behavior changes.

## Security & Configuration
- Never commit `.env` files or API keys; keep secrets local and documented in `Tests/env.example`.

## Architecture References
- Start with `docs/AISDK-ARCHITECTURE.md` for module relationships and data flow.
