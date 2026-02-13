//
//  ComputerUseAgentTests.swift
//  AISDKTests
//
//  Tests for Agent computer use handler integration using mock providers.
//  No real API keys needed — validates handler routing, event emission, and error handling.
//

import XCTest
@testable import AISDK

final class ComputerUseAgentTests: XCTestCase {

    // MARK: - Mock Language Model

    private class MockLanguageModel: LLM, @unchecked Sendable {
        let provider = "mock"
        let modelId = "mock-model"
        let capabilities: LLMCapabilities = []

        var generateTextHandler: ((AITextRequest) async throws -> AITextResult)?
        var streamTextHandler: ((AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error>)?
        var generateTextCallCount = 0
        let lock = NSLock()

        func generateText(request: AITextRequest) async throws -> AITextResult {
            lock.lock()
            generateTextCallCount += 1
            lock.unlock()

            if let handler = generateTextHandler {
                return try await handler(request)
            }

            return AITextResult(
                text: "Mock response",
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .stop
            )
        }

        func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
            if let handler = streamTextHandler {
                return handler(request)
            }
            return AsyncThrowingStream { continuation in
                continuation.yield(.textDelta("Mock"))
                continuation.yield(.finish(finishReason: .stop, usage: AIUsage.zero))
                continuation.finish()
            }
        }

        func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    // MARK: - Payload Helpers

    private func makeOpenAIPayloadJSON(
        actionType: String,
        x: Int? = nil,
        y: Int? = nil,
        button: String? = nil,
        text: String? = nil,
        callId: String = "cu_call_1",
        safetyChecks: [[String: String]]? = nil
    ) -> String {
        let payload = ComputerUseOpenAIPayload(
            actionType: actionType,
            x: x, y: y,
            button: button,
            text: text,
            keys: nil,
            scrollX: nil, scrollY: nil,
            path: nil,
            ms: nil,
            safetyChecks: safetyChecks,
            callId: callId,
            responseItemId: nil
        )
        let data = try! JSONEncoder().encode(payload)
        return String(data: data, encoding: .utf8)!
    }

