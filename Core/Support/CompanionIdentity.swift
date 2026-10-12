import Foundation

/// App-owned state must never use Vamp Assistant's persistence namespaces.
enum CompanionIdentity {
    static let bundleIdentifier = "com.beetcode.companion"
    static let supportDirectoryName = "VampCompanion"
    static let keychainPrefix = "com.beetcode.companion"
    static let checkpointRefPrefix = "refs/vamp-companion/checkpoints/"
    static let userConfigurationDirectory = ".vamp-companion"
    static let updateFeed = "https://mesutcydev.github.io/vamp-companion/appcast.xml"

    static func keychainService(_ name: String) -> String {
        "\(keychainPrefix).\(name)"
    }
}
