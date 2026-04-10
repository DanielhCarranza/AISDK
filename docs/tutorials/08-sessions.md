# Sessions & Persistence

> Persist conversations across app launches with automatic streaming integration

## Overview

AISDK sessions give your agent a memory. Without sessions, every `agent.execute()` starts fresh. With sessions, conversations persist to disk (or any backend), survive app restarts, and support features like rewind, checkpoints, and context compaction.

## Quick Start

```swift
import AISDK

// 1. Choose a store
let store = InMemorySessionStore()       // Development
// let store = FileSystemSessionStore()  // File-based persistence
// let store = SQLiteSessionStore()      // Production

// 2. Create a session
var session = try await AISession.create(userId: "user_1", store: store)

// 3. Use ChatViewModel for streaming + persistence
let vm = ChatViewModel(agent: myAgent, store: store, session: session)
await vm.send("What is the capital of France?")
// Response streams in, messages persist automatically
```

## The Session Model

An `AISession` contains everything about a conversation:

```swift
let session = AISession(
    userId: "user_1",
    agentId: "research-agent",   // Optional: multi-agent attribution
    title: "Trip Planning",
    metadata: ["topic": "travel"]
)

session.id              // Auto-generated UUID
session.messages        // Full message history
session.status          // .active, .completed, .paused, .error, .archived
session.createdAt       // Creation timestamp
session.lastActivityAt  // Updated on each message
session.tags            // Optional organization tags
```

## Choosing a Store

AISDK ships three `SessionStore` implementations:

| Store | Use Case | Persistence | Thread Safety |
|-------|----------|-------------|---------------|
| `InMemorySessionStore` | Tests, previews | None (memory only) | Actor-isolated |
| `FileSystemSessionStore` | Simple apps | JSON files on disk | Actor-isolated |
| `SQLiteSessionStore` | Production apps | SQLite database | Actor-isolated, WAL mode |

```swift
// In-memory (great for SwiftUI previews)
let store = InMemorySessionStore()

// File system (one JSON file per session)
let store = FileSystemSessionStore(
    directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("sessions")
)

// SQLite (production-grade with indexes)
let store = try SQLiteSessionStore(
    path: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("sessions.db").path
)
```

## Building a Chat UI with ChatViewModel

`ChatViewModel` is the main integration point. It connects your agent, store, and SwiftUI view:

```swift
struct ChatScreen: View {
    @State private var vm: ChatViewModel
    @State private var input = ""

    init(agent: Agent, store: SessionStore) {
        _vm = State(initialValue: ChatViewModel(agent: agent, store: store))
    }

    var body: some View {
        VStack {
            ScrollView {
                ForEach(vm.session.messages, id: \.id) { message in
                    MessageBubble(message: message)
                }
            }

            if vm.isStreaming {
                ProgressView("Thinking...")
            }

            HStack {
                TextField("Message", text: $input)
                Button("Send") {
                    let text = input
                    input = ""
                    Task { await vm.send(text) }
                }
                .disabled(vm.isStreaming || input.isEmpty)
            }
        }
        .task {
            try? await vm.createSession(userId: "user_1")
        }
    }
}
```

### ChatViewModel Capabilities

```swift
// Send a message (streams response, persists automatically)
await vm.send("Hello!")

// Resume an incomplete session
await vm.resume()

// Rewind to a checkpoint
await vm.rewind(to: checkpointIndex)

// Retry the last turn
await vm.retryLastTurn()

// Cancel current streaming
vm.cancel()

// Load an existing session
try await vm.loadSession(id: "session-id")
```

## Listing Sessions

Use `SessionListViewModel` for a session browser:

```swift
struct SessionListScreen: View {
    @State private var vm: SessionListViewModel

    init(store: SessionStore) {
        _vm = State(initialValue: SessionListViewModel(
            store: store,
            userId: "user_1"
        ))
    }

    var body: some View {
        List(vm.sessions) { session in
            NavigationLink(value: session.id) {
                VStack(alignment: .leading) {
                    Text(session.title ?? "Untitled")
                    Text("\(session.messageCount) messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { await vm.loadSessions() }
        .refreshable { await vm.refresh() }
    }
}
```

