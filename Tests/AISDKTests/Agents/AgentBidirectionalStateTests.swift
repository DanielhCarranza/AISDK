//
//  AgentBidirectionalStateTests.swift
//  AISDKTests
//
//  Integration tests for bidirectional state: UIStateChangeEvent injection into Agent.
//

import XCTest
@testable import AISDK

final class AgentBidirectionalStateTests: XCTestCase {

    // MARK: - Mock Language Model

    private class MockLLM: LLM, @unchecked Sendable {
        let provider = "mock"
        let modelId = "mock-state-model"
        let capabilities: LLMCapabilities = []

        func generateText(request: AITextRequest) async throws -> AITextResult {
            AITextResult(
                text: "Acknowledged",
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .stop
            )
        }

        func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("Acknowledged"))
                continuation.yield(.finish(finishReason: .stop, usage: AIUsage.zero))
                continuation.finish()
            }
        }

        func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    // MARK: - Tests

    func test_inject_state_change_appends_system_message() async throws {
        let model = MockLLM()
        let agent = Agent(model: model, tools: [], instructions: "Test agent")

        let event = UIStateChangeEvent(
            componentName: "temperature_slider",
            path: "/state/temperature",
            value: SpecValue(72.5)
        )

        await agent.injectStateChange(event)

        let messages = await agent.messages
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, .system)

        let content = messages[0].content.textValue
        XCTAssertTrue(content.contains("temperature_slider"), "Should mention component name")
        XCTAssertTrue(content.contains("/state/temperature"), "Should mention path")
        XCTAssertTrue(content.contains("72.5"), "Should mention new value")
    }

    func test_inject_state_change_with_previous_value() async throws {
        let model = MockLLM()
        let agent = Agent(model: model, tools: [], instructions: "Test agent")

        let event = UIStateChangeEvent(
            componentName: "theme_toggle",
            path: "/state/darkMode",
            value: SpecValue(true),
            previousValue: SpecValue(false)
        )

        await agent.injectStateChange(event)

        let messages = await agent.messages
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, .system)
        XCTAssertTrue(messages[0].content.textValue.contains("theme_toggle"))
    }

    func test_multiple_state_changes_accumulate() async throws {
        let model = MockLLM()
        let agent = Agent(model: model, tools: [], instructions: "Test agent")

        let events = [
            UIStateChangeEvent(componentName: "slider_a", path: "/state/a", value: SpecValue(10)),
            UIStateChangeEvent(componentName: "slider_b", path: "/state/b", value: SpecValue(20)),
            UIStateChangeEvent(componentName: "toggle_c", path: "/state/c", value: SpecValue(true)),
        ]

        for event in events {
            await agent.injectStateChange(event)
        }

        let messages = await agent.messages
        XCTAssertEqual(messages.count, 3, "Each state change should add a system message")

        let systemMessages = messages.filter { $0.role == .system }
        XCTAssertEqual(systemMessages.count, 3)

        XCTAssertTrue(systemMessages[0].content.textValue.contains("slider_a"))
        XCTAssertTrue(systemMessages[1].content.textValue.contains("slider_b"))
        XCTAssertTrue(systemMessages[2].content.textValue.contains("toggle_c"))
    }

    func test_state_change_persists_alongside_user_messages() async throws {
        let model = MockLLM()
        let agent = Agent(model: model, tools: [], instructions: "Test agent")

        // Simulate a conversation with state changes interspersed
        await agent.setMessages([.user("Hello")])

        let event = UIStateChangeEvent(
            componentName: "volume",
            path: "/state/volume",
            value: SpecValue(0.8)
        )
        await agent.injectStateChange(event)

        let messages = await agent.messages
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[1].role, .system)
        XCTAssertTrue(messages[1].content.textValue.contains("volume"))
    }
}
