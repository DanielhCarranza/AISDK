//
//  SessionTests.swift
//  AISDKTests
//
//  Tests for AISession, SessionStatus, SessionCheckpoint, and related types.
//

import XCTest
@testable import AISDK

final class SessionTests: XCTestCase {

    // MARK: - AISession Initialization

    func test_init_setsDefaults() {
        let session = AISession(userId: "user_1")

        XCTAssertFalse(session.id.isEmpty)
        XCTAssertEqual(session.userId, "user_1")
        XCTAssertNil(session.agentId)
        XCTAssertNil(session.title)
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertNil(session.metadata)
        XCTAssertNil(session.tags)
        XCTAssertEqual(session.status, .active)
        XCTAssertTrue(session.checkpoints.isEmpty)
        XCTAssertNil(session.lastCheckpointIndex)
        XCTAssertTrue(session.isLastMessageComplete)
        XCTAssertEqual(session.schemaVersion, 1)
    }

    func test_init_withCustomValues() {
        let messages = [AIMessage.user("Hello"), AIMessage.assistant("Hi")]
        let session = AISession(
            id: "custom_id",
            userId: "user_2",
            agentId: "agent_1",
            title: "Test Chat",
            messages: messages,
            metadata: ["key": "value"],
            tags: ["test", "demo"]
        )

        XCTAssertEqual(session.id, "custom_id")
        XCTAssertEqual(session.userId, "user_2")
        XCTAssertEqual(session.agentId, "agent_1")
        XCTAssertEqual(session.title, "Test Chat")
        XCTAssertEqual(session.messages.count, 2)
        XCTAssertEqual(session.metadata?["key"], "value")
        XCTAssertEqual(session.tags, ["test", "demo"])
    }

    // MARK: - Hashable & Equatable

    func test_equality_usesIdOnly() {
        var session1 = AISession(id: "same_id", userId: "user_1")
        var session2 = AISession(id: "same_id", userId: "user_2")

        // Same ID = equal, even with different user
        XCTAssertEqual(session1, session2)

        // Different ID = not equal
        let session3 = AISession(id: "different_id", userId: "user_1")
        XCTAssertNotEqual(session1, session3)
    }

    func test_hashable() {
        let session1 = AISession(id: "id_1", userId: "user")
        let session2 = AISession(id: "id_2", userId: "user")
        let session3 = AISession(id: "id_1", userId: "other_user")

        var set = Set<AISession>()
        set.insert(session1)
        set.insert(session2)
        set.insert(session3) // Same ID as session1, should not add

        XCTAssertEqual(set.count, 2)
    }

    // MARK: - Codable Round-Trip

