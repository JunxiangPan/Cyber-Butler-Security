"""Policy coverage for the dedicated install workspace."""
from __future__ import annotations

import broker


def test_workspace_delete_requires_totp() -> None:
    target = broker.WORKSPACE_ROOT / "test.txt"
    assert broker.classify("delete", str(target)) == "totp"


def test_workspace_new_file_write_is_allowed() -> None:
    target = broker.WORKSPACE_ROOT / "new-file.txt"
    assert broker.classify("write_file", str(target)) == "totp"


def test_literal_cbs_workspace_is_totp() -> None:
    assert broker.classify("delete", "C:/CyberButler/workspace/test.txt") == "totp"


def test_invalid_config_falls_back_without_crashing(tmp_path, monkeypatch) -> None:
    cfg = tmp_path / "broker_config.json"
    cfg.write_text("{not-json", encoding="utf-8")
    monkeypatch.setattr(broker, "BROKER_CONFIG", cfg)
    roots = broker._workspace_roots()
    assert broker.DEFAULT_WORKSPACE_ROOT in roots
    assert broker.classify("delete", "C:/CyberButler/workspace/x.txt") == "totp"


def test_webui_approval_channel_is_read(tmp_path, monkeypatch) -> None:
    cfg = tmp_path / "broker_config.json"
    cfg.write_text('{"approval_channel":"webui"}', encoding="utf-8")
    monkeypatch.setattr(broker, "BROKER_CONFIG", cfg)
    assert broker._approval_channel() == "webui"


def test_missing_approval_channel_defaults_to_webui(tmp_path, monkeypatch) -> None:
    cfg = tmp_path / "broker_config.json"
    cfg.write_text('{"approval_channel":', encoding="utf-8")
    monkeypatch.setattr(broker, "BROKER_CONFIG", cfg)
    assert broker._approval_channel() == "webui"


def test_shared_default_is_the_cbs_workspace(monkeypatch) -> None:
    monkeypatch.delenv("CBS_WORKSPACE", raising=False)
    assert broker._resolve_shared() == broker.DEFAULT_WORKSPACE_ROOT
