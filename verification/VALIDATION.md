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
- All 93 frozen iOS source, test, asset, and distribution files match the
  inherited snapshot. All inherited iOS targets and release scheme settings
  match as well. The dependency lockfile matches the original revisions.

## Pending gates

- Companion UI checks: the initial runner was stopped before bootstrapping
  because its signature was not trusted. A locally signed rerun is required.
- Unchanged iOS regression tests: compilation completed in the dedicated
  companion QA simulator, but the launch service died before the suite could
  run (`NSMachErrorDomain -308`, server died). A clean rerun is required.
- Developer ID Release signing, notarization, stapling, and Gatekeeper checks.
- ZIP/checksum publication and public-download verification before publishing
  the signed companion appcast.

The sandbox's automatic approval review timed out twice before the locally
signed Mac UI rerun could execute. Testing, signing/notarization, and publication
remain pending the explicit approval request. No public release or appcast has
been published.

Live provider-account access, physical iPhone workflows, real model inference
from iOS, simultaneous running Mac apps, and physical sleep/wake behavior need
separate live verification. Fixture tests do not certify those hardware and
account-dependent scenarios. No original app data is used as a test fixture.
