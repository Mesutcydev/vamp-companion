import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

/// Bots have their own screen now: an index of every profile with its live run
/// state, and a detail page per bot. They used to be split between a cramped
/// home-screen strip (start a chat) and a grid of dense cards (start a run), so
/// nothing ever said what a bot is or what it is currently doing.
struct RemoteBotsView: View {
    let store: RemoteStore
    let onOpen: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.remoteAppearance) private var appearance
    @State private var path: [String] = []
    @State private var selectedBotID: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isOrchestrating = false
    @State private var workflowPrompt = ""
    @State private var selectedModelID = ""

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    library.navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
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
            RemotePageHeading(title: "Your team", subtitle: "Five perspectives. Choose a specialist or give the team one outcome.")
            if !store.isConnected {
                RemoteInlineNotice(title: "Mac unreachable",
                    detail: "Bots run on your Mac. Reconnect to start or steer a run.",
                    actionTitle: "Retry", action: { Task { await store.connectSaved() } })
                    .clipShape(RoundedRectangle(cornerRadius: 17))
            } else if let notice = store.backgroundNotice {
                RemoteInlineNotice(title: "Some bot data didn't load", detail: notice,
                    actionTitle: "Retry", action: { Task { try? await store.refresh() } })
                    .clipShape(RoundedRectangle(cornerRadius: 17))
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
            RemotePageSection(title: "Work together") { workflowPanel }
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

    private func run(for profileID: String) -> RemoteBotRun? {
        store.botRuns.first { $0.profileID == profileID && !$0.isTerminal }
            ?? store.botRuns.first { $0.profileID == profileID }
    }

    private var canOrchestrate: Bool {
        store.isConnected && !isOrchestrating && !selectedModelID.isEmpty
            && !workflowPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var workflowPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Describe an outcome and the bots divide the work between them.")
                .font(.subheadline).foregroundStyle(RemoteInstrument.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if !store.startModels.isEmpty {
                Picker("Model", selection: $selectedModelID) {
                    if selectedModelID.isEmpty { Text("Choose model").tag("") }
                    ForEach(store.startModels) { Text($0.name).tag($0.id) }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityLabel("Model for the workflow")
            }
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

/// One native list row in the bot index: who the bot is, plus whatever it is doing now.
private struct RemoteBotIndexRow: View {
    let profile: RemoteBotProfile
    let run: RemoteBotRun?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var status: String {
        run?.phase ?? (profile.isSpecialist ? "Idle" : "Chat")
    }
    private var stateColor: Color {
        if run?.state == "failed" { return RemoteInstrument.danger }
        if let run, !run.isTerminal { return RemoteInstrument.green }
        if !profile.isSpecialist { return RemoteInstrument.green }
        return RemoteInstrument.secondaryInk
    }

    var body: some View {
        HStack(spacing: 12) {
            RemotePageSymbol(symbol: profile.symbol, active: run.map { !$0.isTerminal } ?? false)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name).font(.body.weight(.medium))
                Text(profile.subtitle).font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if dynamicTypeSize.isAccessibilitySize {
                    RemotePageBadge(title: status.capitalized, color: stateColor)
                }
            }
            Spacer(minLength: 4)
            if !dynamicTypeSize.isAccessibilitySize {
                RemotePageBadge(title: status.capitalized, color: stateColor)
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

/// The page for one bot: what it does, what it is running, and the two ways to
/// put it to work — a chat session, or an autonomous run.
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
    @State private var confirmApply = false
    @State private var applySummaries: [UUID: String] = [:]
    @State private var outputExpanded = false

    init(store: RemoteStore, profile: RemoteBotProfile, selectedModelID: Binding<String>,
         initialMode: String = "chat", onOpen: @escaping (UUID) -> Void) {
        self.store = store
        self.profile = profile
        self._selectedModelID = selectedModelID
        self._detailMode = State(initialValue: initialMode == "run" ? "run" : "chat")
        self.onOpen = onOpen
    }

    private var run: RemoteBotRun? {
        store.botRuns.first { $0.profileID == profile.id && !$0.isTerminal }
            ?? store.botRuns.first { $0.profileID == profile.id }
    }

    /// The Mac allows one live run per specialist; a restored run counts until resumed or discarded.
    private var isBusy: Bool { run.map { !$0.isTerminal } ?? false }

    private var canStartRun: Bool {
        store.isConnected && !mutationInFlight && !selectedModelID.isEmpty && !isBusy
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
                    if let run, !run.isTerminal { activeRunCard(run) }
                    if profile.isSpecialist {
                        RemotePageSegments(selection: $detailMode, options: [("Chat", "chat"), ("Run", "run")])
                        if detailMode == "chat" { chatCard } else { newRunCard }
                    } else { chatCard }
                    if let run, run.isTerminal { lastRunCard(run) }
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
                Text("Openers").font(.system(.caption2, design: .monospaced, weight: .medium)).tracking(0.8)
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
                ProgressView().controlSize(.small)
                Text(run.phase.capitalized).font(.subheadline.weight(.semibold))
                Spacer()
                if let queue = run.queuePosition {
                    Text("Queue #\(queue)").font(.caption)
                        .foregroundStyle(BeetTheme.secondaryText(appearance))
                }
            }
            Text(run.prompt).font(.subheadline).lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            runMetadata(run)
            if !run.latestOutput.isEmpty {
                Text(run.latestOutput)
                    .font(.caption)
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let gate = run.pendingInteraction ?? run.errorMessage {
                Text(gate).font(.caption.weight(.semibold)).foregroundStyle(BeetTheme.accentBright)
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
            }
            .controlSize(.large)
            .disabled(!store.isConnected || mutationInFlight)
        case "needsInput":
            TextField("Answer \(profile.name)", text: $answerDraft, prompt: Text("Answer \(profile.name)").foregroundStyle(RemoteInstrument.secondaryInk), axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(12)
                .remotePageField()
            Button("Send answer") {
                let answer = answerDraft
                performMutation {
                    let success = await store.answerBotRun(run.id, answer: answer)
                    if success && answerDraft == answer { answerDraft = "" }
                    return success
                }
            }
            .buttonStyle(RemotePageButtonStyle(primary: true))
            .controlSize(.large)
            .disabled(!store.isConnected || answerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mutationInFlight)
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
            Label(run.resourceClass ?? "remote", systemImage: "cpu")
            if run.workflowID != nil {
                Label("Workflow", systemImage: "point.3.connected.trianglepath.dotted")
            }
            if let dependencies = run.dependencyRunIDs, !dependencies.isEmpty {
                Label("\(dependencies.count) deps", systemImage: "arrow.triangle.branch")
            }
            if let retry = run.retryCount, retry > 0 {
                Label("Retry \(retry)", systemImage: "arrow.clockwise")
            }
        }
        .font(.caption2)
        .foregroundStyle(BeetTheme.secondaryText(appearance))
    }

    private var newRunCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Run autonomously", systemImage: "play.circle")
                .font(.headline)
            Text("\(profile.name) works the task on its own and reports back.")
                .font(.caption)
                .foregroundStyle(BeetTheme.secondaryText(appearance))
            if !store.startModels.isEmpty {
                Picker("Model", selection: $selectedModelID) {
                    ForEach(store.startModels) { Text($0.name).tag($0.id) }
                }
                .accessibilityLabel("Model for this run")
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
            if isBusy {
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

    private func lastRunCard(_ run: RemoteBotRun) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAST RUN").font(.system(.caption2, design: .monospaced, weight: .medium)).tracking(0.8)
                .foregroundStyle(BeetTheme.secondaryText(appearance))
            HStack(spacing: 8) {
                Text(run.phase.capitalized).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                RemotePageBadge(title: run.state.capitalized,
                    color: run.state == "completed" ? RemoteInstrument.green
                        : run.state == "failed" ? RemoteInstrument.danger : RemoteInstrument.secondaryInk)
            }
            Text(run.prompt).font(.caption).foregroundStyle(BeetTheme.secondaryText(appearance))
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if let error = run.errorMessage {
                Text(error).font(.caption.weight(.semibold)).foregroundStyle(RemoteInstrument.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let evidence = run.evidence {
                let criteria = (run.criteriaTotal ?? 0) > 0
                    ? " · \(run.criteriaMet ?? 0)/\(run.criteriaTotal ?? 0) criteria met" : ""
                Label(evidence.capitalized + criteria, systemImage: "checkmark.seal")
                    .font(.caption2)
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
            }
            if !run.finalOutput.isEmpty {
                Text(run.finalOutput)
                    .font(.caption)
                    .lineLimit(outputExpanded ? nil : 8)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .remotePageField()
                Button(outputExpanded ? "Show less" : "Show full result") { outputExpanded.toggle() }
                    .font(.caption.weight(.semibold))
                    .frame(minHeight: 44)
            }
            if let trace = run.traceID {
                Text("Trace \(trace.suffix(10)) · \(run.artifacts?.count ?? 0) artifacts")
                    .font(.caption2.monospaced())
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
            }
            if let summary = applySummaries[run.id] ?? (run.appliedAt != nil ? "Applied to your project." : nil) {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(RemoteInstrument.green)
                    .fixedSize(horizontal: false, vertical: true)
            } else if run.canApply == true {
                Button {
                    confirmApply = true
                } label: {
                    HStack {
                        if mutationInFlight { ProgressView().tint(.white) }
                        Label("Apply changes to project", systemImage: "square.and.arrow.down.on.square")
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(RemotePageButtonStyle(primary: true))
                .controlSize(.large)
                .disabled(!store.isConnected || mutationInFlight)
                .accessibilityHint(store.isConnected ? "Merges this run's private copy into your project" : "Connect to your Mac first")
            }
            if let sessionID = run.sessionID {
                Button("Open the transcript") { onOpen(sessionID) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(RemotePageButtonStyle())
                    .controlSize(.large)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .remotePageCard()
        .confirmationDialog("Apply \(profile.name)'s changes?", isPresented: $confirmApply, titleVisibility: .visible) {
            Button("Apply to project") {
                performMutation {
                    guard let summary = await store.applyBotRun(run.id) else { return false }
                    applySummaries[run.id] = summary
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    return true
                }
            }
        } message: {
            Text("\(profile.name) worked on a private copy. The Mac checks the patch first; if it conflicts, your project is left untouched.")
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

private struct SpecialistIndexMark: View {
    let profile: RemoteBotProfile

    var body: some View {
        Text(String(format: "%02d", (RemoteBotProfile.profiles.firstIndex(where: { $0.id == profile.id }) ?? 0) + 1))
            .font(.system(.subheadline, design: .monospaced, weight: .medium))
            .foregroundStyle(RemoteInstrument.secondaryInk)
            .frame(minWidth: 30, minHeight: 44, alignment: .topLeading)
            .accessibilityHidden(true)
    }
}

struct RemoteBotChooser: View {
    @Binding var selectedBotID: String

    private var effectiveID: String {
        selectedBotID.isEmpty ? RemoteBotProfile.general.id : selectedBotID
    }

    var body: some View {
        RemotePageScroll {
            RemotePageHeading(title: "Choose a bot", subtitle: "A different perspective for your conversation.")
            VStack(spacing: 0) {
                ForEach(RemoteBotProfile.profiles) { profile in
                    Button {
                        selectedBotID = RemoteBotProfile.resolvedID(profile.id) ?? ""
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        RemoteBotIndexRow(profile: profile, run: nil)
                            .background(effectiveID == profile.id ? RemoteInstrument.recess : .clear,
                                in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(RemotePageRowButtonStyle())
                    .accessibilityAddTraits(effectiveID == profile.id ? .isSelected : [])
                    if profile.id != RemoteBotProfile.profiles.last?.id {
                        RemotePageDivider().padding(.leading, 66)
                    }
                }
            }.remotePageCard()
        }.remotePageChrome()
    }

}

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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
                    .padding(.horizontal, 11)
                    .frame(minHeight: 34)
                    .background(RemoteInstrument.panel, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(RemoteInstrument.seam, lineWidth: 0.75))
                    .buttonStyle(RemotePressButtonStyle())
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityLabel("Suggested tasks")
    }
}
