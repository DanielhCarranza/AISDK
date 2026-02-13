# AISDK Test Suite Documentation

## Overview

The AISDK test suite provides comprehensive testing coverage across all SDK features: LLM providers, agents, computer use, sessions, reliability patterns, generative UI, MCP, skills, tools, and more. Tests use both XCTest and Swift Testing frameworks.

## Test Summary

| Metric | Value |
|--------|-------|
| **Total Tests** | **2,249** |
| XCTest tests | 1,997 |
| Swift Testing tests | 252 |
| XCTest suites | 163 |
| Swift Testing suites | 42 |
| **Success Rate** | **100%** |
| **Failures** | **0** |

## Test Structure

```
Tests/AISDKTests/
├── Agents/                    # Agent unit tests (65+ tests)
│   ├── AgentTests.swift
│   ├── ComputerUseAgentTests.swift
│   ├── AgentHandoffTests.swift
│   ├── AgentStreamingTests.swift
│   ├── AgentToolExecutionTests.swift
│   └── ObservableAgentStateTests.swift
├── Anthropic/                 # Anthropic provider tests (42+ tests)
│   ├── AnthropicServiceTests.swift
│   ├── AnthropicServiceRealAPITests.swift
│   ├── AnthropicServiceStreamingTests.swift
│   ├── AnthropicServiceToolsTests.swift
│   ├── AnthropicServiceSearchResultsTests.swift
│   └── ... (types, batch, files, thinking, models)
├── Core/
│   ├── Providers/             # Provider adapter tests (236+ tests)
│   │   ├── OpenAIClientAdapterTests.swift
│   │   ├── AnthropicClientAdapterTests.swift
│   │   ├── GeminiClientAdapterTests.swift
│   │   ├── OpenRouterClientTests.swift
│   │   ├── LiteLLMClientTests.swift
│   │   ├── ProviderContractTests.swift
│   │   └── ProviderClientTests.swift
│   └── Reliability/           # Reliability pattern tests (269+ tests)
│       ├── FaultInjectorTests.swift
│       ├── RetryPolicyTests.swift
│       ├── AdaptiveCircuitBreakerTests.swift
│       ├── FailoverExecutorTests.swift
│       ├── TimeoutPolicyTests.swift
│       └── ProviderHealthMonitorTests.swift
├── Errors/                    # Error handling tests (42 tests)
│   └── AIErrorTests.swift
├── GenerativeUI/              # Generative UI tests (323+ tests)
│   ├── UICatalogTests.swift          # 80 tests
│   ├── UISnapshotTests.swift         # 65 tests
│   ├── GenerativeUIViewModelTests.swift # 48 tests
│   ├── UITreeTests.swift             # 32 tests
│   ├── UIComponentRegistryTests.swift # 30 tests
│   └── ... (integration, views, components)
├── Integration/               # Live API integration tests (37+ tests)
│   ├── BuiltInToolsLiveTests.swift
│   ├── ComputerUseLiveTests.swift
│   ├── ReasoningE2ETests.swift
│   └── OpenRouterIntegrationTests.swift
├── LLMTests/                  # Core LLM tests (30+ tests)
│   ├── BasicChatTests.swift
│   ├── StreamingChatTests.swift
│   ├── MultimodalTests.swift
│   ├── StructuredOutputTests.swift
│   └── Providers/             # Provider-specific tests (384+ tests)
│       ├── OpenAI/ (Responses API, streaming, tools, file manager)
│       ├── Gemini/ (caching, error mapping, structured output)
│       └── Anthropic/ (caching)
├── Models/                    # Data model tests (155+ tests)
│   ├── AIUsageTests.swift
│   ├── AITraceContextTests.swift
│   ├── AIProviderAccessTests.swift
│   └── ... (requests, results, config)
├── MCP/                       # Model Context Protocol tests (54+ tests)
│   ├── MCPTests.swift
│   └── MCPIntegrationTests.swift
├── Sessions/                  # Session management tests (149+ tests)
│   ├── Models/SessionTests.swift
│   ├── ViewModels/ChatViewModelTests.swift
│   ├── Services/SessionCompactionServiceTests.swift
│   ├── Stores/ (InMemory, FileSystem, SQLite)
│   └── Export/SessionExportTests.swift
├── Skills/                    # Skill system tests (92+ tests)
│   ├── SkillValidatorTests.swift
│   ├── SkillRegistryTests.swift
│   ├── SkillPromptBuilderTests.swift
│   └── SkillParserTests.swift
├── Stress/                    # Stress tests (16 tests)
│   ├── ConcurrencyStressTests.swift
│   └── OpenRouterStressTests.swift
├── Tools/                     # Tool system tests (67+ tests)
│   ├── ToolCallRepairTests.swift
│   ├── AIParameterTests.swift
│   ├── ToolTests.swift
│   └── WebSearchToolTests.swift
├── Mocks/                     # Test infrastructure (no test methods)
│   ├── MockLLMProvider.swift
│   └── MockOpenAIResponsesProvider.swift
└── Fixtures/                  # Test data
    ├── StreamEventFixtures.swift
    └── ResponsesAPIFixtures.swift
```

