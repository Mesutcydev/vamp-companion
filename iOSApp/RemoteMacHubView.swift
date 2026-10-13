import SwiftUI


// This palette belongs only to the Companion panel. The composer and
// shared instrument controls retain the current Assistant materials.
private enum RemoteCompanionPalette {
    static let canvas = RemoteInstrument.adaptive(0xF4F4F4, 0x181818)
    static let panel = RemoteInstrument.adaptive(0xFAFAFA, 0x222222)
    static let recess = RemoteInstrument.adaptive(0xEFEFEF, 0x1C1C1C)
    static let control = RemoteInstrument.adaptive(0xEEEEEE, 0x303030)
    static let seam = RemoteInstrument.adaptive(0xD0D0D0, 0x414141)
    static let ink = RemoteInstrument.adaptive(0x222222, 0xF2F2F2)
    static let secondaryInk = RemoteInstrument.adaptive(0x555555, 0xBBBBBB)
    static let accent = RemoteInstrument.adaptive(0xAD2030, 0xF0808D)
}

private extension View {
    func companionPanel() -> some View {
        background(RemoteCompanionPalette.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(RemoteCompanionPalette.seam, lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }

    func companionNavigationChrome() -> some View {
        foregroundStyle(RemoteCompanionPalette.ink)
            .tint(RemoteCompanionPalette.accent)
            .toolbarBackground(RemoteCompanionPalette.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct RemoteCompanionSection<Content: View>: View {
    let index: String
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(index).font(.caption.monospaced()).foregroundStyle(RemoteCompanionPalette.secondaryInk)
                Text(title).font(.headline).foregroundStyle(RemoteCompanionPalette.ink)
            }
            .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RemoteCompanionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(RemoteCompanionPalette.ink)
            .background(RemoteCompanionPalette.control, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(RemoteCompanionPalette.seam, lineWidth: contrast == .increased ? 1.5 : 0.75)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.48)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum RemoteMacHubAction {
    case start(modelID: String)
    case control
    case switchComputer
}

/// Uses the existing protocol-v1 status/models/provider APIs. Opening the hub
/// never changes host permissions, loads a model, or starts an assistant run.
struct RemoteMacHubView: View {
    let store: RemoteStore
    let onAction: (RemoteMacHubAction) -> Void
    @Environment(\.dismiss) private var dismiss

    private var hostProduct: String {
        (9675...9683).contains(store.baseURL?.port ?? 0) ? "Vamp Companion" : "Vamp Assistant"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    RemoteMacConnectionSection(
                        name: store.activeComputerName, product: hostProduct,
                        connection: store.connectionSubtitle, connected: store.isConnected,
                        working: store.hostStatus?.isRunning == true,
                        queued: store.hostStatus?.queuedTasks ?? 0)
                    if let notice = store.backgroundNotice {
                        RemoteNoticeLabel(title: "Couldn’t refresh your Mac", detail: notice)
                    }
                    RemoteMacModelsSection(
                        models: store.startModels, loaded: store.loadedLocalModel,
                        connected: store.isConnected, unloading: store.isUnloadingModel,
                        onStart: { onAction(.start(modelID: $0)) },
                        onUnload: { await store.unloadLocalModel() })
                    RemoteMacAccessSection(
                        status: store.hostStatus?.macControl,
                        connected: store.isConnected, product: hostProduct,
                        onControl: { onAction(.control) })
                    RemoteCompanionSection(index: "03", title: "Connections") {
                        NavigationLink {
                            RemoteProvidersView(store: store)
                        } label: {
                            RemoteMacDestinationRow(title: "API providers & accounts", symbol: "key.horizontal")
                        }
                        .buttonStyle(PlainButtonStyle())
                        Button { onAction(.switchComputer) } label: {
                            RemoteMacDestinationRow(title: "Switch or pair a Mac", symbol: "desktopcomputer.and.macbook")
                        }
                        .buttonStyle(PlainButtonStyle())
                        Text("Downloads and model imports live on your Mac. Closing the Companion window keeps your sessions running.")
                            .font(.footnote).foregroundStyle(RemoteCompanionPalette.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20).frame(maxWidth: RemoteInstrument.contentWidth)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background { RemoteCompanionPalette.canvas.ignoresSafeArea() }
            .navigationTitle("Your Mac")
            .navigationBarTitleDisplayMode(.inline)
            .companionNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if store.isRefreshing || store.isConnecting { ProgressView() }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(store.isRefreshing || store.isConnecting)
                    .accessibilityLabel("Refresh your Mac")
                }
            }
            .refreshable { await refresh() }
            .task { await store.loadStartModels() }
        }
    }

    private func refresh() async {
        if store.isConnected { try? await store.refresh() }
        else { await store.connectSaved() }
        await store.loadStartModels()
    }
}

private struct RemoteMacConnectionSection: View {
    let name: String
    let product: String
    let connection: String
    let connected: Bool
    let working: Bool
    let queued: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                RemoteVampMark().fill(RemoteCompanionPalette.ink, style: FillStyle(eoFill: true))
                    .padding(9).frame(width: 52, height: 52)
                    .background(RemoteCompanionPalette.recess, in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.title2.weight(.semibold))
                        .foregroundStyle(RemoteCompanionPalette.ink)
                    Text(product).font(.subheadline).foregroundStyle(RemoteCompanionPalette.secondaryInk)
                }
            }
            Label(connected ? connection : "Mac offline · refresh to reconnect",
                  systemImage: connected ? "checkmark.circle" : "wifi.slash")
                .font(.subheadline).foregroundStyle(RemoteCompanionPalette.secondaryInk)
                .accessibilityIdentifier("remote.mac.connection")
            if connected {
                HStack(spacing: 10) {
                    Label(working ? "Assistant is working" : "Ready for a session",
                          systemImage: working ? "waveform" : "bolt")
                    if queued > 0 { Text("\(queued) queued").monospacedDigit() }
                }.font(.footnote).foregroundStyle(RemoteCompanionPalette.secondaryInk)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).companionPanel()
    }
}

