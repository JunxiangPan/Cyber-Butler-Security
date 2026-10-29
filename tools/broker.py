#!/usr/bin/env python3
"""SYSTEM TOTP broker exposed only on 127.0.0.1:18090.

YOUR_SERVICE_USER talks to this HTTP service with a local broker token. No files are
used for cross-account TOTP state, which avoids Windows ACL problems.
"""

from __future__ import annotations

import hashlib
import ipaddress
import json
import os
import secrets
import shutil
import subprocess
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pyotp
import requests
import email_approval

try:
    import win32crypt  # Windows-only; tests inject a verifier.
except ImportError:  # pragma: no cover - exercised on Linux CI
    win32crypt = None

ROOT = Path(r"YOUR_PROJECT_PATH")
BROKER = ROOT / "tools" / "broker"
QUARANTINE = BROKER / "quarantine"
STAGING = BROKER / "staging"
SECRET_FILE = ROOT / "tools" / "totp_secret.dpapi"
RECOVERY_FILE = ROOT / "tools" / "totp_recovery.json"
TOKEN_FILE = ROOT / "tools" / "broker_token.txt"
LOG = ROOT / "tools" / "totp_broker.log"
AUDIT = ROOT / "tools" / "totp_broker_audit.jsonl"
SHARED = Path(r"YOUR_USER_PATH\Desktop\大肥鱼专用文件夹")
UMO = "qq_sujinyan:FriendMessage:YOUR_QQ_ID"
HOST = "127.0.0.1"
PORT = 18090
TIMEOUT_SECONDS = 300
REQUEST_RATE_LIMIT_SECONDS = 1.0

_lock = threading.Lock()
_replay_lock = threading.Lock()
_request_rate_lock = threading.Lock()
_last_request_at = 0.0
_used_totp: dict[str, float] = {}
TOTP_REPLAY_TTL = 120
TOTP_MAX_ATTEMPTS = 5
VERIFY_LOCK_SECONDS = 300
GLOBAL_LOCK_BASE_SECONDS = 300
GLOBAL_LOCK_MAX_SECONDS = 86400
_verify_locked_until = 0.0
_global_failures = 0
_global_lock_until = 0.0
_pending: dict | None = None

BROKER_CONFIG = ROOT / "tools" / "broker_config.json"

def _approval_channel() -> str:
    """Return qq or email; fail safe to qq when the config is missing/invalid."""
    try:
        data = json.loads(BROKER_CONFIG.read_text(encoding="utf-8"))
        channel = str(data.get("approval_channel", "qq")).strip().lower()
        return channel if channel in {"qq", "email"} else "qq"
    except (OSError, ValueError):
        return "qq"


_send_events: dict[str, threading.Event] = {}
_send_results: dict[str, bool] = {}


def log(message: str) -> None:
    line = f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {message}"
    print(line, flush=True)
    try:
        with LOG.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError:
        pass


def audit_failure(request_id: str, action: str, target: str, attempts: int) -> None:
    """Record failed verification without logging the attempted code."""
    try:
        AUDIT.parent.mkdir(parents=True, exist_ok=True)
        with AUDIT.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({
                "at": datetime.now().isoformat(timespec="seconds"),
                "id": request_id,
                "action": action,
                "target": target,
                "ok": False,
                "result": "invalid TOTP or recovery code",
                "attempts": attempts,
            }, ensure_ascii=False) + "\n")
    except OSError as exc:
        log(f"audit write failed: {exc}")


def _audit_manifest_reject(request_id: str, request: dict, result: str) -> None:
    try:
        AUDIT.parent.mkdir(parents=True, exist_ok=True)
        with AUDIT.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({
                "at": datetime.now().isoformat(timespec="seconds"),
                "id": request_id,
                "action": request.get("action"),
                "target": request.get("target"),
                "ok": False,
                "result": result,
            }, ensure_ascii=False) + "\n")
    except OSError as exc:
        log(f"audit write failed: {exc}")


