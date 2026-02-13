//
//  FileSystemSessionStoreTests.swift
//  AISDKTests
//
//  Tests for FileSystemSessionStore.
//

import XCTest
@testable import AISDK

final class FileSystemSessionStoreTests: XCTestCase {

    private var store: FileSystemSessionStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileSystemSessionStoreTests-\(UUID().uuidString)")
        store = try FileSystemSessionStore(directory: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Directory Management

    func test_init_createsDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FSStoreTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try FileSystemSessionStore(directory: dir)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
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

    func test_create_writesJSONFile() async throws {
        let session = AISession(id: "test-file", userId: "user_1")
        _ = try await store.create(session)

        let fileURL = tempDir.appendingPathComponent("test-file.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let data = try Data(contentsOf: fileURL)
        XCTAssertGreaterThan(data.count, 0)

        // Should be valid JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["id"] as? String, "test-file")
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

    func test_load_corruptedFile_returnsNil() async throws {
        // Write garbage to a session file
        let fileURL = tempDir.appendingPathComponent("corrupted.json")
        try "not valid json {{{".data(using: .utf8)!.write(to: fileURL)

        let loaded = try await store.load(id: "corrupted")
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

        // File should be removed
        let fileURL = tempDir.appendingPathComponent("\(session.id).json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
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
        let session = AISession(userId: "user_1", messages: [.assistant("")])
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

    // MARK: - Atomic Write Safety

    func test_atomicWrite_preservesData() async throws {
        // Create a session, save it, then verify the file is consistent
        var session = AISession(userId: "user_1")
        _ = try await store.create(session)

        // Rapidly update the session multiple times
        for i in 0..<10 {
            session.title = "Update \(i)"
            try await store.save(session)
        }

        let loaded = try await store.load(id: session.id)
        XCTAssertEqual(loaded?.title, "Update 9")
    }
}
