import XCTest
@testable import AISDK

final class AnthropicModelsTests: XCTestCase {
    func testClaude45ModelsExist() {
        XCTAssertNotNil(AnthropicModels.findModel("claude-opus-4-5-20251101"))
        XCTAssertNotNil(AnthropicModels.findModel("claude-sonnet-4-5-20250929"))
        XCTAssertNotNil(AnthropicModels.findModel("claude-haiku-4-5-20251001"))
    }

    func testClaude45StaticAccessors() {
        XCTAssertEqual(AnthropicModels.opus45.name, "claude-opus-4-5-20251101")
        XCTAssertEqual(AnthropicModels.sonnet45.name, "claude-sonnet-4-5-20250929")
        XCTAssertEqual(AnthropicModels.haiku45.name, "claude-haiku-4-5-20251001")
    }

    func testClaude45Aliases() {
        XCTAssertNotNil(AnthropicModels.findModel("claude-opus-4-5-latest"))
        XCTAssertNotNil(AnthropicModels.findModel("claude-sonnet-4-5"))
        XCTAssertNotNil(AnthropicModels.findModel("claude-haiku-4-5"))
    }

    func testDeprecatedModelsAreMarked() {
        let deprecatedNames = [
            "claude-3-5-sonnet-20241022",
            "claude-3-7-sonnet-20250219",
            "claude-3-haiku-20240307",
            "claude-3-opus-20240229"
        ]

        for name in deprecatedNames {
            guard let model = AnthropicModels.findModel(name) else {
                XCTFail("Missing model: \(name)")
                continue
            }
            XCTAssertTrue(model.isDeprecated, "\(name) should be deprecated")
        }
    }

    func testCapabilitiesIncludeThinking() {
        let thinkingModels = AnthropicModels().allModels.filter { $0.capabilities.contains(.thinking) }
        XCTAssertGreaterThanOrEqual(thinkingModels.count, 3)
    }

    func testVisionAndToolsCapabilities() {
        let sonnet = AnthropicModels.sonnet45
        XCTAssertTrue(sonnet.capabilities.contains(.vision))
        XCTAssertTrue(sonnet.capabilities.contains(.tools))
    }
}
