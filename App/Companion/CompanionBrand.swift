import CoreText
import SwiftUI

/// Companion's brand is independent of the inherited Assistant preferences.
/// The same screen-and-fangs geometry is used by the app icon and thevamp.app.
enum CompanionBrand {
    // Light surfaces are the iPhone app's system greys. Dark surfaces stay
    // pure neutral greys (AppearanceConvergenceTests holds the canvas to it).
    // Red is reserved for a primary action or a live signal.
    static var canvas: Color { .dynamic(light: 0xF2F2F7, dark: 0x171717, oled: 0x000000) }
    static var surface: Color { .dynamic(light: 0xFFFFFF, dark: 0x202020, oled: 0x121212) }
    static var inset: Color { .dynamic(light: 0xEDEDF2, dark: 0x2A2A2A, oled: 0x1A1A1A) }
    static var control: Color { .dynamic(light: 0xE5E5EA, dark: 0x333333, oled: 0x252525) }
    static var thumb: Color { .dynamic(light: 0xFFFFFF, dark: 0x5A5A5A, oled: 0x4A4A4A) }
    static var stroke: Color { .dynamic(light: 0xD8D8DD, dark: 0x3B3B3B, oled: 0x343434) }
    static let ink = Color.dynamic(light: 0x1C1C1E, dark: 0xF2F2F2, oled: 0xF2F2F2)
    static let secondary = Color.dynamic(light: 0x6C6C70, dark: 0xAEAEAE, oled: 0xAEAEAE)
    static let tertiary = Color.dynamic(light: 0x8A8A8E, dark: 0x8E8E8E, oled: 0x8E8E8E)
    static let accent = Color.fixed(0xBD2939)
    static let accentInk = Color.dynamic(light: 0xAD2030, dark: 0xF0808D, oled: 0xF0808D)
    static let green = Color.dynamic(light: 0x248A3D, dark: 0x30D158, oled: 0x30D158)
    static var accentWash: Color { control }
    static let radius: CGFloat = 14
    static let pageInset: CGFloat = 24

    static func display(_ size: CGFloat) -> Font { .custom("BarlowCondensed-Bold", size: size) }
    static func wordmark(_ size: CGFloat) -> Font { .custom("BarlowCondensed-Black", size: size) }

    @MainActor static func registerFonts() {
        for name in ["BarlowCondensed-Black", "BarlowCondensed-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

struct CompanionVampMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 8, y: 5))
        for point in [CGPoint(x: 32, y: 5), CGPoint(x: 38, y: 11),
                      CGPoint(x: 38, y: 28), CGPoint(x: 28, y: 28),
                      CGPoint(x: 25, y: 36), CGPoint(x: 20, y: 28),
                      CGPoint(x: 15, y: 36), CGPoint(x: 12, y: 28),
                      CGPoint(x: 2, y: 28), CGPoint(x: 2, y: 11)] {
            path.addLine(to: point)
        }
        path.closeSubpath()
        path.move(to: CGPoint(x: 10, y: 11))
        for point in [CGPoint(x: 8, y: 13), CGPoint(x: 8, y: 22),
                      CGPoint(x: 32, y: 22), CGPoint(x: 32, y: 13),
                      CGPoint(x: 30, y: 11)] {
            path.addLine(to: point)
        }
        path.closeSubpath()
        path.addRect(CGRect(x: 12, y: 15, width: 6, height: 3))
        path.addRect(CGRect(x: 22, y: 15, width: 6, height: 3))
        let scale = min(rect.width, rect.height) / 40
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
            .applying(CGAffineTransform(translationX: rect.midX - 20 * scale,
                                       y: rect.midY - 20 * scale))
    }
}

struct CompanionBrandBadge: View {
    var size: CGFloat = 48

    var body: some View {
        CompanionVampMark()
            .fill(CompanionBrand.ink, style: FillStyle(eoFill: true))
            .padding(size * 0.1)
            .frame(width: size, height: size)
            .background(CompanionBrand.surface, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(CompanionBrand.stroke.opacity(0.7), lineWidth: 0.5))
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(CompanionBrand.accent)
                    .frame(width: size * 0.17, height: size * 0.17)
                    .overlay(Circle().stroke(CompanionBrand.surface, lineWidth: 2))
                    .padding(3)
            }
            .accessibilityHidden(true)
    }
}

