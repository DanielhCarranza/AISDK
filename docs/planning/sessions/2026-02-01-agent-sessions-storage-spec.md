# AISDK Agent Sessions & Storage Specification

**Date:** 2026-02-01  
**Status:** Draft  
**Owner:** Engineering  
**Phase:** Phase 5 (Memory + Context Management) per Agentic Roadmap

---

## 1. Executive Summary

This specification defines how AISDK agents handle **sessions** (conversation state) and **storage** (persistence). The goal is to provide world-class, clean, and simple usage patterns that match or exceed modern agentic SDKs (OpenAI Agents SDK, Google ADK, Agno, Claude Code).

### Core Principles

1. **Session = Complete Conversation State**: Messages, tool calls, steps, metadata, checkpoints—everything in one place
2. **Protocol-First Design**: `SessionStore` protocol with pluggable adapters (InMemory, FileSystem, SQLite, Firebase)
3. **Fine-Grained Persistence**: Save after each event for crash recovery (like Claude Code)
4. **Auto-Compaction**: Summarize/compress at ~90% context window to enable long-running sessions
5. **Multi-Agent Ready**: Sessions support multiple agents with attribution and handoffs

### Target Developer Experience

```swift
// Create a session
let store = InMemorySessionStore()
let session = try await Session.create(userId: "user_123", store: store)

// Use with agent
let agent = AIAgentActor(model: model, tools: [SearchTool.self])
for try await event in agent.streamExecute(messages: [.user("Hello")], session: session) {
    // Events auto-persist to session
}

// Resume later
let resumedSession = try await Session.load(id: session.id, store: store)
```

---

## 2. Research Summary: Industry Best Practices

### 2.1 OpenAI Agents SDK

| Aspect | Pattern |
|--------|---------|
| **Protocol** | `Session` with `get_items()`, `add_items()`, `pop_item()`, `clear_session()` |
| **Backends** | SQLite, SQLAlchemy, OpenAI Conversations API, Dapr, Encrypted wrapper |
| **Features** | Auto-compaction, branching, session sharing across agents |
| **ID Scheme** | Developer-provided `session_id` string |

### 2.2 Google ADK

| Aspect | Pattern |
|--------|---------|
| **Protocol** | `SessionService` manages `Session` objects |
| **Backends** | InMemory, VertexAI, Database (async drivers) |
| **Features** | Clear Session vs Memory separation, event-based state updates |
| **ID Scheme** | `session_id` + `user_id` + `app_name` composite |

### 2.3 Agno

| Aspect | Pattern |
|--------|---------|
| **Protocol** | `AgentSession` with full metadata |
| **Backends** | PostgreSQL, SQLite, DynamoDB |
| **Features** | Three memory types (session, user memories, summaries) |
| **ID Scheme** | `session_id` with `user_id` and `agent_id` associations |

### 2.4 Claude Code

| Aspect | Pattern |
|--------|---------|
| **Persistence** | Automatic checkpoint on every user prompt |
| **Features** | Rewind to any checkpoint, restore conversation + code |
| **Resume** | `--resume`, `-r "session-id"`, `-c` (most recent) |
| **Cleanup** | Auto-delete after 30 days (configurable) |
| **Subagents** | Task tool spawns independent agents with isolated context |

### 2.5 Key Insights

1. **Fine-grained persistence wins**: Claude Code checkpoints every prompt; OpenAI saves every item
2. **Sessions are message-centric**: Tool calls and steps are stored as messages (not separate tables)
3. **Protocol-first enables flexibility**: All SDKs define an abstract interface with multiple backends
4. **Compaction is essential**: Long sessions require summarization to fit context windows
5. **Multi-agent = session sharing**: Agents can share sessions or fork them for handoffs

---

## 3. Data Model

### 3.1 Session

```swift
/// A conversation session containing all state for an agent interaction.
///
/// Sessions are the primary unit of persistence in AISDK. They contain:
/// - Complete message history (including tool calls and results)
/// - Metadata (title, tags, timestamps)
/// - Checkpoint information for resume/rewind
/// - Agent attribution for multi-agent scenarios
public struct Session: Codable, Sendable, Identifiable {
    // MARK: - Identity
    
    /// Unique identifier for this session
    public let id: String
    
    /// User who owns this session (required for multi-session support)
    public let userId: String
    
    /// Optional agent identifier (for multi-agent attribution)
    public var agentId: String?
    
    // MARK: - Timestamps
    
    /// When the session was created
    public let createdAt: Date
    
    /// Last activity timestamp (updated on each message)
    public var lastActivityAt: Date
    
    // MARK: - Metadata
    
    /// Human-readable title (auto-generated on first user message)
    public var title: String?
    
    /// Optional tags for organization
    public var tags: [String]?
    
    /// Arbitrary metadata for application use
    public var metadata: [String: String]?
    
    // MARK: - Content
    
    /// Complete message history including tool calls and results.
    /// This is the canonical conversation state.
    public var messages: [AIMessage]
    
    // MARK: - State
    
    /// Current session status
    public var status: SessionStatus
    
    /// Index of the last complete checkpoint (for resume)
    public var lastCheckpointIndex: Int?
    
    /// Whether the last assistant message is complete
    public var isLastMessageComplete: Bool
    
    // MARK: - Initialization
    
    public init(
        id: String = UUID().uuidString,
        userId: String,
        agentId: String? = nil,
        title: String? = nil,
        messages: [AIMessage] = [],
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.userId = userId
        self.agentId = agentId
        self.createdAt = Date()
        self.lastActivityAt = Date()
        self.title = title
        self.messages = messages
        self.metadata = metadata
        self.status = .active
        self.lastCheckpointIndex = nil
        self.isLastMessageComplete = true
        self.tags = nil
    }
}
```

### 3.2 SessionStatus

