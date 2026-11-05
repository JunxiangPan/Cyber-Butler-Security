"""Real HTTP error-path tests for the broker request handler.

These tests call ``Handler.do_POST`` through a lightweight socket stub. They
exercise the real ``_body``, Host/Origin, size-limit, and exception branches.
No network listener is required.
"""
from __future__ import annotations

import io
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import broker  # noqa: E402


class _Stub:
    def __init__(self, *, path: str = "/request", body: bytes = b"", headers: dict | None = None) -> None:
        self.path = path
        self.rfile = io.BytesIO(body)
        self.wfile = io.BytesIO()
        self.client_address = ("127.0.0.1", 5555)
        self.headers = {"Host": "127.0.0.1:18090", **(headers or {})}
        self.last = None

    def _json(self, status: int, payload: dict) -> None:
        self.last = (status, payload)

    def _local_only(self) -> bool:
        return True

    def _auth(self) -> bool:
        return True

    def _body(self) -> dict:
        return broker.Handler._body(self)


class _HostStub:
    def __init__(self, headers: dict) -> None:
        self.headers = headers
        self.client_address = ("127.0.0.1", 5555)
        self.last = None

    def _json(self, status, payload) -> None:
        self.last = (status, payload)

    _host_origin_ok = broker.Handler._host_origin_ok


def _post(stub: _Stub, monkeypatch, run_request=None):
    if run_request is not None:
        monkeypatch.setattr(broker, "run_request", run_request)
    broker.Handler.do_POST(stub)
    return stub.last


def test_malformed_json_returns_400(monkeypatch) -> None:
    payload = b'{"action":'
    stub = _Stub(body=payload, headers={"Content-Length": str(len(payload))})
    status, body = _post(stub, monkeypatch)
    assert status == 400
    assert body["ok"] is False


def test_invalid_utf8_returns_400(monkeypatch) -> None:
    payload = b'{"x":"' + bytes([0xFF]) + b'"}'
    stub = _Stub(body=payload, headers={"Content-Length": str(len(payload))})
    status, _body = _post(stub, monkeypatch)
    assert status == 400


def test_oversized_body_returns_413(monkeypatch) -> None:
    stub = _Stub(headers={"Content-Length": "70000"})
    status, _body = _post(stub, monkeypatch)
    assert status == 413


def test_negative_and_non_numeric_content_length_return_400(monkeypatch) -> None:
    for value in ("-1", "abc"):
        stub = _Stub(headers={"Content-Length": value})
        status, _body = _post(stub, monkeypatch)
        assert status == 400


def test_missing_content_length_is_empty_object(monkeypatch) -> None:
    stub = _Stub()
    status, _body = _post(stub, monkeypatch, run_request=lambda payload: (200, {"ok": True}))
    assert status == 200


def test_incomplete_body_returns_400(monkeypatch) -> None:
    stub = _Stub(headers={"Content-Length": "10"}, body=b"{")
    status, _body = _post(stub, monkeypatch)
    assert status == 400


def test_forged_host_and_origin_are_rejected() -> None:
    assert broker.Handler._local_only(_HostStub({"Host": "evil.example"})) is False
    assert broker.Handler._local_only(_HostStub({"Host": "127.0.0.1:18090", "Origin": "http://evil.example"})) is False


def test_handler_body_exception_returns_500(monkeypatch) -> None:
    stub = _Stub()

    def explode() -> dict:
        raise RuntimeError("unexpected body failure")

    stub._body = explode
    status, _body = _post(stub, monkeypatch)
    assert status == 500
