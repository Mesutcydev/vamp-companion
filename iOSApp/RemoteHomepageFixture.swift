#if DEBUG
import SwiftUI
import Foundation

/// QA only: a canned loopback host, intercepted by the API URLSession.
/// Credentials and drafts never use real connection storage.
struct RemoteHomepageFixture: View {
    @State private var store = makeStore()
    @State private var selectedSession = ""
    private var state: String { ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] ?? "ready" }

    var body: some View {
        NavigationStack {
            SessionListView(store: store) { selectedSession = $0.uuidString }
                .overlay(alignment: .bottom) {
                    if !selectedSession.isEmpty {
                        Text("Opened conversation \(selectedSession)").accessibilityIdentifier("remote.home.fixture-opened")
                    }
                }
        }
        .task {
            if state == "offline" { store.sessions = RemoteHomepageProtocol.sessions() }
            else { try? await store.refresh(); await store.loadStartModels() }
        }
    }

    @MainActor private static func makeStore() -> RemoteStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteHomepageProtocol.self]
        return RemoteStore(connectionStorage: RemoteHomepageStorage(),
            apiSession: URLSession(configuration: configuration), observesNotifications: false,
            drafts: RemoteDraftStore(directory: nil))
    }
}

@MainActor private final class RemoteHomepageStorage: RemoteConnectionPersisting {
    private let computer = PairedBeetCodeComputer(name: "Studio Mac", baseURL: URL(string: "http://127.0.0.1:65500")!, networkKind: "tailscale")
    func load() -> (computers: [PairedBeetCodeComputer], activeID: UUID?) { ([computer], computer.id) }
    func save(computers: [PairedBeetCodeComputer], activeID: UUID?) {}
    func token(for computerID: UUID) -> String? { "homepage-fixture" }
    func saveToken(_ token: String, for computerID: UUID) throws {}
    func clearToken(for computerID: UUID) {}
}

private final class RemoteHomepageProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    private static var working: Bool { ["working", "busy"].contains(ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] ?? "") }
    private static var empty: Bool { ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] == "empty" }

    static func sessions() -> [RemoteSessionSummary] {
        guard !empty else { return [] }
        let now = Date.now.timeIntervalSince1970
        var result = [
            RemoteSessionSummary(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, title: "A calmer workspace", workspace: "Personal", workspacePath: nil, mode: "chat", messageCount: 8, updatedAt: now - 120, isRunning: working, phase: working ? "thinking" : "idle", queueState: nil),
            RemoteSessionSummary(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, title: "Ideas for the weekend", workspace: "Chat", workspacePath: nil, mode: "chat", messageCount: 5, updatedAt: now - 3600, isRunning: false, phase: "idle", queueState: nil)
        ]
        if ProcessInfo.processInfo.environment["VAMP_REMOTE_FIXTURE"] == "busy" {
            result.append(RemoteSessionSummary(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, title: "Review the release", workspace: "Project", workspacePath: nil, mode: "chat", messageCount: 4, updatedAt: now - 60, isRunning: true, phase: "thinking", queueState: nil))
            result.append(RemoteSessionSummary(id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!, title: "Review queued changes", workspace: "Project", workspacePath: nil, mode: "chat", messageCount: 1, updatedAt: now - 30, isRunning: false, phase: "queued", queueState: "queued"))
        }
        return result
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let payload: [String: Any]
        switch path {
        case "/api/status":
            payload = ["protocolVersion": 1, "pairedClients": 1, "networkKind": "tailscale", "isRunning": Self.working, "phase": Self.working ? "thinking" : "idle", "queuedTasks": Self.working ? 1 : 0]
        case "/api/sessions":
            payload = ["sessions": Self.sessions().map { session in
                var entry = ["id": session.id.uuidString, "title": session.title, "workspace": session.workspace, "mode": "chat", "messageCount": session.messageCount, "updatedAt": session.updatedAt, "isRunning": session.isRunning, "phase": session.phase] as [String: Any]
                if let queueState = session.queueState { entry["queueState"] = queueState }
                return entry
            }]
        case "/api/models":
            payload = ["models": [["id": "local|fixture", "name": "Qwen3.5 9B", "source": "local", "detail": "Downloaded on Mac · MLX"]], "loadedLocalModel": ["id": "local|fixture", "name": "Qwen3.5 9B", "canUnload": true]]
        case "/api/workspaces": payload = ["workspaces": []]
        case "/api/bot-computers": payload = ["computers": []]
        default: payload = ["error": "This is an isolated homepage fixture"]
        }
        guard let url = request.url, let data = try? JSONSerialization.data(withJSONObject: payload),
              let response = HTTPURLResponse(url: url, statusCode: payload["error"] == nil ? 200 : 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
