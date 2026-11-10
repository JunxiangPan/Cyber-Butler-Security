#!/usr/bin/env python3
"""CBP coverage gate: critical Broker paths must stay above 80 percent."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = (
    "tests/test_broker_body.py",
    "tests/test_broker_policy.py",
    "tests/test_broker_workspace_policy.py",
    "tests/test_critical_integrity.py",
    "tests/test_totp_replay.py",
    "tests/test_broker_manifest.py",
    "tests/test_broker_http_inprocess.py",
    "tests/test_broker_state_machine.py",
    "tests/test_broker_job_object.py",
    "tests/test_broker_store_helpers.py",
    "tests/test_broker_misc_helpers.py",
    "tests/test_broker_email_branch.py",
)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="cbp-coverage-") as temp:
        data = Path(temp) / ".coverage"
        env = dict(os.environ)
        env["COVERAGE_FILE"] = str(data)
        run = subprocess.run(
            [sys.executable, "-m", "coverage", "run", "--source=.", "-m", "pytest", "-q", *TESTS,
             "--basetemp", str(Path(temp) / "pytest"), "-p", "no:cacheprovider"],
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env,
        )
        report = subprocess.run(
            [sys.executable, "-m", "coverage", "json", "-o", str(Path(temp) / "coverage.json"),
             "--include=tools/broker.py,tools/broker_state.py,tools/broker_store.py"],
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env,
        )
        json_text = (Path(temp) / "coverage.json").read_text(encoding="utf-8") if report.returncode == 0 else ""
    if run.returncode != 0:
        print(run.stdout + run.stderr, file=sys.stderr)
        print("COVERAGE_FAILED: tests did not pass", file=sys.stderr)
        return 1
    if report.returncode != 0:
        print(report.stdout + report.stderr, file=sys.stderr)
        print("COVERAGE_FAILED: no report", file=sys.stderr)
        return 1
    try:
        data = json.loads(json_text)
        percent = float(data["totals"]["percent_covered"])
    except (ValueError, KeyError) as exc:
        print(f"COVERAGE_FAILED: unreadable report: {exc}", file=sys.stderr)
        return 1
    print(f"BROKER_COVERAGE={percent:.2f}")
    if percent <= 80.0:
        print("COVERAGE_FAILED: Broker coverage must be > 80% (precise)", file=sys.stderr)
        return 1
    print("COVERAGE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
