#!/usr/bin/env python3
"""SYSTEM TOTP broker exposed only on 127.0.0.1:18090.

YOUR_SERVICE_USER talks to this HTTP service with a local broker token. No files are
used for cross-account TOTP state, which avoids Windows ACL problems.
"""

from __future__ import annotations

import ctypes
import ctypes.wintypes as wintypes
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
from urllib.parse import parse_qs, urlparse

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
TOTP_VAULT = ROOT / "tools" / "totp-vault"
SECRET_FILE = TOTP_VAULT / "totp_secret.dpapi"
RECOVERY_FILE = TOTP_VAULT / "recovery_hashes.json"
LEGACY_SECRET_FILE = ROOT / "tools" / "totp_secret.dpapi"
LEGACY_RECOVERY_FILE = ROOT / "tools" / "totp_recovery.json"
TOKEN_FILE = ROOT / "tools" / "broker_token.txt"
LOG = ROOT / "tools" / "totp_broker.log"
AUDIT = ROOT / "tools" / "totp_broker_audit.jsonl"
SHARED = Path(r"YOUR_USER_PATH\Desktop\大肥鱼专用文件夹")
UMO = "qq_sujinyan:FriendMessage:YOUR_QQ_ID"
HOST = "127.0.0.1"
PORT = 18090
TIMEOUT_SECONDS = 300
REQUEST_RATE_LIMIT_SECONDS = 1.0

# ---------------------------------------------------------------------------
# Windows Job Object: KILL_ON_JOB_CLOSE
# ---------------------------------------------------------------------------
# The broker is started by Task Scheduler as SYSTEM. The job object is created
# before any child process is spawned, and the broker assigns itself to it.
# Every child (and grandchild) that does not explicitly break away inherits the
# job; when the last job handle closes (including a broker crash), Windows
# terminates the whole tree.
#
# This protects processes spawned by the broker. AstrBot is started by a
# separate scheduled task, so it is NOT automatically in this job; see the
# caveat in SECURITY.md before claiming that AstrBot's children are covered.
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000
JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
_job_handle = None


class _JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("PerProcessUserTimeLimit", ctypes.c_longlong),
        ("PerJobUserTimeLimit", ctypes.c_longlong),
        ("LimitFlags", wintypes.DWORD),
        ("MinimumWorkingSetSize", ctypes.c_size_t),
        ("MaximumWorkingSetSize", ctypes.c_size_t),
        ("ActiveProcessLimit", wintypes.DWORD),
        ("Affinity", ctypes.c_size_t),
        ("PriorityClass", wintypes.DWORD),
        ("SchedulingClass", wintypes.DWORD),
    ]


class _IO_COUNTERS(ctypes.Structure):
    _fields_ = [
        ("ReadOperationCount", ctypes.c_ulonglong),
        ("WriteOperationCount", ctypes.c_ulonglong),
        ("OtherOperationCount", ctypes.c_ulonglong),
        ("ReadTransferCount", ctypes.c_ulonglong),
        ("WriteTransferCount", ctypes.c_ulonglong),
        ("OtherTransferCount", ctypes.c_ulonglong),
    ]


class _JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
    _fields_ = [
        ("BasicLimitInformation", _JOBOBJECT_BASIC_LIMIT_INFORMATION),
        ("IoInfo", _IO_COUNTERS),
        ("ProcessMemoryLimit", ctypes.c_size_t),
        ("JobMemoryLimit", ctypes.c_size_t),
        ("PeakProcessMemoryUsed", ctypes.c_size_t),
        ("PeakJobMemoryUsed", ctypes.c_size_t),
    ]