def ensure_token() -> str:
    if not TOKEN_FILE.exists():
        token = secrets.token_urlsafe(32)
        TOKEN_FILE.write_text(token, encoding="utf-8")
        subprocess.run(
            ["icacls", str(TOKEN_FILE), "/inheritance:r", "/grant:r",
             "SYSTEM:(F)", "YOUR_SERVICE_USER:(R)", "*S-1-5-32-544:(F)"],
            check=False,
            capture_output=True,
        )
    return TOKEN_FILE.read_text(encoding="utf-8").strip()


def secret() -> str:
    if win32crypt is None:
        raise RuntimeError("win32crypt is required to read the DPAPI secret")
    encrypted = SECRET_FILE.read_bytes()
    plain = win32crypt.CryptUnprotectData(encrypted, None, None, None, 0)
    return plain[1].decode("utf-8")


def send_qq(text: str) -> bool:
    try:
        token = (ROOT / ".astrbot_token").read_text(encoding="utf-8").strip()
        response = requests.post(
            "http://127.0.0.1:6185/api/v1/im/messages",
            headers={"Authorization": f"Bearer {token}"},
            json={"umo": UMO, "message": text},
            timeout=60,
        )
        return response.ok
    except Exception as exc:
        log(f"QQ send failed: {exc}")
        return False


def inside_shared(path: Path) -> bool:
    try:
        path.resolve().relative_to(SHARED.resolve())
        return True
    except ValueError:
        return False


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_manifest(items) -> list[dict]:
    """Validate a complete send manifest and recompute every local hash."""
    if not isinstance(items, list) or not items:
        raise ValueError("manifest is required")
    if len(items) > 5:
        raise ValueError("manifest has more than 5 entries")
    canonical: list[dict] = []
    total_bytes = 0
    for item in items:
        if not isinstance(item, dict):
            raise ValueError("manifest entry must be an object")
        kind = str(item.get("kind", "file")).lower()
        raw_path = str(item.get("path", "")).strip()
        if not raw_path:
            raise ValueError("manifest entry has no path")
        if kind == "url":
            if not raw_path.startswith(("http://", "https://")):
                raise ValueError("manifest URL is invalid")
            canonical.append(
                {"kind": "url", "path": raw_path, "size": 0, "sha256": ""}
            )
            continue
        if kind != "file":
            raise ValueError("unsupported manifest entry kind")
        path = Path(raw_path).resolve(strict=True)
        if not path.is_file():
            raise ValueError("manifest target is not a file")
        size = int(path.stat().st_size)
        total_bytes += size
        if total_bytes > 50 * 1024 * 1024:
            raise ValueError("manifest exceeds 50MB")
        digest = _sha256_file(path)
        expected = str(item.get("sha256", "")).lower()
        expected_size = item.get("size")
        if expected and expected != digest:
            raise ValueError("manifest SHA-256 mismatch")
        if expected_size is not None and int(expected_size) != size:
            raise ValueError("manifest size mismatch")
        canonical.append(
            {"kind": "file", "path": str(path), "size": size, "sha256": digest}
        )
    return canonical


def _manifest_equal(left: list[dict], right: list[dict]) -> bool:
    return json.dumps(left, sort_keys=True, ensure_ascii=False) == json.dumps(
        right, sort_keys=True, ensure_ascii=False
    )


def _fail_send_wait(request_id: str) -> None:
    event = _send_events.get(request_id)
    if event:
        _send_results[request_id] = False
        event.set()


def _path_summary(path_text: str) -> str:
    """Full path + type + size + content hash for an approval prompt."""
    try:
        path = Path(path_text).resolve(strict=False)
    except (OSError, ValueError):
        return f"{path_text} | unresolved"
    if not path.exists():
        return f"{path} | missing"
    if path.is_file():
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return f"{path} | file | {path.stat().st_size} bytes | sha256={digest.hexdigest()}"
    if path.is_dir():
        digest = hashlib.sha256()
        count = 0
        for child in sorted(path.rglob("*")):
            if child.is_file():
                count += 1
                rel = str(child.relative_to(path)).replace("\\", "/")
                digest.update(rel.encode("utf-8", "surrogateescape"))
                digest.update(b"\0")
                digest.update(str(child.stat().st_size).encode("ascii"))
                digest.update(b"\0")
        return f"{path} | directory | {count} files | tree-sha256={digest.hexdigest()}"
    return f"{path} | other"


