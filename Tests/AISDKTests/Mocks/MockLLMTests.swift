//
//  MockLLMTests.swift
//  AISDKTests
//
//  Tests for MockLLM
//

import XCTest
@testable import AISDK

// MARK: - Test Helpers

/// Simple output type for object generation tests
struct SimpleTestOutput: Codable, Sendable {
    let name: String
    let count: Int
}

/// Simple schema for object generation tests
struct SimpleTestSchema: SchemaBuilding {
    func build() -> JSONSchema {
        JSONSchema.object(
            properties: [
                "name": JSONSchema.string(),
                "count": JSONSchema.integer()
            ],
            required: ["name", "count"]
        )
    }
}

// MARK: - Tests

final class MockLLMTests: XCTestCase {

    // MARK: - Basic Response Tests

    func test_withResponse_returnsConfiguredText() async throws {
        let mock = MockLLM.withResponse("Hello, world!")

        let request = AITextRequest(messages: [.user("Hi")])
        let result = try await mock.generateText(request: request)

        XCTAssertEqual(result.text, "Hello, world!")
        XCTAssertEqual(result.finishReason, .stop)
        XCTAssertEqual(mock.requestCount, 1)
    }

    func test_withResponse_tracksRequest() async throws {
        let mock = MockLLM.withResponse("Test")

        let messages = [AIMessage.user("What is 2+2?")]
        let request = AITextRequest(messages: messages, model: "test-model")
        _ = try await mock.generateText(request: request)

        XCTAssertEqual(mock.lastTextRequest?.model, "test-model")
        XCTAssertEqual(mock.lastTextRequest?.messages.count, 1)
    }

    // MARK: - Tool Call Tests

