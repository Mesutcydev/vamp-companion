#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${VAMP_APP_STORE_TEAM_ID:?Set VAMP_APP_STORE_TEAM_ID to the team that owns com.beetcode.companion in App Store Connect}"
mode="${1:---archive}"
archive="${2:-$root/dist/appstore/Vamp Companion.xcarchive}"
case "$mode" in
  --archive)
    test ! -e "$archive" || { echo "Archive already exists: $archive" >&2; exit 1; }
    cd "$root"
    python3 scripts/verify-ios-unchanged.py
    xcodegen generate
    xcodebuild -project BeetCode.xcodeproj -scheme VampCompanionAppStore -configuration Release \
      -destination 'generic/platform=macOS' ARCHS=arm64 EXCLUDED_ARCHS=x86_64 -archivePath "$archive" -derivedDataPath .derived-appstore \
      -clonedSourcePackagesDirPath .spm -onlyUsePackageVersionsFromResolvedFile \
      DEVELOPMENT_TEAM="$VAMP_APP_STORE_TEAM_ID" CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="${VAMP_APP_STORE_SIGNING_IDENTITY:-Apple Distribution}" archive
    python3 scripts/validate-companion-appstore.py "$archive/Products/Applications/Vamp Companion.app" --distribution
    ;;
  --export)
    test -d "$archive" || { echo "Archive not found: $archive" >&2; exit 1; }
    python3 "$root/scripts/validate-companion-appstore.py" "$archive/Products/Applications/Vamp Companion.app" --distribution
    export_path="${VAMP_APP_STORE_EXPORT_PATH:-$root/dist/appstore/export}"
    test ! -e "$export_path" || { echo "Export already exists: $export_path" >&2; exit 1; }
    options="$(mktemp -t vamp-companion-appstore-export)"
    trap 'rm -f "$options"' EXIT
    /usr/bin/python3 - "$options" "$VAMP_APP_STORE_TEAM_ID" "${VAMP_APP_STORE_SIGNING_IDENTITY:-Apple Distribution}" "${VAMP_APP_STORE_INSTALLER_IDENTITY:-Mac Installer Distribution}" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as file:
    plistlib.dump({'method':'app-store-connect','destination':'export','teamID':sys.argv[2],
                  'signingStyle':'manual','signingCertificate':sys.argv[3],
                  'installerSigningCertificate':sys.argv[4],
                  'manageAppVersionAndBuildNumber':False}, file)
PY
    xcodebuild -exportArchive -archivePath "$archive" -exportPath "$export_path" \
      -exportOptionsPlist "$options" -allowProvisioningUpdates
    pkgutil --check-signature "$export_path/Vamp Companion.pkg"
    python3 - "$export_path/Vamp Companion.pkg" <<'PY_CHECKSUM'
import hashlib,sys
from pathlib import Path
package = Path(sys.argv[1])
package.with_suffix('.pkg.sha256').write_text(hashlib.sha256(package.read_bytes()).hexdigest() + '  ' + package.name + '\n')
PY_CHECKSUM
    ;;
  *) echo "Usage: $0 --archive|--export [absolute archive path]" >&2; exit 2 ;;
esac