def _manifest_prompt(manifest: list[dict]) -> str:
    lines = [f"哥，瑾言想发送 {len(manifest)} 个文件，请输入动态验证码。完整清单："]
    for index, item in enumerate(manifest, 1):
        if item["kind"] == "url":
            lines.append(f"{index}. URL: {item['path']} [OUTSIDE SHARED]")
        else:
            path = Path(item["path"])
            marker = "" if inside_shared(path) else " [OUTSIDE SHARED]"
            lines.append(
                f"{index}. {item['path']} | {item['size']} bytes | "
                f"sha256={item['sha256']}{marker}"
            )
    return "\n".join(lines)


def verify_code(code: str) -> str:
    code = code.strip().upper()
    if len(code) == 6 and code.isdigit():
        if pyotp.TOTP(secret()).verify(code, valid_window=1):
            digest = hashlib.sha256(code.encode("utf-8")).hexdigest()
            now = time.time()
            with _replay_lock:
                for old_digest, used_at in list(_used_totp.items()):
                    if now - used_at > TOTP_REPLAY_TTL:
                        _used_totp.pop(old_digest, None)
                if digest in _used_totp:
                    return ""
                _used_totp[digest] = now
            return "totp"
        return ""
    if len(code) == 8 and code.isalnum():
        try:
            store = json.loads(RECOVERY_FILE.read_text(encoding="utf-8"))
            digest = hashlib.sha256(code.encode("utf-8")).hexdigest()
            if digest in store.get("sha256", []) and digest not in store.get("used", []):
                store.setdefault("used", []).append(digest)
                RECOVERY_FILE.write_text(
                    json.dumps(store, ensure_ascii=False, indent=2), encoding="utf-8"
                )
                return "recovery"
        except (OSError, ValueError):
            return ""
    return ""


def execute(request: dict) -> tuple[bool, str]:
    action = request.get("action")
    target = Path(request.get("target", ""))
    if not target or not inside_shared(target):
        return False, "目标不在大肥鱼专用文件夹内，拒绝执行。"
    if action == "delete":
        if not target.exists():
            return False, "目标文件不存在。"
        QUARANTINE.mkdir(parents=True, exist_ok=True)
        trash = QUARANTINE / f"{request['id']}_{target.name}"
        shutil.move(str(target), str(trash))
        return True, f"已把 {target.name} 移到隔离区：{trash.name}"
    if action == "overwrite":
        source = Path(request.get("source", ""))
        if not source.exists():
            return False, "覆盖源文件不存在。"
        source_ok = inside_shared(source)
        try:
            source.resolve().relative_to(STAGING.resolve())
            source_ok = True
        except ValueError:
            pass
        if not source_ok:
            return False, "覆盖源文件必须在大肥鱼专用文件夹或 broker staging 内。"
        if target.exists():
            QUARANTINE.mkdir(parents=True, exist_ok=True)
            backup = QUARANTINE / f"{request['id']}_{target.name}.bak"
            shutil.copy2(target, backup)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        return True, f"已覆盖 {target.name}，旧版本备份在隔离区。"
    return False, "不支持的操作类型。"


def timeout_watch(request_id: str) -> None:
    global _pending
    time.sleep(TIMEOUT_SECONDS)
    expired = False
    with _lock:
        if _pending and _pending.get("id") == request_id:
            _pending = None
            expired = True
    if expired:
        send_qq("哥，验证码超时了，这次操作没有执行。")
        log(f"timeout: {request_id}")


def _is_verification_locked() -> bool:
    return time.monotonic() < max(_verify_locked_until, _global_lock_until)


