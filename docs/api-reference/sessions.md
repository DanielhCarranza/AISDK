# Sessions

> Conversation persistence, lifecycle management, and context compaction

## AISession

The primary unit of persistence. Contains the complete state of a conversation.

```swift
public struct AISession: Codable, Sendable, Identifiable, Hashable, Equatable {
    // Identity
    public let id: String
    public let userId: String
    public var agentId: String?

    // Timestamps
    public let createdAt: Date
    public var lastActivityAt: Date

    // Metadata
    public var title: String?
    public var tags: [String]?
    public var metadata: [String: String]?

    // Content
    public var messages: [AIMessage]

    // State
    public var status: SessionStatus
    public var checkpoints: [SessionCheckpoint]
    public var lastCheckpointIndex: Int?
    public var isLastMessageComplete: Bool

    // Versioning
    public let schemaVersion: Int
}
```

### Initialization

```swift
public init(
    id: String = UUID().uuidString,
    userId: String,
    agentId: String? = nil,
    title: String? = nil,
    messages: [AIMessage] = [],
    metadata: [String: String]? = nil,
    tags: [String]? = nil
)
```

### Factory Methods

```swift
extension AISession {
    /// Create and persist a new session
    static func create(
        userId: String,
        store: SessionStore,
        agentId: String? = nil,
        title: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> AISession

    /// Load an existing session
    static func load(id: String, store: SessionStore) async throws -> AISession?
}
```

### Checkpoint Management

```swift
extension AISession {
    /// Create a checkpoint at the current message position
    mutating func createCheckpoint(type: CheckpointType, label: String? = nil)

    /// Get messages up to a specific checkpoint
    func messagesAtCheckpoint(_ checkpointIndex: Int) -> [AIMessage]

    /// Rewind session to a checkpoint (truncates messages after it)
    mutating func rewind(to checkpointIndex: Int)

    /// Fork this session (creates a copy with a new ID)
    func fork(newUserId: String? = nil) -> AISession
}
```

### Summary Conversion

```swift
extension AISession {
    /// Create a lightweight summary (no message history)
    var summary: SessionSummary { get }
}
```

### Usage

```swift
// Create
var session = AISession(userId: "user_1", title: "Planning")

// Add messages
session.messages.append(.user("Hello"))
session.lastActivityAt = Date()

// Checkpoint
session.createCheckpoint(type: .manual, label: "Before edit")

// Rewind
session.rewind(to: 0)

// Fork
let copy = session.fork()
```

---

## SessionStatus

```swift
public enum SessionStatus: String, Codable, Sendable {
    case active     // Accepting messages
    case completed  // Finished normally
    case paused     // Can be resumed
    case error      // Ended with an error
    case archived   // Read-only
}
```

---

## SessionCheckpoint

A restorable point in the conversation.

```swift
public struct SessionCheckpoint: Codable, Sendable, Hashable {
    public let index: Int
    public let messageIndex: Int
    public let createdAt: Date
    public let type: CheckpointType
    public var label: String?
}
```

### CheckpointType

```swift
public enum CheckpointType: String, Codable, Sendable {
    case userMessage
    case toolCallComplete
    case assistantComplete
    case manual
}
```

---

## SessionStore Protocol

Core storage protocol. All implementations must be `Sendable` and handle concurrent access.

```swift
public protocol SessionStore: Sendable {
    // CRUD
    func create(_ session: AISession) async throws -> AISession
    func load(id: String) async throws -> AISession?
    func save(_ session: AISession) async throws
    func delete(id: String) async throws

    // Query
    func list(
        userId: String,
        status: SessionStatus?,
        limit: Int,
        cursor: String?,
        orderBy: SessionOrderBy
    ) async throws -> SessionListResult

    // Incremental Updates (optimized for streaming)
    func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws
    func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws
    func updateStatus(_ status: SessionStatus, forSession sessionId: String) async throws
    func updateMetadata(_ updates: SessionMetadataUpdate, forSession sessionId: String) async throws

    // Real-time (optional, returns nil by default)
    func observe(sessionId: String) -> AsyncThrowingStream<AISession, Error>?
}
```

Default implementations are provided for all incremental update methods and `observe`. Simple store implementations only need CRUD + `list`.

### Built-in Stores

| Store | Description |
|-------|-------------|
| `InMemorySessionStore` | Actor-based, ephemeral. Best for tests and previews. |
| `FileSystemSessionStore` | One JSON file per session. Atomic writes. |
| `SQLiteSessionStore` | System SQLite3, WAL mode, indexed queries. No external dependencies. |

