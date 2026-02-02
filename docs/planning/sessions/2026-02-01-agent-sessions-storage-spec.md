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
3. **Agent API Unchanged**: The agent's `streamExecute(messages:)` stays pure—session management is a ViewModel concern
4. **Fine-Grained Persistence**: Save after each event for crash recovery (like Claude Code)
5. **Auto-Compaction**: Summarize/compress at ~90% context window to enable long-running sessions
6. **Multi-Agent Ready**: Sessions support multiple agents with attribution and handoffs
7. **SwiftUI-First**: `ChatViewModel` provides `@Observable` state for real-time UI updates

### Target Developer Experience

```swift
// Setup
let store = SQLiteSessionStore(path: "conversations.db")
let agent = AIAgentActor(model: model, tools: [SearchTool.self])
let session = Session(userId: "user_123")

// Use via ViewModel (recommended for SwiftUI)
let viewModel = ChatViewModel(session: session, agent: agent, store: store)
await viewModel.send([.text("Hello")])  // Session auto-persists

// Or use agent directly (agent API unchanged)
session.messages.append(.user("Hello"))
for try await event in agent.streamExecute(messages: session.messages) {
    // Handle events, update session manually
}
try await store.save(session)

// Resume later
if let resumedSession = try await store.load(id: session.id) {
    let viewModel = ChatViewModel(session: resumedSession, agent: agent, store: store)
}
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
public struct Session: Codable, Sendable, Identifiable, Hashable, Equatable {
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
    
    // MARK: - Hashable (uses id only for identity)
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Factory Methods

extension Session {
    /// Create and persist a new session
    public static func create(
        userId: String,
        store: SessionStore,
        agentId: String? = nil,
        title: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> Session {
        let session = Session(
            userId: userId,
            agentId: agentId,
            title: title,
            metadata: metadata
        )
        return try await store.create(session)
    }
    
    /// Load an existing session
    public static func load(id: String, store: SessionStore) async throws -> Session? {
        try await store.load(id: id)
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

### 3.3 AIMessage Session Properties

Tool calls, tool results, and reasoning are stored as part of the message stream (not separately). This aligns with how LLMs work: user → assistant (with tool_calls) → tool (result) → assistant (final).

**Implementation Note:** These properties must be added directly to the `AIMessage` struct (Swift extensions cannot add stored properties). Add to `Sources/AISDK/Models/AIMessage.swift`:

```swift
// Add these properties to AIMessage struct directly:
public struct AIMessage: Codable, Sendable {
    // ... existing properties ...
    
    // MARK: - Session Properties
    
    /// Agent that produced this message (for multi-agent sessions)
    public var agentId: String?
    
    /// Agent name for display
    public var agentName: String?
    
    /// Whether this message represents a checkpoint
    public var isCheckpoint: Bool = false
    
    /// Checkpoint index (if this is a checkpoint)
    public var checkpointIndex: Int?
}
```

### 3.4 Checkpoint Model

Checkpoints are created on:
1. **Every user message** (user can rewind to any prompt)
2. **Every tool call completion** (recover from tool failures)
3. **Every complete assistant response** (resume point)

```swift
/// Represents a restorable point in the conversation
public struct SessionCheckpoint: Codable, Sendable, Hashable {
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
    case unavailable(reason: String)
    
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

### 8.1 Architecture Decision: ViewModel-Managed Sessions

**The agent API remains unchanged.** Session management is handled by the ViewModel layer, not the agent. This provides:

- **Clean separation**: Agent is stateless regarding sessions
- **Full control**: ViewModel decides when/how to persist
- **SwiftUI optimized**: Single observable source of truth
- **Testable**: Agent and session logic can be tested independently

```
┌─────────────────────────────────────────────────────────────┐
│                        SwiftUI View                         │
│                    observes viewModel                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     ChatViewModel                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │   Session   │  │    Agent    │  │   SessionStore      │ │
│  │  (messages) │  │ (stateless) │  │ (background persist)│ │
│  └─────────────┘  └─────────────┘  └─────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 8.2 Reference Implementation: ChatViewModel

```swift
import SwiftUI

/// ViewModel for session-based chat with an AI agent.
///
/// Handles:
/// - Session state as single source of truth
/// - Agent execution with existing `streamExecute(messages:)` API
/// - Background persistence (non-blocking)
/// - Real-time SwiftUI updates
@Observable
final class ChatViewModel {
    // MARK: - State
    
