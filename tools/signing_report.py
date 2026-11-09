#!/usr/bin/env python3
"""Create/verify the signing report without modifying BUILD_REPORT.md."""
from __future__ import annotations
import argparse, json, sys
from datetime import datetime, timezone
from pathlib import Path
try:
    from .jcs import payload_sha256
except ImportError:
    from jcs import payload_sha256

def payload_hash(freeze: dict) -> str:
    """Return the canonical hash of the freeze payload."""
    return payload_sha256(freeze)

def main() -> int:
    """Create or verify the signing report."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--freeze", default="pre-build-freeze.json")
    parser.add_argument("--report", default="signing-report.json")
    parser.add_argument("--create", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    freeze_path = Path(args.freeze)
    if not freeze_path.is_file():
        print("SIGNING_INPUT_ERROR freeze missing", file=sys.stderr)
        return 2
    try:
        freeze = json.loads(freeze_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"SIGNING_INPUT_ERROR {exc}", file=sys.stderr)
        return 2
    expected = payload_hash(freeze)
    report_path = Path(args.report)
    if args.create:
        report = {
            "stage": "signed",
            "signed_at": datetime.now(timezone.utc).isoformat(),
            "signed_by": {
                "environment": "release-signing",
                "run_id": str(__import__("os").environ.get("GITHUB_RUN_ID", "")),
                "commit": str(__import__("os").environ.get("GITHUB_SHA", "")),
            },
            "payload_sha256": expected,
        }
        report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print("SIGNING_REPORT_CREATED", report_path)
        return 0
    if args.verify:
        try:
            report = json.loads(report_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            print(f"SIGNING_INPUT_ERROR {exc}", file=sys.stderr)
            return 2
        if report.get("stage") != "signed" or report.get("payload_sha256") != expected:
            print("SIGNING_REPORT_MISMATCH", file=sys.stderr)
            return 3
        print("SIGNING_REPORT_OK")
        return 0
    parser.error("--create or --verify required")
    return 2

if __name__ == "__main__":
    raise SystemExit(main())
