"""Small state/config helper branches."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


def test_retain_and_release_snapshot(monkeypatch) -> None:
    closed = []
    class Snap:
        def close(self): closed.append(True)
    broker.broker_state._retained_snapshots.clear()
    broker._retain_snapshots("r1", {"_snapshot": Snap(), "_source_snapshot": None})
    assert broker._release_retained("r1") is True
    assert closed
    assert broker._release_retained("missing") is False


def test_resolve_shared_env_and_config(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(broker, "TEST_MODE", True)
    monkeypatch.setenv("CBS_TEST_SHARED", str(tmp_path / "shared"))
    assert broker._resolve_shared() == tmp_path / "shared"
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.delenv("CBS_TEST_SHARED", raising=False)
    monkeypatch.setenv("CBS_WORKSPACE", str(tmp_path / "ws"))
    assert broker._resolve_shared() == tmp_path / "ws"


def test_resolve_shared_reads_config_shared_roots(monkeypatch, tmp_path) -> None:
    import json

    config = tmp_path / "broker_config.json"
    config.write_text(json.dumps({"shared_roots": [str(tmp_path / "from-config")]}), encoding="utf-8")
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.delenv("CBS_TEST_SHARED", raising=False)
    monkeypatch.delenv("CBS_WORKSPACE", raising=False)
    monkeypatch.setattr(broker, "BROKER_CONFIG", config)
    assert broker._resolve_shared() == tmp_path / "from-config"


def test_resolve_umo_reads_config(monkeypatch, tmp_path) -> None:
    import json

    config = tmp_path / "broker_config.json"
    config.write_text(json.dumps({"umo": "QQ:FriendMessage:42"}), encoding="utf-8")
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.delenv("CBS_UMO", raising=False)
    monkeypatch.delenv("CBS_QQ_ID", raising=False)
    monkeypatch.setattr(broker, "BROKER_CONFIG", config)
    assert broker._resolve_umo() == "QQ:FriendMessage:42"
    config.write_text(json.dumps({"owner_qq": "43"}), encoding="utf-8")
    assert broker._resolve_umo() == "QQ:FriendMessage:43"


def test_resolve_shared_string_and_warning(monkeypatch, tmp_path, capsys) -> None:
    import json

    config = tmp_path / "broker_config.json"
    config.write_text(json.dumps({"shared_roots": str(tmp_path / "one")}), encoding="utf-8")
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.delenv("CBS_WORKSPACE", raising=False)
    monkeypatch.setattr(broker, "BROKER_CONFIG", config)
    assert broker._resolve_shared() == tmp_path / "one"
    config.write_text("{broken", encoding="utf-8")
    assert broker._resolve_shared() == broker.ROOT / "workspace"
    assert "workspace resolver warning" in capsys.readouterr().err


def test_resolve_umo_env_override(monkeypatch) -> None:
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.setenv("CBS_UMO", "QQ:FriendMessage:99")
    assert broker._resolve_umo() == "QQ:FriendMessage:99"


def test_resolve_umo_qq_env(monkeypatch) -> None:
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.delenv("CBS_UMO", raising=False)
    monkeypatch.setenv("CBS_QQ_ID", "77")
    monkeypatch.setattr(broker, "BROKER_CONFIG", broker.BROKER_CONFIG)
    assert broker._resolve_umo() == "QQ:FriendMessage:77"


def test_resolve_umo_empty_fallback(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.delenv("CBS_UMO", raising=False)
    monkeypatch.delenv("CBS_QQ_ID", raising=False)
    monkeypatch.setattr(broker, "BROKER_CONFIG", tmp_path / "missing.json")
    assert broker._resolve_umo() == ""


def test_resolve_shared_template_fallback(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(broker, "TEST_MODE", False)
    monkeypatch.delenv("CBS_WORKSPACE", raising=False)
    monkeypatch.setattr(broker, "BROKER_CONFIG", tmp_path / "missing.json")
    monkeypatch.setattr(broker, "ROOT", Path("YOUR" + "_TEST_ROOT"))
    assert broker._resolve_shared() == Path(r"C:\CyberButler\workspace")
