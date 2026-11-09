import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MessageTranscript: View {
    let detail: RemoteSessionDetail
    var dismissedErrorMessage: String? = nil
    var onDismissError: (() -> Void)? = nil
    /// Nil while the agent is running — the Mac refuses an undo mid-run, so the
    /// button should not be offered rather than offered and rejected.
    var onRevertCheckpoint: (() -> Void)? = nil
    var onReuseUserMessage: ((String) -> Void)? = nil
    var isReachable = true
    @Environment(\.remoteAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the transcript should keep the newest response in view. This is
    /// deliberately separate from the scroll geometry: content height grows
    /// while a response streams, and treating that growth as user scrolling
    /// makes the “Latest” affordance appear even when the user never touched
    /// the transcript.
    @State private var followsLatest = true
    @State private var userIsInteracting = false
    @State private var scrollRequestGeneration = 0
    @State private var scrollWorkScheduled = false
    @State private var scrollNeedsFollowUp = false
    @State private var scrollAnimationRequested = false
    @State private var seenMessageIDs: Set<String> = []
    @State private var firstPresentation = true

    private struct ScrollMetrics: Equatable {
        let offsetY: CGFloat
        let bottomDistance: CGFloat
    }

    private static let followThreshold: CGFloat = 64

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(detail.messages) { message in
                        MessageBubble(
                            message: message,
                            onRevert: message.checkpointID == nil ? nil : onRevertCheckpoint,
                            onReuse: onReuseUserMessage)
                            .modifier(RemoteChatEntry(animate: !firstPresentation && !seenMessageIDs.contains(message.id)) {
                                seenMessageIDs.insert(message.id)
                            })
                    }
                    if detail.isRunning { StreamingBubble(text: detail.streamingText, phase: detail.phase, active: isReachable) }
                    if let error = detail.error, error.message != dismissedErrorMessage {
                        RemoteChatErrorCard(error: error, onDismiss: onDismissError)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: RemoteInstrument.contentWidth)
                .padding(.horizontal, 16).padding(.vertical, 16).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.top, for: .alignment)
            // Geometry is sampled independently from the scroll phase. The
            // phase tells us whether a change could have come from a finger;
            // without that distinction, every streamed token looks like the
            // user scrolled away from the bottom.
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(
                    offsetY: geometry.contentOffset.y,
                    bottomDistance: max(0, geometry.contentSize.height - geometry.visibleRect.maxY))
            } action: { previous, atBottom in
                guard userIsInteracting else { return }
                if atBottom.bottomDistance <= Self.followThreshold {
                    if !followsLatest { followsLatest = true }
                } else if atBottom.offsetY < previous.offsetY - 1 {
                    // Only a real upward drag disables follow. Content height
                    // changes during streaming leave the offset untouched.
                    if followsLatest { followsLatest = false }
                }
            }
            .onScrollPhaseChange { _, phase, context in
                let geometry = context.geometry
                let bottomDistance = max(0, geometry.contentSize.height - geometry.visibleRect.maxY)
                switch phase {
                case .tracking, .interacting:
                    userIsInteracting = true
                    if bottomDistance <= Self.followThreshold, !followsLatest {
                        followsLatest = true
                    }
                case .idle:
                    userIsInteracting = false
                    if bottomDistance <= Self.followThreshold, !followsLatest {
                        followsLatest = true
                    }
                case .decelerating, .animating:
                    break
                @unknown default:
                    break
                }
            }
            .onAppear {
                seenMessageIDs.formUnion(detail.messages.map(\.id))
                firstPresentation = false
                requestScroll(proxy)
            }
            // Unanimated: a spring restarted per token was also the jitter.
            .onChange(of: detail.streamingText) { _, _ in
                guard followsLatest else { return }
                requestScroll(proxy)
            }
            .onChange(of: detail.messages.count) { _, _ in
                guard followsLatest else { return }
                requestScroll(proxy)
            }
            .onChange(of: detail.isRunning) { _, _ in
                guard followsLatest else { return }
                requestScroll(proxy)
            }
            .onChange(of: detail.id) { _, _ in
                // A reused navigation cell can keep @State from the previous
                // session. A newly opened conversation should always begin at
                // its newest message.
                scrollRequestGeneration &+= 1
                scrollWorkScheduled = false
                scrollNeedsFollowUp = false
                scrollAnimationRequested = false
                followsLatest = true
                userIsInteracting = false
                seenMessageIDs = Set(detail.messages.map(\.id))
                requestScroll(proxy)
            }
            .overlay(alignment: .bottom) {
                ZStack {
                    if !followsLatest { jumpToLatest(proxy) }
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: followsLatest)
            }
            .onDisappear {
                scrollRequestGeneration &+= 1
                scrollWorkScheduled = false
                scrollNeedsFollowUp = false
                scrollAnimationRequested = false
            }
        }
    }

    /// Coalesce token-driven scroll requests and wait for the lazy stack to
    /// finish laying out the new text. Calling `scrollTo` in the same update
    /// that changes a token can target the previous content height, which is
    /// the source of the old “press Latest” behavior.
    private func requestScroll(
        _ proxy: ScrollViewProxy,
        animated: Bool = false,
        delay: TimeInterval = 0.04
    ) {
        // Do not compete with a finger or trackpad drag. If the user keeps
        // following the latest message, the next streamed delta will request
        // the anchor again after the interaction has ended.
        guard followsLatest, !userIsInteracting else { return }
        // A trailing debounce alone never fires when model deltas arrive
        // faster than the debounce interval: every token cancels the previous
        // request. Keep one small main-actor worker alive instead. It drains
        // follow-up requests at a steady cadence and performs a second pass
        // after layout, so the bottom anchor tracks both fast local models and
        // slower network streams without animation jitter.
        scrollNeedsFollowUp = true
        scrollAnimationRequested = scrollAnimationRequested || animated
        guard !scrollWorkScheduled else { return }
        scrollWorkScheduled = true
        let generation = scrollRequestGeneration
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            while generation == scrollRequestGeneration, followsLatest, !userIsInteracting {
                scrollNeedsFollowUp = false
                let shouldAnimate = scrollAnimationRequested
                scrollAnimationRequested = false
                if shouldAnimate {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                } else {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                // Lazy stacks may publish their final height one run-loop
                // turn after the first scroll. Re-anchoring once prevents the
                // user from having to press Latest after a long response.
                try? await Task.sleep(for: .milliseconds(55))
                guard generation == scrollRequestGeneration,
                      followsLatest,
                      !userIsInteracting else { break }
                proxy.scrollTo("bottom", anchor: .bottom)
                if !scrollNeedsFollowUp { break }
                try? await Task.sleep(for: .milliseconds(35))
            }
            if generation == scrollRequestGeneration {
                scrollWorkScheduled = false
                scrollAnimationRequested = false
            }
        }
    }

    private func jumpToLatest(_ proxy: ScrollViewProxy) -> some View {
        Button {
            followsLatest = true
            userIsInteracting = false
            requestScroll(proxy, animated: !reduceMotion, delay: 0)
        } label: {
            Label(detail.isRunning ? "Jump to latest" : "Latest", systemImage: "arrow.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RemoteInstrument.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .vampGlass(Capsule(), interactive: true)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 12)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
        .accessibilityLabel("Jump to latest message")
    }
}

struct MessageBubble: View {
    let message: RemoteMessage
    /// Only supplied where a revert is actually possible (an open session that
    /// is not running); nil elsewhere, and the checkpoint row hides the button.
    var onRevert: (() -> Void)? = nil
    var onReuse: ((String) -> Void)? = nil
    @Environment(\.remoteAppearance) private var appearance
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var isUser: Bool { message.role == "user" }
    var body: some View {
      Group {
        if isUser {
            RemoteUserTurn(text: message.content)
        }
        else if message.role == "toolCall" || message.role == "toolResult" { ToolMessageCard(message: message) }
        // Reasoning is the model's working, not its answer. It used to fall
        // through to the assistant bubble below, which presented thinking as
        // conclusions.
        else if message.role == "reasoning" { ReasoningMessageCard(message: message) }
        else if message.role == "checkpoint" { CheckpointMessageRow(message: message, onRevert: onRevert) }
        // Errors used to render as EmptyView(), so scrolling back through a
        // session showed no trace of anything that had gone wrong.
        else if message.role == "error" {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(message.content)
                    .font(.caption)
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
                    .textSelection(.enabled)
                Spacer(minLength: 4)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.red.opacity(0.3), lineWidth: 0.75) }
        }
        else if message.role == "notice" {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: noticeSymbol).font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
                Text(message.content).font(.caption)
            }
            .foregroundStyle(RemoteInstrument.secondaryInk)
            .padding(.horizontal, 2)
        }
        else {
            RemoteTranscriptTurn(text: message.content)
        }
      }
      .contextMenu {
          if ["user", "assistant"].contains(message.role), !message.content.isEmpty {
              let text = isUser ? RemoteUserTurn.split(message.content).message : message.content
              Button("Copy message", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
              if isUser, let onReuse {
                  Button("Use in composer", systemImage: "pencil") { onReuse(text) }
              }
          }
      }
      .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
      .padding(.leading, isUser && !dynamicTypeSize.isAccessibilitySize ? 48 : 0)
    }

    private var noticeSymbol: String {
        let text = message.content.lowercased()
        if text.contains("image") { return "photo" }
        if text.contains("checkpoint") || text.hasPrefix("undo") { return "clock.arrow.circlepath" }
        if text.hasPrefix("approved") || text.hasSuffix("allowed") { return "checkmark.circle" }
        if text.hasPrefix("declined") || text.hasSuffix("rejected") { return "xmark.circle" }
        return "info.circle"
    }
}

