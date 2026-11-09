import XCTest

@MainActor
final class SecondaryPagesUITests: XCTestCase {
    func testBotLaunchesStayDisabledDuringARejectedRequestAndPreserveDrafts() {
        for (page, fieldID, actionTitle, errorTitle) in [
            ("bot-detail", "remote.bot.runPrompt", "Start run", "Couldn't start bot"),
            ("bots", "remote.bot.workflowPrompt", "Orchestrate", "Couldn't start workflow")
        ] {
            let app = launch(page, appearance: "dark", delayMutation: true)
            if page == "bot-detail" {
                XCTAssertTrue(app.buttons["Run"].waitForExistence(timeout: 15))
                app.buttons["Run"].tap()
            }
            let field = app.descendants(matching: .any).matching(identifier: fieldID).firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 15))
            reveal(field, in: app)
            field.tap()
            field.typeText("Keep this fixture draft")
            let hide = app.buttons["remote.hideKeyboard"]
            if hide.waitForExistence(timeout: 3) { hide.tap() }
            let action = app.buttons[actionTitle]
            reveal(action, in: app)
            XCTAssertTrue(action.isEnabled)
            action.tap()
            XCTAssertFalse(action.isEnabled, "Repeated taps must not submit another launch")
            app.buttons["remote.fixture.rejectMutation"].tap()
            let error = app.alerts[errorTitle]
            XCTAssertTrue(error.waitForExistence(timeout: 15), "The visible menu must present the failure")
            error.buttons["OK"].tap()
            XCTAssertEqual(field.value as? String, "Keep this fixture draft")
            XCTAssertTrue(action.isEnabled, "A failed request must allow a deliberate retry")
            capture(app, "rejected-\(page)-dark")
            app.terminate()
        }
    }

    func testStoreEditionMacOffersChatWithoutFolderOrBotErrors() {
        let app = launch("new-session", appearance: "dark", state: "store-edition")
        let prompt = app.descendants(matching: .any).matching(identifier: "remote.start.prompt").firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["remote.start.options"].waitForExistence(timeout: 5), "Permissions stay in the chat")
        XCTAssertFalse(app.buttons["Code"].exists, "The App Store Mac edition cannot open folders")
        XCTAssertFalse(app.staticTexts["Bot"].exists, "The App Store Mac edition has no bots")
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 3), "Refused routes must not raise alerts")
        capture(app, "new-session-store-edition-dark")
        app.terminate()
    }

    func testNewSessionKeepsARejectedDraftAndPreventsRepeatedStarts() {
        let app = launch("new-session", appearance: "light", delayMutation: true)
        let prompt = app.descendants(matching: .any).matching(identifier: "remote.start.prompt").firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        app.buttons["Chat"].tap()
        prompt.tap()
        prompt.typeText("Keep my reviewed message")
        if app.buttons["remote.hideKeyboard"].waitForExistence(timeout: 3) {
            app.buttons["remote.hideKeyboard"].tap()
        }
        let start = app.buttons["remote.start.submit"]
        XCTAssertTrue(start.isEnabled)
        start.tap()
        XCTAssertFalse(start.isEnabled)
        app.buttons["remote.fixture.rejectMutation"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 15))
        app.alerts.firstMatch.buttons["OK"].tap()
        XCTAssertEqual(prompt.value as? String, "Keep my reviewed message")
        XCTAssertTrue(start.isEnabled)
        capture(app, "new-session-rejected-light")
        app.terminate()
    }

    func testCachedBotApprovalAndConsoleSubmissionAreDisabledOffline() {
        let bots = launch("bot-detail", appearance: "dark", state: "offline")
        XCTAssertTrue(bots.buttons["Approve"].waitForExistence(timeout: 15))
        XCTAssertFalse(bots.buttons["Approve"].isEnabled)
        XCTAssertFalse(bots.buttons["Decline"].isEnabled)
        XCTAssertGreaterThanOrEqual(bots.buttons["Decline"].frame.height, 44)
        XCTAssertFalse(bots.buttons["Start a chat"].isEnabled)
        capture(bots, "cached-bot-offline-dark")
        bots.terminate()

        let console = launch("console", appearance: "dark", state: "offline")
        let command = console.textFields["remote.bot.command"]
        XCTAssertTrue(command.waitForExistence(timeout: 15))
        command.tap()
        command.typeText("ls -la\n")
        XCTAssertTrue(console.staticTexts["Reconnect to your Mac before running a command."].waitForExistence(timeout: 5))
        XCTAssertEqual(command.value as? String, "ls -la", "Keyboard submit must preserve a command while offline")
        XCTAssertFalse(console.buttons["remote.bot.runCommand"].isEnabled)
        capture(console, "console-offline-dark")
    }

    func testCachedProviderShowsOfflineStateAndCannotChangeCredentials() {
        let app = launch("providers", appearance: "light", state: "offline")
        let openAI = app.buttons.containing(.staticText, identifier: "OpenAI").firstMatch
        XCTAssertTrue(openAI.waitForExistence(timeout: 15))
        openAI.tap()
        XCTAssertTrue(app.staticTexts["Mac offline"].waitForExistence(timeout: 5))
        let key = app.secureTextFields["Replacement API key"]
        key.tap()
        key.typeText("fixture-only-not-a-credential")
        XCTAssertFalse(app.buttons["Replace key"].isEnabled)
        XCTAssertFalse(app.buttons["Remove key"].isEnabled)
        XCTAssertGreaterThanOrEqual(app.buttons["Remove key"].frame.height, 44)
        capture(app, "provider-offline-light")
    }

    func testHomeSettingsDismissesBeforeOpeningComputerAndDiagnostics() {
        let app = launch("homepage", appearance: "light")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 15))
        app.buttons["Settings"].tap()
        let computers = app.buttons.containing(.staticText, identifier: "Switch computer").firstMatch
        reveal(computers, in: app)
        computers.tap()
        XCTAssertTrue(app.staticTexts["Your Macs"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        app.buttons["Settings"].tap()
        let diagnostics = app.buttons.containing(.staticText, identifier: "Control diagnostics").firstMatch
        reveal(diagnostics, in: app)
        diagnostics.tap()
        XCTAssertTrue(app.navigationBars["Control Diagnostics"].waitForExistence(timeout: 10))
        capture(app, "settings-to-diagnostics-light")
    }

    func testSettingsAndProviderSetupInBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = launch("settings", appearance: appearance)
            XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["System"].exists)
            XCTAssertGreaterThanOrEqual(app.buttons["Light"].frame.height, 44)
            capture(app, "settings-\(appearance)")
            let providers = app.buttons.containing(.staticText, identifier: "API providers").firstMatch
            reveal(providers, in: app)
            providers.tap()
            XCTAssertTrue(app.staticTexts["Connected intelligence"].waitForExistence(timeout: 5))
            let openAI = app.buttons.containing(.staticText, identifier: "OpenAI").firstMatch
            XCTAssertTrue(openAI.waitForExistence(timeout: 10))
            openAI.tap()
            XCTAssertTrue(app.secureTextFields["API key"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["Save key"].isEnabled, "An empty credential must not be submitted")
            capture(app, "provider-setup-\(appearance)")
            app.terminate()
        }
    }

    func testBotRosterOpensBothChatAndRunWithoutStartingWork() {
        let app = launch("bots", appearance: "dark")
        XCTAssertTrue(app.staticTexts["Your team"].waitForExistence(timeout: 15))
        capture(app, "bots-dark")
        let builder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Builder")).firstMatch
        XCTAssertTrue(builder.exists)
        XCTAssertGreaterThanOrEqual(builder.frame.height, 44)
        builder.tap()
        XCTAssertTrue(app.buttons["Start a chat"].waitForExistence(timeout: 5))
        capture(app, "bot-chat-dark")
        app.buttons["Run"].tap()
        XCTAssertTrue(app.buttons["Start run"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start run"].isEnabled, "Opening Run must not start an empty task")
        capture(app, "bot-run-dark")
    }

    func testOfflineSharingDisablesTransfersAndComputersStayReachable() {
        let app = launch("share", appearance: "light", state: "offline")
        let upload = app.buttons["Send a file to Mac"]
        XCTAssertTrue(upload.waitForExistence(timeout: 15))
        XCTAssertFalse(upload.isEnabled)
        XCTAssertFalse(app.buttons["Paste from Mac"].isEnabled)
        capture(app, "share-offline-light")
        app.terminate()
        let computers = launch("computers", appearance: "light", state: "offline")
        XCTAssertTrue(computers.staticTexts["Your Macs"].waitForExistence(timeout: 15))
        XCTAssertTrue(computers.buttons["Pair another computer"].isEnabled)
        capture(computers, "computers-offline-light")
    }

    func testSecondaryPagesWithAccessibilityText() {
        let app = launch("settings", appearance: "dark", largeText: true)
        XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 15))
        let dark = app.buttons["Dark"]
        reveal(dark, in: app)
        XCTAssertGreaterThanOrEqual(dark.frame.height, 44)
        capture(app, "settings-accessibility-dark")
        let switchComputer = app.buttons.containing(.staticText, identifier: "Switch computer").firstMatch
        reveal(switchComputer, in: app)
        XCTAssertGreaterThanOrEqual(switchComputer.frame.height, 44)
        capture(app, "settings-accessibility-actions-dark")
        app.terminate()
        let bots = launch("bot-detail", appearance: "dark", state: "offline", largeText: true)
        let decline = bots.buttons["Decline"]
        XCTAssertTrue(decline.waitForExistence(timeout: 15))
        reveal(decline, in: bots)
        XCTAssertGreaterThanOrEqual(decline.frame.height, 44)
        XCTAssertLessThanOrEqual(decline.frame.maxX, bots.frame.maxX)
        XCTAssertFalse(decline.isEnabled)
        capture(bots, "bot-controls-accessibility-dark")
    }

    private func launch(_ page: String, appearance: String, state: String = "ready", largeText: Bool = false, delayMutation: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["VAMP_REMOTE_TEST_SCREEN"] = page == "homepage" ? page : "secondary-\(page)"
        if delayMutation { app.launchEnvironment["VAMP_SECONDARY_DELAY_MUTATION"] = "1" }
        app.launchEnvironment["VAMP_TEST_APPEARANCE"] = appearance
        app.launchEnvironment["VAMP_REMOTE_FIXTURE"] = state
        if largeText {
            app.launchEnvironment["VAMP_SECONDARY_LARGE_TEXT"] = "1"
        }
        app.launch()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "secondary-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
