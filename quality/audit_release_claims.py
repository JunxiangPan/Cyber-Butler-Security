#!/usr/bin/env python3
"""Reconcile release-note claims with the machine-generated quality manifest.

Release notes may not hand-write a total. They must contain a
`QUALITY_COUNTS: <passed>/<total>` line generated from the manifest, and that
value must match the manifest exactly.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOKEN = re.compile(r"(?m)^QUALITY_COUNTS:\s*(\d+)/(\d+)\s*$")
HANDWRITTEN = re.compile(r"(?<![\w/])26\s*/\s*26(?![\w/])")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--notes", default=str(ROOT / "docs" / "releases" / "RELEASE_NOTES_v1.6.4.md"))
    parser.add_argument("--manifest", default=str(ROOT / "quality-manifest.json"))
    args = parser.parse_args()
    notes = Path(args.notes)
    manifest = Path(args.manifest)
    if not notes.is_file():
        print("RELEASE_CLAIMS_FAILED: release notes are missing: " + str(notes))
        return 1
    if not manifest.is_file():
        print("RELEASE_CLAIMS_FAILED: quality-manifest.json is missing")
        return 1
    data = json.loads(manifest.read_text(encoding="utf-8"))
    counts = data.get("counts", {})
    expected = f"{counts.get('passed', -1)}/{counts.get('total', -1)}"
    text = notes.read_text(encoding="utf-8")
    tokens = TOKEN.findall(text)
    if len(tokens) != 1:
        print("RELEASE_CLAIMS_FAILED: notes need exactly one QUALITY_COUNTS line")
        return 1
    actual = f"{tokens[0][0]}/{tokens[0][1]}"
    if actual != expected:
        print(f"RELEASE_CLAIMS_FAILED: notes {actual} != manifest {expected}")
        return 1
    handwritten = [match.group(0) for match in HANDWRITTEN.finditer(text)]
    if handwritten:
        print("RELEASE_CLAIMS_FAILED: handwritten 26-item claims are forbidden: " + ",".join(handwritten))
        return 1
    if data.get("profile") == "release" and int(counts.get("passed", 0)) != 26:
        print("RELEASE_CLAIMS_FAILED: release profile is not 26/26")
        return 1
    print(f"RELEASE_CLAIMS_OK: {actual} matches quality-manifest.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
