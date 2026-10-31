# Vamp Companion for the Mac App Store

The `VampCompanionAppStore` target is a sandboxed edition, version 1.0 (1).
The existing `VampCompanion` target remains the unrestricted website download.
Both use `com.beetcode.companion`; install one edition at a time. Store data
uses the macOS sandbox container, and credentials use Companion's existing
Keychain services. The app does not automatically import the website edition's
sessions, preferences, or external model references.

## What ships

- Native Models, Devices, Settings, and a menu bar item.
- MLX safetensors inference using the bundled in-process MLX engine. Model
  downloads are data, never executables. Native model import copies a
  user-selected MLX folder into app-owned storage while retaining its open-panel
  access grant for the full copy.
- Direct API providers with user-supplied credentials, stored in Keychain.
- Authenticated protocol version 1 chat, session streaming, revocation, and
  opt-in clipboard/file exchange over private Wi-Fi or Tailscale.
- Background hosting after window closure; launch at login remains opt-in.
- A promo card on Models and Settings linking to the separate, unrestricted
  website edition. It does not unlock features or install software.
- App Store updates. Sparkle is absent from the store target's dependency graph,
  binary, and Info.plist.

Store builds reject control, terminal, workspace, and bot routes before
routing; cannot enable control through saved preferences; do not register
agent tools or run MCP, hooks, external harnesses, or Codex; do not scan the
Assistant library; and do not launch GGUF or downloaded inference runtimes.
The website edition keeps those features. The compiler flag is fixed at build
time and cannot be changed by a preference or phone request.

## Build, test, and archive

```sh
xcodegen generate
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export TEST_RUNNER_DEVELOPER_DIR="$DEVELOPER_DIR"
xcodebuild -project BeetCode.xcodeproj -scheme VampCompanionAppStore \
  -destination 'platform=macOS' -derivedDataPath .derived-appstore \
  -clonedSourcePackagesDirPath .spm -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO test
python3 scripts/verify-ios-unchanged.py
```

For a signed archive, select the team that owns the bundle ID in App Store
Connect. Do not assume that the website signing team or the development team
owns the App Store record.

```sh
export VAMP_APP_STORE_TEAM_ID=YOUR_TEAM_ID
scripts/archive-companion-appstore.sh --archive
scripts/archive-companion-appstore.sh --export
```

The script archives with manual distribution signing and exports a Mac App Store package locally.
Set `VAMP_APP_STORE_SIGNING_IDENTITY` and `VAMP_APP_STORE_INSTALLER_IDENTITY`
to certificate names or SHA-1 fingerprints when several identities are available.
Set `VAMP_APP_STORE_EXPORT_PATH` to choose a fresh export directory.
It does not upload or submit for review. Open the archive in Xcode Organizer
for validation and upload. Archive/export may need a signed-in Xcode account,
Mac App Store provisioning profile, Apple Distribution certificate, and Mac
Installer Distribution certificate. App Store builds do not use Developer ID,
notarization, stapling, Sparkle, or the website release scripts.

Validate an app bundle with `scripts/validate-companion-appstore.py APP_PATH`.
Use `--distribution` on the distribution-signed app to additionally require a
distribution certificate, with no debugger entitlement. When a profile is
embedded, its distribution type and identity are checked. Add `--testflight`
to require a profile; macOS App Store apps with no restricted entitlements
can ship without one ([TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)). A development/ad hoc archive is local validation evidence, not an
uploadable distribution artifact.

## App Store Connect metadata draft

- Name: **Vamp Companion**
- Subtitle: **Local AI for your iPhone**
- Category: Utilities
- Price: Free; no in-app purchases or subscriptions implemented.
- Keywords: `local AI,MLX,Mac,iPhone,assistant,models,private,companion`
- Marketing/support URL: `https://thevamp.app/companion/`
- Privacy policy URL: `https://thevamp.app/privacy/`
- Copyright: 2026 Vamp Assistant contributors

Description:

> Run local AI models on your Apple Silicon Mac and connect from Vamp Assistant
> on your iPhone or iPad. Download supported MLX models, import your own model
> folder, or connect an API provider with your own key.
>
> Pair your devices with a one-time code over trusted local Wi-Fi or your private
> Tailscale network. Conversations and streaming responses stay available while
> Vamp Companion runs, even after you close its window. You decide whether to
> enable clipboard exchange, file transfer, and launch at login.
>
> Local model inference runs on your Mac. API requests go directly to the
> provider you select and are subject to that provider's terms and charges.
> No model weights or provider credentials are bundled.
>
> Requires an Apple Silicon Mac with macOS 15 or later. Remote use requires a
> compatible Vamp Assistant client and a reachable Mac. This App Store edition
> supports MLX models, API providers, and chat; Mac control, terminal, coding
> tools, ChatGPT account sign-in, and other local runtimes are offered in the
> separate website edition.

## Privacy and review notes

The manifest declares no tracking or developer-operated collection, and states
reasons for app preferences, app/user-selected file metadata, download free-space
checks, and in-app elapsed-time measurement. Third-party model registries and
user-selected API providers receive the requests sent to them. Review the
privacy questionnaire against the final provider behavior and the live policy;
this manifest is not a substitute for the App Store privacy questionnaire.
No microphone, camera, Accessibility, Apple Events, or screen recording
entitlements are requested by the store target.

Suggested reviewer steps:

1. Open Models, choose Discover, and download a supported MLX model appropriate
   for the review Mac's available memory. Alternatively connect an API provider
   with the reviewer's own API key in Settings. No developer account is needed
   for public model downloads; avoid gated models for review.
2. Open Devices, leave trusted local Wi-Fi enabled, and enable iPhone access.
   Pair a compatible Vamp Assistant iOS client using the displayed QR code/code.
   The Mac also serves a browser chat page at the displayed host address; open
   it locally and enter the same pairing code to review without an iPhone.
3. Select the loaded model and send a message. Verify live responses, stop,
   conversation history, and optional sharing.
4. Close the Mac window and reopen it through the menu bar. Quit ends hosting.
5. Review the website-edition card in Models or Settings. It opens a product
   webpage in the default browser. It is informational and does not bypass
   store updates or modify the running app's capabilities.

Before submission: confirm App Store record ownership and signing; validate
and upload the exported build; supply final screenshots, age rating, privacy
answers, review contact, and any client access needed for review. Verify an
actual MLX download/import/inference and a real paired iPhone on Wi-Fi and
Tailscale under the distribution signature. Public iOS availability must match
what the listing promises; do not advertise an unavailable client as released.
Apple approval is determined by App Review.

References: [Mac App Store rules](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility),
[required reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype),
[App Sandbox](https://developer.apple.com/documentation/security/app-sandbox).

## Validation on 23 October 2026

A distribution-signed 1.0 (1) archive and installer were created locally.
The archive and extracted installer payload pass signature, sandbox, privacy
manifest, and Sparkle exclusion checks. The Mac backend suite completed 1,154
tests with 51 opt-in skips and no failures; 57 iOS tests and five store security
and rendering tests passed. Light/dark promo previews were inspected.
See [the evidence record](../verification/appstore/readiness-2026-10-23.json).

The Mac was locked, and the user chose checks without desktop access. Full
interactive Mac UI tests, App Store window screenshots, real model inference,
and live iPhone pairing remain pending. No upload, review submission, or public
release was performed.
