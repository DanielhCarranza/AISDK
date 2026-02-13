---
title: "Add Computer Use tool integration (OpenAI/Anthropic)"
type: feat
date: 2026-02-13
issue: "#18"
brainstorm: "docs/brainstorms/2026-02-13-computer-use-integration-brainstorm.md"
---

# Add Computer Use Tool Integration (OpenAI/Anthropic)

## Overview

Add a unified Computer Use tool as a first-class `BuiltInTool` case enabling screen interaction actions (screenshot, click, type, scroll, keypress, drag, move, wait) across Anthropic and OpenAI providers. The SDK provides typed, provider-agnostic `ComputerUseAction` and `ComputerUseResult` types while each provider adapter handles wire-format translation. The Agent class accepts a handler closure for client-side execution of screen actions.

**Scope:** Computer/screen actions only. Anthropic's `text_editor` and `bash` tools are future work as separate `BuiltInTool` cases.

## Problem Statement

The SDK already registers computer use capabilities (`LLMCapabilities.computerUse` at `LLMModelProtocol.swift:73`), Anthropic beta headers (`AnthropicService.swift:85`), and OpenAI model entries (`OpenAIModels.swift:66`), but there is no way for consumers to actually use computer use through the unified API. Consumers would need to bypass the SDK entirely and craft raw provider-specific requests.

## Proposed Solution

Follow the established `BuiltInTool` pattern used by `webSearch`, `codeExecution`, `fileSearch`, and `imageGeneration`:

1. Add `computerUse(ComputerUseConfig)` and `computerUseDefault` to the `BuiltInTool` enum
2. Define typed `ComputerUseAction` enum and `ComputerUseResult` struct
3. Map through provider adapters (Anthropic, OpenAI Responses, reject for Gemini and Chat Completions)
4. Add `computerUseHandler` closure to Agent for client-side action execution
5. Surface actions as `AIStreamEvent.computerUseAction` for observability

## Technical Approach

### Architecture

```
Consumer Code                    SDK Core                         Provider Adapters

AITextRequest                    BuiltInTool.computerUse          AnthropicClientAdapter
  builtInTools: [               -> ComputerUseConfig                -> computer_20250124 tool
    .computerUse(config)        -> kind: "computerUse"               -> beta header auto-add
  ]
                                                                  OpenAIProvider
Agent                            AIStreamEvent                      -> computer_use_preview tool
  computerUseHandler: {           .computerUseAction(action)        -> ResponseTool case
    execute action
    return screenshot            ComputerUseAction enum            GeminiClientAdapter
  }                               .screenshot, .click, ...          -> ProviderError.invalidRequest

                                 ComputerUseResult                OpenAIClientAdapter (Chat)
                                   screenshot, mediaType, text      -> ProviderError.invalidRequest
```

### Implementation Phases

#### Phase 1: Core Types

Define the provider-agnostic types that all other phases depend on.

**File: `Sources/AISDK/Core/Models/ComputerUse/ComputerUseConfig.swift`**

```swift
public extension BuiltInTool {
    struct ComputerUseConfig: Sendable, Equatable, Hashable, Codable {
        /// Display width in pixels (required by both providers)
        public let displayWidth: Int

        /// Display height in pixels (required by both providers)
        public let displayHeight: Int

        /// Environment type (OpenAI-specific: "browser", "mac", "windows", "ubuntu", "linux")
        public let environment: ComputerUseEnvironment?

        /// X11 display number (Anthropic-specific)
        public let displayNumber: Int?

        /// Enable zoom action (Anthropic computer_20251124 only)
        public let enableZoom: Bool?

        public init(
            displayWidth: Int,
            displayHeight: Int,
            environment: ComputerUseEnvironment? = nil,
            displayNumber: Int? = nil,
            enableZoom: Bool? = nil
        ) {
            self.displayWidth = displayWidth
            self.displayHeight = displayHeight
            self.environment = environment
            self.displayNumber = displayNumber
            self.enableZoom = enableZoom
        }
    }

    enum ComputerUseEnvironment: String, Sendable, Equatable, Hashable, Codable {
        case browser
        case mac
        case windows
        case ubuntu
        case linux
    }
}
```

