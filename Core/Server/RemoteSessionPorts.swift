import Foundation

/// Separate listener range for coexistence with Vamp Host and Vamp Assistant.
enum RemoteSessionPorts {
    static let defaultPort = 9675
    static let reservedForeignPorts: Set<Int> = Set([9471, 9472, 9473, 9475]).union(9575...9583)

    static func resolved(_ requested: Int) -> Int {
        if requested <= 0 || requested > 65_535 || reservedForeignPorts.contains(requested) {
            return defaultPort
        }
        return requested
    }

    /// Ports to try, in order, for a requested port.
    ///
    /// 0 means "any free port" and is returned as-is so the OS assigns one. `resolved` keeps
    /// mapping 0 to `defaultPort`, which is right for a stored user preference that is unset —
    /// but wrong for a caller that explicitly asked for an ephemeral port and reads `actualPort`
    /// back. Routing 0 through the Beet ladder made those callers land on 9575 and collide with
    /// a running Vamp Assistant, surfacing as an opaque `bindFailed(48)`.
    static func candidates(preferred: Int) -> [Int] {
        guard preferred != 0 else { return [0] }
        let start = resolved(preferred)
        var ports = [start]
        for offset in 1...8 {
            let next = start + offset
            guard next <= 65_535 else { break }
            if !reservedForeignPorts.contains(next) {
                ports.append(next)
            }
        }
        return ports
    }
}
