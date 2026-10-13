import XCTest

@MainActor
final class ChatPolishUITests: XCTestCase {
    override func tearDown() { XCUIApplication().terminate(); super.tearDown() }

    func testCodeCopyAndBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = launch(appearance: appearance)
            let copy = app.buttons["remote.chat.copy-code"].firstMatch
            XCTAssertTrue(copy.waitForExistence(timeout: 15))
            XCTAssertGreaterThanOrEqual(copy.frame.height, 44)
            capture(app, name: "chat-polish-\(appearance)")
            copy.tap()
            XCTAssertTrue(app.buttons["Code copied"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testReuseUserMessagePreservesAnExistingDraft() {
        let app = launch(appearance: "dark")
        let editor = app.textFields["remote.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.tap(); editor.typeText("Keep this draft.")
        app.buttons["remote.hideKeyboard"].tap()
        app.scrollViews.firstMatch.swipeDown()
        let prompt = app.staticTexts["Help me turn these release notes into a clear checklist."]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.press(forDuration: 1)
        app.buttons["Use in composer"].tap()
        XCTAssertTrue((editor.value as? String)?.hasPrefix("Keep this draft.") == true)
        XCTAssertTrue((editor.value as? String)?.contains("release notes") == true)
        XCTAssertTrue(app.buttons["remote.composer.primary"].isEnabled)
    }

    func testIncomingMessageKeepsTheComposerUsable() {
        let app = launch(appearance: "light")
        let editor = app.textFields["remote.composer.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 15))
        editor.tap(); editor.typeText("Make the checklist shorter.")
        app.buttons["remote.composer.primary"].tap()
        XCTAssertTrue(app.staticTexts["Make the checklist shorter."].waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "")
        XCTAssertTrue(editor.isHittable)
        XCTAssertFalse(app.buttons["remote.composer.primary"].isEnabled)
    }

    func testToolAndReasoningDisclosuresRemainAvailable() {
        let app = launch(appearance: "dark", state: "tools")
        XCTAssertTrue(app.textFields["remote.composer.editor"].waitForExistence(timeout: 15))
        let tool = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "read file")).firstMatch
        XCTAssertTrue(tool.waitForExistence(timeout: 5))
        tool.tap()
        XCTAssertTrue(app.staticTexts["Read the current release notes.\nNo files were changed."].waitForExistence(timeout: 5))
        let reasoning = app.buttons["Show reasoning"]
        reasoning.tap()
        XCTAssertTrue(app.buttons["Hide reasoning"].waitForExistence(timeout: 5))
        capture(app, name: "chat-polish-tools-dark")
    }

    private func launch(appearance: String, state: String = "ready") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["VAMP_REMOTE_TEST_SCREEN"] = "chat-polish"
        app.launchEnvironment["VAMP_TEST_APPEARANCE"] = appearance
        app.launchEnvironment["VAMP_REMOTE_FIXTURE"] = state
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
