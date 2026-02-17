//
//  SessionEvalSuite.swift
//  AISDKTestRunner
//
//  Layer 2: Session evaluation suite for AISDK.
//  Validates serialization roundtrip across all 3 store types,
//  concurrent access patterns, message append/load cycles, and metadata persistence.
//

import Foundation
import AISDK

public final class SessionEvalSuite: TestSuiteProtocol {
    public let reporter: TestReporter
    public let verbose: Bool
    private let suiteName = "SessionEval"

    public init(reporter: TestReporter, verbose: Bool) {
        self.reporter = reporter
        self.verbose = verbose
    }

    public func run() async throws {
        reporter.log("Starting session evaluation suite...")

        // Roundtrip across all store types
        await testInMemoryStoreRoundtrip()
        await testFileSystemStoreRoundtrip()
        await testSQLiteStoreRoundtrip()

        // Advanced session operations
        await testLargeMessageHistory()
        await testConcurrentAppendAccess()
        await testSessionListAndFilter()
        await testMetadataUpdatePersistence()
        await testStatusTransitions()
        await testUpdateLastMessage()
        await testMultipleSessionIsolation()
    }

    // MARK: - Store Roundtrip Tests

    private func testInMemoryStoreRoundtrip() async {
        await withTimer("InMemoryStore full roundtrip", suiteName) {
            let store = InMemorySessionStore()
            try await runStoreRoundtrip(store: store, storeName: "InMemory")
        }
    }

