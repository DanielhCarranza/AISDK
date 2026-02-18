# Phase 7: Documentation

**Duration**: 2 weeks
**Tasks**: 4
**Dependencies**: All previous phases

---

## Goal

Create comprehensive documentation with architecture docs, migration guide, tutorials, and API reference.

---

## Tasks

### Task 7.1: Update AISDK-ARCHITECTURE.md

**Location**: `docs/AISDK-ARCHITECTURE.md`
**Complexity**: 4/10
**Dependencies**: All phases

**Sections to Update/Add**:

1. **Executive Summary** - Updated capabilities
2. **Module Structure** - New Core module hierarchy
3. **Protocol Layer** - AILanguageModel, AIStreamEvent, etc.
4. **Provider Architecture** - OpenRouter/LiteLLM routing
5. **Reliability Layer** - Circuit breakers, failover
6. **Agent System** - Actor-based, multi-step
7. **Generative UI** - json-render pattern, Core 8
8. **Testing Infrastructure** - Test categories
9. **Diagrams** - Updated architecture diagrams

---

### Task 7.2: Write Migration Guide

**Location**: `docs/MIGRATION-GUIDE.md`
**Complexity**: 5/10
**Dependencies**: All phases

```markdown
# AISDK Migration Guide

## Overview

This guide covers migration from AISDK 1.x to AISDK 2.0.

## Breaking Changes

### 1. Agent API

**Before (1.x)**:
```swift
let agent = Agent(provider: provider, tools: [WeatherTool.self])
let response = try await agent.send("What's the weather?")
```

**After (2.0)**:
```swift
let agent = AIAgent(
    model: OpenRouterClient(),
    tools: [WeatherTool.self],
    stopCondition: .stepCount(10)
)
let result = try await agent.execute(messages: [.user("What's the weather?")])
```

### 2. Streaming

**Before (1.x)**:
```swift
let stream = try await provider.sendChatCompletionStream(request: request)
for try await chunk in stream {
    print(chunk.choices.first?.delta.content ?? "")
}
```

**After (2.0)**:
```swift
let stream = model.streamText(request: AITextRequest(messages: messages))
for try await event in stream {
    switch event {
    case .textDelta(let text):
        print(text)
    case .finish(let reason, let usage):
        print("Done: \(reason)")
    default:
        break
    }
}
```

### 3. Tool Protocol

**Before (1.x)**:
```swift
struct WeatherTool: AITool {
    @Parameter(description: "City name")
    var location: String

    func execute() async throws -> AIToolResult {
        // ...
    }
}
```

**After (2.0)**:
```swift
struct WeatherTool: AITool {
    let name = "get_weather"
    let description = "Get weather for a city"

    @AIParameter(description: "City name")
    var location: String = ""

    init() {}

    func execute() async throws -> AIToolResult {
        // ...
    }
}
```

## Adapter Layer (Optional)

For gradual migration, use adapters:

```swift
// Wrap legacy provider
let legacyProvider = OpenAIProvider(apiKey: "...")
let modernModel = AILanguageModelAdapter(legacyProvider: legacyProvider, modelInfo: .gpt4o)

// Wrap legacy agent
let legacyAgent = Agent(provider: legacyProvider, tools: tools)
let modernAgent = AIAgentAdapter(legacyAgent: legacyAgent)

// Tools migrate directly to AITool (no adapter layer)
```

## Step-by-Step Migration

### Step 1: Update Provider Initialization

Replace direct provider usage with OpenRouterClient.

### Step 2: Update Message Types

Replace `ChatMessage` with `AIMessage`.

### Step 3: Update Error Handling

Replace `AISDKError` with `AIError`.

### Step 4: Update Tool Definitions

Convert @Parameter-based tools to AITool protocol.

### Step 5: Update Agent Usage

Replace Agent with AIAgentActor.

### Step 6: Update Streaming Code

Replace chunk-based streaming with event-based.
```

---

### Task 7.3: Write Tutorials

**Location**: `docs/tutorials/`
**Complexity**: 6/10
**Dependencies**: All phases

**7 Tutorials**:

1. **01-getting-started.md** - Installation, basic usage
2. **02-streaming-basics.md** - Streaming events, handling
3. **03-tool-creation.md** - Creating tools, validation
4. **04-multi-step-agents.md** - Agent loops, callbacks
5. **05-generative-ui.md** - Dynamic UI generation
6. **06-reliability-patterns.md** - Failover, circuit breakers
7. **07-testing-strategies.md** - Mocks, integration tests

