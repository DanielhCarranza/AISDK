# fn-1.24 Task 2.8: ProviderContractTests

## Description
Implement comprehensive contract tests that verify all ProviderClient implementations (OpenAI, Anthropic, Gemini) behave consistently according to the ProviderClient protocol contract.

## Acceptance
- [x] Identity contract tests (providerId, displayName, baseURL uniqueness)
- [x] Health status contract tests (initial unknown, isAvailable logic)
- [x] Capabilities contract tests (known models, streaming support)
- [x] Model availability contract tests (known models, pattern recognition)
- [x] Stream contract tests (valid streams, nonisolated requirement)
- [x] Sendable contract tests (concurrent usage verification)
- [x] Request/response construction contract tests
- [x] Error contract tests (all cases have descriptions)
- [x] Stream event contract tests (conversion to AIStreamEvent)
- [x] Provider-specific tests for OpenAI, Anthropic, Gemini

## Done summary
Implemented ProviderContractTests for Phase 2.8 routing layer verification.

Key features:
- 50 comprehensive contract tests across 4 test classes
- ProviderContractTests: Core contract verification for all providers
- OpenAIContractTests: OpenAI-specific capability tests (vision, reasoning)
- AnthropicContractTests: Anthropic-specific tests (Claude model families)
- GeminiContractTests: Gemini-specific tests (2.5-pro, 2.0-flash)
- Tests cover identity, health, capabilities, streaming, Sendable conformance
- Request/response construction validation
- Error taxonomy and stream event conversion tests

## Evidence
- Commits: 645faf22d70fb7f93e20dff86ffc370ca9a3e90f
- Tests: swift test --filter "ProviderContractTests|OpenAIContractTests|AnthropicContractTests|GeminiContractTests" (50 tests pass)
- PRs:
