import CoreText
import SwiftUI

/// Companion's brand is independent of the inherited Assistant preferences.
/// The same screen-and-fangs geometry is used by the app icon and thevamp.app.
enum CompanionBrand {
    // Every large surface is neutral. Red is reserved for a primary action or
    // an active/attention signal, rather than colouring model categories.
    static var canvas: Color { .dynamic(light: 0xF4F4F4, dark: 0x181818, oled: 0x000000) }
    static var surface: Color { .dynamic(light: 0xFAFAFA, dark: 0x222222, oled: 0x131313) }
    static var inset: Color { .dynamic(light: 0xEFEFEF, dark: 0x1C1C1C, oled: 0x0C0C0C) }
    static var control: Color { .dynamic(light: 0xE8E8E8, dark: 0x303030, oled: 0x242424) }
    static var stroke: Color { .dynamic(light: 0xD0D0D0, dark: 0x414141, oled: 0x383838) }
    static let ink = Color.dynamic(light: 0x222222, dark: 0xF2F2F2, oled: 0xF2F2F2)
    static let secondary = Color.dynamic(light: 0x555555, dark: 0xBBBBBB, oled: 0xBBBBBB)
    static let tertiary = Color.dynamic(light: 0x666666, dark: 0x999999, oled: 0x999999)
    static let accent = Color.fixed(0xBD2939)
    static let accentInk = Color.dynamic(light: 0xAD2030, dark: 0xF0808D, oled: 0xF0808D)
    static var accentWash: Color { control }
    static let radius: CGFloat = 8
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
            .background(CompanionBrand.inset, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(CompanionBrand.stroke, lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(CompanionBrand.accent)
                    .frame(width: size * 0.17, height: size * 0.17)
                    .overlay(Circle().stroke(CompanionBrand.surface, lineWidth: 2))
                    .padding(3)
            }
            .accessibilityHidden(true)
    }
}

struct CompanionPageHeading: View {
    let eyebrow: LocalizedStringResource
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow).textCase(.uppercase)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.2).foregroundStyle(CompanionBrand.secondary)
            Text(title).font(.system(size: 25, weight: .semibold))
                .tracking(-0.4).foregroundStyle(CompanionBrand.ink)
            Text(subtitle).font(.system(size: 14))
                .foregroundStyle(CompanionBrand.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CompanionStatusPill: View {
    let title: LocalizedStringResource
    let isReady: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isReady ? CompanionBrand.ink : CompanionBrand.secondary)
            Text(title).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(CompanionBrand.ink)
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(CompanionBrand.inset, in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(CompanionBrand.stroke, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct CompanionCardModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(CompanionBrand.surface, in: RoundedRectangle(cornerRadius: CompanionBrand.radius))
            .overlay(RoundedRectangle(cornerRadius: CompanionBrand.radius)
                .strokeBorder(contrast == .increased ? CompanionBrand.secondary : CompanionBrand.stroke,
                              lineWidth: 1))
    }
}

extension View {
    func companionCard() -> some View { modifier(CompanionCardModifier()) }
}

struct CompanionNavigationButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isSelected ? CompanionBrand.ink : CompanionBrand.secondary)
            .padding(.horizontal, 18).frame(height: 36)
            .background(isSelected ? CompanionBrand.control : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottom) {
                Rectangle().fill(isSelected ? CompanionBrand.accent : .clear)
                    .frame(height: 2)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CompanionArcadeButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(primary ? Color.white : CompanionBrand.ink)
            .padding(.horizontal, 14).frame(minHeight: 36)
            .background(primary ? CompanionBrand.accent : CompanionBrand.control,
                        in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(primary ? CompanionBrand.accent : CompanionBrand.stroke, lineWidth: 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}
