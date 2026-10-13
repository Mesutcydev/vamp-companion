import Foundation

/// Registry of downloaded models on disk. Layout:
///   ~/Library/Application Support/VampCompanion/Models/<model-id>/…
/// Each installed model records where it came from so updates and deletes
/// are exact.
struct InstalledModel: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var repo: String
    var addedAt: Date
    var sizeBytes: Int64
    var artifactRevision: String? = nil
    var validationStatus: String? = nil
    var directoryBookmark: Data? = nil
    /// Read-only reference to weights discovered in Vamp Assistant's library.
    /// The directory can have a different name from the model ID (external imports).
    var assistantDirectoryPath: String? = nil
    /// Explicit base directory when the model lives OUTSIDE the managed
    /// Application Support Models folder (e.g. the project's gitignored
    /// `beetcode-models/` created by the legacy `lf download` CLI). nil means
    /// the default base.
    var basePath: String?

    var directoryName: String { id }
    var isSharedFromAssistant: Bool { assistantDirectoryPath != nil }
}

/// Read-only discovery of Vamp Assistant weights and model metadata. No
/// migration, registry writes, file copies, or inference processes are shared.
enum AssistantModelLibrary {
    struct Snapshot: Sendable {
        var catalog: [CatalogModel]
        var installed: [InstalledModel]
    }

