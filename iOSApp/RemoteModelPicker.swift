import SwiftUI

#if DEBUG
struct RemoteModelPickerFixture: View {
    @State private var source = "local"
    @State private var selectedModelID = "local|huihui"
    @State private var loaded: RemoteLoadedLocalModel? = .init(
        id: "local|huihui", name: "Huihui Qwen3.8 27B abliterated Q2 K",
        canUnload: ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] != "busy")
    @State private var unloading = false
    var body: some View {
        RemoteModelPickerSheet(models: [
            .init(id: "local|huihui", name: "Huihui Qwen3.8 27B abliterated Q2 K", source: "local",
                  detail: "Downloaded · GGUF", reasoningEfforts: nil, defaultReasoningEffort: nil),
            .init(id: "local|bonsai", name: "Ternary Bonsai 27B", source: "local",
                  detail: "Downloaded · GGUF", reasoningEfforts: nil, defaultReasoningEffort: nil),
        ], source: $source, selectedModelID: $selectedModelID,
           loadedLocalModel: loaded, isUnloadingModel: unloading,
           isConnected: ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] != "offline",
           onUnload: {
               unloading = true
               try? await Task.sleep(for: .milliseconds(300))
               loaded = nil
               unloading = false
               return true
           })
    }
}
#endif

// MARK: - Searchable model picker

