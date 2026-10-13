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
        XCTAssertTrue(app.descendants(matching: .any)["companion-devices"].firstMatch.waitForExistence(timeout: 10))
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
        let window = app.windows["companion"]
        XCTAssertTrue(window.waitForExistence(timeout: 30))
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertNotEqual(app.state, .notRunning)
        app.menuBars.menuBarItems["File"].click()
        app.menuItems["Show Vamp Companion"].click()
        XCTAssertTrue(app.windows["companion"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.windows.matching(identifier: "companion").count, 1)
    }

    func testEmptyLibraryOpensDiscoverAndBothAppearancesKeepNavigation() {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("vamp-companion-ui-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        for appearance in ["light", "dark"] {
            let app = XCUIApplication()
            app.launchEnvironment["VAMP_COMPANION_UI_TESTING"] = "1"
            app.launchEnvironment["VAMP_COMPANION_TEST_APPEARANCE"] = appearance
            app.launchEnvironment["VAMP_COMPANION_UI_MODEL_ROOT"] = fixture.path
            app.launch()
            app.buttons["companion-tab-models"].click()
            let discover = app.buttons["companion-discover-models"]
            if !discover.exists {
                app.scrollViews["companion-models"].scroll(byDeltaX: 0, deltaY: -250)
            }
            XCTAssertTrue(discover.waitForExistence(timeout: 30))
            saveScreenshot(app, name: "\(appearance)-models")
            discover.click()
            XCTAssertTrue(app.staticTexts["Recommended for this Mac"].firstMatch.waitForExistence(timeout: 15))
            app.buttons["companion-tab-devices"].click()
            XCTAssertTrue(app.descendants(matching: .any)["companion-devices"].firstMatch.waitForExistence(timeout: 10))
            saveScreenshot(app, name: "\(appearance)-devices")
            app.buttons["companion-tab-settings"].click()
            XCTAssertTrue(app.buttons["companion-manage-providers"].waitForExistence(timeout: 10))
            saveScreenshot(app, name: "\(appearance)-settings")
            app.terminate()
        }
    }

    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.windows["companion"].screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAssistantModelIsAvailableWithoutDownloadAndHidingKeepsItsFiles() throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("vamp-companion-shared-ui-\(UUID().uuidString)", isDirectory: true)
        defer {
            if FileManager.default.fileExists(atPath: fixture.path) {
                try? FileManager.default.removeItem(at: fixture)
            }
        }
        let own = fixture.appendingPathComponent("VampCompanion/Models", isDirectory: true)
        let assistant = fixture.appendingPathComponent("BeetCode", isDirectory: true)
        let weights = assistant.appendingPathComponent("Models/shared-ui-fixture/model.gguf")
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: weights.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture weights".utf8).write(to: weights)
        let app = XCUIApplication()
        app.launchEnvironment["VAMP_COMPANION_UI_TESTING"] = "1"
        app.launchEnvironment["VAMP_COMPANION_UI_MODEL_ROOT"] = own.path
        app.launchEnvironment["VAMP_COMPANION_UI_ASSISTANT_ROOT"] = assistant.path
        app.launch()
        defer { app.terminate() }
        app.buttons["companion-tab-models"].click()
        let row = app.descendants(matching: .any)["companion-model-row-shared-ui-fixture"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@",
            "Shared with Vamp Assistant", "Shared with Vamp Assistant")).firstMatch.exists)
        XCTAssertTrue(app.buttons["Load"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Download"].exists)
        saveScreenshot(app, name: "assistant-shared-model")
        app.descendants(matching: .any)["More actions for shared ui fixture"].firstMatch.click()
        app.menuItems["Hide from Companion…"].click()
        XCTAssertTrue(app.buttons["Hide"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Hide"].firstMatch.click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: weights.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: own.appendingPathComponent("shared-ui-fixture").path))
    }
}
