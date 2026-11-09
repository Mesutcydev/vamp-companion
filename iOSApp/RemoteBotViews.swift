import SwiftUI
import UIKit

private struct RemoteInlineNotice: View {
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        if let action {
            Button(action: action) {
                RemoteNoticeLabel(title: title, detail: detail, actionTitle: actionTitle)
            }
            .buttonStyle(RemotePressButtonStyle())
        } else {
            RemoteNoticeLabel(title: title, detail: detail)
        }
    }
}

/// How a run's state reads everywhere on the Bots screens: one word, a color that is
/// never the only signal, and a glyph.
private enum RemoteBotRunStyle {
    static func title(_ run: RemoteBotRun) -> String {
        switch run.state {
        case "queued": "Queued"
        case "running": "Working"
        case "needsApproval": "Needs approval"
        case "needsInput": "Has a question"
        case "recoverable", "interrupted": "Interrupted"
        case "completed": "Done"
        case "failed": "Failed"
        case "stopped": "Stopped"
        default: run.phase.capitalized
        }
    }

    static func color(_ run: RemoteBotRun) -> Color {
        switch run.state {
        case "running", "completed": RemoteInstrument.green
        case "needsApproval", "needsInput", "recoverable": RemoteInstrument.orange
        case "failed": RemoteInstrument.danger
        default: RemoteInstrument.secondaryInk
        }
    }

    static func symbol(_ run: RemoteBotRun) -> String {
        switch run.state {
        case "queued": "clock"
        case "running": "circle.dotted"
        case "needsApproval": "hand.raised.fill"
        case "needsInput": "questionmark.bubble.fill"
        case "recoverable", "interrupted": "pause.circle.fill"
        case "completed": "checkmark.circle.fill"
        case "failed": "exclamationmark.triangle.fill"
        default: "stop.circle.fill"
        }
    }

    /// Names of the unfinished workflow steps a queued run is waiting for.
    static func waitingOn(_ run: RemoteBotRun, in runs: [RemoteBotRun]) -> String? {
        guard run.state == "queued" else { return nil }
        let names = (run.dependencyRunIDs ?? []).compactMap { id in
            runs.first { $0.id == id && $0.state != "completed" }?.profileName
        }
        return names.isEmpty ? nil : ListFormatter.localizedString(byJoining: names)
    }
}

private enum RemoteBotRunAction { case approve, decline, answer, resume, discard }

