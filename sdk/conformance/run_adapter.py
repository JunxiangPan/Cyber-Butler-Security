#!/usr/bin/env python3
"""Run the external OpenAI function-tool adapter against a disposable Broker."""
from __future__ import annotations

import json
import os
import secrets
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import pyotp
import requests

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from sdk.adapters.broker_tools import ADAPTER_NAME, ADAPTER_VERSION, BrokerToolAdapter

PORT = 3191
BASE = f"http://127.0.0.1:{PORT}"
OUT = ROOT / "sdk" / "conformance" / "adapter-run.json"
CASES = ROOT / "sdk" / "conformance" / "cases.json"


def wait(port: int) -> None:
    for _ in range(100):
        try:
            if requests.get(f"http://127.0.0.1:{port}/health", timeout=1).status_code == 200:
                return
        except requests.RequestException:
            pass
        time.sleep(0.2)
    raise RuntimeError("adapter QA Broker did not start")


def main() -> int:
    with socket.socket() as sock:
        if sock.connect_ex(("127.0.0.1", PORT)) == 0:
            raise SystemExit(f"REFUSING: port {PORT} is already in use")
    temp = Path(tempfile.mkdtemp(prefix="cbs-adapter-3191-"))
    shared = temp / "workspace"
    (temp / "tools" / "broker").mkdir(parents=True)
    (temp / "tools" / "logs").mkdir(parents=True)
    shared.mkdir()
    token = secrets.token_urlsafe(32)
    secret = pyotp.random_base32()
    (temp / "tools" / "broker_token.txt").write_text(token, encoding="utf-8")
    (temp / "tools" / "broker_config.json").write_text('{"approval_channel": "webui"}', encoding="utf-8")
    env = dict(os.environ)
    env.update({
        "CBS_TEST_MODE": "1", "CBS_TEST_ROOT": str(temp), "CBS_TEST_SHARED": str(shared),
        "CBS_TEST_PORT": str(PORT), "CBS_TEST_TOTP_SECRET": secret,
        "CBS_AUDIT_HMAC_KEY": "00" * 32, "PYTHONIOENCODING": "utf-8",
    })
    process = subprocess.Popen([sys.executable, str(ROOT / "tools" / "broker.py")], cwd=ROOT, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")
    try:
        wait(PORT)
        adapter = BrokerToolAdapter(BASE, token)
        cases = json.loads(CASES.read_text(encoding="utf-8"))["cases"]
        target = shared / "adapter-delete.txt"
        target.write_text("adapter", encoding="utf-8")
        status_request = adapter.call(
            "broker_request", {"target": str(target), "reason": "P0-2 status", "approval_only": True}
        )
        assert status_request["http"] == 200, status_request
        status = adapter.call("broker_status", {"id": status_request["body"]["id"]})
        assert status["http"] == 200, status
        denied = adapter.call(
            "broker_verify", {"id": status_request["body"]["id"], "code": pyotp.TOTP(secret).now()}
        )
        assert denied["http"] == 200, denied
        request = adapter.call("broker_request", {"target": str(target), "reason": "P0-2 adapter conformance"})
        assert request["http"] == 200, request
        verify = adapter.call(
            "broker_verify",
            {"id": request["body"]["id"], "code": pyotp.TOTP(secret).at(time.time() + 30)},
        )
        assert verify["http"] == 200, verify
        audit = temp / "tools" / "totp_broker_audit.jsonl"
        evidence = {
            "adapter": ADAPTER_NAME, "version": ADAPTER_VERSION,
            "cases": [case["name"] for case in cases],
            "port": PORT, "request_http": request["http"], "status_http": status["http"],
            "verify_http": verify["http"], "target_deleted": not target.exists(),
            "audit_lines": len(audit.read_text(encoding="utf-8").splitlines()) if audit.exists() else 0,
            "qa_only_secret": "not-written",
        }
        OUT.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(evidence, indent=2))
        print("ADAPTER_CONFORMANCE_OK")
        return 0
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()


if __name__ == "__main__":
    raise SystemExit(main())