**File: `Sources/AISDK/Core/Models/ComputerUse/ComputerUseAction.swift`**

```swift
/// A unified, provider-agnostic computer use action.
/// Provider adapters translate between this enum and wire format.
public enum ComputerUseAction: Sendable, Equatable {
    case screenshot
    case click(x: Int, y: Int, button: ClickButton = .left)
    case doubleClick(x: Int, y: Int)
    case tripleClick(x: Int, y: Int)
    case type(text: String)
    case keypress(keys: [String])
    case scroll(x: Int, y: Int, scrollX: Int? = nil, scrollY: Int? = nil,
                direction: ScrollDirection? = nil, amount: Int? = nil)
    case move(x: Int, y: Int)
    case drag(path: [Coordinate])
    case wait(durationMs: Int? = nil)
    case cursorPosition
    case zoom(region: [Int]) // [x1, y1, x2, y2]

    /// Safety checks from the provider (OpenAI only; nil for Anthropic)
    public var safetyChecks: [SafetyCheck]?

    public enum ClickButton: String, Sendable, Equatable, Codable {
        case left, right, middle, back, forward, wheel
    }

    public enum ScrollDirection: String, Sendable, Equatable, Codable {
        case up, down, left, right
    }

    public struct Coordinate: Sendable, Equatable, Codable {
        public let x: Int
        public let y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    public struct SafetyCheck: Sendable, Equatable, Codable {
        public let id: String
        public let code: String      // "malicious_instructions", "irrelevant_domain", "sensitive_domain"
        public let message: String
    }
}
```

**Design note on safetyChecks:** Since Swift enums with associated values cannot have stored properties, `safetyChecks` should be modeled as a separate wrapper or as part of a `ComputerUseToolCall` struct that pairs the action with metadata:

```swift
/// Represents a complete computer use tool call from the model
public struct ComputerUseToolCall: Sendable, Equatable {
    public let id: String           // tool call ID for result correlation
    public let callId: String?      // OpenAI-specific call_id
    public let action: ComputerUseAction
    public let safetyChecks: [ComputerUseAction.SafetyCheck]
}
```

**File: `Sources/AISDK/Core/Models/ComputerUse/ComputerUseResult.swift`**

```swift
/// Result returned by the consumer after executing a computer use action.
public struct ComputerUseResult: Sendable, Equatable {
    /// Base64-encoded screenshot image data (typically PNG)
    public let screenshot: String?

    /// Media type of the screenshot
    public let mediaType: ImageMediaType?

    /// Optional text output (e.g., cursor position coordinates)
    public let text: String?

    /// Whether this result represents an error
    public let isError: Bool

    public enum ImageMediaType: String, Sendable, Equatable, Codable {
        case png = "image/png"
        case jpeg = "image/jpeg"
        case gif = "image/gif"
        case webp = "image/webp"
    }

    public init(
        screenshot: String? = nil,
        mediaType: ImageMediaType? = .png,
        text: String? = nil,
        isError: Bool = false
    ) {
        self.screenshot = screenshot
        self.mediaType = mediaType
        self.text = text
        self.isError = isError
    }

    /// Convenience for a screenshot-only result
    public static func screenshot(_ base64: String, mediaType: ImageMediaType = .png) -> ComputerUseResult {
        ComputerUseResult(screenshot: base64, mediaType: mediaType)
    }

    /// Convenience for an error result
    public static func error(_ message: String) -> ComputerUseResult {
        ComputerUseResult(text: message, isError: true)
    }
}
```

- Tasks and deliverables:
  - [ ] Create `Sources/AISDK/Core/Models/ComputerUse/ComputerUseConfig.swift`
  - [ ] Create `Sources/AISDK/Core/Models/ComputerUse/ComputerUseAction.swift`
  - [ ] Create `Sources/AISDK/Core/Models/ComputerUse/ComputerUseResult.swift`
  - [ ] All types conform to `Sendable, Equatable` (and `Codable, Hashable` where needed)
- Success criteria: Types compile, follow existing config struct patterns
- Estimated effort: Small