    static func readJSON<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
        let limit = 4 * 1_024 * 1_024
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue <= limit,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1), data.count <= limit else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func isModelID(_ id: String) -> Bool {
        !id.isEmpty && !id.hasPrefix(".") && !id.contains("/")
            && !id.contains("\\") && !id.contains("\0")
    }

    static func scan(supportDirectory: URL, catalog: [CatalogModel]) -> Snapshot {
        let base = supportDirectory.appendingPathComponent("Models", isDirectory: true)
        let users = readJSON([CatalogModel].self,
            at: supportDirectory.appendingPathComponent("UserModels.json")) ?? []
        let registered = readJSON([InstalledModel].self,
            at: base.appendingPathComponent("InstalledModels.json")) ?? []
        let known = Dictionary((users + catalog).filter { isModelID($0.id) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        var references: [String: (URL, InstalledModel?)] = [:]
        for model in registered.prefix(10_000) where isModelID(model.id) {
            let directory: URL
            if let bookmark = model.directoryBookmark {
                var stale = false
                guard let resolved = try? URL(resolvingBookmarkData: bookmark,
                    options: [.withoutUI, .withoutMounting], relativeTo: nil,
                    bookmarkDataIsStale: &stale) else { continue }
                directory = resolved
            } else if let path = model.basePath, path.hasPrefix("/") {
                directory = URL(fileURLWithPath: path, isDirectory: true)
                    .appendingPathComponent(model.id, isDirectory: true)
            } else if model.basePath == nil {
                directory = base.appendingPathComponent(model.id, isDirectory: true)
            } else {
                continue
            }
            references[model.id] = (directory, model)
        }
        // Also find completed downloads that were never registered, and
        // imported model IDs that are absent from Companion's bundled catalog.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        for name in names.sorted().prefix(10_000) where isModelID(name) && references[name] == nil {
            references[name] = (base.appendingPathComponent(name, isDirectory: true), nil)
        }
        for model in users where isModelID(model.id) && references[model.id] == nil {
            guard let bookmark = model.directoryBookmark else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting], relativeTo: nil,
                bookmarkDataIsStale: &stale) {
                references[model.id] = (url, nil)
            }
        }

        var result = Snapshot(catalog: [], installed: [])
        for id in references.keys.sorted() {
            guard let (directory, registration) = references[id] else { continue }
            let scoped = directory.startAccessingSecurityScopedResource()
            defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
                  isComplete(at: directory, names: names) else { continue }
            if id == QwenStreamArtifact.modelID && (try? QwenStreamArtifact.inspect(directory)) == nil { continue }
            let size = (try? ModelStore.sizeOfDirectory(directory)) ?? registration?.sizeBytes ?? 0
            var metadata = known[id] ?? inferredModel(id: id, directory: directory, names: names, size: size)
            metadata.directoryBookmark = nil  // Do not copy another app's security-scoped state.
            metadata.diskBytes = size
            result.catalog.append(metadata)
            result.installed.append(InstalledModel(
                id: id, repo: registration?.repo ?? metadata.repo,
                addedAt: registration?.addedAt ?? .distantPast, sizeBytes: size,
                artifactRevision: registration?.artifactRevision,
                validationStatus: registration?.validationStatus,
                assistantDirectoryPath: directory.standardizedFileURL.path, basePath: nil))
        }
        return result
    }

    private static func isComplete(at directory: URL, names: [String]) -> Bool {
        guard !names.contains(where: { $0.hasSuffix(".incomplete") }) else { return false }
        let files = names.filter { name in
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(name).path)
            return attributes?[.type] as? FileAttributeType == .typeRegular
                && ((attributes?[.size] as? NSNumber)?.int64Value ?? 0) > 0
        }
        guard ModelStore.isCompleteSnapshot(dirNames: files)
                || ModelStore.isCompleteCoreAIPack(at: directory) else { return false }
        if names.contains("model.safetensors.index.json") {
            struct Index: Decodable { let weight_map: [String: String] }
            guard let index = readJSON(Index.self, at: directory.appendingPathComponent("model.safetensors.index.json")),
                  !index.weight_map.isEmpty,
                  Set(index.weight_map.values).isSubset(of: Set(files)) else { return false }
        }
        return true
    }

    private static func inferredModel(id: String, directory: URL, names: [String], size: Int64) -> CatalogModel {
        let gguf = names.sorted().first {
            $0.lowercased().hasSuffix(".gguf") && !$0.lowercased().contains("mmproj")
                && !$0.lowercased().contains("lora")
        }
        let mlx = MLXModelInspector.read(from: directory)
        let ggufMetadata = gguf.flatMap { GGUFMetadata.read(from: directory.appendingPathComponent($0)) }
        let format: CatalogModel.Format = gguf != nil ? .gguf
            : (ModelStore.isCompleteCoreAIPack(at: directory) ? .coreAI : .mlx)
        return CatalogModel(
            id: id, repo: directory.path,
            displayName: mlx.map { MLXModelInspector.displayName(for: directory, metadata: $0) }
                ?? id.replacingOccurrences(of: "-", with: " "),
            family: mlx?.family ?? ggufMetadata?.architecture?.capitalized ?? format.rawValue.uppercased(),
            parameters: mlx?.parameters ?? "—", quantization: mlx?.quantization ?? format.rawValue.uppercased(),
            diskBytes: size, contextWindow: mlx?.contextWindow ?? ggufMetadata?.contextLength ?? 8_192,
            minRAMGB: max(6, Int(Double(size) / 1_000_000_000 * 1.5)),
            recommendedRAMGB: max(8, Int(Double(size) / 1_000_000_000 * 2)),
            notes: "Shared with Vamp Assistant. Uses the existing model files.", format: format, lanes: [])
    }
}

@MainActor
final class ModelStore: ObservableObject {

    static let shared = ModelStore()

    @Published private(set) var installed: [InstalledModel] = []

    private let fileManager = FileManager.default
    private let assistantSupportDirectory: URL?
    private var scanTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var sharedModels: [InstalledModel] = []
    private var hiddenAssistantModels: Set<String> = []

    /// Test seam: redirects the models directory away from real Application
    /// Support.
    var overrideModelsDir: URL?

    /// Base directory for all model snapshots (Application Support/VampCompanion/Models).
    var modelsBaseURL: URL {
        modelsDirectory
    }

    private var modelsDirectory: URL {
        if let override = overrideModelsDir { return override }
        let dir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VampCompanion/Models", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Legacy CLI folders are not searched. Assistant sharing uses only its
    /// model library and explicit model references, never its other app state.
    nonisolated static var extraScanDirectories: [URL] { [] }

    nonisolated static var defaultAssistantSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeetCode", isDirectory: true)
    }

