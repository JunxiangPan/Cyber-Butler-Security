"""run_verify / recovery / approval-status branch tests."""
from __future__ import annotations

import sys
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


class Snap:
    identity = (0, 0, 3, 4)
    is_directory = False

    def assert_unchanged(self):
        return None

    def close(self):
        return None


def _setup(monkeypatch, tmp_path):
    broker.broker_state._pending = {
        "id": "verify-1", "action": "delete", "target": str(tmp_path / "x"),
        "source": "", "reason": "", "deadline": 10**18, "attempts": 0,
        "channel": "webui", "approval_only": False, "manifest": None,
        "_snapshot": Snap(), "_source_snapshot": None,
        "target_summary": "x", "source_summary": "",
    }
    broker.broker_state._verify_locked_until = 0
    monkeypatch.setattr(broker, "_is_uninstalling", lambda: False)
    monkeypatch.setattr(broker, "_is_verification_locked", lambda: False)
    monkeypatch.setattr(broker, "AUDIT", tmp_path / "audit.jsonl")
    monkeypatch.setattr(broker, "send_qq", lambda text: True)
    monkeypatch.setattr(broker, "execute", lambda request: broker.ExecutionResult(200, "ok"))
    monkeypatch.setattr(broker, "_assert_snapshots_current", lambda request: None)
    monkeypatch.setattr(broker, "_path_summary", lambda target: "x")
    monkeypatch.setattr(broker, "_record_global_failure", lambda: 1.0)


def test_verify_preconditions_and_expiry(monkeypatch, tmp_path) -> None:
    _setup(monkeypatch, tmp_path)
    monkeypatch.setattr(broker, "verify_code", lambda code, request_id="": "totp")
    broker.broker_state._pending = None
    assert broker.run_verify({"id": "x", "code": "1"})[0] == 404
    broker.broker_state._pending = {"id": "a", "channel": "webui", "deadline": 0}
    assert broker.run_verify({"id": "b", "code": "1"})[0] == 404
    broker.broker_state._pending = {"id": "a", "channel": "email", "deadline": 10**18}
    assert broker.run_verify({"id": "a", "code": "1"})[0] == 403
    broker.broker_state._pending = {"id": "a", "channel": "webui", "deadline": 0, "approval_only": True}
    status, _body = broker.run_verify({"id": "a", "code": "1"})
    assert status in {400, 410}


def test_verify_replay_and_invalid_lock(monkeypatch, tmp_path) -> None:
    _setup(monkeypatch, tmp_path)
    monkeypatch.setattr(broker, "audit_failure", lambda *args: None)
    monkeypatch.setattr(broker, "verify_code", lambda code, request_id="": "replay")
    assert broker.run_verify({"id": "verify-1", "code": "1"})[0] == 429
    monkeypatch.setattr(broker, "verify_code", lambda code, request_id="": "")
    for attempt in range(1, 5):
        status, body = broker.run_verify({"id": "verify-1", "code": "1"})
        assert status == 403 and body["attempts"] == attempt
    status, _body = broker.run_verify({"id": "verify-1", "code": "1"})
    assert status == 429


def test_verify_success_delete_and_send_manifest(monkeypatch, tmp_path) -> None:
    _setup(monkeypatch, tmp_path)
    monkeypatch.setattr(broker, "verify_code", lambda code, request_id="": "totp")
    status, body = broker.run_verify({"id": "verify-1", "code": "1"})
    assert status == 200 and body["ok"] is True
    broker.broker_state._pending = {"id": "send-1", "action": "send", "target": "http://example", "deadline": 10**18, "attempts": 0, "channel": "webui", "approval_only": False, "manifest": None}
    assert broker.run_verify({"id": "send-1", "code": "1"})[0] == 409
    broker.broker_state._pending = {"id": "send-2", "action": "send", "target": "http://example", "deadline": 10**18, "attempts": 0, "channel": "webui", "approval_only": False, "manifest": [{"path": "http://example", "kind": "url"}]}
    monkeypatch.setattr(broker, "_canonical_manifest", lambda manifest: [{"path": "other", "kind": "url"}])
    assert broker.run_verify({"id": "send-2", "code": "1"})[0] == 409


def test_reset_totp_with_recovery(monkeypatch, tmp_path) -> None:
    monkeypatch.setattr(broker, "verify_code", lambda code, request_id="": "recovery")
    monkeypatch.setattr(broker, "TOTP_VAULT", tmp_path / "vault")
    monkeypatch.setattr(broker, "SECRET_FILE", tmp_path / "vault" / "secret")
    monkeypatch.setattr(broker, "RECOVERY_FILE", tmp_path / "vault" / "recovery.json")
    monkeypatch.setattr(broker, "win32crypt", SimpleNamespace(CryptProtectData=lambda *a: b"enc"))
    monkeypatch.setattr(broker, "totp_binding_payload", lambda: {"ok": True})
    status, payload = broker.reset_totp_with_recovery("ABCD1234")
    assert status == 200 and payload["recovery_codes"]


def test_get_approval_status_route(monkeypatch) -> None:
    class Stub:
        path = "/api/request_approval/status?id=abc"
        headers = {"Host": "127.0.0.1:18090"}
        client_address = ("127.0.0.1", 1)
        last = None

        def _json(self, status, payload):
            self.last = (status, payload)

        _local_only = broker.Handler._local_only
        _host_origin_ok = broker.Handler._host_origin_ok
        _auth = lambda self: True

    stub = Stub()
    monkeypatch.setattr(broker, "get_approval_status", lambda cid: (200, {"id": cid}))
    broker.Handler.do_GET(stub)
    assert stub.last[0] == 200


def test_verify_uninstalling_and_locked(monkeypatch) -> None:
    monkeypatch.setattr(broker, "_is_uninstalling", lambda: True)
    assert broker.run_verify({"id": "x", "code": "1"})[0] == 503
    monkeypatch.setattr(broker, "_is_uninstalling", lambda: False)
    monkeypatch.setattr(broker, "_is_verification_locked", lambda: True)
    assert broker.run_verify({"id": "x", "code": "1"})[0] == 429
