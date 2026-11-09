#if DEBUG
import SwiftUI
import Foundation
import Synchronization
import UIKit

/// Secondary-page QA uses an intercepted loopback session and in-memory
/// pairing. It cannot contact a real Mac or execute a mutation.
struct RemoteSecondaryPageFixture: View {
    @State private var store = makeStore()
    @State private var modelID = "local|fixture"
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var releasedFixtureResponse = false
    // The real app has host status before New chat is reachable; match that.
    @State private var statusLoaded = ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] != "store-edition"
    private var delaysMutation: Bool { ProcessInfo.processInfo.environment["VAMP_SECONDARY_DELAY_MUTATION"] == "1" }
    private var screen: String { ProcessInfo.processInfo.environment["VAMP_REMOTE_TEST_SCREEN"] ?? "" }

    var body: some View {
        Group { if statusLoaded { page } else { ProgressView() } }
            .transaction { transaction in
                if delaysMutation { transaction.disablesAnimations = true }
            }
            // Mid-leading, clear of the bottom composer and the toolbar.
            .overlay(alignment: .leading) {
                if delaysMutation && !releasedFixtureResponse {
                    Button {
                        RemoteSecondaryPageProtocol.releaseMutationResponse()
                        releasedFixtureResponse = true
                    } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.white).background(.gray, in: RoundedRectangle(cornerRadius: 12))
                    .padding(12).accessibilityLabel("Reject fixture request")
                    .accessibilityIdentifier("remote.fixture.rejectMutation")
                }
            }
            .environment(\.dynamicTypeSize,
                ProcessInfo.processInfo.environment["VAMP_SECONDARY_LARGE_TEXT"] == "1" ? .accessibility3 : typeSize)
            .task {
                guard ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] != "offline" else { return }
                try? await store.refresh()
                statusLoaded = true
                await store.loadStartModels()
            }
    }

    @ViewBuilder private var page: some View {
        switch screen {
        case "secondary-settings":
            RemoteSettingsSheet(store: store, onSwitchComputer: {}, onDiagnostics: {})
        case "secondary-share": RemoteShareSheet(store: store)
        case "secondary-new-session": StartSessionSheet(store: store, initialBotID: "") { _ in }
        case "secondary-computers": ComputerSwitcherSheet(store: store)
        case "secondary-bots": RemoteBotsView(store: store) { _ in }
        case "secondary-bot-detail":
            NavigationStack {
                RemoteBotDetailView(store: store, profile: .profile(id: "builder"), selectedModelID: $modelID) { _ in }
            }.remotePageErrors(store: store)
        case "secondary-providers": NavigationStack { RemoteProvidersView(store: store) }
        case "secondary-console":
            RemoteBotConsoleView(store: store, computer: .init(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!, profileID: "builder",
                name: "Builder workspace", backend: "isolatedWorkspace", state: "running",
                workspacePath: "/workspace", browserProfilePath: "/browser", containerName: nil, updatedAt: 0))
        default: RemoteDiagnosticsView(store: store)
        }
    }

    @MainActor private static func makeStore() -> RemoteStore {
        if ProcessInfo.processInfo.environment["VAMP_SECONDARY_DELAY_MUTATION"] == "1" {
            UIView.setAnimationsEnabled(false)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteSecondaryPageProtocol.self]
        let store = RemoteStore(connectionStorage: RemoteSecondaryPageStorage(),
            apiSession: URLSession(configuration: configuration), observesNotifications: false,
            drafts: RemoteDraftStore(directory: nil))
        if ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] == "offline" {
            store.apiProviders = [.init(id: "openai", name: "OpenAI", kind: "builtIn",
                configured: true, baseURL: nil, needsMacSetup: false)]
            let cachedRun = Data("""
                {"runs":[{"id":"66666666-6666-6666-6666-666666666666","profileID":"builder","profileName":"Builder","modelID":"local|fixture","prompt":"Review an isolated fixture","state":"needsApproval","phase":"waiting for approval","latestOutput":"","createdAt":0,"updatedAt":0}]}
                """.utf8)
            store.botRuns = (try? JSONDecoder().decode(RemoteBotRunEnvelope.self, from: cachedRun))?.runs ?? []
        }
        return store
    }
}

