#!/usr/bin/env python3
"""Check that the companion did not change the inherited iOS application."""
import hashlib
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
expected = json.loads((root / "verification/ios-source-sha256.json").read_text())
changed = []
for name, fingerprint in expected.items():
    path = root / name
    if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != fingerprint:
        changed.append(name)
if changed:
    raise SystemExit("Frozen iOS files changed:\n" + "\n".join(changed))
project = (root / "project.yml").read_text()
project_expected = json.loads((root / "verification/ios-project-sha256.json").read_text())
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
print(f"Verified {len(expected)} unchanged iOS source, test, asset, and distribution files.")
print("Verified unchanged iOS targets and release scheme.")
