import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SessionNavigationView: View {
    let store: RemoteStore
    @State private var path: [UUID] = []
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    SessionListView(store: store, onOpen: { path = [$0] }, selectedSessionID: path.last)
                        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
                } detail: {
                    NavigationStack {
                        if let sessionID = path.last {
                            ConversationView(store: store, sessionID: sessionID)
                        } else {
                            ContentUnavailableView("Choose a conversation", systemImage: "text.alignleft",
                                description: Text("Your chats stay in the conversation library."))
                                .foregroundStyle(RemoteInstrument.ink)
                                .background(RemoteInstrument.reading)
                        }
                    }
                }
            } else {
                NavigationStack(path: $path) {
                    SessionListView(store: store, onOpen: { path.append($0) })
                        .navigationDestination(for: UUID.self) { ConversationView(store: store, sessionID: $0) }
                }
            }
        }
            .alert(store.errorTitle, isPresented: errorBinding) { Button("OK") { store.errorMessage = nil } }
                message: { Text(store.errorMessage ?? "Unknown error") }
            .task(id: RemoteNotificationCenter.shared.pendingNavigation) {
                guard let target = RemoteNotificationCenter.shared.pendingNavigation else { return }
                guard await store.openNotification(target) else {
                    if RemoteNotificationCenter.shared.pendingNavigation == target {
                        RemoteNotificationCenter.shared.pendingNavigation = nil
                    }
                    return
                }
                if path.last != target.sessionID { path = [target.sessionID] }
                if RemoteNotificationCenter.shared.pendingNavigation == target {
                    RemoteNotificationCenter.shared.pendingNavigation = nil
                }
            }
    }
    private var errorBinding: Binding<Bool> { Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }) }
}

private struct RemoteHomeStartRequest: Identifiable {
    let id = UUID()
    let prompt: String
    let modelID: String?
}

private enum RemoteSettingsDestination { case computers, diagnostics }

