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
2. In Models, download or import a supported model. For API-backed models, open
   Settings → Manage API providers and accounts.
3. In Devices, enable iPhone access. Allow local Wi-Fi only on a trusted private
   network, or connect both devices to Tailscale.
4. In the existing Vamp Assistant iOS app, scan the pairing code or enter the
   address and code shown by the companion. App Stream 1.0 build 9 also
   accepts Companion QR codes for app streaming on the same Wi-Fi or Ethernet
   network in its App Store edition; older Stream builds need
   the full private address including `:9675` entered manually.

The unchanged iOS app retains sessions, live responses, stop, approvals, tools,
bots, terminal, and permission-gated clipboard/file exchange and Mac control.
API credentials can be configured from either device. Remote unlock remains
limited to Tailscale. The Mac must remain running and reachable.

Closing the window keeps downloads and the remote host running. Use the menu
bar item to reopen Models, Devices, or Settings. Launch at login is optional and
off by default. Quit stops the companion and its registered child processes.

## Independent from Vamp Assistant

This is an independent copy of the current working Vamp Assistant source.
The original Mac and iOS applications are unchanged. The companion uses
`com.beetcode.companion`, Application Support/VampCompanion, separate Keychain
services and preferences, separate ChatGPT account storage, remote port 9675
(with fallback), and its own Git
checkpoint namespace. It does not migrate or discover the original app's data.

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
for unchanged iOS regression tests; this project publishes only the Mac companion.
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