private struct RemoteMacModelsSection: View {
    let models: [RemoteStartModelOption]
    let loaded: RemoteLoadedLocalModel?
    let connected: Bool
    let unloading: Bool
    let onStart: (String) -> Void
    let onUnload: () async -> Bool

    var body: some View {
        RemoteCompanionSection(index: "01", title: "Models on your Mac") {
            if let loaded {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Loaded on Mac", systemImage: "cpu").font(.caption)
                            .foregroundStyle(RemoteCompanionPalette.secondaryInk)
                        Text(loaded.name).font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 4)
                    Button {
                        Task { _ = await onUnload() }
                    } label: {
                        HStack {
                            if unloading { ProgressView() }
                            else { Text("Unload").font(.subheadline.weight(.semibold)) }
                        }.frame(minWidth: 72, minHeight: 44)
                    }
                    .buttonStyle(RemoteCompanionButtonStyle())
                    .disabled(!connected || !loaded.canUnload || unloading)
                    .accessibilityIdentifier("remote.mac.unload")
                }
                .padding(14).companionPanel()
                Text(loaded.canUnload ? "Unload to free Mac memory. The download and your chats stay saved."
                     : "Stop the active task before unloading.")
                    .font(.footnote).foregroundStyle(RemoteCompanionPalette.secondaryInk)
            }
            if models.isEmpty {
                Text(connected ? "Download a local model in Companion → Models, or add a provider below. Pull to refresh when it’s ready."
                     : "Reconnect to see your Mac’s models. Your conversations stay saved.")
                    .font(.subheadline).foregroundStyle(RemoteCompanionPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(models.prefix(6))) { model in
                        RemoteMacModelRow(model: model, isLoaded: model.id == loaded?.id,
                                          connected: connected, onStart: onStart)
                        if model.id != models.prefix(6).last?.id { Rectangle().fill(RemoteCompanionPalette.seam).frame(height: 0.75).padding(.leading, 48) }
                    }
                }.companionPanel()
                NavigationLink {
                    RemoteMacModelLibraryView(models: models, loadedID: loaded?.id,
                                              connected: connected, onStart: onStart)
                } label: {
                    Label("Browse all models (\(models.count))", systemImage: "square.stack.3d.up")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }
                .accessibilityIdentifier("remote.mac.browse-models")
            }
        }
    }
}

private struct RemoteMacModelLibraryView: View {
    let models: [RemoteStartModelOption]
    let loadedID: String?
    let connected: Bool
    let onStart: (String) -> Void
    @State private var source = "local"
    @State private var query = ""

    private var filtered: [RemoteStartModelOption] {
        models.filter { model in
            model.source == source && (query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || model.name.localizedCaseInsensitiveContains(query)
                || model.id.localizedCaseInsensitiveContains(query)
                || model.detail.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Picker("Model source", selection: $source) {
                ForEach(RemoteModelPickerSheet.sources, id: \.self) { value in
                    Text(RemoteModelPickerSheet.sourceLabel(value)).tag(value)
                }
            }
            .pickerStyle(.segmented).padding(.horizontal, 20)
            if filtered.isEmpty {
                ContentUnavailableView("No matching models", systemImage: "cpu",
                    description: Text("Choose another source or search. Local downloads are managed on your Mac."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { model in
                            RemoteMacModelRow(model: model, isLoaded: model.id == loadedID,
                                              connected: connected, onStart: onStart)
                            Rectangle().fill(RemoteCompanionPalette.seam).frame(height: 0.75).padding(.leading, 48)
                        }
                    }.companionPanel().padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 12).background { RemoteCompanionPalette.canvas.ignoresSafeArea() }
        .navigationTitle("Mac models").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search name, ID, or provider")
        .companionNavigationChrome()
        .onAppear {
            if !models.contains(where: { $0.source == source }) {
                source = RemoteModelPickerSheet.sources.first(where: { candidate in
                    models.contains { $0.source == candidate }
                }) ?? "local"
            }
        }
    }
}

private struct RemoteMacModelRow: View {
    let model: RemoteStartModelOption
    let isLoaded: Bool
    let connected: Bool
    let onStart: (String) -> Void

    var body: some View {
        Button { onStart(model.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: RemoteModelPickerSheet.sourceIcon(model.source))
                    .foregroundStyle(RemoteCompanionPalette.secondaryInk).frame(width: 22)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.name).font(.body.weight(.semibold)).foregroundStyle(RemoteCompanionPalette.ink)
                    Text(isLoaded ? "Loaded · \(model.detail)" : model.detail)
                        .font(.caption).foregroundStyle(RemoteCompanionPalette.secondaryInk)
                }
                Spacer(minLength: 4)
                Image(systemName: "plus.bubble").foregroundStyle(RemoteCompanionPalette.secondaryInk)
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle()).disabled(!connected)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("remote.mac.model.\(model.id)")
        .accessibilityHint("Opens a new session with this model. You choose the task before starting.")
    }
}

private struct RemoteMacAccessSection: View {
    let status: RemoteMacControlStatus?
    let connected: Bool
    let product: String
    let onControl: () -> Void

