import SwiftUI

// MARK: - Settings

struct RemoteAppVersion: Equatable, Sendable {
  let version: String
  let build: String

  static let current: RemoteAppVersion = {
    let info = Bundle.main.infoDictionary
    return RemoteAppVersion(
      version: info?["CFBundleShortVersionString"] as? String ?? "—",
      build: info?["CFBundleVersion"] as? String ?? "—")
  }()
}

struct RemoteAppVersionFooter: View {
  @Environment(\.remoteAppearance) private var appearance
  let version: String
  let build: String

  var body: some View {
    Text(
      "Version \(version) • Build \(build)",
      comment: "App version followed by the internal build number on the pairing screen."
    )
    .font(.caption.monospacedDigit())
    .foregroundStyle(BeetTheme.secondaryText(appearance))
    .accessibilityLabel("Vamp Companion version \(version), build \(build)")
  }
}

/// One destination for everything that was scattered across the header, the
/// toolbar, and an overflow menu: theme, the paired Mac, and diagnostics.
struct RemoteSettingsSheet: View {
  @Bindable var store: RemoteStore
  var onSwitchComputer: () -> Void
  var onDiagnostics: () -> Void

  @Environment(\.dismiss) private var dismiss
  @AppStorage("remoteAppearanceSetting") private var appearanceSetting = RemoteAppearanceSetting
    .dark
  @AppStorage("remoteAccent") private var accent = AccentPalette.beetRed
  @State private var showForgetMac = false
  @State private var showOfflineForget = false

  var body: some View {
    NavigationStack {
      RemotePageScroll {
        RemotePageHeading(title: "Make it yours", subtitle: "Appearance, your paired Mac, and connected accounts.")
        RemoteSettingsIdentity(version: RemoteAppVersion.current)
        RemoteSettingsAppearance(appearanceSetting: $appearanceSetting, accent: $accent)
        RemotePageSection(title: "Paired Mac", padding: 0) {
          HStack(spacing: 12) {
            RemotePageSymbol(symbol: "desktopcomputer.and.macbook", active: store.isConnected)
            VStack(alignment: .leading, spacing: 4) {
              Text(store.activeComputerName).font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
              Text(store.isConnected ? store.connectionSubtitle : store.connectionLabel)
                .font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
              RemotePageBadge(title: store.isConnected ? "Connected" : "Offline",
                color: store.isConnected ? RemoteInstrument.green : RemoteInstrument.secondaryInk)
            }
          }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
          RemotePageDivider().padding(.leading, 66)
          Button {
            dismiss()
            onSwitchComputer()
          } label: {
            RemotePageRowLabel(title: "Switch computer", symbol: "desktopcomputer.and.macbook")
          }.buttonStyle(RemotePageRowButtonStyle())
          RemotePageDivider().padding(.leading, 66)
          Button {
            dismiss()
            onDiagnostics()
          } label: {
            RemotePageRowLabel(title: "Control diagnostics", symbol: "stethoscope")
          }.buttonStyle(RemotePageRowButtonStyle())
          RemotePageDivider().padding(.leading, 66)
          Button(role: .destructive) { showForgetMac = true } label: {
            Label("Forget this Mac", systemImage: "trash")
              .font(.subheadline).foregroundStyle(RemoteInstrument.danger)
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(14)
          }.buttonStyle(RemotePageRowButtonStyle())
        }
        RemotePageSection(title: "Connections", padding: 0) {
          NavigationLink { RemoteProvidersView(store: store) } label: {
            RemotePageRowLabel(title: "API providers", symbol: "key.horizontal", subtitle: "Keys and model access on your Mac")
          }.buttonStyle(RemotePageRowButtonStyle())
        }
        RemotePageSection(title: "About") {
          RemoteSettingValue(title: "Product", value: "Vamp Companion")
          RemoteSettingValue(title: "Platform", value: "iPhone and iPad")
          RemoteSettingValue(title: "Version", value: RemoteAppVersion.current.version)
          RemoteSettingValue(title: "Build", value: RemoteAppVersion.current.build)
        }
      }
      .navigationTitle("Settings")
      .remotePageChrome()
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
          .vampUtilityAction()
      }
      .confirmationDialog(
        "Forget this Mac?",
        isPresented: $showForgetMac,
        titleVisibility: .visible
      ) {
        Button("Forget this Mac", role: .destructive) {
          Task {
            switch await store.revoke() {
            case .revoked:
              dismiss()
            case .unreachable:
              showOfflineForget = true
            }
          }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "This device is unpaired and its access token is deleted. You will need the pairing code from your Mac to connect again."
        )
      }
      .alert("Mac not reachable", isPresented: $showOfflineForget) {
        Button("Forget Locally", role: .destructive) {
          store.forgetSavedMac()
          dismiss()
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Vamp Companion couldn't reach this Mac to revoke the token. You can still forget it on this device; revoke it from the Mac's Remote settings to invalidate it there."
        )
      }
      .alert(
        store.errorTitle,
        isPresented: Binding(
          get: { store.errorMessage != nil },
          set: { if !$0 { store.errorMessage = nil } }
        )
      ) {
        Button("OK") { store.errorMessage = nil }
      } message: {
        Text(store.errorMessage ?? "Unknown error")
      }
    }
    .presentationCornerRadius(12)
  }

}

