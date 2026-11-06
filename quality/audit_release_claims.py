#!/usr/bin/env python3
"""CBS thin wrapper around the standalone CBP claims gate."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "cbp-action" / "src"))
from cbp.claims_gate import run  # noqa: E402
from cbp.config import load_config  # noqa: E402


def main() -> int:
    passed, detail = run(load_config(ROOT, ROOT / "cbp.json"))
    print(("RELEASE_CLAIMS_OK: " if passed else "RELEASE_CLAIMS_FAILED: ") + detail)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
