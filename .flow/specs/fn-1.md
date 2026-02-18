# fn-1 AISDK 2.0 Modernization

## Overview

Modernize AISDK Swift SDK to achieve feature parity with Vercel AI SDK 6.x while maintaining 99.99% uptime for healthcare applications. This is a comprehensive 53-task, 8-phase epic covering adapters, core protocols, provider routing, reliability, agents, generative UI, testing, and documentation.

## Scope

**In Scope**:
- Phase 0: Adapter Layer (safe migration for existing consumers)
- Phase 1: Core Protocol Layer (unified API surface)
- Phase 2: Provider & Routing Layer (OpenRouter primary, LiteLLM secondary)
- Phase 3: Reliability Layer (circuit breaker, failover, 99.99% uptime)
- Phase 4: Agent & Tools (actor-based, Sendable-compliant)
- Phase 5: Generative UI (json-render pattern, Core 8 components)
- Phase 6: Testing Infrastructure (stress, memory leak, integration)
- Phase 7-8: Documentation & Polish

**Out of Scope**:
- Voice/Vision modules (separate epics)
- macOS/watchOS targets (iOS only)
- Custom UI components beyond Core 8

## Approach

### Architecture Decisions

| Area | Decision | Rationale |
|------|----------|-----------|
| Concurrency | Actor-based with ObservableState | Thread safety + UI reactivity |
| Streaming | Bounded AsyncThrowingStream (1000 cap) | Memory safety |
| Routing | OpenRouter primary | Managed, production-ready |
| Failover | Capability-aware with cost constraints | Reliability + cost control |
| Tools | Immutable Sendable protocol | Concurrency safety |
| UI | json-render pattern with Core 8 | Progressive enhancement |

### Key Patterns

1. **SafeAsyncStream**: All streams use bounded buffers with proper cancellation
2. **ObservableAgentState**: `@Observable` class bridging actor state to SwiftUI
3. **PHI Protection**: Provider allowlists prevent sensitive data leakage
4. **Adapter Layer**: Existing LLM/Agent/Tool wrapped for backward compatibility

### Reuse Points

- `Sources/AISDK/Core/Models/AIStreamEvent.swift` - Already has 14 Vercel-compatible events
- `Sources/AISDK/LLMs/LLMModelProtocol.swift` - 31 capability flags
- `Sources/AISDK/Errors/AISDKError.swift` - Complete error taxonomy
- `Sources/AISDK/Tools/Tool.swift` - ToolMetadata types

## Quick commands

```bash
# Build the SDK
swift build

# Run tests
swift test

# Run specific test target
swift test --filter AISDKTests
```

## Acceptance

- [ ] All 53 tasks completed and passing tests
- [ ] Feature parity with Vercel AI SDK 6.x core features
- [ ] 99.99% uptime validated via chaos testing
- [ ] P99 < 200ms overhead in benchmark tests
- [ ] 80%+ test coverage on core modules
- [ ] Zero memory leaks in stress tests
- [ ] Zero data races in concurrency tests
- [ ] Migration guide complete with code examples
- [ ] All existing consumers can migrate via adapters

## References

- [Vercel AI SDK 6.x Docs](https://sdk.vercel.ai/docs)
- [Swift Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/)
- [OpenRouter API](https://openrouter.ai/docs)
- `docs/planning/AISDK-PRD.md` - Product Requirements
- `docs/planning/aisdk-modernization-spec-v3-final.md` - Technical Specification

## Risk Register

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Actor reentrancy corruption | High | Critical | Operation queue, assertions |
| Memory leak in streams | Medium | High | SafeAsyncStream, leak tests |
| PHI leakage in failover | Medium | Critical | Provider allowlists, audit |
| Breaking changes impact | Low | High | Adapter layer (Phase 0) |
