#!/usr/bin/env bash
# Wrap the Release Vamp Companion.app into a UDZO DMG for distribution.
# Does not rebuild — pass the app you just built with xcodebuild -configuration Release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/.derived/Build/Products/Release/Vamp Companion.app}"
DIST="${ROOT}/dist"

if [[ ! -d "$APP" ]]; then
  echo "missing app: $APP" >&2
  echo "usage: $0 [/path/to/Vamp Companion.app]" >&2
  exit 1
fi

IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
[[ "$IDENTIFIER" == com.beetcode.companion ]] || {
  echo "Refusing to package an app other than Vamp Companion." >&2; exit 1;
}

# Preview remains the default for the documented development-signed builds.
# Public packaging must pass the trust gate; this script never signs or submits.
CHANNEL="${VAMP_COMPANION_DISTRIBUTION_CHANNEL:-preview}"
case "$CHANNEL" in
  public) bash "$ROOT/scripts/validate-macos-distribution.sh" "$APP" ;;
  preview) ;;
  *) echo "VAMP_COMPANION_DISTRIBUTION_CHANNEL must be preview or public" >&2; exit 1 ;;
esac

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
# Include the build number so two
# different builds share one name and silently replace each other in dist/.
NAME="Vamp-Companion-${VERSION}-build-${BUILD}-${CHANNEL}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/vamp-companion-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$DIST" "$STAGE"
ditto "$APP" "$STAGE/Vamp Companion.app"
ln -s /Applications "$STAGE/Applications"

# A Release build made with CODE_SIGNING_ALLOWED=NO keeps only the linker's
# ad-hoc stub: no Contents/_CodeSignature, Info.plist unbound, so Gatekeeper
# rejects a downloaded copy as "damaged" ("code has no resources but signature
# indicates they must be present"). Never package an app in that state.
if ! codesign --verify --strict "$STAGE/Vamp Companion.app" >/dev/null 2>&1; then
  cat >&2 <<'MSG'
error: "Vamp Companion.app" has no valid code signature — a downloaded copy would
be rejected by Gatekeeper as "damaged". Build the Release app with signing
enabled (do NOT pass CODE_SIGNING_ALLOWED=NO), or re-sign the app first:
  codesign --force --deep --options runtime --timestamp=none \
    --sign "Apple Development" "/path/to/Vamp Companion.app"
MSG
  exit 1
fi
codesign --verify --deep --strict "$STAGE/Vamp Companion.app" >/dev/null

DMG="${DIST}/${NAME}.dmg"
[[ ! -e "$DMG" ]] || { echo "Artifact already exists: $DMG. Choose a new build number." >&2; exit 1; }
hdiutil create \
  -volname "Vamp Companion ${VERSION}" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

shasum -a 256 "$DMG" | awk '{print $1}' > "${DMG}.sha256"
echo "$DMG"
echo "version=${VERSION} build=${BUILD} sha256=$(cat "${DMG}.sha256")"
