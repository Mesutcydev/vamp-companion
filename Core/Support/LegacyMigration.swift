import Foundation

/// The companion never migrates Vamp Assistant or LocalForge state.
/// Retained as a no-op facade for inherited callers.
enum LegacyMigration {
    static let legacyAppSupportName = "LocalForge"
    static let appSupportName = CompanionIdentity.supportDirectoryName
    static func runOnce() {}
    static func pendingInteractiveRenames() -> [(legacy: String, current: String)] { [] }
    static func needsInteractiveKeyMigration() -> Bool { false }
    @discardableResult static func migrateInteractively() -> Int { 0 }
    static func migrateAppSupportFolder() {}

    /// Pure helper used only by inherited temporary-folder tests.
    static func migrateFolder(from legacy: URL, to new: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: legacy.path), !manager.fileExists(atPath: new.path) else { return }
        try? manager.moveItem(at: legacy, to: new)
    }
}