---

#### Phase 2: BuiltInTool Enum Integration

**File: `Sources/AISDK/Core/Models/BuiltInTool.swift`**

Add two new cases and update `kind`:

```swift
public enum BuiltInTool: Sendable, Equatable, Hashable {
    // ... existing cases ...
    case computerUse(ComputerUseConfig)
    case computerUseDefault
}

// In kind property:
case .computerUse, .computerUseDefault:
    return "computerUse"
```

**`computerUseDefault` rationale:** Include for API consistency with the other built-in tools. The default uses sensible values: `displayWidth: 1024, displayHeight: 768` (XGA, recommended by both providers for minimal scaling issues). Consumers who need specific dimensions use `.computerUse(config)`.

Update the support matrix doc comment:

```
/// | Tool              | OpenAI (Responses) | Gemini | Anthropic              |
/// |-------------------|--------------------|--------|------------------------|
/// | `.computerUse`    | computer_use_prev  | -      | computer_20250124      |
```

- Tasks and deliverables:
  - [ ] Add `computerUse(ComputerUseConfig)` and `computerUseDefault` cases to `BuiltInTool`
  - [ ] Add `"computerUse"` return in `kind` property
  - [ ] Update support matrix doc comment
  - [ ] Verify `Equatable`, `Hashable` conformance with new cases
- Success criteria: `swift build` succeeds (all switch statements will need new cases)
- Estimated effort: Small

---

#### Phase 3: Provider Adapter Mapping (Outbound -- Config to Wire)

##### 3a. Anthropic Adapter

**File: `Sources/AISDK/Core/Providers/AnthropicClientAdapter.swift`**

In `buildRequestBody(from:streaming:)` built-in tools switch (~line 494):

```swift
case .computerUse(let config):
    var toolDict: [String: Any] = [
        "name": "computer"
    ]
    // Select tool version based on enableZoom config
    if config.enableZoom == true {
        toolDict["type"] = "computer_20251124"
        toolDict["enable_zoom"] = true
    } else {
        toolDict["type"] = "computer_20250124"
    }
    toolDict["display_width_px"] = config.displayWidth
    toolDict["display_height_px"] = config.displayHeight
    if let displayNumber = config.displayNumber {
        toolDict["display_number"] = displayNumber
    }
    body.tools?.append(.builtIn(toolDict))

case .computerUseDefault:
    body.tools?.append(.builtIn([
        "type": "computer_20250124",
        "name": "computer",
        "display_width_px": 1024,
        "display_height_px": 768
    ]))
```

In `betaHeaderValue(for:body:)` (~line 263), add auto-beta-header:

```swift
if builtInTools.contains(where: { $0.kind == "computerUse" }) {
    // Use the newer header for enableZoom, standard otherwise
    let hasZoom = builtInTools.contains(where: {
        if case .computerUse(let config) = $0 { return config.enableZoom == true }
        return false
    })
    let header = hasZoom ? "computer-use-2025-11-24" : "computer-use-2025-01-24"
    if !headers.contains(header) {
        headers.append(header)
    }
}
```

##### 3b. OpenAI Responses API

**File: `Sources/AISDK/LLMs/OpenAI/APIModels/Responses/ResponseTool.swift`**

Add new case:

```swift
public enum ResponseTool: Codable {
    // ... existing cases ...
    case computerUsePreview(displayWidth: Int, displayHeight: Int, environment: String?)
}

// In ToolType enum:
case computerUsePreview = "computer_use_preview"
```

Add encode/decode logic following the existing pattern for other tools.

**File: `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+AITextRequest.swift`**

In `convertToResponseRequest()` built-in tools switch (~line 136):

```swift
case .computerUse(let config):
    insertBuiltInTools(kind: tool.kind, tools: [
        .computerUsePreview(
            displayWidth: config.displayWidth,
            displayHeight: config.displayHeight,
            environment: config.environment?.rawValue
        )
    ], preferOrder: true)

case .computerUseDefault:
    insertBuiltInTools(kind: tool.kind, tools: [
        .computerUsePreview(displayWidth: 1024, displayHeight: 768, environment: "browser")
    ], preferOrder: true)
```

