# fn-1.12 Task 1.9: AISDKConfiguration

## Description
Centralized SDK configuration with startup validation and fail-fast semantics. Provides:
- Provider configurations (OpenAI, Anthropic, Google, OpenRouter)
- Reliability settings (timeouts, retries, circuit breaker, failover)
- Telemetry configuration (logging, metrics, sampling)
- PHI protection enforcement
- Stream buffer policy defaults
- Builder pattern for fluent configuration

## Acceptance
- [x] AISDKConfiguration struct with validation on init
- [x] AIProviderConfiguration for per-provider settings
- [x] AIReliabilityConfiguration for circuit breaker/retry/failover
- [x] AITelemetryConfiguration for observability
- [x] AISDKConfigurationError for validation errors
- [x] Fail-fast validation catches issues at startup
- [x] Builder pattern for fluent API
- [x] Provider presets (.openai, .anthropic, .google, .openRouter)
- [x] Shared instance with configure() method
- [x] API key resolution from explicit value or environment variable
- [x] Builds without errors

## Done summary
Implemented AISDKConfiguration at Sources/AISDK/Core/Configuration/AISDKConfiguration.swift providing centralized SDK configuration with:
- Full provider configuration (API keys, base URLs, rate limits, PHI trust)
- Reliability configuration (timeouts, retries, circuit breaker, failover)
- Telemetry configuration (logging, metrics, sampling with PHI-safe defaults)
- Comprehensive validation with descriptive errors
- Builder pattern for ergonomic configuration
- Provider presets for common providers
- Static shared instance pattern with fail-fast validation

## Evidence
- Commits: (pending)
- Tests: All 138 existing tests pass
- PRs:
