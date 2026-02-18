//
//  AgentAutoCompactionTests.swift
//  AISDKTests
//
//  Tests verifying automatic context compaction in the agent loop.
//

import XCTest
@testable import AISDK

// MARK: - Auto-Compaction Tests

final class AgentAutoCompactionTests: XCTestCase {

    // MARK: - SessionCompactionService Usage-Aware Tests

    func testNeedsCompaction_usesProviderTokensWhenAvailable() async {
        let service = SessionCompactionService()
        let policy = ContextPolicy(maxTokens: 1000, compactionThreshold: 0.9)

        // Provider says 950 prompt tokens (over 90% of 1000)
        let usage = AIUsage(promptTokens: 950, completionTokens: 50)
        let messages = [AIMessage.user("short")]

        let result = await service.needsCompaction(messages, usage: usage, policy: policy)
        XCTAssertTrue(result, "Should trigger compaction based on provider-reported tokens")
    }

    func testNeedsCompaction_fallsBackToHeuristicWhenNoUsage() async {
        let service = SessionCompactionService()
        let policy = ContextPolicy(maxTokens: 100, compactionThreshold: 0.5)

        // Create messages that exceed the heuristic threshold
        let longText = String(repeating: "word ", count: 200)
        let messages = [AIMessage.user(longText)]

        let result = await service.needsCompaction(messages, usage: nil, policy: policy)
        XCTAssertTrue(result, "Should use heuristic estimation when usage is nil")
    }

    func testNeedsCompaction_returnsFalseWhenUnderThreshold() async {
        let service = SessionCompactionService()
        let policy = ContextPolicy(maxTokens: 100000, compactionThreshold: 0.9)

        let usage = AIUsage(promptTokens: 100, completionTokens: 50)
        let messages = [AIMessage.user("short")]

        let result = await service.needsCompaction(messages, usage: usage, policy: policy)
        XCTAssertFalse(result, "Should not trigger compaction when well under threshold")
    }

    func testNeedsCompaction_returnsFalseWhenNoMaxTokens() async {
        let service = SessionCompactionService()
        let policy = ContextPolicy(maxTokens: nil) // unlimited

        let usage = AIUsage(promptTokens: 999999, completionTokens: 50)
        let messages = [AIMessage.user("anything")]

        let result = await service.needsCompaction(messages, usage: usage, policy: policy)
        XCTAssertFalse(result, "Should not compact when maxTokens is nil (unlimited)")
    }

    // MARK: - Compaction Strategy Tests

    func testCompact_truncatePreservesSystemPrompt() async throws {
        let service = SessionCompactionService()
        let policy = ContextPolicy(
            maxTokens: 100,
            compactionStrategy: .truncate,
            preserveSystemPrompt: true,
            minMessagesToKeep: 2
        )

        let messages: [AIMessage] = [
            .system("You are a doctor assistant."),
            .user("Old message 1"),
            .assistant("Old reply 1"),
            .user("Old message 2"),
            .assistant("Old reply 2"),
            .user("Recent question"),
            .assistant("Recent answer")
        ]

        let compacted = try await service.compact(messages, policy: policy)

        // Should keep system prompt + last 2 messages
        XCTAssertEqual(compacted.first?.role, .system, "System prompt should be preserved")
        XCTAssertEqual(compacted.first?.content.textValue, "You are a doctor assistant.")
        XCTAssertTrue(compacted.count <= 3, "Should keep system + minMessagesToKeep")
    }

    func testCompact_slidingWindowKeepsFirstAndLast() async throws {
        let service = SessionCompactionService()
        // Use more messages so sliding window actually trims
        let policy = ContextPolicy(
            maxTokens: 100,
            compactionStrategy: .slidingWindow,
            preserveSystemPrompt: true,
            minMessagesToKeep: 2
        )

        var messages: [AIMessage] = [.system("System prompt")]
        for i in 1...10 {
            messages.append(.user("Question \(i)"))
            messages.append(.assistant("Answer \(i)"))
        }
        // 21 messages total: system + 10 Q&A pairs

        let compacted = try await service.compact(messages, policy: policy)

        // Should keep system + first 2 exchanges + last 2 messages
        XCTAssertEqual(compacted.first?.role, .system)
        XCTAssertTrue(compacted.count < messages.count, "Should have fewer messages after compaction")
        XCTAssertEqual(compacted.last?.content.textValue, "Answer 10", "Should keep most recent messages")
    }

    // MARK: - Agent Integration Tests

    func testAgent_initWithContextPolicy() async {
        let mock = MockLLM.withResponse("Hello")
        let policy = ContextPolicy.conservative(maxTokens: 128000)

        let agent = Agent(
            model: mock,
            contextPolicy: policy
        )

        XCTAssertNotNil(agent, "Agent should accept contextPolicy parameter")
    }

    func testAgent_initWithoutContextPolicy() async {
        let mock = MockLLM.withResponse("Hello")

        let agent = Agent(model: mock)

        // Should work without context policy (no compaction)
        XCTAssertNotNil(agent, "Agent should work without contextPolicy")
    }

    func testAgent_executesWithContextPolicy() async throws {
        let mock = MockLLM.withResponse("Response text")
        let policy = ContextPolicy(
            maxTokens: 100000,
            compactionThreshold: 0.9,
            compactionStrategy: .truncate
        )

        let agent = Agent(
            model: mock,
            contextPolicy: policy
        )

        let result = try await agent.execute(messages: [.user("Hello")])
        XCTAssertEqual(result.text, "Response text")
    }
}
