#!/usr/bin/env python3
"""CBS thin wrapper around the standalone CBP binary gate."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "cbp-action" / "src"))
from cbp.binary_gate import run  # noqa: E402
from cbp.config import load_config  # noqa: E402


def main() -> int:
    passed, detail = run(load_config(ROOT, None))
    print(("BINARY_PROVENANCE_OK: " if passed else "BINARY_PROVENANCE_FAILED: ") + detail)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
