//
//  AgentUIToolTests.swift
//  AISDKTests
//
//  Integration tests for UITool detection in Agent tool execution.
//  Verifies that Agent attaches UIToolResultMetadata when executing UITools.
//

import XCTest
@testable import AISDK

#if canImport(SwiftUI)
import SwiftUI

final class AgentUIToolTests: XCTestCase {

    // MARK: - Test Tools

    private struct MockUIWeatherTool: UITool {
        let name = "ui_weather"
        let description = "Get weather with a UI view"

        @Parameter(description: "City name")
        var city: String = ""

        init() {}

        func execute() async throws -> ToolResult {
            ToolResult(content: "Weather in \(city): 20C, Sunny")
        }

        var body: some View {
            Text("Weather: \(city)")
        }
    }

    private struct MockPlainTool: Tool {
        let name = "plain_tool"
        let description = "A plain tool without UI"

        @Parameter(description: "Input")
        var input: String = ""

        init() {}

        func execute() async throws -> ToolResult {
            ToolResult(content: "Result: \(input)")
        }
    }

    // MARK: - Mock Language Model

    private class MockToolLLM: LLM, @unchecked Sendable {
        let provider = "mock"
        let modelId = "mock-uitool-model"
        let capabilities: LLMCapabilities = []

        var generateTextHandler: ((AITextRequest) async throws -> AITextResult)?
        var callCount = 0
        let lock = NSLock()

        func generateText(request: AITextRequest) async throws -> AITextResult {
            lock.lock()
            callCount += 1
            let count = callCount
            lock.unlock()

            if let handler = generateTextHandler {
                return try await handler(request)
            }

            // Default: first call returns tool call, second returns final text
            if count == 1 {
                return AITextResult(
                    text: "",
                    toolCalls: [ToolCallResult(id: "call-1", name: "ui_weather", arguments: "{\"city\":\"Tokyo\"}")],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            }
            return AITextResult(
                text: "Done",
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .stop
            )
        }

        func streamText(request: AITextRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
            AsyncThrowingStream { continuation in
                Task {
                    let result = try await self.generateText(request: request)
                    if !result.toolCalls.isEmpty {
                        for tc in result.toolCalls {
                            continuation.yield(.toolCallStart(id: tc.id, name: tc.name))
                            continuation.yield(.toolCall(id: tc.id, name: tc.name, arguments: tc.arguments))
                        }
                    }
                    if !result.text.isEmpty {
                        continuation.yield(.textDelta(result.text))
                    }
                    continuation.yield(.finish(finishReason: result.finishReason, usage: result.usage))
                    continuation.finish()
                }
            }
        }

        func streamObject<T: Codable & Sendable>(request: AIObjectRequest<T>) -> AsyncThrowingStream<AIStreamEvent, Error> {
            AsyncThrowingStream { $0.finish() }
        }
    }

    // MARK: - Tests

    func test_execute_with_uitool_attaches_metadata() async throws {
        let model = MockToolLLM()
        let agent = Agent(
            model: model,
            tools: [MockUIWeatherTool.self],
            instructions: "Test agent"
        )

        let result = try await agent.execute(messages: [.user("Weather in Tokyo?")])

        // The first step should have a tool result with UIToolResultMetadata
        XCTAssertGreaterThanOrEqual(result.steps.count, 1)

        let toolStep = result.steps.first { !$0.toolResults.isEmpty }
        XCTAssertNotNil(toolStep, "Expected a step with tool results")

        if let toolResult = toolStep?.toolResults.first {
            XCTAssertNotNil(toolResult.metadata, "UITool result should have metadata")
            let uiMeta = toolResult.metadata as? UIToolResultMetadata
            XCTAssertNotNil(uiMeta, "Metadata should be UIToolResultMetadata")
            XCTAssertTrue(uiMeta?.hasUIView ?? false, "hasUIView should be true")
        }
    }

    func test_execute_with_plain_tool_has_no_uitool_metadata() async throws {
        let model = MockToolLLM()
        model.generateTextHandler = { [weak model] _ in
            let count: Int
            model?.lock.lock()
            count = model?.callCount ?? 0
            model?.lock.unlock()

            if count == 1 {
                return AITextResult(
                    text: "",
                    toolCalls: [ToolCallResult(id: "call-1", name: "plain_tool", arguments: "{\"input\":\"hello\"}")],
                    usage: AIUsage(promptTokens: 10, completionTokens: 5),
                    finishReason: .toolCalls
                )
            }
            return AITextResult(
                text: "Done",
                usage: AIUsage(promptTokens: 10, completionTokens: 5),
                finishReason: .stop
            )
        }

        let agent = Agent(
            model: model,
            tools: [MockPlainTool.self],
            instructions: "Test agent"
        )

        let result = try await agent.execute(messages: [.user("Run plain tool")])

        let toolStep = result.steps.first { !$0.toolResults.isEmpty }
        XCTAssertNotNil(toolStep, "Expected a step with tool results")

        if let toolResult = toolStep?.toolResults.first {
            let uiMeta = toolResult.metadata as? UIToolResultMetadata
            XCTAssertNil(uiMeta, "Plain tool should not have UIToolResultMetadata")
        }
    }

    func test_stream_execute_emits_uitool_metadata_in_tool_result() async throws {
        let model = MockToolLLM()
        let agent = Agent(
            model: model,
            tools: [MockUIWeatherTool.self],
            instructions: "Test agent"
        )

        let stream = agent.streamExecute(messages: [.user("Weather?")])

        var foundToolResultWithMetadata = false
        for try await event in stream {
            if case .toolResult(_, _, let metadata) = event {
                if let uiMeta = metadata as? UIToolResultMetadata {
                    XCTAssertTrue(uiMeta.hasUIView)
                    foundToolResultWithMetadata = true
                }
            }
        }

        XCTAssertTrue(foundToolResultWithMetadata, "Stream should emit a .toolResult with UIToolResultMetadata")
    }
}

#endif
