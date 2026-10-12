import AppKit
import XCTest
@testable import BeetCode

@MainActor
final class CompanionIsolationTests: XCTestCase {
    func testKeychainRemovalNeverTouchesOriginalProviderKey() {
        let originalService = "com.beetcode.provider.openAI"
        XCTAssertTrue(Keychain.write("original-key", service: originalService, account: "api-key"))
        defer { Keychain.delete(service: originalService, account: "api-key") }
        XCTAssertEqual(LLMProvider.openAI.keychainService, "com.beetcode.companion.provider.openAI")
        XCTAssertTrue(APIKeyStore.shared.save(key: "companion-key", for: .openAI))
        APIKeyStore.shared.deleteKey(for: .openAI)
        XCTAssertEqual(Keychain.read(service: originalService, account: "api-key"), "original-key")
        XCTAssertNil(Keychain.read(service: LLMProvider.openAI.keychainService, account: "api-key"))
    }

    func testCheckpointCleanupKeepsOriginalAppPins() throws {
        let temporary = TempWorkspace()
        let repository = GitRepo(in: temporary)
        temporary.write("hello", to: "sample.txt")
        repository.commitAll(message: "Initial")
        let checkpointer = GitCheckpointer(workspace: temporary.workspace)
        let checkpoint = try checkpointer.snapshot(summary: "Companion checkpoint")
        let originalRef = "refs/beetcode/checkpoints/original"
        XCTAssertEqual(repository.run("update-ref", originalRef, checkpoint.treeSHA).status, 0)
        let removed = GitCheckpointer.sweepOrphanedPins(
            workspacePath: temporary.url.path, referencedTreeSHAs: [])
        XCTAssertEqual(removed, [try XCTUnwrap(checkpoint.refName)])
        XCTAssertEqual(repository.run("show-ref", "--verify", originalRef).status, 0)
        XCTAssertTrue(checkpointer.pinnedCheckpointRefs().isEmpty)
    }

    func testDefaultPortsNeverOverlapOriginalApps() {
        XCTAssertEqual(RemoteSessionPorts.defaultPort, 9675)
        for originalPort in [9471, 9472, 9473, 9475] + Array(9575...9583) {
            XCTAssertEqual(RemoteSessionPorts.resolved(originalPort), 9675)
            XCTAssertFalse(RemoteSessionPorts.candidates(preferred: originalPort).contains(originalPort))
        }
        XCTAssertEqual(RemoteSessionPorts.candidates(preferred: 0), [0])
        XCTAssertEqual(RemoteSessionPorts.candidates(preferred: 9675), Array(9675...9683))
        XCTAssertEqual(RemoteSessionPorts.candidates(preferred: 65_535), [65_535])
    }

    func testCompanionHasNoLegacyMigrationOrAutomaticModelScan() {
        XCTAssertTrue(ModelStore.extraScanDirectories.isEmpty)
        XCTAssertTrue(LegacyMigration.pendingInteractiveRenames().isEmpty)
        XCTAssertFalse(LegacyMigration.needsInteractiveKeyMigration())
        XCTAssertEqual(LegacyMigration.migrateInteractively(), 0)
    }

    func testWindowCloseKeepsTheApplicationRunning() {
        let delegate = CompanionAppDelegate()
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    func testUninstallDoesNotFollowARegistryPathOutsideCompanionModels() throws {
        let temporary = TempWorkspace()
        let managed = temporary.makeDirectory("VampCompanion/Models")
        let originalModel = temporary.makeDirectory("BeetCode/Models/original")
        temporary.write("original weights", to: "BeetCode/Models/original/model.gguf")
        let store = ModelStore()
        store.overrideModelsDir = managed
        let malicious = InstalledModel(
            id: "../../BeetCode/Models/original", repo: "fixture", addedAt: Date(), sizeBytes: 16,
            basePath: nil)
        store.uninstall(malicious)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalModel.appendingPathComponent("model.gguf").path))
    }

    func testUninstallOfReferencedExternalModelKeepsOriginalFiles() throws {
        let temporary = TempWorkspace()
        let managed = temporary.makeDirectory("VampCompanion/Models")
        let external = temporary.makeDirectory("original-model")
        temporary.write("weights", to: "original-model/model.gguf")
        var catalog = try XCTUnwrap(ModelCatalog.bundled.first)
        catalog.id = "external-fixture"
        catalog.directoryBookmark = try external.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        let store = ModelStore()
        store.overrideModelsDir = managed
        let installed = store.register(catalogModel: catalog, sizeBytes: 7)
        store.uninstall(installed)
        XCTAssertTrue(temporary.exists("original-model/model.gguf"))
        XCTAssertNil(store.installedModel(id: catalog.id))
    }

    func testOwnStorageAndUpdateIdentity() {
        XCTAssertEqual(CompanionIdentity.bundleIdentifier, "com.beetcode.companion")
        XCTAssertEqual(ModelStore.shared.modelsBaseURL.deletingLastPathComponent().lastPathComponent, "VampCompanion")
        XCTAssertEqual(ManagedInferenceRuntime.root.lastPathComponent, "Runtimes")
        XCTAssertEqual(ManagedInferenceRuntime.root.deletingLastPathComponent().lastPathComponent, "VampCompanion")
        XCTAssertEqual(CompanionIdentity.updateFeed, "https://mesutcydev.github.io/vamp-companion/appcast.xml")
    }
}
