#!/usr/bin/env python3
"""Run the 25-item CBS quality matrix and write FINAL_QA_REPORT.md.

This runner does not fake a green result. A skipped or failed item is BLOCKED
or FAIL, and the signing gate refuses to sign unless every item is PASS.
"""
from __future__ import annotations

import argparse
import json
import re
import secrets
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MATRIX = ROOT / "quality" / "quality_matrix.json"
TEST_FILE = "quality/tests/test_quality_matrix.py"
REPORT = ROOT / "FINAL_QA_REPORT.md"

TEST_NAMES = {
    "Q01": "test_q01_path_boundaries_and_unicode",
    "Q02": "test_q02_webui_hostile_input",
    "Q03": "test_q03_totp_replay_and_concurrency",
    "Q04": "test_q04_broker_config_tamper_fallback",
    "Q05": "test_q05_broker_death_agent_unavailable",
    "Q06": "test_q06_wfp_heartbeat_45_seconds",
    "Q07": "test_q07_disk_full_capacity_breaker",
    "Q08": "test_q08_service_acl_loss",
    "Q09": "test_q09_1000_request_handle_leak",
    "Q10": "test_q10_one_hour_memory_soak",
    "Q11": "test_q11_orphan_process_scan",
    "Q12": "test_q12_toctou_snapshot_mismatch",
    "Q13": "test_q13_trash_acl_bypass",
    "Q14": "test_q14_service_privilege_escalation",
    "Q15": "test_q15_clean_uninstall_residue",
    "Q16": "test_q16_offline_wheelhouse_python_free",
    "Q17": "test_q17_interrupted_install_resume",
    "Q18": "test_q18_no_unresolved_placeholders",
    "Q19": "test_q19_qr_uri_matches_broker_secret",
    "Q20": "test_q20_version_single_source",
    "Q21": "test_q21_log_newline_injection",
    "Q22": "test_q22_port_conflict_preflight",
    "Q23": "test_q23_audit_chain_detects_tamper",
    "Q24": "test_q24_package_has_no_dev_artifacts",
    "Q25": "test_q25_matrix_has_25_items",
    "Q26": "test_q26_sbom_matches_actual_package",
}


def run_pytest() -> dict[str, str]:
    command = [
        sys.executable, "-m", "pytest", "-v", "--tb=no", "--no-header",
        TEST_FILE,
    ]
    try:
        completed = subprocess.run(
            command, cwd=ROOT, capture_output=True, text=True, timeout=1800
        )
    except FileNotFoundError:
        return {item: "blocked" for item in TEST_NAMES}
    output = completed.stdout + "\n" + completed.stderr
    statuses: dict[str, str] = {}
    for item, test_name in TEST_NAMES.items():
        match = re.search(
            re.escape(test_name) + r"\s+(PASSED|FAILED|SKIPPED|ERROR)",
            output,
        )
        statuses[item] = match.group(1).lower() if match else "blocked"
    if "FAILED" in output:
        print(output[-6000:])
    if completed.returncode not in (0, 1) and not any(
        status == "passed" for status in statuses.values()
    ):
        statuses = {item: "blocked" for item in TEST_NAMES}
    return statuses


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--nonce", default="")
    args = parser.parse_args()
    nonce = args.nonce or secrets.token_hex(16)
    matrix = json.loads(MATRIX.read_text(encoding="utf-8"))
    statuses = run_pytest()
    rows = []
    for item in matrix["items"]:
        status = statuses.get(item["id"], "blocked")
        rows.append((item["id"], item["title"], item["kind"], status))
    total = len(rows)
    passed = sum(1 for row in rows if row[3] == "passed")
    failed = sum(1 for row in rows if row[3] in {"failed", "error"})
    covered = sum(1 for row in rows if row[3] == "covered")
    blocked = total - passed - failed - covered
    overall = "PASS" if passed == total else ("FAIL" if failed else "BLOCKED")
    lines = [
        "# FINAL QA REPORT",
        "",
        f"- Version: {matrix['version']}",
        f"- Nonce: {nonce}",
        f"- Generated: {datetime.now(timezone.utc).isoformat(timespec='seconds')}",
        f"- Matrix: {total} items",
        f"- Passed: {passed}",
        f"- Failed: {failed}",
        f"- Covered: {covered}",
        f"- Blocked: {blocked}",
        f"- Overall: **{overall}**",
        "",
        "> A skipped/blocked item is not a pass. The signing gate requires every",
        "> row below to be PASS.",
        "",
        "| ID | Check | Type | Status |",
        "|---|---|---|---|",
    ]
    for item_id, title, kind, status in rows:
        lines.append(f"| {item_id} | {title} | {kind} | {status} |")
    lines += [
        "",
        "## Signing gate",
        "",
        "`tools/sign_release.py` refuses to sign unless this report is PASS.",
        "",
    ]
    REPORT.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {REPORT}")
    print(f"overall={overall} passed={passed} failed={failed} blocked={blocked}")
    print("STATUSES " + ",".join(f"{item_id}={status}" for item_id, _title, _kind, status in rows))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
