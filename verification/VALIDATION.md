# Vamp Companion 0.1.0 validation


## App Stream Store Tailscale support — 2026-10-13

- App Stream 1.0 build 12 supports private Tailscale connections to Sync,
  Assistant, and Companion, alongside physical LAN connections. Saved peers,
  reconnects, ordinary requests, and streaming use the same network validation.
- Tailnet destinations require an active tunnel carrying a Tailscale address.
  Public destinations, unconnected tunnels, and HTTP redirects remain blocked.
  Existing pairing, TLS, and host permissions are preserved.
- DNS answers are validated and pinned to the actual request. Allowed IPv4
  answers are preferred for Assistant/Companion listener compatibility; IPv6
  remains a fallback. MagicDNS requires Tailscale DNS enabled on the client.
- All 676 current Stream backend tests and 89 iOS unit tests passed. Linux host
  tests (24) and browser tests (1) passed, and all four active app targets built.
- The production network policy accepted a live remote Tailscale IP through
  the Mac's active tunnel and rejected a public address. The Mac has Tailscale
  DNS disabled, so live MagicDNS and physical iPhone streaming were not verified.
- App Stream's signed Store archive and exported IPA retain its current artwork,
  splash, identity, and App Store distribution channel. Build 12 is available
  to the existing Internal Testers group in TestFlight.
- Companion 0.1.3 build 4 updates Devices guidance and is Developer ID signed,
  notarized, stapled, and installed. Its previous models, pairing, and hosting
  choice were restored; the separate Sync process remained on its own port.
