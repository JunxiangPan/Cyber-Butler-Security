#!/usr/bin/env python3
"""SYSTEM TOTP broker exposed only on 127.0.0.1:18090.

YOUR_SERVICE_USER talks to this HTTP service with a local broker token. No files are
used for cross-account TOTP state, which avoids Windows ACL problems.
"""

from __future__ import annotations

import base64
import ctypes
import io
import ctypes.wintypes as wintypes
import hashlib
from dataclasses import dataclass
import ipaddress
import json
import os
import secrets
import shutil
import random
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import pyotp
import qrcode
import requests
import email_approval
import quarantine
import approval_i18n
import approval_preview
import port_guard
import audit_chain
import injection_audit
from win_path_guard import TargetGuardError, TargetSnapshot, create_exclusive

try:
    import win32crypt  # Windows-only; tests inject a verifier.
except ImportError:  # pragma: no cover - exercised on Linux CI
    win32crypt = None

from broker_config import (
    ALLOWED_HOSTS,
    AUDIT,
    BROKER,
    BROKER_CONFIG,
    DENY_JITTER_MAX,
    DENY_JITTER_MIN,
    HOST,
    LEGACY_RECOVERY_FILE,
    LEGACY_SECRET_FILE,
    LOG,
    PORT,
    QUARANTINE,
    RECOVERY_FILE,
    REQUEST_BURST,
    REQUEST_RATE_LIMIT_SECONDS,
    REQUEST_REFILL_SECONDS,
    ROOT,
    SECRET_FILE,
    STAGING,
    TEST_MODE,
    TIMEOUT_SECONDS,
    TOKEN_FILE,
    TOTP_VAULT,
)


def _resolve_shared() -> Path:
    """Resolve the broker workspace from env, config, then the CBS default."""
    if TEST_MODE:
        return Path(os.environ.get("CBS_TEST_SHARED", str(ROOT / "workspace")))
    env_value = str(os.environ.get("CBS_WORKSPACE", "") or "").strip()
    if env_value:
        return Path(env_value)
    try:
        data = json.loads(BROKER_CONFIG.read_text(encoding="utf-8"))
        for key in ("workspace_path", "workspace_root"):
            value = str(data.get(key, "") or "").strip()
            if value:
                return Path(value)
        shared = data.get("shared_roots", [])
        if isinstance(shared, str):
            shared = [shared]
        if isinstance(shared, (list, tuple)):
            for item in shared:
                text = str(item or "").strip()
                if text:
                    return Path(text)
    except Exception as exc:
        print("workspace resolver warning: " + str(exc), file=sys.stderr)
    if "YOUR_" in str(ROOT):
        return Path(r"C:\CyberButler\workspace")
    return ROOT / "workspace"


SHARED = _resolve_shared()
def _resolve_umo() -> str:
    """Resolve the owner UMO from env/config; never hardcode a QQ number."""
    if TEST_MODE:
        return "QQ:FriendMessage:" + os.environ.get("CBS_TEST_QQ_ID", "10000")
    direct = str(os.environ.get("CBS_UMO", "") or "").strip()
    if direct:
        return direct
    try:
        data = json.loads(BROKER_CONFIG.read_text(encoding="utf-8"))
        direct = str(data.get("umo", "") or "").strip()
        if direct:
            return direct
        qq_id = str(data.get("qq_id", "") or data.get("owner_qq", "") or "").strip()
        if qq_id:
            return "QQ:FriendMessage:" + qq_id
    except Exception as exc:
        print("UMO resolver warning: " + str(exc), file=sys.stderr)
    qq_id = str(os.environ.get("CBS_QQ_ID", "") or "").strip()
    return ("QQ:FriendMessage:" + qq_id) if qq_id else ""


UMO = _resolve_umo()
PLATFORM_IDS = ("QQ", "qq", "qq_sujinyan", "default")

# ---------------------------------------------------------------------------
# Windows Job Object: KILL_ON_JOB_CLOSE
# ---------------------------------------------------------------------------
# The broker is started by Task Scheduler as SYSTEM. The job object is created
# before any child process is spawned, and the broker assigns itself to it.
# Every child (and grandchild) that does not explicitly break away inherits the
# job; when the last job handle closes (including a broker crash), Windows
# terminates the whole tree.
#
# This protects processes spawned by the broker. AgentRuntime is started by a
# separate scheduled task, so it is NOT automatically in this job; see the
# caveat in SECURITY.md before claiming that AgentRuntime's children are covered.
JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000
JOB_OBJECT_LIMIT_PROCESS_TIME = 0x00000002
JOB_OBJECT_LIMIT_JOB_TIME = 0x00000004
JOB_OBJECT_LIMIT_ACTIVE_PROCESS = 0x00000008
JOB_OBJECT_LIMIT_PROCESS_MEMORY = 0x00000100
JOB_OBJECT_LIMIT_JOB_MEMORY = 0x00000200
JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
_job_handle = None


@dataclass(frozen=True)
class ExecutionResult:
    """Typed result for one broker file operation."""

    status: int
    message: str
    code: str = ""

    @property
    def ok(self) -> bool:
        return self.status == 200

    def __iter__(self):
        yield self.ok
        yield self.message


def _ok(message: str) -> ExecutionResult:
    return ExecutionResult(200, message, "ok")


def _fail(message: str, status: int = 500, code: str = "broker.execute_failed") -> ExecutionResult:
    return ExecutionResult(status, message, code)


class _JOBOBJECT_BASIC_LIMIT_INFORMATION(ctypes.Structure):
    """_JOBOBJECT_BASIC_LIMIT_INFORMATION helper/type."""
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
    """_IO_COUNTERS helper/type."""
    _fields_ = [
        ("ReadOperationCount", ctypes.c_ulonglong),
        ("WriteOperationCount", ctypes.c_ulonglong),
        ("OtherOperationCount", ctypes.c_ulonglong),
        ("ReadTransferCount", ctypes.c_ulonglong),
        ("WriteTransferCount", ctypes.c_ulonglong),
        ("OtherTransferCount", ctypes.c_ulonglong),
    ]


class _JOBOBJECT_EXTENDED_LIMIT_INFORMATION(ctypes.Structure):
    """_JOBOBJECT_EXTENDED_LIMIT_INFORMATION helper/type."""
    _fields_ = [
        ("BasicLimitInformation", _JOBOBJECT_BASIC_LIMIT_INFORMATION),
        ("IoInfo", _IO_COUNTERS),
        ("ProcessMemoryLimit", ctypes.c_size_t),
        ("JobMemoryLimit", ctypes.c_size_t),
        ("PeakProcessMemoryUsed", ctypes.c_size_t),
        ("PeakJobMemoryUsed", ctypes.c_size_t),
    ]


def _job_limit_environment() -> dict[str, int]:
    """Read bounded resource limits for the Broker Job Object."""
    def _int(name: str, default: int, minimum: int, maximum: int) -> int:
        """Int.
        
        Args:
            name: caller-supplied value.
            default: caller-supplied value.
            minimum: caller-supplied value.
            maximum: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        try:
            value = int(os.environ.get(name, str(default)))
        except (TypeError, ValueError):
            value = default
        return max(minimum, min(value, maximum))

    return {
        # Generous defaults: do not OOM-kill a normal local model during
        # inference. Operators can lower these only after measuring their host.
        "memory_mb": _int("CBS_BROKER_JOB_MEMORY_MB", 32768, 64, 262144),
        "process_memory_mb": _int("CBS_BROKER_PROCESS_MEMORY_MB", 16384, 32, 262144),
        "cpu_seconds": _int("CBS_BROKER_JOB_CPU_SECONDS", 14400, 30, 86400),
        "active_process": _int("CBS_BROKER_ACTIVE_PROCESS", 64, 1, 256),
    }


def _job_limit_flags() -> tuple[int, dict[str, int]]:
    """Job limit flags.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    limits = _job_limit_environment()
    flags = (
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        | JOB_OBJECT_LIMIT_PROCESS_MEMORY
        | JOB_OBJECT_LIMIT_JOB_MEMORY
        | JOB_OBJECT_LIMIT_JOB_TIME
        | JOB_OBJECT_LIMIT_ACTIVE_PROCESS
    )
    return flags, limits


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
    flags, limits = _job_limit_flags()
    info.BasicLimitInformation.LimitFlags = flags
    info.BasicLimitInformation.PerJobUserTimeLimit = limits["cpu_seconds"] * 10_000_000
    info.BasicLimitInformation.ActiveProcessLimit = limits["active_process"]
    info.ProcessMemoryLimit = limits["process_memory_mb"] * 1024 * 1024
    info.JobMemoryLimit = limits["memory_mb"] * 1024 * 1024
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


import broker_state
from broker_state import (
    APPROVAL_STATE_TTL_SECONDS,
    BYPASS_TTL_SECONDS,
    GLOBAL_LOCK_BASE_SECONDS,
    GLOBAL_LOCK_MAX_SECONDS,
    SCOPED_MAX_MINUTES,
    SCOPED_TTL_SECONDS,
    TOTP_MAX_ATTEMPTS,
    TOTP_REPLAY_TTL,
    VERIFY_LOCK_SECONDS,
)