struct SessionListView: View {
    let store: RemoteStore
    let onOpen: (UUID) -> Void
    var selectedSessionID: UUID? = nil
    @Environment(\.remoteAppearance) private var appearance
    @State private var search = ""
    @State private var startRequest: RemoteHomeStartRequest?
    @State private var showSharing = false
    @State private var showComputers = false
    @State private var showControl = false
    @State private var showBotRuns = false
    @State private var showDiagnostics = false
    @State private var showSettings = false
    @State private var deferredSettingsDestination: RemoteSettingsDestination?
    @State private var showMacHub = false
    @State private var deferredMacAction: RemoteMacHubAction?
    @State private var deferredSessionID: UUID?
    private var visible: [RemoteSessionSummary] { search.isEmpty ? store.sessions : store.sessions.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.workspace.localizedCaseInsensitiveContains(search) } }
    private var history: [RemoteSessionSummary] {
        guard search.isEmpty else { return visible }
        let featured = Set(visible.filter { $0.isRunning || $0.queueState == "queued" }.prefix(2).map(\.id))
        return visible.filter { !featured.contains($0.id) }
    }
    /// Date sections like Messages and Notes, so the list scans by when, not by count.
    private var historyGroups: [(title: String, sessions: [RemoteSessionSummary])] {
        guard search.isEmpty else { return history.isEmpty ? [] : [("Results", history)] }
        let calendar = Calendar.current
        let titles = ["Today", "Yesterday", "Previous 7 days", "Earlier"]
        let groups = Dictionary(grouping: history) { session -> Int in
            let date = Date(timeIntervalSince1970: session.updatedAt)
            if calendar.isDateInToday(date) { return 0 }
            if calendar.isDateInYesterday(date) { return 1 }
            return date > .now.addingTimeInterval(-7 * 86_400) ? 2 : 3
        }
        return groups.keys.sorted().map { (titles[$0], groups[$0] ?? []) }
    }

    var body: some View {
        ZStack {
            RemoteBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if search.isEmpty {
                        RemoteHomeOverview(store: store, onOpen: onOpen,
                            onMac: { showMacHub = true }, onControl: { showControl = true },
                            onBots: { showBotRuns = true }, onShare: { showSharing = true })
                    }
                    if history.isEmpty, !search.isEmpty {
                        RemoteEmptySessions(isSearching: true, isConnected: store.isConnected,
                            onStart: { presentNewSession() }, onClearSearch: { search = "" })
                    } else if visible.isEmpty {
                        Text("Your conversations will appear here.")
                            .font(.subheadline).foregroundStyle(RemoteInstrument.secondaryInk)
                            .padding(.horizontal, 4)
                    }
                    ForEach(historyGroups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            RemotePageSectionHeading(title: LocalizedStringKey(group.title),
                                detail: search.isEmpty ? nil : "\(group.sessions.count)").padding(.horizontal, 4)
                            SessionGroup(sessions: group.sessions, store: store, onOpen: onOpen, selectedSessionID: selectedSessionID)
                        }
                    }
                    if search.isEmpty {
                        RemoteHomeStarters(connected: store.isConnected, onStart: { presentNewSession(prompt: $0) })
                    }
                }
                .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 24)
                .frame(maxWidth: RemoteInstrument.contentWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { try? await store.refresh(); await store.loadStartModels() }
        }
        .safeAreaInset(edge: .bottom) {
            RemoteHomeComposeBar(connected: store.isConnected) { presentNewSession() }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
            .remoteNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    RemoteWordmark()
                }.vampUtilityAction()
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search conversations")
            .task(id: store.isConnected) { if store.isConnected { await store.loadStartModels() } }
            .onChange(of: store.hostStatus?.isRunning) { _, _ in
                if store.isConnected { Task { await store.loadStartModels() } }
            }

            .fullScreenCover(item: $startRequest, onDismiss: openDeferredSession) { request in
                StartSessionSheet(store: store, initialBotID: "", initialPrompt: request.prompt, initialModelID: request.modelID) { sessionID in
                    deferredSessionID = sessionID
                    startRequest = nil
                }
            }
            .sheet(isPresented: $showSharing) { RemoteShareSheet(store: store) }
            .sheet(isPresented: $showSettings, onDismiss: openDeferredSettingsDestination) {
                RemoteSettingsSheet(
                    store: store,
                    onSwitchComputer: {
                        deferredSettingsDestination = .computers
                        showSettings = false
                    },
                    onDiagnostics: {
                        deferredSettingsDestination = .diagnostics
                        showSettings = false
                    })
            }
            .sheet(isPresented: $showBotRuns, onDismiss: openDeferredSession) {
                RemoteBotsView(store: store) { sessionID in
                    deferredSessionID = sessionID
                    showBotRuns = false
                }
            }
            .sheet(isPresented: $showComputers) { ComputerSwitcherSheet(store: store) }
            .sheet(isPresented: $showMacHub, onDismiss: openDeferredMacAction) {
                RemoteMacHubView(store: store) { action in
                    deferredMacAction = action
                    showMacHub = false
                }
            }
            .sheet(isPresented: $showDiagnostics) {
                NavigationStack {
                    RemoteDiagnosticsSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showDiagnostics = false }
                            }
                        }
                }
            }
            .fullScreenCover(isPresented: $showControl) { RemoteControlView(store: store) }
    }

    private func presentNewSession(prompt: String = "", modelID: String? = nil) {
        startRequest = RemoteHomeStartRequest(prompt: prompt, modelID: modelID)
    }

    private func openDeferredSession() {
        guard let sessionID = deferredSessionID else { return }
        deferredSessionID = nil
        // Navigation changes issued during sheet dismissal are occasionally
        // dropped by SwiftUI. The dismissal completion is the first stable
        // point at which the stack can accept the destination.
        Task { @MainActor in
            await Task.yield()
            onOpen(sessionID)
        }
    }
    private func openDeferredSettingsDestination() {
        guard let destination = deferredSettingsDestination else { return }
        deferredSettingsDestination = nil
        Task { @MainActor in
            await Task.yield()
            switch destination {
            case .computers: showComputers = true
            case .diagnostics: showDiagnostics = true
            }
        }
    }

    private func openDeferredMacAction() {
        guard let action = deferredMacAction else { return }
        deferredMacAction = nil
        Task { @MainActor in
            await Task.yield()
            switch action {
            case .start(let modelID):
                presentNewSession(modelID: modelID)
            case .control: showControl = true
            case .switchComputer: showComputers = true
            }
        }
    }
}

