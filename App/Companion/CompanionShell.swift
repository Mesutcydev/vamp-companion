import AppKit
import SwiftUI

struct CompanionShell: View {
    @EnvironmentObject private var appState: AppState
    @Bindable var navigation: CompanionNavigation

    var body: some View {
        VStack(spacing: 0) {
            CompanionHeader(selection: $navigation.destination)
            Divider()
            Group {
                switch navigation.destination {
                case .models:
                    ScrollView {
                        ModelManagerView(embedded: true).padding(20)
                    }
                    .accessibilityIdentifier("companion-models")
                case .devices:
                    CompanionDevicesView()
                case .settings:
                    CompanionSettingsView(navigation: navigation)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            CompanionRuntimeStatus(
                hostRunning: appState.remoteSessionRunning,
                hostEnabled: appState.settings.remoteSessionEnabled,
                enginePhase: appState.enginePhase,
                isWorking: appState.sessions.isRunning)
        }
        .frame(minWidth: 600, minHeight: 520)
        .background(Theme.workspaceCanvas)
        .sheet(isPresented: $navigation.showsProviders) {
            CompanionProviderSheet()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openModelManager)) { _ in
            navigation.destination = .models
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProviderSettings)) { _ in
            navigation.destination = .settings
            navigation.showsProviders = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRemoteAccess)) { _ in
            navigation.destination = .devices
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAppSettings)) { _ in
            navigation.destination = .settings
        }
    }
}

private struct CompanionHeader: View {
    @Binding var selection: CompanionDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 25))
                    .foregroundStyle(Theme.accentText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vamp Companion").font(.title2.weight(.semibold))
                    Text("Run your iPhone assistant on this Mac.")
                        .font(.callout).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                ForEach(CompanionDestination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        Label { Text(destination.title) } icon: { Image(systemName: destination.symbol) }
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.bordered)
                    .tint(selection == destination ? Theme.accent : .secondary)
                    .accessibilityIdentifier("companion-tab-\(destination.rawValue)")
                }
                Spacer()
            }
        }
        .padding(20)
    }
}

private struct CompanionRuntimeStatus: View {
    let hostRunning: Bool
    let hostEnabled: Bool
    let enginePhase: AppState.EnginePhase
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(hostRunning ? Color.green : Color.secondary).frame(width: 6, height: 6)
            Text(hostRunning ? "iPhone access ready" : hostEnabled ? "Connecting…" : "iPhone access off")
            Spacer()
            if isWorking { ProgressView().controlSize(.mini); Text("Assistant is working") }
            else {
                switch enginePhase {
                case .idle: Text("Choose a model to get started")
                case .loading(let name): Text("Loading \(name)…")
                case .ready(let name): Text(name).lineLimit(1)
                case .failed: Text("Model needs attention").foregroundStyle(.orange)
                }
            }
        }
        .font(.caption).foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

struct CompanionDevicesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = SettingsStore.shared
    @State private var setupAllowLAN = true
    @State private var copied = false
    @State private var confirmsRevocation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Pair your iPhone or iPad").font(.title3.weight(.semibold))
                Text("Open Vamp Assistant or Vamp Stream on iPhone or iPad and scan this Mac’s pairing code. The updated Vamp Stream 1.0 build 8 supports Companion QR codes. Your assistant runs here, even when this window is closed.")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !settings.remoteSessionEnabled {
                    CompanionAccessSetup(allowLAN: $setupAllowLAN) {
                        settings.remoteSessionAllowLAN = setupAllowLAN
                        settings.remoteAccessConsentCompleted = true
                        settings.remoteSessionEnabled = true
                    }
                } else {
                    Toggle("iPhone access", isOn: $settings.remoteSessionEnabled).toggleStyle(.switch)
                    Toggle("Allow trusted local Wi-Fi", isOn: $settings.remoteSessionAllowLAN)
                    if appState.remoteSessionRunning {
                        CompanionPairingCard(
                            url: appState.remotePairingURL,
                            code: appState.remotePairingCode,
                            address: appState.remoteSessionURL,
                            expires: appState.remotePairingExpiresAt,
                            networkKind: appState.remoteNetworkKind)
                        HStack {
                            Button(copied ? "Copied" : "Copy pairing link", systemImage: "link") {
                                guard let url = appState.remotePairingURL else { return }
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                                copied = true
                            }
                            .disabled(appState.remotePairingURL == nil)
                            Button("New code", systemImage: "arrow.clockwise") {
                                copied = false
                                appState.rotateRemotePairingCode()
                            }
                            Spacer()
                            Button("Revoke connections…", role: .destructive) { confirmsRevocation = true }
                                .disabled(appState.remotePairedClientCount == 0)
                        }
                        .buttonStyle(.bordered)
                        Text("\(appState.remotePairedClientCount) paired devices")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    } else if let error = appState.remoteSessionError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Button("Retry") { appState.retryRemoteSessionHost() }.buttonStyle(.bordered)
                    } else {
                        ProgressView("Starting iPhone access…")
                    }
                }
                Text("For access away from home, connect both devices to Tailscale. Clipboard, file sharing, and Mac control can be enabled separately in Settings.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(24)
        }
        .accessibilityIdentifier("companion-devices")
        .onAppear {
            if settings.remoteAccessConsentCompleted { setupAllowLAN = settings.remoteSessionAllowLAN }
        }
        .confirmationDialog("Revoke all paired devices?", isPresented: $confirmsRevocation) {
            Button("Revoke all devices", role: .destructive) { appState.revokeRemoteClients() }
        } message: {
            Text("Devices will need to scan a new pairing code. This affects only Vamp Companion.")
        }
    }
}

private struct CompanionAccessSetup: View {
    @Binding var allowLAN: Bool
    let enable: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Allow trusted local Wi-Fi", isOn: $allowLAN)
            Text(allowLAN
                 ? "Use a private Wi-Fi network you trust. A one-time pairing code is required before a device can connect."
                 : "Tailscale must be connected on both devices. A one-time pairing code is still required.")
                .font(.callout).foregroundStyle(Theme.textSecondary)
            Button("Enable iPhone access", systemImage: "qrcode", action: enable)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("companion-enable-access")
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CompanionPairingCard: View {
    let url: String?
    let code: String
    let address: String?
    let expires: Date?
    let networkKind: RemoteNetworkKind?

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            if let url { RemoteQRCodeView(value: url).frame(width: 170, height: 170) }
            VStack(alignment: .leading, spacing: 10) {
                Label(networkKind == .tailscale ? "Tailscale connected" : "Trusted local Wi-Fi",
                      systemImage: networkKind == .tailscale ? "lock.shield" : "wifi")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                Text(code).font(.system(size: 30, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                if let expires { Text("Expires \(expires, style: .relative)").font(.caption) }
                if let address {
                    Text(address).font(.caption.monospaced()).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}