def _retain_snapshots(request_id: str, request: dict) -> None:
    """Keep file handles open across the approval-only execution window."""
    with broker_state._retained_lock:
        broker_state._retained_snapshots[request_id] = request


def _release_retained(request_id: str) -> bool:
    """Release retained snapshots for an approval id."""
    with broker_state._retained_lock:
        old = broker_state._retained_snapshots.pop(request_id, None)
    if old:
        _close_request_snapshots(old)
        return True
    return False

def _allow_request(key: str = "default", now: float | None = None) -> tuple[bool, int]:
    """Token bucket for TOTP requests; returns (allowed, retry_after_seconds)."""
    moment = time.monotonic() if now is None else float(now)
    bucket_key = str(key or "default")
    with broker_state._request_rate_lock:
        for old_key, (_tokens, old_last) in list(broker_state._request_buckets.items()):
            if moment - float(old_last) > 3600:
                broker_state._request_buckets.pop(old_key, None)
        tokens, last = broker_state._request_buckets.get(bucket_key, (float(REQUEST_BURST), moment))
        tokens = min(float(REQUEST_BURST), tokens + (moment - last) / REQUEST_REFILL_SECONDS)
        if tokens < 1.0:
            retry = max(1, int((1.0 - tokens) * REQUEST_REFILL_SECONDS) + 1)
            broker_state._request_buckets[bucket_key] = (tokens, moment)
            return False, retry
        broker_state._request_buckets[bucket_key] = (tokens - 1.0, moment)
        broker_state._last_request_at = moment
        return True, 0


def _deny_jitter() -> None:
    """Blunt timing oracles for zero-information rejections."""
    if os.environ.get("CBS_DISABLE_JITTER") == "1":
        return
    time.sleep(random.uniform(DENY_JITTER_MIN, DENY_JITTER_MAX))


WEBUI_CONTACT = ROOT / "webui" / "data" / "approval-contact.json"

def _admin_email() -> str:
    """Admin email.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    for path in (BROKER_CONFIG, WEBUI_CONTACT):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        value = str(data.get("admin_email", "") or "").strip()
        if value and value.lower() not in {"owner@example.com", "your_email@example.com"} and "YOUR_" not in value:
            return value
    return ""


def _approval_channel() -> str:
    """Return qq or email; fail safe to qq when the config is missing/invalid."""
    try:
        data = json.loads(BROKER_CONFIG.read_text(encoding="utf-8"))
        channel = str(data.get("approval_channel", "webui")).strip().lower()
        return channel if channel in {"qq", "email", "webui"} else "webui"
    except (OSError, ValueError):
        return "webui"


_send_events: dict[str, threading.Event] = {}
_send_results: dict[str, bool] = {}


def log(message: str) -> None:
    """Log.
    
    Args:
        message: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    line = f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {message}"
    print(line, flush=True)
    try:
        with LOG.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")
    except OSError as exc:
        print(f"broker log write failed: {exc}", flush=True)


def _start_audit_chain_mirror() -> None:
    """Mirror newly appended legacy audit lines into the chained sidecar."""
    import threading

    def run() -> None:
        """Run.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        try:
            offset = AUDIT.stat().st_size if AUDIT.exists() else 0
        except OSError:
            offset = 0
        chain_path = AUDIT.with_name(AUDIT.name + ".chain.jsonl")
        while True:
            time.sleep(0.5)
            try:
                if not AUDIT.exists():
                    continue
                size = AUDIT.stat().st_size
                if size < offset:
                    offset = 0
                if size == offset:
                    continue
                with AUDIT.open("rb") as handle:
                    handle.seek(offset)
                    for raw in handle:
                        try:
                            record = json.loads(raw.decode("utf-8"))
                        except ValueError:
                            log("audit chain mirror skipped a malformed legacy line")
                            continue
                        if isinstance(record, dict):
                            audit_chain.append_event(chain_path, record)
                    offset = handle.tell()
            except Exception as exc:
                log(f"audit chain mirror failed: {exc}")
                os._exit(70)

    threading.Thread(target=run, name="audit-chain", daemon=True).start()


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
        raise RuntimeError(f"audit write failed; fail-closed: {exc}") from exc


def _audit_manifest_reject(request_id: str, request: dict, result: str) -> None:
    """Audit manifest reject.
    
    Args:
        request_id: caller-supplied value.
        request: caller-supplied value.
        result: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
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
        raise RuntimeError(f"audit write failed; fail-closed: {exc}") from exc


def ensure_token() -> str:
    """Ensure token.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if not TOKEN_FILE.exists():
        token = secrets.token_urlsafe(32)
        TOKEN_FILE.write_text(token, encoding="utf-8")
        if TEST_MODE:
            return token
        service_user = os.environ.get("CBS_SERVICE_USER", "YOUR_SERVICE_USER").strip() or "YOUR_SERVICE_USER"
        acl = subprocess.run(
            ["icacls", str(TOKEN_FILE), "/inheritance:r", "/grant:r",
             "SYSTEM:(F)", service_user + ":(R)", "*S-1-5-32-544:(F)"],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if acl.returncode != 0:
            raise RuntimeError("broker token ACL failed: " + str(acl.stdout or acl.stderr).strip())
        readback = subprocess.run(
            ["icacls", str(TOKEN_FILE)],
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        if readback.returncode != 0 or "SYSTEM:" not in (readback.stdout or ""):
            raise RuntimeError("broker token ACL readback failed")
    return TOKEN_FILE.read_text(encoding="utf-8").strip()


def _secret_file() -> Path:
    """Secret file.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if SECRET_FILE.is_file():
        return SECRET_FILE
    if LEGACY_SECRET_FILE.is_file():
        return LEGACY_SECRET_FILE
    return SECRET_FILE


def _recovery_file() -> Path:
    """Recovery file.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if RECOVERY_FILE.is_file():
        return RECOVERY_FILE
    if LEGACY_RECOVERY_FILE.is_file():
        return LEGACY_RECOVERY_FILE
    return RECOVERY_FILE


def secret() -> str:
    """Secret.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if TEST_MODE:
        test_secret = os.environ.get("CBS_TEST_TOTP_SECRET", "").strip()
        if test_secret:
            return test_secret
    if win32crypt is None:
        raise RuntimeError("win32crypt is required to read the DPAPI secret")
    encrypted = _secret_file().read_bytes()
    plain = win32crypt.CryptUnprotectData(encrypted, None, None, None, 0)
    return plain[1].decode("utf-8")


def send_qq(text: str) -> bool:
    """Send qq.
    
    Args:
        text: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        token = (ROOT / ".agentruntime_token").read_text(encoding="utf-8").strip()
        owner = UMO.rsplit(":", 1)[-1]
        # AgentRuntime installations differ in the platform id (QQ, qq, or the
        # legacy qq_sujinyan). Try the configured spelling first, then fall
        # back without changing the owner or the message.
        for platform_id in PLATFORM_IDS:
            umo = f"{platform_id}:FriendMessage:{owner}"
            response = requests.post(
                "http://127.0.0.1:6185/api/v1/im/messages",
                headers={"Authorization": f"Bearer {token}"},
                json={"umo": umo, "message": text},
                timeout=60,
            )
            if response.ok:
                return True
        return False
    except Exception as exc:
        log(f"QQ send failed: {exc}")
        return False


def _notify_async(text: str) -> None:
    """Send notification on a daemon thread; never hold broker_state._lock for network IO."""
    threading.Thread(target=send_qq, args=(str(text or ""),), daemon=True).start()


def inside_shared(path: Path) -> bool:
    """Inside shared.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if _inside_any(path, _workspace_roots()):
        return True
    try:
        path.resolve().relative_to(SHARED.resolve())
        return True
    except ValueError:
        return False


WORKSPACE_ROOT = ROOT / "workspace"
DEFAULT_WORKSPACE_ROOT = Path(r"C:\CyberButler\workspace")


def _workspace_roots() -> tuple[Path, ...]:
    """Return configured workspace roots, defaulting safely on bad config."""
    roots = [WORKSPACE_ROOT, DEFAULT_WORKSPACE_ROOT]
    try:
        data = json.loads(BROKER_CONFIG.read_text(encoding="utf-8"))
        for key in ("workspace_root", "workspace_path"):
            value = str(data.get(key, "") or "").strip()
            if value:
                roots.append(Path(value))
        shared = data.get("shared_roots", [])
        if isinstance(shared, str):
            shared = [shared]
        if isinstance(shared, (list, tuple)):
            for item in shared:
                text = str(item or "").strip()
                if text:
                    roots.append(Path(text))
    except Exception as exc:  # noqa: BLE001 - config must never crash the Broker
        try:
            log("broker_config workspace warning: " + str(exc))
        except Exception as log_exc:
            print("broker_config log warning failed: " + str(log_exc), file=sys.stderr)
    return tuple(roots)

