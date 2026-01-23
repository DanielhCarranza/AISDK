# AISDK Modernization Research Findings

**Generated**: 2026-01-22
**Research Scope**: Codebase deep-dive + Vercel AI SDK 6.x patterns

---

## Part 1: Current AISDK Codebase Analysis

### Executive Summary

The AISDK is a **well-structured, multi-provider LLM SDK** for iOS 17+/macOS 14+ written in Swift. It features a sophisticated protocol-based architecture with support for OpenAI, Anthropic, and Google Gemini providers.

**Current State**: Production-ready with innovative metadata tracking, sophisticated message routing, and provider abstraction.

### 1. Core Protocol Architecture

#### LLM Protocol (Core Interface)

**File**: `Sources/AISDK/LLMs/LLMProtocol.swift`

```swift
public protocol LLM {
    func sendChatCompletion(request: ChatCompletionRequest) async throws -> ChatCompletionResponse
    func sendChatCompletionStream(request: ChatCompletionRequest) async throws -> AsyncThrowingStream<ChatCompletionChunk, Error>
    func generateObject<T: Decodable>(request: ChatCompletionRequest) async throws -> T
}
```

**Strengths**:
- Minimal, focused interface - 3 core methods only
- Provider-agnostic request/response types
- Full async/await support with proper error propagation
- Generic object deserialization (`generateObject<T>`)

**Weaknesses**:
- No built-in retry logic (delegated to providers)
- No rate limiting or quota management
- No authentication abstraction
- Missing metadata/usage tracking in response

#### LLMModelProtocol (Sophisticated Capabilities System)

**File**: `Sources/AISDK/LLMs/LLMModelProtocol.swift` (512 lines)

**31+ Capability Flags** (LLMCapabilities - OptionSet):
- Input/Output: text, vision, audio, video, pdf
- Functional: tools, functionCalling, codeExecution, structuredOutputs, jsonMode
- Advanced: reasoning, thinking, search, webSearch, grounding
- Generation: imageGeneration, audioGeneration, videoGeneration, speechToText, textToSpeech
- Operational: streaming, realtime, liveAPI, caching, tuning, embedding
- Special: moderation, computerUse, multilingual, longContext, deprecated

**Strengths**:
- Extremely extensible capability system
- Price calculation helpers
- Well-documented model tiers and latencies
- Clear separation between provider identification and performance traits

**Weaknesses**:
- Only partially implemented across providers (OpenAI complete, Anthropic/Gemini minimal)
- Model deprecation tracking could be more granular

---

### 2. Provider Implementations Analysis

#### OpenAI Provider (Most Mature) ⭐⭐⭐⭐⭐

**File**: `Sources/AISDK/LLMs/OpenAI/OpenAIProvider.swift` (661 lines)

**Key Features**:
- Model-aware initialization with smart defaults (gpt-4o)
- Environment variable fallback for API key
- Complete chat completion (non-streaming + streaming)
- Generic object generation with schema validation
- Responses API support with streaming
- SSE parsing with proper line buffering

**Weaknesses**:
- Heavy debugging output left in production code
- No request deduplication for retries

#### Anthropic Provider ⭐⭐⭐⭐

**File**: `Sources/AISDK/LLMs/Anthropic/AnthropicProvider.swift` (367 lines)

- Uses OpenAI compatibility layer
- Enforces Claude-specific constraints (n=1, temp <= 1.0)
- **Issue**: Complete code duplication with OpenAI provider streaming

#### Gemini Provider ⭐⭐⭐

**File**: `Sources/AISDK/LLMs/Gemini/GeminiProvider.swift` (344 lines)

- Uses native Google AI API
- Built-in retry logic (configurable)
- File upload support
- **Issue**: Returns `AsyncCompactMapSequence` instead of `AsyncThrowingStream` (inconsistent API)

---

### 3. Agent System Analysis

**File**: `Sources/AISDK/Agents/Agent.swift` (656 lines)

#### State Machine
```swift
public enum AgentState: Equatable {
    case idle
    case thinking
    case executingTool(String)
    case responding
    case error(AIError)
}
```

#### Dual Mode Operation
1. **Synchronous**: `send(_ content: String) -> ChatMessage`
2. **Streaming**: `sendStream(_ message: ChatMessage) -> AsyncThrowingStream<ChatMessage, Error>`

#### Tool Execution Flow
1. setState(.thinking)
2. Execute onMessageReceived callback
3. Create ChatCompletionRequest with tool schemas
4. Execute onBeforeLLMRequest callback
5. Get response from LLM
6. Check for tool calls → handleToolCalls() or return text
7. setState(.idle)

#### Callback System