### Filtering and Pagination

```swift
// Filter by status
await vm.loadSessions(status: .active, orderBy: .lastActivityAtDesc)

// Load next page (cursor-based)
await vm.loadMore()

// Delete a session
try await vm.deleteSession(id: "session-id")
```

## Checkpoints and Rewind

Sessions automatically track checkpoints at step boundaries. You can also create manual checkpoints:

```swift
// Create a manual checkpoint
session.createCheckpoint(type: .manual, label: "Before code review")

// Rewind to any checkpoint
session.rewind(to: 0)  // Back to first checkpoint

// Get messages at a specific checkpoint
let messages = session.messagesAtCheckpoint(2)
```

## Context Compaction

Long conversations can exceed model context windows. Use `SessionCompactionService` to manage this:

```swift
let compactor = SessionCompactionService(llm: myLLM)
let policy = ContextPolicy(
    maxTokens: 8000,
    compactionThreshold: 0.9,          // Trigger at 90% capacity
    compactionStrategy: .summarize,    // Use LLM to summarize old messages
    preserveSystemPrompt: true,
    minMessagesToKeep: 4
)

if compactor.needsCompaction(session.messages, policy: policy) {
    session.messages = try await compactor.compact(session.messages, policy: policy)
}
```

### Compaction Strategies

| Strategy | Behavior | Requires LLM |
|----------|----------|--------------|
| `.truncate` | Drop oldest messages, keep recent | No |
| `.summarize` | Replace old messages with LLM summary | Yes |
| `.slidingWindow` | Keep first exchanges + recent messages | No |

## Auto-Generated Titles

Generate conversation titles from content:

```swift
let titleGen = DefaultTitleGenerator(llm: myLLM)
let title = try await titleGen.generateTitle(from: session.messages)
// "Trip Planning for Japan"
```

## Export and Import

```swift
// Export as JSON
let jsonData = try session.exportJSON()

// Import from JSON
let restored = try AISession.importJSON(jsonData)

// Export as Markdown (human-readable)
let markdown = session.exportMarkdown()

// Bulk export all sessions for a user
let allData = try await store.exportAll(userId: "user_1")
```

## Multi-Agent Sessions

Track which agent generated each message and hand off between agents:

```swift
// Fork a session for a specialist agent
let forkedSession = session.fork()

// Configure agent handoff
let handoff = AgentHandoff(
    targetAgentId: "code-review-agent",
    mode: .forked,    // .shared, .forked, or .independent
    message: "Please review this code"
)
```

## Implementing a Custom Store

Conform to `SessionStore` for your own backend (CloudKit, Firebase, REST API):

```swift
actor MyCloudStore: SessionStore {
    func create(_ session: AISession) async throws -> AISession { ... }
    func load(id: String) async throws -> AISession? { ... }
    func save(_ session: AISession) async throws { ... }
    func delete(id: String) async throws { ... }
    func list(userId: String, status: SessionStatus?, limit: Int,
              cursor: String?, orderBy: SessionOrderBy) async throws -> SessionListResult { ... }

    // Incremental updates have default implementations,
    // but override them for better performance:
    func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws { ... }
    func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws { ... }
}
```

## Best Practices

1. **Use SQLiteSessionStore for production** - It handles concurrent access, has indexes, and uses WAL mode
2. **Let ChatViewModel handle persistence** - Don't manually save during streaming; the ViewModel debounces writes
3. **Set a context policy for long conversations** - Prevent context window overflow
4. **Use checkpoints before risky operations** - Allow users to rewind if something goes wrong
5. **Export sessions for debugging** - Markdown export is great for sharing conversation logs

## Next Steps

- [API Reference: Sessions](../api-reference/sessions.md) - Complete type reference
- [Multi-Step Agents](04-multi-step-agents.md) - Agent execution patterns
- [Streaming Basics](02-streaming-basics.md) - Stream event handling