TMP_ROOTS = (
    ROOT / "workspace" / "tmp",
    ROOT / "AgentRuntime" / "data" / "tmp",
    ROOT / "AgentRuntime" / "data" / "temp",
    ROOT / "AgentRuntime" / "data" / "cache",
    ROOT / "AgentRuntime" / "data" / "logs",
)
MEMORY_ROOTS = (
    ROOT / "AgentRuntime" / "data" / "memory",
    ROOT / "AgentRuntime" / "data" / "config",
    ROOT / "AgentRuntime" / "data" / "cmd_config.json",
)
TOTP_VAULT_ROOT = ROOT / "tools" / "totp-vault"
CRITICAL_INTEGRITY_NAMES = {
    "conftest.py", "pytest.ini", "makefile", "package.json", "pyproject.toml",
    ".claude/settings.json",
}
PROTECTED_RULE_NAMES = {
    "network-policy.json", "broker_config.json", "physical-separation.json",
    "wfp-guard-status.json", "totp_broker_audit.jsonl", "totp_broker_audit.chain.jsonl",
    "totp_secret.dpapi", "recovery_hashes.json",
}


def _inside_any(path: Path, roots: tuple[Path, ...]) -> bool:
    """Inside any.
    
    Args:
        path: caller-supplied value.
        roots: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
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


def _workspace_text(target: str) -> bool:
    """Case/alias tolerant check for the dedicated workspace path."""
    try:
        def normalise(value: object) -> str:
            """Normalize a path string for case/separator-insensitive comparison."""
            return os.path.normcase(os.path.normpath(str(value).replace("\\", "/"))).rstrip("/")
        candidate = normalise(target)
        for root in _workspace_roots():
            normalized = normalise(root)
            if candidate == normalized or candidate.startswith(normalized + "/"):
                return True
    except (OSError, ValueError):
        return False
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
    if _inside_any(path, _workspace_roots()) or _workspace_text(target):
        return "totp"
    if _inside_any(path, MEMORY_ROOTS):
        return "totp"
    if inside_shared(path):
        # Creating a brand-new file in the shared workspace is a routine
        # operation. Replacing an existing file remains destructive.
        if action == "write_file" and not path.exists():
            return "allow"
        return "totp"
    return "deny"


def _critical_integrity_hit(target: str) -> bool:
    """Critical integrity hit.
    
    Args:
        target: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        path = Path(str(target or "")).resolve(strict=False)
        root = ROOT.resolve(strict=False)
        path.relative_to(root)
    except (OSError, ValueError):
        return False
    lowered_parts = [part.casefold() for part in path.parts]
    name = path.name.casefold()
    if name in CRITICAL_INTEGRITY_NAMES:
        return True
    if ".claude" in lowered_parts and name == "settings.json":
        return True
    if ".github" in lowered_parts:
        index = lowered_parts.index(".github")
        if index + 1 < len(lowered_parts) and lowered_parts[index + 1] == "workflows":
            return True
    return False


def _rule_tampering_hit(target: str) -> bool:
    """Rule tampering hit.
    
    Args:
        target: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        path = Path(str(target or "")).resolve(strict=False)
        root = ROOT.resolve(strict=False)
        path.relative_to(root)
    except (OSError, ValueError):
        return False
    name = path.name.casefold()
    parts = [part.casefold() for part in path.relative_to(ROOT).parts]
    if name in PROTECTED_RULE_NAMES or name.endswith(".chain.jsonl"):
        return True
    if parts and parts[0] in {"tools", "webui", ".github", "installer", "tests"}:
        return True
    return "quarantine" in parts


def _audit_protection(event: str, action: str, target: str, reason: str) -> None:
    """Audit protection.
    
    Args:
        event: caller-supplied value.
        action: caller-supplied value.
        target: caller-supplied value.
        reason: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        AUDIT.parent.mkdir(parents=True, exist_ok=True)
        with AUDIT.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({
                "at": datetime.now().isoformat(timespec="seconds"),
                "event": event,
                "action": action,
                "target": target,
                "reason": str(reason or "")[:300],
                "ok": False,
            }, ensure_ascii=False) + "\n")
    except OSError as exc:
        raise RuntimeError(f"{event} audit write failed; fail-closed: {exc}") from exc


def _allowed_target(path: Path) -> bool:
    """Allowed target.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return inside_shared(path) or _inside_any(path, TMP_ROOTS) or _inside_any(path, MEMORY_ROOTS)


def _target_mode(action: str, target: str) -> str:
    """Target mode.
    
    Args:
        action: caller-supplied value.
        target: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if action == "write_file":
        try:
            return "create" if not Path(target).resolve(strict=False).exists() else "replace"
        except (OSError, ValueError):
            return "replace"
    if action == "overwrite":
        return "replace"
    return action


def _bypass_scope(action: str, target: str) -> str:
    """Bypass scope.
    
    Args:
        action: caller-supplied value.
        target: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    path = Path(target).resolve(strict=False)
    return f"{action}:{_target_mode(action, target)}:{str(path.parent.resolve(strict=False)).casefold()}"


def _purge_bypass(now: float | None = None) -> None:
    """Purge bypass.
    
    Args:
        now: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    moment = time.monotonic() if now is None else now
    for token, record in list(broker_state._bypass_tokens.items()):
        if float(record.get("expires", 0)) <= moment:
            broker_state._bypass_tokens.pop(token, None)


def _issue_bypass(action: str, target: str, ttl_seconds: int = BYPASS_TTL_SECONDS) -> dict | None:
    """Issue bypass.
    
    Args:
        action: caller-supplied value.
        target: caller-supplied value.
        ttl_seconds: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if action not in {"delete", "overwrite", "write_file"}:
        return None
    ttl = max(1, min(int(ttl_seconds), BYPASS_TTL_SECONDS))
    scope = _bypass_scope(action, target)
    token = secrets.token_urlsafe(32)
    now = time.monotonic()
    with broker_state._bypass_lock:
        _purge_bypass(now)
        broker_state._bypass_tokens[token] = {
            "scope": scope,
            "action": action,
            "expires": now + ttl,
            "uses": 0,
        }
    return {"token": token, "expires_in": ttl, "scope": scope}


def _consume_bypass(token: str, action: str, target: str) -> dict | None:
    """Consume bypass.
    
    Args:
        token: caller-supplied value.
        action: caller-supplied value.
        target: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if not token:
        return None
    scope = _bypass_scope(action, target)
    now = time.monotonic()
    with broker_state._bypass_lock:
        _purge_bypass(now)
        record = broker_state._bypass_tokens.get(token)
        if not record:
            return None
        if record.get("scope") != scope or record.get("action") != action:
            return None
        record["uses"] = int(record.get("uses", 0)) + 1
        return dict(record)


def _close_request_snapshots(request: dict | None) -> None:
    """Close request snapshots.
    
    Args:
        request: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if not isinstance(request, dict):
        return
    for key in ("_snapshot", "_source_snapshot"):
        snap = request.get(key)
        if snap is not None:
            try:
                snap.close()
            except Exception as exc:
                log("snapshot close warning: " + str(exc))


def _prepare_snapshots(action: str, target: str, source: str = "") -> tuple:
    """Prepare snapshots.
    
    Args:
        action: caller-supplied value.
        target: caller-supplied value.
        source: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if action not in {"delete", "overwrite", "write_file"}:
        return None, None
    target_path = Path(target)
    target_snapshot = None
    source_snapshot = None
    if action == "write_file" and not target_path.exists():
        return None, None
    target_snapshot = TargetSnapshot.open(
        target,
        write=action in {"write_file", "overwrite"},
        delete=action == "delete",
    )
    if action == "overwrite":
        source_snapshot = TargetSnapshot.open(source, write=False)
    return target_snapshot, source_snapshot


def _assert_snapshots_current(request: dict) -> None:
    """Assert snapshots current.
    
    Args:
        request: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    for key in ("_snapshot", "_source_snapshot"):
        snap = request.get(key)
        if snap is not None:
            snap.assert_unchanged()


def _sha256_file(path: Path) -> str:
    """Sha256 file.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _url_host_allowed(url: str) -> bool:
    """SSRF gate: URL entries must target an explicitly allowed host."""
    try:
        from urllib.parse import urlparse
        host = (urlparse(url).hostname or "").casefold()
    except ValueError:
        return False
    if not host:
        return False
    allowed = os.environ.get("CBS_URL_ALLOWED_HOSTS", "")
    hosts = {item.strip().casefold() for item in allowed.split(",") if item.strip()}
    return host in hosts


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
            if not _url_host_allowed(raw_path):
                raise ValueError("manifest URL host is not allowlisted")
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
    """Manifest equal.
    
    Args:
        left: caller-supplied value.
        right: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return json.dumps(left, sort_keys=True, ensure_ascii=False) == json.dumps(
        right, sort_keys=True, ensure_ascii=False
    )


def _fail_send_wait(request_id: str) -> None:
    """Fail send wait.
    
    Args:
        request_id: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    event = _send_events.get(request_id)
    if event:
        _send_results[request_id] = False
        event.set()


