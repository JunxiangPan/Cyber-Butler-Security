"""Coverage must be bound to source bytes, not filesystem timestamps."""
from __future__ import annotations

import json
import os
from pathlib import Path

from cbp import coverage_gate, source_hash
from cbp.config import GateConfig


def _cfg(tmp_path: Path) -> GateConfig:
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "a.py").write_text("x = 1\n", encoding="utf-8")
    data = {"files": {"src/a.py": {"summary": {"num_statements": 10, "percent_covered": 100}, "missing_lines": []}}}
    (tmp_path / "coverage.json").write_text(json.dumps(data), encoding="utf-8")
    (tmp_path / "allow.json").write_text('{"files":{}}', encoding="utf-8")
    source_hash.stamp(tmp_path / "coverage.json", tmp_path)
    return GateConfig(
        root=tmp_path,
        coverage_json="coverage.json",
        coverage_allowlist="allow.json",
        coverage_groups=({"name": "src", "files": ["src/a.py"], "threshold": 0},),
    )


def test_source_hash_passes(tmp_path: Path) -> None:
    assert coverage_gate.run(_cfg(tmp_path))[0] is True


def test_touch_cannot_bypass_source_hash(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    (tmp_path / "src" / "a.py").write_text("x = 2\n", encoding="utf-8")
    os.utime(tmp_path / "coverage.json", None)
    passed, detail = coverage_gate.run(cfg)
    assert passed is False
    assert "stale" in detail