def _record_global_failure() -> float:
    """Record a failure even if the pending request is later cleared/expired."""
    global _global_failures, _global_lock_until
    _global_failures += 1
    if _global_failures < TOTP_MAX_ATTEMPTS:
        return 0.0
    exponent = max(0, _global_failures - TOTP_MAX_ATTEMPTS)
    delay = min(GLOBAL_LOCK_BASE_SECONDS * (2 ** exponent), GLOBAL_LOCK_MAX_SECONDS)
    _global_lock_until = max(_global_lock_until, time.monotonic() + delay)
    return delay


def email_watch(request_id: str) -> None:
    """Poll IMAP for the owner's APPROVE reply and execute exactly one Pending."""
    global _pending
    try:
        config = email_approval.load_config()
    except Exception as exc:
        log(f"email config failed: {exc}")
        with _lock:
            if _pending and _pending.get("id") == request_id:
                _pending = None
        return

    while True:
        with _lock:
            if not _pending or _pending.get("id") != request_id or _pending.get("channel") != "email":
                return
            request = dict(_pending)
            deadline = float(request.get("deadline", 0))
        if time.monotonic() > deadline:
            break
        try:
            reply = email_approval.poll_once(config, str(request.get("challenge", "")))
        except Exception as exc:
            log(f"IMAP poll failed: {exc}")
            time.sleep(5)
            continue
        if not reply:
            time.sleep(5)
            continue
        from_header, challenge, totp = reply
        if not email_approval.sender_allowed(from_header, config["allowed_sender"]):
            log("email approval ignored: sender not allowed")
            continue
        with _lock:
            if not _pending or _pending.get("id") != request_id:
                return
            actual_challenge = str(_pending.get("challenge", ""))
            request = dict(_pending)
        if challenge != actual_challenge:
            log("email approval ignored: challenge mismatch")
            continue
        if verify_code(totp) is None:
            with _lock:
                if _pending and _pending.get("id") == request_id:
                    _pending["attempts"] = int(_pending.get("attempts", 0)) + 1
                    if _pending["attempts"] >= TOTP_MAX_ATTEMPTS:
                        _pending = None
                        log("email approval locked after too many failures")
                        return
            log("email approval ignored: invalid TOTP")
            continue
        if _path_summary(str(request.get("target", ""))) != request.get("target_summary"):
            with _lock:
                _pending = None
            _email_result(config, request, "target changed before approval")
            return
        if request.get("action") == "overwrite":
            if _path_summary(str(request.get("source", ""))) != request.get("source_summary"):
                with _lock:
                    _pending = None
                _email_result(config, request, "source changed before approval")
                return
        with _lock:
            _pending = None
        ok, result = execute(request)
        log(f"email approved: {request_id} ok={ok} {result}")
        _email_result(config, request, result)
        return

    with _lock:
        if _pending and _pending.get("id") == request_id:
            _pending = None
    try:
        email_approval.send_email(
            config,
            f"[Cyber-Butler] 审批超时 #{request.get('challenge', '')}",
            "5 分钟内没有收到有效回复，本次操作已拒绝。",
        )
    except Exception as exc:
        log(f"email timeout notice failed: {exc}")


def _email_result(config: dict, request: dict, result: str) -> None:
    try:
        email_approval.send_email(
            config,
            f"[Cyber-Butler] 审批结果 #{request.get('challenge', '')}",
            f"动作：{request.get('action')}\n目标：{request.get('target')}\n结果：{result}",
        )
    except Exception as exc:
        log(f"email result send failed: {exc}")


