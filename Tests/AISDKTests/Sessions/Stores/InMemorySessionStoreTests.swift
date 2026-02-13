//
//  InMemorySessionStoreTests.swift
//  AISDKTests
//
//  Tests for InMemorySessionStore using the shared conformance suite.
//

import XCTest
@testable import AISDK

final class InMemorySessionStoreTests: XCTestCase {

    private var store: InMemorySessionStore!

    override func setUp() {
        super.setUp()
        store = InMemorySessionStore()
    }

    // MARK: - CRUD

    func test_create_andLoad() async throws {
        let session = AISession(userId: "user_1", title: "Test")
        let created = try await store.create(session)
        XCTAssertEqual(created.id, session.id)

        let loaded = try await store.load(id: session.id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.title, "Test")
        XCTAssertEqual(loaded?.userId, "user_1")
    }

    func test_create_duplicate_throws() async throws {
        let session = AISession(id: "dup", userId: "user_1")
        _ = try await store.create(session)

        do {
            _ = try await store.create(AISession(id: "dup", userId: "user_2"))
            XCTFail("Expected alreadyExists error")
        } catch let error as SessionStoreError {
            if case .alreadyExists(let id) = error {
                XCTAssertEqual(id, "dup")
            } else {
                XCTFail("Expected alreadyExists, got \(error)")
            }
        }
    }

    func test_load_nonexistent_returnsNil() async throws {
        let loaded = try await store.load(id: "nonexistent")
        XCTAssertNil(loaded)
    }

    func test_save_updatesSession() async throws {
        var session = AISession(userId: "user_1")
        _ = try await store.create(session)

        session.title = "Updated"
        session.messages.append(.user("Hello"))
        try await store.save(session)

        let loaded = try await store.load(id: session.id)
        XCTAssertEqual(loaded?.title, "Updated")
        XCTAssertEqual(loaded?.messages.count, 1)
    }

    func test_delete_removesSession() async throws {
        let session = AISession(userId: "user_1")
        _ = try await store.create(session)

        try await store.delete(id: session.id)
        let loaded = try await store.load(id: session.id)
        XCTAssertNil(loaded)
    }

    func test_delete_nonexistent_throws() async {
        do {
            try await store.delete(id: "nonexistent")
            XCTFail("Expected notFound error")
        } catch let error as SessionStoreError {
            if case .notFound = error { /* expected */ }
            else { XCTFail("Expected notFound, got \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - List

    func test_list_filtersByUserId() async throws {
        _ = try await store.create(AISession(id: "s1", userId: "user_1"))
        _ = try await store.create(AISession(id: "s2", userId: "user_1"))
        _ = try await store.create(AISession(id: "s3", userId: "user_2"))

        let result = try await store.list(
            userId: "user_1", status: nil, limit: 10, cursor: nil, orderBy: .createdAtDesc
        )
        XCTAssertEqual(result.sessions.count, 2)
        XCTAssertEqual(result.totalCount, 2)
    }

    func test_list_filtersByStatus() async throws {
        var s1 = AISession(id: "s1", userId: "user_1")
        var s2 = AISession(id: "s2", userId: "user_1")
        s1.status = .active
        s2.status = .completed
        _ = try await store.create(s1)
        _ = try await store.create(s2)

        let result = try await store.list(
            userId: "user_1", status: .active, limit: 10, cursor: nil, orderBy: .createdAtDesc
        )
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions[0].status, .active)
    }

    func test_list_pagination() async throws {
        for i in 0..<5 {
            _ = try await store.create(AISession(id: "s\(i)", userId: "user_1"))
        }

        let page1 = try await store.list(
            userId: "user_1", status: nil, limit: 2, cursor: nil, orderBy: .createdAtAsc
        )
        XCTAssertEqual(page1.sessions.count, 2)
        XCTAssertNotNil(page1.nextCursor)

        let page2 = try await store.list(
            userId: "user_1", status: nil, limit: 2, cursor: page1.nextCursor, orderBy: .createdAtAsc
        )
        XCTAssertEqual(page2.sessions.count, 2)

        let page3 = try await store.list(
            userId: "user_1", status: nil, limit: 2, cursor: page2.nextCursor, orderBy: .createdAtAsc
        )
        XCTAssertEqual(page3.sessions.count, 1)
        XCTAssertNil(page3.nextCursor)
    }

    // MARK: - Incremental Updates

    func test_appendMessage() async throws {
        let session = AISession(userId: "user_1")
        _ = try await store.create(session)

        try await store.appendMessage(.user("Hello"), toSession: session.id)

        let loaded = try await store.load(id: session.id)
        XCTAssertEqual(loaded?.messages.count, 1)
        XCTAssertEqual(loaded?.messages[0].textContent, "Hello")
    }

    func test_appendMessage_nonexistent_throws() async {
        do {
            try await store.appendMessage(.user("Hi"), toSession: "nonexistent")
            XCTFail("Expected notFound")
        } catch let error as SessionStoreError {
            if case .notFound = error { /* expected */ }
            else { XCTFail("Expected notFound") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_updateLastMessage() async throws {
        var session = AISession(userId: "user_1", messages: [.assistant("")])
        _ = try await store.create(session)

        let updated = AIMessage.assistant("Hello world")
        try await store.updateLastMessage(updated, inSession: session.id)

        let loaded = try await store.load(id: session.id)
        XCTAssertEqual(loaded?.messages[0].textContent, "Hello world")
    }

    func test_updateStatus() async throws {
        let session = AISession(userId: "user_1")
        _ = try await store.create(session)

        try await store.updateStatus(.completed, forSession: session.id)

        let loaded = try await store.load(id: session.id)
        XCTAssertEqual(loaded?.status, .completed)
    }

    func test_updateMetadata() async throws {
        let session = AISession(userId: "user_1")
        _ = try await store.create(session)

        try await store.updateMetadata(
            SessionMetadataUpdate(title: "New Title", tags: ["tag1"]),
            forSession: session.id
        )

        let loaded = try await store.load(id: session.id)
        XCTAssertEqual(loaded?.title, "New Title")
        XCTAssertEqual(loaded?.tags, ["tag1"])
    }

    // MARK: - Concurrent Access

    func test_concurrentWrites_areSafe() async throws {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask { [store] in
                    let session = AISession(id: "session_\(i)", userId: "user_1")
                    _ = try? await store!.create(session)
                }
            }
        }

        let result = try await store.list(
            userId: "user_1", status: nil, limit: 200, cursor: nil, orderBy: .createdAtAsc
        )
        XCTAssertEqual(result.sessions.count, 100)
    }

    func test_concurrentReadsAndWrites_areSafe() async throws {
        let session = AISession(id: "shared", userId: "user_1")
        _ = try await store.create(session)

        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<50 {
                group.addTask { [store] in
                    try? await store!.appendMessage(.user("msg_\(i)"), toSession: "shared")
                }
            }
            // Readers
            for _ in 0..<50 {
                group.addTask { [store] in
                    _ = try? await store!.load(id: "shared")
                }
            }
        }

        let loaded = try await store.load(id: "shared")
        XCTAssertEqual(loaded?.messages.count, 50)
    }
}
