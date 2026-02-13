# AISDK API Reference

> Complete API documentation for AISDK 2.0

## Overview

AISDK is a Swift framework for building AI-powered applications with a unified interface for language models, agents, tools, and generative UI.

## Quick Links

| Section | Description |
|---------|-------------|
| [Core Protocols](core-protocols.md) | AILanguageModel, AIAgent, AITool |
| [Models](models.md) | AIMessage, AITextRequest, AITextResult, AIStreamEvent |
| [Providers](providers.md) | OpenRouterClient, ProviderClient protocol |
| [Agents](agents.md) | AIAgentActor, ObservableAgentState, StopCondition |
| [Tools](tools.md) | AITool protocol, AIToolRegistry, AIToolResult |
| [Computer Use](computer-use.md) | ComputerUseAction, ComputerUseResult, agent handler |
| [Reliability](reliability.md) | AdaptiveCircuitBreaker, FailoverExecutor, RetryPolicy |
| [Sessions](sessions.md) | AISession, SessionStore, ChatViewModel, context compaction |
| [Generative UI](generative-ui.md) | UICatalog, UITree, Core 8 components |
| [Errors](errors.md) | AISDKErrorV2, AIErrorCode, ProviderError |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Application Layer                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ AIAgentActor │  │GenerativeUI  │  │ Custom Tools     │  │
│  └──────┬───────┘  │  ViewModel   │  └────────┬─────────┘  │
│         │          └──────┬───────┘           │            │
│  ┌──────┴──────────────────────────────────────┘            │
│  │           Sessions & Persistence Layer                   │
│  │  ChatViewModel │ SessionStore │ CompactionService        │
│  └──────┬──────────────────────────────────────┐            │
├─────────┼─────────────────┼───────────────────┼────────────┤
│         │     Reliability Layer               │            │
│  ┌──────┴───────────────────────────┴─────────┴──────┐    │
│  │  CircuitBreaker │ FailoverExecutor │ RetryPolicy  │    │
│  └────────────────────────┬──────────────────────────┘    │
├───────────────────────────┼────────────────────────────────┤
│                    Provider Layer                           │
│  ┌────────────────────────┴────────────────────────────┐  │
│  │     OpenRouterClient  │  LiteLLMClient  │ Custom    │  │
│  └─────────────────────────────────────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                    Core Protocols                           │
│  ┌─────────────────┐ ┌─────────────────┐ ┌──────────────┐ │
│  │ AILanguageModel │ │    AIAgent      │ │   AITool     │ │
│  └─────────────────┘ └─────────────────┘ └──────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Key Concepts

### Unified Message Format

All providers use `AIMessage` with standardized roles and content types:

```swift
let message = AIMessage.user("Hello, world!")
let multimodal = AIMessage.user(parts: [
    .text("What's in this image?"),
    .imageURL("https://example.com/image.jpg")
])
```

### Actor-Based Concurrency

Agent execution uses Swift actors for thread-safe state management:

```swift
let agent = AIAgentActor(model: client, tools: [MyTool.self])
let result = try await agent.execute(messages: [.user("Hello")])
```

### Protocol-Oriented Design

Core functionality is defined through protocols for flexibility:

```swift
protocol AILanguageModel: Actor, Sendable { ... }
protocol AITool: Sendable { ... }
protocol AIAgent: Sendable { ... }
```

## Package Import

```swift
import AISDK
```

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.0+
- Xcode 16.0+

## Type Safety

AISDK leverages Swift's type system:

- **Sendable**: All types crossing concurrency boundaries are Sendable
- **Codable**: Request/response types are Codable for serialization
- **Property Wrappers**: Tools use `@AIParameter` for typed, validated arguments

## Next Steps

- Start with [Core Protocols](core-protocols.md) for foundational types
- See [Models](models.md) for request/response structures
- Check [Agents](agents.md) for building AI workflows
- See [Sessions](sessions.md) for persistence and context management