**Example Tutorial Structure**:

```markdown
# Tutorial 01: Getting Started

## Prerequisites
- Xcode 15+
- iOS 17+ / macOS 14+
- OpenRouter API key

## Installation

Add to Package.swift:
```swift
dependencies: [
    .package(url: "https://github.com/example/AISDK", from: "2.0.0")
]
```

## Basic Usage

### 1. Configure the SDK

```swift
import AISDK

// Validate configuration (fails fast if API key missing)
let config = try AISDKConfiguration.validated()
```

### 2. Create a Model Client

```swift
let model = OpenRouterClient()
```

### 3. Generate Text

```swift
let request = AITextRequest(
    messages: [
        .system("You are a helpful assistant"),
        .user("Hello!")
    ]
)

let result = try await model.generateText(request: request)
print(result.text)
```

### 4. Stream Text

```swift
for try await event in model.streamText(request: request) {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .finish(let reason, let usage):
        print("\n\nTokens used: \(usage.totalTokens)")
    default:
        break
    }
}
```

## Next Steps

- [Streaming Basics](02-streaming-basics.md)
- [Creating Tools](03-tool-creation.md)
```

---

### Task 7.4: Generate API Reference

**Location**: `docs/api-reference/`
**Complexity**: 4/10
**Dependencies**: All phases

**Structure**:

```
docs/api-reference/
├── index.md               # Overview
├── core-protocols.md      # AILanguageModel, etc.
├── models.md              # AITextRequest, AIStreamEvent
├── providers.md           # OpenRouterClient, LiteLLMClient
├── agents.md              # AIAgent, StopCondition
├── tools.md               # AITool, ToolCallRepair
├── reliability.md         # CircuitBreaker, FailoverExecutor
├── generative-ui.md       # UICatalog, UITree, Components
└── errors.md              # AIError
```

**Example API Reference**:

```markdown
# AIAgent

Multi-step agent with tool execution and streaming support.

## Declaration

```swift
public actor AIAgent {
    public nonisolated let observableState: ObservableAgentState

    public init(
        model: any AILanguageModel,
        tools: [any AITool.Type] = [],
        instructions: String? = nil,
        stopCondition: StopCondition = .stepCount(20),
        repairStrategy: ToolCallRepair.Strategy = .autoRepairOnce,
        timeout: TimeoutPolicy = .default
    )
}
```

## Properties

### `observableState`

Observable state for SwiftUI binding.

```swift
public nonisolated let observableState: ObservableAgentState
```

## Methods

### `execute(messages:)`

Execute agent loop synchronously.

```swift
public func execute(messages: [AIMessage]) async throws -> AIAgentResult
```

**Parameters**:
- `messages`: Initial conversation messages

**Returns**: `AIAgentResult` with final response and step history

**Throws**: `AIError` on failure

### `executeStream(messages:onStepFinish:prepareStep:)`

Execute agent loop with streaming events.

```swift
public func executeStream(
    messages: [AIMessage],
    onStepFinish: @Sendable @escaping (AIStepResult) async -> StepAction = { _ in .continue },
    prepareStep: @Sendable @escaping (Int, [AIMessage]) async -> StepPreparation = { _, _ in .default }
) -> AsyncThrowingStream<AIStreamEvent, Error>
```

**Parameters**:
- `messages`: Initial conversation messages
- `onStepFinish`: Called after each step completes
- `prepareStep`: Called before each step to modify configuration

**Returns**: Stream of `AIStreamEvent`

## Example

```swift
let agent = AIAgent(
    model: OpenRouterClient(),
    tools: [WeatherTool.self, SearchTool.self],
    instructions: "You are a helpful assistant",
    stopCondition: .stepCount(10)
)

// Streaming
let stream = agent.executeStream(
    messages: [.user("What's the weather in Tokyo?")],
    onStepFinish: { result in
        print("Step \(result.stepIndex) complete")
        return .continue
    }
)

for try await event in stream {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .toolResult(let id, let result, _):
        print("Tool result: \(result)")
    default:
        break
    }
}
```
```

---

## Verification

- All documentation builds without errors
- All code examples compile and run
- Links between documents work
- API reference covers all public types
