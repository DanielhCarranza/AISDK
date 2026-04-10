# Computer Use Guide

Computer use lets an AI agent control a GUI by requesting screenshots, clicks, and keyboard input. The SDK handles the protocol — your app implements the actual screenshot capture and input simulation via a handler.

## Handler Pattern

The SDK does NOT take screenshots or perform clicks itself. Your app must implement a `ComputerUseHandler` closure:

```swift
import AISDK

let agent = Agent(model: myModel, builtInTools: [.computerUseDefault])

await agent.setComputerUseHandler { toolCall in
    switch toolCall.action {
    case .screenshot:
        let image = captureScreenshot()  // Your implementation
        return .screenshot(image)

    case .click(let x, let y, let button):
        performClick(x: x, y: y, button: button)  // Your implementation
        let image = captureScreenshot()
        return .screenshot(image)

    case .type(let text):
        simulateTyping(text)  // Your implementation
        let image = captureScreenshot()
        return .screenshot(image)

    case .scroll(let x, let y, let direction):
        simulateScroll(at: (x, y), direction: direction)
        let image = captureScreenshot()
        return .screenshot(image)

    case .keyPress(let key):
        simulateKeyPress(key)
        let image = captureScreenshot()
        return .screenshot(image)

    default:
        return .error("Unsupported action: \(toolCall.action)")
    }
}

// Run the agent — it will call your handler when it needs to interact
let result = try await agent.run(messages: [.user("Open Safari and search for Swift")])
```

## Configuration

```swift
let config = BuiltInTool.ComputerUseConfig(
    displayWidth: 1920,    // Screen dimensions for coordinate mapping
    displayHeight: 1080,
    environment: .mac      // OpenAI: .browser, .mac, .windows, .ubuntu, .linux
)

let agent = Agent(model: myModel, builtInTools: [.computerUse(config)])
```

## Error Handling

Handler errors are converted to tool results and fed back to the agent, allowing it to self-correct:

```swift
await agent.setComputerUseHandler { toolCall in
    do {
        return try performAction(toolCall)
    } catch {
        // Error is sent as tool result text — agent sees and adapts
        throw error  // or: return .error(error.localizedDescription)
    }
}
```

If no handler is configured, the agent receives `"Computer use handler not configured"` as a tool result. Errors are never silently swallowed — they always reach the agent.

## Provider Support

| Provider | Tool Name | Notes |
|----------|-----------|-------|
| OpenAI Responses | `computer_use` | Environment-aware (browser, OS) |
| Anthropic | `computer_20250124` / `computer_20251124` | Zoom support with `enableZoom: true` |
| Gemini | Not supported | Throws `invalidRequest` |
| OpenAI Chat | Not supported | Use Responses API |

## Streaming

Computer use actions appear as tool call events during streaming:

```swift
for try await event in agent.streamRun(messages: [.user("Click the submit button")]) {
    switch event {
    case .toolCallStart(let call) where call.name == "computer_use":
        print("Agent requesting: \(call)")
    case .textDelta(let text):
        print(text, terminator: "")
    default:
        break
    }
}
```
