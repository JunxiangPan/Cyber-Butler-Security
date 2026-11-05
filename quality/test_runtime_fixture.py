#!/usr/bin/env python3
"""Real-process Broker fixture with per-case HTTP evidence.

No Mock/Stub is used for the Broker, TOTP algorithm, file move, rate limit or
audit log. CBS_TEST_MODE only replaces the Windows DPAPI/ACL bootstrap so the
fixture can run outside the installed service account.
"""
from __future__ import annotations

import json
import os
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
PORT = int(os.environ.get("CBS_TEST_PORT", "18099"))
SECRET = pyotp.random_base32()
HOST = "127.0.0.1"
BASE = f"http://{HOST}:{PORT}"
EVIDENCE = ROOT / "quality" / "artifacts" / "runtime_fixture"


def wait_port(timeout: float = 20.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket() as sock:
            sock.settimeout(0.5)
            if sock.connect_ex((HOST, PORT)) == 0:
                return
        time.sleep(0.25)
    raise RuntimeError("broker did not listen")


def post(path: str, payload: dict, token: str) -> requests.Response:
    return requests.post(
        BASE + path,
        json=payload,
        headers={"X-Broker-Token": token},
        timeout=10,
    )


def main() -> int:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    records: list[dict[str, object]] = []
    lines: list[str] = []

    def record(case: str, method: str, path: str, response: requests.Response) -> None:
        body = response.text.replace("\n", " ")[:180]
        line = f"CASE={case} METHOD={method} PATH={path} HTTP={response.status_code} BODY={body}"
        print(line)
        lines.append(line)
        records.append({"case": case, "method": method, "path": path, "http": response.status_code, "body": body})

    temporary = tempfile.mkdtemp(prefix="cbs-fixture-")
    root = Path(temporary)
    process: subprocess.Popen[str] | None = None
    exit_code = 1
    try:
        shared = root / "shared"
        (root / "tools" / "broker").mkdir(parents=True)
        (root / "tools" / "logs").mkdir(parents=True)
        (root / "webui" / "data").mkdir(parents=True)
        shared.mkdir()
        token = "fixture-token-" + "x" * 32
        (root / "tools" / "broker_token.txt").write_text(token, encoding="utf-8")
        (root / "tools" / "broker_config.json").write_text(
            json.dumps({"approval_channel": "webui"}), encoding="utf-8"
        )
        env = dict(os.environ)
        env.update({
            "CBS_TEST_MODE": "1",
            "CBS_TEST_ROOT": str(root),
            "CBS_TEST_SHARED": str(shared),
            "CBS_TEST_PORT": str(PORT),
            "CBS_TEST_TOTP_SECRET": SECRET,
            "PYTHONIOENCODING": "utf-8",
        })
        process = subprocess.Popen(
            [sys.executable, str(BROKER)],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        (EVIDENCE / "broker_process.txt").write_text(
            f"pid={process.pid}\ncommand={sys.executable} {BROKER}\nport={PORT}\n",
            encoding="utf-8",
        )
        wait_port()

        no_token = requests.get(BASE + "/pending", timeout=5)
        record("no_token", "GET", "/pending", no_token)
        assert no_token.status_code == 403, no_token.text

        no_token_request = requests.post(BASE + "/request", json={"action": "delete", "target": str(shared / "x.txt")}, timeout=5)
        record("no_token_request", "POST", "/request", no_token_request)
        assert no_token_request.status_code == 403, no_token_request.text
        no_token_verify = requests.post(BASE + "/verify", json={"id": "x", "code": "000000"}, timeout=5)
        record("no_token_verify", "POST", "/verify", no_token_verify)
        assert no_token_verify.status_code == 403, no_token_verify.text
        no_token_trash = requests.get(BASE + "/trash", timeout=5)
        record("no_token_trash", "GET", "/trash", no_token_trash)
        assert no_token_trash.status_code == 403, no_token_trash.text
        no_token_undo = requests.post(BASE + "/trash/undo", json={"id": "x"}, timeout=5)
        record("no_token_trash_undo", "POST", "/trash/undo", no_token_undo)
        assert no_token_undo.status_code == 403, no_token_undo.text
        forged = requests.post(BASE + "/request", json={"action": "delete", "target": str(shared / "x.txt")}, headers={"X-Broker-Token": "deadbeef"}, timeout=5)
        record("forged_token", "POST", "/request", forged)
        assert forged.status_code == 403, forged.text

        target = shared / "fixture-delete.txt"
        target.write_text("fixture", encoding="utf-8")
        request = post("/request", {
            "action": "delete",
            "target": str(target),
            "reason": "fixture",
            "source": "fixture",
        }, token)
        record("request_delete", "POST", "/request", request)
        assert request.status_code == 200, request.text
        assert "QQ" not in request.text
        pending = request.json()
        assert pending.get("id"), pending
        assert pending.get("status") == "requires_totp", pending

        wrong = post("/verify", {"id": pending["id"], "code": "000000"}, token)
        record("bad_totp", "POST", "/verify", wrong)
        assert wrong.status_code == 403, wrong.text
        wrong_second = post("/verify", {"id": pending["id"], "code": "000001"}, token)
        record("bad_totp_second", "POST", "/verify", wrong_second)
        assert wrong_second.status_code == 403, wrong_second.text

        code = pyotp.TOTP(SECRET).now()
        good = post("/verify", {"id": pending["id"], "code": code}, token)
        record("good_totp", "POST", "/verify", good)
        assert good.status_code == 200, good.text
        assert not target.exists()

        trash = requests.get(BASE + "/trash", headers={"X-Broker-Token": token}, timeout=5)
        record("trash_list", "GET", "/trash", trash)
        assert trash.status_code == 200, trash.text

        replay_target = shared / "fixture-replay.txt"
        replay_target.write_text("replay", encoding="utf-8")
        replay_request = post("/request", {
            "action": "delete",
            "target": str(replay_target),
            "reason": "replay",
            "source": "fixture",
        }, token)
        record("replay_request", "POST", "/request", replay_request)
        assert replay_request.status_code == 200, replay_request.text
        replay_id = replay_request.json()["id"]
        replay = post("/verify", {"id": replay_id, "code": code}, token)
        record("replay", "POST", "/verify", replay)
        assert replay.status_code == 429, replay.text
        assert replay_target.exists(), "replay must not delete"

        repeat = post("/verify", {"id": pending["id"], "code": code}, token)
        record("verify_repeat", "POST", "/verify", repeat)
        assert repeat.status_code == 404, repeat.text

        undo = post("/trash/undo", {"id": pending["id"]}, token)
        record("trash_undo", "POST", "/trash/undo", undo)
        assert undo.status_code == 200, undo.text
        assert target.exists(), "undo must restore the file"

        after_undo = post("/verify", {"id": pending["id"], "code": code}, token)
        record("verify_after_undo", "POST", "/verify", after_undo)
        assert after_undo.status_code == 404, after_undo.text

        audit = root / "tools" / "totp_broker_audit.jsonl"
        audit_lines = audit.read_text(encoding="utf-8").splitlines()[-5:] if audit.is_file() else []
        (EVIDENCE / "audit_tail.jsonl").write_text("\n".join(audit_lines) + "\n", encoding="utf-8")
        (EVIDENCE / "http_statuses.json").write_text(
            json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        (EVIDENCE / "run.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
        (EVIDENCE / "exit_code.txt").write_text("0\n", encoding="utf-8")
        print("RUNTIME_FIXTURE_OK")
        print("EVIDENCE=" + str(EVIDENCE / "http_statuses.json"))
        exit_code = 0
        return 0
    except Exception as exc:
        (EVIDENCE / "run.txt").write_text("\n".join(lines) + "\nERROR=" + repr(exc) + "\n", encoding="utf-8")
        (EVIDENCE / "http_statuses.json").write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        (EVIDENCE / "exit_code.txt").write_text("1\n", encoding="utf-8")
        raise
    finally:
        if process is not None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            stdout, stderr = process.communicate()
            (EVIDENCE / "broker_process.txt").write_text(
                f"pid={process.pid}\ncommand={sys.executable} {BROKER}\nport={PORT}\n"
                f"returncode={process.returncode}\nstdout_tail={stdout[-2000:]}\nstderr_tail={stderr[-2000:]}\n",
                encoding="utf-8",
            )
        subprocess.run(["icacls", str(root), "/reset", "/T", "/C"], capture_output=True, text=True)
        if exit_code == 0:
            (EVIDENCE / "exit_code.txt").write_text("0\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