    private func testFileSystemStoreRoundtrip() async {
        await withTimer("FileSystemStore full roundtrip", suiteName) {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("aisdk-session-eval-\(UUID().uuidString)")

            let store = try FileSystemSessionStore(directory: tempDir)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }

            try await runStoreRoundtrip(store: store, storeName: "FileSystem")
        }
    }

    private func testSQLiteStoreRoundtrip() async {
        await withTimer("SQLiteStore full roundtrip", suiteName) {
            let store = try SQLiteSessionStore()
            try await runStoreRoundtrip(store: store, storeName: "SQLite")
        }
    }

    private func runStoreRoundtrip(store: some SessionStore, storeName: String) async throws {
        // 1. Create
        let session = AISession(
            userId: "roundtrip-\(storeName)",
            title: "Roundtrip Test \(storeName)",
            metadata: ["testKey": "testValue"]
        )
        let created = try await store.create(session)

        guard created.id == session.id else {
            throw TestError.assertionFailed("\(storeName): ID mismatch on create")
        }
        reporter.log("\(storeName): created session \(created.id.prefix(8))")

        // 2. Append messages with different roles
        try await store.appendMessage(.user("User message 1"), toSession: session.id)
        try await store.appendMessage(.assistant("Assistant response 1"), toSession: session.id)
        try await store.appendMessage(.user("User message 2"), toSession: session.id)
        try await store.appendMessage(.assistant("Assistant response 2"), toSession: session.id)

        // 3. Load and verify message integrity
        guard let loaded = try await store.load(id: session.id) else {
            throw TestError.assertionFailed("\(storeName): failed to load session")
        }

        guard loaded.messages.count == 4 else {
            throw TestError.assertionFailed("\(storeName): expected 4 messages, got \(loaded.messages.count)")
        }

        // Verify role alternation
        let expectedRoles: [AIMessage.Role] = [.user, .assistant, .user, .assistant]
        for (i, expected) in expectedRoles.enumerated() {
            guard loaded.messages[i].role == expected else {
                throw TestError.assertionFailed(
                    "\(storeName): message \(i) role is \(loaded.messages[i].role), expected \(expected)"
                )
            }
        }

        // Verify content integrity
        guard loaded.messages[0].content.textValue == "User message 1" else {
            throw TestError.assertionFailed("\(storeName): message 0 content corrupted")
        }
        guard loaded.messages[3].content.textValue == "Assistant response 2" else {
            throw TestError.assertionFailed("\(storeName): message 3 content corrupted")
        }

        // 4. Verify title persisted
        guard loaded.title == "Roundtrip Test \(storeName)" else {
            throw TestError.assertionFailed("\(storeName): title mismatch: '\(loaded.title ?? "nil")'")
        }

        // 5. Save modified and re-verify
        var modified = loaded
        modified.title = "Modified \(storeName)"
        try await store.save(modified)

        guard let reloaded = try await store.load(id: session.id) else {
            throw TestError.assertionFailed("\(storeName): failed to reload after save")
        }

        guard reloaded.title == "Modified \(storeName)" else {
            throw TestError.assertionFailed("\(storeName): title not persisted: '\(reloaded.title ?? "nil")'")
        }
        guard reloaded.messages.count == 4 else {
            throw TestError.assertionFailed("\(storeName): messages lost after save")
        }

        // 6. Delete and verify gone
        try await store.delete(id: session.id)
        let deleted = try await store.load(id: session.id)
        guard deleted == nil else {
            throw TestError.assertionFailed("\(storeName): session still exists after delete")
        }

        reporter.log("\(storeName): full roundtrip passed")
    }

    // MARK: - Large Message History

    private func testLargeMessageHistory() async {
        await withTimer("Large message history (100 messages)", suiteName) {
            let store = InMemorySessionStore()
            let session = AISession(userId: "large-history", title: "Large History Test")
            _ = try await store.create(session)

            let messageCount = 100

            // Append alternating user/assistant messages
            for i in 0..<messageCount {
                if i % 2 == 0 {
                    try await store.appendMessage(
                        .user("User message \(i / 2 + 1): This is a moderately long message to simulate real conversation content."),
                        toSession: session.id
                    )
                } else {
                    try await store.appendMessage(
                        .assistant("Assistant response \(i / 2 + 1): Here is a helpful reply with some detail."),
                        toSession: session.id
                    )
                }
            }

            // Load and verify all messages survived
            guard let loaded = try await store.load(id: session.id) else {
                throw TestError.assertionFailed("Failed to load session with \(messageCount) messages")
            }

            guard loaded.messages.count == messageCount else {
                throw TestError.assertionFailed(
                    "Expected \(messageCount) messages, got \(loaded.messages.count)"
                )
            }

            // Verify first and last messages
            guard loaded.messages[0].role == .user else {
                throw TestError.assertionFailed("First message should be user")
            }
            guard loaded.messages[messageCount - 1].role == .assistant else {
                throw TestError.assertionFailed("Last message should be assistant")
            }

            // Verify a middle message
            let midIdx = messageCount / 2
            guard !loaded.messages[midIdx].content.textValue.isEmpty else {
                throw TestError.assertionFailed("Middle message (\(midIdx)) has empty content")
            }

            reporter.log("Large history: \(loaded.messages.count) messages loaded successfully")
        }
    }

    // MARK: - Concurrent Access

    private func testConcurrentAppendAccess() async {
        await withTimer("Concurrent append access (20 concurrent appends)", suiteName) {
            let store = InMemorySessionStore()
            let session = AISession(userId: "concurrent-test", title: "Concurrent Test")
            _ = try await store.create(session)

            let concurrentAppends = 20

            // Concurrent appends from multiple tasks
            await withTaskGroup(of: Error?.self) { group in
                for i in 0..<concurrentAppends {
                    group.addTask {
                        do {
                            try await store.appendMessage(
                                .user("Concurrent message \(i)"),
                                toSession: session.id
                            )
                            return nil
                        } catch {
                            return error
                        }
                    }
                }

                var errors: [Error] = []
                for await error in group {
                    if let error = error {
                        errors.append(error)
                    }
                }

                if !errors.isEmpty {
                    reporter.log("Concurrent appends had \(errors.count) errors: \(errors.first!)")
                }
            }

            // Load and verify -- at minimum, the session shouldn't be corrupted
            guard let loaded = try await store.load(id: session.id) else {
                throw TestError.assertionFailed("Session not found after concurrent appends")
            }

            // All messages should have been appended (actor isolation guarantees ordering)
            guard loaded.messages.count == concurrentAppends else {
                throw TestError.assertionFailed(
                    "Expected \(concurrentAppends) messages after concurrent appends, got \(loaded.messages.count)"
                )
            }

            reporter.log("Concurrent access: \(loaded.messages.count) messages after \(concurrentAppends) concurrent appends")
        }
    }

    // MARK: - Session List and Filter

    private func testSessionListAndFilter() async {
        await withTimer("Session list and filtering", suiteName) {
            let store = InMemorySessionStore()

            // Create multiple sessions with different users
            let session1 = AISession(userId: "user-a", title: "Session A1")
            let session2 = AISession(userId: "user-a", title: "Session A2")
            let session3 = AISession(userId: "user-b", title: "Session B1")

            _ = try await store.create(session1)
            _ = try await store.create(session2)
            _ = try await store.create(session3)

            // List sessions for user-a
            let userASessions = try await store.list(
                userId: "user-a",
                status: nil,
                limit: 100,
                cursor: nil,
                orderBy: .createdAtDesc
            )
            guard userASessions.sessions.count == 2 else {
                throw TestError.assertionFailed(
                    "Expected 2 sessions for user-a, got \(userASessions.sessions.count)"
                )
            }

            // List sessions for user-b
            let userBSessions = try await store.list(
                userId: "user-b",
                status: nil,
                limit: 100,
                cursor: nil,
                orderBy: .createdAtDesc
            )
            guard userBSessions.sessions.count == 1 else {
                throw TestError.assertionFailed(
                    "Expected 1 session for user-b, got \(userBSessions.sessions.count)"
                )
            }

            reporter.log("Session list: user-a=\(userASessions.sessions.count), user-b=\(userBSessions.sessions.count)")
        }
    }

    // MARK: - Metadata Update Persistence

    private func testMetadataUpdatePersistence() async {
        await withTimer("Metadata update persistence", suiteName) {
            let store = InMemorySessionStore()
            let session = AISession(
                userId: "metadata-test",
                title: "Metadata Test",
                metadata: ["key1": "value1"]
            )
            _ = try await store.create(session)

            // Update metadata
            try await store.updateMetadata(
                SessionMetadataUpdate(metadata: ["key2": "value2", "key1": "updated"]),
                forSession: session.id
            )

            // Load and verify
            guard let loaded = try await store.load(id: session.id) else {
                throw TestError.assertionFailed("Failed to load after metadata update")
            }

            guard let metadata = loaded.metadata else {
                throw TestError.assertionFailed("Metadata is nil after update")
            }

            guard metadata["key1"] == "updated" else {
                throw TestError.assertionFailed("key1 not updated: '\(metadata["key1"] ?? "nil")'")
            }

            guard metadata["key2"] == "value2" else {
                throw TestError.assertionFailed("key2 not set: '\(metadata["key2"] ?? "nil")'")
            }

            reporter.log("Metadata update: key1=\(metadata["key1"] ?? "nil"), key2=\(metadata["key2"] ?? "nil")")
        }
    }

    // MARK: - Status Transitions

    private func testStatusTransitions() async {
        await withTimer("Session status transitions", suiteName) {
            let store = InMemorySessionStore()
            let session = AISession(userId: "status-test", title: "Status Test")
            _ = try await store.create(session)

            // Verify initial status
            guard let initial = try await store.load(id: session.id) else {
                throw TestError.assertionFailed("Failed to load initial session")
            }
            guard initial.status == .active else {
                throw TestError.assertionFailed("Initial status should be .active, got \(initial.status)")
            }

            // Transition: active -> paused
            try await store.updateStatus(.paused, forSession: session.id)
            guard let paused = try await store.load(id: session.id) else {
                throw TestError.assertionFailed("Failed to load after pause")
            }
            guard paused.status == .paused else {
                throw TestError.assertionFailed("Status should be .paused, got \(paused.status)")
            }

            // Transition: paused -> completed
            try await store.updateStatus(.completed, forSession: session.id)
            guard let completed = try await store.load(id: session.id) else {
                throw TestError.assertionFailed("Failed to load after complete")
            }
            guard completed.status == .completed else {
                throw TestError.assertionFailed("Status should be .completed, got \(completed.status)")
            }

            reporter.log("Status transitions: active -> paused -> completed passed")
        }
    }

    // MARK: - Update Last Message

    private func testUpdateLastMessage() async {
        await withTimer("Update last message (streaming simulation)", suiteName) {
            let store = InMemorySessionStore()
            let session = AISession(userId: "update-last-test", title: "Update Last Test")
            _ = try await store.create(session)

            // Append user message
            try await store.appendMessage(.user("Hello"), toSession: session.id)

            // Append initial assistant message (partial, simulating stream start)
            try await store.appendMessage(.assistant("Hi"), toSession: session.id)

            // Update last message (simulating streaming accumulation)
            try await store.updateLastMessage(.assistant("Hi there! How can I help you today?"), inSession: session.id)

            // Verify the last message was updated, not duplicated
            guard let loaded = try await store.load(id: session.id) else {
                throw TestError.assertionFailed("Failed to load after updateLastMessage")
            }

            guard loaded.messages.count == 2 else {
                throw TestError.assertionFailed(
                    "Expected 2 messages (user + assistant), got \(loaded.messages.count)"
                )
            }

            let lastMessage = loaded.messages[1]
            guard lastMessage.role == .assistant else {
                throw TestError.assertionFailed("Last message should be assistant")
            }

            guard lastMessage.content.textValue == "Hi there! How can I help you today?" else {
                throw TestError.assertionFailed(
                    "Last message content not updated: '\(lastMessage.content.textValue)'"
                )
            }

            reporter.log("updateLastMessage: correctly updated assistant message in-place")
        }
    }

    // MARK: - Multiple Session Isolation

    private func testMultipleSessionIsolation() async {
        await withTimer("Multiple session isolation", suiteName) {
            let store = InMemorySessionStore()

            // Create two separate sessions
            let sessionA = AISession(userId: "isolation-user", title: "Session A")
            let sessionB = AISession(userId: "isolation-user", title: "Session B")
            _ = try await store.create(sessionA)
            _ = try await store.create(sessionB)

            // Add different messages to each
            try await store.appendMessage(.user("Message for A"), toSession: sessionA.id)
            try await store.appendMessage(.assistant("Reply in A"), toSession: sessionA.id)

            try await store.appendMessage(.user("Message for B only"), toSession: sessionB.id)

            // Verify isolation
            guard let loadedA = try await store.load(id: sessionA.id) else {
                throw TestError.assertionFailed("Failed to load session A")
            }
            guard let loadedB = try await store.load(id: sessionB.id) else {
                throw TestError.assertionFailed("Failed to load session B")
            }

            guard loadedA.messages.count == 2 else {
                throw TestError.assertionFailed("Session A should have 2 messages, got \(loadedA.messages.count)")
            }
            guard loadedB.messages.count == 1 else {
                throw TestError.assertionFailed("Session B should have 1 message, got \(loadedB.messages.count)")
            }

            // Verify no cross-contamination
            guard loadedA.messages[0].content.textValue == "Message for A" else {
                throw TestError.assertionFailed("Session A message content cross-contaminated")
            }
            guard loadedB.messages[0].content.textValue == "Message for B only" else {
                throw TestError.assertionFailed("Session B message content cross-contaminated")
            }

            // Delete A and verify B is unaffected
            try await store.delete(id: sessionA.id)
            guard let bAfterDelete = try await store.load(id: sessionB.id) else {
                throw TestError.assertionFailed("Session B should survive deletion of A")
            }
            guard bAfterDelete.messages.count == 1 else {
                throw TestError.assertionFailed("Session B messages affected by A deletion")
            }

            reporter.log("Session isolation: A and B maintained separate state")
        }
    }
}