**Note:** OpenAI requires `truncation: "auto"` for computer use. The `ResponseRequest` should set this automatically when computer use is present. Check if this field exists on `ResponseRequest` and add it if needed.

##### 3c. Gemini Adapter (Rejection)

**File: `Sources/AISDK/Core/Providers/GeminiClientAdapter.swift`**

In built-in tools switch (~line 463):

```swift
case .computerUse, .computerUseDefault:
    throw ProviderError.invalidRequest(
        "computerUse is not supported by Gemini. Supported built-in tools: webSearch, codeExecution, urlContext."
    )
```

##### 3d. OpenAI Chat Completions Adapter (Already Rejects)

**File: `Sources/AISDK/Core/Providers/OpenAIClientAdapter.swift`**

The existing code already rejects ALL built-in tools for Chat Completions. No changes needed -- the new `computerUse` case will hit the existing rejection. Verify the switch is exhaustive or uses a default case.

- Tasks and deliverables:
  - [ ] Add Anthropic mapping with version selection logic in `AnthropicClientAdapter.swift`
  - [ ] Add beta header auto-addition in `betaHeaderValue` method
  - [ ] Add `ResponseTool.computerUsePreview` case with encode/decode in `ResponseTool.swift`
  - [ ] Add OpenAI Responses mapping in `OpenAIProvider+AITextRequest.swift`
  - [ ] Add `truncation: "auto"` auto-setting for OpenAI when computer use is present
  - [ ] Add Gemini rejection in `GeminiClientAdapter.swift`
  - [ ] Verify OpenAI Chat Completions adapter handles new case (exhaustive switch)
- Success criteria: `swift build` succeeds, each provider produces correct wire format
- Estimated effort: Medium

---

#### Phase 4: Response Parsing (Inbound -- Wire to ComputerUseAction)

##### 4a. OpenAI Response Parsing

**File: `Sources/AISDK/LLMs/OpenAI/APIModels/Responses/ResponseObject.swift`**

Add new output item type:

```swift
public enum ResponseOutputItem: Codable {
    // ... existing cases ...
    case computerCall(ResponseOutputComputerCall)
}

// In OutputType enum:
case computerCall = "computer_call"

// New struct:
public struct ResponseOutputComputerCall: Codable {
    public let id: String
    public let callId: String
    public let action: ComputerCallAction
    public let pendingSafetyChecks: [PendingSafetyCheck]?
    public let status: String?

    public struct ComputerCallAction: Codable {
        public let type: String      // "screenshot", "click", "type", etc.
        public let x: Int?
        public let y: Int?
        public let button: String?
        public let text: String?
        public let keys: [String]?
        public let scrollX: Int?
        public let scrollY: Int?
        public let path: [PathPoint]?
        public let ms: Int?

        public struct PathPoint: Codable {
            public let x: Int
            public let y: Int
        }
    }

    public struct PendingSafetyCheck: Codable {
        public let id: String
        public let code: String
        public let message: String
    }

    enum CodingKeys: String, CodingKey {
        case id, status, action
        case callId = "call_id"
        case pendingSafetyChecks = "pending_safety_checks"
    }
}
```

**File: `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+AITextRequest.swift`**

In `convertToAITextResult()` (~line 307), add handling for `.computerCall`:

```swift
case .computerCall(let call):
    // Convert to unified ComputerUseAction
    let action = ComputerUseAction.from(openAIAction: call.action)
    let safetyChecks = call.pendingSafetyChecks?.map { ... }
    // Store as a special tool call that the Agent recognizes
    toolCalls.append(ToolCallResult(
        id: call.callId,
        name: "__computer_use__",  // sentinel name for Agent routing
        arguments: encodeComputerUseToolCall(action, safetyChecks, callId: call.callId)
    ))
```

##### 4b. Anthropic Response Parsing

Anthropic computer use comes back as standard `tool_use` content blocks with `name: "computer"`. The existing Anthropic response parsing already handles `tool_use` blocks generically and produces `ToolCallResult` with `name` and JSON `arguments`. No structural changes needed for parsing.

