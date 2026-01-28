import XCTest
@testable import AISDK

final class AnthropicBatchTypesTests: XCTestCase {
    func testBatchRequestCountsTotal() {
        let counts = BatchRequestCounts(canceled: 1, errored: 2, expired: 3, processing: 4, succeeded: 5)
        XCTAssertEqual(counts.total, 15)
    }

    func testBatchValidationRejectsDuplicateIds() throws {
        let request = AnthropicMessageRequestBody(
            maxTokens: 1,
            messages: [AnthropicInputMessage(content: [.text("Hi")], role: .user)],
            model: "claude-sonnet-4-5-20250929"
        )

        let items = [
            try AnthropicBatchRequestItem(customId: "dup", params: request),
            try AnthropicBatchRequestItem(customId: "dup", params: request)
        ]

        XCTAssertThrowsError(try BatchRequestValidation.validate(requests: items)) { error in
            guard case .invalidRequest = error as? LLMError else {
                XCTFail("Expected invalidRequest error")
                return
            }
        }
    }

    func testBatchValidationRejectsInvalidIdLength() throws {
        let request = AnthropicMessageRequestBody(
            maxTokens: 1,
            messages: [AnthropicInputMessage(content: [.text("Hi")], role: .user)],
            model: "claude-sonnet-4-5-20250929"
        )

        let longId = String(repeating: "a", count: BatchRequestValidation.maxCustomIdLength + 1)
        let items = [try AnthropicBatchRequestItem(customId: longId, params: request)]

        XCTAssertThrowsError(try BatchRequestValidation.validate(requests: items)) { error in
            guard case .invalidRequest = error as? LLMError else {
                XCTFail("Expected invalidRequest error")
                return
            }
        }
    }

    func testBatchResultDecoding() throws {
        let json = """
        {
          "custom_id": "req-1",
          "result": {
            "type": "succeeded",
            "message": {
              "id": "msg_1",
              "type": "message",
              "role": "assistant",
              "model": "claude-sonnet-4-5-20250929",
              "content": [{"type": "text", "text": "Hello"}],
              "stop_reason": "end_turn",
              "stop_sequence": null,
              "usage": {"input_tokens": 1, "output_tokens": 2}
            }
          }
        }
        """

        let result = try AnthropicHTTPClient.decoder.decode(AnthropicBatchResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.customId, "req-1")
        XCTAssertEqual(result.result.type, .succeeded)
        XCTAssertEqual(result.result.message?.id, "msg_1")
    }
}
