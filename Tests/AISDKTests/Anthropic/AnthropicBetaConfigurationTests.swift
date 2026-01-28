import XCTest
@testable import AISDK

final class AnthropicBetaConfigurationTests: XCTestCase {
    func testHeaderValue() {
        var config = AnthropicService.BetaConfiguration()
        XCTAssertNil(config.headerValue())

        config.filesAPI = true
        config.context1M = true

        XCTAssertEqual(
            config.headerValue(),
            "files-api-2025-04-14,context-1m-2025-08-07"
        )
    }

    func testMergingConfigurations() {
        let a = AnthropicService.BetaConfiguration(filesAPI: true)
        let b = AnthropicService.BetaConfiguration(context1M: true, computerUse: true)

        let merged = a.merging(with: b)
        XCTAssertTrue(merged.filesAPI)
        XCTAssertTrue(merged.context1M)
        XCTAssertTrue(merged.computerUse)
    }

    func testPresets() {
        XCTAssertNil(AnthropicService.BetaConfiguration.none.headerValue())

        let files = AnthropicService.BetaConfiguration.files
        XCTAssertEqual(files.headerValue(), "files-api-2025-04-14")

        let maxContext = AnthropicService.BetaConfiguration.maxContext
        XCTAssertEqual(maxContext.headerValue(), "context-1m-2025-08-07")

        let thinking = AnthropicService.BetaConfiguration.thinkingWithTools
        XCTAssertTrue(thinking.extendedThinking)
        XCTAssertTrue(thinking.interleavedThinking)
    }
}