private struct RemoteSettingsIdentity: View {
  let version: RemoteAppVersion
  var body: some View {
    HStack(spacing: 13) {
      RemoteBeaconMark(size: 42)
        .padding(9).background(RemoteInstrument.recess, in: RoundedRectangle(cornerRadius: 14))
      VStack(alignment: .leading, spacing: 4) {
        Text("Vamp Companion").font(.headline)
        Text("Version \(version.version) · Build \(version.build)")
          .font(.caption.monospacedDigit()).foregroundStyle(RemoteInstrument.secondaryInk)
      }
      Spacer(minLength: 0)
    }
    .padding(14).remotePageCard()
    .accessibilityElement(children: .combine)
  }
}

private struct RemoteSettingsAppearance: View {
  @Binding var appearanceSetting: RemoteAppearanceSetting
  @Binding var accent: AccentPalette

  var body: some View {
    RemotePageSection(title: "Appearance") {
      VStack(alignment: .leading, spacing: 14) {
        RemotePageSegments(selection: $appearanceSetting,
          options: RemoteAppearanceSetting.allCases.map { ($0.label, $0) })
          .accessibilityLabel("Appearance")
        RemotePageDivider()
        HStack {
          Text("Accent").font(.subheadline.weight(.medium))
          Spacer(minLength: 8)
          Text(accent.label).font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
        }
        RemoteSettingsAccentPicker(selection: $accent)
        Text("System follows your device’s appearance.")
          .font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
      }
    }
  }
}

private struct RemoteSettingsAccentPicker: View {
  @Binding var selection: AccentPalette
  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
      ForEach(AccentPalette.allCases) { palette in
        Button {
          UISelectionFeedbackGenerator().selectionChanged()
          selection = palette
        } label: {
          let hex = palette.hexes.accentLight
          ZStack {
            Circle().fill(Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255))
              .frame(width: 28, height: 28)
            if palette == selection {
              Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
            }
          }
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(palette == selection ? RemoteInstrument.recess : .clear,
            in: RoundedRectangle(cornerRadius: 11))
          .overlay {
            RoundedRectangle(cornerRadius: 11).strokeBorder(
              palette == selection ? RemoteInstrument.ink.opacity(0.45) : .clear, lineWidth: 1)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(palette.label) accent")
        .accessibilityAddTraits(palette == selection ? .isSelected : [])
      }
    }
  }
}

/// Provider metadata and connection state come from the paired Mac. The phone
/// never reads back credentials; saving sends the draft once to Mac Keychain.
struct RemoteProvidersView: View {
  @Bindable var store: RemoteStore
  @State private var query = ""
  @State private var isLoading = false

