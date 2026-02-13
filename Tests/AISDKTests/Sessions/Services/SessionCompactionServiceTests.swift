//
//  SessionCompactionServiceTests.swift
//  AISDKTests
//
//  Tests for SessionCompactionService.
//

import XCTest
@testable import AISDK

final class SessionCompactionServiceTests: XCTestCase {

    // MARK: - Token Estimation

    func test_estimateTokens_emptyMessages() async {
        let service = SessionCompactionService()
        let tokens = await service.estimateTokens([])
        // Just the assistant priming (3)
        XCTAssertEqual(tokens, 3)
    }

    func test_estimateTokens_shortMessage() async {
        let service = SessionCompactionService()
        let tokens = await service.estimateTokens([.user("Hello")])
        // 4 (overhead) + ceil(5/4)*1.15 = 4 + ceil(1.25)*1.15 ≈ 4 + 2 + 3 = ~6-7
        XCTAssertGreaterThan(tokens, 5)
        XCTAssertLessThan(tokens, 20)
    }

    func test_estimateTokens_longMessage() async {
        let service = SessionCompactionService()
        // ~400 character message
        let longText = String(repeating: "Hello world! ", count: 30)
        let tokens = await service.estimateTokens([.user(longText)])
        // Approximately 400/4 * 1.15 + overhead ≈ 115 + 7
        XCTAssertGreaterThan(tokens, 80)
        XCTAssertLessThan(tokens, 200)
    }

    func test_estimateTokens_withToolCalls() async {
        let service = SessionCompactionService()
        let msg = AIMessage(
            role: .assistant,
            content: .text("Using tool"),
            toolCalls: [AIMessage.ToolCall(id: "1", name: "search", arguments: "{\"query\": \"test\"}")]
        )
        let tokens = await service.estimateTokens([msg])
        // Should include tool call overhead
        XCTAssertGreaterThan(tokens, 15)
    }

    // MARK: - Needs Compaction

    func test_needsCompaction_underThreshold_returnsFalse() async {
        let service = SessionCompactionService()
        let policy = ContextPolicy(maxTokens: 10000)
        let result = await service.needsCompaction([.user("Hello")], policy: policy)
        XCTAssertFalse(result)
    }

    func test_needsCompaction_overThreshold_returnsTrue() async {
        let service = SessionCompactionService()
        let policy = ContextPolicy(maxTokens: 10, compactionThreshold: 0.5)
        // Even a short message will exceed 5 tokens
        let result = await service.needsCompaction([.user("Hello world")], policy: policy)
        XCTAssertTrue(result)
    }

    func test_needsCompaction_unlimitedPolicy_returnsFalse() async {
        let service = SessionCompactionService()
        let policy = ContextPolicy.unlimited
        let messages = (0..<100).map { AIMessage.user("Message \($0)") }
        let result = await service.needsCompaction(messages, policy: policy)
        XCTAssertFalse(result)
    }

    // MARK: - Truncation Strategy

    func test_truncate_preservesSystemPrompt() async throws {
        let service = SessionCompactionService()
        let policy = ContextPolicy(
            maxTokens: 100,
            compactionStrategy: .truncate,
            preserveSystemPrompt: true,
            minMessagesToKeep: 2
        )

        let messages: [AIMessage] = [
            .system("You are helpful"),
            .user("Message 1"),
            .assistant("Response 1"),
            .user("Message 2"),
            .assistant("Response 2"),
            .user("Message 3"),
            .assistant("Response 3")
        ]

        let compacted = try await service.compact(messages, policy: policy)

        // Should keep system prompt + last 2 messages
        XCTAssertEqual(compacted.first?.role, .system)
        XCTAssertEqual(compacted.first?.textContent, "You are helpful")
        XCTAssertEqual(compacted.count, 3) // system + 2 recent
    }

    func test_truncate_keepsMinMessages() async throws {
        let service = SessionCompactionService()
        let policy = ContextPolicy(
            maxTokens: 100,
            compactionStrategy: .truncate,
            preserveSystemPrompt: false,
            minMessagesToKeep: 4
        )

        let messages: [AIMessage] = [
            .user("Message 1"),
            .assistant("Response 1"),
            .user("Message 2"),
            .assistant("Response 2"),
            .user("Message 3"),
            .assistant("Response 3")
        ]

        let compacted = try await service.compact(messages, policy: policy)
        XCTAssertEqual(compacted.count, 4)
        // Should be the last 4 messages (starting at index 2 of original)
        XCTAssertEqual(compacted[0].textContent, "Message 2")
    }

    func test_truncate_shortConversation_unchanged() async throws {
        let service = SessionCompactionService()
        let policy = ContextPolicy(
            maxTokens: 100,
            compactionStrategy: .truncate,
            minMessagesToKeep: 10
        )

        let messages: [AIMessage] = [
            .user("Hello"),
            .assistant("Hi")
        ]

        let compacted = try await service.compact(messages, policy: policy)
        XCTAssertEqual(compacted.count, 2)
    }

    // MARK: - Summarization Strategy

