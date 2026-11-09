"""P0-2: Python SDK conformance against a local Broker-shaped server."""
from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

from sdk.python.cbs_client import CbsClient, CbsError

TOKEN = "test-broker-token"


class _Handler(BaseHTTPRequestHandler):
    seen: list[dict] = []

    def log_message(self, *_args):
        return

    def _json(self, status: int, body: dict) -> None:
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(length) or b"{}")
        type(self).seen.append({"path": self.path, "token": self.headers.get("X-Broker-Token"), "body": body})
        if self.path == "/request":
            self._json(200, {"ok": True, "status": "requires_totp", "id": "req-1", "action": body["action"]})
        elif self.path == "/verify":
            self._json(200, {"ok": True, "status": "approved", "id": body["id"]})
        else:
            self._json(404, {"ok": False, "error": "not found"})

    def do_GET(self):
        type(self).seen.append({"path": self.path, "token": self.headers.get("X-Broker-Token")})
        if self.path.startswith("/api/request_approval/status"):
            self._json(200, {"ok": True, "status": "pending", "challenge_id": "req-1", "approval_only": True})
        else:
            self._json(404, {"ok": False, "error": "not found"})


@pytest.fixture()
def server():
    _Handler.seen = []
    httpd = HTTPServer(("127.0.0.1", 0), _Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield "http://127.0.0.1:" + str(httpd.server_port), _Handler.seen
    finally:
        httpd.shutdown()


def test_request_status_verify_contract(server):
    base, seen = server
    client = CbsClient(base, token=TOKEN)
    body = client.request_approval("delete", "C:/tmp/x", reason="demo")
    assert body["status"] == "requires_totp"
    assert client.status("req-1")["status"] == "pending"
    assert client.verify("req-1", "123456")["status"] == "approved"
    assert all(item["token"] == TOKEN for item in seen)
    assert seen[0]["body"]["approval_only"] is True
    assert "scoped_minutes" not in seen[-1]["body"]


def test_loopback_only():
    with pytest.raises(ValueError, match="loopback"):
        CbsClient("http://example.com:18090", token=TOKEN)


def test_error_envelope(server):
    base, _seen = server
    client = CbsClient(base, token=TOKEN)
    with pytest.raises(CbsError) as exc:
        client._call("POST", "/missing", {})
    assert exc.value.status == 404
