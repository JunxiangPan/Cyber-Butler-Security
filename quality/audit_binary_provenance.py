#!/usr/bin/env python3
"""CBS thin wrapper around the standalone CBP binary gate."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
from cbp.binary_gate import run  # noqa: E402
from cbp.config import load_config  # noqa: E402


def main() -> int:
    passed, detail = run(load_config(ROOT, ROOT / "cbp.json"))
    print(("BINARY_PROVENANCE_OK: " if passed else "BINARY_PROVENANCE_FAILED: ") + detail)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