```swift
public protocol AgentCallbacks {
    func onMessageReceived(message: Message) -> CallbackResult
    func onBeforeToolExecution(name: String, arguments: String) -> CallbackResult
    func onAfterToolExecution(name: String, result: String) -> CallbackResult
    func onBeforeLLMRequest(messages: [Message]) -> CallbackResult
    func onStreamChunk(chunk: Message) -> CallbackResult
}

public enum CallbackResult {
    case `continue`
    case cancel
    case replace(Message)
}
```

**Key Innovation**: Messages have `isPending` flag for streaming UI updates.

---

### 4. Tool Framework Analysis

**File**: `Sources/AISDK/Tools/Tool.swift`

```swift
public protocol Tool {
    var name: String { get }
    var description: String { get }
    var returnToolResponse: Bool { get }

    init()
    static func jsonSchema() -> ToolSchema
    func execute() async throws -> (content: String, metadata: ToolMetadata?)
    mutating func setParameters(from arguments: [String: Any]) throws
}
```

**Parameter Wrapper**:
```swift
@propertyWrapper
public class Parameter<Value> {
    public let description: String
    public var wrappedValue: Value
    public var validation: [String: Any]?
}
```

**Metadata System**:
- `RenderMetadata` for UI rendering
- `RawToolMetadata` for unknown types (graceful degradation)
- `AnyToolMetadata` type-erasing wrapper with decoder registry

---

### 5. Error Handling

**File**: `Sources/AISDK/Errors/AISDKError.swift` (235 lines)

**Error Hierarchy**:
- `AISDKError` - Generic SDK errors (invalidURL, httpError, parsingError, streamError)
- `LLMError` - Provider-specific (rateLimitExceeded, authenticationError, contextLengthExceeded)
- `AgentError` - Agent operations (toolExecutionFailed, operationCancelled)
- `ToolError` - Tool execution (invalidParameters, executionFailed, validationFailed)

**HTTP Status Code Mapping**:
```swift
switch responseCode {
case 401: return .authenticationError
case 429: return .rateLimitExceeded
case 400...499: return .networkError(...)
case 500...599: return .networkError(...)
}
```

---

### 6. Key Patterns to PRESERVE

1. **Provider Abstraction via Protocol** - Single `LLM` protocol with multiple implementations
2. **Streaming with AsyncThrowingStream** - Native Swift concurrency
3. **Tool Execution Loop** - Register tools → LLM calls → Execute → Interpret
4. **Message Types (Enum-based)** - Type-safe message handling
5. **Callback System** - Hook points for intercepting/modifying behavior
6. **Metadata Tracking** - Optional metadata for UI rendering

### 7. PAIN POINTS to Address

**Critical**:
1. **Provider Code Duplication** - OpenAI/Anthropic streaming 95% identical
2. **Streaming API Inconsistency** - Gemini returns different type
3. **Tool Registry Namespace Collisions** - Single global registry
4. **Model-Provider Mismatch** - Only OpenAI exposes model property

**Important**:
5. **Metadata System Incomplete** - Only OpenAI fully implements LLMModelProtocol
6. **Error Context Loss** - Errors wrapped multiple times
7. **Rate Limiting** - Not implemented despite protocol support
8. **Tool Parameter Validation** - `validation` field unused

**Architectural**:
9. **No Caching** - Every message sent even if identical
10. **State Machine Not Queryable** - Only observable via callback
11. **Testing with Real APIs** - No VCR-style response recording

---

## Part 2: Vercel AI SDK 6.x Patterns

### 1. Core API Functions

**Primary Functions**:
- `generateText()` - Non-streaming, full completion
- `streamText()` - Streaming with events + callbacks
- `generateObject()` / `streamObject()` - Being consolidated into `output` parameter

**Return Values**:
- Core: `text`, `content`, `toolCalls`, `toolResults`
- Metadata: `finishReason`, `usage`, `totalUsage`
- Streaming: `textStream`, `fullStream` (AsyncIterable)
- Callbacks: `onFinish()`, `onStepFinish()`, `onError()`, `onChunk()`

### 2. Streaming Event Model

**Event Types via `fullStream`**:

```typescript
// Text Events
{ type: 'text-delta', text: string }
{ type: 'text-completion', text: string }

// Tool Call Events
{ type: 'tool-call', id, toolName, args }
{ type: 'tool-call-streaming-start', id }
{ type: 'tool-call-streaming-delta', id, delta }
{ type: 'tool-call-streaming-finish', id }
{ type: 'tool-result', id, result }

// Completion Events
{ type: 'step-finish' }
{ type: 'finish', finishReason, usage }
{ type: 'error', error }
```

**Callbacks**:
- `onChunk(chunk)` - Each text delta
- `onStepFinish(step)` - Step complete (text + tools + results)
- `onFinish(result)` - Generation complete
- `onError(error)` - Stream errors

### 3. Multi-Step Agent Loop (ToolLoopAgent)

```typescript
const agent = new ToolLoopAgent({
  model,
  tools,
  instructions,  // Renamed from 'system' in v6
  stopWhen: stepCountIs(20),  // Default changed to 20
});
```

