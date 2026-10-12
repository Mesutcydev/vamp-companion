import XCTest
@testable import BeetCode

@MainActor
final class CompanionBackgroundBrowserTests: XCTestCase {
    func testBrowserToolsRenderWithoutTheRemovedBrowserPanel() async throws {
        let temporary = TempWorkspace()
        let browser = BrowserController.shared
        XCTAssertNil(browser.webView.window)
        temporary.write("""
            <!doctype html><html><head><title>Companion fixture</title></head>
            <body style="margin:0;background:#203040;color:white;padding:40px">
            <h1>Companion background browser</h1></body></html>
            """, to: "fixture.html")
        try browser.open(temporary.url(for: "fixture.html").absoluteString,
                         filePolicy: .confined(temporary.workspace))
        await browser.waitForLoad(timeout: 15)
        var text = ""
        for _ in 0..<100 {
            text = (try? await browser.extractText()) ?? ""
            if text.contains("Companion background browser") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(text.contains("Companion background browser"))
        let image = try await browser.snapshot(to: temporary.url(for: "background.png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: image.path))
        XCTAssertGreaterThan((try Data(contentsOf: image)).count, 100)
        XCTAssertNil(browser.webView.window)
    }
}
