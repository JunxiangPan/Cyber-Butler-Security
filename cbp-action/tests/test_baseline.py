"""Baseline suppresses old findings but never new ones."""
from __future__ import annotations

import json
from pathlib import Path

from cbp import baseline, comment_gate
from cbp.config import GateConfig


def _cfg(tmp_path: Path) -> GateConfig:
    source = tmp_path / "x.py"
    source.write_text('def public(value):\n    """Return a configured value safely."""\n    return value  # This is a function\n', encoding="utf-8")
    return GateConfig(root=tmp_path, comment_files=("x.py",), baseline="cbp-baseline.json")


def test_generated_baseline_suppresses_existing_finding(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    passed, detail = comment_gate.run(cfg)
    assert passed is False
    lines = [line for line in detail.splitlines() if line.startswith("x.py:")]
    baseline.write(tmp_path / "cbp-baseline.json", "comments", lines)
    assert comment_gate.run(cfg)[0] is True


def test_new_finding_is_not_suppressed(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    _, detail = comment_gate.run(cfg)
    lines = [line for line in detail.splitlines() if line.startswith("x.py:")]
    baseline.write(tmp_path / "cbp-baseline.json", "comments", lines)
    (tmp_path / "x.py").write_text('def public(value):\n    """Return a configured value safely."""\n    return value  # This is a function\n\n# This is another function\n', encoding="utf-8")
    passed, _ = comment_gate.run(cfg)
    assert passed is False


def test_cli_generate_baseline(tmp_path: Path, capsys) -> None:
    from cbp import cli
    (tmp_path / "cbp.json").write_text(json.dumps({"schema_version": "0.1.3", "comment_files": ["x.py"]}), encoding="utf-8")
    (tmp_path / "x.py").write_text('def public(value):\n    """Return a configured value safely."""\n    return value  # This is a function\n', encoding="utf-8")
    code = cli.main(["--root", str(tmp_path), "--config", str(tmp_path / "cbp.json"), "--generate-baseline", str(tmp_path / "base.json")])
    assert code == 0
    assert "BASELINE_WRITTEN" in capsys.readouterr().out
