import SwiftUI

/// A compact overview of real host state. Every action goes through the
/// existing session, model, control, or sharing screens.
struct RemoteHomeOverview: View {
    let store: RemoteStore
    let onStart: (String) -> Void
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
        VStack(alignment: .leading, spacing: 13) {
            RemoteHomeHeading(connected: store.isConnected, running: store.sessions.filter(\.isRunning).count)
            RemoteHomeConsole(name: store.activeComputerName,
                subtitle: store.connectionSubtitle, connected: store.isConnected,
                connecting: store.isConnecting || store.isRefreshing,
                working: store.isConnected && (store.hostStatus?.isRunning == true || store.sessions.contains(where: \.isRunning)),
                queued: store.hostStatus?.queuedTasks ?? 0,
                model: store.isConnected ? store.loadedLocalModel?.name : nil,
                modelCount: store.startModels.count, onMac: onMac,
                onReconnect: { Task { await store.connectSaved() } })
            RemoteHomeShortcuts(onMac: onMac, onControl: onControl, onBots: onBots, onShare: onShare)
            if !activity.isEmpty {
                RemoteHomeActivity(sessions: Array(activity.prefix(2)), connected: store.isConnected, onOpen: onOpen)
            }
            RemoteHomeStarters(connected: store.isConnected, onStart: onStart)
        }
        .accessibilityElement(children: .contain)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: activity.map(\.id))
    }
}

private struct RemoteHomeHeading: View {
    let connected: Bool
    let running: Int
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Home").font(.title.weight(.bold)).tracking(-0.7)
                    .accessibilityAddTraits(.isHeader)
                Text(Date.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
            }
            Spacer(minLength: 12)
            if connected {
                Text(running > 0 ? "\(running) in progress" : "Mac connected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(RemoteInstrument.secondaryInk)
                    .contentTransition(.numericText())
            }
        }
    }
}

private struct RemoteHomeConsole: View {
    let name: String
    let subtitle: String
    let connected: Bool
    let connecting: Bool
    let working: Bool
    let queued: Int
    let model: String?
    let modelCount: Int
    let onMac: () -> Void
    let onReconnect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Circle().fill(connected ? RemoteInstrument.signalMint : RemoteInstrument.beacon)
                            .frame(width: 5, height: 5)
                        Text(connecting ? "CONNECTING" : connected ? working ? "MAC IS WORKING" : "YOUR MAC" : "MAC OFFLINE")
                            .font(.system(.caption2, design: .monospaced).weight(.medium)).tracking(1.2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Text(name).font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    Text(connected ? subtitle : "Reconnect to continue. Your work stays on your Mac.")
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                RemoteBeaconMark(ink: .white.opacity(0.92), size: 58, isActive: working)
                    .shadow(color: RemoteInstrument.beacon.opacity(working ? 0.45 : 0.12), radius: working ? 14 : 5)
            }
            Rectangle().fill(.white.opacity(0.13)).frame(height: 0.75)
            HStack(spacing: 10) {
                Image(systemName: "cpu").font(.subheadline)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model ?? (modelCount > 0 && connected ? "\(modelCount) models available" : "Models & providers"))
                        .font(.subheadline.weight(.medium)).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    Text(model != nil ? (queued > 0 ? "Loaded on Mac · \(queued) queued" : "Loaded on Mac · Ready") : connected ? "Choose a model or set up a provider" : "Available when your Mac reconnects")
                        .font(.caption2).foregroundStyle(.white.opacity(0.68))
                }
                Spacer(minLength: 4)
                Button(action: onMac) {
                    Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(RemoteHomeConsoleButtonStyle())
                .accessibilityLabel("Open your Mac and models")
                .accessibilityIdentifier("remote.home.models")
            }
            .foregroundStyle(.white)
            if !connected {
                Button(action: onReconnect) {
                    Label(connecting ? "Connecting…" : "Reconnect Mac", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(RemoteHomeConsoleButtonStyle()).disabled(connecting)
                .accessibilityIdentifier("remote.home.reconnect")
            }
        }
        .padding(17)
        .background {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.19, green: 0.20, blue: 0.23),
                    Color(red: 0.065, green: 0.07, blue: 0.085)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 21).fill(RadialGradient(
                        colors: [RemoteInstrument.beacon.opacity(working ? 0.10 : 0.04), .clear],
                        center: .topTrailing, startRadius: 10, endRadius: 190))
                }
                .overlay { RemoteHomeConsoleTexture(active: working).clipShape(RoundedRectangle(cornerRadius: 21)) }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 21).strokeBorder(
                LinearGradient(colors: [.white.opacity(0.23), .white.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.17), radius: 14, y: 7)
        .accessibilityElement(children: .contain)
    }
}