/// An answer with a quiet footer: the logo plus Copy once finished, the logo
/// plus the live phase while streaming. Same footer height in both states, so
/// nothing moves when a stream becomes a message.
struct RemoteTranscriptTurn: View {
    let text: String
    var phase: String? = nil
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !text.isEmpty { MarkdownText(text) }
            HStack(spacing: 6) {
                RemoteBeaconMark(ink: phase == nil ? RemoteInstrument.secondaryInk : BeetTheme.accentBright,
                                 size: 14, isActive: phase != nil && active)
                if let phase {
                    Text(phase.capitalized).font(.footnote.weight(.medium))
                        .foregroundStyle(RemoteInstrument.secondaryInk)
                        .contentTransition(.opacity)
                    RemoteChatWorkingDots(active: active)
                } else if !text.isEmpty {
                    copyButton
                }
            }
            .frame(minHeight: 34, alignment: .leading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: phase)
        }
        .foregroundStyle(RemoteInstrument.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vamp")
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
        } label: {
            Image(systemName: copied ? "checkmark" : "square.on.square")
                .font(.footnote.weight(.medium))
                .foregroundStyle(copied ? BeetTheme.accentBright : RemoteInstrument.secondaryInk)
                .frame(width: 30, height: 30)
                .hitTarget(7)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Message copied" : "Copy message")
        .accessibilityIdentifier("remote.chat.copy-message")
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            copied = false
        }
    }
}

