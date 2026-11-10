"""State-machine tests for request -> verify -> execute -> trash."""
from __future__ import annotations

import json
from pathlib import Path

import broker


def _setup(monkeypatch, tmp_path: Path) -> Path:
    shared = tmp_path / "workspace"
    shared.mkdir(parents=True)
    (tmp_path / "tools" / "broker").mkdir(parents=True)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    monkeypatch.setattr(broker, "MEMORY_ROOTS", ())
    monkeypatch.setattr(broker, "ROOT", tmp_path)
    monkeypatch.setattr(broker, "TOKEN_FILE", tmp_path / "tools" / "broker_token.txt")
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "tools" / "audit.jsonl")
    monkeypatch.setattr(broker, "BROKER_CONFIG", tmp_path / "tools" / "broker_config.json")
    monkeypatch.setattr(broker, "QUARANTINE", tmp_path / "tools" / "broker" / "trash_staging")
    monkeypatch.setattr(broker, "STAGING", tmp_path / "tools" / "broker" / "staging")
    (tmp_path / "tools" / "broker_token.txt").write_text("state-token-" + "x" * 24, encoding="utf-8")
    (tmp_path / "tools" / "broker_config.json").write_text(json.dumps({"approval_channel": "webui"}), encoding="utf-8")
    broker._pending = None
    return shared


def test_request_verify_executes_and_undo(monkeypatch, tmp_path: Path) -> None:
    shared = _setup(monkeypatch, tmp_path)
    target = shared / "state.txt"
    target.write_text("state", encoding="utf-8")
    status, body = broker.run_request({"action": "delete", "target": str(target), "reason": "state"})
    assert status == 200, body
    challenge = body["id"]
    monkeypatch.setattr(broker, "verify_code", lambda _code: "totp")
    monkeypatch.setattr(broker, "_assert_snapshots_current", lambda _request: None)
    status, body = broker.run_verify({"id": challenge, "code": "123456"})
    assert status == 200, body
    assert not target.exists()
    status, body = broker.undo_trash_request({"id": challenge})
    assert status == 200, body
    assert target.exists()


def test_invalid_state_transitions(monkeypatch, tmp_path: Path) -> None:
    _setup(monkeypatch, tmp_path)
    assert broker.run_verify({})[0] == 404
    assert broker.get_approval_status("")[0] == 400
    assert broker.run_request({"action": "invalid", "target": "x"})[0] == 400
    directory = tmp_path / "dir"
    directory.mkdir()
    assert broker.run_request({"action": "delete", "target": str(directory)})[0] == 400