def initialize_job_object() -> bool:
    """Put this process and its future children in a kill-on-close job.

    Must be called before the broker spawns PowerShell, icacls, Python, or any
    other child. Returns True on Windows, False on non-Windows platforms.
    Raises SystemExit on Windows if the job cannot be installed (fail closed).
    """
    global _job_handle
    if os.name != "nt":
        return False
    if _job_handle is not None:
        return True

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
    kernel32.CreateJobObjectW.restype = wintypes.HANDLE
    kernel32.SetInformationJobObject.argtypes = [
        wintypes.HANDLE,
        ctypes.c_int,
        ctypes.c_void_p,
        wintypes.DWORD,
    ]
    kernel32.SetInformationJobObject.restype = wintypes.BOOL
    kernel32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
    kernel32.AssignProcessToJobObject.restype = wintypes.BOOL
    kernel32.IsProcessInJob.argtypes = [
        wintypes.HANDLE,
        wintypes.HANDLE,
        ctypes.POINTER(wintypes.BOOL),
    ]
    kernel32.IsProcessInJob.restype = wintypes.BOOL
    kernel32.GetCurrentProcess.argtypes = []
    kernel32.GetCurrentProcess.restype = wintypes.HANDLE
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel32.CloseHandle.restype = wintypes.BOOL

    job = kernel32.CreateJobObjectW(None, None)
    if not job:
        raise SystemExit(
            "Broker refuses to start: CreateJobObjectW failed: "
            + str(ctypes.WinError(ctypes.get_last_error()))
        )

    info = _JOBOBJECT_EXTENDED_LIMIT_INFORMATION()
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
    if not kernel32.SetInformationJobObject(
        job,
        JOB_OBJECT_EXTENDED_LIMIT_INFORMATION,
        ctypes.byref(info),
        ctypes.sizeof(info),
    ):
        error = ctypes.WinError(ctypes.get_last_error())
        kernel32.CloseHandle(job)
        raise SystemExit(
            "Broker refuses to start: SetInformationJobObject failed: " + str(error)
        )

    process = kernel32.GetCurrentProcess()
    already = wintypes.BOOL()
    kernel32.IsProcessInJob(process, None, ctypes.byref(already))

    if not kernel32.AssignProcessToJobObject(job, process):
        error_code = ctypes.get_last_error()
        error = ctypes.WinError(error_code)
        kernel32.CloseHandle(job)
        if already.value:
            raise SystemExit(
                "Broker refuses to start: process is already in a job and "
                "cannot be assigned to the kill-on-close job: " + str(error)
            )
        raise SystemExit(
            "Broker refuses to start: AssignProcessToJobObject failed: " + str(error)
        )

    _job_handle = job
    log(
        "job object active: KILL_ON_JOB_CLOSE is set for broker and its "
        "future descendants"
    )
    return True


def close_job_object() -> None:
    """Close the job handle explicitly; KILL_ON_JOB_CLOSE then kills children."""
    global _job_handle
    if os.name != "nt" or _job_handle is None:
        return
    try:
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
        kernel32.CloseHandle.restype = wintypes.BOOL
        kernel32.CloseHandle(_job_handle)
    finally:
        _job_handle = None


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

BYPASS_TTL_SECONDS = 30
_bypass_lock = threading.Lock()
_bypass_tokens: dict[str, dict] = {}

APPROVAL_STATE_TTL_SECONDS = 600
_approval_lock = threading.Lock()
_approval_states: dict[str, dict] = {}

SCOPED_TTL_SECONDS = 1800
SCOPED_MAX_MINUTES = 30
_scoped_lock = threading.Lock()
_scoped_tokens: dict[str, dict] = {}

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


UIPI_BLOCKED_EVENT = "UIPI_BLOCKED_GUI_INTERACTION"


def report_uipi_blocked(operation: str, detail: str = "") -> None:
    """Record a GUI interaction that returned no result under UIPI/AppContainer.

    UIPI can silently discard window messages; callers should invoke this when
    a future GUI operation returns None/False instead of raising. The event is
    intentionally separate from TOTP decisions so operators can alert on it.
    """
    record = {
        "at": datetime.now().isoformat(timespec="seconds"),
        "event": UIPI_BLOCKED_EVENT,
        "operation": str(operation or "unknown"),
        "detail": str(detail or "")[:500],
        "ok": False,
    }
    log(f"{UIPI_BLOCKED_EVENT}: {record['operation']}")
    try:
        AUDIT.parent.mkdir(parents=True, exist_ok=True)
        with AUDIT.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError as exc:
        log(f"UIPI audit write failed: {exc}")


def guard_gui_result(operation: str, result: object) -> object:
    """Treat None/False from a future GUI call as a possible silent UIPI drop."""
    if result is None or result is False:
        report_uipi_blocked(operation, "GUI returned no result; possible UIPI drop")
    return result


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


def _secret_file() -> Path:
    if SECRET_FILE.is_file():
        return SECRET_FILE
    if LEGACY_SECRET_FILE.is_file():
        return LEGACY_SECRET_FILE
    return SECRET_FILE