struct SessionGroup: View {
    let sessions: [RemoteSessionSummary]
    var store: RemoteStore? = nil
    var onOpen: ((UUID) -> Void)? = nil
    var selectedSessionID: UUID? = nil
    @State private var pendingDelete: RemoteSessionSummary?
    @State private var renaming: RemoteSessionSummary?
    @State private var renameDraft = ""

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(sessions) { session in
                Group {
                    if let onOpen {
                        Button { onOpen(session.id) } label: { SessionRow(session: session) }
                    } else {
                        NavigationLink(value: session.id) { SessionRow(session: session) }
                    }
                }
                    .buttonStyle(RemoteSessionButtonStyle(isLast: session.id == sessions.last?.id))
                    .background(selectedSessionID == session.id ? BeetTheme.accentBright.opacity(0.12) : .clear)
                    .accessibilityAddTraits(selectedSessionID == session.id ? .isSelected : [])
                    .contextMenu {
                        if store != nil {
                            Button("Rename", systemImage: "pencil") {
                                renameDraft = session.title
                                renaming = session
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDelete = session
                            }
                        }
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .remotePageCard()
        .confirmationDialog(
            "Delete this chat?",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete) { session in
                Button("Delete", role: .destructive) {
                    Task {
                        if await store?.deleteSession(session.id) == true {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { session in
                // Same wording as the Mac: this removes the file, not a copy.
                Text("“\(session.title)” is removed from your Mac. This cannot be undone.")
            }
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil },
                                                   set: { if !$0 { renaming = nil } })) {
            TextField("Chat name", text: $renameDraft)
            Button("Rename") {
                guard let session = renaming else { return }
                let title = renameDraft
                Task { _ = await store?.renameSession(session.id, title: title) }
            }
            .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose a short name that is easy to find in history.")
        }
    }
}

struct RemoteReasoningSelector: View {
    let modelName: String
    let efforts: [String]
    let defaultEffort: String?
    @Binding var selection: String?
    @Environment(\.remoteAppearance) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Reasoning", systemImage: "brain.head.profile")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(selection ?? defaultEffort ?? "Auto")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(BeetTheme.accentBright)
            }
            Text("Choose how much thinking \(modelName) should use.")
                .font(.caption)
                .foregroundStyle(BeetTheme.secondaryText(appearance))
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    reasoningButton("Auto", value: nil)
                    ForEach(efforts, id: \.self) { effort in
                        reasoningButton(effort.capitalized, value: effort)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(13)
        .background(BeetTheme.surface(appearance), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(BeetTheme.line(appearance)) }
    }

    private func reasoningButton(_ title: String, value: String?) -> some View {
        let selected = selection == value
        return Button(title) { selection = value }
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? Color.white : BeetTheme.secondaryText(appearance))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(
                selected ? BeetTheme.accent : BeetTheme.surfaceStrong(appearance),
                in: Capsule())
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SearchField: View {
    @Environment(\.remoteAppearance) private var appearance
    @Binding var text: String
    var placeholder = "Search conversations"
    var body: some View {
        HStack(spacing: 9) { Image(systemName: "magnifyingglass").foregroundStyle(BeetTheme.secondaryText(appearance)).accessibilityHidden(true); TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(RemoteInstrument.secondaryInk)).textInputAutocapitalization(.never); if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44).contentShape(Rectangle()) }.accessibilityLabel("Clear search").buttonStyle(.plain).foregroundStyle(BeetTheme.secondaryText(appearance)) } }
            .padding(.horizontal, 13).frame(minHeight: 44)
            .remoteRecess()
    }
}

