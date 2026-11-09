#!/usr/bin/env python3
"""Mock CBP CLI used by the reusable workflow before CBP --rules-path exists."""
import json, os, sys
from pathlib import Path

mode = os.environ.get("MOCK_MODE", "pass")
status = {"pass": "PASS", "cbp-fail": "FAIL", "infra": "SKIPPED_INFRA",
          "skip-over": "PASS"}.get(mode, "PASS")
skip = 5 if mode == "skip-over" else 0
ratio = 0.25 if mode == "skip-over" else 0.0
exit_code = {"pass": 0, "cbp-fail": 3, "infra": 3, "skip-over": 4}.get(mode, 0)
report = {
    "schema_version": "1", "package_id": "cbs", "version": "v1.7.0",
    "gate_status": status, "applicable_gate_count": 20, "skip_count": skip,
    "skip_ratio": ratio, "blocking_skip": False,
    "gates": [{"name": "encoding", "status": "PASS", "reason": ""}],
    "artifact_hashes": {}, "release_body_hash": "c" * 64,
    "evidence_sha256": "d" * 64,
}
out = os.environ.get("CBP_REPORT", "quality-manifest.json")
Path(out).write_text(json.dumps(report), encoding="utf-8")
print(f"CBP_MOCK status={status} exit={exit_code}")
sys.exit(exit_code)