**Loop Execution**:
1. LLM generation with current history
2. If tool call → execute, add result, loop to step 1
3. If text response → return and exit
4. If `maxSteps` reached → return early
5. If `stopWhen` condition met → return early

**Loop Control Options**:
- `stopWhen: stepCountIs(n)` - Max n steps
- `prepareStep()` - Modify model/tools per step
- `onStepFinish()` - Called after each step

**Tool Call Repair**:
- Failed tool calls included in next message for model to fix
- `experimental_repairToolCall` for custom repair logic

### 4. Provider Abstraction

```typescript
interface ProviderV3 {
  languageModel(modelId: string): LanguageModelV3;
  embeddingModel?(modelId: string): EmbeddingModelV3;
  imageModel?(modelId: string): ImageModelV3;
}

interface LanguageModelV3 {
  specificationVersion: 'V3';
  provider: string;
  modelId: string;
  doGenerate(options): Promise<GenerateResult>;
  doStream(options): Promise<StreamResult>;
}
```

### 5. Structured Output (Consolidated in v6)

```typescript
// New v6 approach
const result = await generateText({
  model,
  output: Output.object({ schema: MySchema }),
});

// Output modes
Output.object({ schema }) - Typed object
Output.array({ element }) - Array of typed objects
Output.json() - Unstructured JSON
Output.text() - Plain text (default)
```

### 6. Testing Approach

**MockLanguageModelV3**:
```typescript
const model = new MockLanguageModelV3({
  doGenerate: async (options) => ({
    text: 'Fixed response',
    finishReason: 'stop',
    usage: { ... }
  })
});
```

**Stream Simulation**:
```typescript
const stream = simulateReadableStream({
  chunks: ['chunk1', 'chunk2', 'chunk3'],
  intervalMs: 100
});
```

---

## Part 3: Swift Adaptation Recommendations

### 1. Core Protocol Layer

```swift
// Like LanguageModelV3
protocol AILanguageModel {
    var provider: String { get }
    var modelId: String { get }

    func generate(request: AITextRequest) async throws -> AITextResult
    func stream(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
}

// Factory
protocol AIProvider {
    func languageModel(_ modelId: String) -> AILanguageModel
}
```

### 2. Streaming Events

```swift
enum AIStreamEvent: Sendable {
    case textDelta(String)
    case textCompletion(String)
    case toolCallStart(id: String, name: String)
    case toolCallDelta(id: String, delta: String)
    case toolCallFinish(id: String, args: String)
    case toolResult(id: String, result: String, metadata: ToolMetadata?)
    case stepFinish(AIStepResult)
    case finish(finishReason: String, usage: AIUsage)
    case error(Error)
}
```

### 3. Agent Loop

```swift
actor AIAgent {
    let model: AILanguageModel
    let tools: [Tool.Type]
    let instructions: String?
    let stopWhen: StopCondition

    func execute(messages: [AIMessage]) async throws -> AIAgentResult
}

enum StopCondition {
    case stepCount(Int)
    case noToolCalls
    case custom((AIStepResult) -> Bool)
}
```

### 4. Output Modes

```swift
enum OutputMode<T: Codable> {
    case text
    case object(schema: T.Type)
    case array(element: T.Type)
    case json
}

func generateText<T: Codable>(
    request: AITextRequest,
    output: OutputMode<T> = .text
) async throws -> AIResult<T>
```

### 5. Testing Infrastructure

```swift
class MockAILanguageModel: AILanguageModel {
    var generateHandler: ((AITextRequest) async throws -> AITextResult)?
    var streamHandler: ((AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>)?
}

func simulateStream(
    events: [AIStreamEvent],
    intervalMs: UInt64 = 100
) -> AsyncThrowingStream<AIStreamEvent, Error>
```

---

## Key Takeaways

### What Vercel Does Well (Adopt)
1. **Unified event model** - Single stream with typed events
2. **Step-based agent loop** - Clear boundaries, configurable stopping
3. **Output consolidation** - Single API with mode parameter
4. **Callbacks at every level** - onChunk, onStepFinish, onFinish
5. **Tool call repair** - Graceful handling of validation failures

### What AISDK Does Well (Preserve)
1. **Protocol-based abstraction** - Clean Swift idioms
2. **Comprehensive capability flags** - 31+ model capabilities
3. **Metadata tracking** - UI rendering integration
4. **Callback system** - Cancel/replace/continue semantics
5. **Message type safety** - Enum-based routing

### Critical Gaps to Close
1. **Streaming event standardization** - All providers must emit same events
2. **Multi-step agent loop** - Add maxSteps, prepareStep, onStepFinish
3. **Tool call repair** - Add validation + repair mechanism
4. **Provider consistency** - Unify streaming return types
5. **Reliability layer** - Add failover, circuit breakers, rate limiting
