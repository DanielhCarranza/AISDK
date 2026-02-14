# AISDK 2.0 Production Testing Strategy

**Date:** 2026-02-14
**Status:** Draft
**Participants:** Joel Mushagasha

---

## What We're Building

A comprehensive, layered testing strategy to validate that AISDK 2.0 is production-ready for real iOS applications. The SDK currently has 2,249 unit/integration tests and a CLI for manual testing, but lacks validation that it works correctly on real devices, in real apps, under real-world conditions.

This strategy must answer: "How do we know this SDK actually works in production?" - not just "do the tests pass?"

### Success Criteria

- Every SDK feature is validated on-device, not just in test harnesses
- Provider API drift is detected automatically before it reaches users
- Latency, throughput, and memory benchmarks exist with regression tracking
- Streaming reliability is proven under real network conditions
- A developer can integrate the SDK by following our demo app as a reference
- Confidence level: 99.99% request success rate for valid API calls

---

## Why This Approach

### Chosen: Layered Validation Pyramid

We chose a four-layer testing pyramid where each layer catches what the layers below cannot:

```
                    +-------------------+
                    | Layer 4: Contract |  Provider drift detection
                    |   Tests (CI)      |  (scheduled, ~$0.05/day)
                    +-------------------+
                  +------------------------+
                  | Layer 3: Comprehensive  |  Full feature coverage
                  |   Demo App              |  (reference implementation)
                  +------------------------+
              +-------------------------------+
              | Layer 2: SDK Eval Harness      |  Correctness, benchmarks,
              |   (headless, CI-friendly)      |  streaming integrity
              +-------------------------------+
          +--------------------------------------+
          | Layer 1: Smoke Test App               |  "Does it even work?"
          |   (SwiftUI, <200 lines, 30 seconds)   |  on-device gate
          +--------------------------------------+
      +--------------------------------------------+
      | Foundation: 2,249 Unit & Integration Tests   |  Logic correctness
      |   (existing, runs on every PR)               |  (already built)
      +--------------------------------------------+
```

### Why Not Alternatives

- **Single reference app**: Mixing demo and test concerns makes both harder to maintain. UI test flakiness would erode trust in the test suite.
- **Contract-first with snapshots**: Good for provider drift but misses on-device issues entirely. We added contract tests as Layer 4 instead of making it the whole strategy.

---

## Key Decisions

### 1. Layer 1 - Smoke Test App

**Purpose:** Quick on-device validation that the SDK fundamentally works. Run in 30 seconds. This is the "did we ship something broken?" gate.

**What it covers:**
- Connect to each provider (OpenAI, Anthropic, Gemini, OpenRouter)
- Stream a single response and verify chunks arrive
- Execute one tool call and verify the result
- Create an agent session and send a message
- Render a basic generative UI component

**Structure:**
```
SmokeTestApp/
├── SmokeTestApp.swift          # App entry point
├── ProviderSmokeTest.swift     # Test each provider connection
├── StreamingSmokeTest.swift    # Verify streaming works
├── ToolCallSmokeTest.swift     # Verify tool execution
├── SessionSmokeTest.swift      # Verify session persistence
└── ResultsView.swift           # Pass/fail dashboard
```

**Key constraints:**
- No complex UI - just a results list showing pass/fail per test
- Each test has a 10-second timeout
- Requires `.env` with at least one provider API key
- Runs on both simulator and physical device
- Must work with `swift build` (macOS) and Xcode (iOS)

### 2. Layer 2 - SDK Eval Harness

**Purpose:** Automated correctness and performance evaluation. Headless, runs in CI, produces structured reports. This is where benchmarks live.

**What it measures:**

**Correctness Evals:**
- Streaming chunk integrity (no gaps, no duplicates, finish reason received)
- Tool call JSON parsing accuracy across all providers
- Error type correctness (timeout vs rate limit vs auth vs server error)
- Retry behavior verification (backoff timing, max attempts, circuit breaker state)
- Session serialization/deserialization roundtrip fidelity
- Multi-turn conversation state consistency

**Performance Benchmarks:**
- Time to First Token (TTFT) - p50, p95, p99 per provider
- Tokens per second during streaming
- Total request latency per provider
- Memory delta per request (detect leaks)
- Peak memory during concurrent requests
- Connection establishment time

**Reliability Metrics:**
- Request success rate over N requests (target: 99.99%)
- Graceful degradation under simulated network chaos
- Circuit breaker trip/recovery timing
- Failover latency between providers

**Output format:** JSON report with pass/fail + metrics, suitable for CI comparison against baselines.

### 3. Layer 3 - Comprehensive Demo App

**Purpose:** Full-featured reference app that exercises every SDK surface. Doubles as developer documentation ("here's how to use every feature"). Also the closest thing to testing in a real app before integrating with the AI doctor app.

**What it covers:**
- Multi-turn chat with streaming (all providers)
- Agent workflows with tool use and handoffs
- Generative UI rendering and interaction
- MCP server connections
- Session persistence and restoration
- Skills system integration
- Provider switching mid-conversation
- Error states and recovery UI
- Background/foreground handling
- Network transition handling (WiFi to cellular)

**Structure:**
```
DemoApp/
├── DemoApp.swift
├── Features/
│   ├── ChatView.swift           # Multi-turn streaming chat
│   ├── AgentView.swift          # Agent with tools
│   ├── GenerativeUIView.swift   # UITree rendering
│   ├── MCPView.swift            # MCP connections
│   ├── SessionView.swift        # Session management
│   ├── ProviderPicker.swift     # Switch providers
│   └── BenchmarkView.swift      # Run benchmarks on-device
├── Shared/
│   ├── SDKSetup.swift           # Provider configuration
│   └── ErrorHandling.swift      # Error display patterns
└── Resources/
    └── SampleSkills/            # Example skills for testing
```

