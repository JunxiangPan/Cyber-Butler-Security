"""Coverage group enforce/warn behavior."""
from __future__ import annotations

import json

from cbp import source_hash
from cbp.config import GateConfig
from cbp.coverage_gate import run


def _config(tmp_path, mode: str, threshold: float = 80) -> GateConfig:
    (tmp_path / "coverage.json").write_text(json.dumps({"files": {
        "src/a.py": {"summary": {"num_statements": 10, "covered_lines": 5, "percent_covered": 50}, "missing_lines": list(range(6, 11))}
    }}), encoding="utf-8")
    (tmp_path / "coverage_allowlist.json").write_text('{"files": {}}', encoding="utf-8")
    source_hash.stamp(tmp_path / "coverage.json", tmp_path)
    return GateConfig(
        root=tmp_path,
        coverage_json="coverage.json",
        coverage_allowlist="coverage_allowlist.json",
        coverage_groups=({"name": "core", "files": ["src/a.py"], "threshold": threshold, "mode": mode},),
    )


def test_enforce_group_fails_below_threshold(tmp_path) -> None:
    passed, detail = run(_config(tmp_path, "enforce"))
    assert passed is False
    assert "FAIL" in detail


def test_warn_group_does_not_fail(tmp_path) -> None:
    passed, detail = run(_config(tmp_path, "warn"))
    assert passed is True
    assert "WARN" in detail


def test_glob_group_expands_files(tmp_path) -> None:
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "a.py").write_text("x = 1\n", encoding="utf-8")
    cfg = _config(tmp_path, "enforce", threshold=40)
    cfg.coverage_groups = ({"name": "src", "files": ["src/*.py"], "threshold": 40, "mode": "enforce"},)
    passed, detail = run(cfg)
    assert passed is True
    assert "src=50.00%" in detail
