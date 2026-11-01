"""Policy tests for the broker's allow/totp/deny split."""

from __future__ import annotations

from pathlib import Path

import broker


def setup_function() -> None:
    broker._pending = None
    broker._send_events.clear()
    broker._send_results.clear()
    broker._last_request_at = 0.0


def _roots(tmp_path: Path):
    tmp = tmp_path / "tmp"
    memory = tmp_path / "memory"
    vault = tmp_path / "vault"
    shared = tmp_path / "shared"
    for path in (tmp, memory, vault, shared):
        path.mkdir(parents=True, exist_ok=True)
    return tmp, memory, vault, shared


def test_classify_tmp_is_auto_allowed(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)

    assert broker.classify("delete", str(tmp / "a.txt")) == "allow"
    assert broker.classify("write_file", str(tmp / "a.txt")) == "allow"


def test_classify_memory_requires_totp(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)

    assert broker.classify("write_file", str(memory / "facts.db")) == "totp"
    assert broker.classify("delete", str(memory / "facts.db")) == "totp"


def test_classify_vault_is_denied(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)

    assert broker.classify("delete", str(vault / "totp_secret.dpapi")) == "deny"
    assert broker.classify("write_file", str(vault / "x")) == "deny"


def test_tmp_write_file_executes_without_pending(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    target = tmp / "note.txt"

    status, body = broker.run_request(
        {"action": "write_file", "target": str(target), "content": "auto"}
    )

    assert status == 200
    assert body["auto_executed"] is True
    assert target.read_text(encoding="utf-8") == "auto"
    assert broker._pending is None
    assert audit.exists()


def test_memory_write_file_creates_totp_pending(monkeypatch, tmp_path) -> None:
    tmp, memory, vault, shared = _roots(tmp_path)
    audit = tmp_path / "audit.jsonl"
    monkeypatch.setattr(broker, "TMP_ROOTS", (tmp,))
    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", vault)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "AUDIT", audit)
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    target = memory / "facts.db"

    status, body = broker.run_request(
        {"action": "write_file", "target": str(target), "content": "secret"}
    )

    assert status == 200
    assert body.get("id")
    assert broker._pending is not None
    assert broker._pending["action"] == "write_file"
    assert broker._pending["content"] == "secret"
    assert not target.exists()