```swift
/// Status of a session
public enum SessionStatus: String, Codable, Sendable {
    /// Session is active and accepting messages
    case active
    
    /// Session completed normally
    case completed
    
    /// Session paused (can be resumed)
    case paused
    
    /// Session ended with an error
    case error
    
    /// Session archived (read-only)
    case archived
}
```

### 3.3 AIMessage Extensions for Sessions

Tool calls, tool results, and reasoning are stored as part of the message stream (not separately). This aligns with how LLMs work: user → assistant (with tool_calls) → tool (result) → assistant (final).

```swift
extension AIMessage {
    /// Agent that produced this message (for multi-agent sessions)
    public var agentId: String? { get set }
    
    /// Agent name for display
    public var agentName: String? { get set }
    
    /// Whether this message represents a checkpoint
    public var isCheckpoint: Bool { get set }
    
    /// Checkpoint index (if this is a checkpoint)
    public var checkpointIndex: Int? { get set }
}
```

### 3.4 Checkpoint Model

Checkpoints are created on:
1. **Every user message** (user can rewind to any prompt)
2. **Every tool call completion** (recover from tool failures)
3. **Every complete assistant response** (resume point)

```swift
/// Represents a restorable point in the conversation
public struct SessionCheckpoint: Codable, Sendable {
    /// Index of this checkpoint
    public let index: Int
    
    /// Message index in the session
    public let messageIndex: Int
    
    /// Timestamp when checkpoint was created
    public let createdAt: Date
    
    /// Type of checkpoint
    public let type: CheckpointType
    
    /// Optional label for the checkpoint
    public var label: String?
}

public enum CheckpointType: String, Codable, Sendable {
    case userMessage
    case toolCallComplete
    case assistantComplete
    case manual
}
```

---

## 4. Storage Protocol

### 4.1 SessionStore Protocol

```swift
/// Protocol for session persistence backends.
///
/// Implementations must be thread-safe and handle concurrent access.
/// All operations are async to support network-backed stores.
public protocol SessionStore: Sendable {
    // MARK: - CRUD Operations
    
    /// Create a new session
    /// - Parameter session: The session to create
    /// - Returns: The created session (may have server-generated fields)
    func create(_ session: Session) async throws -> Session
    
    /// Load a session by ID
    /// - Parameter id: Session identifier
    /// - Returns: The session if found, nil otherwise
    func load(id: String) async throws -> Session?
    
    /// Save (update) an existing session
    /// - Parameter session: The session to save
    func save(_ session: Session) async throws
    
    /// Delete a session
    /// - Parameter id: Session identifier
    func delete(id: String) async throws
    
    // MARK: - Query Operations
    
    /// List sessions with filtering and pagination
    /// - Parameters:
    ///   - userId: Filter by user (required for multi-user apps)
    ///   - status: Optional status filter
    ///   - limit: Maximum number of results
    ///   - cursor: Pagination cursor from previous result
    ///   - orderBy: Sort order
    /// - Returns: Paginated list of session summaries
    func list(
        userId: String,
        status: SessionStatus?,
        limit: Int,
        cursor: String?,
        orderBy: SessionOrderBy
    ) async throws -> SessionListResult
    
    // MARK: - Incremental Updates (for streaming)
    
    /// Append a message to a session (optimized for streaming)
    /// - Parameters:
    ///   - message: The message to append
    ///   - sessionId: Target session
    func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws
    
    /// Update the last message in a session (for streaming deltas)
    /// - Parameters:
    ///   - message: The updated message
    ///   - sessionId: Target session
    func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws
    
    /// Update session status
    /// - Parameters:
    ///   - status: New status
    ///   - sessionId: Target session
    func updateStatus(_ status: SessionStatus, forSession sessionId: String) async throws
    
    /// Update session metadata (title, tags, etc.)
    /// - Parameters:
    ///   - updates: Fields to update
    ///   - sessionId: Target session
    func updateMetadata(_ updates: SessionMetadataUpdate, forSession sessionId: String) async throws
    
    // MARK: - Real-time (optional)
    
    /// Subscribe to session changes (for real-time UI updates)
    /// - Parameter sessionId: Session to observe
    /// - Returns: Stream of session updates
    func observe(sessionId: String) -> AsyncThrowingStream<Session, Error>?
}
```

### 4.2 Supporting Types

```swift
/// Sort order for session listing
public enum SessionOrderBy: String, Codable, Sendable {
    case createdAtAsc
    case createdAtDesc
    case lastActivityAtAsc
    case lastActivityAtDesc
}

/// Paginated session list result
public struct SessionListResult: Codable, Sendable {
    /// Session summaries (not full message history)
    public let sessions: [SessionSummary]
    
    /// Cursor for next page (nil if no more results)
    public let nextCursor: String?
    
    /// Total count (if available)
    public let totalCount: Int?
}

/// Lightweight session summary for listing
public struct SessionSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let userId: String
    public let title: String?
    public let status: SessionStatus
    public let createdAt: Date
    public let lastActivityAt: Date
    public let messageCount: Int
    public let tags: [String]?
}

/// Partial update for session metadata
public struct SessionMetadataUpdate: Codable, Sendable {
    public var title: String?
    public var tags: [String]?
    public var metadata: [String: String]?
    public var status: SessionStatus?
}
```

### 4.3 Error Types

```swift
/// Errors that can occur during session operations
public enum SessionStoreError: Error, Sendable {
    /// Session not found
    case notFound(sessionId: String)
    
    /// Session already exists (create conflict)
    case alreadyExists(sessionId: String)
    
    /// Storage backend unavailable
    case unavailable(underlying: Error)
    
    /// Invalid session data (decode error)
    case invalidData(reason: String)
    
    /// Operation not supported by this store
    case unsupported(operation: String)
    
    /// Permission denied
    case permissionDenied(reason: String)
}
```

