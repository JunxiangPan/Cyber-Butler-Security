"""Broker denies an invalid TOTP with HTTP 403."""

from __future__ import annotations

import time

import broker


def setup_function() -> None:
    broker._pending = None
    broker._verify_locked_until = 0.0
    broker._global_failures = 0
    broker._global_lock_until = 0.0
    broker._used_totp.clear()


def test_wrong_totp_returns_403(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(broker, "verify_code", lambda code: "")
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "broker-audit.jsonl")

    broker._pending = {
        "id": "req-test",
        "action": "delete",
        "target": "YOUR_USER_PATH/Desktop/shared/note.txt",
        "source": "",
        "reason": "test",
        "deadline": time.monotonic() + 60,
    }

    status, body = broker.run_verify({"id": "req-test", "code": "000000"})

    assert status == 403
    assert body["ok"] is False
    assert body["error"] == "invalid verification code"
    assert body["attempts"] == 1
    assert broker._pending is not None  # invalid code does not consume the challenge
    assert broker._pending["attempts"] == 1
    assert (tmp_path / "broker-audit.jsonl").exists()