    private(set) var session: Session
    private(set) var isStreaming = false
    private(set) var error: Error?
    
    // MARK: - Dependencies
    
    private let agent: AIAgentActor
    private let store: SessionStore
    private let titleGenerator: SessionTitleGenerator?
    private let persistenceBuffer: StreamingPersistenceBuffer
    
    // MARK: - Computed Properties
    
    var messages: [AIMessage] { session.messages }
    var title: String? { session.title }
    
    // MARK: - Initialization
    
    init(
        session: Session,
        agent: AIAgentActor,
        store: SessionStore,
        titleGenerator: SessionTitleGenerator? = nil
    ) {
        self.session = session
        self.agent = agent
        self.store = store
        self.titleGenerator = titleGenerator
        self.persistenceBuffer = StreamingPersistenceBuffer(
            store: store,
            sessionId: session.id
        )
    }
    
    // MARK: - Actions
    
    /// Send a message and stream the agent's response.
    @MainActor
    func send(_ content: [AIContentPart]) async {
        guard !isStreaming else { return }
        
        // 1. Add user message to session (UI updates immediately)
        let userMessage = AIMessage.user(content)
        session.messages.append(userMessage)
        session.lastActivityAt = Date()
        session.lastCheckpointIndex = session.messages.count - 1
        
        // 2. Persist user message (background, non-blocking)
        persistInBackground { store, session in
            try await store.appendMessage(userMessage, toSession: session.id)
        }
        
        // 3. Generate title if first user message
        if session.title == nil, let generator = titleGenerator {
            Task {
                if let title = try? await generator.generateTitle(for: session) {
                    await MainActor.run { session.title = title }
                    persistInBackground { store, session in
                        try await store.updateMetadata(
                            SessionMetadataUpdate(title: title),
                            forSession: session.id
                        )
                    }
                }
            }
        }
        
        // 4. Stream agent response
        isStreaming = true
        session.isLastMessageComplete = false
        error = nil
        
        do {
            // Agent API unchanged: just pass messages
            for try await event in agent.streamExecute(messages: session.messages) {
                await handleStreamEvent(event)
            }
            
            // Mark complete and final save
            session.isLastMessageComplete = true
            session.lastCheckpointIndex = session.messages.count - 1
            await persistenceBuffer.flush()
            try await store.save(session)
            
        } catch {
            self.error = error
            session.status = .error
            try? await store.save(session)
        }
        
        isStreaming = false
    }
    
    /// Resume an incomplete session.
    @MainActor
    func resume() async {
        guard !session.isLastMessageComplete else { return }
        
        // Remove incomplete message
        if let last = session.messages.last, last.role == .assistant {
            session.messages.removeLast()
        }
        
        // Re-run from last checkpoint
        if let lastUserMessage = session.messages.last(where: { $0.role == .user }) {
            // Agent will continue from current message state
            isStreaming = true
            do {
                for try await event in agent.streamExecute(messages: session.messages) {
                    await handleStreamEvent(event)
                }
                session.isLastMessageComplete = true
                try await store.save(session)
            } catch {
                self.error = error
            }
            isStreaming = false
        }
    }
    
    /// Rewind to a specific checkpoint.
    @MainActor
    func rewind(to checkpointIndex: Int) async throws {
        session.rewind(to: checkpointIndex)
        try await store.save(session)
    }
    
    // MARK: - Private
    
