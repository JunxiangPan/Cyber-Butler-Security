"""Seed rules: every rule has a negative and a positive executable test."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from cbp import custom_rules, upgrade_gate
from cbp.claims_gate import run as run_claims
from cbp.comment_gate import run as run_comments
from cbp.config import GateConfig
from cbp.coverage_gate import run as run_coverage
from cbp.dependency_gate import run as run_dependency
from cbp.docs_gate import run as run_docs


def _coverage(tmp_path: Path, percent: float, threshold: float) -> GateConfig:
    (tmp_path / "coverage.json").write_text(json.dumps({"files": {
        "src/a.py": {
            "summary": {"num_statements": 10, "covered_lines": int(percent / 10), "percent_covered": percent},
            "missing_lines": list(range(int(percent / 10) + 1, 11)),
        }
    }}), encoding="utf-8")
    (tmp_path / "coverage_allowlist.json").write_text('{"files": {}}', encoding="utf-8")
    return GateConfig(
        root=tmp_path,
        coverage_json="coverage.json",
        coverage_allowlist="coverage_allowlist.json",
        coverage_groups=({"name": "core", "files": ["src/a.py"], "threshold": threshold, "mode": "enforce"},),
    )


def test_rule_cov_001_negative(tmp_path) -> None:
    passed, _detail = run_coverage(_coverage(tmp_path, 50.0, 80.0))
    assert passed is False


def test_rule_cov_001_positive(tmp_path) -> None:
    passed, _detail = run_coverage(_coverage(tmp_path, 90.0, 80.0))
    assert passed is True


def _dependency(tmp_path: Path, include_hash: bool) -> GateConfig:
    lock = "pytest==9.2.0\n" + ("    --hash=sha256:" + "a" * 64 + "\n" if include_hash else "")
    (tmp_path / "requirements.lock").write_text(lock, encoding="utf-8")
    (tmp_path / "install.sh").write_text("#!/bin/sh\npip install --require-hashes -r requirements.lock\n", encoding="utf-8")
    return GateConfig(root=tmp_path, dependency_lock="requirements.lock", install_command="install.sh")


def test_rule_dep_001_negative(tmp_path) -> None:
    passed, _detail = run_dependency(_dependency(tmp_path, include_hash=False))
    assert passed is False


def test_rule_dep_001_positive(tmp_path) -> None:
    passed, _detail = run_dependency(_dependency(tmp_path, include_hash=True))
    assert passed is True


def _comments(tmp_path: Path, docstring: str) -> GateConfig:
    (tmp_path / "src.py").write_text(f'def public():\n    """{docstring}"""\n    return 1\n', encoding="utf-8")
    return GateConfig(root=tmp_path, comment_files=("src.py",))


def test_rule_cmt_001_negative(tmp_path) -> None:
    passed, _detail = run_comments(_comments(tmp_path, "This caller-supplied value is generic."))
    assert passed is False


def test_rule_cmt_001_positive(tmp_path) -> None:
    passed, _detail = run_comments(_comments(tmp_path, "Return the configured example value."))
    assert passed is True


def _docs(tmp_path: Path, digest: str) -> GateConfig:
    (tmp_path / "doc.md").write_text("hello\n", encoding="utf-8")
    (tmp_path / "manifest.json").write_text(json.dumps({"files": [{"path": "doc.md", "sha256": digest}]}), encoding="utf-8")
    return GateConfig(root=tmp_path, docs_manifest="manifest.json")


def test_rule_doc_001_negative(tmp_path) -> None:
    passed, _detail = run_docs(_docs(tmp_path, "A" * 64))
    assert passed is False


def test_rule_doc_001_positive(tmp_path) -> None:
    digest = hashlib.sha256(b"hello\n").hexdigest().upper()
    passed, _detail = run_docs(_docs(tmp_path, digest))
    assert passed is True


def _claims(tmp_path: Path, note_count: str) -> GateConfig:
    (tmp_path / "manifest.json").write_text(json.dumps({"counts": {"passed": 2, "total": 3}}), encoding="utf-8")
    (tmp_path / "notes.md").write_text(f"QUALITY_COUNTS: {note_count}\n", encoding="utf-8")
    return GateConfig(root=tmp_path, claims_manifest="manifest.json", claims_notes="notes.md")


def test_rule_clm_001_negative(tmp_path) -> None:
    passed, _detail = run_claims(_claims(tmp_path, "1/3"))
    assert passed is False


def test_rule_clm_001_positive(tmp_path) -> None:
    passed, _detail = run_claims(_claims(tmp_path, "2/3"))
    assert passed is True


def test_rule_cst_001_negative(tmp_path) -> None:
    (tmp_path / "x.py").write_text("print('x')" + chr(10), encoding="utf-8")
    cfg = GateConfig(root=tmp_path, custom_rules=({"name": "no_print", "pattern": "print\\(", "files": ["x.py"], "message": "no print", "mode": "enforce"},))
    assert custom_rules.run(cfg)[0] is False


def test_rule_cst_001_positive(tmp_path) -> None:
    (tmp_path / "x.py").write_text("print_removed = True" + chr(10), encoding="utf-8")
    cfg = GateConfig(root=tmp_path, custom_rules=({"name": "no_print", "pattern": "print\\(", "files": ["x.py"], "message": "no print", "mode": "enforce"},))
    assert custom_rules.run(cfg)[0] is True


def test_rule_upg_001_negative(tmp_path) -> None:
    (tmp_path / "old.json").write_text(json.dumps({"properties": {"a": {}}, "required": ["a"]}), encoding="utf-8")
    (tmp_path / "new.json").write_text(json.dumps({"properties": {"b": {}}, "required": ["b"]}), encoding="utf-8")
    cfg = GateConfig(root=tmp_path, previous_schema="old.json", current_schema="new.json")
    assert upgrade_gate.run(cfg)[0] is False


def test_rule_upg_001_positive(tmp_path) -> None:
    assert upgrade_gate.run(GateConfig(root=tmp_path))[0] is True
