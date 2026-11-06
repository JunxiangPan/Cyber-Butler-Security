#!/usr/bin/env python3
"""CBS thin wrapper around the standalone CBP docs-history gate."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
from cbp.config import load_config  # noqa: E402
from cbp.docs_gate import run  # noqa: E402


def main() -> int:
    passed, detail = run(load_config(ROOT, ROOT / "cbp.json"))
    print(("DOCS_HISTORY_OK: " if passed else "DOCS_HISTORY_FAILED: ") + detail)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