    @MainActor
    private func handleStreamEvent(_ event: AIStreamEvent) async {
        switch event {
        case .messageStart:
            // Add placeholder assistant message
            session.messages.append(.assistant(""))
            
        case .textDelta(let delta):
            // Update last message in place
            guard var last = session.messages.last, last.role == .assistant else { return }
            last.appendText(delta)
            session.messages[session.messages.count - 1] = last
            
            // Debounced background persist
            await persistenceBuffer.bufferDelta(last)
            
        case .toolCallStart(let toolCall):
            // Add tool call to assistant message
            guard var last = session.messages.last, last.role == .assistant else { return }
            var calls = last.toolCalls ?? []
            calls.append(toolCall)
            last.toolCalls = calls
            session.messages[session.messages.count - 1] = last
            
        case .toolCallDelta(let callId, let delta):
            // Update tool call arguments
            guard var last = session.messages.last,
                  var calls = last.toolCalls,
                  let index = calls.firstIndex(where: { $0.id == callId }) else { return }
            calls[index].arguments += delta
            last.toolCalls = calls
            session.messages[session.messages.count - 1] = last
            
        case .toolResult(let result):
            // Add tool result as separate message
            let toolMessage = AIMessage.tool(result.content, toolCallId: result.callId)
            session.messages.append(toolMessage)
            session.lastCheckpointIndex = session.messages.count - 1
            
            // Persist checkpoint
            persistInBackground { store, session in
                try await store.appendMessage(toolMessage, toSession: session.id)
            }
            
        case .stepComplete:
            // Checkpoint on step completion
            session.lastCheckpointIndex = session.messages.count - 1
            await persistenceBuffer.flush()
            
        case .finish:
            break
            
        default:
            break
        }
    }
    
