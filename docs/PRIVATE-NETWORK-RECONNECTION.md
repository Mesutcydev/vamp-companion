# Wi-Fi and Tailscale reconnection

Vamp Companion 0.1.5 (9) advertises its trusted Wi-Fi and active Tailscale
IPv4 routes after pairing and in authenticated status responses. The updated
Assistant iOS client saves those routes under the existing paired computer;
it retains the computer ID, token, sessions, and drafts.

For an existing Wi-Fi pairing, update both apps, connect both devices to the
same private Tailscale network, and open iOS once while the Mac is still
reachable on Wi-Fi. The client learns the Tailscale address without another
QR scan. Afterwards, opening the app outside Wi-Fi reconnects through
Tailscale. If Tailscale was never reachable or advertised while the phone
could reach the Mac, the client must first learn that address on Wi-Fi or
pair using the Mac's Tailscale QR code.

The client probes the last successful route first, then remembered private
alternatives with bounded three-second status requests. It refreshes on
foreground entry and network changes, and continues retrying after an
offline launch. A route switch replaces the selected conversation's stream
and the visible Mac-control video/audio transport. It never replays sends,
approvals, terminal input, or other mutations.

Alternate routes must use numeric RFC1918 or Tailscale CGNAT IPv4 addresses,
the same paired port, HTTP root paths, and no credentials, query, or fragment.
Responses must authenticate using the original bearer token and match the
saved Mac UUID. Redirects remain disabled. Public access and LAN permissions
are unchanged; remote unlock remains restricted to Tailscale peers.

The Mac keeps its all-interface listener and pairing code when only advertised
routes change. Protocol version 1, routes, model identifiers, and existing
response fields remain intact; older hosts and clients can omit or ignore the
new optional `hostID` and `connectionEndpoints` fields.

Deterministic URLProtocol tests cover first Wi-Fi pairing, Tailscale fallback,
existing-profile migration/relaunch, return to allowed Wi-Fi, revocation,
reused LAN addresses, identity mismatches, unsafe endpoints, and selected
conversation stream/draft continuity. Native UI checks protect the homepage
and composer. A physical iPhone outside the LAN remains a separate live
verification; simulator routing tests do not establish that result.
