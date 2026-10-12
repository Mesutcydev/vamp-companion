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
- GitHub validation with Xcode 26.6 also passed the entire backend suite
  (1,132 tests, 51 skipped), and the Mac window-close/reopen UI test passed.
- The unchanged iOS regression suite passed on GitHub: 48 unit tests and
  12 UI tests (five optional UI scenarios skipped), with zero failures. The
  unchanged iOS device Release configuration also built successfully.
- Native manual checks reached Models, Devices, Settings, and the compact
  provider sheet. The live companion listened on 9675 while the original app
  continued listening on its separate 9471/9473/9475 ports. The companion's
  host remained running after the close command; an unauthenticated status
  request correctly returned HTTP 401.
- All 93 frozen iOS source, test, asset, and distribution files match the
  inherited snapshot. All inherited iOS targets and release scheme settings
  match as well. The dependency lockfile matches the original revisions.

## Pending gates

- Companion navigation UI check: GitHub exposed an off-screen provider-sheet
  Done button because provider cards were not in a scroll view. The corrected
  layout and centered model empty state are awaiting rerun and visual checks.
- Developer ID Release signing, notarization, stapling, and Gatekeeper checks.
- ZIP/checksum publication and public-download verification before publishing
  the signed companion appcast.

The user authorized validation and release outside the sandbox after its
automatic approval review timed out. Initial local UI runners were stopped
before bootstrap, and the dedicated local iOS simulator timed out during boot;
the GitHub iOS run supplies the completed regression evidence. No public release
or signed appcast has been published yet.

Live provider-account access, physical iPhone workflows, real model inference
from iOS, simultaneous running Mac apps, and physical sleep/wake behavior need
separate live verification. Fixture tests do not certify those hardware and
account-dependent scenarios. No original app data is used as a test fixture.