    private func persistInBackground(_ operation: @escaping (SessionStore, Session) async throws -> Void) {
        let store = self.store
        let session = self.session
        Task.detached {
            try? await operation(store, session)
        }
    }
}
```

### 8.3 Streaming Persistence Buffer

Text deltas are debounced to reduce I/O overhead while still preserving progress:

```swift
/// Debounced persistence for streaming deltas
actor StreamingPersistenceBuffer {
    private let store: SessionStore
    private let sessionId: String
    private let debounceInterval: Duration = .milliseconds(500)
    
    private var pendingMessage: AIMessage?
    private var flushTask: Task<Void, Never>?
    
    init(store: SessionStore, sessionId: String) {
        self.store = store
        self.sessionId = sessionId
    }
    
    /// Buffer a streaming delta for persistence
    func bufferDelta(_ message: AIMessage) async {
        pendingMessage = message
        
        // Only create task if none pending
        if flushTask == nil {
            flushTask = Task {
                try? await Task.sleep(for: debounceInterval)
                await flush()
            }
        }
    }
    
    /// Immediately persist pending message
    func flush() async {
        flushTask?.cancel()
        flushTask = nil
        
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

### 8.4 Auto-Save Behavior

The ViewModel saves after each significant event:

| Event | Persistence Action |
|-------|-------------------|
| User message added | `appendMessage()` + create checkpoint |
| Tool call started | Updated in-memory (assistant message) |
| Tool result received | `appendMessage()` (tool result) + create checkpoint |
| Text delta (streaming) | `updateLastMessage()` (debounced, every 500ms) |
| Step complete | Flush buffer + checkpoint |
| Stream finish | `save()` full session + mark complete |
| Error occurred | `save()` with status = `.error` |

### 8.5 Resume from Checkpoint

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
        Session(
            id: UUID().uuidString,
            userId: userId,
            agentId: agentId,
            title: title.map { "\($0) (fork)" },
            messages: messages,
            metadata: metadata
        )
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
} catch SessionStoreError.unavailable(let reason) {
    // Handle network/database error
    logger.error("Storage unavailable: \(reason)")
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

### 11.4 ViewModels

| ViewModel | Description |
|-----------|-------------|
| `ChatViewModel` | SwiftUI-ready session management with streaming |
| `SessionListViewModel` | Session listing and management |

### 11.5 Services

| Service | Description |
|---------|-------------|
| `SessionCompactionService` | Context window management |
| `DefaultTitleGenerator` | LLM-based title generation |
| `StreamingPersistenceBuffer` | Debounced streaming persistence |

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

### Phase 3: ViewModel & Agent Integration (Week 3-4)

6. **ChatViewModel Reference Implementation**
   - [ ] Implement `ChatViewModel` with `@Observable`
   - [ ] Implement `send(_:)` with streaming
   - [ ] Implement `StreamingPersistenceBuffer` for debounced saves
   - [ ] Implement event handling (`handleStreamEvent`)
   - [ ] Add checkpointing on user message, tool result, step complete

7. **Resume/Rewind**
   - [ ] Implement `Session.rewind(to:)`
   - [ ] Implement `Session.messagesAtCheckpoint(_:)`
   - [ ] Implement `ChatViewModel.resume()` for incomplete sessions
   - [ ] Implement `ChatViewModel.retryLastTurn()`

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
let session = Session(userId: userId)
_ = try await store.create(session)

let agent = AIAgentActor(model: model, tools: tools)
let viewModel = ChatViewModel(
    session: session,
    agent: agent,
    store: store,
    titleGenerator: DefaultTitleGenerator(model: model)
)

// Send message (handles streaming, persistence, title generation)
await viewModel.send([.text("Hello")])
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
            let text = message.textContent ?? ""
            switch message.role {
            case .user:
                md += "## User\n\n\(text)\n\n"
            case .assistant:
                let agent = message.agentName ?? "Assistant"
                md += "## \(agent)\n\n\(text)\n\n"
            case .tool:
                md += "> **Tool Result** (\(message.toolCallId ?? "unknown"))\n>\n"
                md += "> \(text)\n\n"
            case .system:
                md += "*System: \(text.prefix(100))...*\n\n"
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
    
    /// Set a session directly (for test setup)
    public func setSession(_ session: Session) {
        sessions[session.id] = session
    }
    
    /// Set the next error to throw
    public func setNextError(_ error: Error) {
        nextError = error
    }
    
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
   
2. **Offline-first for Firebase**: Should we add local caching layer? -ANSWER: YES!!!
   - Firebase has built-in offline support
   - May need custom handling for long offline periods

3. **Encryption at rest**: Should we provide `EncryptedSessionStore` wrapper? NO
   - OpenAI SDK has this
   - Could be a separate package

### Decisions Made

- **Session lifecycle**: Developer manages (no auto-archive)
- **Session/message limits**: None enforced by SDK (app-level policy)
- **Streaming persistence**: Debounced at 500ms intervals

---

## 18. Appendix: Usage Examples

### A. Basic SwiftUI Chat App

```swift
import SwiftUI

// MARK: - App Setup

@main
struct ChatApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var viewModel: ChatViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                ChatView(viewModel: viewModel)
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            await setupChat()
        }
    }
    
    private func setupChat() async {
        let store = SQLiteSessionStore(path: "conversations.db")
        let agent = AIAgentActor(
            model: OpenRouterClient(modelId: "anthropic/claude-3.5-sonnet"),
            tools: [SearchTool.self]
        )
        
        // Create or load session
        let session = try? await store.load(id: "current") 
            ?? Session(id: "current", userId: "user_123")
        
        viewModel = ChatViewModel(
            session: session,
            agent: agent,
            store: store,
            titleGenerator: DefaultTitleGenerator(model: agent.model)
        )
    }
}

// MARK: - Chat View

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var inputText = ""
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages, id: \.id) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    withAnimation {
                        proxy.scrollTo(viewModel.messages.last?.id)
                    }
                }
            }
            .navigationTitle(viewModel.title ?? "New Chat")
            .safeAreaInset(edge: .bottom) {
                InputBar(
                    text: $inputText,
                    isLoading: viewModel.isStreaming
                ) {
                    Task {
                        await viewModel.send([.text(inputText)])
                    }
                    inputText = ""
                }
            }
        }
    }
}
```

### B. Session List & Management

```swift
@Observable
final class SessionListViewModel {
    private(set) var sessions: [SessionSummary] = []
    private let store: SessionStore
    private let userId: String
    
    init(store: SessionStore, userId: String) {
        self.store = store
        self.userId = userId
    }
    
    func load() async {
        let result = try? await store.list(
            userId: userId,
            status: nil,
            limit: 50,
            cursor: nil,
            orderBy: .lastActivityAtDesc
        )
        sessions = result?.sessions ?? []
    }
    
    func createNew() async -> Session {
        let session = Session(userId: userId)
        _ = try? await store.create(session)
        await load()
        return session
    }
    
    func delete(_ sessionId: String) async {
        try? await store.delete(id: sessionId)
        await load()
    }
}

struct SessionListView: View {
    @Bindable var viewModel: SessionListViewModel
    var onSelect: (String) -> Void
    
    var body: some View {
        List {
            ForEach(viewModel.sessions, id: \.id) { session in
                Button {
                    onSelect(session.id)
                } label: {
                    VStack(alignment: .leading) {
                        Text(session.title ?? "Untitled")
                            .font(.headline)
                        Text(session.lastActivityAt.formatted())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let id = viewModel.sessions[index].id
                    Task { await viewModel.delete(id) }
                }
            }
        }
        .task { await viewModel.load() }
    }
}
```

### C. Resume Incomplete Session

```swift
extension ChatViewModel {
    /// Check and handle incomplete session on load
    @MainActor
    func handleIncompleteSessionOnLoad() async {
        guard !session.isLastMessageComplete else { return }
        
        // Show user options
        // Option 1: Resume (continue from where it stopped)
        // Option 2: Retry (remove incomplete message, re-run)
        // Option 3: Discard (remove incomplete message, wait for user)
    }
    
    /// Retry the last incomplete turn
    @MainActor
    func retryLastTurn() async {
        guard !session.isLastMessageComplete,
              let lastAssistant = session.messages.lastIndex(where: { $0.role == .assistant }) else {
            return
        }
        
        // Remove incomplete assistant message
        session.messages.remove(at: lastAssistant)
        session.isLastMessageComplete = true
        
        // Find the last user message
        guard let lastUser = session.messages.last(where: { $0.role == .user }) else { return }
        
        // Re-run from that point
        isStreaming = true
        do {
            for try await event in agent.streamExecute(messages: session.messages) {
                await handleStreamEvent(event)
            }
            session.isLastMessageComplete = true
            try await store.save(session)
        } catch {
            self.error = error
        }
        isStreaming = false
    }
}
```

### D. Multi-Agent Chat (Handoffs)

```swift
@Observable
final class MultiAgentChatViewModel {
    private(set) var session: Session
    private(set) var activeAgent: AIAgentActor
    private(set) var isStreaming = false
    
    private let agents: [String: AIAgentActor]
    private let store: SessionStore
    
    init(session: Session, agents: [String: AIAgentActor], store: SessionStore) {
        self.session = session
        self.agents = agents
        self.activeAgent = agents["triage"]!
        self.store = store
    }
    
    @MainActor
    func send(_ content: [AIContentPart]) async {
        session.messages.append(.user(content))
        isStreaming = true
        
        do {
            for try await event in activeAgent.streamExecute(messages: session.messages) {
                switch event {
                case .handoff(let handoff):
                    // Switch to new agent
                    if let newAgent = agents[handoff.targetAgentId] {
                        activeAgent = newAgent
                        // Add handoff message for context
                        if let summary = handoff.summary {
                            session.messages.append(.system("Handoff: \(summary)"))
                        }
                    }
                default:
                    await handleStreamEvent(event)
                }
            }
            try await store.save(session)
        } catch {
            // Handle error
        }
        
        isStreaming = false
    }
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
// MARK: - ViewModel Tests

func testViewModelSavesMessagesOnSend() async throws {
    // Arrange
    let mockStore = MockSessionStore()
    let mockAgent = MockAIAgentActor(responses: [.text("Hello back!")])
    let session = Session(userId: "test_user")
    await mockStore.setSession(session)
    
    let viewModel = ChatViewModel(
        session: session,
        agent: mockAgent,
        store: mockStore
    )
    
    // Act
    await viewModel.send([.text("Hello")])
    
    // Assert
    let saveCount = await mockStore.saveCount
    let appendCount = await mockStore.appendMessageCalls.count
    XCTAssertEqual(saveCount, 1)  // Final save
    XCTAssertGreaterThanOrEqual(appendCount, 1)  // At least user message
    XCTAssertEqual(viewModel.messages.count, 2)  // user + assistant
}

func testViewModelHandlesStorageError() async throws {
    // Arrange
    let mockStore = MockSessionStore()
    let mockAgent = MockAIAgentActor(responses: [.text("Response")])
    let session = Session(userId: "test_user")
    
    // Set error on save (not append, so we can add user message)
    await mockStore.setNextError(SessionStoreError.unavailable(reason: "Network timeout"))
    
    let viewModel = ChatViewModel(
        session: session,
        agent: mockAgent,
        store: mockStore
    )
    
    // Act
    await viewModel.send([.text("Hello")])
    
    // Assert - ViewModel captures error, session marked as error
    XCTAssertNotNil(viewModel.error)
    XCTAssertEqual(viewModel.session.status, .error)
}

// MARK: - Session Store Tests

func testSessionStoreRoundTrip() async throws {
    let store = InMemorySessionStore()
    var session = Session(userId: "user_123")
    session.title = "Test Chat"
    session.messages = [
        .user("Hello"),
        .assistant("Hi there!")
    ]
    
    // Create
    let created = try await store.create(session)
    XCTAssertEqual(created.id, session.id)
    
    // Load
    let loaded = try await store.load(id: session.id)
    XCTAssertNotNil(loaded)
    XCTAssertEqual(loaded?.messages.count, 2)
    XCTAssertEqual(loaded?.title, "Test Chat")
    
    // Update
    var updated = loaded!
    updated.messages.append(.user("Another message"))
    try await store.save(updated)
    
    // Verify update
    let reloaded = try await store.load(id: session.id)
    XCTAssertEqual(reloaded?.messages.count, 3)
}
```

---

## 19. Appendix: Design Interview

The following interview captured requirements and design decisions for this specification.

### Session Content & Scope (Q11-Q13)

**Q11: What should be stored in a session?**
> All of it—messages, metadata, tools, thinking, stop message, resume, thread creation. Think of modern AI agentic systems like Claude Code, ChatGPT. When you start a session with an agent, you want to see everything.

**Q12: How should we approach session design?**
> Study how modern agentic systems handle sessions (Claude Agents SDK, Codex, Google ADK, Agno) and extract first principles and best practices.

**Q13: Session relationship to memory?**
> Session is equivalent to short-term memory.

### Persistence Strategy (Q21-Q23)

**Q21: When should we persist?**
> Follow best practices—save every step. Even if the assistant is streaming, save partial responses. Same with tools, reasoning, or errors.

**Q22: Streaming persistence approach?**
> Incremental saves (Option A).

**Q23: Checkpoint granularity?**
> Depends—need to resume incomplete assistant messages, and also checkpoint when a step completes.

### Metadata & Storage (Q31-Q33)

**Q31: Session metadata fields?**
> All fields are important except versioning.

**Q32: Storage architecture?**
> Sessions can be local or via provider (Firebase, Supabase). Build foundations and then create adapters.

**Q33: Existing storage solutions to leverage?**
> No, but account for fundamentals. Build initial adapters for local and Firebase. Protocol-first is the right approach.

### Context Management (Q41-Q43)

**Q41-Q42: Context management approach?**
> Follow best practices.

**Q43: Model context window changes?**
> If the next model has a bigger context window, keep it. If smaller, summarize/compress like Claude Code.

### Multi-Step & Error Handling (Q51-Q53)

**Q51: Multi-step agent patterns?**
> Search for best practices on how Claude Agents SDK works.

**Q52: Error recovery?**
> Make checkpoints.

**Q53: Branching/threading?**
> No, keep it simple for now.

### Lifecycle & Multi-User (Q61-Q62)

**Q61: Session lifecycle/cleanup?**
> Developer responsibility. Forget about auto-cleanup.

**Q62: Multi-user support?**
> Yes. A user can have multiple sessions.

### API Design (Q71)

**Q71: Naming conventions?**
> `Session`, `SessionStore`.

**Q71b: Error handling approach?**
> Fully transparent (Option B). Errors propagate to caller.

**Additional:** When a user sends their first message, there's a separate LLM call that generates a title for the conversation.

### Data Model Details (Q81-Q83)

**Q81: Session data model structure?**
> a) Steps should be part of messages. Think about how an AI agent works: user sends → agent thinks → tools, results → response. All composed, can be parallel tool calls, multiple steps. Do it like Claude Code.
> b) Include agent configuration.
> c) `userId` is required because a user can have multiple sessions. Also think about testing.
> d) Don't store tokens in session—that's an agent concern, not session.

