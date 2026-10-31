import SwiftUI

struct CompanionWebsitePromoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CompanionBrandBadge(size: 38)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MORE ROOM TO VAMP")
                        .font(.caption2.weight(.semibold)).tracking(1.2)
                        .foregroundStyle(CompanionBrand.accentInk)
                    Text("The unrestricted Mac edition")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(CompanionBrand.ink)
                }
            }
            Text("Get Vamp Companion directly from our website for Mac control, terminal access, coding tools, ChatGPT account sign-in, and more model runtimes.")
                .font(.callout).foregroundStyle(CompanionBrand.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: CompanionDistribution.websiteURL) {
                Label("Explore the website edition", systemImage: "arrow.up.right")
            }
            .buttonStyle(CompanionArcadeButtonStyle(primary: true))
            .accessibilityIdentifier("companion-website-edition-link")
            Text("A separate download for your Mac. Your App Store edition keeps working on its own.")
                .font(.caption).foregroundStyle(CompanionBrand.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .companionCard()
        .accessibilityIdentifier("companion-website-promo")
    }
}