    func test_summarize_callsLLM() async throws {
        let mockLLM = MockLLM.withResponse("Summary of conversation")
        let service = SessionCompactionService(llm: mockLLM)
        let policy = ContextPolicy(
            maxTokens: 100,
            compactionStrategy: .summarize,
            preserveSystemPrompt: true,
            minMessagesToKeep: 2
        )

        let messages: [AIMessage] = [
            .system("You are helpful"),
            .user("Message 1"),
            .assistant("Response 1"),
            .user("Message 2"),
            .assistant("Response 2"),
            .user("Recent"),
            .assistant("Recent response")
        ]

        let compacted = try await service.compact(messages, policy: policy)

        // Should have: system + summary system message + 2 recent messages
        XCTAssertEqual(compacted[0].role, .system)
        XCTAssertEqual(compacted[0].textContent, "You are helpful")
        XCTAssertEqual(compacted[1].role, .system)
        XCTAssertTrue(compacted[1].textContent?.contains("Summary of conversation") ?? false)
    }

    func test_summarize_withoutLLM_fallsBackToTruncate() async throws {
        let service = SessionCompactionService(llm: nil)
        let policy = ContextPolicy(
            maxTokens: 100,
            compactionStrategy: .summarize,
            minMessagesToKeep: 2
        )

        let messages: [AIMessage] = [
            .user("Message 1"),
            .assistant("Response 1"),
            .user("Message 2"),
            .assistant("Response 2")
        ]

        let compacted = try await service.compact(messages, policy: policy)
        // Falls back to truncation — should keep last 2
        XCTAssertEqual(compacted.count, 2)
    }

    // MARK: - Sliding Window Strategy

    func test_slidingWindow_keepsHeadAndTail() async throws {
        let service = SessionCompactionService()
        let policy = ContextPolicy(
            maxTokens: 100,
            compactionStrategy: .slidingWindow,
            preserveSystemPrompt: true,
            minMessagesToKeep: 2
        )

        let messages: [AIMessage] = [
            .system("System prompt"),
            .user("First question"),
            .assistant("First answer"),
            .user("Middle question 1"),
            .assistant("Middle answer 1"),
            .user("Middle question 2"),
            .assistant("Middle answer 2"),
            .user("Recent question"),
            .assistant("Recent answer")
        ]

        let compacted = try await service.compact(messages, policy: policy)

        // Should include system + first exchange + recent messages
        XCTAssertEqual(compacted.first?.role, .system)
        XCTAssertTrue(compacted.count >= 4) // system + some head + some tail
        XCTAssertTrue(compacted.count < messages.count) // Actually compacted
    }
}

// MARK: - Title Generator Tests

final class DefaultTitleGeneratorTests: XCTestCase {

    func test_generateTitle_returnsTitle() async throws {
        let mockLLM = MockLLM.withResponse("Weather Discussion Today")
        let generator = DefaultTitleGenerator(llm: mockLLM)

        let title = try await generator.generateTitle(from: [
            .user("What's the weather like?"),
            .assistant("It's sunny and 72 degrees.")
        ])

        XCTAssertEqual(title, "Weather Discussion Today")
    }

    func test_generateTitle_emptyMessages_returnsFallback() async throws {
        let mockLLM = MockLLM.withResponse("Some title")
        let generator = DefaultTitleGenerator(llm: mockLLM)

        let title = try await generator.generateTitle(from: [])
        XCTAssertEqual(title, "New Conversation")
    }

    func test_generateTitle_onlySystemMessages_returnsFallback() async throws {
        let mockLLM = MockLLM.withResponse("Some title")
        let generator = DefaultTitleGenerator(llm: mockLLM)

        let title = try await generator.generateTitle(from: [.system("You are helpful")])
        XCTAssertEqual(title, "New Conversation")
    }

    func test_generateTitle_error_returnsFallback() async throws {
        let mockLLM = MockLLM.failing(with: AISDKError.custom("test error"))
        let generator = DefaultTitleGenerator(llm: mockLLM)

        let title = try await generator.generateTitle(from: [
            .user("Hello"),
            .assistant("Hi there")
        ])
        XCTAssertEqual(title, "New Conversation")
    }

    func test_generateTitle_customFallback() async throws {
        let mockLLM = MockLLM.failing(with: AISDKError.custom("fail"))
        let generator = DefaultTitleGenerator(
            llm: mockLLM,
            fallbackTitle: "Untitled Chat"
        )

        let title = try await generator.generateTitle(from: [.user("Hello")])
        XCTAssertEqual(title, "Untitled Chat")
    }

    func test_generateTitle_trimsQuotes() async throws {
        let mockLLM = MockLLM.withResponse("\"Quoted Title\"")
        let generator = DefaultTitleGenerator(llm: mockLLM)

        let title = try await generator.generateTitle(from: [.user("Hello")])
        XCTAssertEqual(title, "Quoted Title")
    }

    func test_generateTitle_limitsContextMessages() async throws {
        let mockLLM = MockLLM.withResponse("Test Title")
        let generator = DefaultTitleGenerator(llm: mockLLM, maxContextMessages: 2)

        let messages: [AIMessage] = (0..<10).map { .user("Message \($0)") }
        let title = try await generator.generateTitle(from: messages)

        XCTAssertEqual(title, "Test Title")
        // Mock should have been called once
        XCTAssertEqual(mockLLM.requestCount, 1)
    }
}
