#!/usr/bin/env python3
"""Mock CBE CLI used by the reusable workflow before CBE exists."""
import json, os, sys
from pathlib import Path

mode = os.environ.get("MOCK_MODE", "pass")
status = {"pass": "PASS", "cbe-fail": "FAIL", "infra": "SKIPPED_INFRA"}.get(mode, "PASS")
exit_code = {"pass": 0, "cbe-fail": 3, "infra": 3}.get(mode, 0)
report = {
    "schema_version": "1", "package_id": "cbe", "version": "v1.7.0",
    "tag": "v1.7.0", "gate_status": status, "exit_code": exit_code,
    "applicable_count": 4, "skip_count": 0, "skip_ratio": 0.0,
    "blocking_skip": False, "warn_count": 0,
    "rules_manifest_hash": "a" * 64, "sarif_paths": ["mock.sarif"],
    "evidence_sha256": "b" * 64,
}
out = os.environ.get("CBE_REPORT", "cbe-report.json")
Path(out).write_text(json.dumps(report), encoding="utf-8")
print(f"CBE_MOCK status={status} exit={exit_code}")
sys.exit(exit_code)
