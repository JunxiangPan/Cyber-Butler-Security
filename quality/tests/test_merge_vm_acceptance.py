"""Tests for the VM proof merge tool. No BUILD_REPORT is consulted."""
from __future__ import annotations

import hashlib
import shutil
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import merge_vm_acceptance as merge_tool

NONCE = "A-READY-20261105-0145"
WHITELIST = ("Q05", "Q06", "Q07", "Q08", "Q09", "Q10", "Q11", "Q13", "Q14", "Q15", "Q16", "Q17")
BLACKLIST = ("Q02", "Q18", "Q22")


def proof(nonce: str = NONCE, bad_start: bool = False) -> str:
    start = "A" * 64
    end = "B" * 64 if bad_start else start
    return f"""# ACCEPTANCE_PROOF
- Nonce: {nonce}
Overall: PASS
negative_403=True
negative_path=True
script_immutable=True
- Acceptance script SHA256 (start): {start}
- Acceptance script SHA256 (end): {end}
"""


def qa(nonce: str = NONCE, pass_all: bool = False, mutate_black: bool = False, skipped_count: int = 15) -> str:
    statuses = {}
    for item in ("Q01", "Q03", "Q04", "Q12", "Q19", "Q20", "Q21", "Q23", "Q24", "Q25"):
        statuses[item] = "passed"
    skipped = [x for x in ("Q05", "Q06", "Q07", "Q08", "Q09", "Q10", "Q11", "Q13", "Q14", "Q15", "Q16", "Q17", "Q02", "Q18", "Q22")]
    if skipped_count != 15:
        skipped = skipped[:skipped_count]
    for item in skipped:
        statuses[item] = "passed" if pass_all else "skipped"
    if mutate_black:
        statuses["Q02"] = "passed"
        statuses["Q01"] = "skipped"
    rows = ["| ID | Check | Type | Status |", "|---|---|---|---|"]
    for index in range(1, 26):
        item = f"Q{index:02d}"
        rows.append(f"| {item} | check {item} | unit | {statuses.get(item, 'passed')} |")
    return f"""# FINAL QA REPORT
- Nonce: {nonce}
Overall: **BLOCKED**

{chr(10).join(rows)}
"""


def setup(tmp_path: Path, proof_text: str | None = None, qa_text: str | None = None) -> tuple[Path, Path, Path]:
    p = tmp_path / "ACCEPTANCE_PROOF.md"
    q = tmp_path / "FINAL_QA_REPORT.md"
    b = tmp_path / "BUILD_REPORT.md"
    p.write_text(proof_text if proof_text is not None else proof(), encoding="utf-8", newline="")
    q.write_text(qa_text if qa_text is not None else qa(), encoding="utf-8", newline="")
    b.write_text("BUILD_SENTINEL\n", encoding="utf-8", newline="")
    return p, q, b


def test_v1_missing_proof(tmp_path: Path) -> None:
    p = tmp_path / "ACCEPTANCE_PROOF.md"
    with pytest.raises(merge_tool.MergeError, match="missing or empty"):
        merge_tool.verify_proof(p)


def test_v2_proof_not_pass(tmp_path: Path) -> None:
    p, _q, _b = setup(tmp_path, proof_text=proof().replace("Overall: PASS", "Overall: BLOCKED"))
    with pytest.raises(merge_tool.MergeError, match="not Overall: PASS"):
        merge_tool.verify_proof(p)


def test_v3_missing_negative_403(tmp_path: Path) -> None:
    p, _q, _b = setup(tmp_path, proof_text=proof().replace("negative_403=True\n", ""))
    with pytest.raises(merge_tool.MergeError, match="negative_403=True"):
        merge_tool.verify_proof(p)


def test_v4_missing_script_immutable(tmp_path: Path) -> None:
    p, _q, _b = setup(tmp_path, proof_text=proof().replace("script_immutable=True\n", ""))
    with pytest.raises(merge_tool.MergeError, match="script_immutable=True"):
        merge_tool.verify_proof(p)