    private var registryURL: URL {
        modelsDirectory.appendingPathComponent("InstalledModels.json")
    }

    init(modelsDirectory: URL? = nil, assistantSupportDirectory: URL? = nil) {
        overrideModelsDir = modelsDirectory
        // UI fixtures have their own empty model library. Never read or prune
        // the user's registry just to capture an empty state in a UI test.
        let environment = ProcessInfo.processInfo.environment
        let isTestHost = environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
            || environment["VAMP_COMPANION_UI_TESTING"] == "1"
        var assistantRoot = assistantSupportDirectory
        if environment["VAMP_COMPANION_UI_TESTING"] == "1",
           let path = environment["VAMP_COMPANION_UI_MODEL_ROOT"] {
            let candidate = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
            // The sandboxed UI runner has a different TMPDIR from the app.
            // Allow only system temp roots and that runner's known temp container.
            let temporaryRoots = [fileManager.temporaryDirectory,
                URL(fileURLWithPath: "/private/tmp", isDirectory: true),
                fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
                    "Library/Containers/com.beetcode.companion.uitests.xctrunner/Data/tmp", isDirectory: true)
            ].map { $0.resolvingSymlinksInPath() }
            if temporaryRoots.contains(where: { candidate.path.hasPrefix($0.path + "/") }) {
                overrideModelsDir = candidate
                try? fileManager.createDirectory(at: candidate, withIntermediateDirectories: true)
                if let path = environment["VAMP_COMPANION_UI_ASSISTANT_ROOT"] {
                    let fixture = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
                    if temporaryRoots.contains(where: { fixture.path.hasPrefix($0.path + "/") }) {
                        assistantRoot = fixture
                    }
                }
            }
        }
        self.assistantSupportDirectory = assistantRoot
            ?? (!isTestHost && overrideModelsDir == nil ? Self.defaultAssistantSupportDirectory : nil)
        loadRegistry()
        hiddenAssistantModels = Set(AssistantModelLibrary.readJSON(
            [String].self, at: hiddenModelsURL) ?? [])
        // Repair: drop registry entries whose directories vanished (moved or
        // deleted outside the app).
        let before = installed.count
        installed.removeAll { model in
            if model.directoryBookmark != nil { return false }
            return !fileManager.fileExists(atPath: directory(for: model).path)
                || !self.hasConfiguration(model)
        }
        if installed.count != before {
            saveRegistry()
        }
        // Always scan: Assistant models must appear even when Companion
        // already has downloads of its own. All discovery/sizing is off-main.
        if !isTestHost && overrideModelsDir == nil {
            rescanFromDisk()
            refreshTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard let self, !Task.isCancelled else { return }
                    self.rescanFromDisk()
                }
            }
        }
    }

    deinit {
        scanTask?.cancel()
        refreshTask?.cancel()
    }

    func directory(for model: InstalledModel) -> URL {
        if let path = model.assistantDirectoryPath {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if let bookmark = model.directoryBookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark,
                                  options: [.withSecurityScope, .withoutUI],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                if stale {
                    let scope = url.startAccessingSecurityScopedResource()
                    defer { if scope { url.stopAccessingSecurityScopedResource() } }
                    if let renewed = try? url.bookmarkData(options: .withSecurityScope,
                                                          includingResourceValuesForKeys: nil, relativeTo: nil),
                       let i = installed.firstIndex(where: { $0.id == model.id }) {
                        installed[i].directoryBookmark = renewed
                        saveRegistry()
                    }
                }
                return url
            }
            return modelsDirectory.appendingPathComponent(".unavailable-" + model.id)
        }
        if let basePath = model.basePath {
            return URL(fileURLWithPath: basePath, isDirectory: true)
                .appendingPathComponent(model.directoryName, isDirectory: true)
        }
        return modelsDirectory.appendingPathComponent(model.directoryName, isDirectory: true)
    }

    /// A downloaded model is loadable when its weight files are complete.
    /// Two layouts:
    /// - **MLX**: `config.json` + ≥1 `.safetensors` (the historical layout)
    /// - **GGUF**: ≥1 `.gguf` file (llama.cpp; no config.json in the repo)
    /// - **Core AI**: `metadata.json` + ≥1 `.aimodel`/`.aimodelc` resource
    /// A leftover `.incomplete` file always means the download never finished.
    func hasConfiguration(_ model: InstalledModel) -> Bool {
        let dir = directory(for: model)
        if model.id == QwenStreamArtifact.modelID {
            let scoped = dir.startAccessingSecurityScopedResource()
            defer { if scoped { dir.stopAccessingSecurityScopedResource() } }
            return (try? QwenStreamArtifact.inspect(dir)) != nil
        }
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else {
            return false
        }
        return Self.isCompleteSnapshot(dirNames: names)
            || Self.isCompleteCoreAIPack(at: dir)
    }

    /// Shared completeness check for `hasConfiguration` and `scanFromDisk` —
    /// the two must agree or a model shows as installed in one place and as
    /// "Download" in another.
    nonisolated static func isCompleteSnapshot(dirNames names: [String]) -> Bool {
        if names.contains(where: { $0.hasSuffix(".incomplete") }) {
            return false
        }
        // GGUF first: a single-file format, complete iff the .gguf exists.
        if names.contains(where: { $0.lowercased().hasSuffix(".gguf") }) {
            return true
        }
        // MLX: config.json plus real weight files (a directory holding only
        // config/tokenizer files — interrupted before the weights arrived —
        // would otherwise crash the loader with `keyNotFound(lm_head.weight)`).
        guard names.contains("config.json") else { return false }
        return names.contains(where: {
            $0.hasSuffix(".safetensors") || $0.hasSuffix(".weight")
        })
    }

    /// Core AI bundles commonly nest their resources below a platform or
    /// quantization directory, so the shallow MLX/GGUF check is insufficient.
    /// Enumeration is bounded and skips hidden/package descendants.
    nonisolated static func isCompleteCoreAIPack(at directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return false }
        var sawMetadata = false
        var sawAsset = false
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 20_000 { return false }
            let name = url.lastPathComponent.lowercased()
            if name.hasSuffix(".incomplete") { return false }
            if name == "metadata.json" { sawMetadata = true }
            if name.hasSuffix(".aimodel") || name.hasSuffix(".aimodelc") { sawAsset = true }
            if sawMetadata && sawAsset { return true }
        }
        return false
    }

    /// Detects the weights format present on disk for an installed model.
    func detectedFormat(_ model: InstalledModel) -> CatalogModel.Format {
        if model.id == QwenStreamArtifact.modelID { return .qwenStreaming }
        let dir = directory(for: model)
        guard let names = try? fileManager.contentsOfDirectory(atPath: dir.path) else {
            return .mlx
        }
        if names.contains(where: { $0.lowercased().hasSuffix(".gguf") }) {
            return .gguf
        }
        if Self.isCompleteCoreAIPack(at: dir) { return .coreAI }
        return .mlx
    }

    func isInstalled(catalogModel: CatalogModel) -> Bool {
        installed.contains { $0.id == catalogModel.id && hasConfiguration($0) }
    }

    func installedModel(id: String) -> InstalledModel? {
        installed.first { $0.id == id }
    }

    /// Marks a freshly downloaded snapshot as installed and computes its real
    /// size. Idempotent: re-registering an existing model replaces it.
    func register(catalogModel: CatalogModel, sizeBytes: Int64) -> InstalledModel {
        let model = InstalledModel(
            id: catalogModel.id,
            repo: catalogModel.repo,
            addedAt: Date(),
            sizeBytes: sizeBytes,
            artifactRevision: catalogModel.format == .qwenStreaming ? QwenStreamArtifact.revision : nil,
            validationStatus: catalogModel.format == .qwenStreaming ? "payload-verified" : nil,
            directoryBookmark: catalogModel.directoryBookmark)
        installed.removeAll { $0.id == model.id }
        installed.append(model)
        installed.sort { $0.addedAt > $1.addedAt }
        saveRegistry()
        return model
    }

    func uninstall(_ model: InstalledModel) {
        // Only delete from the managed Application Support folder. Models
        // living in an external base (legacy CLI folder, user import) get
        // de-registered but their files stay put — deleting repo-local or
        // user-owned directories would be surprising and destructive.
        if model.basePath == nil && model.directoryBookmark == nil && !model.isSharedFromAssistant {
            let base = modelsDirectory.resolvingSymlinksInPath().standardizedFileURL
            let target = directory(for: model).resolvingSymlinksInPath().standardizedFileURL
            // Corrupt registrations and symlinks must not delete another app's files.
            if target.path.hasPrefix(base.path + "/") {
                try? fileManager.removeItem(at: target)
            }
        }
        installed.removeAll { $0.id == model.id }
        if model.isSharedFromAssistant {
            hiddenAssistantModels.insert(model.id)
            saveHiddenModels()
        }
        saveRegistry()
    }

    func isSharedModelAvailable(id: String) -> Bool {
        sharedModels.contains { $0.id == id }
    }

    /// Restore a hidden shared reference without copying or downloading weights.
    @discardableResult
    func restoreSharedModel(id: String) -> Bool {
        if installedModel(id: id) != nil { return true }
        guard let model = sharedModels.first(where: { $0.id == id }), hasConfiguration(model) else { return false }
        hiddenAssistantModels.remove(id)
        saveHiddenModels()
        installed.append(model)
        installed.sort { $0.addedAt > $1.addedAt }
        saveRegistry()
        return true
    }

    var totalDiskUsage: Int64 {
        installed.reduce(0) { $0 + $1.sizeBytes }
    }

    private func loadRegistry() {
        guard let data = try? Data(contentsOf: registryURL),
              let models = try? JSONDecoder().decode([InstalledModel].self, from: data)
        else {
            return
        }
        installed = models
    }

    private func saveRegistry() {
        guard let data = try? JSONEncoder().encode(installed) else { return }
        try? data.write(to: registryURL, options: .atomic)
    }

    private var hiddenModelsURL: URL { modelsDirectory.appendingPathComponent("HiddenAssistantModels.json") }

    private func saveHiddenModels() {
        guard let data = try? JSONEncoder().encode(hiddenAssistantModels.sorted()) else { return }
        try? data.write(to: hiddenModelsURL, options: .atomic)
    }

    /// Pure directory scan, safe off the main actor. Only directories holding
    /// a complete snapshot (MLX or GGUF — the same check `hasConfiguration`
    /// uses) count as installed; half-downloaded models must surface as
    /// downloads, not as loadable models.
    nonisolated static func scanFromDisk(
        modelsDirectory baseURL: URL?, catalog: [CatalogModel] = ModelCatalog.all
    ) -> [InstalledModel] {
        guard let baseURL,
              let names = try? FileManager.default.contentsOfDirectory(atPath: baseURL.path)
        else { return [] }
        return names.compactMap { name -> InstalledModel? in
            guard let catalog = catalog.first(where: { $0.id == name }) else { return nil }
            let dir = baseURL.appendingPathComponent(name, isDirectory: true)
            guard let dirNames = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
                  (isCompleteSnapshot(dirNames: dirNames) || isCompleteCoreAIPack(at: dir))
            else { return nil }
            if catalog.format == .qwenStreaming, (try? QwenStreamArtifact.inspect(dir)) == nil { return nil }
            let size = (try? sizeOfDirectory(dir)) ?? catalog.diskBytes
            return InstalledModel(
                id: name, repo: catalog.repo, addedAt: Date(), sizeBytes: size,
                basePath: baseURL.path)
        }
    }

    /// Re-syncs the registry with what's actually on disk: discovers models
    /// copied/imported outside the app (or registered by an interrupted
    /// import) and drops entries whose directories vanished. Existing entries
    /// keep their `addedAt`; discoveries in the managed folder get
    /// `basePath: nil` so uninstall deletes their files like any download.
    /// Called when the Model Manager appears — cheap (directory listings,
    /// sizing off-main), and it keeps the UI honest after external changes.
    func rescanFromDisk() {
        guard scanTask == nil else { return }
        let base = modelsBaseURL
        let assistantRoot = assistantSupportDirectory
        // Fixtures never repair or read the user's Companion catalog.
        let users = overrideModelsDir == nil ? ModelCatalog.loadUserModels()
            : AssistantModelLibrary.readJSON([CatalogModel].self,
                at: base.deletingLastPathComponent().appendingPathComponent("UserModels.json")) ?? []
        let catalog = ModelCatalog.bundled + users
        let repairOwnMetadata = overrideModelsDir == nil
        scanTask = Task { @MainActor [weak self] in
            let (scanned, shared) = await Task.detached(priority: .utility) {
                let scanned = Self.scanFromDisk(modelsDirectory: base, catalog: catalog)
                let shared = assistantRoot.map { AssistantModelLibrary.scan(supportDirectory: $0, catalog: catalog) }
                    ?? AssistantModelLibrary.Snapshot(catalog: [], installed: [])
                if repairOwnMetadata { Self.refreshImportedGGUFMetadata(modelsDirectory: base) }
                return (scanned, shared)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.scanTask = nil
            self.sharedModels = shared.installed
            let catalogChanged = ModelCatalog.updateAssistantModels(shared.catalog)
            var updated = self.installed.filter { model in
                if model.isSharedFromAssistant { return false }
                if model.directoryBookmark != nil { return true }
                return self.fileManager.fileExists(atPath: self.directory(for: model).path)
                    && self.hasConfiguration(model)
            }
            // Companion-owned models win duplicate IDs. Shared paths are
            // refreshed so an Assistant import can move without a stale link.
            for var found in scanned + shared.installed where !updated.contains(where: { $0.id == found.id }) {
                if found.isSharedFromAssistant && self.hiddenAssistantModels.contains(found.id) { continue }
                if found.basePath == base.path { found.basePath = nil }
                if let previous = self.installed.first(where: { $0.id == found.id }) { found.addedAt = previous.addedAt }
                updated.append(found)
            }
            updated.sort { $0.addedAt > $1.addedAt }
            if updated != self.installed {
                self.installed = updated
                self.saveRegistry()
            } else if catalogChanged {
                self.objectWillChange.send()
            }
        }
    }

    /// Awaitable discovery for launch restore, download deduplication and fixtures.
    func refreshFromDisk() async {
        rescanFromDisk()
        await scanTask?.value
    }

    /// One-time metadata repair for GGUF models imported before header
    /// sniffing existed: their user-catalog entries carry the 8_192
    /// contextWindow placeholder and a generic "GGUF" family. Reads each
    /// such entry's .gguf header (managed dir only, off-main, 4 MB max) and
    /// rewrites UserModels.json with the real values. Entries already holding
    /// a sniffed context length are skipped, so this stays cheap.
    nonisolated static func refreshImportedGGUFMetadata(modelsDirectory base: URL) {
        var users = ModelCatalog.loadUserModels()
        var changed = false
        for index in users.indices {
            guard users[index].format == .gguf, users[index].contextWindow == 8_192 else { continue }
            let dir = base.appendingPathComponent(users[index].id, isDirectory: true)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
                  let ggufName = names.first(where: { $0.lowercased().hasSuffix(".gguf") }),
                  let sniffed = GGUFMetadata.read(from: dir.appendingPathComponent(ggufName))
            else { continue }  // missing/unreadable header: keep the old values
            if let contextLength = sniffed.contextLength, contextLength != users[index].contextWindow {
                users[index].contextWindow = contextLength
                changed = true
            }
            if users[index].family == "GGUF", let architecture = sniffed.architecture {
                users[index].family = architecture.capitalized
                changed = true
            }
        }
        if changed { ModelCatalog.saveUserModels(users) }
    }

    nonisolated static func sizeOfDirectory(_ url: URL) throws -> Int64 {
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        while let item = enumerator?.nextObject() as? URL {
            let values = try item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true, let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    nonisolated func directorySize(_ url: URL) throws -> Int64 {
        try Self.sizeOfDirectory(url)
    }
}
