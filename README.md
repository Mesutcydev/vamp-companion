# Vamp Companion

A small macOS host for the **existing Vamp Assistant iPhone and iPad app**.
Run local models on your Mac, connect API providers, and control assistant
sessions from iOS. The Mac window contains only **Models, Devices, and Settings**.

[Download Vamp Companion](https://github.com/Mesutcydev/vamp-companion/releases/latest) ·
[Companion site](https://thevamp.app/companion/) ·
[Existing iOS source](https://github.com/Mesutcydev/vamp-assistant)

## Install and pair

Requires an Apple Silicon Mac with macOS 15 or later. The public iOS download
is not available yet; an existing sideloaded Vamp Assistant iOS build can pair
with the companion.

1. Download the notarized ZIP, unzip it, and move **Vamp Companion.app** to Applications.
2. In Models, use a model already downloaded in Vamp Assistant, or download or
   import a supported model. For API-backed models, open
   Settings → Manage API providers and accounts.
3. In Devices, enable iPhone access. Allow local Wi-Fi only on a trusted private
   network, or connect both devices to Tailscale.
4. In the existing Vamp Assistant iOS app, scan the pairing code or enter the
   address and code shown by the companion. App Stream 1.0 build 12 also
   accepts Companion QR codes through **Scan Mac QR Code** on its home screen.
   Confirm the filled address and code, then tap **Pair Mac**. In Devices, choose
   **Local Wi-Fi** on the same network, or **Tailscale** for remote access with
   both devices connected to your private tailnet. The App Store edition supports
   both. Companion can show separate Local Wi-Fi and Tailscale QR links
   when both are available; switching the displayed link keeps existing sessions
   and network permissions intact. App Stream build 12 supports both network
   options in both editions; older Stream builds may need
   the full private address including `:9675` entered manually.

The unchanged iOS app retains sessions, live responses, stop, approvals, tools,
bots, terminal, and permission-gated clipboard/file exchange and Mac control.
API credentials can be configured from either device. Remote unlock remains
limited to Tailscale. The Mac must remain running and reachable.

The updated Assistant iOS client can retain both Wi-Fi and Tailscale routes
for the same pairing. Existing Wi-Fi pairings learn the VPN address when both
apps are updated and reachable with Tailscale connected. They can then reconnect
outside Wi-Fi without another scan. See [private-network reconnection](docs/PRIVATE-NETWORK-RECONNECTION.md).

Closing the window keeps downloads and the remote host running. Use the menu
bar item to reopen Models, Devices, or Settings. Launch at login is optional and
off by default. Quit stops the companion and its registered child processes.

## Independent from Vamp Assistant

Companion's Mac interface uses the Vamp screen-and-fangs mark, a distinct app
icon, dark arcade panels, condensed display type, and a restrained red signal. The reusable
[brand kit](brandkit/index.html) includes vector assets and design tokens. The
Mac icon is generated only into the separate Companion asset catalog; inherited
iOS and Assistant assets are unchanged.

This is an independent copy of the current working Vamp Assistant source.
The original Mac and iOS checkouts remain untouched. This isolated copy also
contains the user-authorized iOS Companion hub and a compact live homepage.
The homepage shows host and model state, active work, quick starts, and recent
conversations. The chat adds clear user turns, compact tool activity, code copy,
and restrained motion based on the user-provided SiteAgent reference. The
composer and shared controls preserve their current design.
The client retains its bundle identity, current assets, model identifiers, and protocol. The companion uses
`com.beetcode.companion`, Application Support/VampCompanion, separate Keychain
services and preferences, separate ChatGPT account storage, remote port 9675
(with fallback), and its own Git
checkpoint namespace. Model weights are shared through read-only references;
other Assistant data remains independent.

Companion automatically discovers complete models in Assistant's model library,
including imported MLX/GGUF models and registered external models. It uses the
same files without copying or downloading them again. The library refreshes
when Models opens, when the app becomes active, and every 30 seconds while
Companion runs. A new download checks for an available Assistant copy first.
Shared models are labeled **Shared with Vamp Assistant**. **Hide from Companion**
removes only Companion's reference; **Use shared model** in Discover restores it.
Assistant's model files and catalog are never modified. New Companion downloads
and ordinary imports still use its own managed library.

Ordinary model imports copy files into the companion's managed library.
Externally referenced Qwen streaming artifacts stay in place; removal only
forgets their registration. No model weights or credentials are bundled.

Local MLX, GGUF, model import/download logic, inference safeguards, and provider
versions are inherited from Vamp Assistant. Model IDs and remote protocol
version 1 remain compatible with the existing iOS app.

## Build and test

Install XcodeGen and a full Xcode installation with Swift 6.

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project BeetCode.xcodeproj -scheme VampCompanion \
  -destination 'platform=macOS' -derivedDataPath .derived \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM="" ENABLE_HARDENED_RUNTIME=NO test
```

The committed `Package.resolved` preserves the inherited dependency revisions.
The internal Mac module remains `BeetCode` so the inherited backend tests and
interfaces can stay intact. The preserved `BeetCodeRemoteIOS` scheme is available
for iOS regression tests and the Companion hub UI checks. See
[the iOS design scope](docs/IOS-COMPANION-DESIGN.md).
Local UI testing requires a signed test runner; the command above uses ad hoc
signing. Public releases always use Developer ID and hardened runtime.

## Public releases

See [the companion release process](docs/COMPANION-RELEASE.md). Downloads and
Sparkle updates are published only to `Mesutcydev/vamp-companion`. The private
update-signing key stays in Keychain under the `vamp-companion` account.

## License and provenance

MIT, derived from [Vamp Assistant](https://github.com/Mesutcydev/vamp-assistant).
The original copyright and third-party dependency notices are retained.
Historical architecture and release documents under docs describe the source
application; current companion behavior is documented here.