    func test_codable_roundTrip() throws {
        var session = AISession(
            userId: "user_1",
            agentId: "agent_1",
            title: "Test",
            messages: [
                .user("Hello"),
                .assistant("Hi there!"),
                .tool("result", toolCallId: "call_1")
            ],
            metadata: ["env": "test"],
            tags: ["tag1"]
        )
        session.status = .paused
        session.isLastMessageComplete = false
        session.lastCheckpointIndex = 1

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AISession.self, from: data)

        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.userId, session.userId)
        XCTAssertEqual(decoded.agentId, session.agentId)
        XCTAssertEqual(decoded.title, session.title)
        XCTAssertEqual(decoded.messages.count, 3)
        XCTAssertEqual(decoded.status, .paused)
        XCTAssertFalse(decoded.isLastMessageComplete)
        XCTAssertEqual(decoded.lastCheckpointIndex, 1)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.metadata?["env"], "test")
        XCTAssertEqual(decoded.tags, ["tag1"])
    }

    func test_codable_backwardCompatibility() throws {
        // Simulate old JSON without new session fields
        let json = """
        {
            "id": "old_session",
            "userId": "user_1",
            "createdAt": "2026-01-01T00:00:00Z",
            "lastActivityAt": "2026-01-01T00:00:00Z",
            "status": "active",
            "messages": []
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(AISession.self, from: data)

        XCTAssertEqual(session.id, "old_session")
        XCTAssertEqual(session.userId, "user_1")
        XCTAssertEqual(session.status, .active)
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertTrue(session.checkpoints.isEmpty)
        XCTAssertTrue(session.isLastMessageComplete)
        XCTAssertEqual(session.schemaVersion, 1)
    }

    // MARK: - Checkpoint Management

    func test_createCheckpoint() {
        var session = AISession(userId: "user_1")
        session.messages = [.user("Hello")]

        session.createCheckpoint(type: .userMessage, label: "First message")

        XCTAssertEqual(session.checkpoints.count, 1)
        XCTAssertEqual(session.checkpoints[0].index, 0)
        XCTAssertEqual(session.checkpoints[0].messageIndex, 0)
        XCTAssertEqual(session.checkpoints[0].type, .userMessage)
        XCTAssertEqual(session.checkpoints[0].label, "First message")
        XCTAssertEqual(session.lastCheckpointIndex, 0)
        XCTAssertTrue(session.messages[0].isCheckpoint)
        XCTAssertEqual(session.messages[0].checkpointIndex, 0)
    }

    func test_createMultipleCheckpoints() {
        var session = AISession(userId: "user_1")
        session.messages = [
            .user("Hello"),
            .assistant("Hi!"),
            .user("How are you?"),
            .assistant("Great!")
        ]

        session.createCheckpoint(type: .userMessage)
        session.messages.append(.user("Another"))
        session.createCheckpoint(type: .userMessage)

        XCTAssertEqual(session.checkpoints.count, 2)
        XCTAssertEqual(session.checkpoints[0].messageIndex, 3) // After "Great!"
        XCTAssertEqual(session.checkpoints[1].messageIndex, 4) // After "Another"
        XCTAssertEqual(session.lastCheckpointIndex, 1)
    }

    // MARK: - Rewind

    func test_rewind_toValidCheckpoint() {
        var session = AISession(userId: "user_1")
        session.messages = [
            .user("Hello"),
            .assistant("Hi!"),
            .user("How are you?"),
            .assistant("Great!")
        ]

        // Create checkpoint at message index 1 (after "Hi!")
        session.checkpoints = [
            SessionCheckpoint(index: 0, messageIndex: 1, type: .assistantComplete)
        ]

        session.rewind(to: 0)

        XCTAssertEqual(session.messages.count, 2) // "Hello" and "Hi!"
        XCTAssertEqual(session.lastCheckpointIndex, 0)
        XCTAssertTrue(session.isLastMessageComplete)
    }

    func test_rewind_toInvalidCheckpoint_doesNothing() {
        var session = AISession(userId: "user_1")
        session.messages = [.user("Hello"), .assistant("Hi")]

        session.rewind(to: 99) // Invalid checkpoint

        XCTAssertEqual(session.messages.count, 2) // Unchanged
    }

    func test_rewind_removesLaterCheckpoints() {
        var session = AISession(userId: "user_1")
        session.messages = [
            .user("1"), .assistant("2"),
            .user("3"), .assistant("4"),
            .user("5"), .assistant("6")
        ]
        session.checkpoints = [
            SessionCheckpoint(index: 0, messageIndex: 1, type: .assistantComplete),
            SessionCheckpoint(index: 1, messageIndex: 3, type: .assistantComplete),
            SessionCheckpoint(index: 2, messageIndex: 5, type: .assistantComplete)
        ]

        session.rewind(to: 1)

        XCTAssertEqual(session.messages.count, 4)
        XCTAssertEqual(session.checkpoints.count, 2) // Only checkpoints 0 and 1
    }

    // MARK: - Messages At Checkpoint

    func test_messagesAtCheckpoint() {
        var session = AISession(userId: "user_1")
        session.messages = [
            .user("1"), .assistant("2"),
            .user("3"), .assistant("4")
        ]
        session.checkpoints = [
            SessionCheckpoint(index: 0, messageIndex: 1, type: .assistantComplete)
        ]

        let messages = session.messagesAtCheckpoint(0)
        XCTAssertEqual(messages.count, 2) // Messages 0 and 1
    }

    func test_messagesAtCheckpoint_invalidIndex_returnsAll() {
        let session = AISession(userId: "user_1", messages: [.user("Hello")])
        let messages = session.messagesAtCheckpoint(99)
        XCTAssertEqual(messages.count, 1) // Returns all messages
    }

    // MARK: - Fork

    func test_fork_createsNewSessionWithCopiedMessages() {
        var session = AISession(
            userId: "user_1",
            agentId: "agent_1",
            title: "Original",
            messages: [.user("Hello"), .assistant("Hi!")],
            metadata: ["key": "val"],
            tags: ["tag"]
        )
        session.checkpoints = [
            SessionCheckpoint(index: 0, messageIndex: 1, type: .assistantComplete)
        ]
        session.lastCheckpointIndex = 0

        let forked = session.fork()

        XCTAssertNotEqual(forked.id, session.id)
        XCTAssertEqual(forked.userId, session.userId)
        XCTAssertEqual(forked.title, "Original (fork)")
        XCTAssertEqual(forked.messages.count, 2)
        XCTAssertEqual(forked.metadata?["key"], "val")
        XCTAssertEqual(forked.tags, ["tag"])
        XCTAssertEqual(forked.checkpoints.count, 1)
        XCTAssertEqual(forked.lastCheckpointIndex, 0)
    }

    func test_fork_withDifferentUser() {
        let session = AISession(userId: "user_1")
        let forked = session.fork(newUserId: "user_2")
        XCTAssertEqual(forked.userId, "user_2")
    }

    // MARK: - Summary

    func test_summary() {
        let session = AISession(
            userId: "user_1",
            title: "Chat",
            messages: [.user("Hello"), .assistant("Hi!")],
            tags: ["tag1"]
        )

        let summary = session.summary
        XCTAssertEqual(summary.id, session.id)
        XCTAssertEqual(summary.userId, "user_1")
        XCTAssertEqual(summary.title, "Chat")
        XCTAssertEqual(summary.status, .active)
        XCTAssertEqual(summary.messageCount, 2)
        XCTAssertEqual(summary.tags, ["tag1"])
    }
}

// MARK: - AIMessage Session Properties Tests

final class AIMessageSessionTests: XCTestCase {

    func test_aiMessage_hasId() {
        let message = AIMessage.user("Hello")
        XCTAssertFalse(message.id.isEmpty)
    }

    func test_aiMessage_uniqueIds() {
        let msg1 = AIMessage.user("Hello")
        let msg2 = AIMessage.user("Hello")
        XCTAssertNotEqual(msg1.id, msg2.id)
    }

    func test_aiMessage_sessionProperties_defaults() {
        let message = AIMessage.user("Hello")
        XCTAssertNil(message.agentId)
        XCTAssertNil(message.agentName)
        XCTAssertFalse(message.isCheckpoint)
        XCTAssertNil(message.checkpointIndex)
    }

    func test_aiMessage_sessionProperties_mutable() {
        var message = AIMessage.assistant("Hello")
        message.agentId = "agent_1"
        message.agentName = "Research Agent"
        message.isCheckpoint = true
        message.checkpointIndex = 3

        XCTAssertEqual(message.agentId, "agent_1")
        XCTAssertEqual(message.agentName, "Research Agent")
        XCTAssertTrue(message.isCheckpoint)
        XCTAssertEqual(message.checkpointIndex, 3)
    }

    func test_aiMessage_appendText() {
        var message = AIMessage.assistant("")
        message.appendText("Hello ")
        message.appendText("world")
        XCTAssertEqual(message.content.textValue, "Hello world")
    }

    func test_aiMessage_appendText_toParts() {
        var message = AIMessage(role: .assistant, content: .parts([.text("Hello ")]))
        message.appendText("world")
        XCTAssertEqual(message.content.textValue, "Hello world")
    }

    func test_aiMessage_textContent() {
        let message = AIMessage.user("Hello")
        XCTAssertEqual(message.textContent, "Hello")

        let emptyMessage = AIMessage.assistant("")
        XCTAssertNil(emptyMessage.textContent)
    }

    func test_aiMessage_mutableToolCalls() {
        var message = AIMessage.assistant("")
        message.toolCalls = [AIMessage.ToolCall(id: "1", name: "search", arguments: "")]
        XCTAssertEqual(message.toolCalls?.count, 1)

        message.toolCalls?[0].arguments += "{\"q\":\"hello\"}"
        XCTAssertEqual(message.toolCalls?[0].arguments, "{\"q\":\"hello\"}")
    }

    func test_aiMessage_assistantWithAttribution() {
        let message = AIMessage.assistant(
            "Hello",
            agentId: "agent_1",
            agentName: "Research Agent"
        )
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.textContent, "Hello")
        XCTAssertEqual(message.agentId, "agent_1")
        XCTAssertEqual(message.agentName, "Research Agent")
    }

    func test_aiMessage_codable_withSessionProperties() throws {
        var message = AIMessage.assistant("Hello")
        message.agentId = "agent_1"
        message.agentName = "Agent"
        message.isCheckpoint = true
        message.checkpointIndex = 5

        let encoder = JSONEncoder()
        let data = try encoder.encode(message)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIMessage.self, from: data)

        XCTAssertEqual(decoded.id, message.id)
        XCTAssertEqual(decoded.agentId, "agent_1")
        XCTAssertEqual(decoded.agentName, "Agent")
        XCTAssertTrue(decoded.isCheckpoint)
        XCTAssertEqual(decoded.checkpointIndex, 5)
    }

    func test_aiMessage_codable_backwardCompat() throws {
        // Old JSON without id, agentId, etc.
        let json = """
        {
            "role": "user",
            "content": {"type": "text", "value": "Hello"}
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let message = try decoder.decode(AIMessage.self, from: data)

        XCTAssertEqual(message.role, .user)
        XCTAssertEqual(message.content.textValue, "Hello")
        XCTAssertFalse(message.id.isEmpty) // Auto-generated
        XCTAssertNil(message.agentId)
        XCTAssertFalse(message.isCheckpoint)
    }
}

