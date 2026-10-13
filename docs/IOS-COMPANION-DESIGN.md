# Vamp Assistant iOS and Companion

The user authorized iOS design and Companion controls on 2026-10-13 and
explicitly selected Vamp Assistant iOS. Work stays in this isolated repository;
the original Assistant checkout and App Stream sources are untouched.

The phone uses the same neutral charcoal surfaces and Vamp red accent as the
Mac. Text keeps native Dynamic Type, controls keep their existing accessibility
semantics, and buttons use flatter, clearer surfaces.

The session header's **Your Mac** action opens a hub with connection and host
activity, local and provider models, model unloading, control readiness,
provider setup, and computer switching. Choosing a model opens the existing
new-session form with that model selected; no task is sent until the user
enters a prompt and starts it. The full model browser searches names, IDs,
and provider details. Offline model and control actions are disabled.

Downloads and imports remain in the Mac's Models tab. Permissions are granted
on the Mac. The hub uses the existing protocol-v1 APIs; routes, authentication,
model identifiers, session behavior, approvals, bots, sharing, and tools are
preserved. Older Vamp Assistant hosts remain supported.

`verification/ios-source-sha256.json` retains the original baseline. The six
modified UI files are explicitly listed in `ios-authorized-ui-changes.json`;
all other inherited files, assets, target identity and distribution settings
are still checked by `scripts/verify-ios-unchanged.py`.

The existing iOS bundle is `com.beetcode.remote.ios`. Its App Store Connect
record is named Vamp Companion (ID 6822249541); this is distinct from App
Stream's `com.mesutcy.remotedesktop.stream`. Release version/build values can
be supplied to Xcode at archive time without changing the inherited target.

Validation includes the existing iOS unit/regression and UI suites, plus
Companion hub checks for light/dark, model selection, and disabled offline
actions. Fixtures never restore a real Mac connection or send work to it.
