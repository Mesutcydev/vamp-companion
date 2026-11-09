import AppKit
import SwiftUI

struct CompanionShell: View {
    @EnvironmentObject private var appState: AppState
    @Bindable var navigation: CompanionNavigation

    var body: some View {
        VStack(spacing: 0) {
            if appState.sessionStorageLocked {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill").foregroundStyle(CompanionBrand.accentInk)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conversations are locked").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CompanionBrand.ink)
                        Text("iPhone can't start sessions until macOS allows the session key. Choose Always Allow when asked.")
                            .font(.system(size: 12)).foregroundStyle(CompanionBrand.secondary)
                    }
                    Spacer()
                    Button("Unlock") {
                        appState.sessionStorageLocked = !SessionCrypto.unlockInteractively()
                    }
                    .buttonStyle(CompanionArcadeButtonStyle(primary: true))
                    .accessibilityIdentifier("companion-unlock-sessions")
                }
                .padding(.horizontal, CompanionBrand.pageInset).padding(.vertical, 10)
                .background(CompanionBrand.surface)
                Rectangle().fill(CompanionBrand.stroke).frame(height: 1)
            }
            Group {
                switch navigation.destination {
                case .models:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            CompanionPageHeading(title: "Models",
                                                 subtitle: "Download a local model or connect a provider, then use it from your iPhone.")
                            if CompanionDistribution.isAppStore { CompanionWebsitePromoCard() }
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
            Rectangle().fill(CompanionBrand.stroke.opacity(0.6)).frame(height: 0.5)
            CompanionRuntimeStatus(enginePhase: appState.enginePhase, isWorking: appState.sessions.isRunning)
        }
        .frame(minWidth: 600, minHeight: 520)
        .background(CompanionBrand.canvas)
        // One compact bar, as the iPhone app's: logo, the three places, and
        // whether your iPhone can reach this Mac.
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    CompanionBrandBadge(size: 26)
                    Text("VAMP").font(CompanionBrand.wordmark(22)).tracking(1.2)
                        .foregroundStyle(CompanionBrand.ink)
                }
                .padding(.leading, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Vamp Companion")
            }
            .companionBareToolbarItem()
            ToolbarItem(placement: .principal) {
                CompanionSegments(selection: $navigation.destination, segments: CompanionDestination.allCases.map {
                    CompanionSegment(title: $0.title, symbol: $0.symbol, value: $0, identifier: "companion-tab-\($0.rawValue)")
                }, inToolbar: true)
            }
            ToolbarItem(placement: .primaryAction) {
                CompanionStatusPill(
                    title: appState.remoteSessionRunning ? "iPhone access ready"
                        : appState.settings.remoteSessionEnabled ? "Connecting…" : "iPhone access off",
                    isReady: appState.remoteSessionRunning,
                    isConnecting: !appState.remoteSessionRunning && appState.settings.remoteSessionEnabled)
            }
        }
        .task { appState.sessionStorageLocked = !SessionCrypto.isAvailable }
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

/// The model and whether the assistant is working, with the live dot the
/// iPhone app uses for the same state.
private struct CompanionRuntimeStatus: View {
    let enginePhase: AppState.EnginePhase
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 8) {
            switch enginePhase {
            case .idle:
                Image(systemName: "cpu").accessibilityHidden(true)
                Text("Choose a model to get started")
            case .loading(let name):
                ProgressView().controlSize(.mini)
                Text("Loading \(name)…")
            case .ready(let name):
                CompanionLivePulse(color: CompanionBrand.green, active: true)
                Text(name).lineLimit(1).foregroundStyle(CompanionBrand.ink)
                Text("Loaded").foregroundStyle(CompanionBrand.secondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
                Text("Model needs attention").foregroundStyle(CompanionBrand.accentInk)
            }
            Spacer()
            if isWorking {
                CompanionLivePulse(color: CompanionBrand.accentInk, active: true, fast: true)
                Text("Assistant is working").foregroundStyle(CompanionBrand.accentInk)
            }
        }
        .font(.system(size: 12)).foregroundStyle(CompanionBrand.secondary)
        .padding(.horizontal, CompanionBrand.pageInset).frame(height: 34)
        .background(CompanionBrand.canvas)
        .accessibilityElement(children: .combine)
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
                CompanionPageHeading(title: "Devices",
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
                            .font(.system(size: 13)).foregroundStyle(CompanionBrand.secondary)
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
                            .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                    } else if let error = appState.remoteSessionError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(CompanionBrand.accentInk)
                            Button("Retry") { appState.retryRemoteSessionHost() }.buttonStyle(CompanionArcadeButtonStyle())
                    } else {
                        ProgressView("Starting iPhone access…")
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(CompanionBrand.accentInk)
                    Text(CompanionDistribution.isAppStore
                         ? "Your assistant keeps running when this window is closed. Choose clipboard and file sharing access in Settings."
                         : "Your assistant keeps running when this window is closed. Choose clipboard, file sharing, and Mac control access in Settings.")
                        .font(.system(size: 13)).foregroundStyle(CompanionBrand.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
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
                .font(.system(size: 14)).foregroundStyle(CompanionBrand.secondary)
            Button("Enable iPhone access", systemImage: "qrcode", action: enable)
                .buttonStyle(CompanionArcadeButtonStyle(primary: true))
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
                    .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(networkKind == .tailscale ? "Tailscale connected" : "Trusted local Wi-Fi",
                      systemImage: networkKind == .tailscale ? "lock.shield" : "wifi")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(CompanionBrand.secondary)
                Text("Pairing code").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CompanionBrand.secondary)
                Text(code).font(.system(size: 34, weight: .medium, design: .monospaced))
                    .tracking(3).foregroundStyle(CompanionBrand.ink)
                    .textSelection(.enabled)
                if let expires { Text("Expires \(expires, style: .relative)").font(.system(size: 13)) }
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
