import XCTest

@MainActor
final class CompanionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOnlyCompanionDestinationsAreReachable() {
        let app = XCUIApplication()
        app.launchEnvironment["VAMP_COMPANION_UI_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["companion-tab-models"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["companion-tab-devices"].exists)
        XCTAssertTrue(app.buttons["companion-tab-settings"].exists)
        XCTAssertFalse(app.buttons["New Chat"].exists)
        app.buttons["companion-tab-devices"].click()
        XCTAssertTrue(app.staticTexts["Pair your iPhone or iPad"].waitForExistence(timeout: 10))
        app.buttons["companion-tab-settings"].click()
        XCTAssertTrue(app.buttons["companion-manage-providers"].waitForExistence(timeout: 10))
        app.buttons["companion-manage-providers"].click()
        XCTAssertTrue(app.staticTexts["API providers & accounts"].waitForExistence(timeout: 10))
        app.buttons["Done"].firstMatch.click()
        app.buttons["companion-tab-models"].click()
        XCTAssertTrue(app.descendants(matching: .any)["companion-models"].firstMatch.waitForExistence(timeout: 10))
    }

    func testClosingAndReopeningWindowKeepsOneHostProcess() {
        let app = XCUIApplication()
        app.launchEnvironment["VAMP_COMPANION_UI_TESTING"] = "1"
        app.launch()
        let window = app.windows["Vamp Companion"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertNotEqual(app.state, .notRunning)
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Show Vamp Companion"].click()
        XCTAssertTrue(app.windows["Vamp Companion"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.windows.matching(identifier: "Vamp Companion").count, 1)
    }
}