def _snapshot_summary(snapshot, path_text: str) -> str:
    """Summarize the already-open target without reopening it.

    The target snapshot holds DELETE access for the later rename. A second
    path-based open can be denied by Windows sharing rules even though the
    Broker owns the first handle, so never reopen the target here.
    """
    try:
        if snapshot is not None and not getattr(snapshot, "is_directory", False):
            return (
                f"{snapshot.path} | file | {int(snapshot.identity[2])} bytes "
                f"| sha256={snapshot.sha256}"
            )
    except Exception as exc:
        log("snapshot summary warning: " + str(exc))
    return _path_summary(path_text)


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
    """Manifest prompt.
    
    Args:
        manifest: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    lines = [approval_i18n.t("manifest", count=len(manifest))]
    for index, item in enumerate(manifest, 1):
        if item["kind"] == "url":
            lines.append(f"{index}. {approval_i18n.t('url')}: {item['path']} [OUTSIDE SHARED]")
        else:
            path = Path(item["path"])
            marker = "" if inside_shared(path) else " [OUTSIDE SHARED]"
            lines.append(
                f"{index}. {item['path']} | {item['size']} bytes | "
                f"sha256={item['sha256']}{marker}"
            )
    return "\n".join(lines)


def verify_code(code: str, request_id: str = "") -> str:
    """Verify code.
    
    Args:
        code: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    code = code.strip().upper()
    if len(code) == 6 and code.isdigit():
        if pyotp.TOTP(secret()).verify(code, valid_window=1):
            digest = hashlib.sha256((str(request_id) + "|" + code).encode("utf-8")).hexdigest()
            now = time.time()
            with broker_state._replay_lock:
                for old_digest, used_at in list(broker_state._used_totp.items()):
                    if now - used_at > TOTP_REPLAY_TTL:
                        broker_state._used_totp.pop(old_digest, None)
                if digest in broker_state._used_totp:
                    return "replay"
                broker_state._used_totp[digest] = now
            return "totp"
        return ""
    if len(code) == 8 and code.isalnum():
        try:
            recovery_path = _recovery_file()
            store = json.loads(recovery_path.read_text(encoding="utf-8"))
            digest = hashlib.sha256(code.encode("utf-8")).hexdigest()
            if digest in store.get("used", []):
                return "replay"
            if digest in store.get("sha256", []) and digest not in store.get("used", []):
                store.setdefault("used", []).append(digest)
                recovery_path.write_text(
                    json.dumps(store, ensure_ascii=False, indent=2), encoding="utf-8"
                )
                return "recovery"
        except (OSError, ValueError):
            return ""
    return ""


def execute(request: dict) -> ExecutionResult:
    """Execute.
    
    Args:
        request: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    action = request.get("action")
    target = Path(request.get("target", ""))
    snapshot = request.get("_snapshot")
    source_snapshot = request.get("_source_snapshot")
    try:
        if snapshot is not None:
            snapshot.assert_unchanged()
        if source_snapshot is not None:
            source_snapshot.assert_unchanged()

        if not target or not _allowed_target(target):
            return _fail("目标不在允许的 Broker 路径内，拒绝执行。", 403, "policy.target_denied")

        if action == "delete":
            if snapshot is not None and not snapshot.is_directory:
                quarantine.TRASH_STAGING = QUARANTINE
                try:
                    entry = quarantine.quarantine_file(
                        snapshot,
                        str(request.get("id", "request")),
                        original_path=str(target),
                        action="delete",
                        reason=str(request.get("reason", "")),
                    )
                except quarantine.QuarantineCapacityError as exc:
                    return _fail("暂存区容量熔断，删除已拦截；没有移动任何文件。" + str(exc), 507, "trash.capacity_exceeded")
                request["_trash_entry"] = str(entry)
                try:
                    manifest = quarantine._read_manifest(entry)
                    request["_trash_expires_at"] = manifest.get("expires_at", "")
                    request["_trash_expires_epoch"] = manifest.get("expires_epoch", 0)
                except Exception as exc:
                    log("trash manifest warning: " + str(exc))
                return _ok(f"文件已移入两阶段暂存回收站，10 分钟内可撤回：{entry.name}")
            if not target.exists():
                return _fail("目标文件不存在。", 404, "target.not_found")
            QUARANTINE.mkdir(parents=True, exist_ok=True)
            trash = QUARANTINE / f"{request['id']}_{target.name}"
            shutil.move(str(target), str(trash))
            return _ok(f"已把 {target.name} 移到隔离区：{trash.name}")

        if action == "overwrite":
            source = Path(request.get("source", ""))
            source_ok = inside_shared(source) or _inside_any(source, TMP_ROOTS)
            try:
                source.resolve().relative_to(STAGING.resolve())
                source_ok = True
            except ValueError as exc:
                log("source staging prefix warning: " + str(exc))
            if not source_ok:
                return _fail("覆盖源文件必须在shared专用文件夹、tmp 或 broker staging 内。", 403, "policy.source_denied")
            if source_snapshot is not None:
                if snapshot is None:
                    return _fail("覆盖目标快照缺失。", 409, "target.snapshot_missing")
                data = source_snapshot.read_bytes(limit=50 * 1024 * 1024)
                snapshot.rewrite(data)
                return _ok(f"已覆盖 {target.name}（句柄绑定，旧版本未直接删除）。")
            if not source.exists():
                return _fail("覆盖源文件不存在。", 409, "source.not_found")
            if target.exists():
                QUARANTINE.mkdir(parents=True, exist_ok=True)
                backup = QUARANTINE / f"{request['id']}_{target.name}.bak"
                shutil.copy2(target, backup)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
            return _ok(f"已覆盖 {target.name}，旧版本备份在隔离区。")

        if action == "write_file":
            content = request.get("content")
            if not isinstance(content, str):
                return _fail("write_file 需要字符串 content。", 400, "request.invalid_content")
            data = content.encode("utf-8")
            if len(data) > 256 * 1024:
                return _fail("write_file 内容超过 256KB。", 413, "request.content_too_large")
            target.parent.mkdir(parents=True, exist_ok=True)
            if request.get("mode") == "create" and snapshot is None:
                create_exclusive(str(target), data)
                return _ok(f"已创建 {target.name}（{len(data)} bytes）。")
            if snapshot is not None:
                if request.get("mode") == "create":
                    return _fail("创建模式发现目标已存在；拒绝覆盖。", 409, "target.exists")
                snapshot.rewrite(data)
                return _ok(f"已写入 {target.name}（{len(data)} bytes，句柄绑定）。")
            if request.get("mode") == "create":
                try:
                    with target.open("x", encoding="utf-8") as handle:
                        handle.write(content)
                except FileExistsError:
                    return _fail("创建模式发现目标已存在；拒绝覆盖。", 409, "target.exists")
                return _ok(f"已创建 {target.name}（{len(data)} bytes）。")
            temp = target.with_name(target.name + ".broker.tmp")
            temp.write_text(content, encoding="utf-8")
            os.replace(temp, target)
            return _ok(f"已写入 {target.name}（{len(data)} bytes）。")
        return _fail("不支持的操作类型。", 400, "request.unsupported_action")
    except TargetGuardError as exc:
        return _fail(f"目标在审批后发生变化（TOCTOU）：{exc}", 409, "target.toctou")
    finally:
        _close_request_snapshots(request)

def timeout_watch(request_id: str) -> None:
    """Timeout watch.
    
    Args:
        request_id: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    time.sleep(TIMEOUT_SECONDS)
    expired = False
    approval_only = False
    with broker_state._lock:
        if broker_state._pending and broker_state._pending.get("id") == request_id:
            approval_only = bool(broker_state._pending.get("approval_only"))
            _close_request_snapshots(broker_state._pending)
            broker_state._pending = None
            expired = True
    if expired:
        if approval_only:
            _set_approval_state(request_id, "expired", approval_only=True)
        send_qq(approval_i18n.t("timeout"))
        log(f"timeout: {request_id}")


