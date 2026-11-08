#!/usr/bin/env python3
"""Run the signing gate without touching the private key."""
from __future__ import annotations

from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sign_release import require_gate


def main() -> int:
    """Validate the staged release artifact against the challenge."""
    challenge = sys.argv[1] if len(sys.argv) > 1 else ""
    if not challenge:
        raise SystemExit("challenge required")
    require_gate(Path("."), challenge)
    print("SIGN_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
