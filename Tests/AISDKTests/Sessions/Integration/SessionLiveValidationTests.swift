//
//  SessionLiveValidationTests.swift
//  AISDKTests
//
//  Live validation tests for the Agent Sessions & Storage implementation.
//  Tests cover 5 layers: smoke, streaming, compaction, multi-store, concurrency.
//
//  Run with: set -a && source .env && set +a && RUN_LIVE_TESTS=1 swift test --filter SessionLiveValidationTests
//

import Foundation
import XCTest
@testable import AISDK

// MARK: - SessionLiveValidationTests

final class SessionLiveValidationTests: XCTestCase {

    // MARK: - Helpers

    private func liveTestGuard() throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Live tests disabled (set RUN_LIVE_TESTS=1)")
        }
    }

    private func loadEnvironmentVariables() {
        let envPath = ".env"
        guard let envContent = try? String(contentsOfFile: envPath) else {
            return
        }

        for line in envContent.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if !trimmedLine.isEmpty && !trimmedLine.hasPrefix("#") {
                let parts = trimmedLine.components(separatedBy: "=")
                if parts.count >= 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
                    setenv(key, value, 0)
                }
            }
        }
    }

    private func openAIKeyOrSkip() throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY required")
        }
        return apiKey
    }

    /// Create an LLM conforming to the `LLM` protocol using OpenAI.
    /// Uses gpt-4o-mini for cost efficiency.
    private func createOpenAILLM(apiKey: String) -> any LLM {
        let client = OpenAIClientAdapter(apiKey: apiKey)
        return ProviderLanguageModelAdapter(client: client, modelId: "gpt-4o-mini")
    }

    // MARK: - Layer 1: Smoke Test

    @MainActor
    func test_layer1_createSession_sendMessage_verifyPersistence() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()

        let store = InMemorySessionStore()
        let llm = createOpenAILLM(apiKey: apiKey)
        let agent = Agent(model: llm)
        let vm = ChatViewModel(agent: agent, store: store)

        // Create session
        try await vm.createSession(userId: "test-user", title: "Smoke Test")
        let sessionId = vm.session.id

        // Send message
        await vm.send("What is 2 + 2? Answer in one word.")

        // Verify in-memory session state
        let msgCount = vm.session.messages.count
        XCTAssertGreaterThanOrEqual(msgCount, 2, "Should have user + assistant messages, got \(msgCount)")
        XCTAssertEqual(vm.session.messages[0].role, .user)
        XCTAssertTrue(vm.session.isLastMessageComplete, "Message should be marked complete")
        XCTAssertFalse(vm.isStreaming, "Should not be streaming after send completes")

        // Verify assistant response has content
        // Note: Agent may produce multiple assistant messages (placeholder + response).
        // We check that at least one assistant message has non-empty text.
        let assistantTexts = vm.session.messages
            .filter { $0.role == .assistant }
            .compactMap { $0.textContent }
        XCTAssertFalse(assistantTexts.isEmpty, "At least one assistant message should have text content")

        // Wait for background persistence
        try await Task.sleep(for: .seconds(2))

        // Verify store has the session
        let loaded = try await store.load(id: sessionId)
        XCTAssertNotNil(loaded, "Session should be persisted in store")
    }

    @MainActor
    func test_layer1_sessionResume_afterReload() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()

        let store = InMemorySessionStore()
        let llm = createOpenAILLM(apiKey: apiKey)
        let agent = Agent(model: llm)

        // First ViewModel: send a message
        let vm1 = ChatViewModel(agent: agent, store: store)
        try await vm1.createSession(userId: "test-user")
        let sessionId = vm1.session.id
        await vm1.send("My name is TestBot")

        // Wait for background persistence to complete
        try await Task.sleep(for: .seconds(2))

        // Second ViewModel: reload and verify messages are present
        let vm2 = ChatViewModel(agent: agent, store: store)
        try await vm2.loadSession(id: sessionId)

        XCTAssertEqual(vm2.session.id, sessionId)
        XCTAssertGreaterThanOrEqual(vm2.session.messages.count, 2, "Reloaded session should have messages")
        XCTAssertEqual(vm2.session.messages[0].role, .user)
    }

    // MARK: - Layer 2: Streaming + Persistence

    @MainActor
    func test_layer2_streamingResponse_persistsCorrectly() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()

        let store = InMemorySessionStore()
        let llm = createOpenAILLM(apiKey: apiKey)
        let agent = Agent(model: llm)
        let vm = ChatViewModel(agent: agent, store: store)
        try await vm.createSession(userId: "test-user")

        // Send and wait for completion
        await vm.send("Count from 1 to 5, each on a new line.")

        // Verify final state
        XCTAssertFalse(vm.isStreaming, "Should not be streaming after completion")
        XCTAssertTrue(vm.session.isLastMessageComplete)
        XCTAssertGreaterThanOrEqual(vm.session.messages.count, 2)

        // Verify the assistant message has accumulated text
        let assistantMsg = vm.session.messages.last(where: { $0.role == .assistant })
        XCTAssertNotNil(assistantMsg, "Should have an assistant message")
        XCTAssertNotNil(assistantMsg?.textContent, "Assistant message should have text")
        XCTAssertFalse(assistantMsg?.textContent?.isEmpty ?? true, "Text should not be empty")
    }

    func test_layer2_directStreamExecute_eventSequence() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()

        let llm = createOpenAILLM(apiKey: apiKey)
        let agent = Agent(model: llm)

        let messages = [AIMessage.user("Say hello")]
        var eventTypes: Set<String> = []

        for try await event in agent.streamExecute(messages: messages) {
            switch event {
            case .start: eventTypes.insert("start")
            case .textDelta: eventTypes.insert("textDelta")
            case .finish: eventTypes.insert("finish")
            default: break
            }
        }

        XCTAssertTrue(eventTypes.contains("start"), "Should have received start event")
        XCTAssertTrue(eventTypes.contains("textDelta"), "Should have received text deltas")
        XCTAssertTrue(eventTypes.contains("finish"), "Should have received finish event")
    }

    // MARK: - Layer 3: Context Compaction + Title Generation

    func test_layer3_compactionSummarize_withRealLLM() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()

        let llm = createOpenAILLM(apiKey: apiKey)
        let compactionService = SessionCompactionService(llm: llm)

        // Build 51 messages (1 system + 25 user/assistant pairs)
        var messages: [AIMessage] = [.system("You are a helpful assistant.")]
        for i in 0..<25 {
            messages.append(.user("Question \(i): Tell me about topic \(i)"))
            messages.append(AIMessage(role: .assistant, content: .text(
                "Response \(i): Here is information about topic \(i). " +
                "It is a fascinating subject with many aspects to consider."
            )))
        }

        XCTAssertEqual(messages.count, 51)

        let policy = ContextPolicy(
            maxTokens: 500,
            compactionStrategy: .summarize,
            preserveSystemPrompt: true,
            minMessagesToKeep: 4
        )

        // Verify compaction is needed
        let needsCompaction = await compactionService.needsCompaction(messages, policy: policy)
        XCTAssertTrue(needsCompaction, "51 messages should exceed 500 token limit")

        // Perform compaction
        let compacted = try await compactionService.compact(messages, policy: policy)

        // Verify results
        XCTAssertLessThan(compacted.count, messages.count, "Compacted should have fewer messages")
        XCTAssertEqual(compacted[0].role, .system, "First message should be system prompt")
        XCTAssertEqual(compacted[0].content.textValue, "You are a helpful assistant.")

        // Second message should be the summary
        XCTAssertEqual(compacted[1].role, .system, "Second message should be the summary")
        XCTAssertTrue(
            compacted[1].content.textValue.hasPrefix("[Previous conversation summary:"),
            "Summary should have the expected prefix"
        )

        // Should have at least system + summary + minMessagesToKeep recent messages
        XCTAssertGreaterThanOrEqual(compacted.count, 6, "Should have system + summary + 4 recent")
    }

    func test_layer3_titleGeneration_withRealLLM() async throws {
        try liveTestGuard()
        loadEnvironmentVariables()
        let apiKey = try openAIKeyOrSkip()

        let llm = createOpenAILLM(apiKey: apiKey)
        let generator = DefaultTitleGenerator(llm: llm)

        let messages: [AIMessage] = [
            .user("I want to learn how to make sourdough bread from scratch"),
            AIMessage(role: .assistant, content: .text(
                "Great choice! Let me walk you through the process of making sourdough bread. " +
                "First, you'll need a starter..."
            ))
        ]

        let title = try await generator.generateTitle(from: messages)

        XCTAssertNotEqual(title, "New Conversation", "Should generate a real title, not fallback")
        XCTAssertFalse(title.isEmpty, "Title should not be empty")
        XCTAssertLessThan(title.count, 100, "Title should be reasonably short")
    }

    // MARK: - Layer 4: Multi-Store Verification

    func test_layer4_multiStore_conversationParity() async throws {
        // No live test guard needed -- this test doesn't use real LLMs
        let memoryStore = InMemorySessionStore()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionLiveTests-\(UUID().uuidString)")
        let fileStore = try FileSystemSessionStore(directory: tempDir)
        let sqliteStore = try SQLiteSessionStore(path: ":memory:")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let stores: [(String, any SessionStore)] = [
            ("InMemory", memoryStore),
            ("FileSystem", fileStore),
            ("SQLite", sqliteStore)
        ]

        for (name, store) in stores {
            // Create session
            let session = AISession(
                id: "multi-store-\(name)",
                userId: "user_1",
                title: "Multi-Store Test",
                messages: [
                    .user("Hello, how are you?"),
                    AIMessage(role: .assistant, content: .text("I'm doing well!")),
                    .user("What is 2 + 2?"),
                    AIMessage(role: .assistant, content: .text("2 + 2 equals 4."))
                ]
            )
            _ = try await store.create(session)

            // Verify load
            let loaded = try await store.load(id: "multi-store-\(name)")
            XCTAssertNotNil(loaded, "\(name): should load session")
            XCTAssertEqual(loaded?.messages.count, 4, "\(name): should have 4 messages")
            XCTAssertEqual(loaded?.title, "Multi-Store Test", "\(name): should preserve title")
            XCTAssertEqual(loaded?.userId, "user_1", "\(name): should preserve userId")

            // Test appendMessage
            try await store.appendMessage(.user("Another message"), toSession: "multi-store-\(name)")
            let afterAppend = try await store.load(id: "multi-store-\(name)")
            XCTAssertEqual(afterAppend?.messages.count, 5, "\(name): should have 5 messages after append")

            // Test updateStatus
            try await store.updateStatus(.completed, forSession: "multi-store-\(name)")
            let afterStatus = try await store.load(id: "multi-store-\(name)")
            XCTAssertEqual(afterStatus?.status, .completed, "\(name): should update status")

            // Test delete
            try await store.delete(id: "multi-store-\(name)")
            let afterDelete = try await store.load(id: "multi-store-\(name)")
            XCTAssertNil(afterDelete, "\(name): should be nil after delete")
        }
    }

    // MARK: - Layer 5: Concurrent Load Testing

    func test_layer5_concurrentSessions_noDataCorruption() async throws {
        let store = InMemorySessionStore()
        let sessionCount = 10

        // Create sessions and append messages concurrently
        try await withThrowingTaskGroup(of: String.self) { group in
            for i in 0..<sessionCount {
                group.addTask {
                    let session = AISession(
                        id: "concurrent-\(i)",
                        userId: "user_1",
                        title: "Session \(i)"
                    )
                    _ = try await store.create(session)
                    for j in 0..<5 {
                        try await store.appendMessage(
                            .user("Message \(j) for session \(i)"),
                            toSession: "concurrent-\(i)"
                        )
                    }
                    return "concurrent-\(i)"
                }
            }

            var completedIds: [String] = []
            for try await id in group {
                completedIds.append(id)
            }
            XCTAssertEqual(completedIds.count, sessionCount)
        }

        // Verify each session has exactly 5 messages
        for i in 0..<sessionCount {
            let session = try await store.load(id: "concurrent-\(i)")
            XCTAssertNotNil(session, "Session concurrent-\(i) should exist")
            XCTAssertEqual(session?.messages.count, 5, "Session concurrent-\(i) should have 5 messages")
        }

        // Verify listing returns all sessions
        let list = try await store.list(
            userId: "user_1",
            status: nil,
            limit: 20,
            cursor: nil,
            orderBy: .lastActivityAtDesc
        )
        XCTAssertEqual(list.sessions.count, sessionCount, "Should list all \(sessionCount) sessions")
    }

    func test_layer5_concurrentStoreOperations_mixedTypes() async throws {
        let stores: [(String, any SessionStore)] = [
            ("InMemory", InMemorySessionStore()),
            ("SQLite", try SQLiteSessionStore(path: ":memory:"))
        ]

        for (name, store) in stores {
            // Create a base session
            _ = try await store.create(AISession(id: "stress-\(name)", userId: "user_1"))

            // Run mixed concurrent operations
            await withTaskGroup(of: Void.self) { group in
                // 20 writers
                for i in 0..<20 {
                    group.addTask {
                        try? await store.appendMessage(
                            .user("Msg \(i)"),
                            toSession: "stress-\(name)"
                        )
                    }
                }
                // 20 readers
                for _ in 0..<20 {
                    group.addTask {
                        _ = try? await store.load(id: "stress-\(name)")
                    }
                }
                // 5 metadata updaters
                for i in 0..<5 {
                    group.addTask {
                        try? await store.updateMetadata(
                            SessionMetadataUpdate(title: "Title \(i)"),
                            forSession: "stress-\(name)"
                        )
                    }
                }
            }

            let final = try await store.load(id: "stress-\(name)")
            XCTAssertNotNil(final, "\(name): session should still exist")
            XCTAssertEqual(
                final?.messages.count, 20,
                "\(name): should have 20 messages after concurrent writes"
            )
        }
    }

    // MARK: - Phase Verification

    func test_phase1_aiMessage_sessionProperties() {
        var msg = AIMessage(role: .assistant, content: .text("Hello"))
        msg.agentId = "agent_1"
        msg.agentName = "Research"
        msg.isCheckpoint = true
        msg.checkpointIndex = 3

        XCTAssertEqual(msg.agentId, "agent_1")
        XCTAssertEqual(msg.agentName, "Research")
        XCTAssertTrue(msg.isCheckpoint)
        XCTAssertEqual(msg.checkpointIndex, 3)
    }

    func test_phase1_aiMessage_mutability() {
        // Test text accumulation
        var msg = AIMessage(role: .assistant, content: .text(""))
        msg.appendText("Hello ")
        msg.appendText("world")
        XCTAssertEqual(msg.textContent, "Hello world")

        // Test toolCalls mutability
        msg.toolCalls = [AIMessage.ToolCall(id: "1", name: "test", arguments: "")]
        XCTAssertNotNil(msg.toolCalls)
        XCTAssertEqual(msg.toolCalls?.count, 1)

        // Test ToolCall.arguments mutability
        msg.toolCalls?[0].arguments = "{\"key\":\"value\"}"
        XCTAssertEqual(msg.toolCalls?[0].arguments, "{\"key\":\"value\"}")
    }

    func test_phase6_agentAttribution_roundtrip() throws {
        var msg = AIMessage(role: .assistant, content: .text("Hello"))
        msg.agentId = "agent_1"
        msg.agentName = "Research Agent"

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(AIMessage.self, from: data)

        XCTAssertEqual(decoded.agentId, "agent_1")
        XCTAssertEqual(decoded.agentName, "Research Agent")
        XCTAssertEqual(decoded.content.textValue, "Hello")
    }
}
