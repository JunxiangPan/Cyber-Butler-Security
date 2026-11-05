"""P0 status-code and TOTP replay semantics."""
from __future__ import annotations

import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
import broker  # noqa: E402


def test_execution_result_is_typed_and_unpackable() -> None:
    result = broker.ExecutionResult(507, "capacity", "trash.capacity_exceeded")
    assert result.ok is False
    ok, message = result
    assert ok is False and message == "capacity"


def test_totp_replay_is_scoped_to_request_id(monkeypatch) -> None:
    monkeypatch.setattr(broker, "secret", lambda: "test-secret")
    class FakeTotp:
        def __init__(self, secret: str) -> None:
            self.secret = secret

        def verify(self, code: str, valid_window: int = 0) -> bool:
            return code == "123456"
    monkeypatch.setattr(broker.pyotp, "TOTP", FakeTotp)
    broker.broker_state._used_totp.clear()
    assert broker.verify_code("123456", "request-a") == "totp"
    assert broker.verify_code("123456", "request-a") == "replay"
    assert broker.verify_code("123456", "request-b") == "totp"


def test_capacity_execution_maps_to_507(monkeypatch, tmp_path) -> None:
    target = tmp_path / "x"
    target.write_text("x", encoding="utf-8")
    broker.broker_state._pending = {
        "id": "capacity-test", "action": "delete", "target": str(target),
        "channel": "webui", "deadline": 10**18, "manifest": None,
        "approval_only": False, "_snapshot": None, "_source_snapshot": None,
        "target_summary": broker._path_summary(str(target)),
    }
    broker.broker_state._verify_locked_until = 0.0
    broker.broker_state._global_failures = 0
    broker.broker_state._global_lock_until = 0.0
    monkeypatch.setattr(broker, "verify_code", lambda code, request_id="": "totp")
    monkeypatch.setattr(broker, "execute", lambda request: broker._fail("capacity", 507, "trash.capacity_exceeded"))
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    try:
        status, body = broker.run_verify({"id": "capacity-test", "code": "123456"})
        assert status == 507, body
        assert body.get("ok") is False
    finally:
        broker.broker_state._pending = None
