from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from quality.run_quality_matrix import render_report, summarize  # noqa: E402

ITEMS = json.loads((ROOT / "quality" / "quality-items.json").read_text(encoding="utf-8"))["items"]


def test_counts_are_physically_recomputed():
    statuses = {item["id"]: "passed" for item in ITEMS}
    result = summarize(ITEMS, statuses, "release")
    assert result["counts"] == {"total": 26, "passed": 26, "failed": 0, "blocked": 0, "skipped_by_design": 0}
    assert result["overall"] == "PASS"


def test_one_blocked_item_blocks_release():
    statuses = {item["id"]: "passed" for item in ITEMS}
    statuses["Q05"] = "skipped"
    result = summarize(ITEMS, statuses, "release")
    assert result["counts"]["blocked"] == 1
    assert result["overall"] == "BLOCKED"


def test_ci_skips_vm_by_design_without_marking_them_passed():
    statuses = {item["id"]: "passed" for item in ITEMS}
    for item in ITEMS:
        if item["class"] != "ci":
            statuses[item["id"]] = "skipped"
    result = summarize(ITEMS, statuses, "ci")
    assert result["counts"]["skipped_by_design"] == 14
    assert result["counts"]["passed"] == 12
    assert result["overall"] == "PASS"


def test_report_header_matches_manifest_counts():
    statuses = {item["id"]: "passed" for item in ITEMS}
    result = summarize(ITEMS, statuses, "release")
    manifest = {"version": "1.6.3", "nonce": "A-READY-TEST-0001", "profile": "release", "generated_at": "2026-11-06T00:00:00Z", "items": result["rows"], "counts": result["counts"], "overall": result["overall"]}
    report = render_report(manifest)
    assert "- Passed: 26" in report
    assert "- Blocked: 0" in report
    assert "| Q01 |" in report
    assert "| Q26 |" in report


def test_template_wrongly_claiming_26_with_blocked_is_detectable():
    statuses = {item["id"]: "passed" for item in ITEMS}
    for item in ITEMS:
        if item["class"] != "ci":
            statuses[item["id"]] = "skipped"
    result = summarize(ITEMS, statuses, "release")
    assert result["counts"]["blocked"] == 14
    assert result["overall"] == "BLOCKED"