**Q82: Retry/resume scope?**
> Only the final response. Tool calls get checkpoints. User can retry or resume if it's the final agent response message.

**Q83: Storage vs memory tradeoff?**
> Like Claude Code—favor more storage.

### API Ergonomics (Q91-Q93)

**Q91: API ergonomics preference?**
> Whatever is best for clean code that works.

**Q92: Session creation pattern?**
> Option A.

**Q93: Message append pattern?**
> Option A.

### Agent-Session Relationship (Q101-Q102)

**Q101: Agent-session coupling?**
> Option B (loosely coupled).

**Q102: Observable state approach?**
> Cleanest/easiest option.

### Context Compaction (Q111-Q112)

**Q111: When to compact?**
> Compaction at ~90% of the agent's token limit. Session should have a method for this. Claude Code does compaction/summarization. Important for longer sessions.

**Q112: Compaction implementation?**
> Cleanest approach, follow best practices.

### Cloud Integration (Q121-Q122)

**Q121: Firebase integration?**
> Best practices, clean and robust implementation.

**Q122: Real-time updates?**
> Option A, follow best practices.

### Multi-Agent Support (Q131-Q132)

**Q131: Multi-agent patterns?**
> Claude Code has subagents, also Codex SDK. They're the best at that—emulate what they do.

