#!/usr/bin/env python3
"""Parse CBE/CBP JSON reports and enforce F1/F2/F3/F5."""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=("cbe", "cbp"), required=True)
    parser.add_argument("--report", required=True)
    args = parser.parse_args()
    try:
        data = json.loads(Path(args.report).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"REPORT_INPUT_ERROR {exc}", file=sys.stderr)
        return 2
    required = {
        "cbe": {"schema_version", "gate_status", "exit_code", "applicable_count",
                "skip_count", "skip_ratio", "blocking_skip", "warn_count"},
        "cbp": {"schema_version", "gate_status", "applicable_gate_count",
                "skip_count", "skip_ratio", "blocking_skip", "gates"},
    }[args.kind]
    missing = sorted(required - set(data))
    if missing:
        print("REPORT_INPUT_ERROR missing=" + ",".join(missing), file=sys.stderr)
        return 2
    if data["schema_version"] != "1":
        print("REPORT_INPUT_ERROR schema_version", file=sys.stderr)
        return 2
    status = data["gate_status"]
    if status not in {"PASS", "FAIL", "SKIPPED_INFRA", "PRECONDITION_FAIL"}:
        print("REPORT_INPUT_ERROR gate_status", file=sys.stderr)
        return 2
    if status == "SKIPPED_INFRA":
        print("GATE_STATUS=SKIPPED_INFRA"); print("PUBLISH=0"); return 3
    if float(data["skip_ratio"]) > 0.20:
        print("GATE_STATUS=FAIL"); print("PUBLISH=0"); print("SKIP_OVER=1"); return 4
    if data.get("blocking_skip"):
        print("GATE_STATUS=FAIL"); print("PUBLISH=0"); print("BLOCKING_SKIP=1"); return 3
    if status != "PASS":
        print(f"GATE_STATUS={status}"); print("PUBLISH=0"); return 3
    print("GATE_STATUS=PASS"); print("PUBLISH=1")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