---

## 5. Built-in Adapters

### 5.1 InMemorySessionStore (Default)

For testing, prototyping, and ephemeral use cases.

```swift
/// In-memory session store for testing and development.
///
/// All data is lost when the process terminates.
/// Thread-safe via actor isolation.
public actor InMemorySessionStore: SessionStore {
    private var sessions: [String: Session] = [:]
    
    public init() {}
    
    // ... implementation
}
```

### 5.2 FileSystemSessionStore

For CLI tools and local apps that need persistence without a database.

```swift
/// File-based session store using JSON files.
///
/// Sessions are stored as individual JSON files in a directory.
/// Suitable for CLI tools and single-user desktop apps.
public actor FileSystemSessionStore: SessionStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    /// Create a file system store
    /// - Parameter directory: Directory to store session files
    public init(directory: URL) {
        self.directory = directory
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    // ... implementation
}
```

### 5.3 SQLiteSessionStore

For mobile apps and desktop apps requiring structured storage.

```swift
/// SQLite-based session store for local persistence.
///
/// Uses a single table with JSON message storage for simplicity.
/// Supports efficient queries by userId, status, and timestamps.
public actor SQLiteSessionStore: SessionStore {
    private let dbPath: String
    private var connection: SQLiteConnection?
    
    /// Create a SQLite store
    /// - Parameter path: Path to SQLite database file
    ///   Use `:memory:` for in-memory database
    public init(path: String = ":memory:") {
        self.dbPath = path
    }
    
    // ... implementation
}
```

### 5.4 FirebaseSessionStore

For cloud-synced apps with real-time updates.

```swift
/// Firebase Firestore-based session store.
///
/// Provides real-time sync and multi-device support.
/// Sessions are stored in a `sessions` collection with userId index.
public actor FirebaseSessionStore: SessionStore {
    private let collectionPath: String
    
    /// Create a Firebase store
    /// - Parameter collectionPath: Firestore collection path (default: "sessions")
    public init(collectionPath: String = "sessions") {
        self.collectionPath = collectionPath
    }
    
    // Supports real-time observation
    public func observe(sessionId: String) -> AsyncThrowingStream<Session, Error>? {
        // Returns Firestore snapshot listener as AsyncStream
    }
    
    // ... implementation
}
```

---

## 6. Context Management & Compaction

### 6.1 Context Policy

Sessions can have an associated context policy for automatic management.

```swift
/// Policy for managing session context size
public struct ContextPolicy: Codable, Sendable {
    /// Maximum tokens before compaction triggers (nil = unlimited)
    public var maxTokens: Int?
    
    /// Trigger compaction at this percentage of max tokens (default: 0.9)
    public var compactionThreshold: Double
    
    /// Strategy for reducing context size
    public var compactionStrategy: CompactionStrategy
    
    /// Always preserve the system prompt
    public var preserveSystemPrompt: Bool
    
    /// Minimum messages to keep after compaction
    public var minMessagesToKeep: Int
    
    public static let `default` = ContextPolicy(
        maxTokens: nil,
        compactionThreshold: 0.9,
        compactionStrategy: .summarize,
        preserveSystemPrompt: true,
        minMessagesToKeep: 4
    )
    
    public init(
        maxTokens: Int? = nil,
        compactionThreshold: Double = 0.9,
        compactionStrategy: CompactionStrategy = .summarize,
        preserveSystemPrompt: Bool = true,
        minMessagesToKeep: Int = 4
    ) {
        self.maxTokens = maxTokens
        self.compactionThreshold = compactionThreshold
        self.compactionStrategy = compactionStrategy
        self.preserveSystemPrompt = preserveSystemPrompt
        self.minMessagesToKeep = minMessagesToKeep
    }
}

/// Strategy for compacting context
public enum CompactionStrategy: String, Codable, Sendable {
    /// Drop oldest messages (FIFO)
    case truncate
    
    /// Summarize old messages into a memory message
    case summarize
    
    /// Sliding window: keep first N + last M messages
    case slidingWindow
}
```

### 6.2 Compaction Service

```swift
/// Service for compacting session context
public actor SessionCompactionService {
    private let model: any AILanguageModel
    
    public init(model: any AILanguageModel) {
        self.model = model
    }
    
    /// Check if session needs compaction
    /// - Parameters:
    ///   - session: Session to check
    ///   - policy: Context policy
    ///   - modelContextLimit: Target model's context window
    /// - Returns: True if compaction is needed
    public func needsCompaction(
        session: Session,
        policy: ContextPolicy,
        modelContextLimit: Int
    ) async -> Bool {
        let effectiveLimit = policy.maxTokens ?? modelContextLimit
        let threshold = Int(Double(effectiveLimit) * policy.compactionThreshold)
        let currentTokens = await estimateTokens(session.messages)
        return currentTokens >= threshold
    }
    
    /// Compact a session according to policy
    /// - Parameters:
    ///   - session: Session to compact
    ///   - policy: Context policy
    /// - Returns: Compacted session with reduced message history
    public func compact(
        session: Session,
        policy: ContextPolicy
    ) async throws -> Session {
        var compacted = session
        
        switch policy.compactionStrategy {
        case .truncate:
            compacted.messages = truncateMessages(
                session.messages,
                keepLast: policy.minMessagesToKeep,
                preserveSystem: policy.preserveSystemPrompt
            )
            
        case .summarize:
            let summary = try await summarizeMessages(session.messages)
            compacted.messages = buildCompactedHistory(
                original: session.messages,
                summary: summary,
                policy: policy
            )
            
        case .slidingWindow:
            compacted.messages = slidingWindow(
                session.messages,
                keepFirst: policy.preserveSystemPrompt ? 1 : 0,
                keepLast: policy.minMessagesToKeep
            )
        }
        
        return compacted
    }
    
    // ... private implementation methods
}
```

