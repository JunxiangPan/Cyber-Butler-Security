#!/usr/bin/env python3
"""CBP coverage gate: critical Broker paths must stay above 80 percent."""
from __future__ import annotations

import os
import re
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
            [sys.executable, "-m", "coverage", "report", "--include=tools/broker.py,tools/broker_state.py,tools/broker_store.py"],
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env,
        )
    if run.returncode != 0:
        print(run.stdout + run.stderr, file=sys.stderr)
        print("COVERAGE_FAILED: tests did not pass", file=sys.stderr)
        return 1
    match = re.search(r"TOTAL\s+\d+\s+\d+\s+(\d+(?:\.\d+)?)%", report.stdout)
    if not match:
        print(report.stdout + report.stderr, file=sys.stderr)
        print("COVERAGE_FAILED: no report", file=sys.stderr)
        return 1
    percent = float(match.group(1))
    print(f"BROKER_COVERAGE={percent:.2f}")
    if percent <= 80.0:
        print("COVERAGE_FAILED: Broker coverage must be > 80%", file=sys.stderr)
        return 1
    print("COVERAGE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