The Agent will identify computer use tool calls by checking `name == "computer"` (Anthropic) or `name == "__computer_use__"` (OpenAI sentinel) and routing to the handler.

##### 4c. Parsing ComputerUseAction from Provider-Specific Arguments

Add static factory methods on `ComputerUseAction`:

```swift
extension ComputerUseAction {
    /// Parse from Anthropic tool_use arguments
    static func fromAnthropic(_ arguments: [String: Any]) -> ComputerUseAction? {
        guard let actionStr = arguments["action"] as? String else { return nil }
        switch actionStr {
        case "screenshot": return .screenshot
        case "left_click":
            guard let coord = arguments["coordinate"] as? [Int], coord.count == 2 else { return nil }
            return .click(x: coord[0], y: coord[1], button: .left)
        case "right_click": ...
        case "type":
            guard let text = arguments["text"] as? String else { return nil }
            return .type(text: text)
        // ... all action types
        }
    }

    /// Parse from OpenAI computer_call action
    static func fromOpenAI(_ action: ResponseOutputComputerCall.ComputerCallAction) -> ComputerUseAction? {
        switch action.type {
        case "screenshot": return .screenshot
        case "click":
            guard let x = action.x, let y = action.y else { return nil }
            let button = ClickButton(rawValue: action.button ?? "left") ?? .left
            return .click(x: x, y: y, button: button)
        // ... all action types
        }
    }
}
```

##### 4d. Streaming Chunk Parsing (OpenAI)

**File: `Sources/AISDK/LLMs/OpenAI/APIModels/Responses/ResponseChunk.swift`**

OpenAI streams computer use as `response.computer_call.*` events. Add handling for:
- `response.computer_call.in_progress` -- action details
- `response.computer_call.completed` -- final action with all fields

The accumulation pattern follows the existing streaming chunk handling in `OpenAIProvider`.

- Tasks and deliverables:
  - [ ] Add `ResponseOutputComputerCall` struct and `computerCall` case to `ResponseOutputItem`
  - [ ] Add computer call parsing in `convertToAITextResult()`
  - [ ] Add `ComputerUseAction.fromAnthropic()` factory method
  - [ ] Add `ComputerUseAction.fromOpenAI()` factory method
  - [ ] Add streaming chunk handling for `computer_call` events in OpenAI streaming
  - [ ] Add `computer_call_output` input item type for OpenAI result sending
- Success criteria: Parse computer use actions from both providers into unified `ComputerUseAction`
- Estimated effort: Medium-Large

---

#### Phase 5: Agent Integration

This is the most complex phase because computer use is unique: it's a "built-in" tool (model knows the schema natively) but requires **client-side execution** (consumer must take screenshots, perform clicks).

##### 5a. Handler Closure on Agent

**File: `Sources/AISDK/Agents/Agent.swift`**

Add the handler property following the `mcpApprovalHandler` pattern (~line 139):

```swift
/// Handler for computer use tool calls. Called when the model requests a screen action.
/// The consumer executes the action (take screenshot, click, etc.) and returns the result.
public var computerUseHandler: (@Sendable (ComputerUseToolCall) async throws -> ComputerUseResult)?
```

Add to `Agent.init()` parameters.

##### 5b. Tool Name Registration

In `builtInToolNameSet` (~line 1082), add computer use tool names so the Agent doesn't try to execute them as regular `Tool` instances:

```swift
case .computerUse, .computerUseDefault:
    names.insert("computer")           // Anthropic tool name
    names.insert("computer_use")       // Alternate
    names.insert("__computer_use__")   // OpenAI sentinel from parsing
```

##### 5c. Execution Routing

In the tool execution loop (~line 508-561), add computer use routing BEFORE the regular tool execution:

