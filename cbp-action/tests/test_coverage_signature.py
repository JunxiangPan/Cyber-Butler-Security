"""Coverage sidecars must bind the exact coverage.json bytes."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from cbp import coverage_gate
from cbp.config import GateConfig


def _cfg(tmp_path: Path, signature: str | None) -> GateConfig:
    data = {"files": {"src/x.py": {"summary": {"num_statements": 10, "percent_covered": 100}, "missing_lines": []}}}
    (tmp_path / "coverage.json").write_text(json.dumps(data), encoding="utf-8")
    (tmp_path / "allow.json").write_text('{"files":{}}', encoding="utf-8")
    if signature is not None:
        (tmp_path / "coverage.json.sha256").write_text(signature, encoding="utf-8")
    return GateConfig(
        root=tmp_path,
        coverage_json=tmp_path / "coverage.json",
        coverage_allowlist=tmp_path / "allow.json",
        coverage_groups=({"name": "src", "files": ["src/x.py"], "threshold": 0},),
        require_coverage_signature=True,
    )


def test_valid_signature_passes(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path, "placeholder")
    digest = hashlib.sha256((tmp_path / "coverage.json").read_bytes()).hexdigest()
    (tmp_path / "coverage.json.sha256").write_text(digest + "  coverage.json\n", encoding="utf-8")
    assert coverage_gate.run(cfg)[0] is True


def test_missing_signature_fails(tmp_path: Path) -> None:
    passed, detail = coverage_gate.run(_cfg(tmp_path, None))
    assert passed is False and "signature missing" in detail


def test_wrong_signature_fails(tmp_path: Path) -> None:
    passed, detail = coverage_gate.run(_cfg(tmp_path, "0" * 64 + "  coverage.json\n"))
    assert passed is False and "signature mismatch" in detail
