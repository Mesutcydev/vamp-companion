import AppKit
import SwiftUI

struct CompanionShell: View {
    @EnvironmentObject private var appState: AppState
    @Bindable var navigation: CompanionNavigation

    var body: some View {
        VStack(spacing: 0) {
            CompanionHeader(selection: $navigation.destination,
                            hostRunning: appState.remoteSessionRunning)
            Rectangle().fill(CompanionBrand.stroke).frame(height: 1)
            Group {
                switch navigation.destination {
                case .models:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            CompanionPageHeading(eyebrow: "Model library", title: "Your models. Your Mac.",
                                                 subtitle: "Download a local model or connect a provider. Run it from your iPhone.")
                            ModelManagerView(embedded: true)
                        }
                        .padding(CompanionBrand.pageInset)
                    }
                    .accessibilityIdentifier("companion-models")
                case .devices:
                    CompanionDevicesView()
                case .settings:
                    CompanionSettingsView(navigation: navigation)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Rectangle().fill(CompanionBrand.stroke).frame(height: 1)
            CompanionRuntimeStatus(
                hostRunning: appState.remoteSessionRunning,
                hostEnabled: appState.settings.remoteSessionEnabled,
                enginePhase: appState.enginePhase,
                isWorking: appState.sessions.isRunning)
        }
        .frame(minWidth: 600, minHeight: 520)
        .background(CompanionBrand.canvas)
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
    let hostRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 13) {
                CompanionBrandBadge()
                VStack(alignment: .leading, spacing: 3) {
                    Text("VAMP").font(.system(size: 27, weight: .heavy, design: .rounded))
                        .tracking(1.5).foregroundStyle(CompanionBrand.ink)
                    Text("Companion").font(.system(size: 11, weight: .medium))
                        .tracking(1.5).foregroundStyle(CompanionBrand.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Vamp Companion")
                Spacer()
                CompanionStatusPill(title: hostRunning ? "iPhone access ready" : "iPhone access off",
                                    isReady: hostRunning)
            }
            HStack(spacing: 6) {
                ForEach(CompanionDestination.allCases) { destination in
                    Button {
                        selection = destination
                    } label: {
                        Label { Text(destination.title) } icon: { Image(systemName: destination.symbol) }
                            .frame(minWidth: 72)
                    }
                    .buttonStyle(CompanionNavigationButtonStyle(isSelected: selection == destination))
                    .accessibilityAddTraits(selection == destination ? [.isSelected] : [])
                    .accessibilityIdentifier("companion-tab-\(destination.rawValue)")
                }
                Spacer()
            }
        }
        .padding(.horizontal, CompanionBrand.pageInset)
        .padding(.top, 18).padding(.bottom, 14)
        .background(CompanionBrand.canvas)
    }
}

private struct CompanionRuntimeStatus: View {
    let hostRunning: Bool
    let hostEnabled: Bool
    let enginePhase: AppState.EnginePhase
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "macbook.and.iphone").accessibilityHidden(true)
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
        .font(.system(size: 11)).foregroundStyle(CompanionBrand.secondary)
        .padding(.horizontal, CompanionBrand.pageInset).padding(.vertical, 12)
        .background(CompanionBrand.canvas)
    }
}

struct CompanionDevicesView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var settings = SettingsStore.shared
    @State private var setupAllowLAN = true
    @State private var copied = false
    @State private var confirmsRevocation = false
    @State private var pairsOverWiFi = true

    private var usesWiFi: Bool {
        pairsOverWiFi && appState.remoteLocalPairingURL != nil
    }

    private var displayedPairingURL: String? {
        usesWiFi ? appState.remoteLocalPairingURL : appState.remotePairingURL
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CompanionPageHeading(eyebrow: "Device connections", title: "Your Mac, within reach.",
                                     subtitle: "Scan the code with Vamp Assistant or App Stream on your iPhone or iPad.")
                if !settings.remoteSessionEnabled {
                    CompanionAccessSetup(allowLAN: $setupAllowLAN) {
                        settings.remoteSessionAllowLAN = setupAllowLAN
                        settings.remoteAccessConsentCompleted = true
                        settings.remoteSessionEnabled = true
                    }
                } else {
                    SettingsCard(title: "Connection", icon: "wifi") {
                        SettingToggle(label: "iPhone access", isOn: $settings.remoteSessionEnabled)
                        SettingToggle(label: "Allow trusted local Wi-Fi", isOn: $settings.remoteSessionAllowLAN)
                    }
                    if appState.remoteSessionRunning {
                        if appState.remoteNetworkKind == .tailscale,
                           appState.remoteLocalPairingURL != nil {
                            Picker("Pair over", selection: $pairsOverWiFi) {
                                Text("Local Wi-Fi").tag(true)
                                Text("Tailscale").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("companion-pairing-network")
                            .onChange(of: pairsOverWiFi) { _, _ in copied = false }
                        }
                        Text(usesWiFi
                             ? "Keep both devices on the same trusted Wi-Fi network."
                             : "Connect both devices to the same private Tailscale network. App Stream build 12 or later supports this connection.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        CompanionPairingCard(
                            url: displayedPairingURL,
                            code: appState.remotePairingCode,
                            address: usesWiFi ? appState.remoteLocalSessionURL : appState.remoteSessionURL,
                            expires: appState.remotePairingExpiresAt,
                            networkKind: usesWiFi ? .localNetwork : appState.remoteNetworkKind)
                        HStack {
                            Button(copied ? "Copied" : "Copy pairing link", systemImage: "link") {
                                guard let url = displayedPairingURL else { return }
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                                copied = true
                            }
                            .disabled(displayedPairingURL == nil)
                            Button("New code", systemImage: "arrow.clockwise") {
                                copied = false
                                appState.rotateRemotePairingCode()
                            }
                            Spacer()
                            Button("Revoke connections…", role: .destructive) { confirmsRevocation = true }
                                .disabled(appState.remotePairedClientCount == 0)
                        }
                        .buttonStyle(.bordered)
                        Label("\(appState.remotePairedClientCount) paired devices", systemImage: "checkmark.shield")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    } else if let error = appState.remoteSessionError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        Button("Retry") { appState.retryRemoteSessionHost() }.buttonStyle(.bordered)
                    } else {
                        ProgressView("Starting iPhone access…")
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(CompanionBrand.accentInk)
                    Text("Your assistant keeps running when this window is closed. Choose clipboard, file sharing, and Mac control access in Settings.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).companionCard()
            }.padding(CompanionBrand.pageInset)
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
        .companionCard()
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
            if let url {
                RemoteQRCodeView(value: url).frame(width: 150, height: 150)
                    .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(networkKind == .tailscale ? "Tailscale connected" : "Trusted local Wi-Fi",
                      systemImage: networkKind == .tailscale ? "lock.shield" : "wifi")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(CompanionBrand.secondary)
                Text("Pairing code").font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase).tracking(1.2).foregroundStyle(CompanionBrand.secondary)
                Text(code).font(.system(size: 34, weight: .medium, design: .monospaced))
                    .tracking(3).foregroundStyle(CompanionBrand.ink)
                    .textSelection(.enabled)
                if let expires { Text("Expires \(expires, style: .relative)").font(.caption) }
                if let address {
                    Text(address).font(.caption.monospaced()).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .companionCard()
    }
}