---

## 7. Title Generation

### 7.1 Title Generator Protocol

```swift
/// Protocol for generating session titles
public protocol SessionTitleGenerator: Sendable {
    /// Generate a title for a session based on its content
    /// - Parameter session: Session to generate title for
    /// - Returns: Generated title
    func generateTitle(for session: Session) async throws -> String
}
```

### 7.2 Default Implementation

```swift
/// Default LLM-based title generator
public actor DefaultTitleGenerator: SessionTitleGenerator {
    private let model: any AILanguageModel
    
    public init(model: any AILanguageModel) {
        self.model = model
    }
    
    public func generateTitle(for session: Session) async throws -> String {
        // Get first few messages for context
        let contextMessages = session.messages.prefix(6)
        
        let prompt = """
        Generate a short, concise title (max 5 words) for this conversation:
        
        \(contextMessages.map { formatMessage($0) }.joined(separator: "\n"))
        
        Title:
        """
        
        let request = AITextRequest(
            messages: [.user(prompt)],
            maxTokens: 20,
            temperature: 0.7
        )
        
        let result = try await model.generateText(request: request)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

### 7.3 Integration with Session

Title generation is triggered asynchronously after the first user message:

```swift
extension Session {
    /// Generate title if needed (called after first user message)
    public mutating func generateTitleIfNeeded(
        using generator: SessionTitleGenerator
    ) async {
        guard title == nil else { return }
        guard messages.contains(where: { $0.role == .user }) else { return }
        
        do {
            title = try await generator.generateTitle(for: self)
        } catch {
            // Title generation is non-critical; use fallback
            title = "New Conversation"
        }
    }
}
```

---

## 8. Agent Integration

### 8.1 Session-Aware Agent Execution

```swift
extension AIAgentActor {
    /// Execute with session persistence
    ///
    /// Messages are automatically loaded from and saved to the session.
    /// Checkpoints are created on user messages, tool completions, and assistant responses.
    ///
    /// - Parameters:
    ///   - userMessage: New user message to add
    ///   - session: Session for persistence
    ///   - store: Storage backend
    /// - Returns: Updated session with new messages
    public func execute(
        userMessage: AIMessage,
        session: inout Session,
        store: SessionStore
    ) async throws -> AIAgentResult {
        // Add user message and create checkpoint
        session.messages.append(userMessage)
        session.lastActivityAt = Date()
        session.lastCheckpointIndex = session.messages.count - 1
        try await store.appendMessage(userMessage, toSession: session.id)
        
        // Execute agent with session messages
        let result = try await execute(messages: session.messages)
        
        // Append result messages to session
        for message in result.messages.dropFirst(session.messages.count) {
            session.messages.append(message)
            try await store.appendMessage(message, toSession: session.id)
        }
        
        session.isLastMessageComplete = true
        try await store.save(session)
        
        return result
    }
    
    /// Stream execute with session persistence
    ///
    /// Events are persisted incrementally as they arrive.
    /// Partial responses are marked incomplete until finished.
    public func streamExecute(
        userMessage: AIMessage,
        session: inout Session,
        store: SessionStore
    ) -> AsyncThrowingStream<AIStreamEvent, Error> {
        // Implementation with incremental persistence
    }
}
```

### 8.2 Auto-Save Behavior

The agent automatically saves after each significant event:

| Event | Persistence Action |
|-------|-------------------|
| User message received | `appendMessage()` + create checkpoint |
| Tool call started | `appendMessage()` (assistant with tool_calls) |
| Tool result received | `appendMessage()` (tool result) + create checkpoint |
| Text delta (streaming) | `updateLastMessage()` (debounced, every 500ms) |
| Assistant complete | `appendMessage()` + create checkpoint + mark complete |
| Error occurred | `updateStatus(.error)` |

### 8.3 Streaming Delta Persistence

Text deltas are debounced to reduce I/O overhead while still preserving progress:

```swift
/// Debounced persistence for streaming deltas
actor StreamingPersistenceBuffer {
    private let store: SessionStore
    private let sessionId: String
    private let debounceInterval: Duration = .milliseconds(500)
    
    private var pendingMessage: AIMessage?
    private var debounceTask: Task<Void, Never>?
    
    /// Buffer a streaming delta for persistence
    func bufferDelta(_ message: AIMessage) async {
        pendingMessage = message
        
        // Cancel existing debounce
        debounceTask?.cancel()
        
        // Schedule new flush
        debounceTask = Task {
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            await flush()
        }
    }
    
    /// Immediately persist pending message
    func flush() async {
        guard let message = pendingMessage else { return }
        pendingMessage = nil
        try? await store.updateLastMessage(message, inSession: sessionId)
    }
}
```

This ensures:
- At most 2 writes per second during streaming
- No data loss on normal completion (final flush)
- Recoverable progress on crash (up to 500ms of text lost)

### 8.3 Resume from Checkpoint

```swift
extension Session {
    /// Get messages up to a specific checkpoint
    /// - Parameter checkpointIndex: Checkpoint to restore to
    /// - Returns: Messages up to and including the checkpoint
    public func messagesAtCheckpoint(_ checkpointIndex: Int) -> [AIMessage] {
        guard checkpointIndex >= 0,
              checkpointIndex < messages.count else {
            return messages
        }
        return Array(messages.prefix(checkpointIndex + 1))
    }
    
