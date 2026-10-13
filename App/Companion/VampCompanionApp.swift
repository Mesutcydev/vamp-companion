import AppKit
import Observation
import SwiftUI

enum CompanionDestination: String, CaseIterable, Identifiable {
    case models, devices, settings
    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .models: "Models"
        case .devices: "Devices"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .models: "square.stack.3d.up"
        case .devices: "iphone"
        case .settings: "gearshape"
        }
    }
}

@MainActor
@Observable
final class CompanionNavigation {
    static let shared = CompanionNavigation()
    var destination = CompanionDestination.models
    var showsProviders = false
}

extension Notification.Name {
    static let openCompanionWindow = Notification.Name("com.beetcode.companion.openWindow")
}

@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppUpdater.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = sender.windows.first(where: { $0.title == "Vamp Companion" }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            NotificationCenter.default.post(name: .openCompanionWindow, object: nil)
        }
        sender.activate(ignoringOtherApps: true)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Only processes registered by this companion process are terminated.
        ChildProcessRegistry.terminateAll()
    }
}

@main
struct VampCompanionApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) private var appDelegate
    // The existing runtime lives with the application, not with any window.
    @StateObject private var appState = AppState()
    @ObservedObject private var settings = SettingsStore.shared
    @State private var navigation = CompanionNavigation.shared

    private var displayAppearance: AppAppearance {
        // CI screenshots exercise both appearances without modifying anyone's
        // saved preferences. This override exists only in the test host.
        if AppState.isTestHost,
           let value = ProcessInfo.processInfo.environment["VAMP_COMPANION_TEST_APPEARANCE"],
           let appearance = AppAppearance(rawValue: value) { return appearance }
        return settings.appearance
    }

    var body: some Scene {
        Window("Vamp Companion", id: "companion") {
            CompanionShell(navigation: navigation)
                .environmentObject(appState)
                .environmentObject(appState.sessions)
                .tint(Theme.accent)
                .preferredColorScheme(displayAppearance.colorScheme)
                .onChange(of: displayAppearance, initial: true) { _, appearance in
                    Theme.applyAppearance(appearance)
                }
                .modifier(ThemeSync(palette: settings.accentPalette,
                                    typeface: settings.typeface,
                                    textSize: settings.textSize))
        }
        .defaultSize(width: 780, height: 680)
        .windowResizability(.contentMinSize)
        .commands { CompanionCommands(navigation: navigation) }

        MenuBarExtra {
            CompanionMenu(navigation: navigation)
                .environmentObject(appState)
        } label: {
            CompanionMenuLabel()
        }
    }
}

private struct CompanionMenuLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        CompanionVampMark()
            .fill(.primary, style: FillStyle(eoFill: true))
            .frame(width: 20, height: 20)
            .accessibilityLabel("Vamp Companion")
            .onReceive(NotificationCenter.default.publisher(for: .openCompanionWindow)) { _ in
                openWindow(id: "companion")
            }
    }
}

private struct CompanionCommands: Commands {
    let navigation: CompanionNavigation
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) { CheckForUpdatesButton() }
        CommandGroup(replacing: .newItem) {
            Button("Show Vamp Companion") { show(.models) }
                .keyboardShortcut("n", modifiers: .command)
            Button("Models") { show(.models) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Devices") { show(.devices) }
                .keyboardShortcut("2", modifiers: .command)
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { show(.settings) }
                .keyboardShortcut(",", modifiers: .command)
        }
    }

    private func show(_ destination: CompanionDestination) {
        navigation.destination = destination
        openWindow(id: "companion")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct CompanionMenu: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    let navigation: CompanionNavigation

    var body: some View {
        Text("Vamp Companion")
        Text(appState.remoteSessionRunning ? "iPhone access ready" : "iPhone access offline")
        switch appState.enginePhase {
        case .idle: Text("No model loaded")
        case .loading(let name): Text("Loading \(name)…")
        case .ready(let name): Text(name)
        case .failed: Text("Model needs attention")
        }
        if appState.sessions.isRunning { Text("Assistant is working") }
        Divider()
        ForEach(CompanionDestination.allCases) { destination in
            Button {
                navigation.destination = destination
                openWindow(id: "companion")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label { Text(destination.title) } icon: { Image(systemName: destination.symbol) }
            }
        }
        Divider()
        CheckForUpdatesButton()
        Button("Quit Vamp Companion") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