## Test Categories

### By Feature Area

| Category | Tests | Key Suites |
|----------|-------|------------|
| Generative UI | ~323 | UICatalog (80), UISnapshot (65), ViewModel (48) |
| LLM Providers | ~384 | OpenAI, Anthropic, Gemini, OpenRouter, LiteLLM |
| Core Reliability | ~269 | FaultInjector, RetryPolicy, CircuitBreaker, Failover |
| Provider Adapters | ~236 | Client adapters, contracts, encoding/parsing |
| Models | ~155 | Usage, TraceContext, ProviderAccess, Requests |
| Sessions | ~149 | Session stores, compaction, export, viewmodels |
| Skills & Tools | ~159 | Validator, Registry, ToolCallRepair, AIParameter |
| Agents | ~65 | Agent, ComputerUse, Handoff, Streaming, Tools |
| MCP | ~54 | Client, Integration, Schema, Transport |
| Integration (Live) | ~37 | BuiltInTools, ComputerUse, Reasoning, OpenRouter |
| Errors | ~42 | AIError comprehensive coverage |
| Stress | ~16 | Concurrency, OpenRouter rate limiting |

### By Test Type

- **Unit Tests** (~2,100): Fast, mocked dependencies, no API keys needed
- **Integration Tests** (~100): Real API calls, require API keys in `.env`
- **Stress Tests** (~16): Concurrency and rate limiting scenarios
- **Live Tests** (~37): Require `RUN_LIVE_TESTS=1` env var

## Running Tests

```bash
# Run complete test suite
swift test

# Run with live API tests enabled
RUN_LIVE_TESTS=1 swift test

# Run specific test class
swift test --filter AgentIntegrationTests

# Run specific test method
swift test --filter testOpenAIBasicChat
```

## Environment Setup

Create a `.env` file in the project root (see `env.example`):

```bash
OPENAI_API_KEY=your_key          # Required for OpenAI integration tests
ANTHROPIC_API_KEY=your_key       # Required for Anthropic integration tests
OPENROUTER_API_KEY=your_key      # Required for OpenRouter integration tests
TAVILY_API_KEY=your_key          # Required for web search tests
```

- Tests skip gracefully via `XCTSkip` when API keys are missing
- Mock-based tests run without any keys
- Live tests additionally require `RUN_LIVE_TESTS=1`

## Recent Additions (PRs #29 & #30)

### PR #29: Computer Use Tools
- `ComputerUseTests.swift` (47 tests) - Unit tests for computer use models
- `ComputerUseMappingTests.swift` (14 tests) - Provider mapping tests
- `ComputerUseAgentTests.swift` (9 tests) - Agent integration
- `ComputerUseLiveTests.swift` (8 tests) - Live API validation

### PR #30: Agent Sessions
- `SessionTests.swift` (30 tests) - Session model tests
- `ChatViewModelTests.swift` (22 tests) - ViewModel tests
- `SessionCompactionServiceTests.swift` (20 tests) - Compaction strategies
- `FileSystemSessionStoreTests.swift` (18 tests) - File persistence
- `SQLiteSessionStoreTests.swift` (17 tests) - SQLite persistence
- `InMemorySessionStoreTests.swift` (16 tests) - In-memory store
- `SessionExportTests.swift` (14 tests) - Export functionality
- `SessionLiveValidationTests.swift` (12 tests) - Live validation

---

*Last Updated: February 13, 2026*
*Test Suite Version: 2.0*
*Total Tests: 2,249 | Success Rate: 100% | All Features: COMPLETE*
