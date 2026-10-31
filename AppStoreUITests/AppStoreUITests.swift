import XCTest

@MainActor
final class AppStoreUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testWebsitePromoAndStoreCapabilitiesInBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["VAMP_COMPANION_UI_TESTING"] = "1"
            app.launchEnvironment["VAMP_COMPANION_TEST_APPEARANCE"] = appearance
            app.launch()
            XCTAssertTrue(app.buttons["companion-tab-models"].waitForExistence(timeout: 30))
            XCTAssertTrue(app.staticTexts["The unrestricted Mac edition"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["companion-website-edition-link"].firstMatch.exists)
            capture(app, name: "appstore-\(appearance)-models")
            app.buttons["companion-tab-settings"].click()
            XCTAssertTrue(app.staticTexts["The unrestricted Mac edition"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any)["companion-website-edition-link"].firstMatch.exists)
            XCTAssertFalse(app.checkBoxes["Mac control from iPhone"].exists)
            XCTAssertFalse(app.checkBoxes["Assistant computer-use tools"].exists)
            capture(app, name: "appstore-\(appearance)-settings")
            let settings = app.scrollViews.firstMatch
            settings.scroll(byDeltaX: 0, deltaY: -900)
            XCTAssertTrue(app.staticTexts["Updates are delivered by the Mac App Store."].exists)
            app.buttons["companion-tab-devices"].click()
            XCTAssertTrue(app.descendants(matching: .any)["companion-devices"].firstMatch.waitForExistence(timeout: 10))
            capture(app, name: "appstore-\(appearance)-devices")
            app.terminate()
        }
    }

    func testWindowCloseKeepsHostAvailableAndReopensOneWindow() {
        let app = XCUIApplication()
        app.launchEnvironment["VAMP_COMPANION_UI_TESTING"] = "1"
        app.launch()
        let window = app.windows["companion"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertNotEqual(app.state, .notRunning)
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Show Vamp Companion"].click()
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertEqual(app.windows.matching(identifier: "companion").count, 1)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows["companion"].screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
