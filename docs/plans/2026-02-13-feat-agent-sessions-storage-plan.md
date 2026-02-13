---
title: "Agent Sessions & Storage"
type: feat
date: 2026-02-13
issue: "#20"
spec: "docs/planning/sessions/2026-02-01-agent-sessions-storage-spec.md"
branch: aisdk-2.0-modernization
---

# Agent Sessions & Storage Implementation Plan

## Overview

Implement session management and storage for AISDK agents per [the spec](../planning/sessions/2026-02-01-agent-sessions-storage-spec.md) and [Issue #20](https://github.com/DanielhCarranza/AISDK/issues/20). This enables conversation persistence, resume/rewind, context compaction, multi-agent attribution, and export/search -- aligning with Phase 5 (Memory + Context Management) of the [Agentic Roadmap](../AISDK-AGENTIC-ROADMAP.md).

## Critical: Spec-to-Codebase Type Mapping

The spec was written before the current codebase was finalized. The following mappings resolve all type mismatches discovered during analysis:

| Spec Type | Actual Codebase Type | Location |
|-----------|---------------------|----------|
| `AIAgentActor` | `Agent` (actor) | `Sources/AISDK/Agents/Agent.swift` |
| `AILanguageModel` | `LLM` (protocol) | `Sources/AISDK/Core/Protocols/LLM.swift` |
| `AIContentPart` | `AIMessage.ContentPart` | `Sources/AISDK/Core/Protocols/LLM.swift:78` |
| `AIStreamEvent.messageStart` | `AIStreamEvent.start(metadata:)` | `Sources/AISDK/Core/Models/AIStreamEvent.swift:74` |
| `.toolCallDelta(callId, delta)` | `.toolCallDelta(id:, argumentsDelta:)` | `AIStreamEvent.swift:40` |
| `.toolResult(result)` | `.toolResult(id:, result:, metadata:)` | `AIStreamEvent.swift:49` |
| `.stepComplete` | `.stepFinish(stepIndex:, result:)` | `AIStreamEvent.swift:80` |
| `result.text` | `result.text` (confirmed) | `AITextResult.swift` |

### AIMessage Immutability Issue

**Problem:** All `AIMessage` properties are `let` constants. The spec requires mutable messages for streaming (appending text deltas, adding tool calls, setting agentId).

**Solution:** Change `AIMessage` properties to `var` where session functionality requires mutation. Specifically: `role` stays `let`, but `content`, `name`, `toolCalls`, `toolCallId` become `var`. Additionally, add new session properties (`id`, `agentId`, `agentName`, `isCheckpoint`, `checkpointIndex`) as `var` with defaults. This is safe because `AIMessage` is a value type (`struct`) -- mutation creates a copy, so `Sendable` is preserved.

### AIMessage Missing `id` Property

**Problem:** `AIMessage` has no `id` property. SwiftUI `ForEach` requires `Identifiable` or an explicit `id` keypath.

**Solution:** Add `public var id: String = UUID().uuidString` to `AIMessage` with a `CodingKeys` update to make it optional on decode (backward compat).

---

## File Structure

All new files go under `Sources/AISDK/Sessions/`:

```
Sources/AISDK/Sessions/
  Models/
    Session.swift                    # Session struct, SessionStatus, SessionCheckpoint
    SessionSummary.swift             # SessionSummary, SessionListResult, SessionOrderBy
    SessionMetadataUpdate.swift      # Partial update type
    SessionStoreError.swift          # Error types
    ContextPolicy.swift              # ContextPolicy, CompactionStrategy
    AgentHandoff.swift               # AgentHandoff, SubagentOptions
    SearchResult.swift               # SearchResult type
  Protocols/
    SessionStore.swift               # SessionStore protocol + default extensions
    SearchableSessionStore.swift     # SearchableSessionStore protocol
    SessionTitleGenerator.swift      # Title generation protocol
  Stores/
    InMemorySessionStore.swift       # Actor-based in-memory store
    FileSystemSessionStore.swift     # JSON file-based store
    SQLiteSessionStore.swift         # SQLite store (import SQLite3)
  Services/
    SessionCompactionService.swift   # Context compaction logic
    DefaultTitleGenerator.swift      # LLM-based title generation
    StreamingPersistenceBuffer.swift # Debounced streaming persistence
  ViewModels/
    ChatViewModel.swift              # @Observable SwiftUI ViewModel
    SessionListViewModel.swift       # Session list management
  Export/
    SessionExport.swift              # JSON/Markdown export + import

Tests/AISDKTests/Sessions/
  Models/
    SessionTests.swift               # Session struct tests
    SessionStatusTests.swift         # Status enum tests
  Stores/
    InMemorySessionStoreTests.swift  # InMemory CRUD + query tests
    FileSystemSessionStoreTests.swift # FileSystem persistence tests
    SQLiteSessionStoreTests.swift    # SQLite CRUD + query tests
    SessionStoreConformanceTests.swift # Shared protocol conformance suite
  Services/
    SessionCompactionServiceTests.swift
    StreamingPersistenceBufferTests.swift
    DefaultTitleGeneratorTests.swift
  ViewModels/
    ChatViewModelTests.swift         # ViewModel + mock store tests
  Export/
    SessionExportTests.swift         # Export/import round-trip tests
  Mocks/
    MockSessionStore.swift           # Test double with operation recording
    MockLLM.swift                    # LLM mock for compaction/title tests
```

---

## Implementation Phases

### Phase 1: Core Data Model + AIMessage Changes

**Goal:** Define all data model types and make the minimal `AIMessage` changes needed for sessions.

#### 1a. Modify `AIMessage` (`Sources/AISDK/Core/Protocols/LLM.swift`)

```swift
public struct AIMessage: Sendable, Codable, Identifiable {
    // New: unique identifier for SwiftUI and session tracking
    public var id: String

    public let role: Role
    public var content: Content       // Changed: let -> var (for streaming text accumulation)
    public let name: String?
    public var toolCalls: [ToolCall]? // Changed: let -> var (for streaming tool call accumulation)
    public let toolCallId: String?

    // Session properties (new)
    public var agentId: String?
    public var agentName: String?
    public var isCheckpoint: Bool
    public var checkpointIndex: Int?

    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: Content,
        name: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        agentId: String? = nil,
        agentName: String? = nil,
        isCheckpoint: Bool = false,
        checkpointIndex: Int? = nil
    ) { /* ... */ }
}
```

Also make `ToolCall.arguments` a `var`:
```swift
public struct ToolCall: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public var arguments: String  // Changed: let -> var
}
```

Add helper methods:
```swift
extension AIMessage {
    /// Append text to a text-content message (for streaming accumulation)
    public mutating func appendText(_ delta: String) {
        switch content {
        case .text(let existing):
            content = .text(existing + delta)
        case .parts(let parts):
            // Append to last text part or add new text part
            var mutableParts = parts
            if case .text(let existing) = mutableParts.last {
                mutableParts[mutableParts.count - 1] = .text(existing + delta)
            } else {
                mutableParts.append(.text(delta))
            }
            content = .parts(mutableParts)
        }
    }

    /// Get text content as string
    public var textContent: String? {
        content.textValue.isEmpty ? nil : content.textValue
    }
}
```

**CodingKeys update:** Make `id` and session properties decode with defaults for backward compat:
```swift
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
    self.role = try container.decode(Role.self, forKey: .role)
    self.content = try container.decode(Content.self, forKey: .content)
    self.name = try container.decodeIfPresent(String.self, forKey: .name)
    self.toolCalls = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
    self.toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
    self.agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
    self.agentName = try container.decodeIfPresent(String.self, forKey: .agentName)
    self.isCheckpoint = try container.decodeIfPresent(Bool.self, forKey: .isCheckpoint) ?? false
    self.checkpointIndex = try container.decodeIfPresent(Int.self, forKey: .checkpointIndex)
}
```

#### 1b. Session Model (`Sources/AISDK/Sessions/Models/Session.swift`)

Implement exactly as spec Section 3.1, with these additions:
- Add `schemaVersion: Int = 1` for future migration support
- Add `checkpoints: [SessionCheckpoint] = []` array (resolves Gap 3.22 from analysis)
- Factory methods `Session.create(userId:store:)` and `Session.load(id:store:)`
- `rewind(to:)` validates checkpoint index against stored checkpoints
- `fork()` for multi-agent handoffs
- `messagesAtCheckpoint(_:)` accessor

#### 1c. Supporting Types

- `SessionStatus` enum (spec Section 3.2) -> `Session.swift`
- `SessionCheckpoint` struct (spec Section 3.4) -> `Session.swift`
- `SessionSummary`, `SessionListResult`, `SessionOrderBy` -> `SessionSummary.swift`
- `SessionMetadataUpdate` -> `SessionMetadataUpdate.swift`
- `SessionStoreError` enum (spec Section 4.3) -> `SessionStoreError.swift`

#### 1d. Tests

- `SessionTests.swift`: Init, factory methods, rewind, fork, checkpoint creation, Codable round-trip, Hashable/Equatable behavior
- `SessionStatusTests.swift`: Raw values, Codable

**Acceptance Criteria:**
- [ ] `AIMessage` has `id`, `agentId`, `agentName`, `isCheckpoint`, `checkpointIndex` properties
- [ ] `AIMessage.content` and `AIMessage.toolCalls` are `var`
- [ ] `AIMessage.ToolCall.arguments` is `var`
- [ ] `AIMessage.appendText(_:)` works for text accumulation
- [ ] `Session` struct is `Codable`, `Sendable`, `Identifiable`, `Hashable`
- [ ] Backward-compatible `AIMessage` decoding (old JSON without `id` still decodes)
- [ ] All existing tests pass after AIMessage changes
- [ ] `swift build` succeeds

---

### Phase 2: SessionStore Protocol + InMemorySessionStore

**Goal:** Define the storage protocol and build the default in-memory implementation with full tests.

#### 2a. SessionStore Protocol (`Sources/AISDK/Sessions/Protocols/SessionStore.swift`)

Implement per spec Section 4.1 with these pragmatic adjustments:

```swift
public protocol SessionStore: Sendable {
    // CRUD
    func create(_ session: Session) async throws -> Session
    func load(id: String) async throws -> Session?
    func save(_ session: Session) async throws
    func delete(id: String) async throws

    // Query
    func list(
        userId: String,
        status: SessionStatus?,
        limit: Int,
        cursor: String?,
        orderBy: SessionOrderBy
    ) async throws -> SessionListResult

    // Incremental Updates
    func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws
    func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws
    func updateStatus(_ status: SessionStatus, forSession sessionId: String) async throws
    func updateMetadata(_ updates: SessionMetadataUpdate, forSession sessionId: String) async throws

    // Real-time (optional)
    func observe(sessionId: String) -> AsyncThrowingStream<Session, Error>?
}
```

**Default protocol extensions** (resolves Gap 3.32):
- `observe` returns `nil` by default
- `appendMessage` defaults to load + append + save
- `updateLastMessage` defaults to load + replace last + save
- `updateStatus` defaults to load + update + save
- `updateMetadata` defaults to load + update + save

These defaults let simple stores implement only CRUD + list while optimized stores override incrementals.

#### 2b. InMemorySessionStore (`Sources/AISDK/Sessions/Stores/InMemorySessionStore.swift`)

Actor-based implementation per spec Section 5.1. Override all methods for optimal performance (no load+save round-trips).

#### 2c. MockSessionStore (`Tests/AISDKTests/Sessions/Mocks/MockSessionStore.swift`)

Per spec Section 16.1 with operation recording, configurable errors, and delay simulation.

#### 2d. SessionStoreConformanceTests

Reusable test suite that verifies any `SessionStore` implementation:
- CRUD round-trip
- Create conflict (duplicate ID)
- Load nonexistent returns nil
- Delete nonexistent throws `.notFound`
- List with userId filter, status filter, pagination, ordering
- Incremental: appendMessage, updateLastMessage, updateStatus, updateMetadata
- Concurrent access safety (100 parallel writes)

Run against `InMemorySessionStore`.

**Acceptance Criteria:**
- [ ] `SessionStore` protocol compiles with all methods
- [ ] Default extensions work for simple implementations
- [ ] `InMemorySessionStore` passes full conformance suite
- [ ] `MockSessionStore` records all operations correctly
- [ ] Concurrent access test passes without data races

---

### Phase 3: FileSystem + SQLite Stores

**Goal:** Add persistent storage backends.

#### 3a. FileSystemSessionStore (`Sources/AISDK/Sessions/Stores/FileSystemSessionStore.swift`)

Per spec Section 5.2:
- Actor isolation for thread safety
- One JSON file per session (`{sessionId}.json`)
- Atomic writes via `Data.write(to:options:[.atomic])`
- ISO 8601 date encoding
- Directory auto-creation on init
- List implementation: scan directory, decode each file
- Cursor-based pagination via sorted filenames

#### 3b. SQLiteSessionStore (`Sources/AISDK/Sessions/Stores/SQLiteSessionStore.swift`)

Per spec Section 5.3 using `import SQLite3` (system library, no external dependency):

**Schema:**
```sql
CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    agent_id TEXT,
    title TEXT,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TEXT NOT NULL,
    last_activity_at TEXT NOT NULL,
    messages_json BLOB NOT NULL,
    checkpoints_json BLOB,
    metadata_json TEXT,
    tags_json TEXT,
    schema_version INTEGER NOT NULL DEFAULT 1,
    is_last_message_complete INTEGER NOT NULL DEFAULT 1,
    last_checkpoint_index INTEGER
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_sessions_last_activity ON sessions(user_id, last_activity_at DESC);
```

Key implementation details:
- Actor wrapping a lightweight `SQLiteConnection` helper class
- WAL mode (`PRAGMA journal_mode=WAL`) for concurrent reads
- Prepared statement caching for hot-path queries
- Messages stored as JSON blob (full `[AIMessage]` array)
- Incremental methods (`appendMessage`, `updateLastMessage`) read only messages blob, modify, write back -- not full session decode
- Transaction support for batch operations

#### 3c. Tests

- `FileSystemSessionStoreTests.swift`: Run conformance suite + file-specific tests (atomic write verification, directory creation, corrupted file handling)
- `SQLiteSessionStoreTests.swift`: Run conformance suite + SQLite-specific tests (index usage, WAL mode, in-memory mode with `:memory:`)

**Acceptance Criteria:**
- [ ] `FileSystemSessionStore` passes full conformance suite
- [ ] `SQLiteSessionStore` passes full conformance suite
- [ ] SQLite uses `import SQLite3` (no external dependency)
- [ ] Corrupted file/row returns nil (not crash)
- [ ] `swift build` succeeds with no new dependencies in Package.swift

---

### Phase 4: Streaming Persistence + ChatViewModel

**Goal:** Build the ViewModel layer that integrates sessions with the existing `Agent` actor.

#### 4a. StreamingPersistenceBuffer (`Sources/AISDK/Sessions/Services/StreamingPersistenceBuffer.swift`)

Per spec Section 8.3:
- Actor with 500ms debounce interval
- `bufferDelta(_:)` schedules debounced persist
- `flush()` immediately persists pending message
- Uses `Task.sleep(for:)` with cancellation handling

#### 4b. ChatViewModel (`Sources/AISDK/Sessions/ViewModels/ChatViewModel.swift`)

Per spec Section 8.2 with these corrections from the gap analysis:

**Key differences from spec:**

1. **`@Observable @MainActor final class`** -- full `@MainActor` isolation (not per-method)

2. **Event handling rewritten for actual `AIStreamEvent`:**
```swift
@MainActor
private func handleStreamEvent(_ event: AIStreamEvent) async {
    switch event {
    case .start:
        // Stream started -- create placeholder assistant message
        let assistantMessage = AIMessage(role: .assistant, content: .text(""))
        session.messages.append(assistantMessage)

    case .textDelta(let delta):
        guard session.messages.last?.role == .assistant else { return }
        session.messages[session.messages.count - 1].appendText(delta)
        await persistenceBuffer.bufferDelta(session.messages[session.messages.count - 1])

    case .toolCallStart(let id, let name):
        guard session.messages.last?.role == .assistant else { return }
        var calls = session.messages[session.messages.count - 1].toolCalls ?? []
        calls.append(AIMessage.ToolCall(id: id, name: name, arguments: ""))
        session.messages[session.messages.count - 1].toolCalls = calls

    case .toolCallDelta(let id, let argumentsDelta):
        guard var last = session.messages.last, last.role == .assistant,
              var calls = last.toolCalls,
              let idx = calls.firstIndex(where: { $0.id == id }) else { return }
        calls[idx].arguments += argumentsDelta
        session.messages[session.messages.count - 1].toolCalls = calls

    case .toolResult(let id, let result, _):
        let toolMessage = AIMessage.tool(result, toolCallId: id)
        session.messages.append(toolMessage)
        session.lastCheckpointIndex = session.messages.count - 1
        persistInBackground { store, sessionId in
            try await store.appendMessage(toolMessage, toSession: sessionId)
        }

    case .stepFinish(_, _):
        session.lastCheckpointIndex = session.messages.count - 1
        await persistenceBuffer.flush()

    case .stepStart(let stepIndex) where stepIndex > 0:
        // New step after tool results -- create new assistant message
        let assistantMessage = AIMessage(role: .assistant, content: .text(""))
        session.messages.append(assistantMessage)

    case .finish(_, _):
        break // Handled in send() after loop

    case .error(let error):
        self.error = error

    default:
        break
    }
}
```

3. **Cancellation support** (resolves Gap 3.39):
```swift
private var streamingTask: Task<Void, Never>?

func cancel() {
    streamingTask?.cancel()
    streamingTask = nil
    isStreaming = false
    session.isLastMessageComplete = false
}
```

4. **Background persistence with error visibility** (resolves Gap 3.27):
```swift
private(set) var persistenceWarning: String?

private func persistInBackground(_ operation: @escaping (SessionStore, String) async throws -> Void) {
    let store = self.store
    let sessionId = self.session.id
    Task.detached { [weak self] in
        do {
            try await operation(store, sessionId)
        } catch {
            await MainActor.run {
                self?.persistenceWarning = "Failed to save: \(error.localizedDescription)"
            }
        }
    }
}
```

5. **`retryLastTurn()` removes all messages after last user message** (resolves Gap 3.40):
```swift
@MainActor
func retryLastTurn() async {
    guard let lastUserIndex = session.messages.lastIndex(where: { $0.role == .user }) else { return }
    session.messages = Array(session.messages.prefix(lastUserIndex + 1))
    session.isLastMessageComplete = true
    // Re-run agent from current messages
    await sendFromCurrentState()
}
```

#### 4c. SessionListViewModel (`Sources/AISDK/Sessions/ViewModels/SessionListViewModel.swift`)

Per spec Appendix B: list, create, delete sessions.

#### 4d. Tests

- `ChatViewModelTests.swift`: Send message flow, streaming event handling, resume, rewind, retry, cancellation, background persistence errors
- Uses `MockSessionStore` + `MockLLM` (existing `MockLanguageModel` from test suite)

**Acceptance Criteria:**
- [ ] `ChatViewModel.send` persists user message, streams response, saves final state
- [ ] Streaming text deltas accumulate correctly via `appendText`
- [ ] Tool calls and results create proper message sequence
- [ ] `cancel()` stops streaming and marks session incomplete
- [ ] `retryLastTurn()` removes all messages after last user message
- [ ] `resume()` handles incomplete sessions
- [ ] `rewind(to:)` truncates to valid checkpoint
- [ ] Background persistence errors surface via `persistenceWarning`
- [ ] `SessionListViewModel` CRUD operations work

---

### Phase 5: Context Management + Title Generation

**Goal:** Add context compaction and automatic title generation.

#### 5a. ContextPolicy (`Sources/AISDK/Sessions/Models/ContextPolicy.swift`)

Per spec Section 6.1. Struct with `maxTokens`, `compactionThreshold`, `compactionStrategy`, `preserveSystemPrompt`, `minMessagesToKeep`.

#### 5b. SessionCompactionService (`Sources/AISDK/Sessions/Services/SessionCompactionService.swift`)

Per spec Section 6.2 with these corrections:
- Takes `any LLM` (not `AILanguageModel`)
- `needsCompaction` uses heuristic token estimation (4 chars/token + 15% safety margin) since no tokenizer dependency exists
- `compact` implements all three strategies: truncate, summarize, slidingWindow
- Summarization uses `LLM.generateText(request:)` with a compaction prompt
- Existing `OpenAIProvider+Compaction.swift` token estimation logic is referenced as a pattern

Token estimation approach:
```swift
func estimateTokens(_ messages: [AIMessage]) -> Int {
    var total = 0
    for message in messages {
        total += 4 // per-message overhead
        let text = message.content.textValue
        let charCount = text.utf8.count
        total += Int(Double((charCount + 3) / 4) * 1.15) // 4 chars/token + 15% margin
        if let toolCalls = message.toolCalls {
            for call in toolCalls {
                total += 4
                total += Int(Double((call.name.utf8.count + call.arguments.utf8.count + 3) / 4) * 1.15)
            }
        }
    }
    total += 3 // assistant priming
    return total
}
```

#### 5c. SessionTitleGenerator Protocol + DefaultTitleGenerator

Per spec Sections 7.1-7.3:
- `SessionTitleGenerator` protocol
- `DefaultTitleGenerator` actor using `any LLM`
- Uses first 6 messages for context
- Fallback to "New Conversation" on error

#### 5d. Tests

- `SessionCompactionServiceTests.swift`: Token estimation accuracy, truncation strategy, summarization strategy, sliding window strategy, threshold detection
- `DefaultTitleGeneratorTests.swift`: Title generation with mock LLM, error fallback

**Acceptance Criteria:**
- [ ] Token estimation within 20% of actual for English text
- [ ] Truncation preserves system prompt and keeps `minMessagesToKeep` recent messages
- [ ] Summarization calls LLM and produces valid compacted session
- [ ] Sliding window keeps first N + last M messages
- [ ] `needsCompaction` triggers at correct threshold
- [ ] Title generation produces short titles from conversation context

---

### Phase 6: Multi-Agent Support + Export/Search

**Goal:** Add agent attribution, handoffs, export, and search.

#### 6a. Agent Attribution

Messages get `agentId`/`agentName` set when produced. Add convenience factory:
```swift
extension AIMessage {
    static func assistant(
        _ text: String,
        agentId: String? = nil,
        agentName: String? = nil,
        toolCalls: [ToolCall]? = nil
    ) -> AIMessage {
        var msg = AIMessage(role: .assistant, content: .text(text), toolCalls: toolCalls)
        msg.agentId = agentId
        msg.agentName = agentName
        return msg
    }
}
```

#### 6b. AgentHandoff + SubagentOptions

Per spec Sections 9.2-9.3: `AgentHandoff` struct, `SubagentOptions` with session modes (shared/forked/independent).

#### 6c. Session Export/Import

Per spec Section 14:
- `Session.exportJSON()` -> `Data`
- `Session.exportMarkdown()` -> `String` (handles multimodal with `[image]`/`[file: name]` placeholders)
- `Session.importJSON(_:)` -> `Session`
- `SessionStore.exportAll(userId:)` default extension (with N+1 awareness note)

#### 6d. Search

Per spec Section 15:
- `SearchableSessionStore` protocol
- `SearchResult` type
- SQLite FTS5 implementation on `SQLiteSessionStore`
- Firebase search throws `.unsupported` with guidance message

#### 6e. Tests

- `SessionExportTests.swift`: JSON round-trip, markdown format, import from exported data
- Search tests in `SQLiteSessionStoreTests.swift`: FTS5 queries, relevance ranking

**Acceptance Criteria:**
- [ ] Agent messages carry `agentId`/`agentName` attribution
- [ ] `Session.fork()` creates independent copy with new ID
- [ ] JSON export/import is lossless
- [ ] Markdown export is human-readable with proper formatting
- [ ] SQLite FTS5 search returns relevant results with snippets

---

### Phase 7: Integration Testing + Polish

**Goal:** End-to-end integration tests and final quality pass.

#### 7a. Integration Tests

- Full ChatViewModel flow with real `InMemorySessionStore`: send multiple messages, verify persistence after each step
- Resume flow: create session, send partial, simulate crash (discard ViewModel), reload from store, verify resume
- Rewind flow: send 5 messages, rewind to message 2, verify truncation
- Multi-agent: two agents sharing a session, verify attribution
- Compaction: send enough messages to trigger compaction, verify reduced message count
- Store migration: create sessions with old schema (no `id` on AIMessage), load with new code

#### 7b. Performance Verification

- Streaming persistence buffer: verify max 2 writes/second during simulated streaming
- SQLite: 1000 sessions CRUD in under 5 seconds
- FileSystem: 100 sessions CRUD with no file corruption
- Concurrent access: 50 parallel read/write operations on same store

#### 7c. Final Quality

- All public APIs have doc comments
- No `try!` or force-unwraps
- All errors properly typed as `SessionStoreError`
- `swift build` clean with no warnings
- `swift test` all green

**Acceptance Criteria:**
- [ ] All integration tests pass
- [ ] Performance benchmarks within targets
- [ ] No compiler warnings
- [ ] Full test coverage for all public APIs

---

## Dependency Impact

**No new Package.swift dependencies.** SQLite uses `import SQLite3` (system library on all Apple platforms). Firebase store is deferred to a future separate target.

**AIMessage changes** affect all existing code that constructs `AIMessage`. Since we're changing `let` to `var` (not removing or renaming), and adding new optional properties with defaults, this is **source-compatible** -- existing code compiles without changes. The new `id` property auto-generates via default parameter.

---

## Testing Strategy

| Layer | Test Type | Store | Count |
|-------|-----------|-------|-------|
| Models | Unit | N/A | ~15 tests |
| InMemoryStore | Conformance | InMemory | ~20 tests |
| FileSystemStore | Conformance + File I/O | FileSystem | ~20 tests |
| SQLiteStore | Conformance + SQL | SQLite | ~25 tests |
| MockStore | Unit | Mock | ~10 tests |
| PersistenceBuffer | Unit | Mock | ~8 tests |
| CompactionService | Unit | Mock LLM | ~10 tests |
| TitleGenerator | Unit | Mock LLM | ~5 tests |
| ChatViewModel | Integration | Mock | ~15 tests |
| SessionListViewModel | Unit | Mock | ~5 tests |
| Export/Import | Unit | N/A | ~8 tests |
| Search (SQLite FTS5) | Integration | SQLite | ~5 tests |
| End-to-end | Integration | InMemory | ~10 tests |
| **Total** | | | **~156 tests** |

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| AIMessage `let`->`var` breaks existing tests | Medium | Low | Run full test suite after changes; value semantics preserve Sendable |
| SQLite C API misuse (memory leaks) | Medium | Medium | Use RAII patterns; test with Address Sanitizer |
| Streaming persistence race conditions | Low | Medium | Actor isolation + structured concurrency; test with concurrent access |
| Large binary content in AIMessage (images) | Low | High | Document that binary content inflates session size; recommend external storage for media |
| Schema migration on app update | Low | High | `schemaVersion` field + migration-on-load pattern from day 1 |

---

## What Is Explicitly Deferred

Per spec phasing and dependency constraints:

1. **FirebaseSessionStore** -- Requires Firebase dependency (heavy). Will be a separate `AISDKFirebase` SPM target in a future PR.
2. **Encryption at rest** -- Spec says NO for now. Future `EncryptedSessionStore` wrapper.
3. **Branching/threading** -- Spec says keep it simple.
4. **Auto-cleanup/archival** -- Developer responsibility per design decision.
5. **Real `MultiAgentChatViewModel`** -- The handoff model and fork logic are included, but a full multi-agent ViewModel orchestrator is deferred to Phase 4 of the Agentic Roadmap.

---

## References

- [Agent Sessions Spec](../planning/sessions/2026-02-01-agent-sessions-storage-spec.md) (2,397 lines)
- [AISDK Agentic Roadmap](../AISDK-AGENTIC-ROADMAP.md) Phase 5
- [GitHub Issue #20](https://github.com/DanielhCarranza/AISDK/issues/20)
- `AIMessage`: `Sources/AISDK/Core/Protocols/LLM.swift:15-101`
- `AIStreamEvent`: `Sources/AISDK/Core/Models/AIStreamEvent.swift:14-92`
- `Agent` actor: `Sources/AISDK/Agents/Agent.swift`
- `LLM` protocol: `Sources/AISDK/Core/Protocols/LLM.swift:250-279`
- Existing compaction: `Sources/AISDK/LLMs/OpenAI/OpenAIProvider+Compaction.swift`