    /// Rewind session to a checkpoint
    /// - Parameter checkpointIndex: Checkpoint to rewind to
    public mutating func rewind(to checkpointIndex: Int) {
        guard checkpointIndex >= 0,
              checkpointIndex < messages.count else { return }
        
        messages = Array(messages.prefix(checkpointIndex + 1))
        lastCheckpointIndex = checkpointIndex
        isLastMessageComplete = true
        lastActivityAt = Date()
    }
}
```

---

## 9. Multi-Agent Support

### 9.1 Agent Attribution

Messages track which agent produced them for multi-agent scenarios:

```swift
extension AIMessage {
    /// Create an assistant message with agent attribution
    public static func assistant(
        _ content: String,
        agentId: String? = nil,
        agentName: String? = nil,
        toolCalls: [ToolCall]? = nil
    ) -> AIMessage {
        var message = AIMessage.assistant(content, toolCalls: toolCalls)
        message.agentId = agentId
        message.agentName = agentName
        return message
    }
}
```

### 9.2 Session Sharing (Handoffs)

Following the Swarm pattern, agents can share a session:

```swift
/// Handoff context for agent transfers
public struct AgentHandoff: Sendable {
    /// Agent to transfer to
    public let targetAgent: AIAgentActor
    
    /// Optional summary for the receiving agent
    public let summary: String?
    
    /// Whether to fork the session (copy) or share it
    public let fork: Bool
    
    public init(
        to agent: AIAgentActor,
        summary: String? = nil,
        fork: Bool = false
    ) {
        self.targetAgent = agent
        self.summary = summary
        self.fork = fork
    }
}

extension Session {
    /// Fork this session for a handoff
    /// - Returns: New session with copied messages and new ID
    public func fork() -> Session {
        var forked = self
        forked.id = UUID().uuidString
        forked.createdAt = Date()
        return forked
    }
}
```

### 9.3 Subagent Pattern

Following Claude Code's Task tool pattern, subagents can:
1. **Share the session**: All messages visible to all agents
2. **Fork the session**: Subagent gets a copy, results summarized back
3. **Independent context**: Subagent has its own session (most isolated)

```swift
/// Subagent execution options
public struct SubagentOptions: Sendable {
    /// How the subagent accesses session state
    public enum SessionMode: Sendable {
        /// Subagent shares the parent's session
        case shared
        
        /// Subagent gets a forked copy of the session
        case forked
        
        /// Subagent has its own empty session
        case independent
    }
    
    public let sessionMode: SessionMode
    public let returnSummary: Bool
    
    public static let `default` = SubagentOptions(
        sessionMode: .independent,
        returnSummary: true
    )
}
```

---

## 10. Error Handling

### 10.1 Storage Errors

Storage errors propagate to the caller (fail loudly):

```swift
// Errors are thrown, not swallowed
do {
    try await store.save(session)
} catch SessionStoreError.unavailable(let underlying) {
    // Handle network/database error
    // Option: Fall back to in-memory, warn user
} catch SessionStoreError.invalidData(let reason) {
    // Handle corruption - this is serious
    logger.error("Session data corrupted: \(reason)")
}
```

### 10.2 Partial Save on Streaming Errors

If streaming fails mid-response, the session is saved with `isLastMessageComplete = false`:

```swift
// On stream error
session.isLastMessageComplete = false
session.status = .paused
try await store.save(session)