  private var matchingProviders: [RemoteProviderOption] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return store.apiProviders.filter { provider in
      needle.isEmpty || provider.name.localizedCaseInsensitiveContains(needle)
        || provider.id.localizedCaseInsensitiveContains(needle)
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 17) {
        RemotePageHeading(title: "Connected intelligence", subtitle: "Add a provider to use its models on iPhone and Mac.")

        if !store.isConnected {
          RemoteReconnectBanner(store: store).clipShape(RoundedRectangle(cornerRadius: 17))
        }
        RemotePageSearchField(text: $query, placeholder: "Find a provider")
          .accessibilityLabel("Find a provider")

        if let notice = store.providerNotice {
          VStack(alignment: .leading, spacing: 8) {
            Text(notice).font(.footnote).foregroundStyle(RemoteInstrument.danger)
            Button("Try again") { Task { await load() } }
          }
        } else if isLoading && store.apiProviders.isEmpty {
          ProgressView("Loading providers")
            .frame(maxWidth: .infinity, minHeight: 120)
        } else if matchingProviders.isEmpty {
          if query.isEmpty {
            ContentUnavailableView("No providers available", systemImage: "key.horizontal",
              description: Text("Reconnect to your Mac and refresh this list."))
              .frame(maxWidth: .infinity, minHeight: 200)
          } else {
            ContentUnavailableView.search(text: query)
              .frame(maxWidth: .infinity, minHeight: 200)
          }
        }

        let connected = matchingProviders.filter(\.isReady)
        let builtIn = matchingProviders.filter { !$0.isReady && $0.kind == "builtIn" }
        let compatible = matchingProviders.filter { !$0.isReady && $0.kind == "compatible" }
        if !connected.isEmpty { providerSection("01", title: "Connected", providers: connected) }
        if !builtIn.isEmpty { providerSection("02", title: "Built-in", providers: builtIn) }
        if !compatible.isEmpty { providerSection("03", title: "Compatible services", providers: compatible) }

        Text("Keys are saved in your Mac's Keychain. Use a trusted connection when adding one from your phone.")
          .font(.footnote)
          .foregroundStyle(RemoteInstrument.secondaryInk)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      .frame(maxWidth: RemoteInstrument.contentWidth)
      .frame(maxWidth: .infinity)
    }
    .background { RemoteBackdrop() }
    .navigationTitle("API providers")
    .navigationBarTitleDisplayMode(.inline)
    .remotePageChrome()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
          .disabled(isLoading)
      }
    }
    .task { await load() }
  }

  private func providerSection(
    _ index: String, title: String, providers: [RemoteProviderOption]
  ) -> some View {
    RemotePageSection(title: LocalizedStringKey(title), detail: "\(providers.count)", padding: 0) {
      VStack(spacing: 0) {
        ForEach(providers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { provider in
          NavigationLink {
            RemoteProviderDetailView(store: store, providerID: provider.id)
          } label: {
            HStack(spacing: 12) {
              Image(systemName: provider.isReady ? "checkmark.seal.fill" : "key.horizontal")
                .foregroundStyle(provider.isReady ? RemoteInstrument.green : RemoteInstrument.secondaryInk)
                .frame(width: 28)
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 3) {
                Text(provider.name).font(.body.weight(.medium))
                Text(provider.needsMacSetup ? "Add a base URL" : provider.id == "custom" && !provider.configured ? "Base URL ready · key optional" : provider.kind == "compatible" ? "OpenAI-compatible" : "API key")
                  .font(.caption)
                  .foregroundStyle(RemoteInstrument.secondaryInk)
              }
              Spacer(minLength: 8)
              Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RemoteInstrument.secondaryInk)
                .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { RemotePageDivider() }
          }
          .buttonStyle(RemotePageRowButtonStyle())
        }
      }
    }
  }

  private func load() async {
    isLoading = true
    defer { isLoading = false }
    await store.loadAPIProviders()
  }
}

private struct RemoteProviderDetailView: View {
  @Bindable var store: RemoteStore
  let providerID: String

  @State private var keyDraft = ""
  @State private var baseURLDraft = ""
  @State private var modelDraft = ""
  @State private var isWorking = false
  @State private var statusMessage: String?
  @State private var showRemoveConfirmation = false

