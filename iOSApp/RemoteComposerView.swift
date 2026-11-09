import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct VampComposerPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// One floating piece of glass: the message on top, and a single row of
/// controls under it. The editor grows with the message up to six lines.
struct RemoteComposer: View {
    @Binding var draft: String
    let isRunning: Bool
    var isReachable: Bool = true
    var isSending: Bool = false
    var hasError: Bool = false
    let onSend: () -> Void
    var onQueue: (() -> Void)? = nil
    var onSteer: (() -> Void)? = nil
    let onStop: () -> Void
    var modelName: String? = nil
    var onSelectModel: (() -> Void)? = nil
    var onShare: (() -> Void)? = nil
    var modeName: String? = nil
    var hasImages = false
    var onAddPhotos: (() -> Void)? = nil
    var onAddImageFiles: (() -> Void)? = nil
    // A new chat reuses this composer under its own identifiers and gate.
    var editorID = "remote.composer.editor"
    var primaryID = "remote.composer.primary"
    var sendLabel = "Send"
    var placeholderText: String? = nil
    var canSend = true
    var autoFocus = false

    @State private var showTools = false
    @State private var showCommandsFallback = false
    @FocusState private var focused: Bool

    private var hasDraft: Bool { hasImages || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var unavailable: Bool { !isReachable || isSending || (!isRunning && (!hasDraft || !canSend)) }
    private var primaryLabel: String { isRunning ? (hasDraft ? "Queue follow-up" : "Stop the agent") : sendLabel }
    private var primarySymbol: String { isRunning ? (hasDraft ? "text.badge.plus" : "stop.fill") : "arrow.up" }
    private var placeholder: String {
        if !isReachable { return "Draft while reconnecting…" }
        if let placeholderText { return placeholderText }
        return isRunning ? "Queue a follow-up or steer…" : "Message Vamp…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RemoteComposerEditor(draft: $draft, placeholder: placeholder, identifier: editorID, focused: $focused)
            RemoteComposerControls(
                modelName: modelName, modeName: modeName, status: statusTitle, statusColor: statusColor,
                statusActive: isReachable && (isRunning || isSending),
                modelEnabled: onSelectModel != nil && !isRunning && isReachable,
                shareEnabled: onShare != nil && isReachable,
                primaryLabel: primaryLabel, primarySymbol: primarySymbol,
                unavailable: unavailable, isSending: isSending,
                showsSteer: isRunning && hasDraft && !hasImages, steerEnabled: isReachable && !isSending,
                // While a follow-up is being written the primary key queues it,
                // so Stop moves beside it instead of disappearing.
                showsStop: isRunning && hasDraft,
                onModel: { onSelectModel?() }, onShare: { onShare?() },
                onTools: { showTools = true }, onPrimary: primaryAction,
                onSteer: { (onSteer ?? onSend)() }, onStop: onStop,
                primaryID: primaryID, hasShare: onShare != nil,
                onAddPhotos: onAddPhotos, onAddImageFiles: onAddImageFiles)
        }
        .padding(4)
        .vampGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: RemoteInstrument.composerWidth)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showTools) {
            RemoteComposerToolsSheet { command in
                showTools = false
                choose(command)
            }
        }
        .alert("Commands", isPresented: $showCommandsFallback) {
            ForEach(RemoteComposerCommand.commands) { command in
                Button(command.title) { choose(command) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Choose a prompt to insert into your message.") }
        .task {
            guard autoFocus else { return }
            try? await Task.sleep(for: .milliseconds(350))
            focused = true
        }
        .onChange(of: draft) { _, value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "/commands" {
                draft = ""
                showCommandsFallback = true
            }
        }
    }

    private func choose(_ command: RemoteComposerCommand) {
        draft = command.prompt
        Task { @MainActor in
            await Task.yield()
            focused = true
        }
    }

    private var statusTitle: String {
        if hasError { return "Error" }
        if !isReachable { return "Offline" }
        if isSending { return "Sending" }
        if isRunning { return "Working" }
        return "Ready"
    }

    private var statusColor: Color {
        if hasError { return RemoteInstrument.danger }
        if !isReachable { return RemoteInstrument.secondaryInk }
        if isRunning || isSending { return BeetTheme.accentBright }
        return RemoteInstrument.green
    }

    private func primaryAction() {
        guard !unavailable else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if isRunning, hasDraft { (onQueue ?? onSend)() }
        else if isRunning { onStop() }
        else { onSend() }
    }
}

private struct RemoteComposerEditor: View {
    @Binding var draft: String
    let placeholder: String
    let identifier: String
    var focused: FocusState<Bool>.Binding
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var maximumLines: Int {
        if dynamicTypeSize.isAccessibilitySize { return verticalSizeClass == .compact ? 1 : 3 }
        return verticalSizeClass == .compact ? 3 : 6
    }

    var body: some View {
        TextField("", text: $draft, axis: .vertical)
            .accessibilityLabel("Message")
            .accessibilityIdentifier(identifier)
            .font(.body)
            .lineLimit(1...maximumLines)
            .fixedSize(horizontal: false, vertical: true)
            .focused(focused)
            .foregroundStyle(RemoteInstrument.ink)
            .tint(BeetTheme.accentBright)
            // ponytail: SwiftUI truncates a `prompt` to one line on a
            // vertical-axis field, so at accessibility sizes this read
            // "Queue a follow-u…". An overlay scales to fit instead.
            .overlay(alignment: .leading) {
                if draft.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(RemoteInstrument.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
    }
}

private struct RemoteComposerControls: View {
    let modelName: String?
    let modeName: String?
    let status: String
    let statusColor: Color
    let statusActive: Bool
    let modelEnabled: Bool
    let shareEnabled: Bool
    let primaryLabel: String
    let primarySymbol: String
    let unavailable: Bool
    let isSending: Bool
    let showsSteer: Bool
    let steerEnabled: Bool
    let showsStop: Bool
    let onModel: () -> Void
    let onShare: () -> Void
    let onTools: () -> Void
    let onPrimary: () -> Void
    let onSteer: () -> Void
    let onStop: () -> Void
    let primaryID: String
    let hasShare: Bool
    var onAddPhotos: (() -> Void)? = nil
    var onAddImageFiles: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var modelTitle: String {
        guard let modelName, !modelName.isEmpty else { return "Choose model" }
        if let open = modelName.lastIndex(of: "("), open > modelName.startIndex, modelName.hasSuffix(")") {
            return String(modelName[..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return modelName
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                model
                HStack(spacing: 0) { share; tools; Spacer(minLength: 4); trailing }
            }
        } else {
            HStack(spacing: 2) {
                share
                model.layoutPriority(-1)
                tools
                Spacer(minLength: 4)
                trailing
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if showsStop {
            Button(action: onStop) {
                Image(systemName: "stop.fill").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RemoteInstrument.danger)
                    .frame(width: 34, height: 34)
                    .background(RemoteInstrument.danger.opacity(0.14), in: Circle())
                    .frame(width: 44, height: 44).contentShape(Circle())
            }
            .buttonStyle(VampComposerPressStyle())
            .disabled(!steerEnabled)
            .accessibilityLabel("Stop the agent")
        }
        if showsSteer {
            Button(action: onSteer) {
                Text("Steer").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(RemoteInstrument.recess, in: Capsule())
                    .frame(minHeight: 44).contentShape(Capsule())
            }
            .buttonStyle(VampComposerPressStyle())
            .foregroundStyle(RemoteInstrument.ink)
            .disabled(!steerEnabled)
            .accessibilityLabel("Steer")
            .accessibilityHint("Redirects the current task instead of waiting")
        }
        Button(action: onPrimary) {
            ZStack {
                if isSending { ProgressView().tint(.white) }
                else { Image(systemName: primarySymbol).font(.system(size: 15, weight: .bold)) }
            }
            .foregroundStyle(unavailable ? RemoteInstrument.secondaryInk : Color.white)
            .frame(width: 34, height: 34)
            .background(unavailable ? RemoteInstrument.recess : BeetTheme.accent, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(VampComposerPressStyle())
        .disabled(unavailable)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(isSending ? "Sending" : primaryLabel)
        .accessibilityIdentifier(primaryID)
    }

    private var model: some View {
        Button(action: onModel) {
            HStack(spacing: 6) {
                RemoteLivePulse(color: statusColor, active: statusActive, fast: true).scaleEffect(0.75)
                Text(modelTitle).font(.footnote.weight(.semibold)).lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                    .foregroundStyle(RemoteInstrument.secondaryInk)
            }
            .foregroundStyle(RemoteInstrument.ink)
            .padding(.leading, 6).padding(.trailing, 10)
            .frame(minHeight: 30)
            .background(RemoteInstrument.recess.opacity(0.75), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(VampComposerPressStyle())
        .disabled(!modelEnabled)
        .accessibilityLabel("Model, \(modelName ?? "not selected")")
        .accessibilityValue([modeName, status].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("remote.composer.model")
    }

    private var tools: some View {
        Button(action: onTools) {
            iconLabel("square.grid.2x2")
        }
        .buttonStyle(VampComposerPressStyle())
        .accessibilityLabel("Tools and context")
    }

    @ViewBuilder
    private var share: some View {
        if !hasShare {
            EmptyView()
        } else if onAddPhotos != nil || onAddImageFiles != nil {
            Menu {
                if let onAddPhotos { Button("Photo Library", systemImage: "photo", action: onAddPhotos) }
                if let onAddImageFiles { Button("Image from Files", systemImage: "folder", action: onAddImageFiles) }
                Divider()
                Button("Share with Mac", systemImage: "square.and.arrow.up", action: onShare)
            } label: { iconLabel("plus") }
            .disabled(!shareEnabled)
            .accessibilityLabel("Add image or share with Mac")
            .accessibilityIdentifier("remote.composer.share")
        } else {
            Button(action: onShare) { iconLabel("plus") }
                .buttonStyle(VampComposerPressStyle())
                .disabled(!shareEnabled)
                .accessibilityLabel("Share clipboard or files with Mac")
                .accessibilityIdentifier("remote.composer.share")
        }
    }

    private func iconLabel(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(RemoteInstrument.ink)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

struct RemoteComposerCommand: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let prompt: String

    static let commands: [RemoteComposerCommand] = [
        .init(id: "diff", title: "Git diff", detail: "Review uncommitted changes", symbol: "arrow.left.arrow.right",
              prompt: "Inspect the current git diff. Summarize the changes, flag concrete bugs or regressions, and suggest the smallest useful test plan. Do not edit files unless I ask."),
        .init(id: "context", title: "@context", detail: "Use the current workspace and chat", symbol: "paperclip",
              prompt: "@context Use the current workspace, active session, recent messages, and available tool state as context for this request: "),
        .init(id: "browser-open", title: "Open page", detail: "Navigate with browser control", symbol: "safari",
              prompt: "Use browser control to open this URL: "),
        .init(id: "browser-read", title: "Read page", detail: "Inspect the current browser page", symbol: "doc.text.magnifyingglass",
              prompt: "Use browser control to inspect the current page. Summarize its visible content and important interactive elements."),
        .init(id: "browser-shot", title: "Browser screenshot", detail: "Capture and analyze the page", symbol: "camera.viewfinder",
              prompt: "Use browser control to take a screenshot of the current page and analyze what is visible."),
        .init(id: "status", title: "System status", detail: "Check Mac and Tailscale", symbol: "waveform.path.ecg",
              prompt: "Check the Mac and Tailscale status using the dedicated read-only status tools. Report the result without navigating system UI."),
    ]
}

/// Long authorization text remains readable without pushing decisions off screen.
struct RemoteApprovalSummary: View {
    let text: String
    @State private var contentHeight: CGFloat = 1

    var body: some View {
        ScrollView {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(RemoteInstrument.secondaryInk)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(height: min(max(contentHeight, 1), 140))
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct PendingInteractionView: View {
    let pending: RemotePendingInteraction
    var isResolving = false
    let onResolve: (String) -> Void
    @Environment(\.remoteAppearance) private var appearance
    @State private var answer = ""
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RemoteInstrument.orange)
                    .frame(width: 30, height: 30)
                    .background(RemoteInstrument.orange.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    if let toolName = pending.toolName, !toolName.isEmpty {
                        Text(toolName).font(.caption.monospaced())
                            .foregroundStyle(BeetTheme.secondaryText(appearance))
                    }
                }
                Spacer()
                RemotePageBadge(title: pending.kind == "approval" ? "Review" : "Input", color: BeetTheme.accentBright)
            }

            RemoteApprovalSummary(text: pending.summary ?? pending.content ?? "Vamp Assistant needs your input.")

            // The change itself, not a description of it.
            if let preview = pending.preview {
                RemoteApprovalPreviewView(preview: preview)
            }

            if isResolving {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(BeetTheme.accentBright)
                    Text("Continuing…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BeetTheme.secondaryText(appearance))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityLabel("Continuing")
            } else if pending.kind == "question" {
                if let options = pending.options, !options.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(options, id: \.self) { option in
                            Button(option) { onResolve(option) }
                                .buttonStyle(RemotePrimaryButtonStyle())
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                TextField("Your answer", text: $answer, prompt: Text("Your answer").foregroundStyle(RemoteInstrument.secondaryInk))
                    .padding(11)
                    .remoteRecess()
                Button("Send answer") { onResolve(answer) }
                    .buttonStyle(RemotePrimaryButtonStyle())
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout { actionButtons }
            }
        }
        .padding(14)
        .remoteFaceplate()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(nil, value: isResolving)
    }

    @ViewBuilder private var actionButtons: some View {
        Button(pending.kind == "plan" ? "Approve plan" : "Allow once") {
            onResolve("approve")
        }
        .buttonStyle(RemotePrimaryButtonStyle())
        .tint(BeetTheme.accent)
        .frame(maxWidth: .infinity)
        if pending.kind == "approval" {
            Button("Decline", role: .destructive) { onResolve("decline") }
                .buttonStyle(RemoteSecondaryButtonStyle())
                .frame(maxWidth: .infinity)
        }
    }

    private var title: String { switch pending.kind { case "question": "Question"; case "plan": "Plan ready"; default: "Approval needed" } }
    private var symbol: String { switch pending.kind { case "question": "questionmark.bubble"; case "plan": "list.bullet.clipboard"; default: "hand.raised.fill" } }
}

#if DEBUG
#if os(iOS)
import SwiftUI

/// Deterministic composer fixture: exercises the exact production hosting
/// path (backdrop, transcript, `safeAreaInset(edge: .bottom)`) so docking and
/// keyboard avoidance can be verified without a live Mac session.
struct RemoteComposerFixture: View {
    @State private var draft = ""
    @State private var state = "Ready"
    @State private var lastAction = "None"
    @State private var model = "Claude Sonnet · Personal workspace"
    @State private var selectedPreview = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Picker("Preview state", selection: $state) {
                            ForEach(["Ready", "Running", "Offline", "Sending"], id: \.self) { Text($0) }
                        }
                        .accessibilityIdentifier("fixture.state")
                        Spacer()
                        Text(lastAction).font(.caption).accessibilityIdentifier("fixture.lastAction")
                    }
                    RemoteUserTurn(text: "Make the workspace feel calmer and more precise.")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    RemoteTranscriptTurn(text: "Start with the essentials.\n\n**A little more room to think.**\nThe conversation stays open, with clear typography and controls that feel deliberate.\n\nThe composer grows only when your message needs it.")
                    HStack(spacing: 8) {
                        Button {} label: {
                            Text("Press and hold").padding(.horizontal, 12).frame(minHeight: 44)
                        }.buttonStyle(RemoteKeyButtonStyle())
                        Button { selectedPreview.toggle() } label: {
                            Text("Selected").padding(.horizontal, 12).frame(minHeight: 44)
                        }.buttonStyle(RemoteKeyButtonStyle(isSelected: selectedPreview))
                            .accessibilityAddTraits(selectedPreview ? .isSelected : [])
                    }
                    .frame(minHeight: 44)
                    .font(.subheadline)
                    if state == "Running" {
                        RemoteTranscriptTurn(text: "Reviewing the layout and controls…", phase: "Working")
                    }
                }
                .padding(16)
            }
            .background(RemoteInstrument.reading)
            .navigationTitle("A quieter workspace")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RemoteComposer(draft: $draft, isRunning: state == "Running",
                    isReachable: state != "Offline", isSending: state == "Sending",
                    onSend: { lastAction = "Send"; draft = "" },
                    onQueue: { lastAction = "Queue"; draft = "" },
                    onSteer: { lastAction = "Steer"; draft = "" },
                    onStop: { lastAction = "Stop"; state = "Ready" },
                    modelName: model, onSelectModel: { model = "GPT-5 Codex" },
                    onShare: { lastAction = "Share" }, modeName: "Code")
            }
        }
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            switch env["VAMP_REMOTE_FIXTURE"] {
            case "running": state = "Running"
            case "offline": state = "Offline"
            case "sending": state = "Sending"
            case "multiline": draft = "One\nTwo\nThree\nFour\nFive\nSix\nSeven\nEight"
            default: break
            }
        }
    }
}
#endif

/// Local visual fixture; no network requests or session mutations.
struct RemoteComposerDesignPreview: View {
    var body: some View { RemoteComposerFixture() }
}

#Preview("Silver composer") {
    RemoteComposerFixture().environment(\.remoteAppearance, .light).preferredColorScheme(.light)
}
#Preview("Graphite composer") {
    RemoteComposerFixture().environment(\.remoteAppearance, .dark).preferredColorScheme(.dark)
}

#endif

struct RemoteComposerToolsSheet: View {
    let onChoose: (RemoteComposerCommand) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RemotePageForm {
                toolSection("Workspace", commands: Array(RemoteComposerCommand.commands.prefix(2)))
                toolSection("Browser", commands: Array(RemoteComposerCommand.commands.dropFirst(2).prefix(3)))
                toolSection("System", commands: Array(RemoteComposerCommand.commands.suffix(1)))
                Section {
                    Text("Choosing a command inserts a prompt into your draft. Review it before sending.")
                        .font(.footnote).foregroundStyle(RemoteInstrument.secondaryInk)
                }
            }
            .navigationTitle("Tools & context")
            .navigationBarTitleDisplayMode(.inline)
            .remoteNavigationChrome()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }.vampUtilityAction() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    private func toolSection(_ title: String, commands: [RemoteComposerCommand]) -> some View {
        Section(title) {
            ForEach(commands) { command in
                Button { onChoose(command) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: command.symbol)
                            .font(.subheadline)
                            .frame(width: 32, height: 32)
                            .background(RemoteInstrument.recess, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(command.title).font(.subheadline.weight(.semibold))
                            Text(command.detail).font(.footnote).foregroundStyle(RemoteInstrument.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(RemoteInstrument.secondaryInk)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }.buttonStyle(RemotePressButtonStyle())
            }
        }
    }

}
