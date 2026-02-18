//
//  OpenAIProviderTextRequestTests.swift
//  AISDKTests
//
//  Tests for OpenAI provider AITextRequest bridge functionality
//

import XCTest
@testable import AISDK

final class OpenAIProviderTextRequestTests: XCTestCase {

    var mockProvider: MockOpenAIResponsesProvider!

    override func setUp() {
        super.setUp()
        mockProvider = MockOpenAIResponsesProvider()
    }

    override func tearDown() {
        mockProvider.reset()
        mockProvider = nil
        super.tearDown()
    }

    // MARK: - Basic Request Conversion Tests

    func testMockProvider_BasicRequest() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Hello")
        )

        let response = try await mockProvider.createResponse(request: request)

        XCTAssertEqual(mockProvider.requestCount, 1)
        XCTAssertNotNil(mockProvider.lastRequest)
        XCTAssertEqual(response.status, .completed)
        XCTAssertNotNil(response.outputText)
    }

    func testMockProvider_WithInstructions() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("What is 2+2?"),
            instructions: "Answer with just the number"
        )

        _ = try await mockProvider.createResponse(request: request)

        XCTAssertEqual(mockProvider.lastRequest?.instructions, "Answer with just the number")
    }

    func testMockProvider_WithPreviousResponseId() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Continue our conversation"),
            previousResponseId: "resp_previous_123"
        )

        _ = try await mockProvider.createResponse(request: request)

        XCTAssertEqual(mockProvider.lastRequest?.previousResponseId, "resp_previous_123")
    }

    // MARK: - Tool Configuration Tests

    func testMockProvider_WithWebSearchTool() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Search for news"),
            tools: [.webSearchPreview]
        )

        let response = try await mockProvider.createResponse(request: request)

        XCTAssertNotNil(mockProvider.lastRequest?.tools)
        XCTAssertEqual(response.status, .completed)
    }

    func testMockProvider_WithFileSearchTool() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Search my files"),
            tools: [.fileSearch(vectorStoreIds: ["vs_123"])]
        )

        _ = try await mockProvider.createResponse(request: request)

        XCTAssertNotNil(mockProvider.lastRequest?.tools)
    }

    func testMockProvider_WithCodeInterpreterTool() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Run some code"),
            tools: [.codeInterpreter]
        )

        _ = try await mockProvider.createResponse(request: request)

        XCTAssertNotNil(mockProvider.lastRequest?.tools)
    }

    func testMockProvider_WithMultipleTools() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Help me with research"),
            tools: [.webSearchPreview, .codeInterpreter]
        )

        _ = try await mockProvider.createResponse(request: request)

        XCTAssertEqual(mockProvider.lastRequest?.tools?.count, 2)
    }

    // MARK: - Request Parameters Tests

    func testMockProvider_WithTemperature() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Test"),
            temperature: 0.7
        )

        _ = try await mockProvider.createResponse(request: request)

        XCTAssertEqual(mockProvider.lastRequest?.temperature, 0.7)
    }

    func testMockProvider_WithTopP() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Test"),
            topP: 0.9
        )

        _ = try await mockProvider.createResponse(request: request)

        XCTAssertEqual(mockProvider.lastRequest?.topP, 0.9)
    }

    func testMockProvider_WithMaxOutputTokens() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Test"),
            maxOutputTokens: 500
        )

        _ = try await mockProvider.createResponse(request: request)

        XCTAssertEqual(mockProvider.lastRequest?.maxOutputTokens, 500)
    }

    func testMockProvider_WithMetadata() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Test"),
            metadata: ["session_id": "sess_123", "user_type": "premium"]
        )

        _ = try await mockProvider.createResponse(request: request)

        XCTAssertNotNil(mockProvider.lastRequest?.metadata)
        XCTAssertEqual(mockProvider.lastRequest?.metadata?["session_id"], "sess_123")
    }

    // MARK: - Response Structure Tests

    func testMockProvider_ResponseHasCorrectStructure() async throws {
        let request = ResponseRequest(
            model: "gpt-4o-mini",
            input: .string("Hello")
        )

        let response = try await mockProvider.createResponse(request: request)

        XCTAssertFalse(response.id.isEmpty)
        XCTAssertEqual(response.object, "response")
        XCTAssertGreaterThan(response.createdAt, 0)
        XCTAssertEqual(response.model, "gpt-4o-mini")
        XCTAssertEqual(response.status, .completed)
        XCTAssertFalse(response.output.isEmpty)
        XCTAssertNotNil(response.usage)
    }

    func testMockProvider_ResponseUsageTracking() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Test message for usage tracking")
        )

        let response = try await mockProvider.createResponse(request: request)

        XCTAssertNotNil(response.usage)
        XCTAssertGreaterThan(response.usage?.inputTokens ?? 0, 0)
        XCTAssertGreaterThan(response.usage?.outputTokens ?? 0, 0)
        XCTAssertEqual(
            response.usage?.totalTokens,
            (response.usage?.inputTokens ?? 0) + (response.usage?.outputTokens ?? 0)
        )
    }

    // MARK: - Error Handling Tests

    func testMockProvider_ThrowsConfiguredError() async throws {
        mockProvider.shouldThrowError = true
        mockProvider.errorToThrow = LLMError.modelNotAvailable

        let request = ResponseRequest(
            model: "invalid-model",
            input: .string("Test")
        )

        do {
            _ = try await mockProvider.createResponse(request: request)
            XCTFail("Expected error to be thrown")
        } catch let error as LLMError {
            XCTAssertEqual(error, .modelNotAvailable)
        }
    }

    func testMockProvider_ThrowsHTTPError() async throws {
        mockProvider.shouldThrowError = true
        mockProvider.errorToThrow = AISDKError.httpError(429, "Rate limit exceeded")

        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Test")
        )

        do {
            _ = try await mockProvider.createResponse(request: request)
            XCTFail("Expected error to be thrown")
        } catch let error as AISDKError {
            if case .httpError(let code, let message) = error {
                XCTAssertEqual(code, 429)
                XCTAssertEqual(message, "Rate limit exceeded")
            } else {
                XCTFail("Unexpected error type")
            }
        }
    }

    // MARK: - Streaming Tests

    func testMockProvider_StreamingResponse() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Tell me a story"),
            stream: true
        )

        var chunks: [ResponseChunk] = []
        for try await chunk in mockProvider.createResponseStream(request: request) {
            chunks.append(chunk)
        }

        XCTAssertFalse(chunks.isEmpty)
        XCTAssertEqual(mockProvider.requestCount, 1)
    }

    func testMockProvider_StreamingCollectsText() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Hello"),
            stream: true
        )

        var collectedText = ""
        for try await chunk in mockProvider.createResponseStream(request: request) {
            if let text = chunk.delta?.text {
                collectedText += text
            }
        }

        XCTAssertFalse(collectedText.isEmpty)
    }

    func testMockProvider_StreamingFinalChunkHasUsage() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Hello"),
            stream: true
        )

        var lastChunk: ResponseChunk?
        for try await chunk in mockProvider.createResponseStream(request: request) {
            lastChunk = chunk
        }

        XCTAssertNotNil(lastChunk)
        XCTAssertNotNil(lastChunk?.usage)
        XCTAssertEqual(lastChunk?.status, .completed)
    }

    // MARK: - Retrieve and Cancel Tests

    func testMockProvider_RetrieveResponse() async throws {
        let responseId = "resp_test_123"
        let response = try await mockProvider.retrieveResponse(id: responseId)

        XCTAssertEqual(mockProvider.lastRetrieveId, responseId)
        XCTAssertNotNil(response.id)
        XCTAssertEqual(response.status, .completed)
    }

    func testMockProvider_CancelResponse() async throws {
        let responseId = "resp_to_cancel"
        let response = try await mockProvider.cancelResponse(id: responseId)

        XCTAssertEqual(mockProvider.lastCancelId, responseId)
        XCTAssertEqual(response.status, .cancelled)
    }

    // MARK: - Custom Mock Response Tests

    func testMockProvider_CustomWebSearchResponse() async throws {
        mockProvider.setMockResponse(MockOpenAIResponsesProvider.createWebSearchResponse())

        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Search for AI news"),
            tools: [.webSearchPreview]
        )

        let response = try await mockProvider.createResponse(request: request)

        XCTAssertEqual(response.id, "resp-websearch-123")
        XCTAssertNotNil(response.outputText)

        // Check for web search call in output
        let hasWebSearchCall = response.output.contains { item in
            if case .webSearchCall = item { return true }
            return false
        }
        XCTAssertTrue(hasWebSearchCall)
    }

    func testMockProvider_CustomCodeInterpreterResponse() async throws {
        mockProvider.setMockResponse(MockOpenAIResponsesProvider.createCodeInterpreterResponse())

        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Run print('Hello')"),
            tools: [.codeInterpreter]
        )

        let response = try await mockProvider.createResponse(request: request)

        XCTAssertEqual(response.id, "resp-code-123")

        // Check for code interpreter call in output
        let hasCodeInterpreterCall = response.output.contains { item in
            if case .codeInterpreterCall = item { return true }
            return false
        }
        XCTAssertTrue(hasCodeInterpreterCall)
    }

    func testMockProvider_CustomFunctionCallResponse() async throws {
        mockProvider.setMockResponse(MockOpenAIResponsesProvider.createFunctionCallResponse())

        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("What's the weather in San Francisco?")
        )

        let response = try await mockProvider.createResponse(request: request)

        XCTAssertEqual(response.id, "resp-func-123")

        // Check for function call in output
        let hasFunctionCall = response.output.contains { item in
            if case .functionCall = item { return true }
            return false
        }
        XCTAssertTrue(hasFunctionCall)
    }

    // MARK: - Request Counter Tests

    func testMockProvider_TracksMultipleRequests() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Test")
        )

        _ = try await mockProvider.createResponse(request: request)
        _ = try await mockProvider.createResponse(request: request)
        _ = try await mockProvider.createResponse(request: request)

        XCTAssertEqual(mockProvider.requestCount, 3)
    }

    func testMockProvider_ResetClearsCounters() async throws {
        let request = ResponseRequest(
            model: "gpt-4o",
            input: .string("Test")
        )

        _ = try await mockProvider.createResponse(request: request)
        XCTAssertEqual(mockProvider.requestCount, 1)

        mockProvider.reset()

        XCTAssertEqual(mockProvider.requestCount, 0)
        XCTAssertNil(mockProvider.lastRequest)
        XCTAssertNil(mockProvider.lastRetrieveId)
        XCTAssertNil(mockProvider.lastCancelId)
    }
}
