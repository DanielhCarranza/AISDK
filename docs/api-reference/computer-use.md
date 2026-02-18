# Computer Use

> Screen interaction through provider-native computer use tools

## Overview

Computer use enables AI models to interact with screens: taking screenshots, clicking, typing, scrolling, and dragging. AISDK provides a unified interface across OpenAI (`computer_use_preview`) and Anthropic (`computer_20250124`).

### Provider Support

| Feature | OpenAI (Responses API) | Anthropic | Gemini |
|---------|----------------------|-----------|--------|
| Tool type | `computer_use_preview` | `computer_20250124` | Not supported |
| Zoom variant | N/A | `computer_20251124` (beta) | N/A |
| Safety checks | `pending_safety_checks` | N/A | N/A |
| Beta header | Not required | Auto-added by SDK | N/A |

---

## Configuration

Add computer use as a built-in tool on any request or agent.

```swift
// Default config (1024x768, browser environment)
let request = AITextRequest(
    messages: [.user("Take a screenshot")],
    model: "computer-use-preview",
    builtInTools: [.computerUseDefault]
)

// Custom config
let config = BuiltInTool.ComputerUseConfig(
    displayWidth: 1920,
    displayHeight: 1080,
    environment: .mac  // OpenAI-specific
)
let request = AITextRequest(
    messages: [.user("Take a screenshot")],
    model: "computer-use-preview",
    builtInTools: [.computerUse(config)]
)
```

### ComputerUseConfig

```swift
public struct ComputerUseConfig: Sendable, Equatable, Hashable, Codable {
    public let displayWidth: Int          // Required. Default: 1024
    public let displayHeight: Int         // Required. Default: 768
    public let environment: ComputerUseEnvironment?  // OpenAI only
    public let displayNumber: Int?        // Anthropic only (X11 display)
    public let enableZoom: Bool?          // Anthropic computer_20251124 only (beta)
}
```

### ComputerUseEnvironment

OpenAI-specific environment values: `.browser`, `.mac`, `.windows`, `.ubuntu`, `.linux`.

---

## Actions

When the model needs to interact with the screen, it returns a `ComputerUseToolCall` containing a `ComputerUseAction`.

```swift
public enum ComputerUseAction: Sendable, Equatable {
    case screenshot
    case click(x: Int, y: Int, button: ClickButton = .left)
    case doubleClick(x: Int, y: Int)
    case tripleClick(x: Int, y: Int)
    case type(text: String)
    case keypress(keys: [String])
    case scroll(x: Int, y: Int, scrollX: Int?, scrollY: Int?,
                direction: ScrollDirection?, amount: Int?)
    case move(x: Int, y: Int)
    case drag(path: [Coordinate])
    case wait(durationMs: Int?)
    case cursorPosition
    case zoom(region: [Int])  // Anthropic only
}
```

### ComputerUseToolCall

```swift
public struct ComputerUseToolCall: Sendable, Equatable {
    public let id: String
    public let callId: String?           // OpenAI-specific
    public let action: ComputerUseAction
    public let safetyChecks: [ComputerUseAction.SafetyCheck]  // OpenAI only
}
```

---

## Results

Return a `ComputerUseResult` from your handler after executing the action.

```swift
public struct ComputerUseResult: Sendable, Equatable {
    public let screenshot: String?        // Base64-encoded image
    public let mediaType: ImageMediaType? // .png (default), .jpeg, .gif, .webp
    public let text: String?              // Optional text output
    public let isError: Bool
}
```

### Convenience Initializers

```swift
// Screenshot result
let result = ComputerUseResult.screenshot(base64String, mediaType: .png)

// Error result
let result = ComputerUseResult.error("Failed to take screenshot")
```

---

## Agent Integration

Set a `computerUseHandler` on the `Agent` to execute actions in the agent loop.

```swift
let agent = Agent(
    model: provider,
    builtInTools: [.computerUse(
        .init(displayWidth: 1920, displayHeight: 1080, environment: .mac)
    )]
)

await agent.setComputerUseHandler { toolCall in
    switch toolCall.action {
    case .screenshot:
        let base64 = takeScreenshot()
        return .screenshot(base64)

    case .click(let x, let y, let button):
        performClick(x: x, y: y, button: button)
        let base64 = takeScreenshot()
        return .screenshot(base64)

    case .type(let text):
        typeText(text)
        let base64 = takeScreenshot()
        return .screenshot(base64)

    default:
        return .error("Unsupported action")
    }
}

let result = try await agent.execute(
    messages: [.user("Open Safari and go to example.com")]
)
```

When no handler is set, computer use tool calls return an error and the agent loop continues.

---

## Streaming

Computer use actions emit a `.computerUseAction` stream event.

```swift
for try await event in agent.streamExecute(messages: messages) {
    switch event {
    case .computerUseAction(let toolCall):
        print("Action: \(toolCall.action)")
    case .textDelta(let text):
        print(text, terminator: "")
    case .finish:
        break
    default:
        break
    }
}
```

---

## Safety Checks (OpenAI)

OpenAI may include `pending_safety_checks` on computer use actions. These are surfaced on `ComputerUseToolCall.safetyChecks`. The SDK automatically acknowledges them when sending results back.

```swift
await agent.setComputerUseHandler { toolCall in
    // Inspect safety checks before executing
    for check in toolCall.safetyChecks {
        print("Safety: [\(check.code)] \(check.message)")
    }

    // Execute action and return result
    switch toolCall.action {
    case .screenshot:
        return .screenshot(takeScreenshot())
    default:
        return .error("Not implemented")
    }
}
```

---

## Provider-Level Usage

For direct provider access without the Agent layer:

### OpenAI (Responses API)

```swift
let provider = OpenAIProvider(apiKey: key)
let result = try await provider.execute(AITextRequest(
    messages: [.user("Take a screenshot")],
    model: "computer-use-preview",
    builtInTools: [.computerUseDefault]
))

// Computer use actions appear as tool calls named "__computer_use__"
for toolCall in result.toolCalls where toolCall.name == "__computer_use__" {
    // Decode action from arguments
}
```

OpenAI computer use requires the Responses API. Chat Completions throws `ProviderError.invalidRequest`.

### Anthropic

```swift
let client = AnthropicClientAdapter(apiKey: key)
let response = try await client.execute(ProviderRequest(
    modelId: "claude-sonnet-4-20250514",
    messages: [.user("Take a screenshot")],
    maxTokens: 1024,
    builtInTools: [.computerUseDefault]
))

// Computer use actions appear as tool calls named "computer"
for toolCall in response.toolCalls where toolCall.name == "computer" {
    // Decode action from arguments
}
```

The SDK automatically adds the required `anthropic-beta` header.

---

## See Also

- [Tools](tools.md) - Custom tool protocol
- [Agents](agents.md) - Agent execution and streaming
- [Models](models.md) - AIMessage, AIStreamEvent
