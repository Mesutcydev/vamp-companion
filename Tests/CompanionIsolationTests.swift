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

    func testCompanionHasNoLegacyMigrationOrUnboundedModelScan() {
        XCTAssertTrue(ModelStore.extraScanDirectories.isEmpty)
        XCTAssertEqual(ModelStore.defaultAssistantSupportDirectory.lastPathComponent, "BeetCode")
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
        let store = ModelStore(modelsDirectory: managed)
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
        let store = ModelStore(modelsDirectory: managed)
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

@MainActor
final class AssistantModelSharingTests: XCTestCase {
    override func tearDown() {
        ModelCatalog.updateAssistantModels([])
        super.tearDown()
    }

    private func catalog(id: String, role: CatalogModel.Role = .chat) -> CatalogModel {
        CatalogModel(id: id, repo: "fixture/\(id)", displayName: "Assistant \(id)",
            family: "Fixture", parameters: "1B", quantization: "4-bit", diskBytes: 7,
            contextWindow: 32_768, minRAMGB: 4, recommendedRAMGB: 8,
            notes: "Imported fixture", format: .gguf, role: role, lanes: [])
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url)
    }

    private func store(_ workspace: TempWorkspace) -> ModelStore {
        let own = workspace.makeDirectory("VampCompanion/Models")
        let assistant = workspace.makeDirectory("BeetCode")
        return ModelStore(modelsDirectory: own, assistantSupportDirectory: assistant)
    }

    func testAssistantImportsAppearBesideExistingCompanionDownloadsWithoutCopying() async throws {
        let temporary = TempWorkspace()
        let store = store(temporary)
        let own = catalog(id: "owned")
        let shared = catalog(id: "assistant-import", role: .vision)
        temporary.write("weights", to: "VampCompanion/Models/owned/model.gguf")
        temporary.write("weights", to: "BeetCode/Models/assistant-import/model.gguf")
        try write([own], to: temporary.url(for: "VampCompanion/UserModels.json"))
        try write([shared], to: temporary.url(for: "BeetCode/UserModels.json"))
        _ = store.register(catalogModel: own, sizeBytes: 7)

        await store.refreshFromDisk()

        XCTAssertEqual(Set(store.installed.map(\.id)), [own.id, shared.id])
        let reference = try XCTUnwrap(store.installedModel(id: shared.id))
        XCTAssertTrue(reference.isSharedFromAssistant)
        XCTAssertEqual(store.directory(for: reference), temporary.url(for: "BeetCode/Models/assistant-import"))
        XCTAssertTrue(store.isInstalled(catalogModel: shared))
        XCTAssertEqual(store.detectedFormat(reference), .gguf)
        XCTAssertEqual(ModelCatalog.model(id: shared.id)?.role, .vision)
        XCTAssertEqual(ModelCatalog.model(id: shared.id)?.contextWindow, 32_768)
        XCTAssertFalse(temporary.exists("VampCompanion/Models/assistant-import"))
    }

    func testSharedLibraryRefreshesNewDeletedAndMovedModels() async throws {
        let temporary = TempWorkspace()
        let store = store(temporary)
        await store.refreshFromDisk()
        XCTAssertTrue(store.installed.isEmpty)
        temporary.write("weights", to: "BeetCode/Models/late-import/model.gguf")
        await store.refreshFromDisk()
        XCTAssertTrue(store.installedModel(id: "late-import")?.isSharedFromAssistant == true)
        let external = temporary.makeDirectory("external/late-import")
        temporary.write("external weights", to: "external/late-import/model.gguf")
        let registration = InstalledModel(id: "late-import", repo: "fixture", addedAt: Date(),
            sizeBytes: 16, basePath: external.deletingLastPathComponent().path)
        try write([registration], to: temporary.url(for: "BeetCode/Models/InstalledModels.json"))
        await store.refreshFromDisk()
        XCTAssertEqual(store.directory(for: try XCTUnwrap(store.installedModel(id: "late-import"))).path, external.path)
        try FileManager.default.removeItem(at: external)
        await store.refreshFromDisk()
        XCTAssertNil(store.installedModel(id: "late-import"))
        XCTAssertNil(ModelCatalog.model(id: "late-import"))
    }

    func testSharedRemovalHidesReferenceAcrossRelaunchAndRestoreUsesSameFiles() async throws {
        let temporary = TempWorkspace()
        let store = store(temporary)
        temporary.write("weights", to: "BeetCode/Models/shared/model.gguf")
        let originalCatalog = temporary.url(for: "BeetCode/UserModels.json")
        let originalRegistry = temporary.url(for: "BeetCode/Models/InstalledModels.json")
        try write([catalog(id: "shared")], to: originalCatalog)
        try write([InstalledModel(id: "shared", repo: "fixture", addedAt: Date(), sizeBytes: 7,
            basePath: nil)], to: originalRegistry)
        let catalogBytes = try Data(contentsOf: originalCatalog)
        let registryBytes = try Data(contentsOf: originalRegistry)
        await store.refreshFromDisk()
        store.uninstall(try XCTUnwrap(store.installedModel(id: "shared")))
        await store.refreshFromDisk()
        XCTAssertNil(store.installedModel(id: "shared"))
        XCTAssertTrue(temporary.exists("BeetCode/Models/shared/model.gguf"))

        let reopened = self.store(temporary)
        await reopened.refreshFromDisk()
        XCTAssertNil(reopened.installedModel(id: "shared"))
        XCTAssertTrue(reopened.isSharedModelAvailable(id: "shared"))
        XCTAssertTrue(reopened.restoreSharedModel(id: "shared"))
        XCTAssertTrue(reopened.installedModel(id: "shared")?.isSharedFromAssistant == true)
        XCTAssertFalse(temporary.exists("VampCompanion/Models/shared"))
        XCTAssertEqual(try Data(contentsOf: originalCatalog), catalogBytes)
        XCTAssertEqual(try Data(contentsOf: originalRegistry), registryBytes)
    }

    func testCompanionCopyWinsDuplicateIDAndAssistantBecomesAvailableAfterRemoval() async throws {
        let temporary = TempWorkspace()
        let store = store(temporary)
        let model = catalog(id: "duplicate")
        temporary.write("owned", to: "VampCompanion/Models/duplicate/model.gguf")
        temporary.write("shared", to: "BeetCode/Models/duplicate/model.gguf")
        try write([model], to: temporary.url(for: "VampCompanion/UserModels.json"))
        _ = store.register(catalogModel: model, sizeBytes: 5)
        await store.refreshFromDisk()
        XCTAssertEqual(store.installed.count, 1)
        let owned = try XCTUnwrap(store.installed.first)
        XCTAssertFalse(owned.isSharedFromAssistant)
        XCTAssertEqual(store.directory(for: owned), temporary.url(for: "VampCompanion/Models/duplicate"))
        store.uninstall(owned)
        await store.refreshFromDisk()
        XCTAssertTrue(store.installedModel(id: model.id)?.isSharedFromAssistant == true)
        XCTAssertTrue(temporary.exists("BeetCode/Models/duplicate/model.gguf"))
    }

    func testRegisteredExternalBookmarkUsesExactDirectoryWithoutCopyingBookmark() throws {
        let temporary = TempWorkspace()
        let assistant = temporary.makeDirectory("BeetCode")
        _ = temporary.makeDirectory("BeetCode/Models")
        let external = temporary.makeDirectory("different-folder-name")
        temporary.write("weights", to: "different-folder-name/model.gguf")
        let bookmark = try external.bookmarkData(options: .withSecurityScope,
            includingResourceValuesForKeys: nil, relativeTo: nil)
        let registered = InstalledModel(id: "external-reference", repo: "fixture", addedAt: Date(), sizeBytes: 7,
            directoryBookmark: bookmark, basePath: nil)
        try write([registered], to: temporary.url(for: "BeetCode/Models/InstalledModels.json"))
        let snapshot = AssistantModelLibrary.scan(supportDirectory: assistant, catalog: [])
        let reference = try XCTUnwrap(snapshot.installed.first)
        XCTAssertEqual(reference.assistantDirectoryPath, external.path)
        XCTAssertNil(reference.directoryBookmark)
        XCTAssertTrue(reference.isSharedFromAssistant)
    }

    func testIncompleteDownloadsMissingShardsAndWeightDirectoriesAreIgnored() throws {
        let temporary = TempWorkspace()
        let assistant = temporary.makeDirectory("BeetCode")
        temporary.write("weights", to: "BeetCode/Models/partial/model.gguf")
        temporary.write("partial", to: "BeetCode/Models/partial/file.incomplete")
        temporary.write("{}", to: "BeetCode/Models/config-only/config.json")
        temporary.write("{}", to: "BeetCode/Models/sharded/config.json")
        temporary.write("weights", to: "BeetCode/Models/sharded/model-00001.safetensors")
        temporary.write("{\"weight_map\":{\"a\":\"model-00001.safetensors\",\"b\":\"model-00002.safetensors\"}}",
            to: "BeetCode/Models/sharded/model.safetensors.index.json")
        _ = temporary.makeDirectory("BeetCode/Models/not-a-weight/model.gguf")
        temporary.write("weights", to: "BeetCode/Models/complete/model.gguf")
        let snapshot = AssistantModelLibrary.scan(supportDirectory: assistant, catalog: [])
        XCTAssertEqual(snapshot.installed.map(\.id), ["complete"])
    }

    func testCompletedMLXShardsAndCoreAIPacksAreRecognized() throws {
        let temporary = TempWorkspace()
        let assistant = temporary.makeDirectory("BeetCode")
        temporary.write("{\"model_type\":\"qwen3\"}", to: "BeetCode/Models/mlx/config.json")
        temporary.write("weights", to: "BeetCode/Models/mlx/model.safetensors")
        temporary.write("{\"weight_map\":{\"a\":\"model.safetensors\"}}",
            to: "BeetCode/Models/mlx/model.safetensors.index.json")
        temporary.write("{}", to: "BeetCode/Models/core/platform/metadata.json")
        temporary.write("weights", to: "BeetCode/Models/core/platform/model.aimodel")
        let snapshot = AssistantModelLibrary.scan(supportDirectory: assistant, catalog: [])
        XCTAssertEqual(Set(snapshot.installed.map(\.id)), ["mlx", "core"])
        XCTAssertEqual(snapshot.catalog.first(where: { $0.id == "mlx" })?.format, .mlx)
        XCTAssertEqual(snapshot.catalog.first(where: { $0.id == "core" })?.format, .coreAI)
    }

    func testInvalidQwenStreamingArtifactAndEscapingRegistryIDsAreIgnored() throws {
        let temporary = TempWorkspace()
        let assistant = temporary.makeDirectory("BeetCode")
        temporary.write("weights", to: "BeetCode/Models/\(QwenStreamArtifact.modelID)/model.gguf")
        temporary.write("weights", to: "outside/model.gguf")
        let escaped = InstalledModel(id: "../../outside", repo: "fixture", addedAt: Date(), sizeBytes: 7, basePath: nil)
        try write([escaped], to: temporary.url(for: "BeetCode/Models/InstalledModels.json"))
        XCTAssertTrue(AssistantModelLibrary.scan(supportDirectory: assistant, catalog: []).installed.isEmpty)
    }

    func testMissingAssistantDoesNotCreateOrWriteItsDirectories() async throws {
        let temporary = TempWorkspace()
        let missing = temporary.url(for: "missing-assistant")
        let store = ModelStore(modelsDirectory: temporary.makeDirectory("VampCompanion/Models"),
            assistantSupportDirectory: missing)
        await store.refreshFromDisk()
        XCTAssertTrue(store.installed.isEmpty)
        XCTAssertFalse(temporary.exists("missing-assistant"))
    }

    func testSharedCatalogDeduplicatesBundledIDsAndOldRegistryStillDecodes() throws {
        let bundled = try XCTUnwrap(ModelCatalog.bundled.first)
        ModelCatalog.updateAssistantModels([bundled])
        XCTAssertEqual(ModelCatalog.all.filter { $0.id == bundled.id }.count, 1)
        let legacy = Data("[{\"id\":\"legacy\",\"repo\":\"fixture\",\"addedAt\":0,\"sizeBytes\":7}]".utf8)
        let decoded = try JSONDecoder().decode([InstalledModel].self, from: legacy)
        XCTAssertFalse(try XCTUnwrap(decoded.first).isSharedFromAssistant)
    }
}
