# What's New in AISDK 2.0

## Executive Summary

AISDK 2.0 is a **comprehensive modernization** bringing the Swift AI SDK to feature parity with Vercel AI SDK 6.x. This is not a minor update - it's a fundamental architectural upgrade with:

- **21,237 lines** of new source code (42 new files)
- **23,960 lines** of new tests (39 new test files)
- **8 major new subsystems** added

---

## What Changed vs AISDK 1.0

| Area | AISDK 1.0 | AISDK 2.0 |
|------|-----------|-----------|
| **Agent System** | Class-based `Agent.swift` | Actor-based `Agent` (thread-safe) |
| **Concurrency** | GCD/Completion handlers | Swift Concurrency (async/await) |
| **Streaming** | Callback-based | `AsyncThrowingStream` with bounded buffers |
| **State Management** | KVO/Delegates | `@Observable` pattern for SwiftUI |
| **Sessions** | None | Pluggable persistence (InMemory, File, SQLite) |
| **Context Management** | None | Auto-compaction (truncate/summarize/sliding window) |
| **Reliability** | None | Full circuit breaker + failover chain |
| **UI Generation** | None | Generative UI with json-render pattern |
| **Telemetry** | None | `AISDKObserver` with tracing |
| **Provider Routing** | Direct calls | OpenRouter primary, LiteLLM secondary |
| **Error Handling** | Basic | Comprehensive `AIError` taxonomy |
| **Testing** | Unit only | Stress, memory leak, integration tests |

---

## New Components Added

### 1. Actor-Based Agent System
**File:** `Sources/AISDK/Agents/Agent.swift`

The heart of AISDK 2.0 - a fully thread-safe, actor-based agent.

```swift
// Before (1.0) - Class-based, not thread-safe
let agent = Agent(llm: provider)
let response = try await agent.send("Hello")

// After (2.0) - Actor-based, thread-safe
let agent = Agent(model: model, instructions: "You are helpful.")
let result = try await agent.execute(messages: [AIMessage(role: .user, content: .text("Hello"))])
```

**Key Features:**
- Thread-safe concurrent execution
- Streaming with `streamExecute(messages:)`
- Tool execution with `Tool` protocol
- Sendable-compliant

---

### 2. Provider System (OpenRouter + LiteLLM)
**Files:**
- `OpenRouterClient.swift` (948 lines)
- `LiteLLMClient.swift` (981 lines)
- `ProviderClient.swift` (736 lines)
- `ModelRegistry.swift` (682 lines)

**New Unified Provider API:**
```swift
// OpenRouter - Primary provider
let client = OpenRouterClient(apiKey: key)
let response = try await client.execute(request: request)

// Streaming
for try await event in client.stream(request: request) {
    switch event {
    case .textDelta(let text): print(text)
    case .finish: break
    default: break
    }
}
```

**Provider Adapters for existing code:**
- `OpenAIClientAdapter.swift` (1,025 lines)
- `AnthropicClientAdapter.swift` (1,040 lines)
- `GeminiClientAdapter.swift` (872 lines)

---

### 3. Reliability Layer (99.99% Uptime Target)
**Files in `Sources/AISDK/Core/Reliability/`:**

| Component | Lines | Purpose |
|-----------|-------|---------|
| `AdaptiveCircuitBreaker.swift` | 555 | Prevents cascading failures |
| `FailoverExecutor.swift` | 454 | Executes across provider chain |
| `CapabilityAwareFailover.swift` | 368 | Smart failover with cost constraints |
| `RetryPolicy.swift` | 410 | Exponential backoff retries |
| `TimeoutPolicy.swift` | 274 | Request/stream timeouts |
| `ProviderHealthMonitor.swift` | 343 | Tracks provider health metrics |
| `FaultInjector.swift` | 709 | Chaos testing for reliability |

**Usage:**
```swift
let executor = FailoverExecutorBuilder()
    .with(providers: [openaiClient, anthropicClient])
    .with(healthMonitor: monitor)
    .build()

// Automatically retries and fails over
let result = try await executor.executeRequest(request: request)
```

---

### 4. Generative UI System
**Files in `Sources/AISDK/GenerativeUI/`:**

| Component | Lines | Purpose |
|-----------|-------|---------|
| `UICatalog.swift` | 674 | Component registry |
| `Core8Components.swift` | 661 | 8 core UI components |
| `UITree.swift` | 531 | JSON to UI tree parser |
| `UIComponentRegistry.swift` | 812 | Custom component registration |
| `GenerativeUIViewModel.swift` | 455 | Observable view model |
| `GenerativeUIView.swift` | 387 | SwiftUI rendering |

**The "Core 8" Components:**
1. `Text` - Display text content
2. `Button` - Interactive buttons
3. `Card` - Container with title/subtitle
4. `Input` - Text input fields
5. `List` - Ordered/unordered lists
6. `Image` - Image display
7. `Stack` - Layout container
8. `Spacer` - Flexible spacing

