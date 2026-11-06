#!/usr/bin/env python3
"""Generate the CBP quality manifest and FINAL_QA_REPORT from real test results.

The JSON manifest is the source of truth. Counts are computed from item rows;
the Markdown report is rendered from the same rows and must not be hand-edited.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import secrets
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ITEMS = ROOT / "quality" / "quality-items.json"
MANIFEST = ROOT / "quality-manifest.json"
MANIFEST_HASH = ROOT / "quality-manifest.sha256"
REPORT = ROOT / "FINAL_QA_REPORT.md"
TEST_FILE = "quality/tests/test_quality_matrix.py"

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


def run_pytest() -> tuple[dict[str, str], str]:
    command = [
        sys.executable, "-m", "pytest", "-v", "--tb=no", "--no-header",
        TEST_FILE,
    ]
    try:
        completed = subprocess.run(
            command, cwd=ROOT, capture_output=True, text=True, timeout=1800
        )
    except FileNotFoundError:
        return {item: "blocked" for item in TEST_NAMES}, "pytest not found"
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
    return statuses, f"pytest_exit={completed.returncode}"


def _gate_status(script: str) -> str:
    """Run one CBP gate and return PASS or FAIL for the quality manifest."""
    result = subprocess.run([sys.executable, str(ROOT / "quality" / script)], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return "PASS" if result.returncode == 0 else "FAIL"


def summarize(items: list[dict], statuses: dict[str, str], profile: str) -> dict:
    rows = []
    for item in items:
        item_id = str(item["id"])
        raw = statuses.get(item_id, "blocked")
        if profile == "ci" and item["class"] != "ci":
            raw = "skipped-by-design"
        elif raw == "skipped":
            raw = "blocked"
        if raw in {"failed", "error"}:
            raw = "failed"
        rows.append({**item, "status": raw})
    passed = sum(1 for row in rows if row["status"] == "passed")
    failed = sum(1 for row in rows if row["status"] == "failed")
    blocked = sum(1 for row in rows if row["status"] == "blocked")
    skipped_by_design = sum(1 for row in rows if row["status"] == "skipped-by-design")
    required = [row for row in rows if profile == "release" or row["class"] == "ci"]
    if failed:
        overall = "FAIL"
    elif any(row["status"] != "passed" for row in required):
        overall = "BLOCKED"
    else:
        overall = "PASS"
    return {
        "rows": rows,
        "counts": {
            "total": len(rows),
            "passed": passed,
            "failed": failed,
            "blocked": blocked,
            "skipped_by_design": skipped_by_design,
        },
        "overall": overall,
    }


def render_report(manifest: dict, quality_manifest_sha256: str = "") -> str:
    counts = manifest["counts"]
    lines = [
        "# FINAL QA REPORT",
        "",
        f"- Version: {manifest['version']}",
        f"- Nonce: {manifest['nonce']}",
        f"- Profile: {manifest['profile']}",
        f"- Generated: {manifest['generated_at']}",
        f"- Matrix: {counts['total']} items",
        f"- Passed: {counts['passed']}",
        f"- Failed: {counts['failed']}",
        f"- Blocked: {counts['blocked']}",
        f"- Skipped by design: {counts['skipped_by_design']}",
        f"- Overall: **{manifest['overall']}**",
        "",
    ]
    if quality_manifest_sha256:
        lines.append(f"QUALITY_MANIFEST_SHA256: {quality_manifest_sha256}")
        lines.append("")
    lines += [
        "> A blocked item is not a pass. The release signing gate requires 26/26",
        "> passed items and a valid quality-manifest.json.",
        "",
        "| ID | Check | Type | Status |",
        "|---|---|---|---|",
    ]
    for row in manifest["items"]:
        lines.append(f"| {row['id']} | {row['title']} | {row['kind']} | {row['status']} |")
    lines += ["", "## Signing gate", "", "`tools/sign_release.py` re-reads quality-manifest.json and refuses blocked/failed items.", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--nonce", default="")
    parser.add_argument("--profile", choices=("ci", "release"), default="ci")
    args = parser.parse_args()
    nonce = args.nonce or secrets.token_hex(16)
    source = json.loads(ITEMS.read_text(encoding="utf-8"))
    statuses, pytest_source = run_pytest()
    result = summarize(source["items"], statuses, args.profile)
    manifest = {
        "schema": "cbp-quality-manifest/v1",
        "version": source["version"],
        "nonce": nonce,
        "profile": args.profile,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "source": {"pytest": pytest_source},
        "items": result["rows"],
        "counts": result["counts"],
        "overall": result["overall"],
        "dependency_gate_status": _gate_status("dependency_gate.py"),
        "comment_audit_status": _gate_status("audit_comments.py"),
        "binary_provenance_status": _gate_status("audit_binary_provenance.py"),
    }
    canonical = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    manifest_bytes = (canonical + chr(10)).encode("utf-8")
    digest = hashlib.sha256(manifest_bytes).hexdigest().upper()
    MANIFEST.write_bytes(manifest_bytes)
    MANIFEST_HASH.write_text(digest + chr(10), encoding="ascii")
    REPORT.write_text(render_report(manifest, digest), encoding="utf-8")
    print(f"wrote {REPORT}")
    print(f"wrote {MANIFEST}")
    print(f"overall={manifest['overall']} passed={manifest['counts']['passed']} failed={manifest['counts']['failed']} blocked={manifest['counts']['blocked']} skipped_by_design={manifest['counts']['skipped_by_design']}")
    print("STATUSES " + ",".join(f"{row['id']}={row['status']}" for row in manifest["items"]))
    return 0 if manifest["overall"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