---

## SearchableSessionStore Protocol

Extends `SessionStore` with full-text search.

```swift
public protocol SearchableSessionStore: SessionStore {
    func search(
        query: String,
        userId: String,
        limit: Int
    ) async throws -> [SessionSearchResult]
}
```

### SessionSearchResult

```swift
public struct SessionSearchResult: Codable, Sendable {
    public let session: SessionSummary
    public let snippet: String?
    public let relevanceScore: Double?
}
```

---

## SessionSummary

Lightweight type for list views (no message history).

```swift
public struct SessionSummary: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let userId: String
    public let title: String?
    public let status: SessionStatus
    public let createdAt: Date
    public let lastActivityAt: Date
    public let messageCount: Int
    public let tags: [String]?
}
```

---

## SessionListResult

Paginated query result.

```swift
public struct SessionListResult: Codable, Sendable {
    public let sessions: [SessionSummary]
    public let nextCursor: String?
    public let totalCount: Int?
}
```

---

## SessionOrderBy

```swift
public enum SessionOrderBy: String, Codable, Sendable {
    case createdAtAsc
    case createdAtDesc
    case lastActivityAtAsc
    case lastActivityAtDesc
}
```

---

## SessionMetadataUpdate

Partial update type for metadata operations.

```swift
public struct SessionMetadataUpdate: Codable, Sendable {
    public var title: String?
    public var tags: [String]?
    public var metadata: [String: String]?
    public var status: SessionStatus?
}
```

---

## SessionStoreError

```swift
public enum SessionStoreError: Error, Sendable, LocalizedError {
    case notFound(sessionId: String)
    case alreadyExists(sessionId: String)
    case unavailable(reason: String)
    case invalidData(reason: String)
    case unsupported(operation: String)
    case permissionDenied(reason: String)
}
```

### Handling Errors

```swift
do {
    let session = try await store.load(id: "abc")
} catch SessionStoreError.notFound(let id) {
    print("Session \(id) not found")
} catch SessionStoreError.unavailable(let reason) {
    print("Store unavailable: \(reason)")
}
```

---

## ContextPolicy

Controls automatic context compaction.

```swift
public struct ContextPolicy: Codable, Sendable {
    public var maxTokens: Int?                          // nil = unlimited
    public var compactionThreshold: Double              // Default: 0.9
    public var compactionStrategy: CompactionStrategy   // Default: .truncate
    public var preserveSystemPrompt: Bool               // Default: true
    public var minMessagesToKeep: Int                    // Default: 4
}
```

### Presets

```swift
// No limits
ContextPolicy.unlimited

// Conservative for small context windows
ContextPolicy.conservative(maxTokens: 4096)
```

### CompactionStrategy

```swift
public enum CompactionStrategy: String, Codable, Sendable {
    case truncate       // Drop oldest messages, keep recent
    case summarize      // Replace old messages with LLM summary
    case slidingWindow  // Keep first N + last M messages
}
```

---

## SessionCompactionService

Actor that manages context window size.

```swift
public actor SessionCompactionService {
    public init(llm: (any LLM)? = nil)

    /// Estimate token count for messages (heuristic: ~4 bytes/token + 15% margin)
    public func estimateTokens(_ messages: [AIMessage]) -> Int

    /// Check if compaction is needed
    public func needsCompaction(_ messages: [AIMessage], policy: ContextPolicy) -> Bool

    /// Compact messages according to policy
    public func compact(_ messages: [AIMessage], policy: ContextPolicy) async throws -> [AIMessage]
}
```

### Usage

```swift
let compactor = SessionCompactionService(llm: myLLM)
let policy = ContextPolicy(maxTokens: 8000, compactionStrategy: .summarize)

if compactor.needsCompaction(session.messages, policy: policy) {
    session.messages = try await compactor.compact(session.messages, policy: policy)
    try await store.save(session)
}
```

---

## SessionTitleGenerator

Protocol for auto-generating session titles.

```swift
public protocol SessionTitleGenerator: Sendable {
    func generateTitle(from messages: [AIMessage]) async throws -> String
}
```

### DefaultTitleGenerator

```swift
public actor DefaultTitleGenerator: SessionTitleGenerator {
    public init(
        llm: any LLM,
        maxContextMessages: Int = 6,
        fallbackTitle: String = "New Conversation"
    )

    public func generateTitle(from messages: [AIMessage]) async throws -> String
}
```