def _is_verification_locked() -> bool:
    """Is verification locked.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return time.monotonic() < max(broker_state._verify_locked_until, broker_state._global_lock_until)


def _record_global_failure() -> float:
    """Record a failure even if the pending request is later cleared/expired."""
    broker_state._global_failures += 1
    if broker_state._global_failures < TOTP_MAX_ATTEMPTS:
        return 0.0
    exponent = max(0, broker_state._global_failures - TOTP_MAX_ATTEMPTS)
    delay = min(GLOBAL_LOCK_BASE_SECONDS * (2 ** exponent), GLOBAL_LOCK_MAX_SECONDS)
    broker_state._global_lock_until = max(broker_state._global_lock_until, time.monotonic() + delay)
    return delay


def email_watch(request_id: str) -> None:
    """Poll IMAP for the owner's APPROVE reply and execute exactly one Pending."""
    try:
        config = email_approval.load_config()
    except Exception as exc:
        log(f"email config failed: {exc}")
        with broker_state._lock:
            if broker_state._pending and broker_state._pending.get("id") == request_id:
                _close_request_snapshots(broker_state._pending)
                broker_state._pending = None
        return

    while True:
        with broker_state._lock:
            if not broker_state._pending or broker_state._pending.get("id") != request_id or broker_state._pending.get("channel") != "email":
                return
            request = dict(broker_state._pending)
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
        with broker_state._lock:
            if not broker_state._pending or broker_state._pending.get("id") != request_id:
                return
            actual_challenge = str(broker_state._pending.get("challenge", ""))
            request = dict(broker_state._pending)
        if challenge != actual_challenge:
            log("email approval ignored: challenge mismatch")
            continue
        if not verify_code(totp, request_id):
            with broker_state._lock:
                if broker_state._pending and broker_state._pending.get("id") == request_id:
                    broker_state._pending["attempts"] = int(broker_state._pending.get("attempts", 0)) + 1
                    if broker_state._pending["attempts"] >= TOTP_MAX_ATTEMPTS:
                        _close_request_snapshots(broker_state._pending)
                        broker_state._pending = None
                        log("email approval locked after too many failures")
                        return
            log("email approval ignored: invalid TOTP")
            continue
        try:
            _assert_snapshots_current(request)
        except TargetGuardError as exc:
            with broker_state._lock:
                _close_request_snapshots(broker_state._pending)
                broker_state._pending = None
            _email_result(config, request, f"target changed before approval: {exc}")
            return
        if request.get("_snapshot") is None and _path_summary(str(request.get("target", ""))) != request.get("target_summary"):
            with broker_state._lock:
                _close_request_snapshots(broker_state._pending)
                broker_state._pending = None
            _email_result(config, request, "target changed before approval")
            return
        if request.get("action") == "overwrite" and request.get("_source_snapshot") is None:
            if _path_summary(str(request.get("source", ""))) != request.get("source_summary"):
                with broker_state._lock:
                    _close_request_snapshots(broker_state._pending)
                    broker_state._pending = None
                _email_result(config, request, "source changed before approval")
                return
        with broker_state._lock:
            broker_state._pending = None
        ok, result = execute(request)
        log(f"email approved: {request_id} ok={ok} {result}")
        _email_result(config, request, result)
        return

    with broker_state._lock:
        if broker_state._pending and broker_state._pending.get("id") == request_id:
            _close_request_snapshots(broker_state._pending)
            broker_state._pending = None
    try:
        email_approval.send_email(
            config,
            f"[Cyber-Butler] 审批超时 #{request.get('challenge', '')}",
            "5 分钟内没有收到有效回复，本次操作已拒绝。",
        )
    except Exception as exc:
        log(f"email timeout notice failed: {exc}")


def _email_result(config: dict, request: dict, result: str) -> None:
    """Email result.
    
    Args:
        config: caller-supplied value.
        request: caller-supplied value.
        result: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    try:
        email_approval.send_email(
            config,
            f"[Cyber-Butler] 审批结果 #{request.get('challenge', '')}",
            f"动作：{request.get('action')}\n目标：{request.get('target')}\n结果：{result}",
        )
    except Exception as exc:
        log(f"email result send failed: {exc}")


def _audit_auto(request: dict, ok: bool, result: str) -> None:
    """Audit auto.
    
    Args:
        request: caller-supplied value.
        ok: caller-supplied value.
        result: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
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
    """Issue scoped.
    
    Args:
        action: caller-supplied value.
        target: caller-supplied value.
        minutes: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if action not in {"delete", "overwrite", "write_file"}:
        return None
    root = _scoped_root(target)
    if root is None:
        return None
    ttl = max(1, min(int(minutes), SCOPED_MAX_MINUTES)) * 60
    token = secrets.token_urlsafe(32)
    now = time.monotonic()
    with broker_state._scoped_lock:
        broker_state._scoped_tokens[token] = {
            "root": str(root).casefold(),
            "expires": now + ttl,
            "uses": 0,
            "actions": ("delete", "overwrite", "write_file"),
        }
        for key, record in list(broker_state._scoped_tokens.items()):
            if float(record.get("expires", 0)) <= now:
                broker_state._scoped_tokens.pop(key, None)
    return {"token": token, "expires_in": ttl, "root": str(root)}


def _consume_scoped(token: str, action: str, target: str) -> dict | None:
    """Consume scoped.
    
    Args:
        token: caller-supplied value.
        action: caller-supplied value.
        target: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if not token or action not in {"delete", "overwrite", "write_file"}:
        return None
    try:
        path = Path(str(target or "")).resolve(strict=False)
    except (OSError, ValueError):
        return None
    if _inside_any(path, (TOTP_VAULT_ROOT,)):
        return None
    now = time.monotonic()
    with broker_state._scoped_lock:
        record = broker_state._scoped_tokens.get(token)
        if not record or float(record.get("expires", 0)) <= now:
            broker_state._scoped_tokens.pop(token, None)
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
    """Audit scoped.
    
    Args:
        request: caller-supplied value.
        result: caller-supplied value.
        root: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
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
    """As bool.
    
    Args:
        value: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if isinstance(value, bool):
        return value
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def _set_approval_state(
    challenge_id: str,
    status: str,
    approval_only: bool = True,
    scoped: dict | None = None,
) -> None:
    """Set approval state.
    
    Args:
        challenge_id: caller-supplied value.
        status: caller-supplied value.
        approval_only: caller-supplied value.
        scoped: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    now = time.monotonic()
    scoped_ttl = int(scoped.get("expires_in", 0)) if scoped else 0
    with broker_state._approval_lock:
        current = broker_state._approval_states.get(challenge_id, {})
        broker_state._approval_states[challenge_id] = {
            "id": challenge_id,
            "status": status,
            "approval_only": bool(approval_only),
            "created": float(current.get("created", now)),
            "updated": now,
            "expires": now + max(APPROVAL_STATE_TTL_SECONDS, scoped_ttl),
            "scoped_token": str(scoped["token"]) if scoped else "",
            "scoped_expires_in": scoped_ttl,
            "scoped_root": str(scoped.get("root", "")) if scoped else "",
        }
        for key, record in list(broker_state._approval_states.items()):
            if float(record.get("expires", 0)) <= now:
                broker_state._approval_states.pop(key, None)


def _get_approval_state(challenge_id: str) -> dict | None:
    """Get approval state.
    
    Args:
        challenge_id: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    now = time.monotonic()
    with broker_state._approval_lock:
        record = broker_state._approval_states.get(challenge_id)
        if not record:
            return None
        if float(record.get("expires", 0)) <= now:
            record["status"] = "expired"
            record["updated"] = now
        return dict(record)


def _audit_bypass(request: dict, result: str, scope: str) -> None:
    """Audit bypass.
    
    Args:
        request: caller-supplied value.
        result: caller-supplied value.
        scope: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
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


def _is_uninstalling() -> bool:
    """Is uninstalling.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if os.environ.get("CBS_IS_UNINSTALLING") == "1":
        return True
    candidate = Path(os.environ.get("ProgramData", r"C:\ProgramData")) / "CyberButler" / "uninstalling.marker"
    return candidate.exists()


