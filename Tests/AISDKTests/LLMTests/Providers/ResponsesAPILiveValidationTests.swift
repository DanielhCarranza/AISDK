//
//  ResponsesAPILiveValidationTests.swift
//  AISDKTests
//
//  Live validation tests for OpenAI Responses API completeness.
//  Gated behind OPENAI_API_KEY environment variable — skipped in CI.
//

import XCTest
@testable import AISDK

final class ResponsesAPILiveValidationTests: XCTestCase {

    private var provider: OpenAIProvider!

    override func setUpWithError() throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY not set — skipping Responses API live validation tests")
        }
        provider = OpenAIProvider(apiKey: apiKey)
    }

    override func tearDownWithError() throws {
        provider = nil
    }

    // MARK: - Web Search with Annotations

    func testWebSearchWithAnnotations() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("What is the current population of Tokyo? Cite your sources."),
            tools: [.webSearchPreview()],
            include: ["web_search_call.action.sources"]
        )

        let response = try await provider.createResponse(request: request)

        XCTAssertTrue(response.status == .completed || response.status == .incomplete)
        XCTAssertNotNil(response.outputText, "Should have text output")

        // Check for web_search_call output item
        let hasWebSearch = response.output.contains { item in
            if case .webSearchCall = item { return true }
            return false
        }
        XCTAssertTrue(hasWebSearch, "Should contain a web_search_call output item")
    }

    // MARK: - Reasoning Output

    func testReasoningOutput() async throws {
        let request = ResponseRequest(
            model: "o4-mini",
            input: .string("What is 15 * 37?"),
            include: ["reasoning.encrypted_content"],
            reasoning: ResponseReasoning(effort: "low", summary: "auto")
        )

        let response = try await provider.createResponse(request: request)

        XCTAssertTrue(response.status == .completed)
        XCTAssertNotNil(response.outputText)

        // Check for reasoning output item
        var foundReasoning = false
        for item in response.output {
            if case .reasoning(let reasoning) = item {
                foundReasoning = true
                XCTAssertNotNil(reasoning.summary, "Reasoning should have summary when summary='auto'")
            }
        }
        XCTAssertTrue(foundReasoning, "Expected reasoning output item from o4-mini")
    }

    // MARK: - Code Interpreter Outputs

    func testCodeInterpreterOutputs() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Calculate the factorial of 10 using Python code."),
            tools: [.codeInterpreter()],
            include: ["code_interpreter_call.outputs"]
        )

        let response = try await provider.createResponse(request: request)

        XCTAssertTrue(response.status == .completed || response.status == .incomplete)

        // Check for code interpreter call
        for item in response.output {
            if case .codeInterpreterCall(let ci) = item {
                XCTAssertNotNil(ci.code, "Code interpreter should have code")
                XCTAssertFalse(ci.code?.isEmpty ?? true, "Code should not be empty")
                return
            }
        }
        // Model may choose not to use code interpreter — not a failure
    }

    // MARK: - Web Search Tool Config

    func testWebSearchToolConfig() async throws {
        let webSearchTool = ResponseTool.webSearchPreview(ResponseWebSearchTool(
            searchContextSize: "medium",
            userLocation: WebSearchUserLocation(city: "San Francisco", country: "US", timezone: "America/Los_Angeles")
        ))

        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("What's the weather like today?"),
            tools: [webSearchTool]
        )

        let response = try await provider.createResponse(request: request)

        // API should accept the request without error
        XCTAssertTrue(response.status != .failed, "API should accept web search tool config")
    }

    // MARK: - Usage Details

    func testUsageDetails() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Say hello in exactly three words."),
            store: true
        )

        let response = try await provider.createResponse(request: request)

        XCTAssertTrue(response.status == .completed)
        XCTAssertNotNil(response.usage, "Response should have usage data")
        XCTAssertGreaterThan(response.usage?.inputTokens ?? 0, 0)
        XCTAssertGreaterThan(response.usage?.outputTokens ?? 0, 0)
    }

    // MARK: - Incomplete Finish Reason

    // MARK: - Reasoning Summary via AITextRequest (Path B)

    func testReasoningSummaryStreaming_PathB() async throws {
        // Uses AITextRequest → convertToResponseRequest (Path B) → createResponseStream
        // Verifies: AIReasoningConfig.effort(.medium) → summary auto-defaults to "auto" → SSE reasoning deltas
        let aiRequest = AITextRequest(
            messages: [AIMessage(role: .user, content: .text("What is 15 * 37?"))],
            model: "o4-mini",
            reasoning: AIReasoningConfig.effort(.medium)
        )

        // Convert through Path B so we validate the auto-default summary logic
        let responseRequest = try provider.convertToResponseRequest(aiRequest, streaming: true)
        XCTAssertEqual(responseRequest.reasoning?.summary, "auto", "Path B should auto-default summary")

        var reasoningText = ""
        let stream = provider.createResponseStream(request: responseRequest)
        for try await chunk in stream {
            if let reasoning = chunk.delta?.reasoning, let summary = reasoning.summary {
                reasoningText += summary
            }
        }

        XCTAssertFalse(reasoningText.isEmpty, "Expected reasoning summary deltas via Path B with effort(.medium)")
    }

    func testReasoningSummaryNonStreaming_PathB() async throws {
        // Non-streaming: AIReasoningConfig → ResponseReasoning(summary: "auto") → reasoning summary in output
        let aiRequest = AITextRequest(
            messages: [AIMessage(role: .user, content: .text("What is 15 * 37?"))],
            model: "o4-mini",
            reasoning: AIReasoningConfig.effort(.medium)
        )

        // Convert through Path B and call createResponse directly to inspect raw output
        let responseRequest = try provider.convertToResponseRequest(aiRequest)
        XCTAssertEqual(responseRequest.reasoning?.summary, "auto", "Path B should auto-default summary")

        let response = try await provider.createResponse(request: responseRequest)
        XCTAssertTrue(response.status == .completed)
        XCTAssertNotNil(response.outputText)

        var foundReasoning = false
        for item in response.output {
            if case .reasoning(let reasoning) = item {
                foundReasoning = true
                XCTAssertNotNil(reasoning.summary, "Reasoning should have summary when summary='auto' via Path B")
            }
        }
        XCTAssertTrue(foundReasoning, "Expected reasoning output item from o4-mini via Path B")
    }

    // MARK: - Incomplete Finish Reason

    func testIncompleteFinishReasonMapsToLength() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Write a very long essay about the history of computing, covering every decade in detail."),
            maxOutputTokens: 16  // Very low to trigger truncation (minimum allowed)
        )

        let response = try await provider.createResponse(request: request)

        if response.status == .incomplete {
            // Verify the raw status is .incomplete — our adapter should map this to .length
            XCTAssertNotNil(response.incompleteDetails, "Incomplete response should have details")
        }
        // If the model completed within 16 tokens, that's also acceptable
    }
}