```swift
// Separate computer use calls from regular tool calls
let (computerUseCalls, regularToolCalls) = partitionToolCalls(toolCalls)

// Execute computer use calls sequentially via handler
for cuCall in computerUseCalls {
    guard let handler = computerUseHandler else {
        throw AgentError.computerUseHandlerNotConfigured
    }
    let cuToolCall = parseComputerUseToolCall(from: cuCall)

    // Emit stream event for observability
    await emitEvent(.computerUseAction(cuToolCall.action))

    do {
        let result = try await handler(cuToolCall)
        // Convert result to message for conversation history
        appendComputerUseResult(result, forToolCall: cuCall)
    } catch {
        // Follow existing pattern: send error as tool result, let model retry
        appendComputerUseResult(.error(error.localizedDescription), forToolCall: cuCall)
    }
}

// Execute regular tool calls (existing logic)
let executableToolCalls = regularToolCalls.filter { !builtInToolNameSet.contains($0.name) }
// ... existing execution logic ...
```

##### 5d. Result-to-Message Conversion (Critical Gap Resolution)

**The problem:** `AIMessage.tool(content:toolCallId:)` is text-only, but computer use results contain base64 image data that must be sent back to the provider in a specific format.

**Solution:** Encode the `ComputerUseResult` as a JSON string in the `AIMessage.tool` content field, with a recognizable prefix/structure. The provider adapter detects this during request building and converts to the appropriate wire format.

```swift
// In Agent:
private func appendComputerUseResult(_ result: ComputerUseResult, forToolCall call: ToolCallResult) {
    // Encode as JSON with a type marker for the adapter to detect
    let payload = ComputerUseResultPayload(
        type: "__computer_use_result__",
        screenshot: result.screenshot,
        mediaType: result.mediaType?.rawValue,
        text: result.text,
        isError: result.isError,
        callId: call.id  // For OpenAI's call_id correlation
    )
    let content = String(data: try! JSONEncoder().encode(payload), encoding: .utf8)!
    workingMessages.append(.tool(content: content, toolCallId: call.id))
}
```

**In AnthropicClientAdapter**, when converting tool messages to wire format, detect the `__computer_use_result__` marker and construct the image content block:

```swift
// When building tool_result content blocks:
if content.contains("__computer_use_result__"),
   let payload = try? JSONDecoder().decode(ComputerUseResultPayload.self, from: content.data(using: .utf8)!) {
    // Build Anthropic image content block
    var resultContent: [[String: Any]] = []
    if let screenshot = payload.screenshot, let mediaType = payload.mediaType {
        resultContent.append([
            "type": "image",
            "source": ["type": "base64", "media_type": mediaType, "data": screenshot]
        ])
    }
    if let text = payload.text {
        resultContent.append(["type": "text", "text": text])
    }
    // Use resultContent array instead of plain text
}
```

**In OpenAI Responses API**, construct `computer_call_output` input item:

```swift
// Build computer_call_output for OpenAI
let outputItem: [String: Any] = [
    "type": "computer_call_output",
    "call_id": payload.callId,
    "output": [
        "type": "input_image",
        "image_url": "data:\(payload.mediaType ?? "image/png");base64,\(payload.screenshot ?? "")"
    ]
]
```

##### 5e. Add AgentError Case

```swift
public enum AgentError: Error {
    // ... existing cases ...
    case computerUseHandlerNotConfigured
}
```

- Tasks and deliverables:
  - [ ] Add `computerUseHandler` closure property to Agent
  - [ ] Add computer use tool names to `builtInToolNameSet`
  - [ ] Add tool call partitioning logic (computer use vs regular)
  - [ ] Implement computer use execution routing in agent loop
  - [ ] Implement `ComputerUseResultPayload` encoding for message history
  - [ ] Add `AgentError.computerUseHandlerNotConfigured`
  - [ ] Update `AnthropicClientAdapter` to detect and convert computer use results
  - [ ] Update `OpenAIProvider` to construct `computer_call_output` from encoded results
  - [ ] Handle error propagation (send error as tool result)
- Success criteria: Agent can route computer use calls to handler and send results back
- Estimated effort: Large

---

#### Phase 6: Stream Events

**File: `Sources/AISDK/Core/Models/AIStreamEvent.swift`**

Add a new event case for typed computer use actions:

