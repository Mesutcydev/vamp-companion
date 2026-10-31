import Foundation

/// Distribution is selected at compile time, never by a preference or a client request.
enum CompanionDistribution {
    #if VAMP_APP_STORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif

    static let websiteURL = URL(string: "https://thevamp.app/companion/")!
    static let privacyURL = URL(string: "https://thevamp.app/privacy/")!
    static let unrestrictedFeaturesMessage = "Mac control, terminal, coding tools, ChatGPT account sign-in, and external inference runtimes are available in the website edition."

    static func supports(_ format: CatalogModel.Format) -> Bool {
        !isAppStore || format == .mlx
    }

    static func supports(_ model: CatalogModel) -> Bool {
        supports(model.format) && (!isAppStore || model.id != ManagedMLXEngine.bonsaiModelID)
    }

    /// Apply before route dispatch, including nested and future control routes.
    static func allowsRemotePath(_ path: String) -> Bool {
        guard isAppStore else { return true }
        let families = ["/api/control", "/api/workspaces", "/api/bot-computers", "/api/bot-runs", "/api/bot-workflows"]
        return !families.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