**How it works:**
```swift
// LLM generates JSON
{
  "root": "main",
  "elements": {
    "main": { "type": "Stack", "children": ["title", "btn"] },
    "title": { "type": "Text", "props": { "content": "Hello!" } },
    "btn": { "type": "Button", "props": { "title": "Click Me" } }
  }
}

// SDK renders as native SwiftUI
GenerativeUIView(viewModel: viewModel)
```

---

### 5. Modern Core Models
**Files in `Sources/AISDK/Core/Models/`:**

| Model | Lines | Purpose |
|-------|-------|---------|
| `AITextRequest.swift` | 214 | Text generation request |
| `AITextResult.swift` | 82 | Text generation result |
| `AIObjectRequest.swift` | 190 | Structured output request |
| `AIObjectResult.swift` | 98 | Structured output result |
| `AIStreamEvent.swift` | ~280 | 20+ Vercel-compatible events |
| `AIStepResult.swift` | 137 | Agent step results |
| `AIUsage.swift` | 206 | Token usage tracking |
| `AITraceContext.swift` | 476 | Distributed tracing |

**Stream Events (Vercel AI SDK Compatible):**
```swift
enum AIStreamEvent {
    case start(metadata: AIStreamMetadata?)
    case textDelta(String)
    case textCompletion(String)
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, argumentsDelta: String)
    case toolCall(id: String, name: String, arguments: String)
    case toolResult(id: String, result: String, metadata: ToolMetadata?)
    case finish(finishReason: AIFinishReason, usage: AIUsage)
    case error(Error)
    // ... plus reasoning, objectDelta, source, file, usage, stepStart/Finish, uiPatch, computerUseAction, webSearch events
}
```

---

### 6. Modern Tool System
**Files:**
- `Tool.swift` - Sendable-compliant tool protocol
- `ToolCallRepair.swift` - Auto-fix malformed tool calls

**Tool Protocol:**
```swift
protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    static var parameters: ParameterSchema { get }
    func execute(arguments: String) async throws -> ToolResult
}
```

---

### 7. Telemetry & Observability
**Files:**
- `AISDKObserver.swift` (381 lines)
- `AITraceContext.swift` (476 lines)

```swift
// Track operations with tracing
let observer = AISDKObserver()
observer.onRequestStart = { request in
    print("Request started: \(request.id)")
}
observer.onRequestEnd = { result in
    print("Completed in \(result.latency)ms")
}
```

---

### 8. Session Persistence & Context Management
**Files in `Sources/AISDK/Sessions/`** (16 files, ~2,500 lines)

Full conversation persistence with pluggable storage backends, streaming integration, context compaction, and SwiftUI ViewModels.

| Component | Purpose |
|-----------|---------|
| `AISession` (struct) | Core session model with messages, checkpoints, metadata |
| `SessionStore` protocol | Pluggable persistence (InMemory, FileSystem, SQLite) |
| `ChatViewModel` | `@Observable` ViewModel integrating agent + store + streaming |
| `SessionListViewModel` | Paginated session list with filtering |
| `SessionCompactionService` | Context window management (truncate/summarize/sliding window) |
| `StreamingPersistenceBuffer` | Debounced writes during streaming (500ms) |
| `SessionTitleGenerator` | LLM-powered auto-titling |
| `SessionExport` | JSON and Markdown export/import |

**Usage:**
```swift
let store = SQLiteSessionStore(path: dbPath)
let session = try await AISession.create(userId: "user_1", store: store)

let vm = ChatViewModel(agent: myAgent, store: store, session: session)
await vm.send("Hello!")  // Streams response, persists automatically
```

**Three built-in stores:**
```swift
InMemorySessionStore()            // Tests and previews
FileSystemSessionStore(directory:) // Simple file-based persistence
SQLiteSessionStore(path:)          // Production (WAL mode, indexes)
```

---

### 9. Safe Async Utilities
**File:** `SafeAsyncStream.swift` (344 lines)

Bounded async streams that prevent memory leaks:
```swift
// Bounded buffer (max 1000 elements) with proper cancellation
let stream = SafeAsyncStream<String>(bufferSize: 1000)
```

---

### 10. Legacy Adapters (Backward Compatibility)
**Files in `Sources/AISDK/Core/Adapters/Legacy/`:**

| Adapter | Lines | Purpose |
|---------|-------|---------|
| `AIAgentAdapter.swift` | 544 | Wrap old Agent for new API |
| `AILanguageModelAdapter.swift` | 528 | Wrap old LLM for new API |
| `AIUsage+Legacy.swift` | 26 | Usage conversion |

> Tools are now unified under `AITool`. Migrate legacy tools to `AITool` directly (there is no ToolAdapter).

