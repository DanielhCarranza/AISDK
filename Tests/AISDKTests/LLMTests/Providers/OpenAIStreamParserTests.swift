//
//  OpenAIStreamParserTests.swift
//  AISDKTests
//
//  Tests for Responses API streaming event decoding and chunk conversion
//

import Foundation
import XCTest
@testable import AISDK

final class OpenAIStreamParserTests: XCTestCase {

    private var decoder: JSONDecoder!

    override func setUp() {
        super.setUp()
        decoder = JSONDecoder()
    }

    override func tearDown() {
        decoder = nil
        super.tearDown()
    }

    // MARK: - Lifecycle Events

    func testResponseCreatedDecodes() throws {
        let event = try decodeEvent(StreamEventFixtures.responseCreated)
        XCTAssertEqual(event.type, "response.created")
        XCTAssertEqual(event.response?.id, "resp_123")
        XCTAssertEqual(event.response?.status, .inProgress)
    }

    func testResponseCompletedDecodesUsage() throws {
        let event = try decodeEvent(StreamEventFixtures.responseCompleted)
        XCTAssertEqual(event.type, "response.completed")
        XCTAssertEqual(event.response?.usage?.totalTokens, 8)
    }

    func testResponseFailedDecodesError() throws {
        let event = try decodeEvent(StreamEventFixtures.responseFailed)
        XCTAssertEqual(event.response?.error?.message, "Internal server error")
    }

    // MARK: - Output Items and Content Parts

    func testOutputItemAddedDecodesMessage() throws {
        let event = try decodeEvent(StreamEventFixtures.outputItemAdded)
        guard case .message(let message) = event.item else {
            XCTFail("Expected message output item")
            return
        }
        XCTAssertEqual(message.role, "assistant")
        XCTAssertEqual(message.id, "msg_123")
    }

    func testContentPartAddedDecodesPart() throws {
        let event = try decodeEvent(StreamEventFixtures.contentPartAdded)
        XCTAssertEqual(event.part?.type, "output_text")
    }

    // MARK: - Text Delta Events

    func testOutputTextDeltaCreatesChunk() throws {
        let event = try decodeEvent(StreamEventFixtures.outputTextDelta)
        let accumulated = ResponsesAPIFixtures.makeResponse(status: .inProgress)

        let chunk = ResponseChunk.from(event: event, accumulatedResponse: accumulated)
        XCTAssertEqual(chunk?.delta?.outputText, "Hello")
        XCTAssertEqual(chunk?.status, .inProgress)
    }

    func testOutputTextDoneCreatesChunk() throws {
        let event = try decodeEvent(StreamEventFixtures.outputTextDone)
        let accumulated = ResponsesAPIFixtures.makeResponse(status: .inProgress)

        let chunk = ResponseChunk.from(event: event, accumulatedResponse: accumulated)
        XCTAssertEqual(chunk?.delta?.outputText, "Hello world!")
    }

    // MARK: - Function Call Events

    func testFunctionCallArgumentsDeltaDecodes() throws {
        let event = try decodeEvent(StreamEventFixtures.functionCallArgumentsDelta)
        XCTAssertEqual(event.delta, "{\"location\":")
    }

    // MARK: - Error Handling

    func testErrorEventCreatesChunkWithError() throws {
        let event = try decodeEvent(StreamEventFixtures.errorEvent)
        let chunk = ResponseChunk.from(event: event, accumulatedResponse: nil)

        XCTAssertEqual(chunk?.error?.code, "server_error")
        XCTAssertEqual(chunk?.error?.message, "Internal server error")
    }

    func testUnknownEventDoesNotThrow() throws {
        let event = try decodeEvent(StreamEventFixtures.unknownEvent)
        XCTAssertEqual(event.type, "response.some_future_event")

        let accumulated = ResponsesAPIFixtures.makeResponse(status: .inProgress)
        let chunk = ResponseChunk.from(event: event, accumulatedResponse: accumulated)
        XCTAssertEqual(chunk?.status, .inProgress)
    }

    // MARK: - Edge Cases

    func testEmptyDeltaDecodes() throws {
        let event = try decodeEvent(StreamEventFixtures.emptyDelta)
        XCTAssertEqual(event.delta, "")
    }

    func testEscapedJsonDeltaDecodes() throws {
        let event = try decodeEvent(StreamEventFixtures.escapedJsonDelta)
        XCTAssertTrue(event.delta?.contains("\\\"quotes\\\"") ?? false)
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try decodeEvent("{invalid}"))
    }

    // MARK: - Helpers

    private func decodeEvent(_ json: String) throws -> ResponseStreamEvent {
        let data = Data(json.utf8)
        return try decoder.decode(ResponseStreamEvent.self, from: data)
    }
}