def run_request(payload: dict) -> tuple[int, dict]:
    global _pending
    if _is_verification_locked():
        return 429, {"ok": False, "error": "verification is temporarily locked"}
    action = str(payload.get("action", "")).strip().lower()
    target_text = str(payload.get("target", "")).strip()
    target = Path(target_text)
    manifest: list[dict] | None = None
    if action not in {"delete", "overwrite", "send"}:
        return 400, {"ok": False, "error": "action must be delete, overwrite or send"}
    if action in {"delete", "overwrite"} and not inside_shared(target):
        return 403, {"ok": False, "error": "target outside shared folder"}
    if action == "send":
        try:
            manifest = _canonical_manifest(payload.get("manifest"))
        except (OSError, ValueError) as exc:
            return 409, {"ok": False, "error": f"invalid send manifest: {exc}"}
        # The overlay deliberately routes URLs and files outside the shared
        # folder through TOTP. Do not reject them here: the owner sees the
        # complete manifest in the challenge and the approval is bound to it.
        target_text = manifest[0]["path"]
        target = Path(target_text)
        if not (target_text.startswith(("http://", "https://")) or target.exists()):
            return 400, {"ok": False, "error": "send target does not exist"}

    channel = _approval_channel()
    email_mode = channel == "email" and action in {"delete", "overwrite"}
    if channel == "email" and action == "send":
        return 400, {"ok": False, "error": "send is not available in email mode; switch approval_channel to qq"}
    challenge = secrets.token_hex(2).upper() if email_mode else ""

    event = None
    with _lock:
        if _pending:
            return 409, {"ok": False, "error": "another TOTP request is pending"}
        request_id = secrets.token_hex(6)
        _pending = {
            "id": request_id,
            "action": action,
            "target": target_text,
            "source": str(payload.get("source", "")),
            "reason": str(payload.get("reason", ""))[:300],
            "deadline": time.monotonic() + TIMEOUT_SECONDS,
            "manifest": manifest,
            "target_summary": _path_summary(target_text),
            "source_summary": _path_summary(str(payload.get("source", ""))) if action == "overwrite" else "",
            "channel": "email" if email_mode else "qq",
            "challenge": challenge,
        }
        if action == "delete":
            prompt = (
                "哥，瑾言想删除以下对象，请输入动态验证码。\n"
                f"完整路径与哈希：{_path_summary(target_text)}\n"
                f"请求号：{request_id}"
            )
        elif action == "overwrite":
            source_text = str(payload.get("source", ""))
            prompt = (
                "哥，瑾言想用源文件覆盖目标文件，请输入动态验证码。\n"
                f"源：{_path_summary(source_text)}\n"
                f"目标：{_path_summary(target_text)}\n"
                f"请求号：{request_id}"
            )
        else:
            prompt = _manifest_prompt(manifest or [])
        if action == "send":
            event = threading.Event()
            _send_events[request_id] = event
            _send_results[request_id] = False

    if email_mode:
        try:
            email_config = email_approval.load_config()
            subject = f"[Cyber-Butler] 待审批请求 #{challenge}"
            body = (
                f"{prompt}\n\n"
                f"回复第一行（只读第一行）：APPROVE #{challenge} TOTP 123456\n"
                f"有效期 5 分钟，仅一次。"
            )
            email_approval.send_email(email_config, subject, body)
        except Exception as exc:
            with _lock:
                if _pending and _pending.get("id") == request_id:
                    _pending = None
            return 502, {"ok": False, "error": f"email challenge send failed: {exc}"}
        threading.Thread(target=email_watch, args=(request_id,), daemon=True).start()
        log(f"email challenge sent: {request_id} {action} {target_text}")
        return 200, {"ok": True, "id": request_id, "channel": "email", "challenge": challenge, "action": action, "target": target_text}

    # Network I/O must never run while _lock is held: send_qq can block for
    # up to 60 seconds, and the lock only protects pending-state transitions.
    if not send_qq(prompt):
        with _lock:
            if _pending and _pending.get("id") == request_id:
                _pending = None
            _send_events.pop(request_id, None)
            _send_results.pop(request_id, None)
        return 502, {"ok": False, "error": "QQ challenge send failed"}

    with _lock:
        if action != "send":
            threading.Thread(target=timeout_watch, args=(request_id,), daemon=True).start()
        log(f"challenge sent: {request_id} {action} {target_text}")

    if action == "send":
        approved = event.wait(TIMEOUT_SECONDS) if event else False
        with _lock:
            result = bool(_send_results.pop(request_id, False))
            _send_events.pop(request_id, None)
            if _pending and _pending.get("id") == request_id:
                _pending = None
        if approved and result:
            return 200, {"ok": True, "approved": True, "id": request_id}
        send_qq("哥，验证码超时了，这次发送没有执行。")
        return 408, {"ok": False, "approved": False, "error": "verification timed out"}

    return 200, {"ok": True, "id": request_id, "action": action, "target": target_text}


