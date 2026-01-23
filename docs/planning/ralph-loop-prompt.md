# AISDK Modernization - Ralph Autonomous Implementation Prompt

**Project**: AISDK Swift SDK Modernization
**Target**: Vercel AI SDK 6.x Feature Parity
**Reliability Target**: 99.99% uptime (Healthcare-grade)
**Total Tasks**: 53 across 8 phases
**Timeline**: 15 weeks

---

## Context

You are implementing a comprehensive modernization of the AISDK Swift SDK for an AI doctor application. The SDK must achieve feature parity with Vercel AI SDK 6.x while maintaining healthcare-grade reliability.

### Key Architecture Decisions (IMMUTABLE)

| Area | Decision | Rationale |
|------|----------|-----------|
| Concurrency | Actor-based with ObservableState | Thread safety + UI reactivity |
| Streaming | Bounded AsyncThrowingStream (1000 buffer) | Memory safety |
| Routing | OpenRouter primary, LiteLLM secondary | Managed, production-ready |
| Failover | Capability-aware with cost constraints | Reliability + cost control |
| Tools | Immutable Sendable protocol (static execute) | Concurrency safety |
| UI | json-render pattern with Core 8 components | Progressive enhancement |
| Default Model | GPT-5-mini (model-agnostic design) | Cost-effective default |

---

## Execution Instructions

### Phase Order

Execute phases in this order. Some phases can run in parallel:

```
Week 1:     Phase 0 (Adapters)
Weeks 2-3:  Phase 1 (Core Protocols + Testing Mocks)
Weeks 4-5:  Phase 2 (Routing) ──┬── can parallel
Weeks 6-7:  Phase 3 (Reliability) ◄─┘
Weeks 8-9.5: Phase 4 (Agents) ──┬── can parallel
Weeks 10-11: Phase 5 (Gen UI) ◄──┘
Week 12:    Phase 6 (Testing Infrastructure)
Weeks 13-14: Phase 7 (Documentation)
Week 15:    Phase 8 (Buffer & Polish)
```

### Section Files

Each phase has a detailed section file with tasks, code, and acceptance criteria:

| Section | File | Tasks |
|---------|------|-------|
| Phase 0 | `sections/01-adapters.md` | 3 tasks |
| Phase 1 | `sections/02-core-protocols.md` | 13 tasks |
| Phase 2 | `sections/03-providers-routing.md` | 8 tasks |
| Phase 3 | `sections/04-reliability.md` | 7 tasks |
| Phase 4 | `sections/05-agents-tools.md` | 7 tasks |
| Phase 5 | `sections/06-generative-ui.md` | 7 tasks |
| Phase 6 | `sections/07-testing.md` | 4 tasks |
| Phase 7 | `sections/08-documentation.md` | 4 tasks |

### Task Execution Pattern

For each task:

1. **Read Section File**: Load the relevant section file for full task details
2. **Check Dependencies**: Verify prerequisite tasks are complete
3. **Read Context Files**: Load files listed in "Context Files" section
4. **Write Tests First**: Create test file before implementation
5. **Implement**: Write the implementation following code in section
6. **Verify**: Run tests and ensure acceptance criteria pass
7. **Commit**: Commit with descriptive message (no attribution)

### File Locations

All new files go in:
```
Sources/AISDK/
├── Core/
│   ├── Protocols/          # AILanguageModel, etc.
│   ├── Models/             # AITextRequest, AIStreamEvent, etc.
│   ├── Errors/             # AIError
│   ├── Configuration/      # AISDKConfiguration
│   ├── Utilities/          # SafeAsyncStream
│   ├── Telemetry/          # AISDKObserver
│   ├── Adapters/Legacy/    # Phase 0 adapters
│   └── Reliability/        # Circuit breaker, failover
├── Providers/
│   ├── OpenRouter/         # OpenRouterClient
│   ├── LiteLLM/            # LiteLLMClient
│   └── Adapters/           # OpenAI, Anthropic, Gemini adapters
├── Agents/                 # AIAgent
├── Tools/                  # AITool protocol
└── GenerativeUI/           # UI components

Tests/AISDKTests/
├── Core/                   # Protocol tests
├── Integration/            # Real API tests
├── Stress/                 # Concurrency tests
├── Memory/                 # Leak detection tests
├── Mocks/                  # MockAILanguageModel
└── Helpers/                # FaultInjector, simulateStream
```

---

## Critical Implementation Rules

### 1. Actor Safety

Always use operation queues for reentrancy protection:

```swift
public actor AIAgent {
    private var operationQueue: [AIOperation] = []
    private var isProcessing = false

    public func execute(messages: [AIMessage]) async throws -> AIAgentResult {
        // Queue if already processing
        if isProcessing {
            return try await withCheckedThrowingContinuation { continuation in
                operationQueue.append(AIOperation(messages: messages, continuation: continuation))
            }
        }

        isProcessing = true
        defer {
            isProcessing = false
            processNextInQueue()
        }

        return try await executeInternal(messages: messages)
    }
}
```

### 2. Bounded Streams

Always use SafeAsyncStream with bounded policy:

```swift
// CORRECT
let stream = SafeAsyncStream.make(bufferingPolicy: .bounded(capacity: 1000)) { continuation in
    // ...
}

// WRONG - unbounded can cause memory issues
let stream = AsyncThrowingStream { continuation in
    // ...
}
```

### 3. Sendable Compliance

All types crossing actor boundaries must be Sendable:

```swift
// CORRECT
public struct AITextRequest: Sendable, Codable {
    public let messages: [AIMessage]
}

// WRONG - not Sendable
public class AITextRequest {
    public var messages: [AIMessage]
}
```

### 4. Tool Protocol Pattern

Tools must be stateless with static execution:

```swift
// CORRECT
public protocol AITool: Sendable {
    associatedtype Arguments: Codable & Sendable
    static func execute(arguments: Arguments) async throws -> AIToolResult<Metadata>
}

// WRONG - mutable state
public protocol Tool {
    mutating func setParameters(_ params: [String: Any])
    func execute() async throws -> String
}
```

### 5. PHI Protection

Always check data sensitivity before failover:

```swift
func selectProvider(for request: AITextRequest) throws -> ProviderClient {
    // Respect PHI constraints
    if let allowed = request.allowedProviders {
        let filtered = providers.filter { allowed.contains($0.id) }
        guard !filtered.isEmpty else {
            throw AIError.configuration(message: "No allowed providers available")
        }
        return filtered.first!
    }
    return providers.first!
}
```

### 6. Error Handling

Use the AIError taxonomy consistently:

```swift
public enum AIError: Error, Sendable, Equatable {
    case network(statusCode: Int, message: String)
    case authentication(provider: String, message: String)
    case rateLimit(provider: String, retryAfter: TimeInterval?)
    case timeout(operation: String, duration: TimeInterval)
    case invalidRequest(field: String, reason: String)
    case toolExecution(toolName: String, underlying: String)
    case cancelled
    case configuration(message: String)
    case unknown(message: String)
}
```

---

## Testing Requirements

### Test Categories

1. **Unit Tests**: Use MockAILanguageModel, no network
2. **Integration Tests**: Real API calls (skip if no API key)
3. **Stress Tests**: 100+ concurrent operations
4. **Memory Tests**: Verify proper deallocation

### Running Tests

```bash
# All tests
swift test

# By category
swift test --filter "Unit"
swift test --filter "Integration"
swift test --filter "Stress"
swift test --filter "Memory"
```

### Required Test Coverage

- Core protocols: 100% coverage
- Error paths: 100% coverage
- Agents: 80%+ coverage
- UI components: Snapshot tests

---

## Verification Checklist

Before marking a phase complete:

- [ ] All tasks in section file implemented
- [ ] All tests passing
- [ ] No compiler warnings
- [ ] Sendable compliance verified
- [ ] Memory leak tests pass
- [ ] Documentation updated

---

## Commit Guidelines

- No attribution to Claude or Anthropic
- Use conventional commit format:
  - `feat: Add AILanguageModel protocol`
  - `fix: Resolve race condition in circuit breaker`
  - `test: Add concurrency stress tests`
  - `docs: Update migration guide`

---

## Recovery Instructions

If stuck or encountering errors:

1. **Compilation Error**: Check Sendable compliance, actor isolation
2. **Test Failure**: Read error message, check mock configuration
3. **Memory Leak**: Verify stream cancellation handling
4. **Race Condition**: Add actor isolation or use operation queue
5. **API Error**: Check API key, use mock for development

---

## Start Command

Begin implementation with:

```
Read docs/planning/sections/01-adapters.md
Execute Phase 0, Task 0.1: AILanguageModelAdapter
```

---

## Success Criteria

Project is complete when:

1. All 53 tasks implemented and tested
2. `swift test` passes with 0 failures
3. Integration tests pass with real API
4. Memory tests show no leaks
5. Stress tests show no races
6. Documentation complete with tutorials
7. Migration guide verified with example app