def test_v5_start_end_mismatch(tmp_path: Path) -> None:
    p, _q, _b = setup(tmp_path, proof_text=proof(bad_start=True))
    with pytest.raises(merge_tool.MergeError, match="script SHA256 changed"):
        merge_tool.verify_proof(p)


def test_v6_valid_proof(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    p, _q, _b = setup(tmp_path)
    nonce = merge_tool.verify_proof(p)
    out = capsys.readouterr().out
    assert nonce == NONCE
    assert "PROOF_VERIFIED" in out
    assert "PROOF_SHA256=" + hashlib.sha256(p.read_bytes()).hexdigest().upper() in out


def test_m1_nonce_mismatch(tmp_path: Path) -> None:
    p, q, _b = setup(tmp_path)
    with pytest.raises(merge_tool.MergeError, match="does not match --nonce"):
        merge_tool.merge(p, "WRONGNONCE123456", q)


def test_m2_qa_nonce_mismatch(tmp_path: Path) -> None:
    p, q, _b = setup(tmp_path, qa_text=qa(nonce="OTHER-NONCE-123456"))
    with pytest.raises(merge_tool.MergeError, match="does not match FINAL_QA_REPORT"):
        merge_tool.merge(p, NONCE, q)


def test_m3_already_pass(tmp_path: Path) -> None:
    p, q, _b = setup(tmp_path, qa_text=qa().replace("**BLOCKED**", "**PASS**"))
    with pytest.raises(merge_tool.MergeError, match="not BLOCKED"):
        merge_tool.merge(p, NONCE, q)


def test_m4_wrong_skipped_count(tmp_path: Path) -> None:
    p, q, _b = setup(tmp_path, qa_text=qa(skipped_count=14))
    with pytest.raises(merge_tool.MergeError, match="expected 15"):
        merge_tool.merge(p, NONCE, q)


def test_m5_blacklist_changed(tmp_path: Path) -> None:
    p, q, _b = setup(tmp_path, qa_text=qa(mutate_black=True))
    with pytest.raises(merge_tool.MergeError, match="Q02 is not skipped"):
        merge_tool.merge(p, NONCE, q)


def test_m6_valid_merge(tmp_path: Path) -> None:
    p, q, b = setup(tmp_path)
    before_build = b.read_bytes()
    merge_tool.merge(p, NONCE, q)
    assert q.read_text(encoding="utf-8").count("| passed |") == 22
    assert b.read_bytes() == before_build


def test_m7_twelve_whitelist_changed(tmp_path: Path) -> None:
    p, q, _b = setup(tmp_path)
    merge_tool.merge(p, NONCE, q)
    text = q.read_text(encoding="utf-8")
    for item in WHITELIST:
        assert f"| {item} | check {item} | unit | passed |" in text


def test_m8_blacklist_unchanged(tmp_path: Path) -> None:
    p, q, _b = setup(tmp_path)
    merge_tool.merge(p, NONCE, q)
    text = q.read_text(encoding="utf-8")
    for item in BLACKLIST:
        assert f"| {item} | check {item} | unit | skipped |" in text


def test_m9_overall_pass(tmp_path: Path) -> None:
    p, q, _b = setup(tmp_path)
    merge_tool.merge(p, NONCE, q)
    assert "Overall: **PASS**" in q.read_text(encoding="utf-8")


def test_m10_backup_matches_original(tmp_path: Path) -> None:
    p, q, _b = setup(tmp_path)
    original = q.read_bytes()
    merge_tool.merge(p, NONCE, q)
    backup = q.with_name(q.name + ".pre-vm-merge")
    assert backup.is_file()
    assert backup.read_bytes() == original


def test_m11_build_report_unchanged(tmp_path: Path) -> None:
    p, q, b = setup(tmp_path)
    before = b.read_bytes()
    merge_tool.merge(p, NONCE, q)
    assert b.read_bytes() == before
