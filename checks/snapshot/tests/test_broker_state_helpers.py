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
