//
//  SessionExportTests.swift
//  AISDKTests
//
//  Tests for session export and import.
//

import XCTest
@testable import AISDK

final class SessionExportTests: XCTestCase {

    // MARK: - JSON Export/Import

    func test_exportJSON_roundTrip() throws {
        let session = AISession(
            id: "test-export",
            userId: "user_1",
            title: "Export Test",
            messages: [
                .user("Hello"),
                .assistant("Hi there!"),
                .user("How are you?")
            ],
            metadata: ["key": "value"],
            tags: ["test", "export"]
        )

        let json = try session.exportJSON()
        let imported = try AISession.importJSON(json)

        XCTAssertEqual(imported.id, session.id)
        XCTAssertEqual(imported.userId, session.userId)
        XCTAssertEqual(imported.title, session.title)
        XCTAssertEqual(imported.messages.count, 3)
        XCTAssertEqual(imported.metadata?["key"], "value")
        XCTAssertEqual(imported.tags, ["test", "export"])
    }

    func test_exportJSON_preservesAllFields() throws {
        var session = AISession(
            id: "full-test",
            userId: "user_1",
            agentId: "agent-1",
            title: "Full Fields"
        )
        session.status = .paused
        session.createCheckpoint(type: .manual, label: "Test checkpoint")

        let json = try session.exportJSON()
        let imported = try AISession.importJSON(json)

        XCTAssertEqual(imported.agentId, "agent-1")
        XCTAssertEqual(imported.status, .paused)
        XCTAssertEqual(imported.schemaVersion, 1)
    }

    func test_exportJSON_producesValidJSON() throws {
        let session = AISession(userId: "user_1", title: "Test")
        let json = try session.exportJSON()

        // Should be valid JSON
        let parsed = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["userId"] as? String, "user_1")
    }

    func test_importJSON_invalidData_throws() {
        let invalidData = "not json".data(using: .utf8)!

        XCTAssertThrowsError(try AISession.importJSON(invalidData))
    }

    // MARK: - Markdown Export

    func test_exportMarkdown_includesMetadata() {
        let session = AISession(
            id: "md-test",
            userId: "user_1",
            title: "Markdown Test",
            tags: ["tag1", "tag2"]
        )

        let markdown = session.exportMarkdown()

        XCTAssertTrue(markdown.contains("# Markdown Test"))
        XCTAssertTrue(markdown.contains("md-test"))
        XCTAssertTrue(markdown.contains("user_1"))
        XCTAssertTrue(markdown.contains("tag1, tag2"))
    }

    func test_exportMarkdown_formatsMessages() {
        let session = AISession(
            userId: "user_1",
            messages: [
                .user("Hello"),
                .assistant("World")
            ]
        )

        let markdown = session.exportMarkdown()

        XCTAssertTrue(markdown.contains("### User"))
        XCTAssertTrue(markdown.contains("Hello"))
        XCTAssertTrue(markdown.contains("### Assistant"))
        XCTAssertTrue(markdown.contains("World"))
    }

    func test_exportMarkdown_formatsToolCalls() {
        let session = AISession(
            userId: "user_1",
            messages: [
                AIMessage(
                    role: .assistant,
                    content: .text("Let me search"),
                    toolCalls: [AIMessage.ToolCall(id: "tc1", name: "search", arguments: "{\"q\":\"test\"}")]
                ),
                .tool("Found result", toolCallId: "tc1")
            ]
        )

        let markdown = session.exportMarkdown()

        XCTAssertTrue(markdown.contains("**Tool Calls:**"))
        XCTAssertTrue(markdown.contains("`search`"))
        XCTAssertTrue(markdown.contains("### Tool Result"))
    }

    func test_exportMarkdown_agentAttribution() {
        let session = AISession(
            userId: "user_1",
            messages: [
                .assistant("Hello", agentId: "agent-1", agentName: "Research Bot")
            ]
        )

        let markdown = session.exportMarkdown()
        XCTAssertTrue(markdown.contains("Assistant (Research Bot)"))
    }

    func test_exportMarkdown_untitledSession() {
        let session = AISession(userId: "user_1")
        let markdown = session.exportMarkdown()
        XCTAssertTrue(markdown.contains("# Untitled Session"))
    }

    // MARK: - Bulk Export

    func test_exportAll() async throws {
        let store = InMemorySessionStore()
        _ = try await store.create(AISession(id: "s1", userId: "user_1", title: "Session 1"))
        _ = try await store.create(AISession(id: "s2", userId: "user_1", title: "Session 2"))
        _ = try await store.create(AISession(id: "s3", userId: "user_2", title: "Other User"))

        let data = try await store.exportAll(userId: "user_1")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode([AISession].self, from: data)

        XCTAssertEqual(exported.count, 2)
        XCTAssertTrue(exported.allSatisfy { $0.userId == "user_1" })
    }
}

// MARK: - AgentHandoff Tests

final class AgentHandoffTests: XCTestCase {

    func test_handoff_initialization() {
        let handoff = AgentHandoff(
            targetAgentId: "agent-2",
            mode: .forked,
            message: "Take over",
            metadata: ["reason": "specialization"]
        )

        XCTAssertEqual(handoff.targetAgentId, "agent-2")
        XCTAssertEqual(handoff.mode, .forked)
        XCTAssertEqual(handoff.message, "Take over")
        XCTAssertEqual(handoff.metadata?["reason"], "specialization")
    }

    func test_handoff_codable() throws {
        let handoff = AgentHandoff(targetAgentId: "agent-2", mode: .shared)
        let data = try JSONEncoder().encode(handoff)
        let decoded = try JSONDecoder().decode(AgentHandoff.self, from: data)

        XCTAssertEqual(decoded.targetAgentId, "agent-2")
        XCTAssertEqual(decoded.mode, .shared)
    }

    func test_subagentOptions_defaults() {
        let opts = SubagentOptions()
        XCTAssertEqual(opts.sessionMode, .forked)
        XCTAssertNil(opts.maxSteps)
        XCTAssertTrue(opts.includeMessagesInParent)
    }

    func test_handoffMode_rawValues() {
        XCTAssertEqual(HandoffMode.shared.rawValue, "shared")
        XCTAssertEqual(HandoffMode.forked.rawValue, "forked")
        XCTAssertEqual(HandoffMode.independent.rawValue, "independent")
    }
}
