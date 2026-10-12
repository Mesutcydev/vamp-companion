# Vamp Companion 0.1.0 validation

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