// On resume, user can choose to:
// 1. Retry the last turn (remove incomplete message)
// 2. Continue from partial (risky but preserves work)
```

### 10.3 Corrupted Sessions

If a session fails to decode, return nil (not found):

```swift
func load(id: String) async throws -> Session? {
    guard let data = try await loadData(id) else {
        return nil  // Not found
    }
    
    do {
        return try decoder.decode(Session.self, from: data)
    } catch {
        // Log the corruption for debugging
        logger.error("Failed to decode session \(id): \(error)")
        // Return nil - effectively "not found"
        // Alternative: throw SessionStoreError.invalidData
        return nil
    }
}
```

---

## 11. API Reference Summary

### 11.1 Core Types

| Type | Description |
|------|-------------|
| `Session` | Complete conversation state |
| `SessionStatus` | Session lifecycle status |
| `SessionCheckpoint` | Restorable point in conversation |
| `SessionSummary` | Lightweight listing model |

### 11.2 Protocols

| Protocol | Description |
|----------|-------------|
| `SessionStore` | Storage backend abstraction |
| `SessionTitleGenerator` | Title generation abstraction |

### 11.3 Built-in Stores

| Store | Use Case |
|-------|----------|
| `InMemorySessionStore` | Testing, prototyping (default) |
| `FileSystemSessionStore` | CLI tools, single-user apps |
| `SQLiteSessionStore` | Mobile apps, desktop apps |
| `FirebaseSessionStore` | Cloud sync, multi-device |

### 11.4 Services

| Service | Description |
|---------|-------------|
| `SessionCompactionService` | Context window management |
| `DefaultTitleGenerator` | LLM-based title generation |

---

## 12. Implementation Plan

### Phase 1: Core Foundation (Week 1-2)

1. **Data Model**
   - [ ] Implement `Session` struct
   - [ ] Implement `SessionStatus` enum
   - [ ] Extend `AIMessage` with session metadata
   
2. **SessionStore Protocol**
   - [ ] Define `SessionStore` protocol
   - [ ] Define error types
   - [ ] Define supporting types (list result, summary, etc.)

3. **InMemorySessionStore**
   - [ ] Implement all CRUD operations
   - [ ] Implement query operations
   - [ ] Add tests

### Phase 2: Local Persistence (Week 2-3)

4. **FileSystemSessionStore**
   - [ ] Implement JSON file storage
   - [ ] Handle concurrent access
   - [ ] Add tests

5. **SQLiteSessionStore**
   - [ ] Design schema
   - [ ] Implement CRUD operations
   - [ ] Implement queries with indexes
   - [ ] Add tests

### Phase 3: Agent Integration (Week 3-4)

6. **AIAgentActor Extensions**
   - [ ] Add `execute(session:store:)` method
   - [ ] Add `streamExecute(session:store:)` method
   - [ ] Implement auto-save behavior
   - [ ] Implement checkpointing

7. **Resume/Rewind**
   - [ ] Implement `Session.rewind(to:)`
   - [ ] Implement `Session.messagesAtCheckpoint(_:)`
   - [ ] Add retry logic for incomplete responses

### Phase 4: Context Management (Week 4-5)

8. **Context Policy**
   - [ ] Implement `ContextPolicy` struct
   - [ ] Implement `CompactionStrategy` enum

9. **SessionCompactionService**
   - [ ] Implement token estimation
   - [ ] Implement truncation strategy
   - [ ] Implement summarization strategy
   - [ ] Implement sliding window strategy
   - [ ] Integrate with agent execution

### Phase 5: Cloud Storage (Week 5-6)

10. **FirebaseSessionStore**
    - [ ] Implement Firestore CRUD
    - [ ] Implement real-time observation
    - [ ] Handle offline/online transitions
    - [ ] Add tests

11. **Title Generation**
    - [ ] Implement `SessionTitleGenerator` protocol
    - [ ] Implement `DefaultTitleGenerator`
    - [ ] Integrate async title generation

### Phase 6: Multi-Agent (Week 6-7)

12. **Agent Attribution**
    - [ ] Add `agentId`/`agentName` to messages
    - [ ] Track attribution in session

13. **Handoffs & Subagents**
    - [ ] Implement `AgentHandoff` model
    - [ ] Implement `Session.fork()`
    - [ ] Implement `SubagentOptions`

### Phase 7: Export, Search & Testing (Week 7-8)

14. **Export/Import**
    - [ ] Implement `Session.exportJSON()`
    - [ ] Implement `Session.exportMarkdown()`
    - [ ] Implement `Session.importJSON()`
    - [ ] Implement bulk export for stores

15. **Search**
    - [ ] Define `SearchableSessionStore` protocol
    - [ ] Implement SQLite FTS5 search
    - [ ] Document Firebase search integration options

16. **Testing Support**
    - [ ] Implement `MockSessionStore`
    - [ ] Implement `SessionTestHelpers`
    - [ ] Add operation recording and assertions

### Phase 8: Documentation & Polish (Week 8-9)

17. **Documentation**
    - [ ] API reference docs
    - [ ] Tutorial: Basic session usage
    - [ ] Tutorial: Custom storage backend
    - [ ] Tutorial: Multi-agent sessions
    - [ ] Tutorial: Export and search
    - [ ] Migration guide from AIChatManager

18. **Testing**
    - [ ] Unit tests for all stores
    - [ ] Integration tests with AIAgentActor
    - [ ] Stress tests for concurrent access
    - [ ] Performance benchmarks
    - [ ] Search accuracy tests

---

## 13. Migration from AIChatManager

For users of the current `AIChatManager`:

### 13.1 Conceptual Mapping

| AIChatManager | New Sessions API |
|---------------|------------------|
| `ChatSession` | `Session` |
| `chatSessions: [ChatSession]` | `store.list(userId:)` |
| `currentSession` | Managed by app (pass to agent) |
| `messages` | `session.messages` |
| `loadSession()` | `Session.load(id:store:)` |
| `createNewSession()` | `Session.create(userId:store:)` |
| `storeMessage()` | Auto-saved by agent |
| `generateTitle()` | `DefaultTitleGenerator` |

### 13.2 Migration Example

Before:
```swift
let manager = AIChatManager()
manager.loadChatSessions()
manager.sendMessage("Hello")
```

After:
```swift
let store = FirebaseSessionStore()
var session = try await Session.create(userId: userId, store: store)
let agent = AIAgentActor(model: model, tools: tools)

let result = try await agent.execute(
    userMessage: .user("Hello"),
    session: &session,
    store: store
)
```

---

## 14. Export & Import

Sessions support export for backup, sharing, and debugging.

### 14.1 Export Formats

```swift
extension Session {
    /// Export session to JSON
    public func exportJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    
    /// Export session to Markdown for human readability
    public func exportMarkdown() -> String {
        var md = "# \(title ?? "Untitled Conversation")\n\n"
        md += "**Created:** \(createdAt.formatted())\n"
        md += "**Last Activity:** \(lastActivityAt.formatted())\n"
        md += "**Messages:** \(messages.count)\n\n"
        md += "---\n\n"
        
        for message in messages {
            switch message.role {
            case .user:
                md += "## User\n\n\(message.content)\n\n"
            case .assistant:
                let agent = message.agentName ?? "Assistant"
                md += "## \(agent)\n\n\(message.content)\n\n"
            case .tool:
                md += "> **Tool Result** (\(message.toolCallId ?? "unknown"))\n>\n"
                md += "> \(message.content)\n\n"
            case .system:
                md += "*System: \(message.content.prefix(100))...*\n\n"
            }
        }
        
        return md
    }
    
    /// Import session from JSON
    public static func importJSON(_ data: Data) throws -> Session {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Session.self, from: data)
    }
}
```

### 14.2 Bulk Export

```swift
extension SessionStore {
    /// Export all sessions for a user (for backup/migration)
    func exportAll(userId: String) async throws -> Data {
        var allSessions: [Session] = []
        var cursor: String? = nil
        
        repeat {
            let result = try await list(
                userId: userId,
                status: nil,
                limit: 100,
                cursor: cursor,
                orderBy: .createdAtAsc
            )
            
            for summary in result.sessions {
                if let session = try await load(id: summary.id) {
                    allSessions.append(session)
                }
            }
            
            cursor = result.nextCursor
        } while cursor != nil
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(allSessions)
    }
}
```

---

## 15. Search

### 15.1 Search Protocol Extension

```swift
/// Extended protocol for stores that support full-text search
public protocol SearchableSessionStore: SessionStore {
    /// Search sessions by message content
    /// - Parameters:
    ///   - query: Search query string
    ///   - userId: Filter by user
    ///   - limit: Maximum results
    /// - Returns: Matching session summaries with relevance scores
    func search(
        query: String,
        userId: String,
        limit: Int
    ) async throws -> [SearchResult]
}

