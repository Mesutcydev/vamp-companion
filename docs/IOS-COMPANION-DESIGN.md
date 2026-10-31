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

## Conversation polish

The user supplied the Desktop/SiteAgent project as a read-only reference.
Its ChatView, MotionKit, DesignKit, and native screenshot informed this pass.
No SiteAgent source, branding, configuration, or data was changed or imported.

User turns now have a trailing, softly elevated surface. Assistant replies
remain open, readable text with no header thumbnails. The navigation title
includes the actual Mac name. Tool requests/results use compact disclosure rows;
reasoning, failures, checkpoints, approvals, and their existing actions remain.
Code blocks have a language label and a 44-point Copy control with brief feedback.
Long-press Copy message and Use in composer are available for user turns.
Reuse preserves an existing draft and never sends it automatically.

New turns enter once with a short fade and eight-point movement. History renders
immediately. Streaming text does not restart entry or scroll animations on every
token; scroll-back intent and Jump to latest are preserved. Phase labels fade
briefly, and working dots stop while offline, inactive, or Reduce Motion is on.
The composer file, layout, model control, attachment routes, queue/steer/stop,
keyboard behavior, and shared button materials are preserved.

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

## Consistent secondary pages

Models, Settings, Bots, API providers, sharing, paired computers, console files,
connection diagnostics, and session setup use the homepage’s warm canvas and
charcoal/white reading surfaces. `RemotePageDesign.swift` supplies the shared
17-point cards, compact section headings, soft icon wells, dividers, fields,
source controls, and press feedback. The Mac hub no longer owns a separate
neutral palette. Model search, source groups, latest labels, loaded state,
unloading, and the existing reviewed-session flow remain available.

The bot roster comes before delegation. Each role has a distinct line glyph
and a readable state. Bot details, run inputs, and bot selection share the same
cards. Settings uses compact appearance controls and accessible accent swatches;
provider credentials still travel once to the Mac’s Keychain. Sharing and
new-work controls show connection state and are disabled while offline.

Accessibility text stacks source controls, status badges, and metadata where
needed. Every new action has a minimum 44-point target. Reduce Motion disables
press scaling and console scroll movement; the new cards are opaque under all
transparency preferences and strengthen their borders with Increase Contrast.
The existing homepage, transcript, composer, palette, and app assets are retained.

## Source and release identity

The newer working iOS client used for TestFlight 0.10.54 (134) was imported
read-only on 2026-10-13 before this pass, including its current branding, icon,
privacy manifest, and client fixes. The initial baseline remains in
`verification/ios-source-sha256.json`; the current baseline is in
`ios-current-source-sha256.json` and `ios-current-project-sha256.json`.
The authorized secondary UI files have explicit exceptions. New homepage and Mac-hub
files are isolated additions. The guard verifies all inherited files outside those exceptions,
iOS target identity and scheme, shared palette, and composer button surfaces.

The current display name and App Store Connect record are **Vamp Companion**
(ID 6822249541). This is the existing Assistant client, bundle
`com.beetcode.remote.ios`, distinct from App Stream's
`com.mesutcy.remotedesktop.stream`. The combined homepage/chat archive uses 0.10.55, build 137.
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

Chat-specific UI coverage checks both appearances and code copy, draft-safe reuse,
incoming-message/composer behavior, and tool/reasoning disclosures.

The secondary-page pass on 2026-10-13 passes 57 iOS unit tests, 14 affected iPhone UI checks, and the iPad bot Chat/Run flow. The Mac regression run passes 1,096 tests with 51 opt-in skips. The unsigned iPhone/iPad Release build and the 76-file source preservation guard also pass.

The secondary-page release audit and its fixes are recorded in [IOS-RELEASE-AUDIT-2026-10-13.md](IOS-RELEASE-AUDIT-2026-10-13.md). The signed release is 0.10.56 (139), using the existing Companion app record and internal mes group.