def _recovery_file() -> Path:
    if RECOVERY_FILE.is_file():
        return RECOVERY_FILE
    if LEGACY_RECOVERY_FILE.is_file():
        return LEGACY_RECOVERY_FILE
    return RECOVERY_FILE


def secret() -> str:
    if win32crypt is None:
        raise RuntimeError("win32crypt is required to read the DPAPI secret")
    encrypted = _secret_file().read_bytes()
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


TMP_ROOTS = (
    ROOT / "workspace" / "tmp",
    ROOT / "AstrBot" / "data" / "tmp",
    ROOT / "AstrBot" / "data" / "temp",
    ROOT / "AstrBot" / "data" / "cache",
    ROOT / "AstrBot" / "data" / "logs",
)
MEMORY_ROOTS = (
    ROOT / "AstrBot" / "data" / "memory",
    ROOT / "AstrBot" / "data" / "config",
    ROOT / "AstrBot" / "data" / "cmd_config.json",
)
TOTP_VAULT_ROOT = ROOT / "tools" / "totp-vault"


def _inside_any(path: Path, roots: tuple[Path, ...]) -> bool:
    try:
        resolved = path.resolve(strict=False)
    except (OSError, ValueError):
        return False
    for root in roots:
        try:
            resolved.relative_to(root.resolve(strict=False))
            return True
        except (OSError, ValueError):
            continue
    return False


def classify(action: str, target: str) -> str:
    """Return allow | totp | deny for a broker request.

    This is the server-side policy boundary. The LLM must never be allowed to
    choose its own risk class.
    """
    action = str(action or "").strip().lower()
    if action not in {"delete", "overwrite", "write_file", "send", "send_file"}:
        return "deny"
    if action in {"send", "send_file"}:
        # Every egress manifest is owner-approved as one unit.
        return "totp"
    try:
        path = Path(str(target or "")).resolve(strict=False)
    except (OSError, ValueError):
        return "deny"
    if _inside_any(path, (TOTP_VAULT_ROOT,)):
        return "deny"
    if _inside_any(path, TMP_ROOTS):
        return "allow"
    if _inside_any(path, MEMORY_ROOTS):
        return "totp"
    if inside_shared(path):
        # Creating a brand-new file in the shared workspace is a routine
        # operation. Replacing an existing file remains destructive.
        if action == "write_file" and not path.exists():
            return "allow"
        return "totp"
    return "deny"


def _allowed_target(path: Path) -> bool:
    return inside_shared(path) or _inside_any(path, TMP_ROOTS) or _inside_any(path, MEMORY_ROOTS)


def _target_mode(action: str, target: str) -> str:
    if action == "write_file":
        try:
            return "create" if not Path(target).resolve(strict=False).exists() else "replace"
        except (OSError, ValueError):
            return "replace"
    if action == "overwrite":
        return "replace"
    return action


def _bypass_scope(action: str, target: str) -> str:
    path = Path(target).resolve(strict=False)
    return f"{action}:{_target_mode(action, target)}:{str(path.parent.resolve(strict=False)).casefold()}"


def _purge_bypass(now: float | None = None) -> None:
    moment = time.monotonic() if now is None else now
    for token, record in list(_bypass_tokens.items()):
        if float(record.get("expires", 0)) <= moment:
            _bypass_tokens.pop(token, None)


def _issue_bypass(action: str, target: str, ttl_seconds: int = BYPASS_TTL_SECONDS) -> dict | None:
    if action not in {"delete", "overwrite", "write_file"}:
        return None
    ttl = max(1, min(int(ttl_seconds), BYPASS_TTL_SECONDS))
    scope = _bypass_scope(action, target)
    token = secrets.token_urlsafe(32)
    now = time.monotonic()
    with _bypass_lock:
        _purge_bypass(now)
        _bypass_tokens[token] = {
            "scope": scope,
            "action": action,
            "expires": now + ttl,
            "uses": 0,
        }
    return {"token": token, "expires_in": ttl, "scope": scope}


