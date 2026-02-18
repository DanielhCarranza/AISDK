import XCTest
@testable import AISDK

final class AnthropicStreamingDeltaTests: XCTestCase {
    func testDeltaDecoding() throws {
        let textJSON = #"{"type":"text_delta","text":"Hello"}"#
        let text = try JSONDecoder().decode(AnthropicStreamingDelta.self, from: Data(textJSON.utf8))
        XCTAssertEqual(text, .textDelta(text: "Hello"))

        let thinkingJSON = #"{"type":"thinking_delta","thinking":"Thought"}"#
        let thinking = try JSONDecoder().decode(AnthropicStreamingDelta.self, from: Data(thinkingJSON.utf8))
        XCTAssertEqual(thinking, .thinkingDelta(thinking: "Thought"))

        let signatureJSON = #"{"type":"signature_delta","signature":"sig"}"#
        let signature = try JSONDecoder().decode(AnthropicStreamingDelta.self, from: Data(signatureJSON.utf8))
        XCTAssertEqual(signature, .signatureDelta(signature: "sig"))

        let jsonDeltaJSON = #"{"type":"input_json_delta","partial_json":"{\"a\":1}"}"#
        let jsonDelta = try JSONDecoder().decode(AnthropicStreamingDelta.self, from: Data(jsonDeltaJSON.utf8))
        XCTAssertEqual(jsonDelta, .inputJsonDelta(partialJson: "{\"a\":1}"))
    }

    func testDeltaEncoding() throws {
        let delta = AnthropicStreamingDelta.thinkingDelta(thinking: "Plan")
        let data = try JSONEncoder().encode(delta)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "thinking_delta")
        XCTAssertEqual(json?["thinking"] as? String, "Plan")
    }

    func testContentBlockStartParsing() {
        // SSE lines have actual JSON, not escaped backslashes
        let line = #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#
        let start = AnthropicContentBlockStart.from(line: line)
        XCTAssertEqual(start?.index, 0)
        XCTAssertEqual(start?.contentBlock.type, "thinking")
    }

    func testContentBlockDeltaParsing() {
        // SSE lines have actual JSON, not escaped backslashes
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#
        let delta = AnthropicContentBlockDelta.from(line: line)
        XCTAssertEqual(delta?.index, 0)
        XCTAssertEqual(delta?.delta, .textDelta(text: "Hi"))
    }

    func testContentBlockStopParsing() {
        // SSE lines have actual JSON, not escaped backslashes
        let line = #"data: {"type":"content_block_stop","index":2}"#
        let stop = AnthropicContentBlockStop.from(line: line)
        XCTAssertEqual(stop?.index, 2)
    }
}
