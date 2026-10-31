import SwiftUI
import UIKit

/// Secondary screens use Home's canvas, reading surfaces, and compact rhythm.
/// The transcript, composer, and instrument controls keep their own materials.
struct RemotePageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) { content }
                .padding(16)
                .frame(maxWidth: RemoteInstrument.contentWidth)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { RemoteBackdrop() }
    }
}

/// Existing Section-based forms keep their identities while sharing the page
/// surfaces. In particular, console file rows never inherit a system fill.
struct RemotePageForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        RemotePageScroll {
            ForEach(sections: content) { section in
                VStack(alignment: .leading, spacing: 9) {
                    if !section.header.isEmpty {
                        ForEach(section.header) { header in
                            header.font(.subheadline.weight(.semibold))
                                .foregroundStyle(RemoteInstrument.ink)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(section.content) { row in
                            row.padding(14).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            if row.id != section.content.last?.id { RemotePageDivider() }
                        }
                    }.remotePageCard()
                    if !section.footer.isEmpty {
                        ForEach(section.footer) { footer in
                            footer.font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                        }
                    }
                }
            }
        }
    }
}

struct RemotePageHeading: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title.weight(.bold)).tracking(-0.7)
                .foregroundStyle(RemoteInstrument.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline)
                .foregroundStyle(RemoteInstrument.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }
}

struct RemotePageSearchField: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(RemoteInstrument.secondaryInk)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).frame(minHeight: 44)
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(RemoteInstrument.secondaryInk)
                        .frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12).padding(.trailing, text.isEmpty ? 12 : 0)
        .remotePageField()
    }
}

struct RemotePageSection<Content: View>: View {
    let title: LocalizedStringKey
    var detail: String? = nil
    var padding: CGFloat = 14
    var spacing: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RemotePageSectionHeading(title: title, detail: detail)
            VStack(alignment: .leading, spacing: spacing) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(padding)
                .remotePageCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RemotePageSectionHeading: View {
    let title: LocalizedStringKey
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(RemoteInstrument.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let detail {
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(RemoteInstrument.secondaryInk)
            }
        }
    }
}

struct RemotePageValueRow<Value: View>: View {
    let title: String
    @ViewBuilder var value: Value
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(title).font(.subheadline).foregroundStyle(RemoteInstrument.secondaryInk)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            value.font(.subheadline.weight(.medium)).foregroundStyle(RemoteInstrument.ink)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct RemotePageCard: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(RemoteInstrument.reading, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(RemoteInstrument.seam.opacity(contrast == .increased ? 0.85 : 0.3),
                                  lineWidth: contrast == .increased ? 1.5 : 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.1 : 0.035), radius: 5, y: 2)
    }
}

extension View {
    func remotePageCard(radius: CGFloat = 17) -> some View {
        modifier(RemotePageCard(radius: radius))
    }

    func remotePageField() -> some View {
        background(RemoteInstrument.recess, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(RemoteInstrument.seam.opacity(0.3), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
    }

    func remotePageChrome() -> some View {
        foregroundStyle(RemoteInstrument.ink)
            .navigationBarTitleDisplayMode(.inline)
            .remoteNavigationChrome()
    }
}

struct RemotePageDivider: View {
    var body: some View {
        Rectangle().fill(RemoteInstrument.seam.opacity(0.3)).frame(height: 0.75)
            .accessibilityHidden(true)
    }
}

struct RemotePageSymbol: View {
    let symbol: String
    var active = false

    var body: some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .medium))
            .foregroundStyle(active ? BeetTheme.accentBright : RemoteInstrument.secondaryInk)
            .frame(width: 40, height: 40)
            .background(RemoteInstrument.recess, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct RemotePageBadge: View {
    let title: String
    var color: Color = RemoteInstrument.secondaryInk

    var body: some View {
        Text(title).font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct RemotePageRowLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    var subtitle: String? = nil
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            RemotePageSymbol(symbol: symbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(RemoteInstrument.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(RemoteInstrument.secondaryInk).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct RemotePageRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? RemoteInstrument.recess : .clear,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(enabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct RemotePageButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .padding(.horizontal, 14)
            .foregroundStyle(primary ? Color.white : configuration.role == .destructive ? RemoteInstrument.danger : RemoteInstrument.ink)
            .background(primary ? BeetTheme.accent : RemoteInstrument.recess,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(primary ? Color.white.opacity(0.12) : RemoteInstrument.seam.opacity(0.3), lineWidth: 0.75)
            }
            .opacity(enabled ? configuration.isPressed ? 0.8 : 1 : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Home's soft inset control, with a vertical layout for accessibility sizes.
struct RemotePageSegments<Selection: Hashable>: View {
    @Binding var selection: Selection
    let options: [(String, Selection)]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            ForEach(options, id: \.1) { option in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selection = option.1
                } label: {
                    Text(option.0).font(.subheadline.weight(.medium))
                        .foregroundStyle(selection == option.1 ? RemoteInstrument.ink : RemoteInstrument.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(selection == option.1 ? RemoteInstrument.reading : .clear,
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        // Reading and recess are close in dark mode; the edge
                        // and lift keep the selected option legible.
                        .overlay {
                            if selection == option.1 {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(RemoteInstrument.seam.opacity(0.45), lineWidth: 0.75)
                            }
                        }
                        .shadow(color: .black.opacity(selection == option.1 ? 0.18 : 0), radius: 3, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.0)
                .accessibilityAddTraits(selection == option.1 ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RemoteInstrument.recess, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: selection)
        .accessibilityElement(children: .contain)
    }
}


extension View {
    /// Errors must be presented by the visible sheet, not a covered home view.
    func remotePageErrors(store: RemoteStore) -> some View {
        alert(store.errorTitle, isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
    }
}
