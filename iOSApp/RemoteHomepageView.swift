import SwiftUI

/// The top of Home: the Mac and what it is doing right now. Conversations,
/// quick starts, and the new-chat bar are laid out by SessionListView.
struct RemoteHomeOverview: View {
    let store: RemoteStore
    let onOpen: (UUID) -> Void
    let onMac: () -> Void
    let onControl: () -> Void
    let onBots: () -> Void
    let onShare: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activity: [RemoteSessionSummary] {
        store.sessions.filter { $0.isRunning || $0.queueState == "queued" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            RemoteHomeMacPanel(name: store.activeComputerName,
                connected: store.isConnected,
                connecting: store.isConnecting || store.isRefreshing,
                running: store.sessions.filter(\.isRunning).count,
                working: store.isConnected && (store.hostStatus?.isRunning == true || store.sessions.contains(where: \.isRunning)),
                queued: store.hostStatus?.queuedTasks ?? 0,
                model: store.isConnected ? store.loadedLocalModel?.name : nil,
                modelCount: store.startModels.count,
                onMac: onMac, onControl: onControl, onBots: onBots, onShare: onShare,
                onReconnect: { Task { await store.connectSaved() } })
            if !activity.isEmpty {
                RemoteHomeActivity(sessions: Array(activity.prefix(2)), connected: store.isConnected, onOpen: onOpen)
            }
        }
        .accessibilityElement(children: .contain)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: activity.map(\.id))
    }
}

/// The Mac is the subject of the app, so it gets the one glass panel on the
/// page, with its four destinations laid out like a contact card's actions.
private struct RemoteHomeMacPanel: View {
    let name: String
    let connected: Bool
    let connecting: Bool
    let running: Int
    let working: Bool
    let queued: Int
    let model: String?
    let modelCount: Int
    let onMac: () -> Void
    let onControl: () -> Void
    let onBots: () -> Void
    let onShare: () -> Void
    let onReconnect: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var state: String {
        if connecting { return "Connecting" }
        if !connected { return "Offline" }
        if running > 0 { return running == 1 ? "Working" : "\(running) running" }
        return working ? "Working" : "Online"
    }

