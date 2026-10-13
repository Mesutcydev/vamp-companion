# Assistant iOS client and Companion

The user selected Vamp Assistant iOS for the Companion controls and design
round. All work stays in this isolated repository. The original Assistant
checkout, App Stream sources, and their installed applications remain untouched.

## Compact live home

Home combines a layered graphite Mac console, a compact shortcut bar, active
work, two editable quick starts, and recent conversations in one scrollable
surface. The console uses the existing dotted Vamp mark, a soft red signal,
thin edge highlights, and a quiet dot texture. It shows the actual connection,
loaded model, and queue; it does not invent performance measurements. The
texture and beacon animate only while work is running and the app is active.
Reduce Motion stops those effects and press scaling. Controls remain at least
44 points tall; larger accessibility text reflows the shortcuts and starters.

Models, Control, Bots, and Share open the existing workflows. Quick starts
prefill the existing new-session form for review; they never submit work
without an explicit Start action. Active conversations can be resumed directly. Two are featured; every additional
active or queued conversation stays reachable in the recent list.
Search, pull to refresh, rename, delete, Settings, and New remain available.
Offline state retains cached conversations and disables new work. Decorative
thumbnails have been removed from chat list rows and transcript speaker headers.
The composer file, shared palette, and composer button materials are preserved.

## Mac cooperation

The Models shortcut opens Your Mac with connection and host activity, local
and provider models, model unloading, control readiness, provider setup, and
computer switching. Choosing a model opens the existing new-session form with
that model selected. A missing control status from an older host is reported as
unavailable, rather than falsely reporting disabled Mac permissions.

Downloads, imports, and permission grants remain on the Mac. The hub uses the
existing protocol-v1 APIs. Routes, authentication, model identifiers, session
behavior, approvals, bots, sharing, tools, and provider behavior are preserved.
Older Vamp Assistant hosts remain supported.

## Source and release identity

The newer working iOS client used for TestFlight 0.10.54 (134) was imported
read-only on 2026-10-13 before this pass, including its current branding, icon,
privacy manifest, and client fixes. The initial baseline remains in
`verification/ios-source-sha256.json`; the current baseline is in
`ios-current-source-sha256.json` and `ios-current-project-sha256.json`.
Five inherited UI files have authorized exceptions. New homepage and Mac-hub
files are isolated additions. The guard verifies the other 89 inherited files,
iOS target identity and scheme, shared palette, and composer button surfaces.

The current display name and App Store Connect record are **Vamp Companion**
(ID 6822249541). This is the existing Assistant client, bundle
`com.beetcode.remote.ios`, distinct from App Stream's
`com.mesutcy.remotedesktop.stream`. The final archive uses 0.10.55, build 136.
The user authorized distribution to the existing internal TestFlight group
**mes**. No other tester invitations or App Store submission are included.

## Validation

Run the existing iOS unit and UI suites, Companion hub tests, and homepage UI
checks. The homepage checks cover light/dark model state, reviewed quick-start
prompts, active-session navigation, offline history/disabled starters, and multiple active/queued conversations.
Native composer renders are compared against the current original source in
both appearances. DEBUG fixtures use temporary in-memory credentials and
stubbed loopback API calls; they do not restore a real paired Mac or submit
work. Physical iPhone, Tailscale streaming, and sleep/wake tests still require
live hardware and must not be inferred from simulator results.
