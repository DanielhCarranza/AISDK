import XCTest
@testable import AISDK

final class AnthropicThinkingTypesTests: XCTestCase {
    func testThinkingConfigEncodingEnabled() throws {
        let config = AnthropicThinkingConfigParam.enabled(budgetTokens: 2048)
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "enabled")
        XCTAssertEqual(json?["budget_tokens"] as? Int, 2048)
    }

    func testThinkingConfigEncodingDisabled() throws {
        let config = AnthropicThinkingConfigParam.disabled
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["type"] as? String, "disabled")
        XCTAssertNil(json?["budget_tokens"])
    }

    func testThinkingConfigDecoding() throws {
        let enabledJSON = #"{"type":"enabled","budget_tokens":1024}"#
        let enabled = try JSONDecoder().decode(
            AnthropicThinkingConfigParam.self,
            from: Data(enabledJSON.utf8)
        )
        XCTAssertEqual(enabled, .enabled(budgetTokens: 1024))

        let disabledJSON = #"{"type":"disabled"}"#
        let disabled = try JSONDecoder().decode(
            AnthropicThinkingConfigParam.self,
            from: Data(disabledJSON.utf8)
        )
        XCTAssertEqual(disabled, .disabled)
    }

    func testThinkingConfigValidation() {
        XCTAssertThrowsError(try AnthropicThinkingConfigParam.enabled(budgetTokens: 512).validate(maxTokens: 4096)) { error in
            guard case .invalidRequest = error as? LLMError else {
                XCTFail("Expected invalidRequest error")
                return
            }
        }

        XCTAssertThrowsError(try AnthropicThinkingConfigParam.enabled(budgetTokens: 4096).validate(maxTokens: 4096)) { error in
            guard case .invalidRequest = error as? LLMError else {
                XCTFail("Expected invalidRequest error")
                return
            }
        }

        XCTAssertNoThrow(try AnthropicThinkingConfigParam.enabled(budgetTokens: 2048).validate(maxTokens: 4096))
        XCTAssertNoThrow(try AnthropicThinkingConfigParam.disabled.validate(maxTokens: 4096))
    }

    func testThinkingConfigConvenienceProperties() {
        let enabled = AnthropicThinkingConfigParam.enabled(budgetTokens: 2048)
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertEqual(enabled.budgetTokens, 2048)

        let disabled = AnthropicThinkingConfigParam.disabled
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertNil(disabled.budgetTokens)
    }

    func testThinkingBlocksRoundTrip() throws {
        let block = AnthropicThinkingBlock(thinking: "Plan", signature: "sig")
        let data = try JSONEncoder().encode(block)
        let decoded = try JSONDecoder().decode(AnthropicThinkingBlock.self, from: data)
        XCTAssertEqual(decoded, block)

        let redacted = AnthropicRedactedThinkingBlock(data: "secret")
        let redactedData = try JSONEncoder().encode(redacted)
        let decodedRedacted = try JSONDecoder().decode(AnthropicRedactedThinkingBlock.self, from: redactedData)
        XCTAssertEqual(decodedRedacted, redacted)
    }
}
