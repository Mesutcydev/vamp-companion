import SwiftUI

/// Companion's brand is independent of the inherited Assistant preferences.
/// The same screen-and-fangs geometry is used by the app icon and thevamp.app.
enum CompanionBrand {
    static let canvas = Color.dynamic(light: 0xF4F3F1, dark: 0x131416, oled: 0x08090A)
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x1D1F22, oled: 0x131517)
    static let inset = Color.dynamic(light: 0xEEEDEA, dark: 0x16181B, oled: 0x0D0F11)
    static let stroke = Color.dynamic(light: 0xDDDCDA, dark: 0x35383D, oled: 0x2A2D31)
    static let ink = Color.dynamic(light: 0x202124, dark: 0xF4F4F2, oled: 0xF4F4F2)
    static let secondary = Color.dynamic(light: 0x606166, dark: 0xB2B5BD, oled: 0xB2B5BD)
    static let accent = Color.fixed(0xBD2939)
    static let accentInk = Color.dynamic(light: 0xAD2030, dark: 0xFF7B88, oled: 0xFF7B88)
    static let accentWash = Color.dynamic(light: 0xFCE9E9, dark: 0x382126, oled: 0x301B21)
    static let radius: CGFloat = 16
    static let pageInset: CGFloat = 24
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
            .background(CompanionBrand.surface, in: RoundedRectangle(cornerRadius: size * 0.24))
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
                .tracking(1.8).foregroundStyle(CompanionBrand.accentInk)
            Text(title).font(.system(size: 25, weight: .semibold))
                .tracking(-0.7).foregroundStyle(CompanionBrand.ink)
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
        .background(CompanionBrand.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(CompanionBrand.stroke, lineWidth: 1))
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
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? CompanionBrand.ink : CompanionBrand.secondary)
            .padding(.horizontal, 18).frame(height: 36)
            .background(isSelected ? CompanionBrand.surface : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? CompanionBrand.stroke : .clear, lineWidth: 1))
            .overlay(alignment: .bottom) {
                Capsule().fill(isSelected ? CompanionBrand.accent : .clear)
                    .frame(width: 22, height: 2).padding(.bottom, 4)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}