// MARK: - SessionStatus Tests

final class SessionStatusTests: XCTestCase {
    func test_rawValues() {
        XCTAssertEqual(SessionStatus.active.rawValue, "active")
        XCTAssertEqual(SessionStatus.completed.rawValue, "completed")
        XCTAssertEqual(SessionStatus.paused.rawValue, "paused")
        XCTAssertEqual(SessionStatus.error.rawValue, "error")
        XCTAssertEqual(SessionStatus.archived.rawValue, "archived")
    }

    func test_codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for status in [SessionStatus.active, .completed, .paused, .error, .archived] {
            let data = try encoder.encode(status)
            let decoded = try decoder.decode(SessionStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }
}

// MARK: - SessionStoreError Tests

final class SessionStoreErrorTests: XCTestCase {
    func test_errorDescriptions() {
        XCTAssertNotNil(SessionStoreError.notFound(sessionId: "abc").errorDescription)
        XCTAssertNotNil(SessionStoreError.alreadyExists(sessionId: "abc").errorDescription)
        XCTAssertNotNil(SessionStoreError.unavailable(reason: "offline").errorDescription)
        XCTAssertNotNil(SessionStoreError.invalidData(reason: "bad json").errorDescription)
        XCTAssertNotNil(SessionStoreError.unsupported(operation: "search").errorDescription)
        XCTAssertNotNil(SessionStoreError.permissionDenied(reason: "no access").errorDescription)
    }
}