```swift
public enum AIStreamEvent: Sendable, Equatable {
    // ... existing cases ...

    /// A computer use action requested by the model (typed version of tool call)
    case computerUseAction(ComputerUseToolCall)
}
```

This provides typed access to computer use actions for consumers using the streaming API directly (without the Agent). The existing `.toolCallStart`/`.toolCallFinish` events are ALSO emitted for backward compatibility -- `.computerUseAction` is an additional typed event.

**File: `Sources/AISDK/Core/Providers/ProviderClient.swift`**

If using `ProviderStreamEvent` as an intermediary, add a case or emit the event during the adapter's stream conversion.

- Tasks and deliverables:
  - [ ] Add `.computerUseAction(ComputerUseToolCall)` to `AIStreamEvent`
  - [ ] Emit event from both Anthropic and OpenAI stream adapters when computer use actions are parsed
  - [ ] Ensure existing `.toolCall*` events still emit for backward compatibility
- Success criteria: Consumers see typed computer use events in the stream
- Estimated effort: Small

---

#### Phase 7: Tests

##### 7a. Core Type Tests

**File: `Tests/AISDKTests/Core/ComputerUseTests.swift`**

Following the pattern in `BuiltInToolTests.swift`:

```swift
// Test cases:
func testComputerUseDefault() // kind == "computerUse"
func testComputerUseWithConfig() // all config fields
func testComputerUseConfigCodable() // JSON round-trip
func testKindDeduplication() // configured and default share kind
func testHashable() // configured and default are distinct in Set
func testComputerUseActionFromAnthropic() // parse each action type
func testComputerUseActionFromOpenAI() // parse each action type
func testComputerUseResultConvenience() // .screenshot(), .error() factories
func testComputerUseEnvironmentCodable() // enum round-trip
```

##### 7b. Provider Mapping Tests

**File: `Tests/AISDKTests/LLMTests/Providers/ComputerUseMappingTests.swift`**

Following the pattern in `BuiltInToolMappingTests.swift`:

```swift
// Anthropic tests:
func testAnthropicComputerUseMapping() // wire format correct
func testAnthropicComputerUseWithZoom() // computer_20251124 type selected
func testAnthropicComputerUseBetaHeader() // auto-added
func testAnthropicComputerUseBetaHeaderZoom() // newer header for zoom
func testAnthropicComputerUseDefaultMapping() // 1024x768 defaults

// OpenAI Responses tests:
func testOpenAIResponsesComputerUseMapping() // ResponseTool.computerUsePreview
func testOpenAIResponsesComputerUseDefaultMapping() // default environment
func testOpenAIResponsesComputerCallParsing() // parse computer_call output

// Rejection tests:
func testGeminiRejectsComputerUse() // ProviderError.invalidRequest
func testOpenAIChatCompletionsRejectsComputerUse() // existing rejection covers this

// Agent integration tests:
func testAgentComputerUseHandlerCalled() // handler invoked with correct action
func testAgentComputerUseHandlerNilThrows() // AgentError.computerUseHandlerNotConfigured
func testAgentComputerUseResultSentBack() // result appears in conversation
func testAgentMixedToolCalls() // computer use + regular function calls
```

- Tasks and deliverables:
  - [ ] Create `Tests/AISDKTests/Core/ComputerUseTests.swift`
  - [ ] Create `Tests/AISDKTests/LLMTests/Providers/ComputerUseMappingTests.swift`
  - [ ] All tests pass with `swift test --filter ComputerUse`
- Success criteria: Full coverage of config, action parsing, provider mapping, agent routing
- Estimated effort: Medium

---

## Acceptance Criteria

### Functional Requirements

- [x] A `BuiltInTool.computerUse(config)` exists and can be passed to `AITextRequest`
- [x] Anthropic adapter produces correct `computer_20250124` / `computer_20251124` tool format
- [x] Anthropic adapter auto-adds the correct beta header
- [x] OpenAI Responses adapter produces correct `computer_use_preview` tool format
- [x] Gemini adapter throws `ProviderError.invalidRequest` for computer use
- [x] Computer use actions from both providers parse into unified `ComputerUseAction`
- [x] Agent calls `computerUseHandler` when model requests computer actions
- [x] Agent sends `ComputerUseResult` back to provider in correct wire format
- [x] `AgentError.computerUseHandlerNotConfigured` thrown when handler is nil
- [x] OpenAI safety checks surface on `ComputerUseToolCall.safetyChecks`
- [x] Stream events include `.computerUseAction` for observability