**Q132: Parallel subagents?**
> Subagents work in parallel, account for that. Storing agent ID and name is nice for future use cases. Imagine multiple agents in the same conversation, or some working in parallel.

### Built-in Adapters (Q141-Q142)

**Q141: Which adapters to build?**
> Like those 4 (InMemory, FileSystem, SQLite, Firebase). Default should be InMemory.

**Q142: Adapter selection criteria?**
> Best UX, considering that an AI agent will appear in a UI streaming conversation.

### Testing (Q151-Q152)

**Q151-Q152: Testing strategy?**
> Follow best practices.

### Export & Features (Q161-Q192)

**Q161: Export format?** Option A.

**Q171: Search capability?** Option A.

**Q172: Session limits?** No limit.

**Q181: Migration path?** Ok.

**Q191: Streaming persistence buffer?** Yes.

**Q192: Export/import features?** Yes.

**Q20: Search and testing support?** Ok.

### Architecture Decision (Post-Interview)

**Q: Agent API for session-aware execution?**

After analysis for SwiftUI + background persistence, the decision was made:

> **Option C: ViewModel-managed sessions.** The agent API stays unchanged (`streamExecute(messages:)`). The ViewModel owns the session, feeds messages to the agent, handles events, updates session state, and persists in background. This keeps the agent pure/stateless regarding sessions, gives the ViewModel full control over persistence timing, and provides a single source of truth for SwiftUI observation.

---

*This specification is a living document and will be updated as implementation progresses.*
