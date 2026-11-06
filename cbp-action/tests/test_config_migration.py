"""Old cbp.json files must migrate without breaking existing CI."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from cbp.config import load_config


def _write(tmp_path: Path, data: dict) -> Path:
    path = tmp_path / "cbp.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def test_legacy_fields_are_mapped(tmp_path: Path, capsys) -> None:
    path = _write(tmp_path, {"installer_core": "install.sh", "broker_files": ["tools/x.py"]})
    cfg = load_config(tmp_path, path)
    assert str(cfg.install_command).replace(chr(92), "/").endswith("install.sh")
    assert cfg.target_files == ["tools/x.py"]
    assert "CBP_CONFIG_WARN" in capsys.readouterr().err


def test_missing_schema_version_is_auto_migrated(tmp_path: Path, capsys) -> None:
    path = _write(tmp_path, {"coverage_threshold": 70})
    cfg = load_config(tmp_path, path)
    assert cfg.schema_version == "0.1.3"
    assert "schema_version missing" in capsys.readouterr().err


def test_future_schema_version_is_rejected(tmp_path: Path) -> None:
    path = _write(tmp_path, {"schema_version": "9.0.0"})
    with pytest.raises(ValueError, match="unsupported future"):
        load_config(tmp_path, path)


def test_current_config_without_new_fields_runs(tmp_path: Path) -> None:
    path = _write(tmp_path, {"schema_version": "0.1.3"})
    cfg = load_config(tmp_path, path)
    assert cfg.custom_rules == ()
    assert cfg.evidence_readers == {}
