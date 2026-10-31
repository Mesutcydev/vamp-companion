# Project Environment

Vamp Companion is a native SwiftUI macOS app with preserved native iOS targets.
It is not React Native; there is no Android target or Metro server. The
`argent-environment-inspector` completed this session on 2026-10-23.
Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (Xcode 27.1),
not the globally selected Xcode beta. Forward that value as
`TEST_RUNNER_DEVELOPER_DIR` for tests that invoke nested Xcode builds.

`project.yml` is the XcodeGen source. Generate only while no builds are running.
`VampCompanion` is the unrestricted Developer ID edition; the new
`VampCompanionAppStore` scheme compiles the sandboxed edition with
`VAMP_APP_STORE`. Both preserve the internal `BeetCode` module and Companion
bundle identity. The preserved iOS scheme is `BeetCodeRemoteIOS`.

Use `.spm` for cached package clones, `.derived` for the website edition,
`.derived-appstore` for the store edition, and `.derived-ios` for iOS.
Backend tests live in `Tests`, native Mac UI tests in `CompanionUITests`, and
store capability/route/UI tests in `AppStoreTests` and `AppStoreUITests`.
Run `python3 scripts/verify-ios-unchanged.py` before releasing.
See `docs/COMPANION-APP-STORE.md` and `docs/COMPANION-RELEASE.md`.

The inspection JSON is saved in `verification/appstore/environment-inspection.json`.
The signed App Store package and evidence are recorded in
`verification/appstore/readiness-2026-10-23.json`. Full interactive Mac UI QA
remains pending because the user chose checks without desktop access.
