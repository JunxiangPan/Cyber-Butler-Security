#!/usr/bin/env python3
"""Fail when a tracked text file contains a Git conflict marker."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

MARKERS = ("<" * 7, "=" * 7, ">" * 7)


def main() -> int:
    """Scan tracked UTF-8 files and return nonzero on any marker."""
    root = Path(__file__).resolve().parents[1]
    names = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z"]
    ).decode("utf-8").split("\0")
    findings: list[str] = []
    for name in names:
        if not name:
            continue
        path = root / name
        try:
            text = path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeDecodeError):
            continue
        for number, line in enumerate(text.splitlines(), 1):
            if line.startswith(MARKERS):
                findings.append(f"{name}:{number}: conflict marker")
    if findings:
        print("CONFLICT_MARKERS_FOUND")
        print("\n".join(findings))
        return 1
    print("CONFLICT_MARKER_GUARD_OK files=" + str(len(names)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
