#!/usr/bin/env python3
"""CBP supply-chain gate: runtime requirements must be hash-pinned."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIREMENTS = ROOT / "requirements-runtime.txt"


def main() -> int:
    """Reject unpinned runtime requirements."""
    if not REQUIREMENTS.is_file():
        print("DEPENDENCY_GATE_FAILED: requirements-runtime.txt missing", file=sys.stderr)
        return 1
    unpinned = []
    for line in REQUIREMENTS.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or stripped.startswith("--"):
            continue
        if "--hash=" not in stripped:
            unpinned.append(stripped)
    if unpinned:
        print("DEPENDENCY_GATE_FAILED: unpinned runtime requirements", file=sys.stderr)
        for item in unpinned:
            print("  " + item, file=sys.stderr)
        return 1
    print("DEPENDENCY_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
