#!/usr/bin/env python3
"""P1-07: machine-checked publish gate for the v1.7 release train."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REQUIRED = {
    "main_ci": "success",
    "precondition_status": "PASS",
    "cbe_gate_status": "PASS",
    "cbp_gate_status": "PASS",
    "skip_ok": True,
}


def evaluate(report: dict) -> tuple[bool, list[str]]:
    problems = []
    for key, expected in REQUIRED.items():
        if report.get(key) != expected:
            problems.append(f"{key}={report.get(key)!r} expected {expected!r}")
    if report.get("tag_commit") != report.get("ci_commit"):
        problems.append("tag_commit != ci_commit")
    if report.get("rebuilt") is True:
        problems.append("publish rebuilt the artifact")
    return not problems, problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    report = json.loads(Path(args.report).read_text(encoding="utf-8"))
    ok, problems = evaluate(report)
    for problem in problems:
        print("PUBLISH_BLOCKED", problem, file=sys.stderr)
    print("PUBLISH_ALLOWED" if ok else "PUBLISH_BLOCKED")
    return 0 if ok else 3


if __name__ == "__main__":
    raise SystemExit(main())
