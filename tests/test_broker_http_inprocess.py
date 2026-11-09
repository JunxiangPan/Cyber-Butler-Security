"""In-process HTTP characterization for the Broker handler (coverage-visible)."""
from __future__ import annotations

import json
import threading
from http.server import ThreadingHTTPServer
from pathlib import Path

import pytest
import requests

import broker


@pytest.fixture()
def http_broker(monkeypatch, tmp_path: Path):
    root = tmp_path / "root"
    shared = root / "workspace"
    (root / "tools" / "broker").mkdir(parents=True)
    (root / "tools" / "logs").mkdir(parents=True)
    shared.mkdir(parents=True)
    token = "inprocess-token-" + "x" * 24
    token_file = root / "tools" / "broker_token.txt"
    token_file.write_text(token, encoding="utf-8")
    (root / "tools" / "broker_config.json").write_text(json.dumps({"approval_channel": "webui"}), encoding="utf-8")
    monkeypatch.setattr(broker, "ROOT", root)
    monkeypatch.setattr(broker, "SHARED", shared)
    monkeypatch.setattr(broker, "TOKEN_FILE", token_file)
    monkeypatch.setattr(broker, "BROKER_CONFIG", root / "tools" / "broker_config.json")
    monkeypatch.setattr(broker, "TMP_ROOTS", ())
    monkeypatch.setattr(broker, "MEMORY_ROOTS", ())
    monkeypatch.setattr(broker, "AUDIT", root / "tools" / "audit.jsonl")
    monkeypatch.setattr(broker, "_pending", None)
    server = ThreadingHTTPServer(("127.0.0.1", 0), broker.Handler)
    broker.ALLOWED_HOSTS = {f"127.0.0.1:{server.server_port}", f"localhost:{server.server_port}"}
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield "http://127.0.0.1:" + str(server.server_port), token, shared
    finally:
        server.shutdown()
        thread.join(timeout=5)
        broker._pending = None


def test_inprocess_health_auth_and_request(http_broker) -> None:
    base, token, shared = http_broker
    assert requests.get(base + "/health", timeout=5).json() == {"status": "ok"}
    assert requests.get(base + "/pending", timeout=5).status_code == 403
    headers = {"X-Broker-Token": token}
    target = shared / "http.txt"
    target.write_text("x", encoding="utf-8")
    response = requests.post(
        base + "/request",
        json={"action": "delete", "target": str(target), "approval_only": True},
        headers=headers, timeout=5,
    )
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "requires_totp"
    status = requests.get(
        base + "/api/request_approval/status",
        params={"id": response.json()["id"]},
        headers=headers, timeout=5,
    )
    assert status.status_code == 200 and status.json()["status"] == "pending"
    pending = requests.get(base + "/pending", headers=headers, timeout=5)
    assert pending.status_code == 200 and pending.json()["pending"] is True
    approval = requests.get(base + "/pending/approval", headers=headers, timeout=5)
    assert approval.status_code == 200 and approval.json()["pending"] is True
    assert requests.get(base + "/trash", headers=headers, timeout=5).status_code == 200
    assert requests.get(base + "/totp/bind", headers=headers, timeout=5).status_code in {200, 409}
    undo = requests.post(base + "/trash/undo", json={"id": "missing"}, headers=headers, timeout=5)
    assert undo.status_code in {400, 404}
    unknown = requests.get(base + "/api/request_approval/status", params={"id": "none"}, headers=headers, timeout=5)
    assert unknown.status_code == 404
    assert requests.get(base + "/unknown", headers=headers, timeout=5).status_code == 404
    assert requests.post(base + "/request", data="{", headers=headers, timeout=5).status_code == 400
