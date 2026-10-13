#!/usr/bin/env python3
"""Check the inherited iOS baseline outside the user's explicit change scopes."""
import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
current_baseline = root / "verification/ios-current-source-sha256.json"
baseline = current_baseline if current_baseline.exists() else root / "verification/ios-source-sha256.json"
expected = json.loads(baseline.read_text())
authorization = root / "verification/ios-authorized-ui-changes.json"
allowed = set(json.loads(authorization.read_text())["files"]) if authorization.exists() else set()
connectivity = root / "verification/ios-authorized-connectivity-changes.json"
network_allowed = set(json.loads(connectivity.read_text())["files"]) if connectivity.exists() else set()
allowed |= network_allowed
if any(not name.startswith("iOSApp/") or not name.endswith(".swift") for name in allowed):
    raise SystemExit("iOS authorization must not include assets, identity, or release settings.")
changed = []
for name, fingerprint in expected.items():
    path = root / name
    if name not in allowed and (not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != fingerprint):
        changed.append(name)
if changed:
    raise SystemExit("Frozen iOS files changed:\n" + "\n".join(changed))
project = (root / "project.yml").read_text()
current_project = root / "verification/ios-current-project-sha256.json"
project_baseline = current_project if current_project.exists() else root / "verification/ios-project-sha256.json"
project_expected = json.loads(project_baseline.read_text())
for section, fingerprint in project_expected.items():
    kind, name = section.split(":", 1)
    if kind == "target":
        match = re.search(r"^  " + re.escape(name) + r":\n(?:(?!^  \w|^\w).|\n)*", project, re.M)
        block = match.group() if match else ""
    else:
        schemes = project[project.index("schemes:"):]
        offset = schemes.find("  " + name + ":")
        block = schemes[offset:] if offset >= 0 else ""
    if hashlib.sha256(block.encode()).hexdigest() != fingerprint:
        changed.append(section)
if changed:
    raise SystemExit("Frozen iOS project settings changed:\n" + "\n".join(changed))
design_path = root / "verification/ios-protected-design-sha256.json"
if design_path.exists():
    for region in json.loads(design_path.read_text())["regions"]:
        source = (root / region["file"]).read_text()
        start = source.find(region["start"])
        end = source.find(region["end"], start)
        body = source[start:end] if start >= 0 and end > start else ""
        if hashlib.sha256(body.encode()).hexdigest() != region["sha256"]:
            raise SystemExit(f"Protected shared palette/composer design changed: {region['file']} ({region['start']})")
    print("Verified the current shared palette and original composer button surfaces.")
print(f"Verified {len(set(expected) - allowed)} unchanged iOS source, test, asset, and distribution files.")
if allowed: print(f"User-authorized iOS scope: {len(allowed)} Swift files ({len(network_allowed)} connectivity); original baseline retained.")
print("Verified unchanged iOS targets and release scheme.")
