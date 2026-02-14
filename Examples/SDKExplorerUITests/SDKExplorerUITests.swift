import XCTest

final class SDKExplorerUITests: XCTestCase {
    func testAppLaunchesAndShowsLayer3Tabs() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Sessions"].exists)
        XCTAssertTrue(app.tabBars.buttons["Diagnostics"].exists)
    }
}