def _consume_bypass(token: str, action: str, target: str) -> dict | None:
    if not token:
        return None
    scope = _bypass_scope(action, target)
    now = time.monotonic()
    with _bypass_lock:
        _purge_bypass(now)
        record = _bypass_tokens.get(token)
        if not record:
            return None
        if record.get("scope") != scope or record.get("action") != action:
            return None
        record["uses"] = int(record.get("uses", 0)) + 1
        return dict(record)


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
            recovery_path = _recovery_file()
            store = json.loads(recovery_path.read_text(encoding="utf-8"))
            digest = hashlib.sha256(code.encode("utf-8")).hexdigest()
            if digest in store.get("sha256", []) and digest not in store.get("used", []):
                store.setdefault("used", []).append(digest)
                recovery_path.write_text(
                    json.dumps(store, ensure_ascii=False, indent=2), encoding="utf-8"
                )
                return "recovery"
        except (OSError, ValueError):
            return ""
    return ""


def execute(request: dict) -> tuple[bool, str]:
    action = request.get("action")
    target = Path(request.get("target", ""))
    if not target or not _allowed_target(target):
        return False, "目标不在允许的 Broker 路径内，拒绝执行。"
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
        source_ok = inside_shared(source) or _inside_any(source, TMP_ROOTS)
        try:
            source.resolve().relative_to(STAGING.resolve())
            source_ok = True
        except ValueError:
            pass
        if not source_ok:
            return False, "覆盖源文件必须在大肥鱼专用文件夹、tmp 或 broker staging 内。"
        if target.exists():
            QUARANTINE.mkdir(parents=True, exist_ok=True)
            backup = QUARANTINE / f"{request['id']}_{target.name}.bak"
            shutil.copy2(target, backup)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        return True, f"已覆盖 {target.name}，旧版本备份在隔离区。"
    if action == "write_file":
        content = request.get("content")
        if not isinstance(content, str):
            return False, "write_file 需要字符串 content。"
        if len(content.encode("utf-8")) > 256 * 1024:
            return False, "write_file 内容超过 256KB。"
        target.parent.mkdir(parents=True, exist_ok=True)
        if request.get("mode") == "create":
            try:
                with target.open("x", encoding="utf-8") as handle:
                    handle.write(content)
            except FileExistsError:
                return False, "创建模式发现目标已存在；拒绝覆盖。"
            return True, f"已创建 {target.name}（{len(content.encode('utf-8'))} bytes）。"
        temp = target.with_name(target.name + ".broker.tmp")
        temp.write_text(content, encoding="utf-8")
        os.replace(temp, target)
        return True, f"已写入 {target.name}（{len(content.encode('utf-8'))} bytes）。"
    return False, "不支持的操作类型。"


def timeout_watch(request_id: str) -> None:
    global _pending
    time.sleep(TIMEOUT_SECONDS)
    expired = False
    approval_only = False
    with _lock:
        if _pending and _pending.get("id") == request_id:
            approval_only = bool(_pending.get("approval_only"))
            _pending = None
            expired = True
    if expired:
        if approval_only:
            _set_approval_state(request_id, "expired", approval_only=True)
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


def _audit_auto(request: dict, ok: bool, result: str) -> None:
    try:
        AUDIT.parent.mkdir(parents=True, exist_ok=True)
        with AUDIT.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({
                "at": datetime.now().isoformat(timespec="seconds"),
                "id": request.get("id", ""),
                "action": request.get("action"),
                "target": request.get("target"),
                "ok": bool(ok),
                "result": result,
                "auto": True,
            }, ensure_ascii=False) + "\n")
    except OSError as exc:
        log(f"audit write failed: {exc}")


def _scoped_root(target: str) -> Path | None:
    """Return the canonical directory a 30-minute scoped token may cover.

    A scoped token is intentionally limited to the shared scratch tree and
    temporary trees. Memory/config and the TOTP vault never qualify.
    """
    try:
        path = Path(str(target or "")).resolve(strict=False)
    except (OSError, ValueError):
        return None
    if _inside_any(path, (TOTP_VAULT_ROOT,)):
        return None
    root = path.parent.resolve(strict=False)
    if _inside_any(root, (TOTP_VAULT_ROOT,)):
        return None
    if _inside_any(root, (SHARED,)) or _inside_any(root, TMP_ROOTS):
        return root
    return None