struct SessionRow: View {
    let session: RemoteSessionSummary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if session.isRunning {
                    RemoteChatWorkingDots()
                } else {
                    Image(systemName: session.mode == "code" ? "chevron.left.forwardslash.chevron.right" : "bubble.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RemoteInstrument.secondaryInk)
                }
            }
            .frame(width: 32, height: 32)
            .background(session.isRunning ? BeetTheme.accentBright.opacity(0.12) : RemoteInstrument.recess, in: Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(session.title).font(.body.weight(.medium))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !dynamicTypeSize.isAccessibilitySize {
                        SessionTimestamp(updatedAt: session.updatedAt)
                    }
                }
                Group {
                    if session.isRunning {
                        Text(session.phase.capitalized + "…").foregroundStyle(BeetTheme.accentBright)
                    } else {
                        Text("\(session.workspace.isEmpty ? "Chat" : session.workspace) · ^[\(session.messageCount) message](inflect: true)")
                            .foregroundStyle(RemoteInstrument.secondaryInk)
                    }
                }
                .font(.footnote)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                if dynamicTypeSize.isAccessibilitySize { SessionTimestamp(updatedAt: session.updatedAt) }
            }
        }
        .foregroundStyle(RemoteInstrument.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(session.isRunning ? [.isButton, .updatesFrequently] : .isButton)
    }
}

/// Time for today and yesterday, the weekday this week, the date after that,
/// as Messages does; the date section already says which day.
private struct SessionTimestamp: View {
    let updatedAt: TimeInterval
    var body: some View {
        let date = Date(timeIntervalSince1970: updatedAt)
        let calendar = Calendar.current
        Text(calendar.isDateInToday(date) || calendar.isDateInYesterday(date)
             ? date.formatted(date: .omitted, time: .shortened)
             : date > .now.addingTimeInterval(-7 * 86_400) ? date.formatted(.dateTime.weekday(.wide))
             : date.formatted(date: .numeric, time: .omitted))
            .font(.footnote.monospacedDigit())
            .foregroundStyle(RemoteInstrument.secondaryInk)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct RemoteSessionButtonStyle: ButtonStyle {
    var isLast = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? RemoteInstrument.recess : Color.clear)
            .overlay(alignment: .bottom) {
                if !isLast { RemotePageDivider().padding(.leading, 58) }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Flat list/disclosure rows use immediate tonal feedback. Physical action
/// buttons use RemoteKeyButtonStyle so rows never acquire decorative shells.
struct RemotePressButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? RemoteInstrument.recess.opacity(0.7) : .clear)
            .opacity(isEnabled ? 1 : 0.48)
    }
}

struct RemoteEmptySessions: View {
    let isSearching: Bool
    var isConnected = true
    var onStart: (() -> Void)? = nil
    var onClearSearch: (() -> Void)? = nil
    @Environment(\.remoteAppearance) private var appearance

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isSearching ? "magnifyingglass" : "rectangle.stack.badge.plus")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(BeetTheme.accentBright)
                .accessibilityHidden(true)
            Text(isSearching ? "No matching sessions" : "No sessions yet").font(.headline)
            Text(isSearching
                 ? "Try another title or project name."
                 : "Start a chat, or pick a bot from the Bots screen. You can also continue a conversation from your Mac.")
                .font(.subheadline)
                .foregroundStyle(BeetTheme.secondaryText(appearance))
                .multilineTextAlignment(.center)
            // The copy described an action but never offered one.
            if isSearching, let onClearSearch {
                Button("Clear search", action: onClearSearch)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(RemoteSecondaryButtonStyle())
                    .controlSize(.large)
            } else if !isSearching, let onStart {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onStart()
                } label: {
                    Label("Start a chat", systemImage: "plus.bubble.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 180, minHeight: 46)
                }
                .buttonStyle(RemotePrimaryButtonStyle())
                .disabled(!isConnected)
                .accessibilityHint(isConnected ? "" : "Connect to your Mac first")
                .padding(.top, 2)
            }
        }
        .padding(RemoteInstrument.Space.section)
        .frame(maxWidth: .infinity)

    }
}
