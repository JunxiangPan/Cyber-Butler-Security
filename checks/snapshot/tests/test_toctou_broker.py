"""Broker-level TOCTOU regression: approval must use the same handle."""

from __future__ import annotations

import time
from pathlib import Path

import broker


def setup_function() -> None:
    broker._pending = None
    broker._verify_locked_until = 0.0
    broker._global_failures = 0
    broker._global_lock_until = 0.0
    broker._last_request_at = 0.0


def test_verify_rejects_handle_content_change(monkeypatch, tmp_path: Path) -> None:
    memory = tmp_path / "memory"
    memory.mkdir()
    target = memory / "facts.txt"
    target.write_text("original", encoding="utf-8")
    audit = tmp_path / "audit.jsonl"

    monkeypatch.setattr(broker, "MEMORY_ROOTS", (memory,))
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    monkeypatch.setattr(broker, "SHARED", tmp_path / "shared")
    monkeypatch.setattr(broker, "TOTP_VAULT_ROOT", tmp_path / "vault")
    monkeypatch.setattr(broker, "AUDIT", audit)
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    monkeypatch.setattr(broker, "verify_code", lambda code, request_id="": "totp")

    status, body = broker.run_request(
        {"action": "write_file", "target": str(target), "content": "approved"}
    )
    assert status == 200
    assert body["status"] == "requires_totp"
    assert broker._pending is not None

    # Mutate through the same approved handle. A path re-open would not notice
    # this before execution; the broker must reject it at verify time.
    snapshot = broker._pending["_snapshot"]
    snapshot.rewrite(b"tampered")
    broker._pending["deadline"] = time.monotonic() + 60

    status, body = broker.run_verify({"id": broker._pending["id"], "code": "123456"})

    assert status == 409
    assert "TOCTOU" in body["error"]
    assert broker._pending is None