**DX validation checklist** (use this app to verify developer experience):
- [ ] Can a new developer get the app running in < 5 minutes?
- [ ] Are error messages actionable (not just "request failed")?
- [ ] Is provider switching intuitive?
- [ ] Does streaming feel smooth (no UI jank)?
- [ ] Is the API surface predictable (no surprising behaviors)?
- [ ] Does autocomplete/documentation appear correctly in Xcode?

### 4. Layer 4 - Provider Contract Tests

**Purpose:** Detect when a provider's API changes shape before it breaks production apps. Runs on a schedule (daily) against real provider APIs with minimal token usage.

**What it validates per provider:**
- Response schema matches expected structure (required fields present)
- Streaming format hasn't changed (chunk shape, delta format)
- Tool call response format is still compatible
- Error response format is parseable
- Rate limit headers are present and parseable
- API versioning headers are correct

**Cost management:**
- Each provider test: 1 completion (5 max tokens) + 1 streaming request (5 max tokens) + 1 tool call
- Estimated cost per run: ~$0.01-0.03 across all providers
- Monthly cost at daily cadence: ~$0.30-0.90

**Implementation approach:**
```swift
// Minimal contract test per provider
func testProviderContract(_ provider: AILanguageModel) async throws {
    // 1. Basic completion
    let response = try await provider.complete(
        messages: [.user("Say hi")],
        maxTokens: 5
    )
    try validateResponseSchema(response)

    // 2. Streaming
    var chunks: [StreamChunk] = []
    for try await chunk in provider.stream(
        messages: [.user("Say hi")],
        maxTokens: 5
    ) {
        chunks.append(chunk)
    }
    try validateStreamingSchema(chunks)

    // 3. Tool calling
    let toolResponse = try await provider.complete(
        messages: [.user("What's the weather?")],
        tools: [weatherTool],
        maxTokens: 50
    )
    try validateToolCallSchema(toolResponse)
}
```

**Alert mechanism:** CI job fails and sends notification when a contract breaks. Include the specific field/format that changed in the failure message.

### 5. Device vs. Simulator Testing Strategy

Based on industry research, different test types need different environments:

| Test Type | Simulator | Real Device | Notes |
|-----------|-----------|-------------|-------|
| Unit tests | Primary | - | Speed matters, run on every PR |
| Integration tests | Primary | Weekly | Simulator is fine for API logic |
| Streaming tests | Quick check | Primary | Network stack differs on device |
| Memory tests | Acceptable | Monthly | Simulator memory model is close enough |
| Performance benchmarks | Never | Primary | Timing is meaningless on simulator |
| Background handling | Never | Primary | Simulator doesn't simulate backgrounding realistically |
| Network transitions | Never | Primary | WiFi/cellular switching doesn't exist on simulator |

### 6. Memory Leak Detection

**Automated in CI:**
- After 100 sequential requests, measure memory delta
- If delta > 10MB, flag as potential leak
- Track memory baselines over time, alert on regression

**On-device profiling (manual, monthly):**
- Instruments Allocations + Leaks during a 30-minute chat session
- Profile with multiple providers
- Check for retain cycles in streaming closures and agent callbacks

### 7. Chaos Testing (Reliability Layer)

Test SDK behavior under adversarial conditions:
- **Network timeout mid-stream:** Verify stream terminates cleanly with error
- **Provider returns 500:** Verify retry logic activates, circuit breaker trips
- **Rate limit (429):** Verify backoff respects Retry-After header
- **Invalid API key:** Verify error is actionable, not a crash
- **Memory pressure warning:** Verify SDK doesn't crash, degrades gracefully
- **App backgrounded during stream:** Verify stream resumes or errors cleanly

---

## Implementation Priority

**Phase 1 (Week 1-2): Foundation**
1. Build the Smoke Test App (Layer 1) - validates basic on-device operation
2. Add Provider Contract Tests (Layer 4) - catches drift immediately
3. Set up CI workflow for contract tests on daily schedule

**Phase 2 (Week 3-4): Depth**
4. Build the SDK Eval Harness (Layer 2) - benchmarks and correctness
5. Establish performance baselines per provider
6. Add memory leak detection to CI

**Phase 3 (Week 5-6): Breadth**
7. Build the Comprehensive Demo App (Layer 3)
8. Write DX validation checklist and test with a fresh developer
9. Add chaos testing scenarios

**Phase 4 (Ongoing): Maintenance**
10. Monitor contract tests daily
11. Update benchmarks baselines quarterly
12. Refresh demo app when new features are added

---

## Resolved Questions

1. **CI infrastructure:** Manual device testing for now. CI stays simulator-only. A self-hosted macOS runner with a connected device is a future option if it's free/cheap. Joel has physical devices available for manual testing.

2. **Provider priority:** Focus testing on **OpenAI, Anthropic, and Gemini** (top 3). OpenRouter and LiteLLM get minimal/smoke-level testing. The BYOM (bring your own model) path must also be tested to ensure the SDK is model-agnostic.

3. **Public demo app:** Keep private for now. Make public when the SDK launches. The smoke test and basic examples can go public sooner.

4. **Benchmark storage:** Simple JSON files committed to the repo. Easy, version-controlled, no external dependencies.

## Open Questions

_(None remaining - all questions resolved.)_

---

## References

- OpenAI SDK testing patterns: ecosystem tests across runtimes, retry/resilience tests, breaking change detection
- Anthropic engineering: self-evaluation loops, rules-based feedback
- Industry contract testing: consumer-driven contracts for API drift detection
- iOS device testing: Simulator limitations for networking, memory, backgrounding
- Automated memory leak detection via UI tests (Showmax Engineering, Pol Piella)