@MainActor private final class RemoteSecondaryPageStorage: RemoteConnectionPersisting {
    private let computer = PairedBeetCodeComputer(name: "Studio Mac",
        baseURL: URL(string: "http://127.0.0.1:65501")!, networkKind: "tailscale")
    func load() -> (computers: [PairedBeetCodeComputer], activeID: UUID?) { ([computer], computer.id) }
    func save(computers: [PairedBeetCodeComputer], activeID: UUID?) {}
    func token(for computerID: UUID) -> String? { "secondary-page-fixture" }
    func saveToken(_ token: String, for computerID: UUID) throws {}
    func clearToken(for computerID: UUID) {}
}

private final class RemoteSecondaryPageProtocol: URLProtocol, @unchecked Sendable {
    private let pending = Mutex<Task<Void, Never>?>(nil)
    private static let responseReleased = Mutex(false)
    static func releaseMutationResponse() { responseReleased.withLock { $0 = true } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] == "offline" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        if request.httpMethod != "GET", ProcessInfo.processInfo.environment["VAMP_SECONDARY_DELAY_MUTATION"] == "1" {
            let task = Task.detached { @Sendable [self] in
                do {
                    while !Self.responseReleased.withLock({ $0 }) {
                        try await Task.sleep(for: .milliseconds(100))
                        try Task.checkCancellation()
                    }
                } catch { return }
                deliver(["error": "The page fixture does not execute actions"])
            }
            pending.withLock { $0 = task }
            return
        }
        var payload: [String: Any] = ["error": "The page fixture does not execute actions"]
        // The App Store Mac edition omits folders and bots and refuses those routes.
        let storeEdition = ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] == "store-edition"
        let refused = ["error": "Mac control, terminal, coding tools, ChatGPT account sign-in, and external inference runtimes are available in the website edition."]
        if request.httpMethod == "GET" {
            switch request.url?.path ?? "" {
            case "/api/status":
                payload = ["protocolVersion": 1, "pairedClients": 1, "networkKind": "tailscale", "isRunning": false, "phase": "idle", "queuedTasks": 0]
                if storeEdition { payload["capabilities"] = ["sessions", "sharing", "stream-revocation", "chat-images", "connection-routes"] }
            case "/api/sessions": payload = ["sessions": []]
            case "/api/models": payload = ["models": [
                ["id": "local|fixture", "name": "Qwen3.5 9B", "source": "local", "detail": "Downloaded on Mac · MLX"],
                ["id": "api|fixture", "name": "API model", "source": "api", "detail": "OpenAI"]]]
            case "/api/providers": payload = ["providers": [
                ["id": "anthropic", "name": "Anthropic", "kind": "builtIn", "configured": true, "needsMacSetup": false],
                ["id": "openai", "name": "OpenAI", "kind": "builtIn", "configured": false, "needsMacSetup": false]]]
            case "/api/bot-runs": payload = ["runs": []]
            case "/api/bot-computers": payload = storeEdition ? refused : ["computers": []]
            case "/api/workspaces": payload = storeEdition ? refused : ["workspaces": []]
            case "/api/files": payload = ["files": [["name": "Project notes.md", "size": 2048, "modifiedAt": 0]]]
            case "/api/clipboard": payload = ["text": "Fixture clipboard", "updatedAt": 0]
            default:
                if request.url?.path.contains("/files") == true { payload = ["path": "", "entries": []] }
            }
        }
        deliver(payload)
    }

    private func deliver(_ payload: [String: Any]) {
        guard let url = request.url, let data = try? JSONSerialization.data(withJSONObject: payload),
              let response = HTTPURLResponse(url: url, statusCode: payload["error"] == nil ? 200 : 403,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { pending.withLock { $0?.cancel(); $0 = nil } }
}
#endif