### Non-Functional Requirements

- [x] All new types conform to `Sendable` (actor isolation)
- [x] No breaking changes to existing API surface
- [x] `swift build` and `swift test` pass

### Quality Gates

- [x] Unit tests for all action types (both provider parsers)
- [x] Unit tests for provider mapping (Anthropic, OpenAI, Gemini rejection)
- [x] Unit tests for Agent handler routing and error cases
- [x] Code follows existing patterns (no new abstractions beyond what's needed)

## Dependencies and Prerequisites

- No external dependencies
- Requires existing `BuiltInTool` infrastructure (already in place)
- Requires `LLMCapabilities.computerUse` (already defined at `LLMModelProtocol.swift:73`)
- Requires `BetaConfiguration.computerUse` (already defined at `AnthropicService.swift:85`)

## Risk Analysis and Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| AIMessage text-only content doesn't carry images | High | High | JSON-encoded payload with type marker, adapter detects and converts |
| OpenAI streaming format for computer_call undocumented | Medium | Medium | Start with non-streaming, add streaming later if needed |
| OpenAI `computer-use-preview` model deprecation (April 2026) | Low | Medium | SDK maps to wire format; model changes don't affect SDK types |
| Memory bloat from base64 screenshots in message history | Medium | Medium | Document recommended practices; future: add screenshot retention config |
| Handler called on wrong thread/actor | Low | High | `@Sendable` annotation, document MainActor considerations |

## Future Considerations

- **Text Editor and Bash tools**: Add as separate `BuiltInTool.textEditor` and `BuiltInTool.bash` cases
- **Screenshot retention policy**: Add `maxHistoryScreenshots` config to limit memory usage
- **ResponseAgent support**: Add computer use handler to ResponseAgent for OpenAI-specific usage
- **Coordinate validation**: Optional client-side validation against display dimensions
- **Screenshot compression**: Optional auto-resize/compress to optimize token usage

## References

### Internal References

- BuiltInTool enum: `Sources/AISDK/Core/Models/BuiltInTool.swift`
- Anthropic adapter: `Sources/AISDK/Core/Providers/AnthropicClientAdapter.swift:493-541`
- OpenAI Responses conversion: `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+AITextRequest.swift:136-161`
- ResponseTool enum: `Sources/AISDK/LLMs/OpenAI/APIModels/Responses/ResponseTool.swift`
- ResponseOutputItem: `Sources/AISDK/LLMs/OpenAI/APIModels/Responses/ResponseObject.swift:143-213`
- Agent tool loop: `Sources/AISDK/Agents/Agent.swift:508-561`
- builtInToolNameSet: `Sources/AISDK/Agents/Agent.swift:1082-1101`
- BetaConfiguration: `Sources/AISDK/LLMs/Anthropic/AnthropicService.swift:57-214`
- LLMCapabilities.computerUse: `Sources/AISDK/LLMs/LLMModelProtocol.swift:73`
- Existing tests: `Tests/AISDKTests/Core/BuiltInToolTests.swift`, `Tests/AISDKTests/LLMTests/Providers/BuiltInToolMappingTests.swift`
- Brainstorm: `docs/brainstorms/2026-02-13-computer-use-integration-brainstorm.md`

### External References

- Anthropic Computer Use API: https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool
- Anthropic Beta Headers: https://platform.claude.com/docs/en/api/beta-headers
- OpenAI Computer Use Guide: https://platform.openai.com/docs/guides/tools-computer-use
- OpenAI Responses API: https://platform.openai.com/docs/api-reference/responses
- OpenAI CUA Sample App: https://github.com/openai/openai-cua-sample-app

### Related Work

- Issue: #18 (Task 10: Add Computer Use tool integration)
- Prior art: Prompt caching PR #28, Native built-in tools PR #27