private struct RemoteHomeConsoleTexture: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !active || reduceMotion || scenePhase != .active)) { timeline in
            Canvas { context, size in
                let phase = active && !reduceMotion ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4 : 0
                for x in stride(from: size.width * 0.6, through: size.width, by: 13) {
                    for y in stride(from: 8.0, through: size.height, by: 13) {
                        let offset = Double(x / 30 + y / 40) - phase * Double.pi * 2
                        let intensity = pow(0.5 + 0.5 * sin(offset), 3)
                        let opacity = 0.035 + (active ? 0.08 * intensity : 0)
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white.opacity(opacity)))
                    }
                }
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct RemoteHomeConsoleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(.white)
            .background(.white.opacity(configuration.isPressed ? 0.18 : 0.09), in: RoundedRectangle(cornerRadius: 11))
            .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.12), lineWidth: 0.75) }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
    }
}

private struct RemoteHomeShortcuts: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let onMac: () -> Void
    let onControl: () -> Void
    let onBots: () -> Void
    let onShare: () -> Void
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 7)) : AnyLayout(HStackLayout(spacing: 7))
        layout {
            RemoteHomeShortcut(title: "Models", symbol: "cpu", action: onMac)
            RemoteHomeShortcut(title: "Control", symbol: "display", action: onControl)
            RemoteHomeShortcut(title: "Bots", symbol: "person.2", action: onBots)
            RemoteHomeShortcut(title: "Share", symbol: "square.and.arrow.up", action: onShare)
        }
        .padding(5)
        .background(RemoteInstrument.reading, in: RoundedRectangle(cornerRadius: 17))
        .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(RemoteInstrument.seam.opacity(0.3), lineWidth: 0.75) }
        .shadow(color: .black.opacity(0.06), radius: 6, y: 3)
    }
}

private struct RemoteHomeShortcut: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                Text(title).font(.caption.weight(.medium))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(RemoteInstrument.ink)
            .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 88 : 56)
        }
        .buttonStyle(RemoteHomeShortcutStyle())
        .accessibilityLabel(title)
    }
}

private struct RemoteHomeShortcutStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? RemoteInstrument.recess : .clear, in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
    }
}

private struct RemoteHomeTileStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RemoteInstrument.reading, in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(RemoteInstrument.seam.opacity(0.28), lineWidth: 0.75) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.10 : 0.035), radius: configuration.isPressed ? 0 : 3, y: 2)
            .opacity(enabled ? 1 : 0.5)
            .offset(y: configuration.isPressed && !reduceMotion ? 1 : 0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
    }
}

private struct RemoteHomeActivity: View {
    let sessions: [RemoteSessionSummary]
    let connected: Bool
    let onOpen: (UUID) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(connected ? "Happening now" : "Last known activity").font(.subheadline.weight(.semibold))
                Spacer()
                if connected { Text("LIVE").font(.system(.caption2, design: .monospaced)).foregroundStyle(BeetTheme.accentBright) }
            }
            ForEach(sessions) { session in
                Button { onOpen(session.id) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(session.queueState == "queued" ? "Queued" : session.phase.lowercased().contains("approval") ? "Needs your approval" : "In progress")
                                .font(.caption.weight(.medium)).foregroundStyle(BeetTheme.accentBright)
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption)
                        }
                        Text(session.title).font(.body.weight(.semibold)).foregroundStyle(RemoteInstrument.ink)
                            .multilineTextAlignment(.leading).lineLimit(2)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(RemoteHomeTileStyle())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("remote.home.activity.\(session.id)")
            }
        }
    }
}

private struct RemoteHomeStarters: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let connected: Bool
    let onStart: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Quick starts").font(.subheadline.weight(.semibold))
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
            layout {
                RemoteHomeStarter(title: "Plan & organize", detail: "Turn a to-do into a plan.", symbol: "checklist", connected: connected,
                    action: { onStart("Help me turn my to-do list into a practical plan. Ask what needs to get done first.") })
                RemoteHomeStarter(title: "Work on a project", detail: "Build, review, or improve.", symbol: "hammer", connected: connected,
                    action: { onStart("Help me work on a project. Ask what I’m building and what I’d like to improve.") })
            }
            if !connected {
                Text("Reconnect your Mac to start something new.")
                    .font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
            }
        }
    }
}

private struct RemoteHomeStarter: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    let connected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack { Image(systemName: symbol).foregroundStyle(BeetTheme.accentBright); Spacer(); Image(systemName: "plus").foregroundStyle(RemoteInstrument.secondaryInk) }
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(RemoteInstrument.ink)
                Text(detail).font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(13).frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        }
        .buttonStyle(RemoteHomeTileStyle()).disabled(!connected)
        .accessibilityLabel(title)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the new-session form. Nothing is sent until you start it.")
    }
}