def run_verify(payload: dict) -> tuple[int, dict]:
    global _pending, _verify_locked_until, _global_failures, _global_lock_until
    request_id = str(payload.get("id", "")).strip()
    code = str(payload.get("code", "")).strip()
    if _is_verification_locked():
        return 429, {"ok": False, "error": "verification is temporarily locked"}
    with _lock:
        if not _pending:
            return 404, {"ok": False, "error": "pending request not found or expired"}
        if not request_id:
            request_id = str(_pending.get("id", ""))
        if _pending.get("id") != request_id:
            return 404, {"ok": False, "error": "pending request not found or expired"}
        if _pending.get("channel") == "email":
            return 403, {"ok": False, "error": "email approval required"}
        if time.monotonic() > float(_pending.get("deadline", 0)):
            _pending = None
            return 410, {"ok": False, "error": "verification code expired"}
        code_type = verify_code(code)
        if not code_type:
            attempts = int(_pending.get("attempts", 0)) + 1
            _pending["attempts"] = attempts
            delay = _record_global_failure()
            audit_failure(
                request_id,
                str(_pending.get("action", "")),
                str(_pending.get("target", "")),
                attempts,
            )
            if attempts >= TOTP_MAX_ATTEMPTS:
                _pending = None
                _verify_locked_until = time.monotonic() + VERIFY_LOCK_SECONDS
                log(
                    f"verification locked after {attempts} failures: {request_id} "
                    f"(global_failures={_global_failures}, backoff={delay:.0f}s)"
                )
                return 429, {
                    "ok": False,
                    "error": "too many invalid attempts; verification locked",
                    "attempts": attempts,
                }
            return 403, {
                "ok": False,
                "error": "invalid verification code",
                "attempts": attempts,
            }
        _global_failures = 0
        _global_lock_until = 0.0
        request = dict(_pending)
        if request.get("action") == "send":
            manifest = request.get("manifest")
            try:
                current = _canonical_manifest(manifest)
            except (OSError, ValueError) as exc:
                _pending = None
                _audit_manifest_reject(request_id, request, f"manifest invalid at approval: {exc}")
                _fail_send_wait(request_id)
                return 409, {"ok": False, "error": f"file manifest changed: {exc}"}
            if not _manifest_equal(manifest, current):
                _pending = None
                _audit_manifest_reject(request_id, request, "manifest changed at approval")
                _fail_send_wait(request_id)
                return 409, {"ok": False, "error": "file manifest changed before approval"}
        _pending = None
        if request.get("action") in {"delete", "overwrite"}:
            if _path_summary(str(request.get("target", ""))) != request.get("target_summary"):
                return 409, {"ok": False, "error": "target changed before approval"}
            if request.get("action") == "overwrite":
                if _path_summary(str(request.get("source", ""))) != request.get("source_summary"):
                    return 409, {"ok": False, "error": "source changed before approval"}
        if request.get("action") == "send":
            _send_results[request_id] = True
            event = _send_events.get(request_id)
            if event:
                event.set()
            with AUDIT.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps({
                    "at": datetime.now().isoformat(timespec="seconds"),
                    "id": request_id,
                    "action": "send",
                    "target": request.get("target"),
                    "ok": True,
                    "result": "TOTP approved for file send",
                    "code_type": code_type,
                }, ensure_ascii=False) + "\n")
            log(f"send approved: {request_id} {request.get('target')}")
            return 200, {"ok": True, "approved": True, "id": request_id, "result": "已授权发送"}

    ok, result = execute(request)
    send_qq(result)
    with AUDIT.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({
            "at": datetime.now().isoformat(timespec="seconds"),
            "id": request_id,
            "action": request.get("action"),
            "target": request.get("target"),
            "ok": ok,
            "result": result,
            "code_type": code_type,
        }, ensure_ascii=False) + "\n")
    log(f"executed: {request_id} ok={ok} {result}")
    return (200 if ok else 500), {"ok": ok, "id": request_id, "result": result}


