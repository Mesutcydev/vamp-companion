#!/usr/bin/env python3
"""Fail closed on a wrong distribution channel or unsafe App Store entitlements."""
import argparse
import json
import plistlib
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path)
parser.add_argument('--distribution', action='store_true', help='Also require a Mac App Store distribution signature')
parser.add_argument('--testflight', action='store_true', help='Require a provisioning profile for TestFlight')
args = parser.parse_args()
if args.testflight:
    args.distribution = True
app = args.app.resolve()
contents = app / 'Contents'
def require(condition, message):
    if not condition:
        raise SystemExit(message)
info = plistlib.loads((contents / 'Info.plist').read_bytes())
require(info['CFBundleIdentifier'] == 'com.beetcode.companion', 'Wrong bundle identity')
require(not any(key.startswith('SU') for key in info), 'Sparkle configuration must not ship in App Store builds')
require(not list(app.rglob('Sparkle.framework')), 'Sparkle framework must not ship in App Store builds')
manifest = plistlib.loads((contents / 'Resources/PrivacyInfo.xcprivacy').read_bytes())
require(manifest['NSPrivacyTracking'] is False, 'Unexpected tracking declaration')
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
signed = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True, check=True)
entitlements = plistlib.loads(signed.stdout)
allowed = {'com.apple.security.app-sandbox', 'com.apple.security.network.client', 'com.apple.security.network.server',
           'com.apple.security.files.user-selected.read-write', 'com.apple.security.get-task-allow',
           'com.apple.application-identifier', 'com.apple.developer.team-identifier'}
require(entitlements.get('com.apple.security.app-sandbox') is True, 'App Sandbox is required')
require(not (set(entitlements) - allowed), 'Unexpected entitlements: ' + str(set(entitlements) - allowed))
require(not any('temporary-exception' in key for key in entitlements), 'Temporary sandbox exceptions are not allowed')
if args.distribution:
    require(not entitlements.get('com.apple.security.get-task-allow'), 'Distribution cannot allow a debugger')
    profile_path = contents / 'embedded.provisionprofile'
    require(not args.testflight or profile_path.is_file(), 'TestFlight provisioning profile is missing')
    # TN3125: macOS apps without restricted entitlements need no profile,
    # including App Store distribution. TestFlight always requires one.
    if profile_path.is_file():
        profile = plistlib.loads(subprocess.run(['security', 'cms', '-D', '-i', str(profile_path)], capture_output=True, check=True).stdout)
        require(not profile.get('ProvisionedDevices'), 'A development profile cannot be submitted')
        require(profile.get('Entitlements', {}).get('com.apple.application-identifier', '').endswith('.com.beetcode.companion'), 'Profile identity does not match')
    signature = subprocess.run(['codesign', '-dvv', str(app)], capture_output=True, text=True, check=True).stderr
    require('Authority=Apple Distribution:' in signature or 'Authority=3rd Party Mac Developer Application:' in signature,
            'A Mac App Store distribution certificate is required')
print(json.dumps({'app': str(app), 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
                  'sandbox': True, 'sparkle': False, 'privacy_manifest': True, 'distribution_checked': args.distribution}, indent=2))