def _issue_scoped(action: str, target: str, minutes: int = SCOPED_MAX_MINUTES) -> dict | None:
    if action not in {"delete", "overwrite", "write_file"}:
        return None
    root = _scoped_root(target)
    if root is None:
        return None
    ttl = max(1, min(int(minutes), SCOPED_MAX_MINUTES)) * 60
    token = secrets.token_urlsafe(32)
    now = time.monotonic()
    with _scoped_lock:
        _scoped_tokens[token] = {
            "root": str(root).casefold(),
            "expires": now + ttl,
            "uses": 0,
            "actions": ("delete", "overwrite", "write_file"),
        }
        for key, record in list(_scoped_tokens.items()):
            if float(record.get("expires", 0)) <= now:
                _scoped_tokens.pop(key, None)
    return {"token": token, "expires_in": ttl, "root": str(root)}


def _consume_scoped(token: str, action: str, target: str) -> dict | None:
    if not token or action not in {"delete", "overwrite", "write_file"}:
        return None
    try:
        path = Path(str(target or "")).resolve(strict=False)
    except (OSError, ValueError):
        return None
    if _inside_any(path, (TOTP_VAULT_ROOT,)):
        return None
    now = time.monotonic()
    with _scoped_lock:
        record = _scoped_tokens.get(token)
        if not record or float(record.get("expires", 0)) <= now:
            _scoped_tokens.pop(token, None)
            return None
        if action not in tuple(record.get("actions", ())):
            return None
        try:
            path.relative_to(Path(str(record.get("root", ""))))
        except (OSError, ValueError):
            return None
        record["uses"] = int(record.get("uses", 0)) + 1
        return dict(record)


def _audit_scoped(request: dict, result: str, root: str) -> None:
    try:
        AUDIT.parent.mkdir(parents=True, exist_ok=True)
        with AUDIT.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({
                "at": datetime.now().isoformat(timespec="seconds"),
                "id": request.get("id", ""),
                "action": request.get("action"),
                "target": request.get("target"),
                "ok": True,
                "result": result,
                "scoped": True,
                "scoped_token": "30m_directory",
                "bypass_label": "Scoped via 30-minute Directory Token",
                "scope": root,
            }, ensure_ascii=False) + "\n")
    except OSError as exc:
        log(f"audit write failed: {exc}")


def _as_bool(value: object) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def _set_approval_state(challenge_id: str, status: str, approval_only: bool = True) -> None:
    now = time.monotonic()
    with _approval_lock:
        current = _approval_states.get(challenge_id, {})
        _approval_states[challenge_id] = {
            "id": challenge_id,
            "status": status,
            "approval_only": bool(approval_only),
            "created": float(current.get("created", now)),
            "updated": now,
            "expires": now + APPROVAL_STATE_TTL_SECONDS,
        }
        for key, record in list(_approval_states.items()):
            if float(record.get("expires", 0)) <= now:
                _approval_states.pop(key, None)


def _get_approval_state(challenge_id: str) -> dict | None:
    now = time.monotonic()
    with _approval_lock:
        record = _approval_states.get(challenge_id)
        if not record:
            return None
        if float(record.get("expires", 0)) <= now:
            record["status"] = "expired"
            record["updated"] = now
        return dict(record)


def _audit_bypass(request: dict, result: str, scope: str) -> None:
    try:
        AUDIT.parent.mkdir(parents=True, exist_ok=True)
        with AUDIT.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({
                "at": datetime.now().isoformat(timespec="seconds"),
                "id": request.get("id", ""),
                "action": request.get("action"),
                "target": request.get("target"),
                "ok": True,
                "result": result,
                "bypassed": True,
                "bypass": "30s_session",
                "bypass_label": "Bypassed via 30s Session Token",
                "scope": scope,
            }, ensure_ascii=False) + "\n")
    except OSError as exc:
        log(f"audit write failed: {exc}")


