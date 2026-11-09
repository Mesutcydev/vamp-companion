import SwiftUI
import UIKit

/// Secondary screens use Home's canvas, reading surfaces, and compact rhythm.
/// The transcript, composer, and instrument controls keep their own materials.
struct RemotePageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(.horizontal, 16).padding(.vertical, 12)
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
                            header.font(.footnote.weight(.semibold))
                                .foregroundStyle(RemoteInstrument.secondaryInk)
                                .padding(.horizontal, 4)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(section.content) { row in
                            row.padding(.horizontal, 16).padding(.vertical, 11)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            if row.id != section.content.last?.id { RemotePageDivider().padding(.leading, 16) }
                        }
                    }.remotePageCard()
                    if !section.footer.isEmpty {
                        ForEach(section.footer) { footer in
                            footer.font(.caption).foregroundStyle(RemoteInstrument.secondaryInk)
                                .padding(.horizontal, 4)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title2.weight(.bold))
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
        VStack(alignment: .leading, spacing: 7) {
            RemotePageSectionHeading(title: title, detail: detail).padding(.horizontal, 4)
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
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(RemoteInstrument.secondaryInk)
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

/// Content sits on solid, softly lifted surfaces; glass is kept for controls.
private struct RemotePageCard: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = scheme == .dark
        content
            .background(RemoteInstrument.reading, in: shape)
            .overlay {
                // A lit top edge reads as depth without drawing a border.
                shape.strokeBorder(contrast == .increased
                    ? LinearGradient(colors: [RemoteInstrument.seam], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [.white.opacity(dark ? 0.1 : 0.9), .white.opacity(dark ? 0.02 : 0)],
                                     startPoint: .top, endPoint: .bottom),
                    lineWidth: contrast == .increased ? 1.5 : 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(dark ? 0.4 : 0.06), radius: 16, y: 6)
    }
}

extension View {
    func remotePageCard(radius: CGFloat = 22) -> some View {
        modifier(RemotePageCard(radius: radius))
    }

    func remotePageField() -> some View {
        background(RemoteInstrument.recess, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func remotePageChrome() -> some View {
        foregroundStyle(RemoteInstrument.ink)
            .navigationBarTitleDisplayMode(.inline)
            .remoteNavigationChrome()
    }
}

struct RemotePageDivider: View {
    var body: some View {
        Rectangle().fill(RemoteInstrument.seam.opacity(0.7)).frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

struct RemotePageSymbol: View {
    let symbol: String
    var active = false
    /// A filled tile in this colour, as iOS Settings draws its rows.
    var tint: Color? = nil

    var body: some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            .foregroundStyle(active || tint != nil ? Color.white : RemoteInstrument.ink)
            .frame(width: 32, height: 32)
            .background(tint ?? (active ? BeetTheme.accent : RemoteInstrument.recess),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct RemotePageBadge: View {
    let title: String
    var color: Color = RemoteInstrument.secondaryInk

    var body: some View {
        Text(title).font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct RemotePageRowLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    var subtitle: String? = nil
    var showsChevron = true
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 12) {
            RemotePageSymbol(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body).foregroundStyle(RemoteInstrument.ink)
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
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            // Exactly 44 can measure 43.99997 at a fractional y; the half point keeps
            // every button at or above the 44-pt touch target wherever it lands.
            .frame(minHeight: 44.5)
            .padding(.horizontal, 16)
            .foregroundStyle(primary ? Color.white : configuration.role == .destructive ? RemoteInstrument.danger : RemoteInstrument.ink)
            .modifier(RemoteKeySurface(isPressed: configuration.isPressed, prominent: primary))
    }
}

/// Home's soft inset control, with a vertical layout for accessibility sizes.
struct RemotePageSegments<Selection: Hashable>: View {
    @Binding var selection: Selection
    let options: [(String, Selection)]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumb

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        layout {
            ForEach(options, id: \.1) { option in
                let selected = selection == option.1
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selection = option.1
                } label: {
                    Text(option.0).font(.subheadline.weight(selected ? .semibold : .medium))
                        .foregroundStyle(selected ? RemoteInstrument.ink : RemoteInstrument.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected {
                                Capsule().fill(RemoteInstrument.thumb)
                                    .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.0)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RemoteInstrument.recess, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: selection)
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
