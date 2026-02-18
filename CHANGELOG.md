# Changelog

All notable changes to AISDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0-beta.1] - 2026-02-17

### Added

#### Universal Message System
- Cross-provider message format (`AIInputMessage`) with consistent API across all LLM providers
- Unified content types: text, images, audio, files, and video with automatic provider-specific conversion
- Provider conversion extensions for OpenAI (Chat + Response API), Anthropic, and Gemini
- Order-aware multimodal content (text + image + text sequences preserved)
- Type-safe tool call system (`AIToolCall`) with provider-specific conversion

#### Actor-Based Agent (v2)
- New `Agent` actor with Swift 6 concurrency, SwiftUI-bindable state via `@Observable`
- Configurable stop conditions, timeout policies, and operation queue
- `RequestOptions` for per-request configuration
- `streamExecute()` returning `AsyncThrowingStream<AIAgentEvent, Error>`

#### LLM Protocol
- Unified `LLM` protocol (`generateText`, `streamText`, `generateObject`, `streamObject`)
- `ProviderLanguageModelAdapter` for v2 provider clients (OpenRouter, LiteLLM)
- `AILanguageModelAdapter` bridging legacy providers to v2 `LLM` protocol
- `LLMCapabilities` option set: `.text`, `.vision`, `.tools`, `.streaming`, `.reasoning`, `.computerUse`, `.structuredOutputs`, `.webSearch`, `.caching`, and more

#### Provider Clients (v2)
- `OpenRouterClient` — 200+ models via single API key
- `LiteLLMClient` — self-hosted proxy support
- Full `ProviderClient` actor protocol with streaming and structured output

#### Reliability
- `RetryPolicy` with configurable backoff strategies
- `AdaptiveCircuitBreaker` for provider failure isolation
- `FailoverExecutor` with capability-aware failover
- `ProviderHealthMonitor` and `TimeoutPolicy`
- `FaultInjector` for testing reliability under failure

#### Generative UI
- Spec-driven UI generation framework
- Progressive rendering bridge for incremental streaming updates
- Component catalog, registry, and spec stream engine
- `@Observable` view models with SwiftUI views

#### Sessions and Persistence
- `SessionStore` protocol with InMemory, FileSystem, and SQLite implementations
- `SessionCompactionService` for automatic context compaction
- `StreamingPersistenceBuffer` for streaming state management
- Session export capabilities

#### MCP Integration
- `MCPClient` for Model Context Protocol server communication
- `MCPServerConfiguration` for multi-server setup
- Full MCP message type support

#### Skills System
- Skill registry, validator, and parser
- Prompt builder for skill-based interactions

#### SwiftUI Modernization
- iOS 17+ `@Observable` pattern replacing `@ObservableObject/@Published`
- Selective view updates with automatic dependency tracking

#### v1 Backward Compatibility
- Typealiases: `ChatMessage`, `AgentState`, `Message`, `ResearcherAgentState`
- `LegacyAgent` class preserved for gradual migration
- `LegacyChatMessage` and `LegacyAgentState` available alongside v2 types
- Legacy adapter layer (`AIAgentAdapter`, `AILanguageModelAdapter`) bridges v1 usage to v2 internals

#### Testing
- 2,397 tests (2,071 XCTest + 326 Swift Testing), all passing
- Integration, stress, and provider contract test suites

### Breaking Changes
- `ChatMessage` renamed to `LegacyChatMessage` (typealias provided)
- `AgentState` renamed to `LegacyAgentState` (typealias provided)
- `Message` renamed to `LegacyMessage` (typealias provided)
- `ResearcherAgentState` renamed to `ResearcherLegacyAgentState` (typealias provided)
- Tool `execute()` return type changed from `(content: String, metadata: ToolMetadata?)` to `ToolResult`
- Minimum platforms: iOS 17+, macOS 14+, watchOS 10+, tvOS 17+

### Migration
- See [docs/MIGRATION-GUIDE.md](docs/MIGRATION-GUIDE.md) for full migration instructions
- Consumers must use `.exact("2.0.0-beta.1")` in Package.swift — SPM does not resolve pre-release versions with range-based requirements

---

## [1.0.0] - 2025-06-28

### Added

#### Core AISDK Features
- Multi-provider LLM support: OpenAI, Anthropic (Claude), and Google Gemini
- Unified agent system with state management and callbacks
- Advanced tool framework with UI rendering via `RenderableTool` protocol
- Streaming support with Server-Sent Events (SSE)
- Modern Swift architecture: Swift Concurrency, `@Observable`, SwiftUI

#### Model Management
- Universal model protocol for all LLM providers
- Provider-specific models: OpenAI (GPT-4.1, GPT-4o, o4-mini, o3), Anthropic (Claude 4, 3.7, 3.5), Google (Gemini 2.5, 2.0, 1.5)
- Capability-based selection and performance tier classification

#### AISDKChat Module
- Session-based conversations with persistent storage
- Pre-built SwiftUI views: `ChatCompanionView`, `MessageBubble`, `AttachmentPreviewBar`, `TypingIndicator`
- Flexible storage protocol with Firebase, Supabase, and custom adapters
- Attachment system for images, PDFs, and files

#### AISDKVoice Module
- Native speech recognition with AVFoundation and Speech framework
- Voice activity detection and text-to-speech
- Voice UI components: `AIVoiceModeView`, `AnimatedTranscriptView`

#### AISDKVision Module
- LiveKit integration for real-time video streaming
- Camera management and agent video interaction

#### AISDKResearch Module
- Specialized research agents for analysis tasks
- Evidence management, medical record analysis, biomarker tools

#### Developer Experience
- Comprehensive documentation and demo applications
- Test suite with API integration tests
- Multiplatform support: iOS 17+, macOS 14+, watchOS 10+, tvOS 17+

### Dependencies
- Alamofire 5.8.0+ (networking)
- SwiftyJSON 5.0.0+ (JSON handling)
- MarkdownUI 2.0.0+ (chat UI)
- Charts 5.0.0+ (data visualization)
- LiveKit 2.0.0+ (vision features)