/// Bots have their own screen: what needs you, what is working, the latest workflow,
/// then every profile and a team objective. The live sections come first because
/// they are why you open this screen while bots run.
struct RemoteBotsView: View {
    let store: RemoteStore
    let onOpen: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.remoteAppearance) private var appearance
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var path: [String] = []
    @State private var selectedBotID: String?
    @State private var isOrchestrating = false
    @State private var workflowPrompt = ""
    @State private var selectedModelID = ""
    @State private var busyRunIDs: Set<UUID> = []

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    library.navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 400)
                } detail: {
                    if let selectedBotID {
                        RemoteBotDetailView(store: store, profile: RemoteBotProfile.profile(id: selectedBotID),
                            selectedModelID: $selectedModelID, onOpen: onOpen)
                            .id(selectedBotID)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "person.2").font(.title2)
                            VampMicroLabel(title: "Choose a specialist")
                            Text("Select a bot to open its workspace.").font(.subheadline)
                        }
                        .foregroundStyle(RemoteInstrument.secondaryInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RemoteInstrument.canvas)
                    }
                }
            } else {
                NavigationStack(path: $path) { library }
            }
        }
        .presentationDetents([.large])
        .remotePageErrors(store: store)
    }

    private var library: some View {
        RemotePageScroll {
            RemotePageHeading(title: "Your team", subtitle: LocalizedStringKey(summary))
            if !botsAvailable {
                RemoteInlineNotice(title: "Bots aren't available on this Mac",
                    detail: "This Mac runs the App Store edition of Vamp Companion. Bots need the website edition.")
                    .clipShape(RoundedRectangle(cornerRadius: 17))
            } else if !store.isConnected {
                RemoteInlineNotice(title: "Mac unreachable",
                    detail: "Bots run on your Mac. Reconnect to start or steer a run.",
                    actionTitle: "Retry", action: { Task { await store.connectSaved() } })
                    .clipShape(RoundedRectangle(cornerRadius: 17))
            } else if let notice = store.backgroundNotice {
                RemoteInlineNotice(title: "Some bot data didn't load", detail: notice,
                    actionTitle: "Retry", action: { Task { try? await store.refresh() } })
                    .clipShape(RoundedRectangle(cornerRadius: 17))
            }
            if !attention.isEmpty {
                RemotePageSection(title: "Needs you", detail: "\(attention.count)", padding: 0) {
                    ForEach(attention) { run in
                        RemoteBotAttentionRow(
                            run: run, enabled: store.isConnected && !busyRunIDs.contains(run.id),
                            onOpen: { open(run.profileID) }, onAction: { perform($0, on: run) })
                        if run.id != attention.last?.id { RemotePageDivider().padding(.leading, 66) }
                    }
                }
            }
            if !working.isEmpty {
                RemotePageSection(title: "Working now", detail: "\(working.count)", padding: 0) {
                    ForEach(working) { run in
                        Button { open(run.profileID) } label: {
                            RemoteBotActivityRow(run: run,
                                waitingOn: RemoteBotRunStyle.waitingOn(run, in: store.botRuns))
                        }
                        .buttonStyle(RemotePageRowButtonStyle())
                        if run.id != working.last?.id { RemotePageDivider().padding(.leading, 66) }
                    }
                }
            }
            if let steps = latestWorkflow {
                RemotePageSection(title: "Latest workflow",
                    detail: "\(steps.filter { $0.state == "completed" }.count) of \(steps.count) done") {
                    RemoteBotWorkflowSteps(steps: steps, onOpen: open)
                }
            }
            RemotePageSection(title: "Specialists", detail: "\(RemoteBotProfile.profiles.count)", padding: 0) {
                ForEach(RemoteBotProfile.profiles) { profile in
                    if horizontalSizeClass == .regular {
                        Button { selectedBotID = profile.id } label: {
                            RemoteBotIndexRow(profile: profile, run: run(for: profile.id))
                                .background(selectedBotID == profile.id ? RemoteInstrument.recess : .clear,
                                    in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(RemotePageRowButtonStyle())
                        .accessibilityAddTraits(selectedBotID == profile.id ? .isSelected : [])
                    } else {
                        NavigationLink(value: profile.id) {
                            RemoteBotIndexRow(profile: profile, run: run(for: profile.id))
                        }.buttonStyle(RemotePageRowButtonStyle())
                    }
                    if profile.id != RemoteBotProfile.profiles.last?.id {
                        RemotePageDivider().padding(.leading, 66)
                    }
                }
            }
            if botsAvailable { RemotePageSection(title: "Work together") { workflowPanel } }
        }
        .refreshable { try? await store.refresh() }
        .navigationTitle("Bots")
        .remotePageChrome()
        .navigationDestination(for: String.self) { id in
            RemoteBotDetailView(store: store, profile: RemoteBotProfile.profile(id: id),
                selectedModelID: $selectedModelID, onOpen: onOpen)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }.vampUtilityAction()
        }
        .keyboardDismissToolbar()
        .task {
            if store.startModels.isEmpty { await store.loadStartModels() }
            if selectedModelID.isEmpty { selectedModelID = store.startModels.first?.id ?? "" }
            try? await store.refresh()
        }
    }

    private var attention: [RemoteBotRun] { store.botRuns.filter(\.needsAttention) }
    private var working: [RemoteBotRun] { store.botRuns.filter(\.isWorking) }

    private var summary: String {
        var parts: [String] = []
        if !attention.isEmpty { parts.append("\(attention.count) need\(attention.count == 1 ? "s" : "") you") }
        if !working.isEmpty { parts.append("\(working.count) working") }
        return parts.isEmpty
            ? "Four specialists and the Assistant. Give one a task, or the team an outcome."
            : parts.joined(separator: " · ")
    }

    /// The newest workflow's steps, in the order they run.
    private var latestWorkflow: [RemoteBotRun]? {
        guard let id = store.botRuns.filter({ $0.workflowID != nil })
            .max(by: { $0.createdAt < $1.createdAt })?.workflowID else { return nil }
        let steps = store.botRuns.filter { $0.workflowID == id }
        func depth(_ run: RemoteBotRun) -> Int {
            (run.dependencyRunIDs ?? []).compactMap { dependency in steps.first { $0.id == dependency } }
                .map { depth($0) + 1 }.max() ?? 0
        }
        return steps.sorted { (depth($0), $0.profileName) < (depth($1), $1.profileName) }
    }

    private func run(for profileID: String) -> RemoteBotRun? {
        store.botRuns.first { $0.profileID == profileID && !$0.isTerminal }
            ?? store.botRuns.first { $0.profileID == profileID }
    }

    private func open(_ profileID: String) {
        if horizontalSizeClass == .regular { selectedBotID = profileID } else { path.append(profileID) }
    }

    private func perform(_ action: RemoteBotRunAction, on run: RemoteBotRun) {
        if action == .answer { open(run.profileID); return }
        // Inserted before the request so a second tap cannot send it twice.
        guard store.isConnected, busyRunIDs.insert(run.id).inserted else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            defer { busyRunIDs.remove(run.id) }
            switch action {
            case .approve: _ = await store.approveBotRun(run.id, approved: true)
            case .decline: _ = await store.approveBotRun(run.id, approved: false)
            case .resume: _ = await store.resumeBotRun(run.id)
            case .discard: _ = await store.stopBotRun(run.id)
            case .answer: break
            }
        }
    }

    private var botsAvailable: Bool { store.hostStatus?.capabilities?.contains("bots") ?? true }

    private var canOrchestrate: Bool {
        store.isConnected && !isOrchestrating && !selectedModelID.isEmpty
            && !workflowPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var workflowPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Describe an outcome. Your Mac splits it into research, browsing, building, and review steps.")
                .font(.subheadline).foregroundStyle(RemoteInstrument.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            RemoteBotModelRow(store: store, selectedModelID: $selectedModelID, label: "Model for the workflow")
            RemoteBotStarters(
                starters: ["Research and implement a feature", "Fix a bug and review it", "Review my changes"],
                tint: BeetTheme.accentBright, appearance: appearance, prompt: $workflowPrompt)
            TextField("Describe the complete outcome", text: $workflowPrompt, prompt: Text("Describe the complete outcome").foregroundStyle(RemoteInstrument.ink.opacity(0.58)), axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(12)
                .remotePageField()
                .accessibilityIdentifier("remote.bot.workflowPrompt")
            Button {
                guard canOrchestrate else { return }
                let prompt = workflowPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                let modelID = selectedModelID
                isOrchestrating = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task {
                    defer { isOrchestrating = false }
                    if await store.orchestrateBots(modelID: modelID, prompt: prompt) {
                        if workflowPrompt.trimmingCharacters(in: .whitespacesAndNewlines) == prompt {
                            workflowPrompt = ""
                        }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            } label: {
                HStack {
                    if isOrchestrating { ProgressView().tint(.white) }
                    Text("Orchestrate")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(RemotePageButtonStyle(primary: true))
            .controlSize(.large)
            .disabled(!canOrchestrate)
            .accessibilityLabel("Orchestrate")
            .accessibilityValue(isOrchestrating ? "Starting workflow" : "")
            .accessibilityHint(store.isConnected ? "" : "Connect to your Mac first")
        }
    }
}

/// The model a run or workflow uses, and where it runs. Opens the same picker as a new chat:
/// local models, the ChatGPT account, and every configured API provider, with search.
private struct RemoteBotModelRow: View {
    let store: RemoteStore
    @Binding var selectedModelID: String
    let label: String
    @Environment(\.remoteAppearance) private var appearance
    @State private var showPicker = false
    @State private var source = "local"

    private var selected: RemoteStartModelOption? { store.startModels.first { $0.id == selectedModelID } }

    var body: some View {
        Button {
            source = selected?.source ?? RemoteModelPickerSheet.sources.first { option in
                store.startModels.contains { $0.source == option }
            } ?? "local"
            showPicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: RemoteModelPickerSheet.sourceIcon(selected?.source ?? "local"))
                    .font(.body)
                    .foregroundStyle(RemoteInstrument.secondaryInk)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected?.name ?? "Choose a model").font(.subheadline.weight(.medium))
                    if let selected {
                        Text("\(RemoteModelPickerSheet.sourceLabel(selected.source)) · \(selected.detail)")
                            .font(.caption).foregroundStyle(RemoteInstrument.secondaryInk).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                    .foregroundStyle(RemoteInstrument.secondaryInk)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(RemoteInstrument.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .remotePageField()
            .contentShape(Rectangle())
        }
        .buttonStyle(RemotePressButtonStyle())
        .accessibilityLabel(label)
        .accessibilityValue(selected.map { "\($0.name), \(RemoteModelPickerSheet.sourceLabel($0.source))" } ?? "None chosen")
        .sheet(isPresented: $showPicker) {
            RemoteModelPickerSheet(
                models: store.startModels,
                source: $source,
                selectedModelID: $selectedModelID,
                onRefresh: { await store.loadStartModels() },
                loadedLocalModel: store.loadedLocalModel,
                isUnloadingModel: store.isUnloadingModel,
                isConnected: store.isConnected,
                onUnload: { await store.unloadLocalModel() })
                .environment(\.remoteAppearance, appearance)
        }
    }
}

/// A run waiting on you, with its decision right in the row. Answers need a text field,
/// so Answer opens the bot instead.
private struct RemoteBotAttentionRow: View {
    let run: RemoteBotRun
    let enabled: Bool
    let onOpen: () -> Void
    let onAction: (RemoteBotRunAction) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var headline: String {
        switch run.state {
        case "needsApproval": "\(run.profileName) needs your approval"
        case "needsInput": "\(run.profileName) has a question"
        default: "\(run.profileName) was interrupted by a restart"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: RemoteBotRunStyle.symbol(run))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(RemoteBotRunStyle.color(run))
                        .frame(width: 40, height: 40)
                        .background(RemoteInstrument.recess, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(headline).font(.body.weight(.medium)).foregroundStyle(RemoteInstrument.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(run.objective).font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(RemoteInstrument.secondaryInk).accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens \(run.profileName)")
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout { actions }
                .disabled(!enabled)
                .padding(.leading, typeSize.isAccessibilitySize ? 0 : 52)
        }
        .padding(14)
    }

    @ViewBuilder private var actions: some View {
        switch run.state {
        case "needsApproval":
            Button("Approve") { onAction(.approve) }.buttonStyle(RemotePageButtonStyle(primary: true))
            Button("Decline", role: .destructive) { onAction(.decline) }.buttonStyle(RemotePageButtonStyle())
        case "needsInput":
            Button("Answer") { onAction(.answer) }.buttonStyle(RemotePageButtonStyle(primary: true))
        default:
            Button("Resume") { onAction(.resume) }.buttonStyle(RemotePageButtonStyle(primary: true))
            Button("Discard", role: .destructive) { onAction(.discard) }.buttonStyle(RemotePageButtonStyle())
        }
    }
}

/// A queued or working run: who, on what, and how far along.
private struct RemoteBotActivityRow: View {
    let run: RemoteBotRun
    let waitingOn: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemotePageSymbol(symbol: RemoteBotProfile.profile(id: run.profileID).symbol, active: run.state == "running")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(run.profileName).font(.body.weight(.medium))
                    if run.state == "running" { ProgressView().controlSize(.mini).accessibilityHidden(true) }
                }
                Text(run.objective).font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                status.font(.caption2.monospacedDigit()).foregroundStyle(RemoteInstrument.secondaryInk)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(RemoteInstrument.secondaryInk).accessibilityHidden(true)
        }
        .foregroundStyle(RemoteInstrument.ink)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        if let waitingOn {
            Text("Waits for \(waitingOn)")
        } else if let queue = run.queuePosition {
            Text("Queue #\(queue)")
        } else if run.createdAt > 0 {
            Text("\(run.phase.capitalized) · \(Text(run.startedAt, style: .relative))")
        } else {
            Text(run.phase.capitalized)
        }
    }
}

/// The newest workflow's steps in run order, each opening its bot.
private struct RemoteBotWorkflowSteps: View {
    let steps: [RemoteBotRun]
    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let objective = steps.first?.objective {
                Text(objective).font(.subheadline).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(steps) { step in
                Button { onOpen(step.profileID) } label: {
                    HStack(spacing: 10) {
                        Group {
                            if step.state == "running" { ProgressView().controlSize(.small) }
                            else {
                                Image(systemName: RemoteBotRunStyle.symbol(step))
                                    .foregroundStyle(RemoteBotRunStyle.color(step))
                            }
                        }
                        .frame(width: 24)
                        .accessibilityHidden(true)
                        Text(step.profileName).font(.subheadline.weight(.medium)).foregroundStyle(RemoteInstrument.ink)
                        Spacer(minLength: 8)
                        Text(RemoteBotRunStyle.title(step)).font(.caption.weight(.medium))
                            .foregroundStyle(RemoteBotRunStyle.color(step))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RemotePageRowButtonStyle())
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// One native list row in the bot index: who the bot is, plus whatever it is doing now.
private struct RemoteBotIndexRow: View {
    let profile: RemoteBotProfile
    let run: RemoteBotRun?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var status: String {
        run.map(RemoteBotRunStyle.title) ?? (profile.isSpecialist ? "Idle" : "Chat")
    }
    private var stateColor: Color {
        if let run { return RemoteBotRunStyle.color(run) }
        return profile.isSpecialist ? RemoteInstrument.secondaryInk : RemoteInstrument.green
    }

    var body: some View {
        HStack(spacing: 12) {
            RemotePageSymbol(symbol: profile.symbol, active: run.map { !$0.isTerminal } ?? false)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name).font(.body.weight(.medium))
                Text(profile.subtitle).font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if dynamicTypeSize.isAccessibilitySize {
                    RemotePageBadge(title: status, color: stateColor)
                }
            }
            Spacer(minLength: 4)
            if !dynamicTypeSize.isAccessibilitySize {
                RemotePageBadge(title: status, color: stateColor)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(RemoteInstrument.secondaryInk).accessibilityHidden(true)
        }
        .foregroundStyle(RemoteInstrument.ink)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The page for one bot: what it is doing now, the two ways to put it to work (a chat
/// session or an autonomous run), and its recent results.
struct RemoteBotDetailView: View {
    let store: RemoteStore
    let profile: RemoteBotProfile
    @Binding var selectedModelID: String
    let onOpen: (UUID) -> Void
    @Environment(\.remoteAppearance) private var appearance
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var prompt = ""
    @State private var detailMode = "chat"
    @State private var steerDraft = ""
    @State private var answerDraft = ""
    @State private var showStartChat = false
    @State private var deferredChatSessionID: UUID?
    @State private var mutationInFlight = false
    @State private var applyRun: RemoteBotRun?
    @State private var confirmApply = false
    @State private var applySummaries: [UUID: String] = [:]
    @State private var fullOutputRunIDs: Set<UUID> = []
    /// nil until the user picks a row; until then the newest result is open.
    @State private var expandedRunID: UUID??

    init(store: RemoteStore, profile: RemoteBotProfile, selectedModelID: Binding<String>,
         initialMode: String = "chat", onOpen: @escaping (UUID) -> Void) {
        self.store = store
        self.profile = profile
        self._selectedModelID = selectedModelID
        self._detailMode = State(initialValue: initialMode == "run" ? "run" : "chat")
        self.onOpen = onOpen
    }

    private var runs: [RemoteBotRun] { store.botRuns.filter { $0.profileID == profile.id } }
    /// The Mac allows one live run per specialist; a restored run counts until resumed or discarded.
    private var activeRun: RemoteBotRun? { runs.first { !$0.isTerminal } }
    private var history: [RemoteBotRun] { Array(runs.filter(\.isTerminal).prefix(5)) }

    private var canStartRun: Bool {
        store.isConnected && !mutationInFlight && !selectedModelID.isEmpty && activeRun == nil
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            RemoteBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    if !store.isConnected {
                        RemoteInlineNotice(
                            title: "Mac unreachable",
                            detail: "Reconnect to start a chat or a run with \(profile.name).",
                            actionTitle: "Retry",
                            action: { Task { await store.connectSaved() } })
                            .clipShape(RoundedRectangle(cornerRadius: 17))
                    }
                    if let run = activeRun { activeRunCard(run) }
                    if profile.isSpecialist {
                        RemotePageSegments(selection: $detailMode, options: [("Chat", "chat"), ("Run", "run")])
                        if detailMode == "chat" { chatCard } else { newRunCard }
                    } else { chatCard }
                    if !history.isEmpty { historySection }
                }
                .padding(16)
                .frame(maxWidth: RemoteInstrument.contentWidth)
                .frame(maxWidth: .infinity)
            }
            .refreshable { try? await store.refresh() }
            .scrollDismissesKeyboard(.interactively)
        }
        .keyboardDismissToolbar()
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .remotePageChrome()
        .fullScreenCover(isPresented: $showStartChat, onDismiss: openDeferredChat) {
            StartSessionSheet(store: store, initialBotID: RemoteBotProfile.resolvedID(profile.id) ?? "") { sessionID in
                deferredChatSessionID = sessionID
                showStartChat = false
            }
        }
        .confirmationDialog("Apply \(profile.name)'s changes?", isPresented: $confirmApply,
                            titleVisibility: .visible, presenting: applyRun) { run in
            Button("Apply to project") { apply(run) }
        } message: { _ in
            Text("\(profile.name) worked on a private copy. The Mac checks the patch first; if it conflicts, your project is left untouched.")
        }
    }

    private func openDeferredChat() {
        guard let sessionID = deferredChatSessionID else { return }
        deferredChatSessionID = nil
        Task { @MainActor in
            await Task.yield()
            onOpen(sessionID)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                RemotePageSymbol(symbol: profile.symbol, active: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name).font(.title3.weight(.semibold))
                    Text(profile.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(BeetTheme.secondaryText(appearance))
                }
                Spacer(minLength: 0)
                if profile.isSpecialist {
                    RemotePageBadge(title: activeRun.map(RemoteBotRunStyle.title) ?? "Idle",
                        color: activeRun.map(RemoteBotRunStyle.color) ?? RemoteInstrument.secondaryInk)
                }
            }
            DisclosureGroup("Role instructions") {
                Text(profile.instruction ?? "A general assistant with no specialist brief. Good for planning, explaining, and deciding.")
                    .font(.subheadline)
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
            .frame(minHeight: 44)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .remotePageCard()
    }

    private var chatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Chat with \(profile.name)", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)
            Text("A normal conversation, with this bot's brief applied.")
                .font(.caption)
                .foregroundStyle(BeetTheme.secondaryText(appearance))
            if !profile.starters.isEmpty {
                Text("Openers").font(.footnote.weight(.semibold))
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
                ForEach(profile.starters, id: \.self) { starter in
                    Text("· \(starter)")
                        .font(.caption)
                        .foregroundStyle(BeetTheme.secondaryText(appearance))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showStartChat = true
            } label: {
                Label("Start a chat", systemImage: "plus.bubble")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(RemotePageButtonStyle(primary: true))
            .disabled(!store.isConnected)
            .accessibilityHint(store.isConnected ? "" : "Connect to your Mac first")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .remotePageCard()
    }

    private func activeRunCard(_ run: RemoteBotRun) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                if run.isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: RemoteBotRunStyle.symbol(run)).foregroundStyle(RemoteBotRunStyle.color(run))
                }
                Text(run.state == "running" ? run.phase.capitalized : RemoteBotRunStyle.title(run))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Group {
                    if let queue = run.queuePosition {
                        Text("Queue #\(queue)")
                    } else if run.state == "running", run.createdAt > 0 {
                        Text(run.startedAt, style: .relative)
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(BeetTheme.secondaryText(appearance))
            }
            Text(run.objective).font(.subheadline).lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if let waitingOn = RemoteBotRunStyle.waitingOn(run, in: store.botRuns) {
                Label("Starts after \(waitingOn) finishes", systemImage: "arrow.triangle.branch")
                    .font(.caption).foregroundStyle(BeetTheme.secondaryText(appearance))
            }
            runMetadata(run)
            if !run.latestOutput.isEmpty {
                Text(run.latestOutput)
                    .font(.caption.monospaced())
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .remotePageField()
            }
            if let error = run.errorMessage {
                Text(error).font(.caption.weight(.semibold)).foregroundStyle(RemoteInstrument.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            runControls(run)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .remotePageCard()
    }

    private func performMutation(_ operation: @escaping () async -> Bool) {
        guard store.isConnected, !mutationInFlight else { return }
        mutationInFlight = true
        Task {
            defer { mutationInFlight = false }
            _ = await operation()
        }
    }

    private var runControlLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    @ViewBuilder
    private func runControls(_ run: RemoteBotRun) -> some View {
        switch run.state {
        case "recoverable":
            // Discard matters: until it is resumed or discarded, this run blocks new work for the bot.
            runControlLayout {
                Button("Resume") { performMutation { await store.resumeBotRun(run.id) } }
                    .buttonStyle(RemotePageButtonStyle(primary: true))
                Button("Discard", role: .destructive) { performMutation { await store.stopBotRun(run.id) } }
                    .buttonStyle(RemotePageButtonStyle())
            }
            .controlSize(.large)
            .disabled(!store.isConnected || mutationInFlight)
        case "needsApproval":
            runControlLayout {
                Button("Approve") { performMutation { await store.approveBotRun(run.id, approved: true) } }
                    .buttonStyle(RemotePageButtonStyle(primary: true))
                Button("Decline", role: .destructive) { performMutation { await store.approveBotRun(run.id, approved: false) } }
                    .buttonStyle(RemotePageButtonStyle())
                if let sessionID = run.sessionID {
                    Button("See request") { onOpen(sessionID) }.buttonStyle(RemotePageButtonStyle())
                }
            }
            .controlSize(.large)
            .disabled(!store.isConnected || mutationInFlight)
        case "needsInput":
            TextField("Answer \(profile.name)", text: $answerDraft, prompt: Text("Answer \(profile.name)").foregroundStyle(RemoteInstrument.secondaryInk), axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(12)
                .remotePageField()
            runControlLayout {
                Button("Send answer") {
                    let answer = answerDraft
                    performMutation {
                        let success = await store.answerBotRun(run.id, answer: answer)
                        if success && answerDraft == answer { answerDraft = "" }
                        return success
                    }
                }
                .buttonStyle(RemotePageButtonStyle(primary: true))
                .disabled(!store.isConnected || answerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mutationInFlight)
                if let sessionID = run.sessionID {
                    Button("See question") { onOpen(sessionID) }.buttonStyle(RemotePageButtonStyle())
                }
            }
            .controlSize(.large)
        default:
            // A queued or starting run has no session yet, and the Mac refuses to steer it.
            if run.sessionID != nil {
                TextField("Steer this run", text: $steerDraft, prompt: Text("Steer this run").foregroundStyle(RemoteInstrument.secondaryInk), axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .remotePageField()
            }
            runControlLayout {
                if let sessionID = run.sessionID {
                    Button("Steer") {
                        let message = steerDraft
                        performMutation {
                            let success = await store.steerBotRun(run.id, message: message)
                            if success && steerDraft == message { steerDraft = "" }
                            return success
                        }
                    }
                    .disabled(!store.isConnected || steerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mutationInFlight)
                    Button("Inspect") { onOpen(sessionID) }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button("Stop", role: .destructive) { performMutation { await store.stopBotRun(run.id) } }
                    .disabled(!store.isConnected || mutationInFlight)
            }
            .buttonStyle(RemotePageButtonStyle())
            .controlSize(.large)
        }
    }

    private func runMetadata(_ run: RemoteBotRun) -> some View {
        HStack(spacing: 9) {
            Label(source(run), systemImage: "cpu")
            if run.workflowID != nil {
                Label("Workflow", systemImage: "point.3.connected.trianglepath.dotted")
            }
            if let retry = run.retryCount, retry > 0 {
                Label("Retry \(retry)", systemImage: "arrow.clockwise")
            }
        }
        .font(.caption2)
        .foregroundStyle(BeetTheme.secondaryText(appearance))
    }

    private func source(_ run: RemoteBotRun) -> String {
        switch run.resourceClass {
        case "localInference": "On your Mac"
        case "codex": "ChatGPT"
        default: "API model"
        }
    }

    private var newRunCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Run autonomously", systemImage: "play.circle")
                .font(.headline)
            Text("\(profile.name) works on a private copy of your project and reports back. You choose whether to apply its changes.")
                .font(.caption)
                .foregroundStyle(BeetTheme.secondaryText(appearance))
                .fixedSize(horizontal: false, vertical: true)
            RemoteBotModelRow(store: store, selectedModelID: $selectedModelID, label: "Model for this run")
            if !profile.starters.isEmpty {
                RemoteBotStarters(starters: profile.starters, tint: profile.tint, appearance: appearance, prompt: $prompt)
            }
            TextField("Task for \(profile.name)", text: $prompt, prompt: Text("Task for \(profile.name)").foregroundStyle(RemoteInstrument.secondaryInk), axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .padding(12)
                .remotePageField()
                .accessibilityIdentifier("remote.bot.runPrompt")
            Button {
                guard canStartRun else { return }
                let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                let modelID = selectedModelID
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                performMutation {
                    let success = await store.startBotRun(profileID: profile.id, modelID: modelID, prompt: text)
                    if success {
                        if prompt.trimmingCharacters(in: .whitespacesAndNewlines) == text { prompt = "" }
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    return success
                }
            } label: {
                HStack {
                    if mutationInFlight { ProgressView().tint(.white) }
                    Text("Start run")
                }.frame(maxWidth: .infinity)
            }
            .buttonStyle(RemotePageButtonStyle(primary: true))
            .controlSize(.large)
            .disabled(!canStartRun)
            .accessibilityLabel("Start run")
            .accessibilityValue(mutationInFlight ? "Starting run" : "")
            .accessibilityHint(store.isConnected ? "" : "Connect to your Mac first")
            if activeRun != nil {
                Text("\(profile.name) is already on a run. Finish, stop, or discard it to start another.")
                    .font(.caption)
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .remotePageCard()
    }

    // MARK: Recent runs

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            RemotePageSectionHeading(title: "Recent runs", detail: "\(history.count)")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(history) { run in
                    historyRow(run)
                    if run.id != history.last?.id { RemotePageDivider() }
                }
            }
            .remotePageCard()
        }
    }

    private func historyRow(_ run: RemoteBotRun) -> some View {
        let expanded = (expandedRunID ?? history.first?.id) == run.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                expandedRunID = .some(expanded ? nil : run.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: RemoteBotRunStyle.symbol(run))
                        .foregroundStyle(RemoteBotRunStyle.color(run))
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.objective).font(.subheadline.weight(.medium))
                            .lineLimit(expanded ? 4 : 1)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 4) {
                            Text(RemoteBotRunStyle.title(run)).foregroundStyle(RemoteBotRunStyle.color(run))
                            if run.updatedAt > 0 {
                                Text("·")
                                Text(run.finishedAt, format: .relative(presentation: .named))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(BeetTheme.secondaryText(appearance))
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(RemoteInstrument.secondaryInk)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(RemoteInstrument.ink)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RemotePageRowButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(expanded ? "Hides the result" : "Shows the result")
            if expanded {
                runResult(run).padding([.horizontal, .bottom], 14)
            }
        }
    }

    private func runResult(_ run: RemoteBotRun) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if let error = run.errorMessage {
                Text(error).font(.caption.weight(.semibold)).foregroundStyle(RemoteInstrument.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let evidence = run.evidence {
                let criteria = (run.criteriaTotal ?? 0) > 0
                    ? " · \(run.criteriaMet ?? 0)/\(run.criteriaTotal ?? 0) criteria met" : ""
                Label(evidence + criteria, systemImage: "checkmark.seal")
                    .font(.caption2)
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
            }
            if !run.finalOutput.isEmpty {
                let full = fullOutputRunIDs.contains(run.id)
                Text(run.finalOutput)
                    .font(.caption)
                    .lineLimit(full ? nil : 8)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .remotePageField()
                Button(full ? "Show less" : "Show full result") {
                    if full { fullOutputRunIDs.remove(run.id) } else { fullOutputRunIDs.insert(run.id) }
                }
                .font(.caption.weight(.semibold))
                .frame(minHeight: 44)
            }
            if let summary = applySummaries[run.id] ?? (run.appliedAt != nil ? "Applied to your project." : nil) {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(RemoteInstrument.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
            runControlLayout {
                if run.canApply == true && applySummaries[run.id] == nil {
                    Button {
                        applyRun = run
                        confirmApply = true
                    } label: {
                        HStack {
                            if mutationInFlight { ProgressView().tint(.white) }
                            Label("Apply changes", systemImage: "square.and.arrow.down.on.square")
                        }
                    }
                    .buttonStyle(RemotePageButtonStyle(primary: true))
                    .disabled(!store.isConnected || mutationInFlight)
                    .accessibilityHint(store.isConnected ? "Merges this run's private copy into your project" : "Connect to your Mac first")
                }
                if let sessionID = run.sessionID {
                    Button("Open transcript") { onOpen(sessionID) }
                        .buttonStyle(RemotePageButtonStyle())
                }
            }
            .controlSize(.large)
        }
    }

    private func apply(_ run: RemoteBotRun) {
        performMutation {
            guard let summary = await store.applyBotRun(run.id) else { return false }
            applySummaries[run.id] = summary
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        }
    }
}

struct RemoteBotProfile: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let starters: [String]
    let instruction: String?

    static let general = RemoteBotProfile(
        id: "general", name: "Assistant", subtitle: "Balanced assistant",
        starters: ["Plan this task", "Explain this project", "Help me decide"],
        instruction: nil)
    static let profiles: [RemoteBotProfile] = [
        general,
        .init(id: "builder", name: "Builder", subtitle: "Build and fix",
              starters: ["Fix the current issue", "Build this feature", "Run the tests"],
              instruction: "Work as a focused software builder. Inspect the existing project, implement the request completely, preserve unrelated work, and verify the result."),
        .init(id: "reviewer", name: "Reviewer", subtitle: "Diff and risks",
              starters: ["Review my changes", "Check for regressions", "Audit this diff"],
              instruction: "Work as a careful code reviewer. Inspect the current changes, identify concrete bugs and regressions first, and give evidence-backed recommendations. Do not edit unless asked."),
        .init(id: "navigator", name: "Navigator", subtitle: "Browser control",
              starters: ["Open and inspect this site", "Test this web flow", "Compare these pages"],
              instruction: "Work as a browser navigator. Use the available browser tools directly, keep actions scoped to the request, and summarize what changed or what you found."),
        .init(id: "researcher", name: "Researcher", subtitle: "Sources and synthesis",
              starters: ["Research this topic", "Compare the best options", "Verify this claim"],
              instruction: "Work as a technical researcher. Prefer primary sources, compare evidence, distinguish facts from inference, and return concise actionable findings."),
    ]

    static func profile(id: String) -> RemoteBotProfile {
        profiles.first(where: { $0.id == id }) ?? general
    }

    static func resolvedID(_ id: String?) -> String? {
        guard let id, !id.isEmpty, id != general.id else { return nil }
        return id
    }

    @MainActor var tint: Color {
        BeetTheme.accentBright
    }

    var symbol: String {
        switch id {
        case "builder": "hammer"
        case "reviewer": "checkmark.shield"
        case "navigator": "safari"
        case "researcher": "text.book.closed"
        default: "sparkles"
        }
    }

    /// Only the specialists have an autonomous-run backend; the general
    /// assistant is chat-only.
    var isSpecialist: Bool { id != RemoteBotProfile.general.id }
}

/// Suggested tasks that fill the field for review; they never start work on their own.
struct RemoteBotStarters: View {
    let starters: [String]
    let tint: Color
    let appearance: RemoteAppearance
    @Binding var prompt: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(starters, id: \.self) { starter in
                    Button(starter) {
                        prompt = starter
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(RemoteInstrument.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(RemoteInstrument.recess, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Capsule())
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Suggested tasks")
    }
}
