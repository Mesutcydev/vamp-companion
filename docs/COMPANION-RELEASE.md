# Vamp Companion release process

Vamp Companion has its own app identity, GitHub repository, Pages site, and
Sparkle update channel. Never publish companion assets to `vamp-assistant`.

1. Run the macOS backend/unit suite, companion UI smoke tests, and unchanged
   iOS regression tests. Verify model download/import, remote session workflows,
   window-close behavior, and isolation alongside the original Mac app.
2. Run `scripts/release-vamp-companion.sh --submit` using a full Xcode installation
   with the signing team's Apple account. This archives, Developer ID signs,
   and submits through Xcode's notarization flow. Revoked identities are excluded.
3. After Apple accepts, run `scripts/release-vamp-companion.sh --export-notarized
   /absolute/path/to/Vamp\ Companion.xcarchive`.
4. Packaging validates Developer ID, hardened runtime, timestamp, release
   entitlements, the stapled ticket, and Gatekeeper. It creates the public ZIP,
   checksum, and a signed appcast staged under `dist/updates/`.
5. Upload the ZIP and checksum to `Mesutcydev/vamp-companion` release `v<version>`.
   Download and verify the public archive. Only then copy the staged appcast to
   `site/appcast.xml`, commit it, and publish GitHub Pages.

The update-signing private key remains in the login Keychain under the
`vamp-companion` account. The appcast and archives use that key, never the
original app's `vamp-assistant` signing account. Do not export private keys
into this repository.

The shipped feed is `https://mesutcydev.github.io/vamp-companion/appcast.xml`.
The original iOS app is unchanged and distributed from its existing repository.
The `site/` directory alone is deployed to Pages; inherited historical documents
and original distribution metadata under `docs/` are not deployed.

ChatGPT account state uses the private `Application Support/VampCompanion/Codex`
directory. The app-server child uses its own CLI home and explicitly selects
file credential storage, as documented in [OpenAI's credential storage guidance](https://learn.chatgpt.com/docs/auth#credential-storage).
Signing out removes only that account's companion credentials. The parent
environment and the original CLI account directory are never changed.
