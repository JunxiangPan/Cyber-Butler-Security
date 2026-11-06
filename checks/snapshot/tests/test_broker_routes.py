"""Exercise every broker HTTP route with real handler methods and stubs."""
from __future__ import annotations

import io
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


class Stub:
    def __init__(self, path: str, body: bytes = b"{}", auth: bool = True) -> None:
        self.path = path
        self.headers = {"Host": "127.0.0.1:18090", "Content-Length": str(len(body))}
        self.rfile = io.BytesIO(body)
        self.wfile = io.BytesIO()
        self.client_address = ("127.0.0.1", 5555)
        self.auth = auth
        self.last = None

    def _json(self, status, payload):
        self.last = (status, payload)

    def _local_only(self):
        return True

    def _auth(self):
        return self.auth

    def _body(self):
        return broker.Handler._body(self)


def _get(path: str, auth: bool = True):
    stub = Stub(path, auth=auth)
    broker.Handler.do_GET(stub)
    return stub.last


def _post(path: str, monkeypatch, auth: bool = True, body: bytes = b"{}"):
    stub = Stub(path, body=body, auth=auth)
    broker.Handler.do_POST(stub)
    return stub.last


def test_health_and_not_found() -> None:
    assert _get("/health")[0] == 200
    assert _get("/missing")[0] == 404


def test_pending_endpoints(monkeypatch) -> None:
    broker.broker_state._pending = None
    assert _get("/pending")[1]["pending"] is False
    assert _get("/pending/approval")[1]["pending"] is False
    broker.broker_state._pending = {"id": "abcdef123456", "action": "delete", "target": "C:/x/a.txt", "deadline": 0, "channel": "webui"}
    status, body = _get("/pending")
    assert status == 200 and body["pending"] is True and body["target_name"] == "a.txt"
    status, body = _get("/pending/approval")
    assert status == 200 and body["id"] == "abcdef123456"
    broker.broker_state._pending = None


def test_protected_get_endpoints(monkeypatch) -> None:
    assert _get("/pending", auth=False)[0] == 403
    assert _get("/pending/approval", auth=False)[0] == 403
    assert _get("/totp/bind", auth=False)[0] == 403
    assert _get("/trash", auth=False)[0] == 403


def test_totp_bind_and_trash(monkeypatch) -> None:
    monkeypatch.setattr(broker, "totp_binding_payload", lambda: {"otpauth_uri": "x", "qr_png_base64": "y"})
    assert _get("/totp/bind")[0] == 200
    monkeypatch.setattr(broker.quarantine, "list_pending", lambda: [{"id": "1"}])
    assert _get("/trash")[1]["items"][0]["id"] == "1"


def test_post_route_dispatch(monkeypatch) -> None:
    monkeypatch.setattr(broker, "_allow_request", lambda key: (True, 0))
    called = []
    for name, value in {"run_request": (200, {"ok": True}), "run_approval_request": (200, {"ok": True}), "record_external_read": (200, {"ok": True}), "run_verify": (200, {"ok": True}), "undo_trash_request": (200, {"ok": True}), "reset_totp_with_recovery": (200, {"ok": True})}.items():
        monkeypatch.setattr(broker, name, lambda payload, v=value: v)
    for path in ("/request", "/api/request_approval", "/external-read", "/verify", "/deny", "/approval/complete", "/trash/undo", "/totp/recovery-reset", "/missing"):
        assert _post(path, monkeypatch)[0] in {200, 400, 404}


def test_post_rate_limit_and_auth(monkeypatch) -> None:
    monkeypatch.setattr(broker, "_allow_request", lambda key: (False, 7))
    assert _post("/request", monkeypatch)[0] == 429
    assert _post("/request", monkeypatch, auth=False)[0] == 403
