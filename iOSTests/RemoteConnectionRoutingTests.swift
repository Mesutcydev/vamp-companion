import Foundation
import Synchronization
import XCTest
@testable import BeetCodeRemoteIOS

@MainActor
final class RemoteConnectionRoutingTests: XCTestCase {
    nonisolated private static let lan = URL(string: "http://192.168.1.20:9675/")!
    nonisolated private static let tail = URL(string: "http://100.90.4.3:9675/")!
    nonisolated private static let hostID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func makeStore(_ computer: PairedBeetCodeComputer?,
                           handler: @escaping RemoteStubProtocol.Handler) -> (RemoteStore, MemoryConnectionStorage, URLSession) {
        RemoteStubProtocol.handler.withLock { $0 = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RemoteStubProtocol.self]
        let session = URLSession(configuration: configuration)
        let storage = MemoryConnectionStorage(computer.map { [$0] } ?? [])
        return (RemoteStore(connectionStorage: storage, apiSession: session,
            observesNotifications: false, drafts: RemoteDraftStore(directory: nil)), storage, session)
    }

    private func computer(url: URL? = nil, routes: Bool = true) -> PairedBeetCodeComputer {
        var computer = PairedBeetCodeComputer(name: "Paired Mac", baseURL: url ?? Self.lan)
        computer.hostID = Self.hostID
        if routes { computer.connectionEndpoints = [
            .init(url: Self.lan, networkKind: "localNetwork"),
            .init(url: Self.tail, networkKind: "tailscale")]
        }
        return computer
    }

    nonisolated private static func status(kind: String, hostID: UUID? = nil, routes: Bool = true) -> Data {
        let endpoints: [[String: String]] = routes ? [
            ["url": lan.absoluteString, "networkKind": "localNetwork"],
            ["url": tail.absoluteString, "networkKind": "tailscale"]] : []
        return json(["protocolVersion": 1, "hostID": (hostID ?? Self.hostID).uuidString,
            "connectionEndpoints": endpoints, "pairedClients": 1, "networkKind": kind,
            "tokenExpiresAt": 2_100_000_000, "isRunning": false, "phase": "idle", "queuedTasks": 0])
    }

