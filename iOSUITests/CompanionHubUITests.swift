import XCTest

@MainActor
final class CompanionHubUITests: XCTestCase {
    func testModelStartsFromTheMacHubAndKeepsBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            XCTAssertTrue(app.staticTexts["Vamp Companion"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["Mac control status unavailable"].exists,
                          "An older host's missing status must not report disabled Mac permissions")
            let model = app.buttons["remote.mac.model.local|fixture"]
            XCTAssertTrue(model.isEnabled)
            XCTAssertGreaterThanOrEqual(model.frame.height, 44)
            capture(app, name: "assistant-mac-hub-\(appearance)")
            model.tap()
            XCTAssertTrue(app.staticTexts["remote.mac.fixture-selection"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testOfflineHubKeepsModelsVisibleAndDisablesNewSessions() {
        let app = launch(appearance: "dark", state: "offline")
        let model = app.buttons["remote.mac.model.local|fixture"]
        XCTAssertTrue(model.waitForExistence(timeout: 15))
        XCTAssertFalse(model.isEnabled)
        XCTAssertTrue(app.staticTexts["remote.mac.connection"].label.contains("offline"))
        XCTAssertFalse(app.staticTexts["Ready to control"].exists)
        capture(app, name: "assistant-mac-hub-offline")
    }

    private func launch(appearance: String, state: String = "ready") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["VAMP_REMOTE_TEST_SCREEN"] = "mac-hub"
        app.launchEnvironment["VAMP_TEST_APPEARANCE"] = appearance
        app.launchEnvironment["VAMP_REMOTE_FIXTURE"] = state
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
