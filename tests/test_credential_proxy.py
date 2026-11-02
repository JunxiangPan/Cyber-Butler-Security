from __future__ import annotations

import http.client
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import credential_proxy


class Upstream(BaseHTTPRequestHandler):
    seen: list[str] = []

    def do_POST(self):
        self.seen.append(self.headers.get("Authorization", ""))
        length = int(self.headers.get("Content-Length", "0"))
        self.rfile.read(length)
        body = b'{"ok":true,"upstream":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def _start(server):
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return thread


def test_proxy_replaces_fake_key_and_forwards_only_v1(monkeypatch):
    monkeypatch.setenv("CBS_CREDENTIAL_PROXY_REAL_KEY", "real-secret-value")
    upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
    _start(upstream)
    config = credential_proxy.ProxyConfig(
        upstream=f"http://127.0.0.1:{upstream.server_port}",
        fake_token="fake-token-123456",
        listen_port=0,
    )
    proxy = credential_proxy.build_server(config)
    _start(proxy)
    try:
        conn = http.client.HTTPConnection("127.0.0.1", proxy.server_port, timeout=5)
        conn.request("POST", "/v1/chat/completions", b'{"x":1}', {
            "Authorization": "Bearer fake-token-123456",
            "Content-Type": "application/json",
        })
        response = conn.getresponse()
        assert response.status == 200
        assert json.loads(response.read())["upstream"] is True
        assert Upstream.seen[-1] == "Bearer real-secret-value"

        conn.request("GET", "/admin", headers={"Authorization": "Bearer fake-token-123456"})
        assert conn.getresponse().status == 400

        conn.request("POST", "/v1/chat/completions", b"{}", {"Authorization": "Bearer wrong-token"})
        assert conn.getresponse().status == 401
        conn.close()
    finally:
        proxy.shutdown()
        upstream.shutdown()


def test_config_rejects_non_http_upstream(tmp_path: Path):
    path = tmp_path / "proxy.json"
    path.write_text('{"upstream":"file:///etc/passwd","fake_token":"0123456789abcdef"}', encoding="utf-8")
    try:
        credential_proxy.ProxyConfig.load(path)
    except ValueError:
        return
    raise AssertionError("unsafe upstream accepted")