**Migration path:**
```swift
// Your existing 1.0 code
let legacyLLM = OpenAIProvider(apiKey: key)

// Wrap with adapter
let adapted = AILanguageModelAdapter(
    llm: legacyLLM,
    provider: "openai",
    modelId: "gpt-4o"
)

// Use with new agent
let agent = Agent(model: adapted)
```

---

## New Test Infrastructure

### Test Categories Added

| Category | Lines | Purpose |
|----------|-------|---------|
| **Agent Tests** | 2,153 | Agent actor comprehensive tests |
| **Reliability Tests** | 3,732 | Circuit breaker, failover, retry |
| **Generative UI Tests** | 6,471 | UI catalog, tree, rendering |
| **Provider Tests** | 3,560 | OpenRouter, LiteLLM, adapters |
| **Stress Tests** | TBD | Concurrent execution, memory |
| **Integration Tests** | TBD | Real API validation |

### Real API Integration Tests (Verified Working)

| Test | Model | Status |
|------|-------|--------|
| Basic Chat | 3 free models | Passing |
| Streaming | Nemotron | Passing |
| JSON Output | DeepSeek | Passing |
| Reasoning | DeepSeek | Passing |
| Tool Calling | Trinity Mini | Passing |

---

## Comparison with Vercel AI SDK 6.x

| Feature | Vercel AI SDK 6.x | AISDK 2.0 | Parity |
|---------|-------------------|-----------|--------|
| `generateText()` | Yes | `execute()` | Yes |
| `streamText()` | Yes | `streamExecute()` | Yes |
| `generateObject<T>()` | Yes | `AIObjectRequest` | Yes |
| Stream Events | 14 types | 20+ types | Better |
| Tool Calling | Yes | `Tool` | Yes |
| Multi-step Agents | Yes | `Agent` (actor) | Yes |
| Provider Abstraction | Yes | `ProviderClient` | Yes |
| Circuit Breaker | No | Yes | Better |
| Failover Chain | No | Yes | Better |
| Generative UI | Experimental | Core 8 | Yes |
| Session Persistence | No | 3 built-in stores | Better |
| Context Compaction | No | 3 strategies | Better |
| PHI Protection | No | Allowlists | Better |

---

## What We Tested Against Real Models

### OpenRouter Free Tier Models

| Model | Chat | Stream | JSON | Reasoning | Tools |
|-------|------|--------|------|-----------|-------|
| `tngtech/deepseek-r1t2-chimera:free` | Yes | Yes | Yes | Yes | No |
| `nvidia/nemotron-3-nano-30b-a3b:free` | Yes | Yes | Yes | Yes | Yes (auto) |
| `arcee-ai/trinity-mini:free` | Yes | Yes | Yes | Yes | Yes |

### What's Verified Working
1. OpenRouterClient - chat, streaming, JSON, tools
2. Agent actor - basic execution
3. Stream events - all 20+ types
4. Tool calling - with `tool_choice: .auto`

### What Still Needs Real Model Testing
1. Reliability layer (circuit breaker, failover)
2. Generative UI rendering
3. Stress/memory tests
4. LiteLLM client
5. Provider adapters (OpenAI, Anthropic, Gemini)

---

## Summary: AISDK 2.0 is Modernized

### What's Actually New (Not Just Renamed)
- **Actor-based concurrency** - Complete rewrite of agent system
- **Session persistence** - Brand new (3 stores, streaming integration, checkpoints)
- **Context management** - Brand new (compaction, title generation, export)
- **Reliability layer** - Brand new (circuit breaker, failover, retry)
- **Generative UI** - Brand new (json-render pattern)
- **Provider routing** - Brand new (OpenRouter/LiteLLM abstraction)
- **Telemetry** - Brand new (tracing, observability)
- **Safe streaming** - Brand new (bounded async streams)

### Lines of Code Added
| Category | Lines Added |
|----------|-------------|
| Source Code | 21,237 |
| Tests | 23,960 |
| **Total** | **45,197** |

### This is Real Modernization Because:
1. **Architecture change** - Actor-based vs class-based
2. **Concurrency model** - Swift Concurrency vs GCD
3. **New subsystems** - Reliability, GenUI, Telemetry didn't exist
4. **Vercel AI SDK parity** - Same patterns and APIs
5. **Production features** - Circuit breakers, failover for 99.99% uptime

---

## Demo Commands

```bash
# Run the comprehensive demo
swift run AISDKDemo --mode showcase

# Interactive chat (ask your own questions)
swift run AISDKDemo --mode interactive

# OpenRouter demo
swift run OpenRouterDemo --mode all

# Run integration tests
swift test --filter OpenRouterIntegrationTests
```

---

## Migration Guide

For detailed migration instructions, see [MIGRATION-GUIDE.md](./MIGRATION-GUIDE.md).

For architecture details, see [AISDK-ARCHITECTURE.md](./AISDK-ARCHITECTURE.md).
