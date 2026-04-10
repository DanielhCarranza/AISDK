# Multi-Step Agents

> Building complex AI workflows with tool loops and state management

## Overview

Real-world AI applications often require multiple steps: gathering information, making decisions, and taking actions. This tutorial covers building sophisticated agent workflows.

## Understanding Agent Execution

When an agent receives a message, it may:
1. Generate a direct response
2. Call one or more tools
3. Process tool results and continue reasoning
4. Repeat steps 2-3 until the task is complete

```swift
// Agent automatically handles multi-step execution
let agent = Agent(
    model: client,
    tools: [WeatherTool.self, CalendarTool.self, EmailTool.self],
    instructions: """
        You are a personal assistant that can:
        - Check the weather
        - Access calendar events
        - Send emails
        """
)

// This may involve multiple tool calls
let result = try await agent.execute(
    messages: [.user("Check my schedule for today and email me a summary with the weather")]
)
```

## Configuring Agent Behavior

### Maximum Steps

Limit iterations to prevent runaway loops:

```swift
let agent = Agent(
    model: client,
    tools: tools,
    maxSteps: 10  // Stop after 10 LLM calls
)
```

### Stop Conditions

Define custom stopping logic:

```swift
let result = try await agent.execute(
    messages: messages,
    stopCondition: .stepCount(5)  // Stop after 5 steps
)

// Or stop when specific tool is called
let result = try await agent.execute(
    messages: messages,
    stopCondition: .toolCalled("send_email")
)
```

## Observable State for UI

Track agent progress in SwiftUI:

```swift
@Observable
class ChatViewModel {
    var messages: [AIMessage] = []
    var currentTool: String?
    var isProcessing = false
    var error: Error?

    private let agent: Agent

    func sendMessage(_ text: String) async {
        messages.append(.user(text))
        isProcessing = true
        defer { isProcessing = false }

        do {
            for try await event in agent.streamExecute(messages: messages) {
                await handleEvent(event)
            }
        } catch {
            self.error = error
        }
    }

    @MainActor
    private func handleEvent(_ event: AIAgentEvent) {
        switch event {
        case .textDelta(let text):
            appendToLastAssistantMessage(text)

        case .toolCallStart(_, let name):
            currentTool = name

        case .toolResult:
            currentTool = nil

        case .finish:
            break

        default:
            break
        }
    }
}
```

## Building a Research Agent

Example: An agent that researches topics using multiple tools.

```swift
// Define research tools
struct WebSearchTool: Tool {
    let name = "web_search"
    let description = "Search the web for information"

    @Parameter(description: "Search query")
    var query: String = ""

    @Parameter(description: "Maximum number of results")
    var maxResults: Int = 5

    init() {}

    func execute() async throws -> ToolResult {
        let results = await searchWeb(query: query, limit: maxResults)
        return ToolResult(content: formatResults(results))
    }
}

struct WikipediaTool: Tool {
    let name = "wikipedia"
    let description = "Look up information on Wikipedia"

    @Parameter(description: "Topic to look up")
    var topic: String = ""

    init() {}

    func execute() async throws -> ToolResult {
        let article = await fetchWikipediaArticle(topic)
        return ToolResult(content: article.summary)
    }
}

struct NoteTool: Tool {
    let name = "save_note"
    let description = "Save a research note"

    @Parameter(description: "Note title")
    var title: String = ""

    @Parameter(description: "Note content")
    var content: String = ""

    init() {}

    func execute() async throws -> ToolResult {
        await saveNote(title: title, content: content)
        return ToolResult(content: "Note saved: \(title)")
    }
}

// Create research agent
let researchAgent = Agent(
    model: client,
    tools: [WebSearchTool.self, WikipediaTool.self, NoteTool.self],
    instructions: """
        You are a research assistant. When given a topic:
        1. Search for relevant information using web_search
        2. Look up key concepts on Wikipedia
        3. Synthesize findings and save a note with sources

        Always cite your sources.
        """
)

// Execute research task
let result = try await researchAgent.execute(
    messages: [.user("Research the history of Swift programming language")]
)

// Result includes all tool calls and final synthesis
```

## Conversation Context Management

For simple, in-memory context tracking:

```swift
class ConversationManager {
    private let agent: Agent
    private var history: [AIMessage] = []

    init(agent: Agent) {
        self.agent = agent
    }

    func send(_ message: String) async throws -> AIAgentResult {
        history.append(.user(message))
        let result = try await agent.execute(messages: history)
        history.append(.assistant(result.text))
        return result
    }

    func clearHistory() {
        history.removeAll()
    }
}
```

For persistent conversations that survive app restarts, use **Sessions** instead:

```swift
let store = SQLiteSessionStore(path: dbPath)
let vm = ChatViewModel(agent: agent, store: store)
try await vm.createSession(userId: "user_1")
await vm.send("Hello!")  // Persists automatically
```

See [Sessions & Persistence](08-sessions.md) for the full guide.

## Parallel Tool Execution

When multiple tools can run independently:

```swift
let agent = Agent(
    model: client,
    tools: [WeatherTool.self, StockTool.self, NewsTool.self],
    parallelToolCalls: true  // Enable parallel execution
)

// Agent may call weather, stocks, and news simultaneously
let result = try await agent.execute(
    messages: [.user("Give me a morning briefing: weather, stocks, and news")]
)
```

## Error Recovery

Handle tool failures gracefully:

```swift
struct ResilientTool: Tool {
    let name = "api_call"
    let description = "Call an external API"

    @Parameter(description: "API endpoint URL")
    var endpoint: String = ""

    init() {}

    func execute() async throws -> ToolResult {
        do {
            let data = try await callAPI(endpoint)
            return ToolResult(content: data)
        } catch {
            // Return error as content so agent can adapt
            return ToolResult(
                content: "API call failed: \(error.localizedDescription). Please try an alternative approach.",
                isError: true
            )
        }
    }
}
```

## Streaming Multi-Step Workflows

Provide real-time feedback during complex operations:

```swift
func executeWithProgress(query: String) async {
    var stepCount = 0

    for try await event in agent.streamExecute(messages: [.user(query)]) {
        switch event {
        case .textDelta(let text):
            appendToOutput(text)

        case .toolCallStart(_, let name):
            stepCount += 1
            showProgress("Step \(stepCount): Calling \(name)...")

        case .toolResult(_, let result):
            showProgress("Got result, continuing...")

        case .finish(let reason, let usage):
            showProgress("Complete! Used \(usage.totalTokens) tokens")

        default:
            break
        }
    }
}
```

## Best Practices

1. **Limit max steps** - Prevent infinite loops
2. **Use clear system prompts** - Guide the agent's reasoning
3. **Provide error context** - Help agent recover from failures
4. **Stream for long tasks** - Keep users informed
5. **Manage conversation history** - Prune old messages to stay within context limits

## Next Steps

- [Generative UI](05-generative-ui.md) - Dynamic interfaces
- [Reliability Patterns](06-reliability-patterns.md) - Production hardening
- [Testing Strategies](07-testing-strategies.md) - Verify agent behavior
- [Sessions & Persistence](08-sessions.md) - Persist conversations across app launches
