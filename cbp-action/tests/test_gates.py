"""Minimal CBP self-tests without external services."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
from cbp.config import GateConfig  # noqa: E402
from cbp.coverage_gate import run as coverage_run  # noqa: E402
from cbp.dependency_gate import run as dependency_run  # noqa: E402


def test_coverage_gate_rejects_low_coverage(tmp_path: Path) -> None:
    cover = {"files": {"tools/broker.py": {"summary": {"num_statements": 100}, "missing_lines": [1] * 50}, "tools/broker_policy.py": {"summary": {"percent_covered": 90}}}}
    (tmp_path / "coverage.json").write_text(json.dumps(cover), encoding="utf-8")
    (tmp_path / "coverage_allowlist.json").write_text('{"files":{}}', encoding="utf-8")
    cfg = GateConfig(root=tmp_path, coverage_json=tmp_path / "coverage.json", coverage_allowlist=tmp_path / "coverage_allowlist.json")
    assert coverage_run(cfg)[0] is False


def test_dependency_gate_requires_hash_lock(tmp_path: Path) -> None:
    cfg = GateConfig(root=tmp_path, coverage_json=tmp_path / "c.json", coverage_allowlist=tmp_path / "a.json", dependency_lock=tmp_path / "lock", installer_core=tmp_path / "installer")
    assert dependency_run(cfg)[0] is False
