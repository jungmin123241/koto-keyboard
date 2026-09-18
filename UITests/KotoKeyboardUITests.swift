import XCTest

final class KotoKeyboardUITests: XCTestCase {
    func testOnboardingAndKeyboardGuide() {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.navigationBars["코토 키보드"].waitForExistence(timeout: 5))
        app.buttons["setupLink"].tap()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 3))
    }
    func testTranslationSettingAndHelpNavigation() {
        let app = XCUIApplication(); app.launch()
        app.buttons["settingsLink"].tap()
        let toggle = app.switches["translationToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        let previous = toggle.value as? String
        toggle.tap()
        XCTAssertNotEqual(toggle.value as? String, previous)
        toggle.tap() // Restore the user's original setting.
    }
}
