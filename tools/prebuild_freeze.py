#!/usr/bin/env python3
"""Create/verify the two-phase CBS build freeze anchor."""
from __future__ import annotations
import argparse, hashlib, json, sys
from pathlib import Path
FILES = ("update-manifest.json", "BUILD_REPORT.md", "FINAL_QA_REPORT.md", "ACCEPTANCE_PROOF.md")

def hashes(root: Path) -> dict[str, str]:
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in FILES}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--create", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    root = Path(args.root)
    path = root / "pre-build-freeze.json"
    if args.create:
        missing = [name for name in FILES if not (root / name).is_file()]
        if missing:
            print("FREEZE_MISSING " + ",".join(missing), file=sys.stderr)
            return 2
        path.write_text(json.dumps(hashes(root), indent=2) + "\n", encoding="utf-8")
        print("FREEZE_CREATED", path)
        return 0
    if args.verify:
        try:
            expected = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"FREEZE_INPUT_ERROR {exc}", file=sys.stderr)
            return 2
        actual = hashes(root)
        if actual != expected:
            print("FREEZE_MISMATCH", file=sys.stderr)
            return 3
        print("FREEZE_OK")
        return 0
    parser.error("--create or --verify required")
    return 2

if __name__ == "__main__":
    raise SystemExit(main())
