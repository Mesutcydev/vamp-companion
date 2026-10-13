import CoreText
import SwiftUI

/// Companion's brand is independent of the inherited Assistant preferences.
/// The same screen-and-fangs geometry is used by the app icon and thevamp.app.
enum CompanionBrand {
    static var canvas: Color { .dynamic(light: 0xF4F4F4, dark: 0x111111, oled: 0x000000) }
    static var surface: Color { .dynamic(light: 0xFAFAFA, dark: 0x1C1C1C, oled: 0x131313) }
    static var inset: Color { .dynamic(light: 0xE8E8E8, dark: 0x080808, oled: 0x050505) }
    static var stroke: Color { .dynamic(light: 0xA4A4A4, dark: 0x777777, oled: 0x777777) }
    static let ink = Color.dynamic(light: 0x202124, dark: 0xF4F4F2, oled: 0xF4F4F2)
    static let secondary = Color.dynamic(light: 0x606166, dark: 0xB2B5BD, oled: 0xB2B5BD)
    static let accent = Color.fixed(0xBD2939)
    static let accentInk = Color.dynamic(light: 0xAD2030, dark: 0xFF7B88, oled: 0xFF7B88)
    static let accentWash = Color.dynamic(light: 0xFCE9E9, dark: 0x382126, oled: 0x301B21)
    static let radius: CGFloat = 4
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
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.8).foregroundStyle(CompanionBrand.secondary)
            Text(title).textCase(.uppercase).font(CompanionBrand.display(34))
                .tracking(0.3).foregroundStyle(CompanionBrand.ink)
                .shadow(color: CompanionBrand.stroke.opacity(0.6), radius: 0, x: 1, y: 1)
            Text(subtitle).font(.system(size: 13))
                .foregroundStyle(CompanionBrand.secondary)
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
            Circle().fill(isReady ? Theme.positive : CompanionBrand.secondary)
                .frame(width: 6, height: 6)
            Text(title).font(.system(size: 11, weight: .medium))
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
            .overlay(alignment: .top) {
                Rectangle().fill(CompanionBrand.ink).frame(height: 2)
                    .padding(.horizontal, 1)
            }
            .shadow(color: CompanionBrand.inset, radius: 0, x: 3, y: 3)
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
            .font(CompanionBrand.display(17))
            .foregroundStyle(isSelected ? CompanionBrand.canvas : CompanionBrand.secondary)
            .padding(.horizontal, 18).frame(height: 36)
            .background(isSelected ? CompanionBrand.ink : Color.clear,
                        in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3)
                .strokeBorder(isSelected ? CompanionBrand.ink : CompanionBrand.stroke, lineWidth: 1))
            .overlay(alignment: .bottom) {
                Rectangle().fill(isSelected ? CompanionBrand.accent : .clear)
                    .frame(height: 2)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 3))
    }
}

struct CompanionArcadeButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textCase(.uppercase).font(CompanionBrand.display(17))
            .foregroundStyle(primary ? CompanionBrand.canvas : CompanionBrand.ink)
            .padding(.horizontal, 14).frame(minHeight: 34)
            .background(primary ? CompanionBrand.ink : CompanionBrand.surface,
                        in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(CompanionBrand.ink, lineWidth: 1))
            .shadow(color: CompanionBrand.stroke, radius: 0,
                    x: configuration.isPressed ? 0 : 2, y: configuration.isPressed ? 0 : 2)
            .offset(x: configuration.isPressed && !reduceMotion ? 1 : 0,
                    y: configuration.isPressed && !reduceMotion ? 1 : 0)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}
