import XCTest

@MainActor
final class HomepageUITests: XCTestCase {
    override func tearDown() {
        XCUIApplication().terminate()
        super.tearDown()
    }

    func testHomeShowsRealModelStateAndOpensAReviewedPrompt() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance, state: "ready")
            XCTAssertTrue(app.staticTexts["Qwen3.5 9B"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["Models"].exists)
            capture(app, name: "homepage-\(appearance)")
            app.buttons["Plan & organize"].tap()
            let editor = app.textFields["remote.start.prompt"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            XCTAssertTrue((editor.value as? String)?.contains("to-do list") == true,
                          "Quick starts must carry their reviewed prompt into the form: \(String(describing: editor.value))")
            XCTAssertFalse(app.staticTexts["Opened conversation"].exists)
            app.buttons["Cancel"].tap()
            app.buttons["Start a new session"].tap()
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            XCTAssertEqual(editor.value as? String, "", "A cancelled quick-start prompt must not leak into New")
            app.terminate()
        }
    }

    func testWorkingHomeCanResumeTheActiveConversation() {
        let app = launch(appearance: "dark", state: "working")
        let activity = app.buttons["remote.home.activity.11111111-1111-1111-1111-111111111111"]
        XCTAssertTrue(activity.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(activity.frame.height, 44)
        capture(app, name: "homepage-working-dark")
        activity.tap()
        XCTAssertTrue(app.staticTexts["remote.home.fixture-opened"].waitForExistence(timeout: 5))
    }

    func testOfflineHomeKeepsHistoryAndDisablesStarters() {
        let app = launch(appearance: "dark", state: "offline")
        XCTAssertTrue(app.buttons["remote.home.reconnect"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Plan & organize"].isEnabled)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Ideas for the weekend")).firstMatch.exists)
        capture(app, name: "homepage-offline-dark")
    }

    private func launch(appearance: String, state: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["VAMP_REMOTE_TEST_SCREEN"] = "homepage"
        app.launchEnvironment["VAMP_REMOTE_FIXTURE"] = state
        app.launchEnvironment["VAMP_TEST_APPEARANCE"] = appearance
        app.launch()
        return app
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
