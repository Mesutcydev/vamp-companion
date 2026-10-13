import AppKit
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class CompanionLoginItem {
    static let shared = CompanionLoginItem()
    private(set) var enabled = false
    private(set) var requiresApproval = false
    private(set) var errorMessage: String?

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
        requiresApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        refresh()
    }
}

struct CompanionSettingsView: View {
    let navigation: CompanionNavigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CompanionPageHeading(eyebrow: "Preferences", title: "Make it yours.",
                                     subtitle: "Connect your providers and choose what paired devices can access.")
                CompanionGeneralSettings()
                SettingsCard(title: "Connections", icon: "key") {
                    Text("Set up API providers here or from Settings in the paired iOS app.")
                        .font(.callout).foregroundStyle(Theme.textSecondary)
                    Button("Manage API providers and accounts…") { navigation.showsProviders = true }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("companion-manage-providers")
                }
                HuggingFaceProviderCard()
                CompanionPermissionsSettings()
                AppUpdateSettings()
            }.padding(CompanionBrand.pageInset)
        }
        .accessibilityIdentifier("companion-settings")
    }
}

private struct CompanionGeneralSettings: View {
    @ObservedObject private var settings = SettingsStore.shared
    private let loginItem = CompanionLoginItem.shared

    var body: some View {
        SettingsCard(title: "General", icon: "gearshape") {
            SettingRow(label: "Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    Text("System").tag(AppAppearance.system)
                    Text("Light").tag(AppAppearance.light)
                    Text("Dark").tag(AppAppearance.dark)
                }.labelsHidden().frame(width: 160)
            }
            SettingToggle(label: "Launch at login", isOn: Binding(
                get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
            if loginItem.requiresApproval {
                Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = loginItem.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            SettingToggle(label: "Resume interrupted downloads", isOn: Binding(
                get: { AppPreferencesStore.shared.current.autoResumeDownloads },
                set: { value in
                    var preferences = AppPreferencesStore.shared.current
                    preferences.autoResumeDownloads = value
                    AppPreferencesStore.shared.save(preferences)
                }))
            Text("Closing the window keeps the companion running. Use Quit to stop it.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }
}

struct CompanionPermissionsSettings: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = SettingsStore.shared
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false
    @State private var requestedScreenRecording = false

    var body: some View {
        SettingsCard(title: "Sharing & control", icon: "hand.raised",
                     footer: "Permissions apply only to Vamp Companion. Enable the access you want to grant to paired devices.") {
            SettingToggle(label: "Clipboard exchange", isOn: $settings.remoteClipboardSharingEnabled)
            SettingToggle(label: "File transfer", isOn: $settings.remoteFileSharingEnabled)
            SettingToggle(label: "Assistant computer-use tools", isOn: $settings.computerControlEnabled)
            SettingToggle(label: "Mac control from iPhone", isOn: $settings.remoteMacControlEnabled)
                .onChange(of: settings.remoteMacControlEnabled) { _, value in
                    if !value { appState.remoteSessionHost.disableMacControl() }
                }
            if settings.remoteMacControlEnabled || settings.computerControlEnabled {
                CompanionPermissionRow(title: "Accessibility", granted: accessibilityGranted, needsRelaunch: false) {
                    ComputerPermission.requestAccessibility()
                }
                CompanionPermissionRow(title: "Screen Recording", granted: screenRecordingGranted,
                                       needsRelaunch: requestedScreenRecording) {
                    ComputerPermission.requestScreenRecording()
                    requestedScreenRecording = true
                }
            }
            if settings.remoteMacControlEnabled {
                SettingToggle(label: "Remote unlock over Tailscale", isOn: $settings.remoteMacUnlockEnabled)
                Text("Remote unlock requires Tailscale. Submitted passwords are never stored.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func refreshPermissions() {
        accessibilityGranted = ComputerPermission.accessibilityGranted
        screenRecordingGranted = ComputerPermission.screenRecordingGranted
    }
}

private struct CompanionPermissionRow: View {
    let title: LocalizedStringResource
    let granted: Bool
    let needsRelaunch: Bool
    let grant: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if granted { Text("Granted").foregroundStyle(Theme.textSecondary) }
            else if needsRelaunch { Text("Quit and reopen to finish").foregroundStyle(.orange) }
            else { Button("Grant…", action: grant).buttonStyle(.bordered) }
        }.font(.callout)
    }
}

struct CompanionProviderSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CompanionBrandBadge(size: 32)
                Text("API providers & accounts").font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                ProvidersTab(includesSafetyOptions: false)
                    .padding(20)
            }
        }
        .frame(width: 660, height: 580)
        .background(CompanionBrand.canvas)
    }
}
