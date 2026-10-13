import Foundation

/// Alternate routes are learned only from a successfully paired/authenticated
/// Mac. They never contain a pairing code, and cannot change the host's port.
struct RemoteConnectionEndpoint: Codable, Equatable, Sendable {
    let url: URL
    let networkKind: String

    func validated(relativeTo pairedURL: URL) -> RemoteConnectionEndpoint? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "http", pairedURL.scheme == "http",
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              let port = parts.port, port == pairedURL.port, (1...65535).contains(port),
              let host = parts.host, let kind = Self.networkKind(for: host),
              kind == networkKind else { return nil }
        var normalized = parts
        normalized.path = "/"
        guard let url = normalized.url else { return nil }
        return Self(url: url, networkKind: kind)
    }

    static func networkKind(for host: String) -> String? {
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              components.allSatisfy({ $0 == "0" || !$0.hasPrefix("0") }) else { return nil }
        let parts = components.compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return nil }
        if parts[0] == 100 && (64...127).contains(parts[1]) { return "tailscale" }
        if parts[0] == 10 || parts[0] == 192 && parts[1] == 168
            || parts[0] == 172 && (16...31).contains(parts[1]) { return "localNetwork" }
        return nil
    }
}
