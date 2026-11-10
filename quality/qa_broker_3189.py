#!/usr/bin/env python3
"""Isolated QA Broker acceptance on loopback port 3189.

This starts a disposable Broker with its own temp root, QA token and QA-only
TOTP secret. It never reads or changes the production Broker's token, ACL or
TOTP vault. The QA secret exists only in this process environment and is not
written to the repository or the evidence file.
"""
from __future__ import annotations

import hashlib
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

ROOT = Path(__file__).resolve().parents[1]
BROKER = ROOT / "tools" / "broker.py"
PORT = 3189
HOST = "127.0.0.1"
BASE = f"http://{HOST}:{PORT}"
EVIDENCE = ROOT / "quality" / "artifacts" / "qa-broker-3189"


def free_port() -> bool:
    with socket.socket() as sock:
        return sock.connect_ex((HOST, PORT)) != 0


def wait_ready(process: subprocess.Popen[str]) -> None:
    deadline = time.time() + 20
    while time.time() < deadline:
        if process.poll() is not None:
            out, err = process.communicate(timeout=2)
            raise RuntimeError(f"QA Broker exited: {out}\n{err}")
        try:
            if requests.get(BASE + "/health", timeout=1).status_code == 200:
                return
        except requests.RequestException:
            pass
        time.sleep(0.2)
    raise RuntimeError("QA Broker did not become ready")


def main() -> int:
    if not free_port():
        raise SystemExit("REFUSING: 127.0.0.1:3189 is already in use")
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    temp = Path(tempfile.mkdtemp(prefix="cbs-qa-broker-"))
    shared = temp / "workspace"
    (temp / "tools" / "broker").mkdir(parents=True)
    (temp / "tools" / "logs").mkdir(parents=True)
    shared.mkdir()
    token = secrets.token_urlsafe(32)
    secret = pyotp.random_base32()
    token_file = temp / "tools" / "broker_token.txt"
    token_file.write_text(token, encoding="utf-8")
    (temp / "tools" / "broker_config.json").write_text(
        json.dumps({"approval_channel": "webui"}), encoding="utf-8"
    )
    env = dict(os.environ)
    env.update({
        "CBS_TEST_MODE": "1",
        "CBS_TEST_ROOT": str(temp),
        "CBS_TEST_SHARED": str(shared),
        "CBS_TEST_PORT": str(PORT),
        "CBS_TEST_TOTP_SECRET": secret,
        "CBS_AUDIT_HMAC_KEY": "00" * 32,
        "PYTHONIOENCODING": "utf-8",
    })
    process = subprocess.Popen(
        [sys.executable, str(BROKER)],
        cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
    )
    evidence: dict[str, object] = {"port": PORT, "qa_only_secret": "not-written"}
    try:
        wait_ready(process)
        headers = {"X-Broker-Token": token}
        target = shared / "qa-3189-delete.txt"
        target.write_text("QA Broker acceptance target", encoding="utf-8")
        created = requests.post(
            BASE + "/request",
            json={"action": "delete", "target": str(target), "reason": "P0-1 QA acceptance"},
            headers=headers, timeout=10,
        )
        evidence["request_http"] = created.status_code
        evidence["request_body"] = created.json()
        challenge = str(created.json().get("id", ""))
        if created.status_code != 200 or not challenge:
            raise RuntimeError(f"request failed: {created.status_code} {created.text}")
        code = pyotp.TOTP(secret).now()
        verified = requests.post(
            BASE + "/verify", json={"id": challenge, "code": code},
            headers=headers, timeout=10,
        )
        evidence["verify_http"] = verified.status_code
        evidence["verify_body"] = verified.json()
        evidence["target_deleted"] = not target.exists()
        if verified.status_code != 200 or target.exists():
            raise RuntimeError(f"verify failed: {verified.status_code} {verified.text}")
        audit = temp / "tools" / "totp_broker_audit.jsonl"
        audit_text = audit.read_text(encoding="utf-8") if audit.exists() else ""
        evidence["audit_path"] = "temp/tools/totp_broker_audit.jsonl"
        evidence["audit_bytes"] = len(audit_text.encode("utf-8"))
        evidence["audit_sha256"] = hashlib.sha256(audit_text.encode("utf-8")).hexdigest()
        evidence["audit_lines"] = len([line for line in audit_text.splitlines() if line.strip()])
        evidence["qa_token_file"] = "temp/tools/broker_token.txt"
        evidence["qa_secret"] = "QA-only; not written to evidence"
        (EVIDENCE / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        (EVIDENCE / "acceptance.log").write_text(
            "QA_BROKER_3189_OK\n"
            f"request_http={evidence['request_http']}\n"
            f"verify_http={evidence['verify_http']}\n"
            f"target_deleted={evidence['target_deleted']}\n"
            f"audit_lines={evidence['audit_lines']}\n"
            f"audit_sha256={evidence['audit_sha256']}\n",
            encoding="utf-8",
        )
        print(json.dumps(evidence, indent=2))
        print("QA_BROKER_3189_OK")
        return 0
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        # The temp root and QA secret stay outside the repository and are left
        # for operator inspection; they are not copied into evidence or Git.


if __name__ == "__main__":
    raise SystemExit(main())