def run_request(payload: dict) -> tuple[int, dict]:
    """Run request.
    
    Args:
        payload: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if _is_uninstalling():
        return 503, {"ok": False, "status": "uninstalling", "error": "broker is uninstalling"}
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
    if action == "delete" and target.is_dir():
        return 400, {"ok": False, "error": "directory deletion is not supported; delete files individually"}
    if action in {"delete", "overwrite", "write_file"}:
        if _critical_integrity_hit(target_text):
            _audit_protection("TEST_TAMPERING_ATTEMPT", action, target_text, str(payload.get("reason", "")))
            return 403, {"ok": False, "error": "critical integrity file is hard-denied"}
        if _rule_tampering_hit(target_text):
            _audit_protection("RULE_TAMPERING_ATTEMPT", action, target_text, str(payload.get("reason", "")))
            return 403, {"ok": False, "error": "CBS rule/config file is hard-denied"}
    manifest: list[dict] | None = None
    if action not in {"delete", "overwrite", "write_file", "send"}:
        return 400, {"ok": False, "error": "action must be delete, overwrite, write_file or send"}
    risk = classify(action, target_text)
    if risk == "deny":
        _deny_jitter()
        return 403, {"ok": False, "error": "target is not allowed by broker policy"}

    try:
        target_snapshot, source_snapshot = _prepare_snapshots(
            action, target_text, str(payload.get("source", ""))
        )
    except (OSError, ValueError, TargetGuardError) as exc:
        _deny_jitter()
        return 409, {"ok": False, "error": f"target cannot be bound: {exc}"}

    bypass_token = str(payload.get("bypass_token", "") or "")
    if action in {"delete", "overwrite", "write_file"} and risk == "totp" and bypass_token:
        bypass = _consume_bypass(bypass_token, action, target_text)
        if bypass:
            if approval_only:
                _close_request_snapshots({"_snapshot": target_snapshot, "_source_snapshot": source_snapshot})
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
                "_snapshot": target_snapshot,
                "_source_snapshot": source_snapshot,
            }
            ok, result = execute(request)
            if ok:
                _audit_bypass(request, result, str(bypass.get("scope", "")))
                log(f"bypass executed: {request_id} {action} {target_text}")
                return 200, {"ok": True, "bypassed": True, "id": request_id, "result": result}
            return 400, {"ok": False, "error": result, "bypassed": True}

    scoped_token = str(payload.get("scoped_token", "") or "")
    scoped_invalid = False
    if action in {"delete", "overwrite", "write_file"} and risk == "totp" and scoped_token:
        scoped = _consume_scoped(scoped_token, action, target_text)
        if scoped:
            if approval_only:
                _close_request_snapshots({"_snapshot": target_snapshot, "_source_snapshot": source_snapshot})
                audit_request = {
                    "id": "",
                    "action": action,
                    "target": target_text,
                }
                _audit_scoped(
                    audit_request,
                    "approval-only scoped; DSH may execute",
                    str(scoped.get("root", "")),
                )
                log(f"scoped approval-only allowed: {action} {target_text}")
                return 200, {
                    "ok": True,
                    "status": "allowed",
                    "approval_only": True,
                    "auto_executed": False,
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
                "_snapshot": target_snapshot,
                "_source_snapshot": source_snapshot,
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
        scoped_invalid = True

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
            _close_request_snapshots({"_snapshot": target_snapshot, "_source_snapshot": source_snapshot})
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
            "_snapshot": target_snapshot,
            "_source_snapshot": source_snapshot,
        }
        ok, result = execute(request)
        _audit_auto(request, ok, result)
        if not ok:
            return 400, {"ok": False, "error": result, "auto_executed": False}
        return 200, {"ok": True, "auto_executed": True, "id": request_id, "result": result}

    channel = _approval_channel()
    if approval_only and channel == "email":
        _close_request_snapshots({"_snapshot": target_snapshot, "_source_snapshot": source_snapshot})
        return 400, {"ok": False, "error": "approval_only requires approval_channel=qq"}
    email_mode = channel == "email" and action in {"delete", "overwrite"}
    if channel == "email" and action == "send":
        _close_request_snapshots({"_snapshot": target_snapshot, "_source_snapshot": source_snapshot})
        return 400, {"ok": False, "error": "send is not available in email mode; switch approval_channel to qq"}
    challenge = secrets.token_hex(2).upper() if email_mode else ""

    try:
        preview = approval_preview.build_preview(
            action,
            target_text,
            content=payload.get("content"),
            source=str(payload.get("source", "")),
            reason=str(payload.get("reason", "")),
        )
    except (OSError, ValueError) as exc:
        _close_request_snapshots({"_snapshot": target_snapshot, "_source_snapshot": source_snapshot})
        return 409, {"ok": False, "error": f"cannot build approval preview: {exc}"}

    preview["external_read_warning"] = injection_audit.warning()
    event = None
    with broker_state._lock:
        if broker_state._pending:
            _close_request_snapshots({"_snapshot": target_snapshot, "_source_snapshot": source_snapshot})
            return 409, {"ok": False, "error": "another TOTP request is pending"}
        request_id = secrets.token_hex(6)
        broker_state._pending = {
            "id": request_id,
            "action": action,
            "target": target_text,
            "source": str(payload.get("source", "")),
            "reason": str(payload.get("reason", ""))[:300],
            "deadline": time.monotonic() + TIMEOUT_SECONDS,
            "manifest": manifest,
            "content": payload.get("content"),
            "mode": _target_mode(action, target_text),
            "scope_root": str(Path(target_text).resolve(strict=False).parent),
            "target_summary": _snapshot_summary(target_snapshot, target_text),
            "source_summary": _path_summary(str(payload.get("source", ""))) if action == "overwrite" else "",
            "channel": "email" if email_mode else ("webui" if channel == "webui" else "qq"),
            "challenge": challenge,
            "approval_only": approval_only,
            "preview": preview,
            "_snapshot": target_snapshot,
            "_source_snapshot": source_snapshot,
        }
        if action == "send":
            prompt = _manifest_prompt(manifest or [])
        else:
            prompt = approval_preview.format_preview(preview, request_id)
        if action == "send":
            event = threading.Event()
            _send_events[request_id] = event
            _send_results[request_id] = False

    if email_mode:
        admin_email = _admin_email()
        if not admin_email:
            with broker_state._lock:
                if broker_state._pending and broker_state._pending.get("id") == request_id:
                    _close_request_snapshots(broker_state._pending)
                    broker_state._pending = None
            return 503, {"ok": False, "error": "email approval requires admin_email; configure it in the installer or WebUI"}
        try:
            email_config = email_approval.load_config()
            email_config["approval_to"] = admin_email
            subject = f"[Cyber-Butler] 待审批请求 #{challenge}"
            body = (
                f"{prompt}\n\n"
                f"回复第一行（只读第一行）：APPROVE #{challenge} TOTP 123456\n"
                f"有效期 5 分钟，仅一次。"
            )
            email_approval.send_email(email_config, subject, body)
        except Exception as exc:
            with broker_state._lock:
                if broker_state._pending and broker_state._pending.get("id") == request_id:
                    _close_request_snapshots(broker_state._pending)
                    broker_state._pending = None
            return 502, {"ok": False, "error": f"email challenge send failed: {exc}"}
        threading.Thread(target=email_watch, args=(request_id,), daemon=True).start()
        log(f"email challenge sent: {request_id} {action} {target_text}")
        return 200, {
            "ok": True,
            "status": "requires_totp",
            "id": request_id,
            "channel": "email",
            "challenge": challenge,
            "action": action,
            "target": target_text,
        }

    if channel == "webui":
        with broker_state._lock:
            if action != "send":
                if approval_only:
                    _set_approval_state(request_id, "pending", approval_only=True)
                threading.Thread(target=timeout_watch, args=(request_id,), daemon=True).start()
            log(f"webui challenge ready: {request_id} {action} {target_text}")
        return 200, {
            "ok": True,
            "status": "requires_totp",
            "id": request_id,
            "channel": "webui",
            "challenge": "",
            "action": action,
            "target": target_text,
        }

    # Network I/O must never run while broker_state._lock is held: send_qq can block for
    # up to 60 seconds, and the lock only protects pending-state transitions.
    if not send_qq(prompt):
        with broker_state._lock:
            if broker_state._pending and broker_state._pending.get("id") == request_id:
                _close_request_snapshots(broker_state._pending)
                broker_state._pending = None
            _send_events.pop(request_id, None)
            _send_results.pop(request_id, None)
        return 502, {"ok": False, "error": "QQ challenge send failed"}

    with broker_state._lock:
        if action != "send":
            if approval_only:
                _set_approval_state(request_id, "pending", approval_only=True)
            threading.Thread(target=timeout_watch, args=(request_id,), daemon=True).start()
        log(f"challenge sent: {request_id} {action} {target_text}")

    if approval_only:
        response: dict[str, object] = {
            "ok": True,
            "status": "requires_totp",
            "approval_only": True,
            "id": request_id,
            "challenge_id": request_id,
            "action": action,
        }
        if scoped_invalid:
            response["scoped_invalid"] = True
            response["scoped_error"] = "CBS_SCOPED_INVALID"
        return 200, response

    if action == "send":
        approved = event.wait(TIMEOUT_SECONDS) if event else False
        with broker_state._lock:
            send_ok = bool(_send_results.pop(request_id, False))
            _send_events.pop(request_id, None)
            if broker_state._pending and broker_state._pending.get("id") == request_id:
                broker_state._pending = None
        if approved and send_ok:
            return 200, {"ok": True, "approved": True, "id": request_id}
        send_qq(approval_i18n.t("timeout"))
        return 408, {"ok": False, "approved": False, "error": "verification timed out"}

    response = {
        "ok": True,
        "status": "requires_totp",
        "id": request_id,
        "action": action,
        "target": target_text,
    }
    if scoped_invalid:
        response["scoped_invalid"] = True
        response["scoped_error"] = "CBS_SCOPED_INVALID"
    return 200, response


def record_external_read(payload: dict) -> tuple[int, dict]:
    """Let the agent report an external read; never store page content."""
    try:
        event = injection_audit.record(
            str(payload.get("kind", "web")),
            str(payload.get("source", "")),
            str(payload.get("summary", "")),
        )
    except (OSError, ValueError) as exc:
        return 400, {"ok": False, "error": str(exc)}
    return 200, {"ok": True, "event": event}


def run_verify(payload: dict) -> tuple[int, dict]:
    """Run verify.
    
    Args:
        payload: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if _is_uninstalling():
        return 503, {"ok": False, "status": "uninstalling", "error": "broker is uninstalling"}
    request_id = str(payload.get("id", "")).strip()
    code = str(payload.get("code", "")).strip()
    try:
        bypass_seconds = int(payload.get("bypass_seconds", 0) or 0)
    except (TypeError, ValueError):
        bypass_seconds = 0
    bypass_seconds = max(0, min(bypass_seconds, BYPASS_TTL_SECONDS))
    # The caller never owns approval scope. Broker computes it from the
    # pending target; a caller-supplied scoped_minutes is deliberately ignored.
    scoped_minutes = 0
    if _is_verification_locked():
        return 429, {"ok": False, "error": "verification is temporarily locked"}
    with broker_state._lock:
        if not broker_state._pending:
            return 404, {"ok": False, "error": "pending request not found or expired"}
        if not request_id:
            request_id = str(broker_state._pending.get("id", ""))
        if broker_state._pending.get("id") != request_id:
            return 404, {"ok": False, "error": "pending request not found or expired"}
        if broker_state._pending.get("channel") == "email":
            return 403, {"ok": False, "error": "email approval required"}
        if time.monotonic() > float(broker_state._pending.get("deadline", 0)):
            expired_id = str(broker_state._pending.get("id", ""))
            if broker_state._pending.get("approval_only"):
                _set_approval_state(expired_id, "expired", approval_only=True)
            _close_request_snapshots(broker_state._pending)
            broker_state._pending = None
            return 410, {"ok": False, "error": "verification code expired"}
        code_type = verify_code(code, request_id)
        if code_type == "replay":
            _record_global_failure()
            audit_failure(
                request_id,
                str(broker_state._pending.get("action", "")),
                str(broker_state._pending.get("target", "")),
                int(broker_state._pending.get("attempts", 0)) + 1,
            )
            return 429, {"ok": False, "error": "TOTP replay rejected"}
        if not code_type:
            attempts = int(broker_state._pending.get("attempts", 0)) + 1
            broker_state._pending["attempts"] = attempts
            delay = _record_global_failure()
            audit_failure(
                request_id,
                str(broker_state._pending.get("action", "")),
                str(broker_state._pending.get("target", "")),
                attempts,
            )
            if attempts >= TOTP_MAX_ATTEMPTS:
                if broker_state._pending.get("approval_only"):
                    _set_approval_state(str(broker_state._pending.get("id", "")), "denied", approval_only=True)
                _close_request_snapshots(broker_state._pending)
                broker_state._pending = None
                broker_state._verify_locked_until = time.monotonic() + VERIFY_LOCK_SECONDS
                log(
                    f"verification locked after {attempts} failures: {request_id} "
                    f"(global_failures={broker_state._global_failures}, backoff={delay:.0f}s)"
                )
                return 429, {
                    "ok": False,
                    "error": "too many invalid attempts; verification locked",
                    "attempts": attempts,
                }
            _deny_jitter()
            return 403, {
                "ok": False,
                "error": "invalid verification code",
                "attempts": attempts,
            }
        broker_state._global_failures = 0
        broker_state._global_lock_until = 0.0
        request = dict(broker_state._pending)
        if request.get("action") == "send":
            manifest = request.get("manifest")
            if manifest is None:
                broker_state._pending = None
                _fail_send_wait(request_id)
                return 409, {"ok": False, "error": "file manifest missing at approval"}
            try:
                current = _canonical_manifest(manifest)
            except (OSError, ValueError) as exc:
                broker_state._pending = None
                _audit_manifest_reject(request_id, request, f"manifest invalid at approval: {exc}")
                _fail_send_wait(request_id)
                return 409, {"ok": False, "error": f"file manifest changed: {exc}"}
            if not _manifest_equal(manifest, current):
                broker_state._pending = None
                _audit_manifest_reject(request_id, request, "manifest changed at approval")
                _fail_send_wait(request_id)
                return 409, {"ok": False, "error": "file manifest changed before approval"}
        broker_state._pending = None
        if request.get("action") in {"delete", "overwrite", "write_file"}:
            try:
                _assert_snapshots_current(request)
            except TargetGuardError as exc:
                _close_request_snapshots(request)
                return 409, {"ok": False, "error": f"target changed before approval (TOCTOU): {exc}"}
            if request.get("_snapshot") is None and _path_summary(str(request.get("target", ""))) != request.get("target_summary"):
                _close_request_snapshots(request)
                return 409, {"ok": False, "error": "target changed before approval"}
            if request.get("action") == "overwrite" and request.get("_source_snapshot") is None:
                if _path_summary(str(request.get("source", ""))) != request.get("source_summary"):
                    _close_request_snapshots(request)
                    return 409, {"ok": False, "error": "source changed before approval"}
        if request.get("approval_only"):
            scoped = None
            if scoped_minutes > 0:
                scoped = _issue_scoped(
                    str(request.get("action", "")),
                    str(request.get("target", "")),
                    scoped_minutes,
                )
            _set_approval_state(request_id, "approved", approval_only=True, scoped=scoped)
            _notify_async(approval_i18n.t("approved"))
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
            _retain_snapshots(request_id, request)
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

    execution = execute(request)
    ok, result = execution
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
    if ok and request.get("_trash_entry"):
        response["undo_available"] = True
        response["trash_id"] = request_id
        response["undo_expires_at"] = str(request.get("_trash_expires_at", ""))
        response["undo_expires_epoch"] = float(request.get("_trash_expires_epoch", 0) or 0)
    if bypass:
        response["bypass_token"] = bypass["token"]
        response["bypass_expires_in"] = bypass["expires_in"]
    if scoped:
        response["scoped_token"] = scoped["token"]
        response["scoped_expires_in"] = scoped["expires_in"]
        response["scoped_root"] = scoped["root"]
    return (200 if ok else execution.status), response


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
    """Get approval status.
    
    Args:
        challenge_id: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    challenge_id = str(challenge_id or "").strip()
    if not challenge_id:
        return 400, {"ok": False, "error": "id is required"}
    state = _get_approval_state(challenge_id)
    if not state:
        return 404, {"ok": False, "status": "unknown", "error": "challenge not found"}
    body = {
        "ok": True,
        "status": state.get("status", "pending"),
        "challenge_id": challenge_id,
        "approval_only": bool(state.get("approval_only", True)),
    }
    if body["status"] == "approved" and state.get("scoped_token"):
        body["scoped_token"] = str(state["scoped_token"])
        body["scoped_expires_in"] = int(state.get("scoped_expires_in", 0) or 0)
        body["scoped_root"] = str(state.get("scoped_root", ""))
    return 200, body


def _totp_qr(uri: str) -> str:
    """Totp qr.
    
    Args:
        uri: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    image = qrcode.make(uri)
    buffer = io.BytesIO()
    image.get_image().save(buffer, format="PNG")
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def totp_binding_payload() -> dict:
    """Totp binding payload.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    value = secret()
    uri = pyotp.TOTP(value).provisioning_uri(
        name="Cyber-Butler owner", issuer_name="Cyber-Butler"
    )
    return {
        "ok": True,
        "otpauth_uri": uri,
        "qr_png_base64": _totp_qr(uri),
        "issuer": "Cyber-Butler",
        "account": "Cyber-Butler owner",
    }


def reset_totp_with_recovery(code: str) -> tuple[int, dict]:
    """Consume a recovery code, rotate the secret, and return new enrollment."""
    code = str(code or "").strip().upper()
    if verify_code(code, "recovery-reset") != "recovery":
        return 403, {"ok": False, "error": "valid recovery code required"}
    if win32crypt is None:
        return 503, {"ok": False, "error": "win32crypt is unavailable"}
    value = pyotp.random_base32()
    TOTP_VAULT.mkdir(parents=True, exist_ok=True)
    encrypted = win32crypt.CryptProtectData(
        value.encode("utf-8"), "Cyber-Butler TOTP", None, None, None, 0x4
    )
    SECRET_FILE.write_bytes(encrypted)
    codes = [
        "".join(secrets.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(8))
        for _ in range(3)
    ]
    hashes = [hashlib.sha256(item.encode("utf-8")).hexdigest() for item in codes]
    RECOVERY_FILE.write_text(
        json.dumps({"sha256": hashes, "used": []}, indent=2), encoding="utf-8"
    )
    recovery_text = RECOVERY_FILE.with_name("recovery_codes.txt")
    recovery_lines = ["Cyber-Butler TOTP recovery codes (one use each)", ""]
    recovery_lines.extend(f"{i + 1}. {item}" for i, item in enumerate(codes))
    recovery_lines.append("")
    recovery_text.write_text(chr(10).join(recovery_lines), encoding="utf-8")

    with broker_state._replay_lock:
        broker_state._used_totp.clear()
    payload = totp_binding_payload()
    payload["recovery_codes"] = codes
    return 200, payload


def undo_trash_request(payload: dict) -> tuple[int, dict]:
    """Undo a two-stage delete; the HTTP layer has already authenticated."""
    request_id = str(payload.get("id", "") or "").strip()
    if not request_id or any(ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for ch in request_id):
        return 400, {"ok": False, "error": "invalid trash id"}
    entry = quarantine.TRASH_STAGING / request_id
    if not entry.is_dir():
        return 404, {"ok": False, "error": "trash entry not found or expired"}
    try:
        manifest = quarantine._read_manifest(entry)
        destination = Path(str(manifest.get("original_path", "")))
        if not destination.is_absolute() or not _allowed_target(destination):
            return 400, {"ok": False, "error": "original target is not allowed"}
        restored = quarantine.restore_quarantine(entry, destination)
    except FileExistsError:
        return 409, {"ok": False, "error": "original path exists again; refusing to overwrite"}
    except (OSError, ValueError) as exc:
        return 409, {"ok": False, "error": "undo failed: " + str(exc)}
    try:
        AUDIT.parent.mkdir(parents=True, exist_ok=True)
        with AUDIT.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps({
                "at": datetime.now().isoformat(timespec="seconds"),
                "id": request_id,
                "action": "trash_undo",
                "target": str(restored),
                "ok": True,
                "result": "two-stage delete restored by owner",
            }, ensure_ascii=False) + "\n")
    except OSError as exc:
        log("trash undo audit warning: " + str(exc))
    return 200, {"ok": True, "restored": str(restored), "id": request_id}


class Handler(BaseHTTPRequestHandler):
    """Handler helper/type."""
    server_version = "AgentRuntimeTOTPBroker/1.6.3"

    def _json(self, status: int, payload: dict) -> None:
        """Json.
        
        Args:
            status: caller-supplied value.
            payload: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _auth(self) -> bool:
        """Auth.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        expected = ensure_token()
        provided = self.headers.get("X-Broker-Token", "")
        return secrets.compare_digest(provided, expected)

    def _host_origin_ok(self) -> bool:
        """Reject DNS-rebinding / cross-site requests before token auth."""
        host_header = str(self.headers.get("Host", "") or "").strip().casefold()
        if host_header not in ALLOWED_HOSTS:
            return False
        origin = str(self.headers.get("Origin", "") or "").strip()
        if origin:
            try:
                parsed = urlparse(origin)
            except ValueError:
                return False
            if parsed.scheme not in {"http", "https"}:
                return False
            if (parsed.hostname or "").lower() not in {"127.0.0.1", "localhost"}:
                return False
        return True

    def _local_only(self) -> bool:
        """Local only.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        peer = str(self.client_address[0] if self.client_address else "").strip()
        try:
            loopback = bool(peer and ipaddress.ip_address(peer).is_loopback)
        except ValueError:
            loopback = False
        if not loopback:
            self._json(403, {"ok": False, "error": "loopback access only"})
            log(f"rejected non-loopback client: {peer}")
            return False
        if not self._host_origin_ok():
            self._json(403, {"ok": False, "error": "invalid Host or Origin"})
            log(
                "rejected forged Host/Origin: host=%r origin=%r"
                % (self.headers.get("Host", ""), self.headers.get("Origin", ""))
            )
            return False
        return True

    def _body(self) -> dict:
        """Body.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        raw_length = str(self.headers.get("Content-Length", "0") or "0").strip()
        try:
            length = int(raw_length)
        except (TypeError, ValueError) as exc:
            raise ValueError("invalid Content-Length") from exc
        if length < 0 or length > 65536:
            raise ValueError("Content-Length out of range")
        if not length:
            raw = b"{}"
        else:
            chunks = []
            remaining = length
            while remaining > 0:
                chunk = self.rfile.read(remaining)
                if not chunk:
                    raise ValueError("incomplete request body")
                chunks.append(chunk)
                remaining -= len(chunk)
            raw = b"".join(chunks)
        if len(raw) != length:
            raise ValueError("request body length mismatch")
        # Tolerate an optional UTF-8 BOM; reject other invalid UTF-8 instead of
        # silently replacing bytes and turning a valid JSON error into a 400.
        text = raw.decode("utf-8-sig")
        try:
            return json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"invalid JSON at position {exc.pos}: {exc.msg}") from exc

    def do_GET(self) -> None:
        """Do get.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        if not self._local_only():
            return
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json(200, {"status": "ok"})
        elif parsed.path == "/api/request_approval/status":
            if not self._auth():
                self._json(403, {"ok": False, "error": "unauthorized"})
                return
            query = parse_qs(parsed.query)
            challenge_id = str((query.get("id") or [""])[0])
            status, body = get_approval_status(challenge_id)
            self._json(status, body)
        elif parsed.path == "/pending":
            if not self._auth():
                self._json(403, {"ok": False, "error": "unauthorized"})
                return
            # Read-only hint for the local dashboard. Never expose the TOTP,
            # email challenge, full path, manifest or reason.
            with broker_state._lock:
                pending = dict(broker_state._pending) if broker_state._pending else None
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
                    "target_size": int((getattr(pending.get("_snapshot"), "identity", (0, 0, 0, 0))[2]) or 0),
                    "target_mtime_ns": int((getattr(pending.get("_snapshot"), "identity", (0, 0, 0, 0))[3]) or 0),
                    "remaining_seconds": remaining,
                })
        elif parsed.path == "/pending/approval":
            if not self._auth():
                self._json(403, {"ok": False, "error": "unauthorized"})
                return
            with broker_state._lock:
                pending = dict(broker_state._pending) if broker_state._pending else None
            if not pending:
                self._json(200, {"ok": True, "pending": False})
            else:
                snapshot = pending.get("_snapshot")
                self._json(200, {
                    "ok": True,
                    "pending": True,
                    "id": str(pending.get("id", "")),
                    "action": str(pending.get("action", "")),
                    "target_name": Path(str(pending.get("target", ""))).name,
                    "scope_root": str(pending.get("scope_root", "")),
                    "target_size": int(snapshot.identity[2] if snapshot else 0),
                    "target_mtime_ns": int(snapshot.identity[3] if snapshot else 0),
                    "remaining_seconds": max(0, int(float(pending.get("deadline", 0)) - time.monotonic())),
                })
        elif parsed.path == "/totp/bind":
            if not self._auth():
                self._json(403, {"ok": False, "error": "unauthorized"})
                return
            try:
                self._json(200, totp_binding_payload())
            except Exception as exc:
                self._json(409, {"ok": False, "error": str(exc)})
        elif parsed.path == "/trash":
            if not self._auth():
                self._json(403, {"ok": False, "error": "unauthorized"})
                return
            trash_items = quarantine.list_pending()
            self._json(200, {"ok": True, "items": trash_items})
        else:
            self._json(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:
        """Do post.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        if not self._local_only():
            return
        if not self._auth():
            self._json(403, {"ok": False, "error": "unauthorized"})
            return
        try:
            payload = self._body()
        except (ValueError, TypeError) as exc:
            self._json(400, {"ok": False, "error": "invalid JSON", "detail": str(exc)})
            return
        try:
            parsed = urlparse(self.path)
            if parsed.path in {"/request", "/api/request_approval"}:
                client_ip = str(getattr(self, "client_address", ("unknown",))[0] or "unknown")
                bucket_key = client_ip + ":" + str(payload.get("action", "") or "request")
                allowed, retry_after = _allow_request(bucket_key)
                if not allowed:
                    self._json(429, {
                        "ok": False,
                        "error": "request rate limited",
                        "retry_after": retry_after,
                    })
                    return
                if parsed.path == "/api/request_approval":
                    status, body = run_approval_request(payload)
                else:
                    status, body = run_request(payload)
            elif parsed.path == "/external-read":
                status, body = record_external_read(payload)
            elif parsed.path == "/verify":
                status, body = run_verify(payload)
            elif parsed.path == "/deny":
                request_id = str(payload.get("id", "")).strip()
                if request_id:
                    released = _release_retained(request_id)
                    log(f"approval denied id={request_id[:32]} released={released}")
                    status, body = 200, {"ok": True, "denied": True, "released": released}
                else:
                    status, body = 400, {"ok": False, "error": "id required"}
            elif parsed.path == "/approval/complete":
                request_id = str(payload.get("id", "")).strip()
                if request_id:
                    status, body = 200, {"ok": True, "released": _release_retained(request_id)}
                else:
                    status, body = 400, {"ok": False, "error": "id required"}
            elif parsed.path == "/trash/undo":
                status, body = undo_trash_request(payload)
            elif parsed.path == "/totp/recovery-reset":
                status, body = reset_totp_with_recovery(str(payload.get("code", "")))
            else:
                status, body = 404, {"ok": False, "error": "not found"}
        except Exception as exc:
            log(f"HTTP handler error: {exc}")
            status, body = 500, {"ok": False, "error": str(exc)}
        self._json(status, body)

    def log_message(self, format: str, *args) -> None:
        """Log message.
        
        Args:
            fmt: caller-supplied value.
            args: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        log("http: " + format % args)


def verify_runtime_acl() -> None:
    """Fail closed unless the checker proves the real filesystem ACLs are safe."""
    if TEST_MODE:
        return
    if os.name != "nt":
        return
    checker = ROOT / "tools" / "verify_broker_acl.ps1"
    if not checker.exists():
        raise SystemExit(
            "Broker refuses to start: tools/verify_broker_acl.ps1 is missing; "
            "lock down tools/ and AgentRuntime/.venv before running as SYSTEM."
        )
    try:
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
            timeout=45,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise SystemExit(f"Broker refuses to start: ACL checker could not run: {exc}") from exc
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise SystemExit(
            "Broker refuses to start: runtime ACL is writable or owned by a "
            f"low-privilege principal. {detail}"
        )
    if "Broker runtime ACL: OK" not in (result.stdout or ""):
        raise SystemExit("Broker refuses to start: ACL checker did not confirm success")
    log("runtime ACL check passed (tools/ and AgentRuntime/.venv locked)")


def main() -> None:
    """Main.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    unrendered = [value for value in (str(ROOT), str(SHARED), UMO) if "YOUR_" in value]
    if unrendered:
        log("broker startup refused: unrendered YOUR_* placeholder; run the installer or render the template first")
        raise SystemExit("Broker refuses to start: unrendered YOUR_* placeholder")

    log("broker startup; checking loopback port ownership")
    port_guard.assert_broker_port(PORT)
    log("broker starting; installing job object")
    initialize_job_object()
    log("broker starting; verifying runtime ACL")
    try:
        verify_runtime_acl()
    except SystemExit as exc:
        log(f"broker startup refused: {exc}")
        raise
    ensure_token()
    _start_audit_chain_mirror()
    QUARANTINE.mkdir(parents=True, exist_ok=True)
    STAGING.mkdir(parents=True, exist_ok=True)
    log(f"broker HTTP listening on {HOST}:{PORT}")
    quarantine.start_sweeper()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    try:
        server.serve_forever()
    finally:
        close_job_object()


if __name__ == "__main__":
    main()