def run_request(payload: dict) -> tuple[int, dict]:
    global _pending
    if _is_verification_locked():
        return 429, {"ok": False, "error": "verification is temporarily locked"}
    action = str(payload.get("action", "")).strip().lower()
    if action == "send_file":
        action = "send"
    approval_only = _as_bool(payload.get("approval_only"))
    if approval_only and action == "send":
        return 400, {"ok": False, "error": "approval_only is not supported for send"}
    target_text = str(payload.get("target", "")).strip()
    target = Path(target_text)
    manifest: list[dict] | None = None
    if action not in {"delete", "overwrite", "write_file", "send"}:
        return 400, {"ok": False, "error": "action must be delete, overwrite, write_file or send"}
    risk = classify(action, target_text)
    if risk == "deny":
        return 403, {"ok": False, "error": "target is not allowed by broker policy"}

    bypass_token = str(payload.get("bypass_token", "") or "")
    if action in {"delete", "overwrite", "write_file"} and risk == "totp" and bypass_token:
        bypass = _consume_bypass(bypass_token, action, target_text)
        if bypass:
            if approval_only:
                return 200, {
                    "ok": True,
                    "status": "allowed",
                    "approval_only": True,
                    "bypassed": True,
                    "id": "",
                    "challenge_id": "",
                }
            request_id = secrets.token_hex(6)
            request = {
                "id": request_id,
                "action": action,
                "target": target_text,
                "source": str(payload.get("source", "")),
                "content": payload.get("content"),
                "mode": _target_mode(action, target_text),
                "reason": str(payload.get("reason", ""))[:300],
            }
            ok, result = execute(request)
            if ok:
                _audit_bypass(request, result, str(bypass.get("scope", "")))
                log(f"bypass executed: {request_id} {action} {target_text}")
                return 200, {"ok": True, "bypassed": True, "id": request_id, "result": result}
            return 400, {"ok": False, "error": result, "bypassed": True}

    scoped_token = str(payload.get("scoped_token", "") or "")
    if action in {"delete", "overwrite", "write_file"} and risk == "totp" and scoped_token:
        scoped = _consume_scoped(scoped_token, action, target_text)
        if scoped:
            if approval_only:
                return 200, {
                    "ok": True,
                    "status": "allowed",
                    "approval_only": True,
                    "scoped": True,
                    "id": "",
                    "challenge_id": "",
                }
            request_id = secrets.token_hex(6)
            request = {
                "id": request_id,
                "action": action,
                "target": target_text,
                "source": str(payload.get("source", "")),
                "content": payload.get("content"),
                "mode": _target_mode(action, target_text),
                "reason": str(payload.get("reason", ""))[:300],
            }
            ok, result = execute(request)
            if ok:
                _audit_scoped(request, result, str(scoped.get("root", "")))
                log(f"scoped token executed: {request_id} {action} {target_text}")
                return 200, {
                    "ok": True,
                    "scoped": True,
                    "id": request_id,
                    "result": result,
                    "status": "allowed",
                }
            return 400, {"ok": False, "error": result, "scoped": True}

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
        for item in manifest:
            if item.get("kind") == "file" and _inside_any(Path(item["path"]), (TOTP_VAULT_ROOT,)):
                return 403, {"ok": False, "error": "TOTP vault files cannot be sent"}
        risk = "totp"

    if action in {"delete", "overwrite", "write_file"} and risk == "allow":
        if approval_only:
            return 200, {
                "ok": True,
                "status": "allowed",
                "approval_only": True,
                "auto_executed": False,
                "id": "",
                "challenge_id": "",
            }
        request_id = secrets.token_hex(6)
        request = {
            "id": request_id,
            "action": action,
            "target": target_text,
            "source": str(payload.get("source", "")),
            "content": payload.get("content"),
            "mode": _target_mode(action, target_text),
            "reason": str(payload.get("reason", ""))[:300],
        }
        ok, result = execute(request)
        _audit_auto(request, ok, result)
        if not ok:
            return 400, {"ok": False, "error": result, "auto_executed": False}
        return 200, {"ok": True, "auto_executed": True, "id": request_id, "result": result}

    channel = _approval_channel()
    if approval_only and channel == "email":
        return 400, {"ok": False, "error": "approval_only requires approval_channel=qq"}
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
            "content": payload.get("content"),
            "mode": _target_mode(action, target_text),
            "target_summary": _path_summary(target_text),
            "source_summary": _path_summary(str(payload.get("source", ""))) if action == "overwrite" else "",
            "channel": "email" if email_mode else "qq",
            "challenge": challenge,
            "approval_only": approval_only,
        }
        if action == "delete":
            prompt = "哥，瑾言想删除以下对象，请输入动态验证码。" + chr(10)
            prompt += f"完整路径与哈希：{_path_summary(target_text)}" + chr(10)
            prompt += "仅本次：<6 位动态码>" + chr(10)
            prompt += "同一目录同动作 30 秒：<6 位动态码> BYPASS 30" + chr(10)
            prompt += "当前草稿目录 30 分钟：<6 位动态码> SCOPED 30" + chr(10)
            prompt += f"请求号：{request_id}"
        elif action == "overwrite":
            source_text = str(payload.get("source", ""))
            prompt = "哥，瑾言想用源文件覆盖目标文件，请输入动态验证码。" + chr(10)
            prompt += f"源：{_path_summary(source_text)}" + chr(10)
            prompt += f"目标：{_path_summary(target_text)}" + chr(10)
            prompt += "仅本次：<6 位动态码>" + chr(10)
            prompt += "同一目录同动作 30 秒：<6 位动态码> BYPASS 30" + chr(10)
            prompt += "当前草稿目录 30 分钟：<6 位动态码> SCOPED 30" + chr(10)
            prompt += f"请求号：{request_id}"
        elif action == "write_file":
            content = payload.get("content")
            size = len(content.encode("utf-8")) if isinstance(content, str) else 0
            prompt = chr(10).join([
                "哥，瑾言想写入核心文件，请输入动态验证码。",
                f"目标：{_path_summary(target_text)}",
                f"写入大小：{size} bytes",
                "仅本次：<6 位动态码>",
                "同一目录同动作 30 秒：<6 位动态码> BYPASS 30",
                "当前草稿目录 30 分钟：<6 位动态码> SCOPED 30",
                f"请求号：{request_id}",
            ])
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
            if approval_only:
                _set_approval_state(request_id, "pending", approval_only=True)
            threading.Thread(target=timeout_watch, args=(request_id,), daemon=True).start()
        log(f"challenge sent: {request_id} {action} {target_text}")

    if approval_only:
        return 200, {
            "ok": True,
            "status": "requires_totp",
            "approval_only": True,
            "id": request_id,
            "challenge_id": request_id,
            "action": action,
        }

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
    try:
        bypass_seconds = int(payload.get("bypass_seconds", 0) or 0)
    except (TypeError, ValueError):
        bypass_seconds = 0
    bypass_seconds = max(0, min(bypass_seconds, BYPASS_TTL_SECONDS))
    try:
        scoped_minutes = int(payload.get("scoped_minutes", 0) or 0)
    except (TypeError, ValueError):
        scoped_minutes = 0
    scoped_minutes = max(0, min(scoped_minutes, SCOPED_MAX_MINUTES))
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
            expired_id = str(_pending.get("id", ""))
            if _pending.get("approval_only"):
                _set_approval_state(expired_id, "expired", approval_only=True)
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
                if _pending.get("approval_only"):
                    _set_approval_state(str(_pending.get("id", "")), "denied", approval_only=True)
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
        if request.get("action") in {"delete", "overwrite", "write_file"}:
            if _path_summary(str(request.get("target", ""))) != request.get("target_summary"):
                return 409, {"ok": False, "error": "target changed before approval"}
            if request.get("action") == "overwrite":
                if _path_summary(str(request.get("source", ""))) != request.get("source_summary"):
                    return 409, {"ok": False, "error": "source changed before approval"}
        if request.get("approval_only"):
            _set_approval_state(request_id, "approved", approval_only=True)
            scoped = None
            if scoped_minutes > 0:
                scoped = _issue_scoped(
                    str(request.get("action", "")),
                    str(request.get("target", "")),
                    scoped_minutes,
                )
            send_qq("已批准 DSH 请求；本次只放行，不执行文件操作。")
            with AUDIT.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps({
                    "at": datetime.now().isoformat(timespec="seconds"),
                    "id": request_id,
                    "action": request.get("action"),
                    "target": request.get("target"),
                    "ok": True,
                    "result": "approval-only approved; DSH may execute",
                    "code_type": code_type,
                    "approval_only": True,
                }, ensure_ascii=False) + "\n")
            log(f"approval-only approved: {request_id} {request.get('action')}")
            response = {
                "ok": True,
                "approved": True,
                "approval_only": True,
                "status": "approved",
                "id": request_id,
                "challenge_id": request_id,
            }
            if scoped:
                response["scoped_token"] = scoped["token"]
                response["scoped_expires_in"] = scoped["expires_in"]
                response["scoped_root"] = scoped["root"]
            return 200, response
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
    bypass = None
    scoped = None
    if ok and scoped_minutes > 0 and request.get("action") in {"delete", "overwrite", "write_file"}:
        scoped = _issue_scoped(
            str(request.get("action", "")),
            str(request.get("target", "")),
            scoped_minutes,
        )
    if ok and bypass_seconds > 0 and request.get("action") in {"delete", "overwrite", "write_file"}:
        bypass = _issue_bypass(
            str(request.get("action", "")),
            str(request.get("target", "")),
            bypass_seconds,
        )
    with AUDIT.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps({
            "at": datetime.now().isoformat(timespec="seconds"),
            "id": request_id,
            "action": request.get("action"),
            "target": request.get("target"),
            "ok": ok,
            "result": result,
            "code_type": code_type,
            "bypass_issued": bool(bypass),
            "bypass_ttl": bypass_seconds if bypass else 0,
            "scoped_issued": bool(scoped),
            "scoped_ttl": scoped["expires_in"] if scoped else 0,
        }, ensure_ascii=False) + "\n")
    log(f"executed: {request_id} ok={ok} {result}")
    response = {"ok": ok, "id": request_id, "result": result}
    if bypass:
        response["bypass_token"] = bypass["token"]
        response["bypass_expires_in"] = bypass["expires_in"]
    if scoped:
        response["scoped_token"] = scoped["token"]
        response["scoped_expires_in"] = scoped["expires_in"]
        response["scoped_root"] = scoped["root"]
    return (200 if ok else 500), response


