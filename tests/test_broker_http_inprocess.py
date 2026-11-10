"""In-process HTTP characterization for the Broker handler (coverage-visible)."""
from __future__ import annotations

import json
import threading
from http.server import ThreadingHTTPServer
from pathlib import Path

import pytest
import pyotp
import requests

import broker

SECRET = "JBSWY3DPEHPK3PXP"


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
    monkeypatch.setattr(broker, "QUARANTINE", root / "tools" / "broker" / "trash_staging")
    monkeypatch.setattr(broker, "STAGING", root / "tools" / "broker" / "staging")
    monkeypatch.setattr(broker, "secret", lambda: SECRET)
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
        json={"action": "delete", "target": str(target)},
        headers=headers, timeout=5,
    )
    assert response.status_code == 200, response.text
    assert response.json()["status"] == "requires_totp"
    pending = requests.get(base + "/pending", headers=headers, timeout=5)
    assert pending.status_code == 200 and pending.json()["pending"] is True
    approval = requests.get(base + "/pending/approval", headers=headers, timeout=5)
    assert approval.status_code == 200 and approval.json()["pending"] is True
    assert requests.get(base + "/trash", headers=headers, timeout=5).status_code == 200
    assert requests.get(base + "/totp/bind", headers=headers, timeout=5).status_code in {200, 409}
    undo = requests.post(base + "/trash/undo", json={"id": "missing"}, headers=headers, timeout=5)
    assert undo.status_code in {400, 404}
    challenge = response.json()["id"]
    code = pyotp.TOTP(SECRET).now()
    wrong = requests.post(base + "/verify", json={"id": challenge, "code": "000000"}, headers=headers, timeout=5)
    assert wrong.status_code == 403
    good = requests.post(base + "/verify", json={"id": challenge, "code": code}, headers=headers, timeout=5)
    assert good.status_code == 200, good.text
    assert not target.exists()
    trash = requests.get(base + "/trash", headers=headers, timeout=5)
    assert trash.status_code == 200 and trash.json()["items"]
    restored = requests.post(base + "/trash/undo", json={"id": challenge}, headers=headers, timeout=5)
    assert restored.status_code == 200, restored.text
    assert target.exists()
    replay = requests.post(base + "/verify", json={"id": challenge, "code": code}, headers=headers, timeout=5)
    assert replay.status_code in {404, 429}
    third = requests.post(
        base + "/request",
        json={"action": "delete", "target": str(target), "approval_only": True},
        headers=headers, timeout=5,
    )
    assert third.status_code == 200, third.text
    denied = requests.post(base + "/deny", json={"id": third.json()["id"]}, headers=headers, timeout=5)
    assert denied.status_code == 200 and denied.json()["denied"] is True
    completed = requests.post(base + "/approval/complete", json={"id": third.json()["id"]}, headers=headers, timeout=5)
    assert completed.status_code == 200 and completed.json()["ok"] is True
    assert requests.post(base + "/deny", json={}, headers=headers, timeout=5).status_code == 400
    assert requests.post(base + "/approval/complete", json={}, headers=headers, timeout=5).status_code == 400
    assert requests.post(base + "/external-read", json={"kind": "web", "source": "test", "summary": "test"}, headers=headers, timeout=5).status_code in {200, 400}
    assert requests.post(base + "/totp/recovery-reset", json={}, headers=headers, timeout=5).status_code in {400, 403}
    broker._pending = None
    alias = requests.post(
        base + "/api/request_approval",
        json={"action": "delete", "target": str(target)},
        headers=headers, timeout=5,
    )
    assert alias.status_code == 200, alias.text
    alias_denied = requests.post(base + "/deny", json={"id": alias.json()["id"]}, headers=headers, timeout=5)
    assert alias_denied.status_code == 200
    assert requests.post(base + "/verify", json={"id": "missing", "code": "123456"}, headers=headers, timeout=5).status_code == 404
    assert requests.post(base + "/trash/undo", json={}, headers=headers, timeout=5).status_code in {400, 404}
    unknown = requests.get(base + "/api/request_approval/status", params={"id": "none"}, headers=headers, timeout=5)
    assert unknown.status_code == 404
    assert requests.get(base + "/unknown", headers=headers, timeout=5).status_code == 404
    assert requests.post(base + "/request", data="{", headers=headers, timeout=5).status_code == 400


def test_inprocess_totp_bind_and_post_404(http_broker, monkeypatch) -> None:
    base, token, _shared = http_broker
    monkeypatch.setattr(broker, "totp_binding_payload", lambda: {"ok": True})
    headers = {"X-Broker-Token": token}
    assert requests.get(base + "/totp/bind", headers=headers, timeout=5).status_code == 200
    assert requests.post(base + "/unknown", headers=headers, timeout=5).status_code == 400


def test_inprocess_handler_500(http_broker, monkeypatch) -> None:
    base, token, _shared = http_broker
    monkeypatch.setattr(broker, "record_external_read", lambda _payload: (_ for _ in ()).throw(RuntimeError("boom")))
    response = requests.post(base + "/external-read", json={"kind": "web", "source": "x", "summary": "x"}, headers={"X-Broker-Token": token}, timeout=5)
    assert response.status_code == 500


def test_inprocess_duplicate_pending_409(http_broker) -> None:
    base, token, shared = http_broker
    headers = {"X-Broker-Token": token}
    broker._last_request_at = 0.0
    broker._request_buckets.clear()
    target = shared / "dup.txt"
    target.write_text("x", encoding="utf-8")
    first = requests.post(base + "/request", json={"action": "delete", "target": str(target), "approval_only": True}, headers=headers, timeout=5)
    broker._request_buckets.clear()
    assert first.status_code == 200, first.text
    second = requests.post(base + "/request", json={"action": "delete", "target": str(target), "approval_only": True}, headers=headers, timeout=5)
    assert second.status_code == 409
    requests.post(base + "/deny", json={"id": first.json()["id"]}, headers=headers, timeout=5)


def test_inprocess_empty_pending_views(http_broker) -> None:
    base, token, _shared = http_broker
    headers = {"X-Broker-Token": token}
    assert requests.get(base + "/pending", headers=headers, timeout=5).json()["pending"] is False
    assert requests.get(base + "/pending/approval", headers=headers, timeout=5).json()["pending"] is False
    assert requests.get(base + "/trash", headers=headers, timeout=5).json()["items"] == []


def test_inprocess_get_unknown_and_bad_verify(http_broker) -> None:
    base, token, _shared = http_broker
    headers = {"X-Broker-Token": token}
    assert requests.get(base + "/nope", headers=headers, timeout=5).status_code == 404
    assert requests.post(base + "/verify", json={}, headers=headers, timeout=5).status_code == 404
    assert requests.post(base + "/deny", json={}, headers=headers, timeout=5).status_code == 400
