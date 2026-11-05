#!/usr/bin/env python3
"""CBP coverage gate: enforce the measured, allowlisted coverage floor."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COVERAGE = ROOT / "coverage.json"
ALLOWLIST = ROOT / "coverage_allowlist.json"
POLICY_MIN = 85.0


def _norm(path: str) -> str:
    return path.replace("\\", "/")


def _allowed_lines(ranges: list[dict]) -> set[int]:
    allowed: set[int] = set()
    for item in ranges:
        start, end = item["lines"]
        allowed.update(range(int(start), int(end) + 1))
    return allowed


def main() -> int:
    if not COVERAGE.is_file():
        print("COVERAGE_FAILED: coverage.json is missing; run coverage before the gate")
        return 1
    if not ALLOWLIST.is_file():
        print("COVERAGE_FAILED: coverage_allowlist.json is missing")
        return 1
    data = json.loads(COVERAGE.read_text(encoding="utf-8"))
    allow = json.loads(ALLOWLIST.read_text(encoding="utf-8"))
    policy_file = "tools/broker_policy.py"
    policy = next((entry for key, entry in data["files"].items() if _norm(key) == policy_file), None)
    if policy is None:
        print("COVERAGE_FAILED: broker_policy.py not measured")
        return 1
    policy_pct = float(policy["summary"]["percent_covered"])
    if policy_pct < POLICY_MIN:
        print(f"COVERAGE_FAILED: broker_policy.py {policy_pct:.2f}% < {POLICY_MIN:.2f}%")
        return 1
    files_cfg = allow.get("files", {})
    broker = next((entry for key, entry in data["files"].items() if _norm(key) == "tools/broker.py"), None)
    if broker is None:
        print("COVERAGE_FAILED: broker.py not measured")
        return 1
    allowed = _allowed_lines(files_cfg.get("tools/broker.py", []))
    missing = [line for line in broker["missing_lines"] if line not in allowed]
    statements = int(broker["summary"]["num_statements"])
    covered = statements - len(missing)
    pct = (covered / statements * 100.0) if statements else 0.0
    threshold = float(allow.get("policy", {}).get("tools/broker.py", 70.0))
    print(f"BROKER_POLICY_COVERAGE={policy_pct:.2f}% (min {POLICY_MIN:.2f}%)")
    print(f"BROKER_COVERAGE_ALLOWLISTED={pct:.2f}% (min {threshold:.2f}%)")
    print(f"BROKER_ALLOWLISTED_LINES={len(broker['missing_lines']) - len(missing)}")
    if pct < threshold:
        print(f"COVERAGE_FAILED: broker.py {pct:.2f}% < {threshold:.2f}%")
        return 1
    print("COVERAGE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