/// Search result with relevance information
public struct SearchResult: Codable, Sendable {
    public let session: SessionSummary
    public let relevanceScore: Double
    public let matchingSnippets: [String]
}
```

### 15.2 SQLite Full-Text Search

```swift
extension SQLiteSessionStore: SearchableSessionStore {
    /// Initialize with FTS support
    public init(path: String, enableFTS: Bool = true) {
        // Creates FTS5 virtual table for message content
    }
    
    public func search(
        query: String,
        userId: String,
        limit: Int
    ) async throws -> [SearchResult] {
        // Uses SQLite FTS5 for efficient full-text search
        let sql = """
            SELECT s.*, snippet(messages_fts, 0, '<b>', '</b>', '...', 32) as snippet,
                   bm25(messages_fts) as score
            FROM sessions s
            JOIN messages_fts ON s.id = messages_fts.session_id
            WHERE messages_fts MATCH ? AND s.user_id = ?
            ORDER BY score
            LIMIT ?
        """
        // ... execute query
    }
}
```

### 15.3 Firebase Search

For Firebase, full-text search requires integration with external services:

```swift
extension FirebaseSessionStore: SearchableSessionStore {
    /// Search using Algolia or Typesense (requires additional setup)
    public func search(
        query: String,
        userId: String,
        limit: Int
    ) async throws -> [SearchResult] {
        // Option 1: Algolia integration
        // Option 2: Typesense integration  
        // Option 3: Firebase Extensions for search
        throw SessionStoreError.unsupported(
            operation: "search - configure Algolia or Typesense extension"
        )
    }
}
```

---

## 16. Testing Support

### 16.1 MockSessionStore

```swift
/// Mock session store for testing with operation recording
public actor MockSessionStore: SessionStore {
    // MARK: - Recorded Operations
    
    public private(set) var createCalls: [(Session, Date)] = []
    public private(set) var loadCalls: [(String, Date)] = []
    public private(set) var saveCalls: [(Session, Date)] = []
    public private(set) var deleteCalls: [(String, Date)] = []
    public private(set) var appendMessageCalls: [(AIMessage, String, Date)] = []
    
    // MARK: - Configurable Behavior
    
    /// Sessions to return from load()
    public var sessions: [String: Session] = [:]
    
    /// Error to throw on next operation (then cleared)
    public var nextError: Error?
    
    /// Delay to add to operations (for testing async behavior)
    public var operationDelay: Duration?
    
    // MARK: - Convenience Accessors
    
    public var saveCount: Int { saveCalls.count }
    public var lastSavedSession: Session? { saveCalls.last?.0 }
    public var lastLoadedId: String? { loadCalls.last?.0 }
    
    // MARK: - SessionStore Implementation
    
    public func create(_ session: Session) async throws -> Session {
        if let delay = operationDelay {
            try await Task.sleep(for: delay)
        }
        if let error = nextError {
            nextError = nil
            throw error
        }
        createCalls.append((session, Date()))
        sessions[session.id] = session
        return session
    }
    
    public func load(id: String) async throws -> Session? {
        if let delay = operationDelay {
            try await Task.sleep(for: delay)
        }
        if let error = nextError {
            nextError = nil
            throw error
        }
        loadCalls.append((id, Date()))
        return sessions[id]
    }
    
    public func save(_ session: Session) async throws {
        if let delay = operationDelay {
            try await Task.sleep(for: delay)
        }
        if let error = nextError {
            nextError = nil
            throw error
        }
        saveCalls.append((session, Date()))
        sessions[session.id] = session
    }
    
    public func delete(id: String) async throws {
        if let delay = operationDelay {
            try await Task.sleep(for: delay)
        }
        if let error = nextError {
            nextError = nil
            throw error
        }
        deleteCalls.append((id, Date()))
        sessions.removeValue(forKey: id)
    }
    
    // ... other methods
    
    // MARK: - Test Helpers
    
    /// Reset all recorded operations
    public func reset() {
        createCalls = []
        loadCalls = []
        saveCalls = []
        deleteCalls = []
        appendMessageCalls = []
        sessions = [:]
        nextError = nil
    }
    
    /// Assert a specific sequence of operations occurred
    public func assertOperationSequence(_ expected: [OperationType]) {
        // Implementation for test assertions
    }
}

public enum OperationType {
    case create, load, save, delete, appendMessage, updateLastMessage
}
```

### 16.2 Test Helpers

```swift
/// Test utilities for session testing
public enum SessionTestHelpers {
    /// Create a session with sample messages for testing
    public static func sampleSession(
        userId: String = "test_user",
        messageCount: Int = 5
    ) -> Session {
        var session = Session(userId: userId)
        session.title = "Test Conversation"
        
        for i in 0..<messageCount {
            if i % 2 == 0 {
                session.messages.append(.user("User message \(i)"))
            } else {
                session.messages.append(.assistant("Assistant response \(i)"))
            }
        }
        
        return session
    }
    
