"""CLI behavior tests including watch mode and explicit config."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from cbp import cli


def _fixture(tmp_path: Path, percent: float = 100.0, threshold: float = 80.0) -> str:
    (tmp_path / "coverage.json").write_text(json.dumps({"files": {
        "src/a.py": {
            "summary": {"num_statements": 10, "covered_lines": int(percent / 10), "percent_covered": percent},
            "missing_lines": list(range(int(percent / 10) + 1, 11)),
        }
    }}), encoding="utf-8")
    (tmp_path / "coverage_allowlist.json").write_text('{"files": {}}', encoding="utf-8")
    config = {
        "coverage_json": "coverage.json",
        "coverage_allowlist": "coverage_allowlist.json",
        "coverage_groups": [{"name": "core", "files": ["src/a.py"], "threshold": threshold, "mode": "enforce"}],
        "enable_coverage": True,
        "enable_dependency": False,
        "enable_comments": False,
        "enable_docs": False,
        "enable_binary": False,
        "enable_claims": False,
    }
    path = tmp_path / "custom.json"
    path.write_text(json.dumps(config), encoding="utf-8")
    return str(path)


def test_cli_enforce_success(tmp_path, capsys) -> None:
    config = _fixture(tmp_path)
    assert cli.main(["--root", str(tmp_path), "--config", config]) == 0
    assert "CBP_RESULT=PASS" in capsys.readouterr().out


def test_cli_enforce_failure(tmp_path) -> None:
    config = _fixture(tmp_path, percent=50.0)
    assert cli.main(["--root", str(tmp_path), "--config", config]) == 1


def test_cli_warn_and_audit_do_not_block(tmp_path) -> None:
    config = _fixture(tmp_path, percent=50.0)
    assert cli.main(["--root", str(tmp_path), "--config", config, "--mode", "warn"]) == 0
    assert cli.main(["--root", str(tmp_path), "--config", config, "--mode", "audit"]) == 0


def test_cli_default_config_and_missing_files(tmp_path) -> None:
    assert cli.main(["--root", str(tmp_path)]) == 0
    _fixture(tmp_path)
    (tmp_path / "cbp.json").write_text((tmp_path / "custom.json").read_text(encoding="utf-8"), encoding="utf-8")
    assert cli.main(["--root", str(tmp_path), "--config", str(tmp_path / "cbp.json")]) == 0

def test_cli_default_cbp_json(tmp_path) -> None:
    _fixture(tmp_path)
    (tmp_path / "cbp.json").write_text((tmp_path / "custom.json").read_text(encoding="utf-8"), encoding="utf-8")
    assert cli.main(["--root", str(tmp_path)]) == 0


def test_cli_invalid_mode(tmp_path) -> None:
    config = _fixture(tmp_path)
    with pytest.raises(SystemExit):
        cli.main(["--root", str(tmp_path), "--config", config, "--mode", "bogus"])


def test_cli_disable_flags(tmp_path) -> None:
    config = _fixture(tmp_path)
    assert cli.main(["--root", str(tmp_path), "--config", config, "--enable-coverage", "false"]) == 0
    assert cli.main(["--root", str(tmp_path), "--config", config, "--enable-coverage", "true", "--enable-dependency", "true"]) == 0
