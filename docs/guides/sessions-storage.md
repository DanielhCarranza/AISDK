# Sessions & Storage Guide

AISDK provides a session system for persisting conversations across app launches. Sessions support streaming persistence, checkpoints, and custom storage backends.

## Quick Start: Create, Stream, Load

```swift
import AISDK

let store = SQLiteSessionStore(path: "~/Documents/chat.db")

// Create a session
var session = AISession(userId: "user_123")
session = try await store.create(session)

// Append a user message
let userMsg = AIMessage(role: .user, content: .text("What is Swift concurrency?"))
try await store.appendMessage(userMsg, toSession: session.id)

// Stream assistant response and persist incrementally
let buffer = StreamingPersistenceBuffer(store: store, sessionId: session.id)
for try await event in llm.streamText(messages: session.messages) {
    switch event {
    case .textDelta(let text):
        await buffer.bufferDelta(text)
    case .stepFinish:
        await buffer.flush()
    default:
        break
    }
}
await buffer.flush()

// Load the session later
if let loaded = try await store.load(id: session.id) {
    print("Messages: \(loaded.messages.count)")
}
```

## Built-in Store Implementations

| Store | Use Case | Concurrency |
|-------|----------|-------------|
| `SQLiteSessionStore` | Production persistence | Actor + WAL mode |
| `FileSystemSessionStore` | Simple file-based storage | Actor isolated |
| `InMemorySessionStore` | Testing and ephemeral sessions | Actor isolated |

## Custom Backend: SessionStore Protocol

To use Firebase, CoreData, or any custom backend, conform to `SessionStore`:

```swift
public actor FirebaseSessionStore: SessionStore {
    // Required — 5 core methods:

    func create(_ session: AISession) async throws -> AISession {
        // Write session to Firestore
        try await db.collection("sessions").document(session.id).setData(session.encoded())
        return session
    }

    func load(id: String) async throws -> AISession? {
        // Read session from Firestore
        let doc = try await db.collection("sessions").document(id).getDocument()
        return try doc.data(as: AISession.self)
    }

    func save(_ session: AISession) async throws {
        // Full upsert
        try await db.collection("sessions").document(session.id).setData(session.encoded())
    }

    func delete(id: String) async throws {
        try await db.collection("sessions").document(id).delete()
    }

    func list(
        userId: String,
        status: SessionStatus?,
        limit: Int,
        cursor: String?,
        orderBy: SessionOrderBy
    ) async throws -> SessionListResult {
        // Query Firestore with filters and pagination
        var query = db.collection("sessions")
            .whereField("userId", isEqualTo: userId)
            .order(by: orderBy == .createdAt ? "createdAt" : "updatedAt")
            .limit(to: limit)
        if let status { query = query.whereField("status", isEqualTo: status.rawValue) }
        if let cursor { query = query.start(afterDocument: cursor) }
        let snapshot = try await query.getDocuments()
        let summaries = snapshot.documents.compactMap { try? $0.data(as: SessionSummary.self) }
        return SessionListResult(sessions: summaries, nextCursor: snapshot.documents.last?.documentID)
    }

    // Optional — have default implementations but override for efficiency:

    func appendMessage(_ message: AIMessage, toSession sessionId: String) async throws {
        // Incremental update — cheaper than full save during streaming
        try await db.collection("sessions").document(sessionId).updateData([
            "messages": FieldValue.arrayUnion([message.encoded()])
        ])
    }

    func updateLastMessage(_ message: AIMessage, inSession sessionId: String) async throws {
        // Update the last message in place (streaming delta accumulation)
        var session = try await load(id: sessionId)!
        session.messages[session.messages.count - 1] = message
        try await save(session)
    }
}
```

The 5 core methods (`create`, `load`, `save`, `delete`, `list`) are required. The incremental update methods (`appendMessage`, `updateLastMessage`, `updateStatus`, `updateMetadata`) and `observe` have default implementations that fall back to full `load` + `save`.

## SQLite Concurrent Safety

`SQLiteSessionStore` is a Swift actor with WAL (Write-Ahead Logging) enabled:
- All method calls serialize through the actor — no data races
- WAL allows concurrent reads while a write is in progress
- Prepared statements are cached for performance
- `appendMessage` and `updateLastMessage` only rewrite the `messages_json` column, not the full row

## Session Status Lifecycle

```
active → paused → active → completed
   ↓                          ↓
  error                   archived
```

Statuses: `.active`, `.completed`, `.paused`, `.error`, `.archived`

## Checkpoints

Save restorable points during long conversations:

```swift
session.addCheckpoint(.manual, label: "Before tool call")
// ... later ...
if let checkpoint = session.checkpoints.last {
    let restored = session.messages[0..<checkpoint.messageIndex]
}
```

## Schema Migration

Sessions include a `schemaVersion` field (currently version 1). When the schema changes between betas, increment the version and handle migration in your store:

```swift
func load(id: String) async throws -> AISession? {
    var session = try await rawLoad(id: id)
    if session?.schemaVersion == 1 {
        // Migrate v1 → v2
        session?.schemaVersion = 2
        if let s = session { try await save(s) }
    }
    return session
}
```

The `AISession.init(from:)` decoder uses `decodeIfPresent` with defaults for all fields, providing soft forward/backward compatibility for JSON-stored data.
