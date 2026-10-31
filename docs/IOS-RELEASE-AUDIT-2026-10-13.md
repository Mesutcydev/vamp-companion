# Vamp Companion iOS release audit — 0.10.56 (139)

Release status: **Available in internal TestFlight testing**. App Store Connect app 6822249541; existing bundle `com.beetcode.remote.ios`; internal tester group **mes**.

The audit covers the updated Models, Settings, Bots, providers, sharing, paired computers, console, diagnostics, and session setup. All identified code and design findings below are fixed. The homepage, composer, palette, pairing, protocol, and app assets are preserved. Unrelated pre-existing Mac host work remains intact.

## Findings and fixes

| Severity | Finding | Final behavior |
| --- | --- | --- |
| P2 | Repeated taps could schedule multiple bot launches or provider updates. | Pending state is set before creating a task; actions are disabled and checked at entry. Requests capture their reviewed inputs. |
| P2 | Cached bot approval/run controls and keyboard console submission stayed available offline. | Execution controls check connection state. Offline keyboard submission preserves the command and explains how to reconnect. |
| P2 | Settings requested another sheet during dismissal. | Computer switching and diagnostics open from the dismissal completion; navigation is covered on phone and tablet. |
| P2 | Errors could be hidden behind the open menu or full-screen session form. | Bots, sharing, the Mac hub, and session setup present errors in the visible surface. Rejected requests keep the draft. |
| P2 | Successful run-control responses could clear text edited while the request was pending. | Answer, steer, launch, and key drafts clear only when the submitted text is still current; provider fields are locked during updates. |
| P3 | Cached provider readiness and an empty provider list could imply a live connection or failed search. | Provider detail explicitly reports Mac offline, disables mutations, and uses a useful empty state and reconnect guidance. |
| P3 | Some destructive controls had inconsistent disabled feedback and small touch targets. | Bot controls and key removal use the shared style and 44-point targets. Bot action controls stack at accessibility text sizes. |
| P3 | A cancelled sharing toast task could clear newer feedback. | Toast lifetime is keyed to its message and cancellation returns without clearing the current notice. |
| P3 | The offline bot notice did not match the shared card shape; previous release archives omitted crash symbols. | The notice uses the shared rounded shape. This archive generates matching dSYMs and includes matching symbols in the IPA. |

## Validation

| Check | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| Full iOS suite | 84 | 0 | 5 |
| Final iPhone menus and navigation | 16 | 0 | 0 |
| Final iPhone pending requests, touch targets, and large text | 5 | 0 | 0 |
| Final iPad secondary pages | 9 | 0 | 0 |
| Mac unit and UI regressions | 1096 | 0 | 51 |

The full suite and focused reruns are separate checkpoints, not additive counts of unique tests. The five iOS skips require optional isolated-host harnesses; the Mac skips are opt-in live or expensive checks. Physical iPhone/Mac, live Tailscale streaming, and sleep/wake were not exercised in this pass.

The negative new-session check exposed its missing error presenter and verified the fix. Earlier simulator runs produced a typing mismatch and observed a completed request after waiting for animations. QA now runs serially with an explicit fixture response gate, and the QA iPad runtime was refreshed. The fixture never executes real mutations and is excluded from Release.

`scripts/verify-ios-unchanged.py` verifies 76 inherited source, test, asset, and distribution files, plus the original composer surfaces, shared palette, iOS targets, and release scheme. `git diff --check` passes. Enabled primary-button text contrast is at least 4.70:1 across both appearances and all accent fills.

The final archive and IPA pass strict signature validation and Apple validation. The payload is arm64, supports iPhone and iPad on iOS 18+, retains the existing Keychain identity, sets `get-task-allow` to false, includes the privacy manifest and matching crash symbols, and excludes DEBUG fixtures and the build-tool helper. Signing and version overrides live in the temporary release project.

The frozen source manifest verifies 95 production/input files and is recorded in `verification/ios-0.10.56-build-139-source-sha256.json`. The build includes local authorized changes, so its source manifest is authoritative alongside the base commit.

IPA SHA-256: `9abcd033f227b08e6c9b70b9326f790f63aafc73818f443036d56e6753143462`.

## Distribution record

The signed IPA is `dist/companion-ios-testflight-0.10.56-build-139/export-upload/Vamp Companion.ipa`. The structured audit and Apple processing details are in `verification/ios-0.10.56-build-139-release-audit.json`.

Distribution uses the existing Companion App Store Connect record and internal **mes** group. TestFlight notes describe the menu redesign, pending/error feedback, offline controls, and Settings navigation. There is no App Store submission, public TestFlight link, or new tester invitation in this release.

Apple confirms processing state `VALID`, internal state `IN_BETA_TESTING`, and build 139 in the existing mes group. Build ID: `cddbbe30-9ce2-420b-9760-0685d72ebcc8`. The en-GB testing notes were saved and independently read back using Apple’s [localized build-note API](https://developer.apple.com/documentation/appstoreconnectapi/betabuildlocalization/attributes-data.dictionary).
