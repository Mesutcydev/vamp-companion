import SwiftUI
import UIKit

/// Conversation-specific surfaces. The composer and shared palette stay intact.
struct RemoteUserTurn: View {
    let text: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack {
            Spacer(minLength: typeSize.isAccessibilitySize ? 0 : 32)
            VStack(alignment: .trailing, spacing: 6) {
                Text("You").font(.caption.weight(.medium)).foregroundStyle(RemoteInstrument.secondaryInk)
                MarkdownText(text)
                    .padding(.horizontal, 15).padding(.vertical, 12)
                    .background(RemoteInstrument.reading, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(RemoteInstrument.seam.opacity(0.45), lineWidth: 0.75) }
                    .shadow(color: .black.opacity(0.045), radius: 5, y: 2)
            }
        }
        .foregroundStyle(RemoteInstrument.ink)
        .accessibilityElement(children: .contain)
    }
}

struct RemoteChatWorkingDots: View {
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06, paused: !active || reduceMotion || scenePhase != .active)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    let wave = !active || reduceMotion ? 0.5 : 0.5 + 0.5 * sin(time * 4 - Double(index) * 0.8)
                    Circle().fill(BeetTheme.accentBright.opacity(0.35 + wave * 0.6))
                        .frame(width: 4, height: 4)
                        .offset(y: !active || reduceMotion ? 0 : -wave * 2)
                }
            }.frame(width: 20, height: 12)
        }
        .accessibilityHidden(true)
    }
}

struct RemoteConversationTitle: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.headline).lineLimit(1).truncationMode(.tail)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption2).foregroundStyle(RemoteInstrument.secondaryInk).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Entry transforms do not change layout. History appears immediately; new
/// turns enter once. Token growth never restarts a spring or a reveal timer.
struct RemoteChatEntry: ViewModifier {
    let onSeen: () -> Void
    @State private var shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(animate: Bool, onSeen: @escaping () -> Void) {
        self.onSeen = onSeen
        _shown = State(initialValue: !animate)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                if !shown {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.92)) { shown = true }
                }
                onSeen()
            }
    }
}

struct RemoteChatCodeBlock: View {
    let text: String
    let language: String?
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(language.flatMap { $0.isEmpty ? nil : $0 } ?? "Code")
                    .font(.caption.monospaced().weight(.medium)).foregroundStyle(RemoteInstrument.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.medium)).frame(minWidth: 64, minHeight: 44)
                        .contentShape(Rectangle())
                        .contentTransition(.opacity)
                }
                .buttonStyle(.plain).foregroundStyle(copied ? BeetTheme.accentBright : RemoteInstrument.ink)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(copied ? "Code copied" : "Copy code")
                .accessibilityIdentifier("remote.chat.copy-code")
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: copied)
            }.padding(.horizontal, 12)
            Rectangle().fill(RemoteInstrument.seam.opacity(0.3)).frame(height: 0.75)
            ScrollView(.horizontal) {
                Text(text).font(.callout.monospaced()).lineSpacing(3)
                    .textSelection(.enabled).padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(RemoteInstrument.recess, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(RemoteInstrument.seam.opacity(0.4), lineWidth: 0.75) }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
    }
}
