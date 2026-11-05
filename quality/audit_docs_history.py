#!/usr/bin/env python3
"""Block packaging when the incident-history corpus is deleted or altered.

The manifest is the expected state for the six v1.6.2/v1.6.3 postmortems.
This gate is intentionally narrow: it protects documented operational lessons,
not arbitrary documentation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs" / "history-manifest.json"
EXPECTED = {
    "docs/40-history/incidents/acl-self-lock.md",
    "docs/40-history/incidents/s4u-retirement.md",
    "docs/40-history/incidents/sqlite-readonly.md",
    "docs/40-history/incidents/task-rollback.md",
    "docs/40-history/incidents/v1.6.3-fake-qa-report.md",
    "docs/40-history/incidents/wfp-empty-rules.md",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=str(ROOT))
    args = parser.parse_args()
    root = Path(args.root)
    manifest = root / "docs" / "history-manifest.json"
    if not manifest.is_file():
        print("DOCS_HISTORY_FAILED: docs/history-manifest.json is missing")
        return 1
    data = json.loads(manifest.read_text(encoding="utf-8"))
    entries = {entry["path"]: entry["sha256"].upper() for entry in data.get("files", [])}
    missing = sorted(EXPECTED - set(entries))
    extra = sorted(set(entries) - EXPECTED)
    if missing or extra:
        print("DOCS_HISTORY_FAILED: manifest key set changed")
        for path in missing:
            print("  missing: " + path)
        for path in extra:
            print("  unexpected: " + path)
        return 1
    for path in sorted(EXPECTED):
        target = root / path
        if not target.is_file():
            print("DOCS_HISTORY_FAILED: missing file " + path)
            return 1
        raw = target.read_bytes().replace(bytes([13, 10]), bytes([10]))
        digest = hashlib.sha256(raw).hexdigest().upper()
        if digest != entries[path]:
            print("DOCS_HISTORY_FAILED: hash changed " + path)
            return 1
    print(f"DOCS_HISTORY_OK: {len(EXPECTED)} incident files match the manifest")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