    private var stateColor: Color {
        if !connected { return connecting ? RemoteInstrument.orange : RemoteInstrument.secondaryInk }
        return working ? BeetTheme.accentBright : RemoteInstrument.green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(RemoteInstrument.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    detail.font(.footnote).foregroundStyle(RemoteInstrument.secondaryInk)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    RemoteLivePulse(color: stateColor, active: connected || connecting, fast: working || connecting)
                    Text(state).font(.caption.weight(.semibold)).foregroundStyle(stateColor)
                        .contentTransition(.numericText())
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
                RemoteHomeAction(title: "Models", symbol: "cpu", action: onMac)
                RemoteHomeAction(title: "Control", symbol: "display", action: onControl)
                RemoteHomeAction(title: "Bots", symbol: "person.2", action: onBots)
                RemoteHomeAction(title: "Share", symbol: "square.and.arrow.up", action: onShare)
            }

            if !connected {
                Button(action: onReconnect) {
                    Label(connecting ? "Connecting…" : "Reconnect Mac", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RemotePrimaryButtonStyle())
                .disabled(connecting)
                .accessibilityIdentifier("remote.home.reconnect")
            }
        }
        .padding(14)
        .foregroundStyle(RemoteInstrument.ink)
        .vampGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// The model name stays its own text so it reads (and is found) on its own.
    @ViewBuilder private var detail: some View {
        if !connected {
            Text("Reconnect to continue. Your work stays on your Mac.")
        } else if let model {
            HStack(spacing: 4) {
                Text(model)
                Text(queued > 0 ? "· \(queued) queued" : "· Ready")
            }
        } else {
            Text(modelCount > 0 ? "\(modelCount) models available" : "Choose a model or set up a provider")
        }
    }
}

private struct RemoteHomeAction: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(BeetTheme.accentBright)
                    .frame(height: 22)
                Text(title).font(.caption.weight(.medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(RemoteInstrument.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(RemoteHomePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

/// A status dot that radiates a slow ring while the thing it describes is
/// alive. Stops under Reduce Motion and in the background.
struct RemoteLivePulse: View {
    let color: Color
    var active = true
    var fast = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let animates = active && !reduceMotion && scenePhase == .active
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animates)) { context in
            let period = fast ? 1.4 : 2.6
            let phase = animates ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period : 1
            Circle().fill(color).frame(width: 7, height: 7)
                .background {
                    Circle().stroke(color, lineWidth: 1.2)
                        .scaleEffect(1 + phase * 1.6)
                        .opacity(animates ? (1 - phase) * 0.7 : 0)
                }
        }
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

struct RemoteHomePressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(enabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct RemoteHomeActivity: View {
    let sessions: [RemoteSessionSummary]
    let connected: Bool
    let onOpen: (UUID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RemotePageSectionHeading(title: connected ? "Happening now" : "Last known activity").padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    Button { onOpen(session.id) } label: {
                        HStack(spacing: 12) {
                            Group {
                                if session.queueState == "queued" {
                                    Image(systemName: "clock").font(.footnote.weight(.semibold))
                                        .foregroundStyle(RemoteInstrument.secondaryInk)
                                } else {
                                    RemoteChatWorkingDots(active: connected)
                                }
                            }
                            .frame(width: 32, height: 32)
                            .background(BeetTheme.accentBright.opacity(session.queueState == "queued" ? 0 : 0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title).font(.body.weight(.medium))
                                    .multilineTextAlignment(.leading).lineLimit(1)
                                Text(status(session)).font(.footnote)
                                    .foregroundStyle(session.queueState == "queued" ? RemoteInstrument.secondaryInk : BeetTheme.accentBright)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                .foregroundStyle(RemoteInstrument.secondaryInk)
                        }
                        .foregroundStyle(RemoteInstrument.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RemotePageRowButtonStyle())
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("remote.home.activity.\(session.id)")
                    if session.id != sessions.last?.id { RemotePageDivider().padding(.leading, 58) }
                }
            }
            .remotePageCard()
        }
    }

    private func status(_ session: RemoteSessionSummary) -> String {
        if session.queueState == "queued" { return "Queued" }
        if session.phase.lowercased().contains("approval") { return "Needs your approval" }
        return session.phase.isEmpty || session.phase == "idle" ? "In progress" : session.phase.capitalized + "…"
    }
}

/// Quick starts fill the new-chat form; nothing is sent until it is started.
struct RemoteHomeStarters: View {
    let connected: Bool
    let onStart: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            RemotePageSectionHeading(title: "Start something").padding(.horizontal, 4)
            VStack(spacing: 0) {
                starter("Plan & organize", detail: "Turn a to-do into a plan.", symbol: "checklist",
                    prompt: "Help me turn my to-do list into a practical plan. Ask what needs to get done first.")
                RemotePageDivider().padding(.leading, 58)
                starter("Work on a project", detail: "Build, review, or improve.", symbol: "hammer",
                    prompt: "Help me work on a project. Ask what I’m building and what I’d like to improve.")
            }
            .remotePageCard()
            if !connected {
                Text("Reconnect your Mac to start something new.")
                    .font(.caption).foregroundStyle(RemoteInstrument.secondaryInk).padding(.horizontal, 4)
            }
        }
    }

    private func starter(_ title: LocalizedStringKey, detail: LocalizedStringKey, symbol: String, prompt: String) -> some View {
        Button { onStart(prompt) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BeetTheme.accentBright)
                    .frame(width: 32, height: 32)
                    .background(BeetTheme.accentBright.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(RemoteInstrument.ink)
                    Text(detail).font(.footnote).foregroundStyle(RemoteInstrument.secondaryInk)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.forward").font(.caption.weight(.semibold))
                    .foregroundStyle(RemoteInstrument.secondaryInk)
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RemotePageRowButtonStyle())
        .disabled(!connected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint("Opens the new-session form. Nothing is sent until you start it.")
    }
}

/// Home ends in the same floating glass field a chat does, so starting one
/// feels like typing, not filling a form.
struct RemoteHomeComposeBar: View {
    let connected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(connected ? "Message Vamp" : "Reconnect to start a chat")
                    .font(.body).foregroundStyle(RemoteInstrument.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "square.and.pencil").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(connected ? BeetTheme.accent : RemoteInstrument.secondaryInk.opacity(0.5), in: Circle())
            }
            .padding(.leading, 18).padding(.trailing, 7)
            .frame(maxWidth: .infinity, minHeight: 50)
            .vampGlass(Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(RemoteHomePressStyle())
        .disabled(!connected)
        .padding(.horizontal, 16).padding(.bottom, 6)
        .frame(maxWidth: RemoteInstrument.contentWidth)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Start a new session")
    }
}
