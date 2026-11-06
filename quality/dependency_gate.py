#!/usr/bin/env python3
"""CBS thin wrapper around the standalone CBP dependency gate."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
from cbp.config import load_config  # noqa: E402
from cbp.dependency_gate import run  # noqa: E402


def main() -> int:
    passed, detail = run(load_config(ROOT, ROOT / "cbp.json"))
    print(("DEPENDENCY_GATE_OK: " if passed else "DEPENDENCY_GATE_FAILED: ") + detail)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