  private var provider: RemoteProviderOption? {
    store.apiProviders.first { $0.id == providerID }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 17) {
        if !store.isConnected {
          Text("Mac offline. Reconnect to update providers.")
            .font(.footnote).foregroundStyle(RemoteInstrument.secondaryInk)
        }
        if let provider {
          RemotePageSection(title: "Connection", spacing: 12) {
            RemoteMobileStatus(
              title: !store.isConnected ? "MAC OFFLINE" : provider.isReady ? "READY" : "NOT CONNECTED",
              color: store.isConnected && provider.isReady ? RemoteInstrument.green : RemoteInstrument.secondaryInk)
            if let baseURL = provider.baseURL {
              Text(baseURL).font(.caption.monospaced())
                .foregroundStyle(RemoteInstrument.secondaryInk)
                .textSelection(.enabled)
            }
            if providerID == "custom" {
              TextField("Base URL (https://…/v1)", text: $baseURLDraft)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .remotePageField()
                .disabled(isWorking)
                .accessibilityLabel("Custom provider base URL")
              Button("Save base URL") {
                guard store.isConnected, !isWorking else { return }
                isWorking = true
                statusMessage = nil
                Task {
                  defer { isWorking = false }
                  if await store.saveCustomProviderURL(baseURLDraft) {
                    statusMessage = "Base URL saved on your Mac."
                  }
                }
              }
              .buttonStyle(RemotePageButtonStyle())
              .disabled(!store.isConnected || isWorking || baseURLDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !provider.needsMacSetup {
              SecureField(provider.configured ? "New API key" : "API key", text: $keyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .privacySensitive()
                .padding(12)
                .remotePageField()
                .disabled(isWorking)
                .accessibilityLabel(provider.configured ? "Replacement API key" : "API key")
              Button(provider.configured ? "Replace key" : "Save key") {
                guard store.isConnected, !isWorking else { return }
                isWorking = true
                statusMessage = nil
                Task {
                  defer { isWorking = false }
                  if await store.saveAPIKey(providerID: providerID, key: keyDraft) {
                    keyDraft = ""
                    statusMessage = "Key saved on your Mac. Choose a model or add its ID below."
                  }
                }
              }
              .buttonStyle(RemotePageButtonStyle(primary: true))
              .disabled(!store.isConnected || isWorking || keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if provider.configured {
              Button("Remove key", role: .destructive) { showRemoveConfirmation = true }
                .buttonStyle(RemotePageButtonStyle())
                .disabled(!store.isConnected || isWorking)
            }
            if isWorking { ProgressView("Updating provider") }
            if let statusMessage {
              Text(statusMessage).font(.footnote).foregroundStyle(RemoteInstrument.green)
            }
          }
          if provider.isReady {
            RemotePageSection(title: "Add model", spacing: 12) {
              Text("Use a model ID from this provider when it does not appear in the picker.")
                .font(.footnote)
                .foregroundStyle(RemoteInstrument.secondaryInk)
              TextField("Model ID", text: $modelDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .remotePageField()
                .disabled(isWorking)
              Button("Add model") {
                guard store.isConnected, !isWorking else { return }
                isWorking = true
                statusMessage = nil
                Task {
                  defer { isWorking = false }
                  if await store.addProviderModel(providerID: providerID, modelID: modelDraft) {
                    modelDraft = ""
                    statusMessage = "Model added to the picker."
                  }
                }
              }
              .buttonStyle(RemotePageButtonStyle())
              .disabled(!store.isConnected || isWorking || modelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
          }
        } else {
          ContentUnavailableView("Provider unavailable", systemImage: "key.slash")
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 16)
      .frame(maxWidth: RemoteInstrument.contentWidth)
      .frame(maxWidth: .infinity)
    }
    .background { RemoteBackdrop() }
    .navigationTitle(provider?.name ?? "API provider")
    .navigationBarTitleDisplayMode(.inline)
    .remotePageChrome()
    .task(id: provider?.baseURL) {
      if providerID == "custom", baseURLDraft.isEmpty {
        baseURLDraft = provider?.baseURL ?? ""
      }
    }
    .confirmationDialog("Remove this API key from your Mac?", isPresented: $showRemoveConfirmation) {
      Button("Remove key", role: .destructive) {
        guard store.isConnected, !isWorking else { return }
        isWorking = true
        statusMessage = nil
        Task {
          defer { isWorking = false }
          if await store.removeAPIKey(providerID: providerID) {
            keyDraft = ""
            statusMessage = "Key removed from your Mac."
          }
        }
      }
    } message: {
      Text("This provider's models will no longer be available until you add another key.")
    }
  }
}

/// Metadata stacks at accessibility sizes without squeezing either column.
private struct RemoteSettingValue: View {
  let title: String
  let value: String
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(spacing: 12))
    layout {
      Text(title).font(.subheadline).foregroundStyle(
        RemoteInstrument.secondaryInk)
      if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
      Text(verbatim: value).font(.subheadline.weight(.medium)).foregroundStyle(RemoteInstrument.ink)
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(minHeight: 44)
    .padding(.vertical, 4)
    .overlay(alignment: .bottom) { RemotePageDivider() }
    .accessibilityElement(children: .combine)
  }
}
