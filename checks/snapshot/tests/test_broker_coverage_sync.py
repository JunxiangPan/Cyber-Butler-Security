"""Coverage helpers for configuration and execution-result compatibility."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


def test_execution_values_accepts_typed_and_tuple() -> None:
    assert broker._execution_values(broker.ExecutionResult(200, "ok")) == (True, "ok")
    assert broker._execution_values((False, "bad")) == (False, "bad")
    try:
        broker._execution_values("bad")
    except TypeError:
        return
    raise AssertionError("non-result should raise TypeError")


def test_resolvers_read_config(monkeypatch, tmp_path) -> None:
    config = tmp_path / "broker_config.json"
    config.write_text(json.dumps({"workspace_path": str(tmp_path / "ws"), "umo": "QQ:FriendMessage:test"}), encoding="utf-8")
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.setattr(broker, "BROKER_CONFIG", config)
    monkeypatch.delenv("CBS_WORKSPACE", raising=False)
    monkeypatch.delenv("CBS_UMO", raising=False)
    assert broker._resolve_shared() == tmp_path / "ws"
    assert broker._resolve_umo() == "QQ:FriendMessage:test"


def test_admin_email_reads_config(monkeypatch, tmp_path) -> None:
    config = tmp_path / "broker_config.json"
    config.write_text(json.dumps({"admin_email": "owner@example.org"}), encoding="utf-8")
    monkeypatch.setattr(broker, "BROKER_CONFIG", config)
    monkeypatch.setattr(broker, "WEBUI_CONTACT", tmp_path / "missing.json")
    assert broker._admin_email() == "owner@example.org"