- [Release CI](https://github.com/Mesutcydev/vamp-companion/actions/runs/38364982585)
  passed 1,134 backend tests (51 optional skips), two companion UI tests,
  the unchanged iOS suite (48 unit and 12 UI tests, five optional UI skips),
  and both Mac and iOS Release builds. One initial iOS session-teardown test
  crashed; the unchanged full iOS job passed on rerun.
- The public notarized archive was independently downloaded and verified:
  15,246,383 bytes, SHA-256
  `1fd7939dfc4958cf2853c89764b57572f8fcaea3022af6970ccdbb54701e16e8`.
  The signed feed was published only after public archive verification.
- Apple guideline 4.2.7 still specifies LAN for focused streaming clients.
  Tailscale is disclosed in review notes; internal TestFlight is not App Store
  approval. See [Apple's current rule](https://developer.apple.com/app-store/review/guidelines/#minimum-functionality).

## App Stream home scanner compatibility — 2026-10-13

- App Stream 1.0 build 10 fixes the home scanner's Sync-only QR routing.
  Companion and Assistant HTTP pairing links open their existing code-pairing
  form with the scanned address and code. Sync links retain fingerprint approval.
- All 88 current iOS unit tests passed, including the home scanner checks for
  both host port ranges, Sync links, and invalid or unrelated QR payloads.
- The installed Companion's actual Local Wi-Fi QR was decoded and accepted by
  the production App Stream parser and home scanner router. Port 9675 and the
  six-digit code were retained. The simulator's scanner entry and pairing screen
  were inspected; camera scanning requires a physical iPhone.
- The signed Store archive and exported IPA identify App Stream 1.0 build 10
  with the existing bundle ID, current icon and splash, and App Store LAN policy.
- Companion 0.1.2 build 3 remains the Mac release. Its installed signature,
  notarization staple, Gatekeeper assessment, and unchanged live signed Sparkle
  feed were verified again. This client fix does not change the Mac binary.

The independent source snapshot is commit `f1ba57e`. The original checkout was
read to create the snapshot; implementation changes were made only in this
repository. Concurrent changes in the original checkout were left intact.

## Completed

- The macOS companion Debug application builds on Apple Silicon with Xcode 27.
- The complete backend suite ran 1,132 tests: zero failures and 51 optional
  tests skipped. Optional model checks require weights or explicit fixture
  settings that are intentionally absent from fresh companion storage.
- All eight companion isolation tests passed: provider credential separation,
  checkpoint cleanup, reserved ports, disabled migrations/discovery, window
  close lifetime, managed-path confinement, external model removal, and app
  storage/update identity.
- The account integration tests passed, including a subprocess fixture proving
  that logout removes only companion authentication and preserves original
  account files. Account storage has owner-only directory permissions.
- Browser text extraction and PNG snapshots passed without an attached Mac
  window, using the retained background browser viewport.
- Remote protocol workflow tests passed over trusted LAN, including one-time
  pairing, saved-session recovery, client revocation, model selection/unload,
  bots, approvals, and permission-gated sharing. Existing network restriction
  and Tailscale policy tests remain in the backend suite.
- Download finalization, activation, pause/resume persistence, imports, agent
  execution, streaming, stop, and provider routing passed their backend checks.
- [GitHub validation with Xcode 26.6](https://github.com/Mesutcydev/vamp-companion/actions/runs/38286473235)
  passed the entire backend suite (1,132 tests, 51 skipped), both companion
  UI tests, and both Mac and iOS device Release builds.
- The unchanged iOS regression suite passed on GitHub: 48 unit tests and
  12 UI tests (five optional UI scenarios skipped), with zero failures. The
  unchanged iOS device Release configuration also built successfully.
- Native manual checks reached Models, Devices, Settings, and the compact
  provider sheet. The live companion listened on 9675 while the original app
  continued listening on its separate 9471/9473/9475 ports. The companion's
  host remained running after the close command; an unauthenticated status
  request correctly returned HTTP 401.
- The empty Models message is centered and the provider sheet keeps its
  header visible while its cards scroll. The rebuilt native UI was inspected
  in screenshots, and the updated navigation smoke test passed.
- The actual inherited parallel downloader fetched the public Qwen3 0.6B
  weights in isolated Debug and Release diagnostics. Its full SHA-256 check
  passed: `392e8d466d56100ada00eb82031fb854297fc9e389b7d303eba3af114e87bce2`.
  Native pause/resume controls were exercised. Initial live Debug attempts
  encountered transport failures; the isolated full-file reruns succeeded
  without changing backend behavior.
- The complete public model fixture imported through the native file panel.
  Its 351.4 MB snapshot was copied into companion-managed storage, retained
  the original fixture, matched its weights checksum, and loaded successfully.
- The notarized release resumed the interrupted catalog download and completed
  the full Qwen3 0.6B snapshot with its Mac window closed. All model files were
  finalized in companion storage, the weights hash matched, and the download
  manifest was removed. Reopening the window preserved its state. The downloaded
  model then loaded and explicitly unloaded through the release interface.
- Quit removed the companion's listener on 9675 while the original app remained
  running on 9475. Relaunching the notarized app restored its saved hosting
  choice on 9675, alongside the original app.
- The Developer ID archive and Apple notarization submission succeeded.
  The exported app is stapled and Gatekeeper reports `Notarized Developer ID`.
  The public ZIP extraction, release entitlements, and Sparkle archive/feed
  signatures passed their distribution checks.
- All 93 frozen iOS source, test, asset, and distribution files match the
  inherited snapshot. All inherited iOS targets and release scheme settings
  match as well. The dependency lockfile matches the original revisions.

## Distribution

- [Vamp Companion 0.1.0](https://github.com/Mesutcydev/vamp-companion/releases/tag/v0.1.0)
  publishes the notarized ZIP and its SHA-256 checksum. The public archive was
  downloaded independently and matched both the verified local ZIP and its
  Sparkle signature: 15,242,748 bytes, SHA-256
  `5559a9efec1204dae96bbf1e96c7d859dcb5dcab76975c7983fa1cd038280c5f`.
- The signed companion appcast was staged only after public archive verification.
  [GitHub Pages deployment](https://github.com/Mesutcydev/vamp-companion/actions/runs/38297193917)
  succeeded. The [download page](https://mesutcydev.github.io/vamp-companion/)
  and [signed feed](https://mesutcydev.github.io/vamp-companion/appcast.xml)
  returned successfully; the live feed exactly matches its signed source and
  its Sparkle signature verifies. The page points to the verified Mac archive
  and the existing iOS distribution.

The user authorized validation and release outside the sandbox after its
automatic approval review timed out. Initial local UI runners were stopped
before bootstrap, and the dedicated local iOS simulator timed out during boot;
the GitHub iOS run supplies the completed regression evidence. The release
assets have passed local and public archive verification.

## Remaining hardware and account checks

Live provider-account access, physical iPhone workflows, real model inference
from iOS, full concurrent account/session workflows in both Mac apps, and
physical sleep/wake behavior need separate live verification. Fixture tests do
not certify those hardware and account-dependent scenarios. No original app
data is used as a test fixture.

## Installed app and main website

- The notarized 0.1.0 build 1 is installed in `/Applications/Vamp Companion.app`.
  Its executable hash matches the verified release, code-signature verification
  passes, and Gatekeeper accepts it as Notarized Developer ID. The installed app
  reopened its existing model library and preferences and restored hosting on
  port 9675 alongside the original app.
- A native Check for Updates from the installed app verified the appcast EdDSA
  signature and displayed “You’re up to date!” for 0.1.0. Automatic checks are
  enabled; installation remains user-confirmed. No runtime binary change was
  necessary after publishing the signed feed and installing the release.
- [The main Companion page](https://thevamp.app/companion/) is published through
  the independent website repository, with home and Assistant page links. Its
  desktop/mobile layouts, English/Turkish language switch, dark/light themes,
  navigation, and Mac download/checksum links were checked. All 15 release
  selector tests and static site link checks passed.
- The iOS download is deliberately empty at the user's request; current
  sideloaded builds can pair. No iOS source or distribution asset was changed.

## Companion 0.1.1 and current App Stream compatibility

- Release source: `8ce0def7a71dee6b985047008224763204834bba`. [Validation](https://github.com/Mesutcydev/vamp-companion/actions/runs/38309291470) passed: 1,132 Mac backend tests (51 optional skips), two Companion UI checks, 48 unchanged Assistant iOS unit tests, 12 iOS UI checks (five optional skips), and both device Release builds. All 93 frozen iOS files and release targets remain unchanged.
- The corrected Mac package is Developer ID signed, notarized, and stapled. Its independently downloaded [public ZIP](https://github.com/Mesutcydev/vamp-companion/releases/download/v0.1.1/Vamp-Companion-0.1.1-build-2-public.zip) exactly matches the verified local archive: 15,242,735 bytes, SHA-256 `4437242c2e269febc9b2ca6a7cc3f3079e59f69009f2f575e3f1d5363f575c1a`. Gatekeeper and Sparkle archive/feed signature checks passed before the feed was published.
- The pairing fix is also applied to the current **App Stream** source snapshot from the publisher’s newer working project. Its App Store build is **1.0 (9)** with the unchanged bundle identity and `app-store` channel. Its current artwork, splash, launch screen, and LAN policy are preserved. 667 backend tests and 25 Linux checks passed. Apple processed the signed IPA as VALID, and the existing Internal Testers group has the replacement build. The older website-edition build 8 was removed from that group.
- App Stream’s App Store edition requires the user’s own Mac on the same physical LAN. The existing Assistant iOS app and website Stream edition retain their existing private-network behavior. Physical phone and account-dependent verification remains separate from fixture coverage.

## Companion 0.1.2 local Wi-Fi pairing

- Release source `aeb992e7a06bedc3cc47039b1802d123ab0cb483`. [Final CI](https://github.com/Mesutcydev/vamp-companion/actions/runs/38313579945) passed: 1,134 backend tests (51 optional skips), two Companion UI checks, 48 unchanged Assistant iOS unit tests, 12 iOS UI checks (five optional skips), and both Release builds. All 93 frozen iOS files remain unchanged.
- The native installed release defaults to its physical LAN QR when trusted local Wi-Fi is enabled. Selecting Tailscale changes the QR to the active private VPN endpoint; decoded captures verified port 9675 and the same six-digit pairing code for both. The captures and private network-status output were removed after verification. Selection preserves the running host, paired device count, and network permissions.
- Sparkle’s actual 0.1.0 to 0.1.1 download, installation, and relaunch succeeded in Applications. The verified 0.1.2 is now installed there with the existing models, preferences, credentials, and hosting choice.
- The public 0.1.2 ZIP exactly matches the verified local package: 15,246,498 bytes, SHA-256 `beccb353c30f305ed767ee4f4abeb03c8910e437ca5fd175aabb844417852cea`. Developer ID, notarization, stapling, Gatekeeper, and Sparkle archive/feed signatures passed before feed publication.
- Current App Stream 1.0 build 9 is VALID and IN_BETA_TESTING in the existing Internal Testers group; older build 8 is absent. Its current iOS suite covered 84 cases: 83 passed initially, one stale label expectation was corrected, and all 28 tests in that layout class then passed. 667 backend tests, 25 Linux checks, and all four active Stream/Sync/Control Release target builds passed. Its tested nine-file fix was applied to the current working project while preserving the other 824 snapshot files.


## Current release and iOS home polish — 2026-10-13

- Mac release **0.1.4 (8)**, source `c16534ce5911aee73ab9bff043fcd2d891c7dc6a`,
  is Developer ID signed, notarized (Apple Accepted submission
  `3a979c67-9500-4566-a8a3-118c2405167b`), stapled, and independently verified
  after downloading the public ZIP. SHA-256:
  `628d23c6c8947515314864dee82eab840d6986a3622d44df93b3073a47f4e1bb`.
  Strict signature and Gatekeeper checks passed. The distinct Sparkle archive
  and feed signatures passed before feed publication. The installed app is
  0.1.4 (8); the user's models, preferences, and permission choices were retained.
- Closing the installed Companion window retained its process and host on
  port 9675. The native Settings view reported Accessibility and Screen
  Recording granted. No system permission database was edited for this check.
- The website's current native Mac gallery, brand kit, download, checksum,
  and appcast are live. Pages deployment `38387402473` and 15 site checks
  passed. The iOS download stays empty at the user's request.
- Current **App Stream 1.0 (12)** is VALID and in the existing Internal Testers
  group. Its App Store edition supports trusted Tailscale as well as local
  Wi-Fi. **Vamp Sync 2.3.2 (73)** is signed, notarized, stapled, published,
  and installed; its own signed feed is live. Sync's trusted peer file was
  unchanged by the upgrade. Physical end-to-end Tailscale video still requires
  a paired phone; simulator and policy tests do not certify that workflow.
- The newer working Assistant iOS client used for **0.10.54 (134)** was copied
  read-only into this isolated repository before the design pass. It already
  uses the display name Vamp Companion and bundle `com.beetcode.remote.ios`.
  All 89 inherited files outside the five authorized UI exceptions, the iOS
  targets and release scheme, shared palette, and composer surfaces pass the
  source guard. Core source and dependency versions did not change.
- The compact live home has actual Mac/model/queue state, restrained active
  motion, an integrated shortcut bar, resumable active work, reviewed quick
  starts, and recent conversations. Session and transcript header thumbnails
  were removed. An atomic presentation request carries the selected prompt
  or model into the existing form; cancellation clears it before a fresh New.
- The complete local simulator run passed **48 unit tests and 18 UI cases**
  (five optional UI skips, zero failures). The initial three homepage cases check
  both appearances, prompt review and cancellation reset, offline history and
  disabled starters, and active conversation navigation. Six composer UI cases
  and both Companion hub cases passed with the existing suite.
- The original composer source SHA-256 remains
  `3eca6b2b36cf68c49d5bc81a4def421925507cabeb453338970378aa6eba169e`.
  Its native rendered region is pixel-identical to the current original source
  in light and dark. The complete fixture has a small expected transcript
  layout change from the requested thumbnail removal; it is not claimed to be
  globally identical. Details are in `ios-design-preservation-report.json`.
- Physical phone remote inference, full concurrent live provider-account
  workflows, and physical sleep/wake reconnection remain unverified. No real
  Mac credentials, original app data, or user workspaces were test fixtures.

- Final busy-state review found that the compact featured section could omit
  conversations beyond its first two entries. Additional active and queued
  conversations now remain in the recent list. Running status counts only
  running work. A fourth homepage case opens an additional queued conversation
  and verifies its exact ID; all four homepage cases passed. The combined suite
  now contains 48 unit and 19 UI cases, with five optional UI skips.
  Build 135 was successfully processed by Apple but is superseded by the final
  0.10.55 (136) archive with this correction.


## SiteAgent reference and chat polish

- Desktop/SiteAgent was inspected read-only at the user's request: ChatView,
  MotionKit, DesignKit, and its native chat screenshot. No reference source,
  assets, or data were changed. The isolated iOS app adapts its clear role
  hierarchy, compact tool disclosures, short entry motion, and code-copy UX.
- User turns use an elevated trailing surface. Replies remain open text.
  Code blocks include their language and a 44-point copy control. User-message
  context menus can copy or reuse text; reuse preserves an existing draft and
  never submits automatically. Header thumbnails remain removed.
- New messages enter once without changing layout; token growth does not
  restart springs. Scroll-back, Jump to latest, reasoning, tool failures,
  checkpoints, approvals, image routes, and composer actions are retained.
  Working dots stop offline, in the background, and under Reduce Motion.
- The combined local run passed 48 unit tests and 23 UI cases (five optional
  skips). Four chat cases passed: both appearances/code copy, draft preservation,
  incoming message/composer behavior, and tool/reasoning disclosures.
  The final additional homepage case covers Models → Mac hub → reviewed form.
- The shared palette, composer button regions, original composer source, and
  88 other inherited files pass the source guard. Native composer regions still
  match the current original source exactly in light and dark after chat edits.
- Clean Mac CI at revision 6ecf79a passed 1,134 backend cases (51 optional skips),
  three Companion UI checks, and the Mac Release build. An iOS 26.5 homepage
  interaction failure was inspected through its exported UI hierarchy; the
  whole shortcut surface now explicitly participates in hit testing.
  Final iOS compatibility CI must pass before claiming cross-version completion.
- Build 136 was exported but not uploaded; the user's subsequent chat-reference
  request is included in the combined 0.10.55 (137) package. Build 135 is our own
  uploaded intermediate and will be superseded after the combined build verifies.


## Final Wi-Fi / Tailscale release — 2026-10-13

- Companion 0.1.5 (9) advertises authenticated private routes and a stable Mac
  UUID without changing protocol version 1. Network advertisement changes keep
  the existing listener and code. The iOS client preserves its computer ID,
  token, conversation and draft when switching routes; it reconnects on
  foreground/network changes without replaying mutations.
- Clean macOS job 115361529545 in run 38416304913 passed 1,135 backend cases
  (51 optional skips), three companion UI cases, and the Release build.
- That run passed all 24 iOS UI cases (five optional skips). Its unit process
  exposed a fixture cleanup issue: a pre-seeded fake Mac was automatically
  reconnected after the test URLSession was invalidated. First pairing now
  starts with no profiles and cleanup removes all fixture profiles first.
  This changed only tests and workflow controls; signed production source
  remains identical to revision 254fdff.
- Corrected clean iOS run 38420679884 passed all 57 unit cases, including nine
  routing cases, and the device Release build. Local iOS 27 also passed all
  57 unit cases and the final 15 homepage/composer/chat checks. The shared
  composer remains byte-identical to the current original; 83 inherited
  files outside the explicit UI/connectivity scopes pass the frozen guard.
- Apple notarization accepted Mac submission
  a9a5e553-1c65-48e6-93d1-388028768ed2. The stapled public ZIP passed SHA-256,
  strict signature, hardened-runtime, ticket and Gatekeeper checks after
  downloading it from release v0.1.5. SHA-256:
  45c40372237601be1277b0bf950d2336f6c311f2d5c1917e6581b65eee2f4f88.
- The installed app is 0.1.5 (9). Existing three pairings and native
  Accessibility/Screen Recording grants survived. With its window closed,
  the same temporary test token authenticated status, sessions and models
  through both Wi-Fi and Tailscale. Both reported the same host UUID and
  ready Mac control; unlock was offered only on Tailscale. Cleanup revoked
  only that temporary token and preserved all existing pairings.
- The live signed Sparkle feed advertises precisely the verified archive.
  The thevamp.app page and homepage download use 0.1.5 (9), with matching
  setup instructions. Fifteen site tests and all 49 download/checksum links
  passed. The public iOS download remains empty as requested.
- iOS 0.10.55 (138), bundle com.beetcode.remote.ios, passed strict signing
  and profile/privacy checks, Apple processing is VALID, internal state is
  IN_BETA_TESTING, and the existing mes group lists the build. Its notes
  describe route learning and the combined home/chat polish. Only our own
  intermediate 135 was expired; 136/137 were never uploaded.
- Physical iPhone reconnection outside the LAN, real sleep/wake and concurrent
  live-provider inference remain unverified. The local two-route check does
  not substitute for an actual phone on another network.
