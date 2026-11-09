"""P0-4 characterization tests: freeze existing Broker HTTP behavior."""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

import pytest
import requests

ROOT = Path(__file__).resolve().parents[1]
BROKER = ROOT / "tools" / "broker.py"
TOKEN = "characterization-token-" + "x" * 24
SECRET = "JBSWY3DPEHPK3PXP"


def _free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


@pytest.fixture()
def broker_server(tmp_path: Path):
    port = _free_port()
    root = tmp_path / "root"
    shared = root / "workspace"
    (root / "tools" / "broker").mkdir(parents=True)
    (root / "tools" / "logs").mkdir(parents=True)
    shared.mkdir(parents=True)
    (root / "tools" / "broker_token.txt").write_text(TOKEN, encoding="utf-8")
    (root / "tools" / "broker_config.json").write_text(
        json.dumps({"approval_channel": "webui"}), encoding="utf-8"
    )
    env = dict(os.environ)
    env.update({
        "CBS_TEST_MODE": "1",
        "CBS_TEST_ROOT": str(root),
        "CBS_TEST_SHARED": str(shared),
        "CBS_TEST_PORT": str(port),
        "CBS_TEST_TOTP_SECRET": SECRET,
        "CBS_AUDIT_HMAC_KEY": "00" * 32,
        "PYTHONIOENCODING": "utf-8",
    })
    process = subprocess.Popen(
        [sys.executable, str(BROKER)],
        cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
    )
    base = f"http://127.0.0.1:{port}"
    try:
        deadline = time.time() + 20
        while time.time() < deadline:
            try:
                if requests.get(base + "/health", timeout=1).status_code == 200:
                    break
            except requests.RequestException:
                pass
            if process.poll() is not None:
                raise AssertionError(process.stderr.read() if process.stderr else "broker exited")
            time.sleep(0.1)
        else:
            raise AssertionError("broker did not listen")
        yield base, shared, root
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()


def test_health_and_auth_envelope(broker_server) -> None:
    base, _shared, _root = broker_server
    assert requests.get(base + "/health", timeout=5).json() == {"status": "ok"}
    response = requests.get(base + "/pending", timeout=5)
    assert response.status_code == 403
    assert response.json()["error"] == "unauthorized"
    forged = requests.get(base + "/pending", headers={"X-Broker-Token": "wrong"}, timeout=5)
    assert forged.status_code == 403


def test_request_status_verify_error_codes(broker_server) -> None:
    base, shared, _root = broker_server
    headers = {"X-Broker-Token": TOKEN}
    invalid = requests.post(base + "/request", json={"action": "nope", "target": "x"}, headers=headers, timeout=5)
    assert invalid.status_code == 400
    target = shared / "characterization.txt"
    target.write_text("x", encoding="utf-8")
    created = requests.post(
        base + "/request",
        json={"action": "delete", "target": str(target), "approval_only": True},
        headers=headers, timeout=5,
    )
    assert created.status_code == 200, created.text
    challenge = created.json()["id"]
    assert created.json()["status"] == "requires_totp"
    status = requests.get(base + "/api/request_approval/status", params={"id": challenge}, headers=headers, timeout=5)
    assert status.status_code == 200 and status.json()["status"] == "pending"
    bad = requests.post(base + "/verify", json={"id": challenge, "code": "000000"}, headers=headers, timeout=5)
    assert bad.status_code == 403
    unknown = requests.get(base + "/api/request_approval/status", params={"id": "missing"}, headers=headers, timeout=5)
    assert unknown.status_code == 404
    not_found = requests.get(base + "/not-a-route", headers=headers, timeout=5)
    assert not_found.status_code == 404


def test_malformed_json_is_400(broker_server) -> None:
    base, _shared, _root = broker_server
    response = requests.post(
        base + "/request",
        data="{not json",
        headers={"X-Broker-Token": TOKEN, "Content-Type": "application/json"},
        timeout=5,
    )
    assert response.status_code == 400