    nonisolated private static func json(_ body: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: body)
    }

    private func finish(_ store: RemoteStore, _ session: URLSession) {
        // Removing an active Mac deliberately reconnects to the next saved
        // one. Clear every fixture profile before invalidating its transport.
        for computer in store.pairedComputers where computer.id != store.activeComputerID {
            store.removeComputer(computer.id)
        }
        store.forgetSavedMac()
        session.invalidateAndCancel()
    }

    func testLegacyPairingDecodesWithoutLosingItsIdentityOrToken() throws {
        let id = UUID()
        let data = Self.json(["id": id.uuidString, "name": "Saved Mac", "baseURL": Self.lan.absoluteString])
        let saved = try JSONDecoder().decode(PairedBeetCodeComputer.self, from: data)
        XCTAssertEqual(saved.id, id)
        XCTAssertNil(saved.hostID)
        XCTAssertNil(saved.connectionEndpoints)
        let legacy = try JSONDecoder().decode(RemotePairResponse.self,
            from: Self.json(["token": "legacy", "expiresAt": 2_100_000_000]))
        XCTAssertNil(legacy.hostID)
        XCTAssertNil(legacy.connectionEndpoints)
    }

    func testWiFiPairingSwitchesToTailscaleAndKeepsConversationDraftAndToken() async throws {
        let wifi = Mutex(true), posts = Mutex(0)
        let conversationID = UUID()
        let streamReconnected = expectation(description: "selected conversation stream reconnects on Tailscale")
        streamReconnected.assertForOverFulfill = false
        let (store, storage, session) = makeStore(nil) { request in
            let isLAN = request.url?.host == "192.168.1.20"
            if isLAN && !wifi.withLock({ $0 }) { throw URLError(.networkConnectionLost) }
            if request.httpMethod == "POST" {
                posts.withLock { $0 += 1 }
                XCTAssertEqual(request.url?.path, "/api/pair")
                return (200, Self.json(["token": "fresh-pair-token", "expiresAt": 2_100_000_000,
                    "hostID": Self.hostID.uuidString, "connectionEndpoints": [
                        ["url": Self.lan.absoluteString, "networkKind": "localNetwork"],
                        ["url": Self.tail.absoluteString, "networkKind": "tailscale"]]]))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh-pair-token")
            switch request.url?.path {
            case "/api/status":
                XCTAssertEqual(request.timeoutInterval, 3, "An unreachable old Wi-Fi route must have a bounded probe")
                return (200, Self.status(kind: isLAN ? "localNetwork" : "tailscale"))
            case "/api/sessions": return (200, Self.json(["sessions": [["id": conversationID.uuidString,
                "title": "Keep working", "workspace": "Chat", "modelID": "local|qwen", "messageCount": 0,
                "updatedAt": 1, "isRunning": false, "phase": "idle"]]]))
            case "/api/sessions/\(conversationID)": return (200, RemoteStoreConcurrencyTests.detail(conversationID))
            case "/api/sessions/\(conversationID)/events":
                if !isLAN { streamReconnected.fulfill() }
                return (404, Self.json(["error": "No continuous stream in the isolated test"]))
            default: return (200, Self.json(["runs": []]))
            }
        }
        defer { finish(store, session) }
        let paired = await store.connect(address: Self.lan.absoluteString, code: "123456")
        XCTAssertTrue(paired)
        let id = try XCTUnwrap(store.activeComputerID)
        await store.select(sessionID: conversationID)
        store[draftFor: conversationID] = "Keep this draft."
        wifi.withLock { $0 = false }
        try await store.refresh()
        await fulfillment(of: [streamReconnected], timeout: 3)
        XCTAssertTrue(store.isConnected)
        XCTAssertEqual(store.baseURL, Self.tail)
        XCTAssertEqual(store.activeComputerID, id)
        XCTAssertEqual(store.activeComputer?.networkKind, "tailscale")
        XCTAssertEqual(store.selectedSession?.id, conversationID)
        XCTAssertEqual(store[draftFor: conversationID], "Keep this draft.")
        XCTAssertEqual(storage.token(for: id), "fresh-pair-token")
        XCTAssertEqual(posts.withLock { $0 }, 1, "Changing routes must not pair again or replay a mutation")
    }

    func testExistingWiFiPairingLearnsRoutesAndRestoresOutsideWiFi() async throws {
        let wifi = Mutex(true)
        var saved = computer(routes: false)
        saved.hostID = nil
        let (store, storage, session) = makeStore(saved) { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let isLAN = request.url?.host == "192.168.1.20"
            if isLAN && !wifi.withLock({ $0 }) { throw URLError(.cannotConnectToHost) }
            if request.url?.path == "/api/status" { return (200, Self.status(kind: isLAN ? "localNetwork" : "tailscale")) }
            if request.url?.path == "/api/sessions" { return (200, Self.json(["sessions": []])) }
            return (200, Self.json(["runs": []]))
        }
        defer { finish(store, session) }
        try await store.refresh()
        XCTAssertEqual(storage.computers.first?.connectionEndpoints?.count, 2)
        wifi.withLock { $0 = false }
        let relaunched = RemoteStore(connectionStorage: storage, apiSession: session,
            observesNotifications: false, drafts: RemoteDraftStore(directory: nil))
        await relaunched.restore()
        XCTAssertTrue(relaunched.isConnected)
        XCTAssertEqual(relaunched.baseURL, Self.tail)
        XCTAssertEqual(relaunched.activeComputerID, saved.id)
        XCTAssertEqual(storage.token(for: saved.id), "test-token")
        relaunched.forgetSavedMac()
    }

    func testTailscaleOutageFallsBackToAllowedWiFiAndKeepsTheVPNRoute() async throws {
        let (store, _, session) = makeStore(computer(url: Self.tail)) { request in
            if request.url?.host == "100.90.4.3" { throw URLError(.timedOut) }
            if request.url?.path == "/api/status" { return (200, Self.status(kind: "localNetwork", routes: false)) }
            if request.url?.path == "/api/sessions" { return (200, Self.json(["sessions": []])) }
            return (200, Self.json(["runs": []]))
        }
        defer { finish(store, session) }
        await store.connectSaved()
        XCTAssertTrue(store.isConnected)
        XCTAssertEqual(store.baseURL, Self.lan)
        XCTAssertEqual(store.activeComputer?.networkKind, "localNetwork")
        XCTAssertTrue(store.activeComputer?.connectionEndpoints?.contains(where: { $0.url == Self.tail }) == true)
    }

    func testAnotherMacAtTheOldWiFiAddressCannotInvalidateThePairing() async throws {
        let (store, _, session) = makeStore(computer()) { request in
            if request.url?.host == "192.168.1.20" { return (401, Self.json(["error": "Different Mac"])) }
            if request.url?.path == "/api/status" { return (200, Self.status(kind: "tailscale")) }
            if request.url?.path == "/api/sessions" { return (200, Self.json(["sessions": []])) }
            return (200, Self.json(["runs": []]))
        }
        defer { finish(store, session) }
        await store.connectSaved()
        XCTAssertTrue(store.isConnected)
        XCTAssertFalse(store.requiresPairing)
        XCTAssertEqual(store.baseURL, Self.tail)
    }

    func testRevokedTokenOnAllRoutesRequiresPairing() async {
        let (store, _, session) = makeStore(computer()) { _ in
            (401, Self.json(["error": "Access revoked"]))
        }
        defer { finish(store, session) }
        await store.connectSaved()
        XCTAssertTrue(store.requiresPairing)
        XCTAssertFalse(store.isConnected)
    }

    func testAlternateRouteMustMatchThePairedHostIdentity() async {
        let (store, _, session) = makeStore(computer()) { request in
            if request.url?.host == "192.168.1.20" { throw URLError(.cannotConnectToHost) }
            XCTAssertEqual(request.url?.path, "/api/status", "Do not fetch conversations from an unrecognized host")
            return (200, Self.status(kind: "tailscale", hostID: UUID()))
        }
        defer { finish(store, session) }
        await store.connectSaved()
        XCTAssertFalse(store.isConnected)
        XCTAssertFalse(store.requiresPairing)
        XCTAssertEqual(store.baseURL, Self.lan)
    }

    func testSwitchingComputerCancelsAnOldTailscaleProbe() async throws {
        let probing = expectation(description: "old computer's Tailscale probe started")
        let (_, storage, session) = makeStore(computer()) { request in
            if request.url?.host == "192.168.1.20" { throw URLError(.cannotConnectToHost) }
            if request.url?.host == "100.90.4.3" {
                probing.fulfill()
                try await Task.sleep(for: .milliseconds(200))
                return (200, Self.status(kind: "tailscale"))
            }
            if request.url?.path == "/api/status" { return (200, RemoteStoreConcurrencyTests.status(2_100_000_000)) }
            if request.url?.path == "/api/sessions" { return (200, Self.json(["sessions": []])) }
            return (200, Self.json(["runs": []]))
        }
        var second = PairedBeetCodeComputer(name: "Other Mac", baseURL: URL(string: "http://192.168.1.30:9675/")!)
        second.networkKind = "localNetwork"
        storage.computers.append(second)
        storage.tokens[second.id] = "other-token"
        // Reload the in-memory profile list as an actual app launch would.
        let restored = RemoteStore(connectionStorage: storage, apiSession: session,
            observesNotifications: false, drafts: RemoteDraftStore(directory: nil))
        let originalID = storage.computers[0].id
        defer { restored.removeComputer(originalID); finish(restored, session) }
        let old = Task { try? await restored.refresh() }
        await fulfillment(of: [probing], timeout: 2)
        await restored.switchComputer(to: second.id)
        await old.value
        XCTAssertEqual(restored.activeComputerID, second.id)
        XCTAssertEqual(restored.baseURL, second.baseURL)
        XCTAssertTrue(restored.isConnected)
        XCTAssertEqual(storage.token(for: second.id), "other-token")
    }

    func testAdvertisedRoutesRejectPublicAddressesCredentialsPathsAndDifferentPorts() {
        let bad = ["http://8.8.8.8:9675/", "http://127.0.0.1:9675/", "http://192.168.1.20:9575/",
            "http://user@100.90.4.3:9675/", "http://100.90.4.3:9675/?pair=123456",
            "http://100.90.4.3:9675/api/", "https://100.90.4.3:9675/", "http://100.90.4.999:9675/",
            "http://192.168.1.20:9675/#redirect", "http://somehost.local:9675/"]
        for value in bad {
            let endpoint = RemoteConnectionEndpoint(url: URL(string: value)!, networkKind: "tailscale")
            XCTAssertNil(endpoint.validated(relativeTo: Self.lan), value)
        }
        XCTAssertNotNil(RemoteConnectionEndpoint(url: Self.tail, networkKind: "tailscale").validated(relativeTo: Self.lan))
        XCTAssertNotNil(RemoteConnectionEndpoint(url: Self.lan, networkKind: "localNetwork").validated(relativeTo: Self.lan))
        XCTAssertNil(RemoteConnectionEndpoint(url: Self.lan, networkKind: "tailscale").validated(relativeTo: Self.lan))
    }
}