def run_approval_request(payload: dict) -> tuple[int, dict]:
    """Approval-only adapter for external agents; never executes a file action."""
    body = dict(payload)
    body["approval_only"] = True
    status, response = run_request(body)
    if status == 200:
        if response.get("status") in {"allowed", "requires_totp"}:
            return 200, response
        # Defensive: approval-only must never report an auto execution.
        return 500, {"ok": False, "status": "denied", "error": "invalid approval-only result"}
    if status == 403:
        return 403, {
            "ok": False,
            "status": "denied",
            "error": str(response.get("error", "denied by broker policy")),
        }
    return status, {
        "ok": False,
        "status": "denied",
        "error": str(response.get("error", "approval request failed")),
    }


def get_approval_status(challenge_id: str) -> tuple[int, dict]:
    challenge_id = str(challenge_id or "").strip()
    if not challenge_id:
        return 400, {"ok": False, "error": "id is required"}
    state = _get_approval_state(challenge_id)
    if not state:
        return 404, {"ok": False, "status": "unknown", "error": "challenge not found"}
    return 200, {
        "ok": True,
        "status": state.get("status", "pending"),
        "challenge_id": challenge_id,
        "approval_only": bool(state.get("approval_only", True)),
    }


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
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json(200, {"ok": True, "service": "totp-broker"})
        elif parsed.path == "/api/request_approval/status":
            if not self._auth():
                self._json(401, {"ok": False, "error": "unauthorized"})
                return
            query = parse_qs(parsed.query)
            challenge_id = str((query.get("id") or [""])[0])
            status, body = get_approval_status(challenge_id)
            self._json(status, body)
        elif parsed.path == "/pending":
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
            parsed = urlparse(self.path)
            if parsed.path in {"/request", "/api/request_approval"}:
                with _request_rate_lock:
                    global _last_request_at
                    now = time.monotonic()
                    if now - _last_request_at < REQUEST_RATE_LIMIT_SECONDS:
                        self._json(429, {"ok": False, "error": "request rate limited"})
                        return
                    _last_request_at = now
                if parsed.path == "/api/request_approval":
                    status, body = run_approval_request(payload)
                else:
                    status, body = run_request(payload)
            elif parsed.path == "/verify":
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
    log("broker starting; installing job object")
    initialize_job_object()
    log("broker starting; verifying runtime ACL")
    try:
        verify_runtime_acl()
    except SystemExit as exc:
        log(f"broker startup refused: {exc}")
        raise
    ensure_token()
    QUARANTINE.mkdir(parents=True, exist_ok=True)
    STAGING.mkdir(parents=True, exist_ok=True)
    log(f"broker HTTP listening on {HOST}:{PORT}")
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    try:
        server.serve_forever()
    finally:
        close_job_object()


if __name__ == "__main__":
    main()
