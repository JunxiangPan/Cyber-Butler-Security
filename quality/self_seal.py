#!/usr/bin/env python3
"""CBP self-seal: record and verify hashes of the pipeline's core scripts."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = (
    "tools/Run-ReleasePipeline.ps1",
    "tools/package_release.py",
    "tools/audit_text_hygiene.py",
    "tools/audit_code_comments.py",
    "tools/update_core.py",
    "tools/verify_release.py",
    "quality/preflight.py",
    "quality/test_guard.py",
    "quality/mutation_check.py",
    "quality/source_mutation_check.py",
    "quality/silent_failure_scan.py",
    "quality/coverage_gate.py",
    "quality/self_seal.py",
)


def hashes() -> dict[str, str]:
    """Return SHA-256 values for all existing core scripts."""
    result: dict[str, str] = {}
    for relative in CORE:
        path = ROOT / relative
        if path.is_file():
            result[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def main(argv: list[str]) -> int:
    """Record or verify the core-script seal."""
    if len(argv) < 3 or argv[1] not in {"--record", "--verify"}:
        print("usage: self_seal.py --record|--verify <path>", file=sys.stderr)
        return 2
    path = Path(argv[2])
    current = hashes()
    if argv[1] == "--record":
        path.write_text(json.dumps(current, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        print(f"SELF_SEAL_RECORDED files={len(current)}")
        return 0
    try:
        recorded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"SELF_SEAL_FAILED: cannot read seal: {exc}", file=sys.stderr)
        return 1
    if recorded != current:
        print("SELF_SEAL_FAILED: core scripts changed during the pipeline", file=sys.stderr)
        return 1
    print(f"SELF_SEAL_OK files={len(current)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
