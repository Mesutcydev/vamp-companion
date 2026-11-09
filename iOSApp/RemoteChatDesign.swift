import SwiftUI
import UIKit

/// Conversation-specific surfaces. The composer and shared palette stay intact.
/// The user's turn hugs its text on the trailing side. The Mac appends
/// attachment summaries ("  ·  1 image") to the shown text; they become chips.
struct RemoteUserTurn: View {
    let text: String

    static func split(_ text: String) -> (message: String, attachments: [String]) {
        let parts = text.components(separatedBy: "  ·  ")
        return (parts[0], Array(parts.dropFirst()))
    }

    private let bubble = UnevenRoundedRectangle(
        topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous)

    var body: some View {
        let parts = Self.split(text)
        VStack(alignment: .trailing, spacing: 6) {
            if !parts.message.isEmpty {
                MarkdownText(parts.message)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(RemoteInstrument.recess, in: bubble)
                    .contentShape(.contextMenuPreview, bubble)
            }
            if !parts.attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(parts.attachments, id: \.self) { item in
                        Label(item, systemImage: item.hasSuffix("image") || item.hasSuffix("images") ? "photo" : "paperclip")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(RemoteInstrument.secondaryInk)
                            .lineLimit(1)
                            .padding(.horizontal, 10).frame(minHeight: 26)
                            .background(RemoteInstrument.recess.opacity(0.7), in: Capsule())
                    }
                }
            }
        }
        .foregroundStyle(RemoteInstrument.ink)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("You")
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

struct RemoteConversationTitle<Subtitle: View>: View {
    let title: String
    @ViewBuilder var subtitle: Subtitle
    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.tail)
            subtitle.font(.caption2).foregroundStyle(RemoteInstrument.secondaryInk).lineLimit(1)
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
                    .font(.caption.weight(.medium)).foregroundStyle(RemoteInstrument.secondaryInk)
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
            Rectangle().fill(RemoteInstrument.seam.opacity(0.6)).frame(height: 0.5)
            ScrollView(.horizontal) {
                Text(text).font(.callout.monospaced()).lineSpacing(3)
                    .textSelection(.enabled).padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(RemoteInstrument.reading, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(RemoteInstrument.seam.opacity(0.6), lineWidth: 0.5) }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
    }
}