/// The one place the iOS client lists models.
///
/// The new-session sheet used to render every model inline with no search, and
/// the in-conversation switcher used a `Menu` — both fall apart the moment a
/// gateway like OpenRouter contributes a few hundred API models. This is a
/// searchable, sectioned, counted list instead, presented as a sheet from both.
struct RemoteModelPickerSheet: View {
    let models: [RemoteStartModelOption]
    var modeName: String? = nil
    @Binding var source: String
    @Binding var selectedModelID: String
    /// Called with the chosen model so callers can also apply its default
    /// reasoning effort without re-looking it up.
    var onSelect: (RemoteStartModelOption) -> Void = { _ in }
    /// Pull-to-refresh, so a model configured on the Mac while this sheet is
    /// open can be picked up without closing and reopening it.
    var onRefresh: (() async -> Void)? = nil
    var loadedLocalModel: RemoteLoadedLocalModel? = nil
    var isUnloadingModel = false
    var isConnected = true
    var onUnload: (() async -> Bool)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.remoteAppearance) private var appearance
    @State private var query = ""
    @State private var didUnload = false

    static let sources = ["local", "chatgpt", "api"]

    static func sourceLabel(_ source: String) -> String {
        switch source {
        case "chatgpt": "ChatGPT"
        case "api": "API"
        default: "Local"
        }
    }

    static func sourceIcon(_ source: String) -> String {
        switch source {
        case "chatgpt": "person.crop.circle"
        case "api": "cloud"
        default: "cpu"
        }
    }

    private var inSource: [RemoteStartModelOption] {
        models.filter { $0.source == source }
    }

    /// Matches name, model id, and the provider shown in `detail`, so an exact
    /// id typed from a provider's docs finds its model.
    private var filtered: [RemoteStartModelOption] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return inSource }
        return inSource.filter { model in
            [model.name, model.id, model.detail].contains {
                $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    /// API models come from many providers at once; grouping by `detail` keeps
    /// each provider's models together instead of interleaving them.
    private var groups: [(title: String, models: [RemoteStartModelOption])] {
        if source == "chatgpt" {
            let latest = filtered.filter(\.isLatest)
            let rest = filtered.filter { !$0.isLatest }
            var sections: [(String, [RemoteStartModelOption])] = []
            if !latest.isEmpty { sections.append(("Latest", latest)) }
            if !rest.isEmpty {
                sections.append((latest.isEmpty ? "ChatGPT" : "More", rest))
            }
            return sections
        }
        guard source == "api" else {
            return filtered.isEmpty ? [] : [(Self.sourceLabel(source), filtered)]
        }
        let byProvider = Dictionary(grouping: filtered, by: \.detail)
        return byProvider.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { ($0, byProvider[$0]!.sorted { lhs, rhs in
                if lhs.isLatest != rhs.isLatest { return lhs.isLatest }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }) }
    }

    private var emptyDescription: String {
        switch source {
        case "chatgpt": "Sign in with ChatGPT on your Mac, then refresh."
        case "api": "Add an API key in Settings → API providers, then refresh."
        default: "Download a model on your Mac first."
        }
    }

    var body: some View {
        NavigationStack {
            RemotePageScroll {
                RemotePageHeading(title: "Choose a model", subtitle: "Local models and connected providers, ready for your next conversation.")
                if let modeName {
                    Text("Conversation mode: \(modeName)")
                        .font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                }
                RemotePageSearchField(text: $query, placeholder: "Search name, ID, or provider")
                RemotePageSegments(selection: $source, options: Self.sources.map { option in
                    let count = models.filter { $0.source == option }.count
                    return (count > 0 ? "\(Self.sourceLabel(option)) \(count)" : Self.sourceLabel(option), option)
                })
                .accessibilityLabel("Model source")

                if !isConnected {
                    RemoteNoticeLabel(title: "Mac offline", detail: "Reconnect to refresh models or start a session. Cached models stay visible.", symbol: "wifi.slash")
                        .clipShape(RoundedRectangle(cornerRadius: 17))
                }
                if source == "local", onUnload != nil { unloadControl }
                if inSource.isEmpty {
                    ContentUnavailableView(
                        isConnected ? "No \(Self.sourceLabel(source)) models" : "Models unavailable",
                        systemImage: Self.sourceIcon(source),
                        description: Text(isConnected ? emptyDescription : "Reconnect to load the models on your Mac."))
                        .remotePageCard()
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: query).remotePageCard()
                } else {
                    ForEach(groups, id: \.title) { group in
                        RemotePageSection(title: LocalizedStringKey(group.title), detail: "\(group.models.count)", padding: 0) {
                            LazyVStack(spacing: 0) {
                                ForEach(group.models) { model in
                                    row(model)
                                    if model.id != group.models.last?.id {
                                        RemotePageDivider().padding(.leading, 66)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .refreshable { await onRefresh?() }
            .navigationTitle("Models")
            .remotePageChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }.vampUtilityAction()
            }
            .task { await onRefresh?() }
            .keyboardDismissToolbar()
        }
    }

    @ViewBuilder
    private var unloadControl: some View {
        if let loaded = loadedLocalModel {
            RemotePageSection(title: "Loaded on Mac") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(loaded.name).font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loaded.canUnload
                         ? "Free Mac memory. Your download and conversations stay saved."
                         : "Stop the active task to unload this model.")
                        .font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                    Button {
                        Task { didUnload = await onUnload?() ?? false }
                    } label: {
                        HStack(spacing: 8) {
                            if isUnloadingModel { ProgressView().controlSize(.small) }
                            else { Image(systemName: "eject") }
                            Text(isUnloadingModel ? "Unloading…" : "Unload model")
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RemotePageButtonStyle())
                    .disabled(!isConnected || !loaded.canUnload || isUnloadingModel)
                    .accessibilityIdentifier("remote.model.unload")
                    .accessibilityHint("Frees memory on your Mac. Keeps the downloaded model and your conversations.")
                }
            }
        } else if didUnload {
            Label("Model unloaded", systemImage: "checkmark.circle")
                .font(.subheadline).foregroundStyle(RemoteInstrument.green)
                .accessibilityIdentifier("remote.model.unloaded")
        }
    }

    private func row(_ model: RemoteStartModelOption) -> some View {
        Button {
            selectedModelID = model.id
            onSelect(model)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                RemotePageSymbol(symbol: Self.sourceIcon(model.source), active: selectedModelID == model.id)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name).font(.body.weight(.medium))
                        .foregroundStyle(RemoteInstrument.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.detail).font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.isLatest { RemotePageBadge(title: "Latest", color: BeetTheme.accentBright) }
                }
                Spacer(minLength: 4)
                if selectedModelID == model.id {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(BeetTheme.accentBright)
                        .accessibilityHidden(true)
                }
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RemotePageRowButtonStyle())
        .accessibilityAddTraits(selectedModelID == model.id ? .isSelected : [])
    }

}

/// The summary row that opens the picker. Shows the current model, its source,
/// and how many are available, so the size of the catalog is visible without
/// opening anything.
struct RemoteModelSummaryRow: View {
    let models: [RemoteStartModelOption]
    let selectedModelID: String
    let action: () -> Void
    @Environment(\.remoteAppearance) private var appearance

    private var selected: RemoteStartModelOption? {
        models.first { $0.id == selectedModelID }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: RemoteModelPickerSheet.sourceIcon(selected?.source ?? "local"))
                    .foregroundStyle(BeetTheme.accentBright)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(selected?.name ?? "Choose a model")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(RemoteInstrument.ink)
                    Text(selected?.detail ?? "\(models.count) available")
                        .font(.caption)
                        .foregroundStyle(BeetTheme.secondaryText(appearance))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(BeetTheme.surface(appearance), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(BeetTheme.line(appearance)) }
        .accessibilityLabel("Model, \(selected?.name ?? "none chosen")")
        .accessibilityHint("Opens the searchable model list")
    }
}