---

## StreamingPersistenceBuffer

Actor that debounces streaming writes to reduce store pressure.

```swift
public actor StreamingPersistenceBuffer {
    public init(
        store: any SessionStore,
        sessionId: String,
        debounceInterval: Duration = .milliseconds(500)
    )

    /// Buffer a message delta (resets debounce timer)
    public func bufferDelta(_ message: AIMessage)

    /// Immediately persist any pending message
    public func flush() async

    /// Whether there's a pending write
    public var hasPending: Bool { get }
}
```

---

## AgentHandoff

Configuration for multi-agent session transfers.

```swift
public struct AgentHandoff: Codable, Sendable {
    public let targetAgentId: String
    public let mode: HandoffMode
    public let message: String?
    public let metadata: [String: String]?
}
```

### HandoffMode

```swift
public enum HandoffMode: String, Codable, Sendable {
    case shared      // Both agents share the same session
    case forked      // Session is copied for the target agent
    case independent // New session created for target agent
}
```

### SubagentOptions

```swift
public struct SubagentOptions: Codable, Sendable {
    public let sessionMode: HandoffMode        // Default: .forked
    public let maxSteps: Int?
    public let includeMessagesInParent: Bool    // Default: true
}
```

---

## ChatViewModel

Observable ViewModel integrating agents with session persistence.

```swift
@Observable
@MainActor
public final class ChatViewModel {
    // State
    public private(set) var session: AISession
    public private(set) var isStreaming: Bool
    public private(set) var error: Error?
    public private(set) var persistenceWarning: String?

    // Initialization
    public init(agent: Agent, store: any SessionStore, session: AISession? = nil)

    // Lifecycle
    public func createSession(userId: String, title: String? = nil) async throws
    public func loadSession(id: String) async throws

    // Messaging
    public func send(_ text: String) async
    public func resume() async
    public func rewind(to checkpointIndex: Int) async
    public func retryLastTurn() async
    public func cancel()
}
```

---

## SessionListViewModel

Observable ViewModel for browsing sessions.

```swift
@Observable
@MainActor
public final class SessionListViewModel {
    // State
    public private(set) var sessions: [SessionSummary]
    public private(set) var totalCount: Int
    public private(set) var isLoading: Bool
    public private(set) var hasMore: Bool
    public private(set) var error: Error?

    // Initialization
    public init(store: any SessionStore, userId: String, pageSize: Int = 20)

    // Loading
    public func loadSessions(status: SessionStatus? = nil, orderBy: SessionOrderBy = .lastActivityAtDesc) async
    public func loadMore() async
    public func refresh() async

    // CRUD
    @discardableResult
    public func createSession(title: String? = nil, metadata: [String: String]? = nil) async throws -> AISession
    public func deleteSession(id: String) async throws
}
```

---

## Session Export

```swift
extension AISession {
    /// Export as pretty-printed JSON with ISO 8601 dates
    public func exportJSON() throws -> Data

    /// Import from JSON
    public static func importJSON(_ data: Data) throws -> AISession

    /// Export as human-readable Markdown
    public func exportMarkdown() -> String
}

extension SessionStore {
    /// Export all sessions for a user as JSON
    public func exportAll(userId: String) async throws -> Data
}
```

---

## Type Relationships

```
AISession
    ├── AIMessage[]           (complete history)
    ├── SessionStatus         (active/completed/paused/error/archived)
    ├── SessionCheckpoint[]   (rewindable points)
    └── .summary ──► SessionSummary (lightweight, no messages)

SessionStore (protocol)
    ├── InMemorySessionStore   (actor, ephemeral)
    ├── FileSystemSessionStore (actor, JSON files)
    └── SQLiteSessionStore     (actor, database)

ChatViewModel
    ├── uses Agent             (for streaming responses)
    ├── uses SessionStore      (for persistence)
    ├── uses StreamingPersistenceBuffer (debounced writes)
    └── exposes AISession      (observable state)

SessionListViewModel
    ├── uses SessionStore      (for queries)
    └── exposes SessionSummary[] (paginated list)
```

## See Also

- [Sessions Tutorial](../tutorials/08-sessions.md) - Step-by-step guide
- [Agents](agents.md) - AIAgentActor and streaming
- [Models](models.md) - AIMessage and AIStreamEvent