    private var ready: Bool {
        connected && status?.enabled == true && status?.ready == true && status?.locked != true
    }

    var body: some View {
        RemoteCompanionSection(index: "02", title: "Mac control") {
            Label(ready ? "Ready to control" : !connected ? "Reconnect to check permissions"
                  : status == nil ? "Mac control status unavailable"
                  : status?.locked == true ? "Mac is locked"
                  : status?.enabled == false ? "Disabled on Mac" : "Mac permissions need attention",
                  systemImage: ready ? "checkmark.shield" : "lock.shield")
                .font(.subheadline.weight(.medium)).foregroundStyle(RemoteCompanionPalette.ink)
                .accessibilityIdentifier("remote.mac.control-status")
            Text(ready ? "Control your Mac from here. Sharing and control permissions stay managed on your Mac."
                 : product == "Vamp Companion"
                 ? "Enable Mac control in Companion → Settings → Sharing & control. Accessibility and Screen Recording are granted on the Mac."
                 : "Enable Mac control and grant Accessibility and Screen Recording in Vamp Assistant on your Mac.")
                .font(.footnote).foregroundStyle(RemoteCompanionPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onControl) {
                Label("Control Mac", systemImage: "display")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
                .buttonStyle(RemoteCompanionButtonStyle()).disabled(!connected)
        }
    }
}

private struct RemoteMacDestinationRow: View {
    let title: LocalizedStringKey
    let symbol: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).frame(width: 24)
            Text(title).font(.body)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption)
                .foregroundStyle(RemoteCompanionPalette.secondaryInk)
        }
        .foregroundStyle(RemoteCompanionPalette.ink).frame(minHeight: 52).contentShape(Rectangle())
    }
}

struct RemoteVampMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 8, y: 5))
        for point in [CGPoint(x: 32, y: 5), CGPoint(x: 38, y: 11), CGPoint(x: 38, y: 28),
                      CGPoint(x: 28, y: 28), CGPoint(x: 25, y: 36), CGPoint(x: 20, y: 28),
                      CGPoint(x: 15, y: 36), CGPoint(x: 12, y: 28), CGPoint(x: 2, y: 28), CGPoint(x: 2, y: 11)] {
            path.addLine(to: point)
        }
        path.closeSubpath()
        path.move(to: CGPoint(x: 10, y: 11))
        for point in [CGPoint(x: 8, y: 13), CGPoint(x: 8, y: 22), CGPoint(x: 32, y: 22),
                      CGPoint(x: 32, y: 13), CGPoint(x: 30, y: 11)] { path.addLine(to: point) }
        path.closeSubpath()
        path.addRect(CGRect(x: 12, y: 15, width: 6, height: 3))
        path.addRect(CGRect(x: 22, y: 15, width: 6, height: 3))
        let scale = min(rect.width, rect.height) / 40
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
            .applying(CGAffineTransform(translationX: rect.midX - 20 * scale, y: rect.midY - 20 * scale))
    }
}

#if DEBUG
struct RemoteMacHubFixture: View {
    @State private var selected = ""
    private var connected: Bool { ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] != "offline" }
    private let model = RemoteStartModelOption(id: "local|fixture", name: "Qwen local model",
        source: "local", detail: "Downloaded on Mac · MLX", reasoningEfforts: nil, defaultReasoningEffort: nil)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    RemoteMacConnectionSection(name: "My Mac", product: "Vamp Companion",
                        connection: "Private over Tailscale", connected: connected, working: false, queued: 0)
                    RemoteMacModelsSection(models: [model], loaded: nil, connected: connected,
                        unloading: false, onStart: { selected = $0 }, onUnload: { false })
                    RemoteMacAccessSection(status: nil, connected: connected, product: "Vamp Companion", onControl: {})
                    if !selected.isEmpty { Text("New session model: \(selected)").accessibilityIdentifier("remote.mac.fixture-selection") }
                }.padding(20)
            }
            .background { RemoteCompanionPalette.canvas.ignoresSafeArea() }.navigationTitle("Your Mac")
            .navigationBarTitleDisplayMode(.inline).companionNavigationChrome()
        }
    }
}
#endif
