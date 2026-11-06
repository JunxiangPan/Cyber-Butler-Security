"""Upgrade evidence must fail closed; schema breaks need explicit approval."""
from __future__ import annotations

import json
import sys
from pathlib import Path

from cbp import upgrade_gate
from cbp.config import GateConfig


def test_no_upgrade_checks_is_a_noop(tmp_path: Path) -> None:
    passed, detail = upgrade_gate.run(GateConfig(root=tmp_path))
    assert passed is True
    assert detail == "upgrade=no checks configured"


def test_script_failure_blocks(tmp_path: Path) -> None:
    cfg = GateConfig(root=tmp_path, upgrade_script=f'"{sys.executable}" -c "raise SystemExit(3)"')
    passed, detail = upgrade_gate.run(cfg)
    assert passed is False
    assert "upgrade script failed" in detail


def test_script_success_passes(tmp_path: Path) -> None:
    cfg = GateConfig(root=tmp_path, upgrade_script=f'"{sys.executable}" -c "print(1)"')
    passed, detail = upgrade_gate.run(cfg)
    assert passed is True and "script" in detail


def test_old_config_fixture_parses(tmp_path: Path) -> None:
    fixture = tmp_path / "old.json"
    fixture.write_text(json.dumps({"installer_core": "install.sh"}), encoding="utf-8")
    cfg = GateConfig(root=tmp_path, upgrade_fixtures=("old.json",))
    passed, detail = upgrade_gate.run(cfg)
    assert passed is True and "fixtures" in detail


def test_missing_fixture_blocks(tmp_path: Path) -> None:
    cfg = GateConfig(root=tmp_path, upgrade_fixtures=("missing.json",))
    passed, detail = upgrade_gate.run(cfg)
    assert passed is False and "fixture missing" in detail


def test_schema_break_blocks_unless_allowed(tmp_path: Path) -> None:
    (tmp_path / "old.json").write_text(json.dumps({"properties": {"a": {}, "removed": {}}, "required": ["a"]}), encoding="utf-8")
    (tmp_path / "new.json").write_text(json.dumps({"properties": {"a": {}}, "required": ["a", "b"]}), encoding="utf-8")
    cfg = GateConfig(root=tmp_path, previous_schema="old.json", current_schema="new.json")
    passed, detail = upgrade_gate.run(cfg)
    assert passed is False and "schema compatibility failed" in detail
    cfg.allow_breaking_changes = True
    assert upgrade_gate.run(cfg)[0] is True


def test_shell_metacharacters_are_rejected(tmp_path: Path) -> None:
    for script in (
        f'"{sys.executable}" -c "print(1)" && echo hacked',
        f'"{sys.executable}" -c "print(1)" | cat',
        f'"{sys.executable}" -c "print(1)" > out.txt',
    ):
        passed, detail = upgrade_gate.run(GateConfig(root=tmp_path, upgrade_script=script))
        assert passed is False
        assert "metacharacters" in detail


def test_pull_request_event_is_rejected(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("GITHUB_EVENT_NAME", "pull_request")
    cfg = GateConfig(root=tmp_path, upgrade_script=f'"{sys.executable}" -c "print(1)"')
    passed, detail = upgrade_gate.run(cfg)
    assert passed is False
    assert "pull_request" in detail