    /// Create a session with tool calls for testing
    public static func sessionWithToolCalls(userId: String = "test_user") -> Session {
        var session = Session(userId: userId)
        session.messages = [
            .user("What's the weather?"),
            .assistant("", toolCalls: [
                .init(id: "call_1", name: "get_weather", arguments: "{\"city\":\"Tokyo\"}")
            ]),
            .tool("72°F, sunny", toolCallId: "call_1"),
            .assistant("The weather in Tokyo is 72°F and sunny.")
        ]
        return session
    }
}
```

---

## 17. Open Questions

1. **Schema versioning**: How do we handle session schema changes across app updates?
   - Option A: Version field + migration on load
   - Option B: Backwards-compatible additions only
   
2. **Offline-first for Firebase**: Should we add local caching layer?
   - Firebase has built-in offline support
   - May need custom handling for long offline periods

3. **Encryption at rest**: Should we provide `EncryptedSessionStore` wrapper?
   - OpenAI SDK has this
   - Could be a separate package

### Decisions Made

- **Session lifecycle**: Developer manages (no auto-archive)
- **Session/message limits**: None enforced by SDK (app-level policy)
- **Streaming persistence**: Debounced at 500ms intervals

---

## 18. Appendix: Usage Examples

### A. Basic Session Usage

```swift
// Create store and session
let store = SQLiteSessionStore(path: "conversations.db")
let session = try await Session.create(userId: "user_123", store: store)

// Create agent
let agent = AIAgentActor(
    model: OpenRouterClient(modelId: "anthropic/claude-3.5-sonnet"),
    tools: [SearchTool.self]
)

// Execute with session
var mutableSession = session
let result = try await agent.execute(
    userMessage: .user("What's the weather in Tokyo?"),
    session: &mutableSession,
    store: store
)

print(result.text)
// Session auto-saved with all messages
```

### B. Streaming with Session

```swift
var session = try await Session.load(id: sessionId, store: store)!

for try await event in agent.streamExecute(
    userMessage: .user("Tell me a story"),
    session: &session,
    store: store
) {
    switch event {
    case .textDelta(let text):
        print(text, terminator: "")
    case .stepFinish(let index, let result):
        // Checkpoint created
        print("\n[Step \(index) complete]")
    case .finish:
        print("\n[Done]")
    default:
        break
    }
}
```

### C. Resume from Checkpoint

```swift
// Load session
var session = try await Session.load(id: sessionId, store: store)!

// Check if last message was incomplete
if !session.isLastMessageComplete {
    // Remove incomplete message and retry
    session.messages.removeLast()
    session.isLastMessageComplete = true
    try await store.save(session)
}

// Continue conversation
let result = try await agent.execute(
    userMessage: .user("Please continue"),
    session: &session,
    store: store
)
```

### D. Multi-Agent Handoff

```swift
let triageAgent = AIAgentActor(
    model: model,
    tools: [TransferToSalesAgent.self, TransferToSupportAgent.self],
    instructions: "Triage customer requests"
)

let salesAgent = AIAgentActor(
    model: model,
    tools: [PlaceOrder.self],
    instructions: "Help with purchases"
)

// Start with triage
var session = try await Session.create(userId: userId, store: store)
let result = try await triageAgent.execute(
    userMessage: .user("I want to buy something"),
    session: &session,
    store: store
)

// Check for handoff
if let handoff = result.handoff {
    // Continue with sales agent (shared session)
    let salesResult = try await handoff.targetAgent.execute(
        userMessage: .user("What do you recommend?"),
        session: &session,
        store: store
    )
}
```

### E. Export Session

```swift
// Export to JSON for backup
let jsonData = try session.exportJSON()
try jsonData.write(to: backupURL)

// Export to Markdown for sharing
let markdown = session.exportMarkdown()
print(markdown)
// Output:
// # Weather Chat
//
// **Created:** Jan 31, 2026 at 3:45 PM
// **Last Activity:** Jan 31, 2026 at 3:47 PM
// **Messages:** 4
//
// ---
//
// ## User
//
// What's the weather in Tokyo?
//
// ## Assistant
//
// The weather in Tokyo is 72°F and sunny with light winds.
// ...

// Import from backup
let importedData = try Data(contentsOf: backupURL)
let restoredSession = try Session.importJSON(importedData)
```

### F. Search Sessions

```swift
// SQLite with FTS enabled
let store = SQLiteSessionStore(path: "conversations.db", enableFTS: true)

// Search for sessions mentioning "weather"
let results = try await store.search(
    query: "weather tokyo",
    userId: "user_123",
    limit: 10
)

for result in results {
    print("\(result.session.title ?? "Untitled") - Score: \(result.relevanceScore)")
    for snippet in result.matchingSnippets {
        print("  ...\(snippet)...")
    }
}
// Output:
// Weather Chat - Score: 0.95
//   ...What's the <b>weather</b> in <b>Tokyo</b>?...
//   ...The <b>weather</b> in <b>Tokyo</b> is 72°F...
```

### G. Testing with MockSessionStore

```swift
func testAgentSavesMessagesOnExecute() async throws {
    // Arrange
    let mockStore = MockSessionStore()
    var session = Session(userId: "test_user")
    mockStore.sessions[session.id] = session
    
    let agent = AIAgentActor(model: mockModel, tools: [])
    
    // Act
    _ = try await agent.execute(
        userMessage: .user("Hello"),
        session: &session,
        store: mockStore
    )
    
    // Assert
    XCTAssertEqual(mockStore.saveCount, 1)
    XCTAssertEqual(mockStore.appendMessageCalls.count, 2) // user + assistant
    XCTAssertEqual(mockStore.lastSavedSession?.messages.count, 2)
}

func testAgentHandlesStorageError() async throws {
    // Arrange
    let mockStore = MockSessionStore()
    mockStore.nextError = SessionStoreError.unavailable(
        underlying: NSError(domain: "Test", code: -1)
    )
    
    var session = Session(userId: "test_user")
    let agent = AIAgentActor(model: mockModel, tools: [])
    
    // Act & Assert
    await XCTAssertThrowsError(
        try await agent.execute(
            userMessage: .user("Hello"),
            session: &session,
            store: mockStore
        )
    ) { error in
        XCTAssertTrue(error is SessionStoreError)
    }
}
```

---

*This specification is a living document and will be updated as implementation progresses.*