    func test_withToolCall_returnsToolCall() async throws {
        let mock = MockLLM.withToolCall("get_weather", arguments: "{\"location\":\"Tokyo\"}")

        let request = AITextRequest(messages: [.user("What's the weather?")])
        let result = try await mock.generateText(request: request)

        XCTAssertEqual(result.finishReason, .toolCalls)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls.first?.name, "get_weather")
        XCTAssertEqual(result.toolCalls.first?.arguments, "{\"location\":\"Tokyo\"}")
    }

    func test_withToolCalls_returnsMultipleToolCalls() async throws {
        let mock = MockLLM.withToolCalls([
            (name: "search", arguments: "{\"query\":\"swift\"}"),
            (name: "calculate", arguments: "{\"expression\":\"2+2\"}")
        ])

        let request = AITextRequest(messages: [.user("Search and calculate")])
        let result = try await mock.generateText(request: request)

        XCTAssertEqual(result.toolCalls.count, 2)
        XCTAssertEqual(result.toolCalls[0].name, "search")
        XCTAssertEqual(result.toolCalls[1].name, "calculate")
    }

    // MARK: - Streaming Tests

    func test_streamText_emitsEvents() async throws {
        let mock = MockLLM.withResponse("Hello world")

        let request = AITextRequest(messages: [.user("Hi")])
        var events: [AIStreamEvent] = []

        for try await event in mock.streamText(request: request) {
            events.append(event)
        }

        // Should have start, text deltas, completion, usage, and finish events
        XCTAssertTrue(events.contains { if case .start = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .textDelta = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .textCompletion = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .finish = $0 { return true }; return false })
    }

    func test_withStreamEvents_emitsCustomEvents() async throws {
        let customEvents: [AIStreamEvent] = [
            .textDelta("Custom "),
            .textDelta("event"),
            .textCompletion("Custom event"),
            .finish(finishReason: .stop, usage: .zero)
        ]
        let mock = MockLLM.withStreamEvents(customEvents)

        let request = AITextRequest(messages: [.user("Hi")])
        var events: [AIStreamEvent] = []

        for try await event in mock.streamText(request: request) {
            events.append(event)
        }

        // Should include start plus our custom events
        XCTAssertTrue(events.contains { if case .start = $0 { return true }; return false })

        // Count textDelta events
        let textDeltas = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }
        XCTAssertEqual(textDeltas.count, 2)
        XCTAssertEqual(textDeltas[0], "Custom ")
        XCTAssertEqual(textDeltas[1], "event")
    }

    // MARK: - Error Injection Tests

    func test_failing_throwsConfiguredError() async throws {
        let expectedError = AISDKError.custom("Test error")
        let mock = MockLLM.failing(with: expectedError)

        let request = AITextRequest(messages: [.user("Hi")])

        do {
            _ = try await mock.generateText(request: request)
            XCTFail("Expected error to be thrown")
        } catch let error as AISDKError {
            if case .custom(let message) = error {
                XCTAssertEqual(message, "Test error")
            } else {
                XCTFail("Unexpected error type")
            }
        }
    }

    func test_failing_streamReturnsError() async throws {
        let expectedError = AISDKError.httpError(500, "Server error")
        let mock = MockLLM.failing(with: expectedError)

        let request = AITextRequest(messages: [.user("Hi")])

        var errorThrown = false
        do {
            for try await event in mock.streamText(request: request) {
                // Should emit error event then throw
                if case .error = event {
                    // This is expected before the throw
                    continue
                }
            }
        } catch {
            errorThrown = true
            XCTAssertTrue(error is AISDKError)
        }

        XCTAssertTrue(errorThrown, "Expected error to be thrown after emitting error event")
    }

    // MARK: - Delay Tests

    func test_withSlowResponse_delays() async throws {
        let mock = MockLLM.withSlowResponse(delay: .milliseconds(100), response: "Delayed")

        let request = AITextRequest(messages: [.user("Hi")])

        let start = Date()
        let result = try await mock.generateText(request: request)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result.text, "Delayed")
        XCTAssertGreaterThanOrEqual(elapsed, 0.09) // Allow small margin
    }

    // MARK: - Object Generation Tests

    func test_generateObject_parsesJSONResponse() async throws {
        // Set up mock with raw JSON response
        let mock = MockLLM()
        mock.responseText = "{\"name\":\"test\",\"count\":42}"

        // Use SimpleTestSchema which conforms to JSONSchemaModel
        let request = AIObjectRequest<SimpleTestOutput>(
            messages: [.user("Generate test output")],
            schema: SimpleTestSchema()
        )

        let result: AIObjectResult<SimpleTestOutput> = try await mock.generateObject(request: request)

        XCTAssertEqual(result.object.name, "test")
        XCTAssertEqual(result.object.count, 42)
        XCTAssertEqual(result.finishReason, AIFinishReason.stop)
    }

    // MARK: - Sequential Mock Tests

    func test_withSequence_returnsDifferentResponses() async throws {
        let mock = MockLLM.withSequence(["First", "Second", "Third"])

        let request = AITextRequest(messages: [.user("Hi")])

        let result1 = try await mock.generateText(request: request)
        let result2 = try await mock.generateText(request: request)
        let result3 = try await mock.generateText(request: request)

        XCTAssertEqual(result1.text, "First")
        XCTAssertEqual(result2.text, "Second")
        XCTAssertEqual(result3.text, "Third")
    }

    func test_withSequence_repeatsLastWhenExhausted() async throws {
        let mock = MockLLM.withSequence(["First", "Second"])

        let request = AITextRequest(messages: [.user("Hi")])

        _ = try await mock.generateText(request: request)
        _ = try await mock.generateText(request: request)
        let result3 = try await mock.generateText(request: request)
        let result4 = try await mock.generateText(request: request)

        XCTAssertEqual(result3.text, "Second")
        XCTAssertEqual(result4.text, "Second")
    }

    // MARK: - Provider Configuration Tests

    func test_withProvider_setsProviderID() async throws {
        let mock = MockLLM.withProvider("custom-provider")

        let request = AITextRequest(messages: [.user("Hi")])
        let result = try await mock.generateText(request: request)

        XCTAssertEqual(mock.provider, "custom-provider")
        XCTAssertEqual(result.provider, "custom-provider")
    }

    // MARK: - Reset Tests

    func test_reset_clearsTrackingState() async throws {
        let mock = MockLLM.withResponse("Test")

        let request = AITextRequest(messages: [.user("Hi")])
        _ = try await mock.generateText(request: request)

        XCTAssertEqual(mock.requestCount, 1)
        XCTAssertNotNil(mock.lastTextRequest)

        mock.reset()

        XCTAssertEqual(mock.requestCount, 0)
        XCTAssertNil(mock.lastTextRequest)
    }

    // MARK: - Concurrent Request Tests

    func test_concurrentRequests_trackCorrectly() async throws {
        let mock = MockLLM.withResponse("Test")

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let request = AITextRequest(messages: [.user("Hi")])
                    _ = try? await mock.generateText(request: request)
                }
            }
        }

        XCTAssertEqual(mock.requestCount, 10)
    }

    // MARK: - streamObject Tests

    func test_streamObject_emitsEvents() async throws {
        let mock = MockLLM()
        mock.responseText = "{\"name\":\"stream-test\",\"count\":99}"

        let request = AIObjectRequest<SimpleTestOutput>(
            messages: [.user("Generate output")],
            schema: SimpleTestSchema()
        )

        var events: [AIStreamEvent] = []
        for try await event in mock.streamObject(request: request) {
            events.append(event)
        }

        // Should have start, objectDelta, usage, and finish events
        XCTAssertTrue(events.contains { if case .start = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .objectDelta = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .usage = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .finish = $0 { return true }; return false })
    }

    func test_streamObject_reassemblesJSON() async throws {
        let mock = MockLLM()
        let expectedJSON = "{\"name\":\"reassembly-test\",\"count\":123}"
        mock.responseText = expectedJSON

        let request = AIObjectRequest<SimpleTestOutput>(
            messages: [.user("Generate output")],
            schema: SimpleTestSchema()
        )

        var collectedData = Data()
        for try await event in mock.streamObject(request: request) {
            if case .objectDelta(let chunk) = event {
                collectedData.append(chunk)
            }
        }

        let reassembledJSON = String(data: collectedData, encoding: .utf8)
        XCTAssertEqual(reassembledJSON, expectedJSON)
    }

    // MARK: - Empty Sequence Tests

    func test_withSequence_emptyReturnsEmptyString() async throws {
        let mock = MockLLM.withSequence([])

        let request = AITextRequest(messages: [.user("Hi")])
        let result = try await mock.generateText(request: request)

        // Should return empty string rather than crash
        XCTAssertEqual(result.text, "")
    }

    // MARK: - Error Event Tests

    func test_failing_streamEmitsErrorEvent() async throws {
        let expectedError = AISDKError.custom("Stream error")
        let mock = MockLLM.failing(with: expectedError)

        let request = AITextRequest(messages: [.user("Hi")])

        var errorEventReceived = false
        do {
            for try await event in mock.streamText(request: request) {
                if case .error = event {
                    errorEventReceived = true
                }
            }
        } catch {
            // Expected to throw after emitting error event
        }

        XCTAssertTrue(errorEventReceived, "Stream should emit .error event before throwing")
    }

    func test_failing_streamObjectEmitsErrorEvent() async throws {
        let expectedError = AISDKError.custom("Object stream error")
        let mock = MockLLM.failing(with: expectedError)

        let request = AIObjectRequest<SimpleTestOutput>(
            messages: [.user("Generate output")],
            schema: SimpleTestSchema()
        )

        var errorEventReceived = false
        do {
            for try await event in mock.streamObject(request: request) {
                if case .error = event {
                    errorEventReceived = true
                }
            }
        } catch {
            // Expected to throw after emitting error event
        }

        XCTAssertTrue(errorEventReceived, "Stream should emit .error event before throwing")
    }

    // MARK: - Tool Call Stream Tests

    func test_withToolCall_streamDoesNotEmitEmptyTextCompletion() async throws {
        let mock = MockLLM.withToolCall("get_weather", arguments: "{}")

        let request = AITextRequest(messages: [.user("Get weather")])

        var hasTextCompletion = false
        for try await event in mock.streamText(request: request) {
            if case .textCompletion(let text) = event {
                hasTextCompletion = true
                // If we get a text completion, it should not be empty
                XCTAssertFalse(text.isEmpty, "Text completion should not be empty for tool-call-only responses")
            }
        }

        // For tool-call-only responses with empty text, no text completion should be emitted
        XCTAssertFalse(hasTextCompletion, "Should not emit text completion for tool-call-only responses")
    }

    // MARK: - Custom Stream Events with Start

    func test_withStreamEvents_includesStartDoesNotDuplicate() async throws {
        let customEvents: [AIStreamEvent] = [
            .start(metadata: AIStreamMetadata(requestId: "custom-start", model: "custom-model", provider: "custom")),
            .textDelta("Hello"),
            .textCompletion("Hello"),
            .finish(finishReason: .stop, usage: .zero)
        ]
        let mock = MockLLM.withStreamEvents(customEvents)

        let request = AITextRequest(messages: [.user("Hi")])

        var startCount = 0
        for try await event in mock.streamText(request: request) {
            if case .start = event {
                startCount += 1
            }
        }

        XCTAssertEqual(startCount, 1, "Should not duplicate .start event when custom events include it")
    }
}