class Handler(BaseHTTPRequestHandler):
    server_version = "AstrBotTOTPBroker/1.0"

    def _json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self) -> bool:
        expected = ensure_token()
        provided = self.headers.get("X-Broker-Token", "")
        return secrets.compare_digest(provided, expected)

    def _local_only(self) -> bool:
        host = str(self.client_address[0] if self.client_address else "").strip()
        try:
            if host and ipaddress.ip_address(host).is_loopback:
                return True
        except ValueError:
            pass
        self._json(403, {"ok": False, "error": "loopback access only"})
        log(f"rejected non-loopback client: {host}")
        return False

    def _body(self) -> dict:
        length = min(int(self.headers.get("Content-Length", "0") or 0), 65536)
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw.decode("utf-8", errors="replace"))

    def do_GET(self) -> None:
        if not self._local_only():
            return
        if self.path == "/health":
            self._json(200, {"ok": True, "service": "totp-broker"})
        elif self.path == "/pending":
            # Read-only hint for the local dashboard. Never expose the TOTP,
            # email challenge, full path, manifest or reason.
            with _lock:
                pending = dict(_pending) if _pending else None
            if not pending:
                self._json(200, {"ok": True, "pending": False})
            else:
                action = str(pending.get("action", ""))
                target_name = ""
                if action in {"delete", "overwrite"}:
                    target_name = Path(str(pending.get("target", ""))).name
                remaining = max(0, int(float(pending.get("deadline", 0)) - time.monotonic()))
                self._json(200, {
                    "ok": True,
                    "pending": True,
                    "id_prefix": str(pending.get("id", ""))[:8],
                    "action": action,
                    "channel": str(pending.get("channel", "")),
                    "target_name": target_name,
                    "remaining_seconds": remaining,
                })
        else:
            self._json(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:
        if not self._local_only():
            return
        if not self._auth():
            self._json(401, {"ok": False, "error": "unauthorized"})
            return
        try:
            payload = self._body()
        except (ValueError, TypeError):
            self._json(400, {"ok": False, "error": "invalid JSON"})
            return
        try:
            if self.path == "/request":
                with _request_rate_lock:
                    global _last_request_at
                    now = time.monotonic()
                    if now - _last_request_at < REQUEST_RATE_LIMIT_SECONDS:
                        self._json(429, {"ok": False, "error": "request rate limited"})
                        return
                    _last_request_at = now
                status, body = run_request(payload)
            elif self.path == "/verify":
                status, body = run_verify(payload)
            else:
                status, body = 404, {"ok": False, "error": "not found"}
        except Exception as exc:
            log(f"HTTP handler error: {exc}")
            status, body = 500, {"ok": False, "error": str(exc)}
        self._json(status, body)

    def log_message(self, fmt: str, *args) -> None:
        log("http: " + fmt % args)


def verify_runtime_acl() -> None:
    """Fail closed unless the SYSTEM runner's script roots pass the ACL check."""
    if os.name != "nt":
        return
    checker = ROOT / "tools" / "verify_broker_acl.ps1"
    if not checker.exists():
        raise SystemExit(
            "Broker refuses to start: tools/verify_broker_acl.ps1 is missing; "
            "lock down tools/ and AstrBot/.venv before running as SYSTEM."
        )
    result = subprocess.run(
        [
            "powershell.exe",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy", "Bypass",
            "-File", str(checker),
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise SystemExit(
            "Broker refuses to start: runtime ACL is writable or owned by a "
            f"low-privilege principal. {detail}"
        )
    log("runtime ACL check passed (tools/ and AstrBot/.venv locked)")


def main() -> None:
    verify_runtime_acl()
    ensure_token()
    QUARANTINE.mkdir(parents=True, exist_ok=True)
    STAGING.mkdir(parents=True, exist_ok=True)
    log(f"broker HTTP listening on {HOST}:{PORT}")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