/// The model's visible working, collapsed by default. It is deliberately
/// quieter than an answer bubble: smaller type, no avatar, muted colour.
struct ReasoningMessageCard: View {
    let message: RemoteMessage
    @Environment(\.remoteAppearance) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : RemoteInstrument.motion) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain").font(.caption)
                    Text("Reasoning").font(.footnote.weight(.medium))
                    Spacer(minLength: 8)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                }
                .foregroundStyle(RemoteInstrument.secondaryInk)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(RemotePressButtonStyle())
            .accessibilityLabel(expanded ? "Hide reasoning" : "Show reasoning")
            if expanded {
                VampHairline()
                Text(LocalizedStringKey(message.content))
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(RemoteInstrument.secondaryInk)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .background(expanded ? RemoteInstrument.recess.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A git checkpoint the agent took before mutating the tree. Carries the revert
/// affordance, which the phone could not offer while checkpoints arrived as
/// stringified notices.
struct CheckpointMessageRow: View {
    let message: RemoteMessage
    var onRevert: (() -> Void)? = nil
    @Environment(\.remoteAppearance) private var appearance
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BeetTheme.accentBright)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Checkpoint")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
                Text(message.content)
                    .font(.caption)
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if onRevert != nil {
                Button("Revert") { confirming = true }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(RemoteSecondaryButtonStyle())
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RemoteInstrument.recess.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .confirmationDialog("Restore this checkpoint?",
                            isPresented: $confirming,
                            titleVisibility: .visible) {
            Button("Restore", role: .destructive) { onRevert?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Mac's working tree is rolled back to this point. Changes made after it are lost.")
        }
    }
}

struct RemoteChatErrorCard: View {
    let error: RemoteErrorPresentation
    var onDismiss: (() -> Void)? = nil
    @Environment(\.remoteAppearance) private var appearance

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Label(error.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(BeetTheme.accentBright)
                Spacer(minLength: 8)
                if let onDismiss {
                    Button("Dismiss", action: onDismiss)
                        .font(.caption.weight(.semibold))
                }
            }
            Text(error.message)
                .font(.subheadline)
                .lineSpacing(3)
                .textSelection(.enabled)
            Text("You can change the model or start a new chat. This failed chat will not be reopened automatically.")
                .font(.caption)
                .foregroundStyle(BeetTheme.secondaryText(appearance))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RemoteInstrument.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct MarkdownText: View {
    let content: String
    init(_ content: String) { self.content = content }

    struct ListItem: Equatable { var marker: String; var level: Int; var text: String }
    enum Block: Equatable {
        case paragraph(String), heading(Int, String), code(String, String?), list([ListItem]), quote(String), rule
    }

    /// Block structure only; inline syntax is left to AttributedString. An
    /// unclosed fence (a stream mid-code) still renders as code.
    static func blocks(_ content: String) -> [Block] {
        var result: [Block] = []
        var paragraph: [String] = [], items: [ListItem] = [], quote: [String] = []
        var code: [String]?
        var language: String?
        func flush() {
            if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: "\n"))) }
            if !items.isEmpty { result.append(.list(items)) }
            if !quote.isEmpty { result.append(.quote(quote.joined(separator: "\n"))) }
            paragraph = []; items = []; quote = []
        }
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if trimmed.hasPrefix("```") {
                if let body = code {
                    result.append(.code(body.joined(separator: "\n"), language)); code = nil
                } else {
                    flush(); code = []
                    language = String(trimmed.dropFirst(3).split(whereSeparator: \.isWhitespace).first?.prefix(32) ?? "")
                }
            } else if code != nil {
                code?.append(line)
            } else if trimmed.isEmpty {
                flush()
            } else if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flush(); result.append(.heading(hashes, String(trimmed.dropFirst(hashes + 1))))
            } else if trimmed.count >= 3, let first = trimmed.first, "-*_".contains(first),
                      trimmed.allSatisfy({ $0 == first || $0 == " " }) {
                flush(); result.append(.rule)
            } else if let item = listItem(line) {
                if items.isEmpty { flush() }
                items.append(item)
            } else if trimmed.hasPrefix(">") {
                if quote.isEmpty { flush() }
                quote.append(String(trimmed.dropFirst().drop(while: { $0 == " " })))
            } else if !items.isEmpty, line.first == " " || line.first == "\t" {
                items[items.count - 1].text += "\n" + trimmed
            } else {
                if paragraph.isEmpty { flush() }
                paragraph.append(line)
            }
        }
        flush()
        if let body = code { result.append(.code(body.joined(separator: "\n"), language)) }
        return result
    }

    private static func listItem(_ line: String) -> ListItem? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let rest = line.dropFirst(indent)
        let level = min(indent / 2, 3)
        if let first = rest.first, "-*+•".contains(first), rest.dropFirst().first == " " {
            return ListItem(marker: "•", level: level, text: String(rest.dropFirst(2)))
        }
        let digits = rest.prefix(while: \.isNumber)
        guard (1...3).contains(digits.count),
              let dot = rest.dropFirst(digits.count).first, dot == "." || dot == ")",
              rest.dropFirst(digits.count + 1).first == " " else { return nil }
        return ListItem(marker: digits + ".", level: level, text: String(rest.dropFirst(digits.count + 2)))
    }

    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.blocks(content).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    prose(text)
                case .heading(let level, let text):
                    Text(Self.inline(text))
                        .font(level == 1 ? .title3.weight(.semibold) : level == 2 ? .headline : .subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                        .accessibilityAddTraits(.isHeader)
                case .code(let text, let language):
                    RemoteChatCodeBlock(text: text, language: language)
                case .list(let items):
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.marker)
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(RemoteInstrument.secondaryInk)
                                    .accessibilityHidden(item.marker == "•")
                                prose(item.text)
                            }
                            .padding(.leading, CGFloat(item.level) * 18)
                        }
                    }
                case .quote(let text):
                    prose(text)
                        .foregroundStyle(RemoteInstrument.secondaryInk)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Capsule().fill(RemoteInstrument.seam).frame(width: 3)
                        }
                case .rule:
                    Rectangle().fill(RemoteInstrument.seam).frame(height: 0.5).padding(.vertical, 4)
                }
            }
        }
    }

    private func prose(_ text: String) -> some View {
        Text(Self.inline(text))
            .font(.body)
            .lineSpacing(4)
            .tint(BeetTheme.accentBright)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ToolMessageCard: View {
    let message: RemoteMessage
    @Environment(\.remoteAppearance) private var appearance
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if !displayContent.isEmpty {
                Text(displayContent).font(.callout.monospaced()).lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RemoteInstrument.recess.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.bottom, 12)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.subheadline)
                    .foregroundStyle(message.didFail ? RemoteInstrument.danger : RemoteInstrument.secondaryInk)
                    .frame(width: 22).accessibilityHidden(true)
                Text(displayName).font(.subheadline.weight(.medium)).foregroundStyle(RemoteInstrument.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(message.role == "toolCall" ? "Request" : message.didFail ? "Failed" : "Done")
                    .font(.caption).foregroundStyle(message.didFail ? RemoteInstrument.danger : RemoteInstrument.secondaryInk)
            }
            .frame(minHeight: 44)
        }
        .tint(RemoteInstrument.secondaryInk)
        .padding(.horizontal, 12)
        .background(RemoteInstrument.recess.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: expanded)
    }

    /// A failed tool used to render with the same checkmark as a successful
    /// one — the Mac tracked the failure but it never crossed the wire.
    private var symbol: String {
        if message.role == "toolCall" { return "hammer" }
        return message.didFail ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    private var displayName: String {
        let raw = message.toolName ?? "Tool activity"
        return raw.replacingOccurrences(of: "dynamic:", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    private var displayContent: String {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "{}" { return "" }
        guard let data = trimmed.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !array.isEmpty else { return message.content }
        let text = array.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return text.isEmpty ? message.content : text
    }
}

struct StreamingBubble: View {
    let text: String, phase: String
    var active = true
    var body: some View {
        RemoteTranscriptTurn(text: text, phase: phase, active: active)
    }
}

struct QueuedFollowUpsView: View {
    let items: [RemoteQueuedItem]
    var canSend = false
    var canRemove = true
    var isUpdating = false
    var sendingTaskID: UUID?
    let onSend: (UUID) -> Void
    let onCancel: (UUID) -> Void
    @Environment(\.remoteAppearance) private var appearance

    var body: some View {
        VStack(spacing: 6) {
            ForEach(items) { item in
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(BeetTheme.accentBright)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label ?? "Queued")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BeetTheme.accentBright)
                        Text(item.message)
                            .font(.caption)
                            .foregroundStyle(BeetTheme.secondaryText(appearance))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Button {
                        onSend(item.id)
                    } label: {
                        Group {
                            if sendingTaskID == item.id { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.up").font(.subheadline.weight(.semibold)) }
                        }
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(RemoteKeyButtonStyle())
                    .disabled(!canSend || isUpdating)
                    .accessibilityLabel("Send queued follow-up now")
                    .accessibilityHint("Sends this saved message when the Mac is idle.")
                    .accessibilityIdentifier("remote.queue.send.\(item.id)")
                    Button {
                        onCancel(item.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .frame(width: 28, height: 28)
                            .hitTarget(8)
                    }
                    .foregroundStyle(BeetTheme.secondaryText(appearance))
                    .buttonStyle(RemotePressButtonStyle())
                    .disabled(!canRemove || isUpdating)
                    .accessibilityLabel("Remove queued follow-up")
                }
                .padding(.leading, 14).padding(.trailing, 6)
                .padding(.vertical, 4)
                .vampGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: RemoteInstrument.contentWidth)
        .frame(maxWidth: .infinity)
    }
}