/// Sentence-case page title, as the iPhone app writes its headings.
struct CompanionPageHeading: View {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .semibold))
                .foregroundStyle(CompanionBrand.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.system(size: 13))
                .foregroundStyle(CompanionBrand.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A status dot that radiates a slow ring while the thing it describes is
/// alive, matching the iPhone app. Stops under Reduce Motion.
struct CompanionLivePulse: View {
    let color: Color
    var active = true
    var fast = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animates = active && !reduceMotion
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

struct CompanionStatusPill: View {
    let title: LocalizedStringResource
    let isReady: Bool
    var isConnecting = false

    private var color: Color {
        isReady ? CompanionBrand.green : isConnecting ? Color.orange : CompanionBrand.secondary
    }

    var body: some View {
        HStack(spacing: 6) {
            CompanionLivePulse(color: color, active: isReady || isConnecting, fast: isConnecting)
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 10).frame(height: 28)
        .companionToolbarTrack()
        .accessibilityElement(children: .combine)
    }
}

struct CompanionCardModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CompanionBrand.radius, style: .continuous)
        content
            .background(CompanionBrand.surface, in: shape)
            .overlay {
                // A lit top edge reads as depth without drawing a box.
                shape.strokeBorder(contrast == .increased
                    ? LinearGradient(colors: [CompanionBrand.secondary], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [CompanionBrand.stroke.opacity(scheme == .dark ? 0.9 : 0.6),
                                              CompanionBrand.stroke.opacity(scheme == .dark ? 0.3 : 0.25)],
                                     startPoint: .top, endPoint: .bottom),
                    lineWidth: contrast == .increased ? 1 : 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.05), radius: 10, y: 3)
    }
}

extension View {
    func companionCard() -> some View { modifier(CompanionCardModifier()) }

    /// macOS 26 already seats toolbar items on Liquid Glass; earlier systems
    /// get the same capsule as a quiet track.
    @ViewBuilder
    func companionToolbarTrack() -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            background(CompanionBrand.control, in: Capsule())
        }
    }
}

extension ToolbarContent {
    /// The logo sits on the bar itself, not inside a glass capsule.
    @ToolbarContentBuilder
    func companionBareToolbarItem() -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

struct CompanionSegment<Value: Hashable>: Identifiable {
    let title: LocalizedStringResource
    var symbol: String? = nil
    let value: Value
    var identifier: String? = nil
    var id: Value { value }
}

/// The iPhone app's segmented control: a neutral thumb that slides between
/// choices. Each segment stays a button with its own identifier.
struct CompanionSegments<Value: Hashable>: View {
    @Binding var selection: Value
    let segments: [CompanionSegment<Value>]
    var inToolbar = false
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                let selected = segment.value == selection
                Button { selection = segment.value } label: {
                    HStack(spacing: 6) {
                        if let symbol = segment.symbol {
                            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                        }
                        Text(segment.title)
                    }
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? CompanionBrand.ink : CompanionBrand.secondary)
                    .padding(.horizontal, 14).frame(height: 26)
                    .background {
                        if selected {
                            Capsule().fill(CompanionBrand.thumb)
                                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier(segment.identifier ?? "")
            }
        }
        .padding(2)
        .modifier(CompanionSegmentTrack(inToolbar: inToolbar))
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: selection)
    }
}

private struct CompanionSegmentTrack: ViewModifier {
    let inToolbar: Bool
    func body(content: Content) -> some View {
        if inToolbar { content.companionToolbarTrack() }
        else { content.background(CompanionBrand.control, in: Capsule()) }
    }
}

struct CompanionArcadeButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(primary ? Color.white : CompanionBrand.ink)
            .padding(.horizontal, 14).frame(minHeight: 30)
            .background(primary ? CompanionBrand.accent : CompanionBrand.control, in: Capsule())
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
