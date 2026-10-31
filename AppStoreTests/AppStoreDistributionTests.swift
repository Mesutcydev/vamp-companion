import Foundation
import XCTest
import SwiftUI
@testable import BeetCode

@MainActor
final class AppStoreDistributionTests: XCTestCase {
    func testStoreCannotEnableControlWithSavedPreferencesOrRemoteFullAccess() {
        let name = "com.beetcode.companion.storetests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults, persistentDomainName: name)
        settings.computerControlEnabled = true
        settings.remoteMacControlEnabled = true
        settings.remoteMacUnlockEnabled = true
        XCTAssertFalse(settings.computerControlEnabled)
        XCTAssertFalse(settings.remoteMacControlEnabled)
        XCTAssertFalse(settings.remoteMacUnlockEnabled)
        for chatOnly in [true, false] {
            XCTAssertTrue(AgentSessionController.sessionTools(
                computerControlEnabled: true, chatOnly: chatOnly, linuxGuest: true).isEmpty)
        }
    }

    func testOnlyBundledMLXRuntimeIsOfferedAndSparkleIsAbsent() throws {
        XCTAssertTrue(CompanionDistribution.isAppStore)
        XCTAssertFalse(ModelCatalog.all.isEmpty)
        XCTAssertTrue(ModelCatalog.all.allSatisfy { $0.format == .mlx })
        XCTAssertFalse(CompanionDistribution.supports(.gguf))
        XCTAssertFalse(CompanionDistribution.supports(.qwenStreaming))
        XCTAssertFalse(ManagedInferenceRuntime.Kind.omlx.enabled)
        XCTAssertFalse(ManagedInferenceRuntime.Kind.mlxfast.enabled)
        XCTAssertNil(Bundle.main.url(forResource: "Sparkle", withExtension: "framework", subdirectory: "Contents/Frameworks"))
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL"))
        XCTAssertNotNil(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    }

    func testWebsitePromoRendersAtMinimumWindowWidthInBothAppearances() throws {
        let previous = Theme.currentAppearance
        defer { Theme.applyAppearance(previous) }
        for (appearance, scheme) in [(AppAppearance.light, ColorScheme.light), (.dark, .dark)] {
            Theme.applyAppearance(appearance)
            let renderer = ImageRenderer(content: CompanionWebsitePromoCard()
                .padding(24).frame(width: 600)
                .background(CompanionBrand.canvas)
                .environment(\.colorScheme, scheme))
            renderer.scale = 2
            let rendered = try XCTUnwrap(renderer.nsImage)
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "website-promo-\(appearance.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testCodexExecutableCannotBeStarted() async {
        do {
            try await CodexAppServerClient().start()
            XCTFail("The App Store edition must not start an external CLI")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("website edition"))
        }
    }

    func testAuthenticatedHostRejectsRestrictedRoutesAndStillServesChatStatus() async throws {
        let engine = FakeLLMEngine()
        let controller = AgentSessionController(engine: engine, settings: SettingsStore.shared, thermal: ThermalMonitor())
        let host = RemoteSessionHost(engine: engine, sessions: controller, persistsPairedClients: false)
        var sessionStarts = 0
        host.startSessionHandler = { _, _, _ in
            sessionStarts += 1
            return .accepted(UUID())
        }
        try await host.start(port: 0, allowLAN: true)
        do {
            let port = try XCTUnwrap(host.actualPort)
            let base = URL(string: "http://127.0.0.1:\(port)")!
            let pair = try await request(base, path: "/api/pair", method: "POST",
                                         body: ["code": host.pairingCode])
            XCTAssertEqual(pair.0, 200)
            let token = try XCTUnwrap(pair.1["token"] as? String)
            for path in ["/api/control", "/api/control/terminal", "/api/control/apps/launch",
                         "/api/control/unlock", "/api/workspaces", "/api/bot-computers/fixture/exec",
                         "/api/bot-runs", "/api/bot-workflows"] {
                let unauthorized = try await request(base, path: path, method: "POST")
                XCTAssertEqual(unauthorized.0, 401, path)
                let denied = try await request(base, path: path, method: "POST", token: token)
                XCTAssertEqual(denied.0, 403, path)
                XCTAssertTrue((denied.1["error"] as? String)?.contains("website edition") == true, path)
            }
            for context in [["workspacePath": "/tmp"], ["botComputerID": UUID().uuidString], ["botProfileID": "navigator"]] {
                let payload = context.merging(["modelID": "test-model", "message": "Do work"]) { first, _ in first }
                let denied = try await request(base, path: "/api/sessions", method: "POST", token: token, body: payload)
                XCTAssertEqual(denied.0, 403)
            }
            XCTAssertEqual(sessionStarts, 0)
            let chat = try await request(base, path: "/api/sessions", method: "POST", token: token,
                                         body: ["modelID": "test-model", "message": "Hello"])
            XCTAssertEqual(chat.0, 202)
            XCTAssertEqual(sessionStarts, 1)
            let status = try await request(base, path: "/api/status", token: token)
            XCTAssertEqual(status.0, 200)
            XCTAssertEqual(status.1["protocolVersion"] as? Int, 1)
            let capabilities = try XCTUnwrap(status.1["capabilities"] as? [String])
            XCTAssertTrue(capabilities.contains("sessions"))
            XCTAssertFalse(capabilities.contains("bots"))
            XCTAssertFalse(capabilities.contains("workspaces"))
            XCTAssertEqual((status.1["macControl"] as? [String: Any])?["enabled"] as? Bool, false)
            await host.stop()
        } catch {
            await host.stop()
            throw error
        }
    }

    private func request(_ base: URL, path: String, method: String = "GET", token: String? = nil,
                         body: [String: String]? = nil) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 10
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as! HTTPURLResponse).statusCode,
                (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }
}
