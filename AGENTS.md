# Vamp Companion — agent onboarding

Vamp Companion is a separate macOS host for the existing Vamp Assistant iOS
app. Work only in this repository. Never edit or publish to the original
`vamp-assistant` repository or use its preferences, Keychain services, model
folders, checkpoint refs, or update-signing key.

## Product contract

- The Mac has one window with Models, Devices, and Settings, plus a menu bar
  item. Runtime services belong to the application and survive window closure.
- Preserve the session host, agent tools, bots, approvals, streaming, native
  dialogs, local and provider models, and remote protocol version 1.
- Keep the inherited iOS application, assets, identity, and release settings
  unchanged. Run `python3 scripts/verify-ios-unchanged.py` after changes.
- Companion identity is `com.beetcode.companion`; Application Support is
  `VampCompanion`; default hosting port is 9675; checkpoint refs are under
  `refs/vamp-companion/checkpoints/`. No legacy migration or model discovery
  from the original app is allowed.
- Launch at login, sharing, and Mac control are opt-in. Hosting begins after
  explicit pairing setup and restores that saved choice on later launches.

## Build and validation

Read `README.md` and `docs/COMPANION-RELEASE.md`. The inherited
`docs/APP-REPORT.md`, `docs/COMPARISON.md`, and `docs/COMPOSER-DESIGN.md`
describe the preserved backend and original UI for reference.

Run `xcodegen generate` after adding or removing source files, only when no
build is running. The project and internal Swift module remain named BeetCode
for backend compatibility; the Mac target and scheme are VampCompanion.

Run the VampCompanion scheme for macOS and BeetCodeRemoteIOS for the iOS
simulator, using separate derived data when needed. Use a full Xcode through
`DEVELOPER_DIR`; also forward it as `TEST_RUNNER_DEVELOPER_DIR` for Ship Center
integration tests. Run backend unit tests, companion UI tests, and unchanged
iOS regression tests. Verify model workflows, protocol compatibility,
closed-window operation, and state isolation. Report any hardware or
live-account checks that remain unverified.

## Backend architecture and rules

- `AppState` (MainActor) → `AgentSessionController` → `AgentLoop` (actor) →
  `PermissionGate` → `ToolExecutor` → `AgentTool`s.
- `LLMEngine` and `EngineRouter` retain local MLX/GGUF and provider routing.
- `Workspace` confines paths; `ShellRunner` owns process groups;
  `GitCheckpointer` owns only companion checkpoint refs.
- Sessions are encrypted with the companion Keychain key. Bot runtimes and
  downloads must also use companion-owned storage.
- Keep NSLock operations in synchronous helpers. Add tools through
  `AgentSessionController.defaultTools` with honest risk and JSON schemas.
- Use `FakeLLMEngine`, `FixtureHub`, and `TempWorkspace` in tests. Never mutate
  real user workspaces or original app data to verify isolation.

## Distribution

Publish only to `Mesutcydev/vamp-companion`. Developer ID signing,
notarization, stapling, Gatekeeper verification, and archive verification must
pass before publishing a release. The Sparkle Keychain account is
`vamp-companion`; never export its private key into source control. Upload and
verify release assets before publishing the signed appcast. GitHub Pages
deploys only `site/`; inherited original appcasts and iOS distribution metadata
under `docs/` are historical reference files.
