"""Broker locks after five invalid TOTP attempts (HTTP 429)."""

from __future__ import annotations

import json
import time

import broker


def setup_function() -> None:
    broker._pending = None
    broker._verify_locked_until = 0.0


def test_five_bad_attempts_lock_verification(monkeypatch, tmp_path) -> None:
    audit = tmp_path / "broker-audit.jsonl"
    monkeypatch.setattr(broker, "verify_code", lambda code: "")
    monkeypatch.setattr(broker, "AUDIT", audit)
    broker._pending = {
        "id": "req-lock",
        "action": "delete",
        "target": "YOUR_USER_PATH/Desktop/shared/note.txt",
        "source": "",
        "reason": "test",
        "deadline": time.monotonic() + 60,
        "attempts": 0,
    }

    for attempt in range(1, 5):
        status, body = broker.run_verify({"id": "req-lock", "code": "000000"})
        assert status == 403
        assert body["attempts"] == attempt

    status, body = broker.run_verify({"id": "req-lock", "code": "000000"})
    assert status == 429
    assert body["attempts"] == 5
    assert broker._pending is None
    assert broker._verify_locked_until > time.monotonic()

    # A new request is rejected while the verification lock is active.
    status, _ = broker.run_request({"action": "delete", "target": "x"})
    assert status == 429

    records = [json.loads(line) for line in audit.read_text(encoding="utf-8").splitlines()]
    assert len(records) == 5
    assert all(record["ok"] is False for record in records)
    assert records[-1]["attempts"] == 5