    private func makeAnthropicArgsJSON(action: String, coordinate: [Int]? = nil, text: String? = nil) -> String {
        var dict: [String: Any] = ["action": action]
        if let coordinate = coordinate {
            dict["coordinate"] = coordinate
        }
        if let text = text {
            dict["text"] = text
        }
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - Non-Streaming: Handler Called

    func test_computerUseHandler_calledOnScreenshot() async throws {
        let model = MockLanguageModel()
        var handlerCallCount = 0
        var receivedAction: ComputerUseAction?

        model.generateTextHandler = { request in
            model.lock.lock()
            let count = model.generateTextCallCount
            model.lock.unlock()

            if count == 1 {
                let args = self.makeOpenAIPayloadJSON(actionType: "screenshot")
                return AITextResult(
                    text: "",
                    toolCalls: [ToolCallResult(id: "tc_1", name: "__computer_use__", arguments: args)],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "I took a screenshot.",
                    usage: AIUsage(promptTokens: 20, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            builtInTools: [.computerUseDefault],
            stopCondition: .stepCount(5)
        )

        await agent.setComputerUseHandler { cuCall in
            handlerCallCount += 1
            receivedAction = cuCall.action
            return .screenshot("fakeBase64Data")
        }

        let result = try await agent.execute(messages: [.user("Take a screenshot")])

        XCTAssertEqual(handlerCallCount, 1, "Handler should be called exactly once")
        XCTAssertEqual(receivedAction, .screenshot, "Handler should receive screenshot action")
        XCTAssertEqual(result.steps.count, 2, "Should have 2 steps: tool call + final response")
        XCTAssertEqual(result.text, "I took a screenshot.")
    }

    func test_computerUseHandler_receivesClickAction() async throws {
        let model = MockLanguageModel()
        var receivedAction: ComputerUseAction?
        var receivedCallId: String?

        model.generateTextHandler = { request in
            model.lock.lock()
            let count = model.generateTextCallCount
            model.lock.unlock()

            if count == 1 {
                let args = self.makeOpenAIPayloadJSON(actionType: "click", x: 150, y: 250, button: "left", callId: "cu_click_42")
                return AITextResult(
                    text: "",
                    toolCalls: [ToolCallResult(id: "tc_1", name: "__computer_use__", arguments: args)],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "Clicked.",
                    usage: AIUsage(promptTokens: 20, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            builtInTools: [.computerUseDefault],
            stopCondition: .stepCount(5)
        )

        await agent.setComputerUseHandler { cuCall in
            receivedAction = cuCall.action
            receivedCallId = cuCall.callId
            return .screenshot("fakeBase64Data")
        }

        _ = try await agent.execute(messages: [.user("Click at 150, 250")])

        XCTAssertEqual(receivedAction, .click(x: 150, y: 250, button: .left))
        XCTAssertEqual(receivedCallId, "cu_click_42")
    }

    // MARK: - Non-Streaming: Error Handling

    func test_computerUseHandler_nil_returnsError() async throws {
        let model = MockLanguageModel()

        model.generateTextHandler = { request in
            model.lock.lock()
            let count = model.generateTextCallCount
            model.lock.unlock()

            if count == 1 {
                let args = self.makeOpenAIPayloadJSON(actionType: "screenshot")
                return AITextResult(
                    text: "",
                    toolCalls: [ToolCallResult(id: "tc_1", name: "__computer_use__", arguments: args)],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "No handler was available.",
                    usage: AIUsage(promptTokens: 20, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            builtInTools: [.computerUseDefault],
            stopCondition: .stepCount(5)
        )
        // Intentionally do NOT set computerUseHandler

        let result = try await agent.execute(messages: [.user("Take a screenshot")])

        XCTAssertEqual(result.steps.count, 2)
        let messages = await agent.messages
        let toolMessages = messages.filter { $0.role == .tool }
        XCTAssertFalse(toolMessages.isEmpty, "Should have tool result messages")

        let toolContent = toolMessages.first?.content.textValue ?? ""
        XCTAssertTrue(
            toolContent.contains("computerUseHandler") || toolContent.contains("computer use"),
            "Tool result should mention missing handler: \(toolContent)"
        )
    }

    func test_computerUseHandler_throwsError_captured() async throws {
        let model = MockLanguageModel()

        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "Screenshot capture failed" }
        }

        model.generateTextHandler = { request in
            model.lock.lock()
            let count = model.generateTextCallCount
            model.lock.unlock()

            if count == 1 {
                let args = self.makeOpenAIPayloadJSON(actionType: "screenshot")
                return AITextResult(
                    text: "",
                    toolCalls: [ToolCallResult(id: "tc_1", name: "__computer_use__", arguments: args)],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "Handled the error.",
                    usage: AIUsage(promptTokens: 20, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            builtInTools: [.computerUseDefault],
            stopCondition: .stepCount(5)
        )

        await agent.setComputerUseHandler { _ in
            throw TestError()
        }

        let result = try await agent.execute(messages: [.user("Take a screenshot")])

        XCTAssertEqual(result.steps.count, 2)
        let messages = await agent.messages
        let toolMessages = messages.filter { $0.role == .tool }
        let toolContent = toolMessages.first?.content.textValue ?? ""
        XCTAssertTrue(
            toolContent.contains("Error") || toolContent.contains("failed"),
            "Tool result should contain error: \(toolContent)"
        )
    }

    // MARK: - Non-Streaming: Result Encoding

    func test_computerUseResult_encodedAsPayload() async throws {
        let model = MockLanguageModel()

        model.generateTextHandler = { request in
            model.lock.lock()
            let count = model.generateTextCallCount
            model.lock.unlock()

            if count == 1 {
                let args = self.makeOpenAIPayloadJSON(actionType: "screenshot")
                return AITextResult(
                    text: "",
                    toolCalls: [ToolCallResult(id: "tc_1", name: "__computer_use__", arguments: args)],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "Done.",
                    usage: AIUsage(promptTokens: 20, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            builtInTools: [.computerUseDefault],
            stopCondition: .stepCount(5)
        )

        await agent.setComputerUseHandler { _ in
            return .screenshot("abc123", mediaType: .png)
        }

        _ = try await agent.execute(messages: [.user("Screenshot")])

        let messages = await agent.messages
        let toolMessages = messages.filter { $0.role == .tool }
        let toolContent = toolMessages.first?.content.textValue ?? ""

        XCTAssertTrue(toolContent.contains("__computer_use_result__"), "Result should contain payload marker")

        if let data = toolContent.data(using: .utf8),
           let payload = try? JSONDecoder().decode(ComputerUseResultPayload.self, from: data) {
            XCTAssertEqual(payload.screenshot, "abc123")
            XCTAssertEqual(payload.mediaType, "image/png")
            XCTAssertFalse(payload.isError)
        } else {
            XCTFail("Could not decode ComputerUseResultPayload from tool message")
        }
    }

    // MARK: - Non-Streaming: Anthropic-style Tool Call

    func test_anthropicStyleToolCall_parsed() async throws {
        let model = MockLanguageModel()
        var receivedAction: ComputerUseAction?
        var receivedCallId: String?

        model.generateTextHandler = { request in
            model.lock.lock()
            let count = model.generateTextCallCount
            model.lock.unlock()

            if count == 1 {
                let args = self.makeAnthropicArgsJSON(action: "left_click", coordinate: [100, 200])
                return AITextResult(
                    text: "",
                    toolCalls: [ToolCallResult(id: "toolu_1", name: "computer", arguments: args)],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "Clicked.",
                    usage: AIUsage(promptTokens: 20, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            builtInTools: [.computerUseDefault],
            stopCondition: .stepCount(5)
        )

        await agent.setComputerUseHandler { cuCall in
            receivedAction = cuCall.action
            receivedCallId = cuCall.callId
            return .screenshot("fakeBase64")
        }

        _ = try await agent.execute(messages: [.user("Click")])

        XCTAssertEqual(receivedAction, .click(x: 100, y: 200, button: .left))
        XCTAssertNil(receivedCallId, "Anthropic-style calls should not have a callId")
    }

    // MARK: - Non-Streaming: Mixed Tool Calls

    func test_computerUseAndRegularToolCalls_bothProcessed() async throws {
        let model = MockLanguageModel()
        var cuHandlerCalled = false

        model.generateTextHandler = { request in
            model.lock.lock()
            let count = model.generateTextCallCount
            model.lock.unlock()

            if count == 1 {
                let cuArgs = self.makeOpenAIPayloadJSON(actionType: "screenshot")
                return AITextResult(
                    text: "",
                    toolCalls: [
                        ToolCallResult(id: "tc_cu", name: "__computer_use__", arguments: cuArgs),
                        ToolCallResult(id: "tc_reg", name: "cu_test_mock_tool", arguments: "{\"input\":\"test\"}")
                    ],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            } else {
                return AITextResult(
                    text: "Both processed.",
                    usage: AIUsage(promptTokens: 20, completionTokens: 10),
                    finishReason: .stop
                )
            }
        }

        let agent = Agent(
            model: model,
            tools: [CUTestMockTool.self],
            builtInTools: [.computerUseDefault],
            stopCondition: .stepCount(5)
        )

        await agent.setComputerUseHandler { _ in
            cuHandlerCalled = true
            return .screenshot("fakeBase64")
        }

        _ = try await agent.execute(messages: [.user("Do both")])

        XCTAssertTrue(cuHandlerCalled, "Computer use handler should be called")

        let messages = await agent.messages
        let toolMessages = messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.count, 2, "Should have 2 tool result messages")
    }

    // MARK: - Streaming: Event Emission

    func test_streamExecute_emitsComputerUseAction() async throws {
        let model = MockLanguageModel()

        model.streamTextHandler = { request in
            AsyncThrowingStream { continuation in
                model.lock.lock()
                let count = model.generateTextCallCount
                model.generateTextCallCount += 1
                model.lock.unlock()

                if count == 0 {
                    let args = self.makeOpenAIPayloadJSON(actionType: "screenshot")
                    continuation.yield(.toolCall(id: "tc_1", name: "__computer_use__", arguments: args))
                    continuation.yield(.finish(finishReason: .toolCalls, usage: AIUsage(promptTokens: 10, completionTokens: 5)))
                    continuation.finish()
                } else {
                    continuation.yield(.textDelta("Done streaming."))
                    continuation.yield(.finish(finishReason: .stop, usage: AIUsage(promptTokens: 20, completionTokens: 10)))
                    continuation.finish()
                }
            }
        }

        let agent = Agent(
            model: model,
            builtInTools: [.computerUseDefault],
            stopCondition: .stepCount(5)
        )

        await agent.setComputerUseHandler { cuCall in
            return .screenshot("streamBase64")
        }

        var events: [AIStreamEvent] = []
        for try await event in agent.streamExecute(messages: [.user("Take a screenshot")]) {
            events.append(event)
        }

        let cuEvents = events.compactMap { event -> ComputerUseToolCall? in
            if case .computerUseAction(let cuCall) = event {
                return cuCall
            }
            return nil
        }

        XCTAssertFalse(cuEvents.isEmpty, "Should emit at least one computerUseAction event")
        XCTAssertEqual(cuEvents.first?.action, .screenshot)
    }

    func test_streamExecute_computerUseLoop_continues() async throws {
        let model = MockLanguageModel()

        model.streamTextHandler = { request in
            AsyncThrowingStream { continuation in
                model.lock.lock()
                model.generateTextCallCount += 1
                let count = model.generateTextCallCount
                model.lock.unlock()

                if count == 1 {
                    let args = self.makeOpenAIPayloadJSON(actionType: "screenshot")
                    continuation.yield(.toolCall(id: "tc_1", name: "__computer_use__", arguments: args))
                    continuation.yield(.finish(finishReason: .toolCalls, usage: AIUsage(promptTokens: 10, completionTokens: 5)))
                    continuation.finish()
                } else {
                    continuation.yield(.textDelta("Final response after screenshot."))
                    continuation.yield(.finish(finishReason: .stop, usage: AIUsage(promptTokens: 20, completionTokens: 10)))
                    continuation.finish()
                }
            }
        }

        let agent = Agent(
            model: model,
            builtInTools: [.computerUseDefault],
            stopCondition: .stepCount(5)
        )

        await agent.setComputerUseHandler { _ in
            return .screenshot("fakeBase64")
        }

        var events: [AIStreamEvent] = []
        for try await event in agent.streamExecute(messages: [.user("Screenshot")]) {
            events.append(event)
        }

        let stepStartEvents = events.filter {
            if case .stepStart = $0 { return true }
            return false
        }
        XCTAssertGreaterThanOrEqual(stepStartEvents.count, 2, "Should have at least 2 step starts")

        let hasCUEvent = events.contains {
            if case .computerUseAction = $0 { return true }
            return false
        }
        XCTAssertTrue(hasCUEvent, "Should emit computerUseAction event")

        let textDeltas = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }
        let fullText = textDeltas.joined()
        XCTAssertTrue(fullText.contains("Final response"), "Should have final text from second step")
    }
}

// MARK: - Mock Tool

private struct CUTestMockTool: Tool {
    var name: String { "cu_test_mock_tool" }
    var description: String { "A mock tool for computer use agent tests" }

    @Parameter(description: "Test input")
    var input: String = ""

    init() {}

    func execute() async throws -> ToolResult {
        ToolResult(content: "Mock result: \(input)")
    }
}
