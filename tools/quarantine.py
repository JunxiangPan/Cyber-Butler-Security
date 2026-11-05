"""Two-Stage Delayed Delete staging for high-risk Broker deletes.

A delete approved by TOTP is *not* destroyed immediately. The file is moved
under ``trash_staging/<request_id>/`` and locked to SYSTEM-only access. An undo
API can restore it during the grace period. After the deadline a sweeper
overwrites the bytes and removes the entry.
"""

from __future__ import annotations

import getpass
import json
import os
import shutil
import subprocess
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from win_path_guard import TargetSnapshot

ROOT = Path(os.environ.get("CBS_ROOT", r"C:\CyberButler")).resolve()
QUARANTINE_ROOT = ROOT / "tools" / "broker" / "quarantine"
TRASH_STAGING = ROOT / "tools" / "broker" / "trash_staging"
DELAY_SECONDS = int(os.environ.get("CBS_TRASH_DELAY_SECONDS", "600"))
MAX_BYTES = int(os.environ.get("CBS_TRASH_MAX_BYTES", str(500 * 1024 * 1024)))
MAX_ENTRIES = int(os.environ.get("CBS_TRASH_MAX_ENTRIES", "1000"))
SERVICE_ACCOUNT = os.environ.get("CBS_SERVICE_ACCOUNT", "CyberButlerSvc")
_sweep_lock = threading.Lock()


class QuarantineCapacityError(OSError):
    """Raised when the staging area would exceed its hard capacity budget."""


def _safe_id(request_id: str) -> str:
    """Safe id.
    
    Args:
        request_id: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return "".join(ch for ch in request_id if ch.isalnum() or ch in "-_")[:80] or "request"


def _manifest_path(entry: Path) -> Path:
    """Manifest path.
    
    Args:
        entry: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return entry / "manifest.json"


def _entry_bytes() -> int:
    """Entry bytes.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    total = 0
    if not TRASH_STAGING.is_dir():
        return 0
    for path in TRASH_STAGING.rglob("*"):
        try:
            if path.is_file() and not path.is_symlink():
                total += path.stat().st_size
        except OSError:
            continue
    return total


def _lock_quarantine_acl(entry: Path) -> None:
    """Grant SYSTEM only; explicitly deny the desktop owner and Svc account.

    The Broker is the SYSTEM process that can still move/restore/erase. The
    desktop account must use the undo API; Explorer and the agent cannot read
    the staged bytes.
    """
    if os.name != "nt" or os.environ.get("CBS_DISABLE_ACL") == "1" or os.environ.get("CBS_TEST_MODE") == "1":
        return
    owner = getpass.getuser()
    # SYSTEM can resolve through getpass as "HYPERPC$"; that computer account
    # has no local mapping and icacls rejects it. The SYSTEM grant above
    # already covers the Broker, so omit non-user identities.
    if owner.casefold() in {"system", r"nt authority\system"} or owner.endswith("$"):
        owner = ""
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    args = ["icacls", str(entry), "/inheritance:r", "/grant:r", "*S-1-5-18:(F)"]
    for identity in {owner, SERVICE_ACCOUNT}:
        if identity and identity.casefold() not in {"system", "nt authority\\system"}:
            args.extend(["/deny", f"{identity}:(R,W,D)"])
    result = subprocess.run(args, capture_output=True, text=True, creationflags=flags)
    if result.returncode != 0:
        raise OSError("cannot lock trash ACL: " + (result.stderr or "").strip())


def quarantine_file(
    snapshot: TargetSnapshot,
    request_id: str,
    *,
    original_path: str,
    action: str,
    reason: str = "",
) -> Path:
    """Move an approved file into two-stage staging and write its manifest."""
    snapshot.assert_unchanged()
    if snapshot.is_directory:
        raise OSError("two-stage delayed delete supports regular files only")
    size = int(snapshot.identity[2])
    if _entry_bytes() + size > MAX_BYTES:
        raise QuarantineCapacityError(
            f"trash staging byte quota exceeded: {MAX_BYTES} bytes"
        )
    if len(list_pending()) >= MAX_ENTRIES:
        raise QuarantineCapacityError(
            f"trash staging entry quota exceeded: {MAX_ENTRIES} entries"
        )
    TRASH_STAGING.mkdir(parents=True, exist_ok=True)
    entry = TRASH_STAGING / _safe_id(request_id)
    if entry.exists():
        raise FileExistsError(f"trash entry already exists: {entry}")
    entry.mkdir(parents=False, exist_ok=False)
    try:
        _lock_quarantine_acl(entry)
    except Exception:
        try:
            entry.rmdir()
        finally:
            snapshot.close()
        raise
    destination = entry / snapshot.path.name
    try:
        source = snapshot.path
        digest = snapshot.sha256
        identity = snapshot.identity
        # Close the verified handle before the move; the source was already
        # re-checked and the destination is locked to SYSTEM.
        snapshot.close()
        shutil.move(str(source), str(destination))
    except Exception:
        try:
            destination.unlink(missing_ok=True)
            entry.rmdir()
        finally:
            raise
    now = datetime.now(timezone.utc)
    expires = time.time() + DELAY_SECONDS
    manifest = {
        "request_id": request_id,
        "action": action,
        "original_path": original_path,
        "quarantine_path": str(destination),
        "sha256": digest,
        "size": size,
        "mtime_ns": int(identity[3]),
        "reason": reason[:300],
        "state": "pending_delete",
        "created_at": now.isoformat(timespec="seconds"),
        "expires_at": datetime.fromtimestamp(expires, timezone.utc).isoformat(timespec="seconds"),
        "expires_epoch": expires,
    }
    manifest_path = _manifest_path(entry)
    tmp = manifest_path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(manifest_path)
    return entry


def _read_manifest(entry: Path) -> dict[str, Any]:
    """Read manifest.
    
    Args:
        entry: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return json.loads(_manifest_path(entry).read_text(encoding="utf-8"))


def list_pending() -> list[dict[str, Any]]:
    """List pending.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    result: list[dict[str, Any]] = []
    if not TRASH_STAGING.is_dir():
        return result
    for entry in sorted(TRASH_STAGING.iterdir()):
        if not entry.is_dir():
            continue
        try:
            manifest = _read_manifest(entry)
        except (OSError, ValueError):
            continue
        if manifest.get("state") != "pending_delete":
            continue
        result.append({
            "id": str(manifest.get("request_id", entry.name)),
            "original_path": str(manifest.get("original_path", "")),
            "expires_at": str(manifest.get("expires_at", "")),
            "expires_epoch": float(manifest.get("expires_epoch", 0) or 0),
            "size": int(manifest.get("size", 0) or 0),
        })
    return result


def restore_quarantine(entry: Path, destination: Path) -> Path:
    """Restore a staged file; caller must have verified owner identity."""
    manifest = _read_manifest(entry)
    if manifest.get("state") != "pending_delete":
        raise ValueError("trash entry is not pending delete")
    source = Path(str(manifest["quarantine_path"]))
    if not source.is_file():
        raise FileNotFoundError(source)
    if destination.exists():
        raise FileExistsError(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(destination))
    manifest["state"] = "restored"
    manifest["restored_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    manifest["restored_to"] = str(destination)
    _manifest_path(entry).write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return destination


def secure_erase(path: Path, passes: int = 3) -> None:
    """Overwrite a regular file with random bytes, then unlink it."""
    if not path.is_file():
        if path.exists():
            raise OSError("secure erase supports regular files only")
        return
    length = path.stat().st_size
    with path.open("r+b", buffering=0) as handle:
        for _ in range(max(1, min(int(passes), 3))):
            handle.seek(0)
            remaining = length
            while remaining > 0:
                chunk = os.urandom(min(1024 * 1024, remaining))
                handle.write(chunk)
                remaining -= len(chunk)
            handle.flush()
            os.fsync(handle.fileno())
    path.unlink()


def purge_expired(now: float | None = None, *, secure: bool = True) -> int:
    """Erase expired staged files and remove their directories."""
    moment = time.time() if now is None else float(now)
    removed = 0
    with _sweep_lock:
        if not TRASH_STAGING.is_dir():
            return 0
        for entry in list(TRASH_STAGING.iterdir()):
            if not entry.is_dir():
                continue
            try:
                manifest = _read_manifest(entry)
                if manifest.get("state") != "pending_delete":
                    continue
                if float(manifest.get("expires_epoch", 0) or 0) > moment:
                    continue
                source = Path(str(manifest["quarantine_path"]))
                if secure:
                    secure_erase(source)
                else:
                    source.unlink(missing_ok=True)
                shutil.rmtree(entry, ignore_errors=True)
                removed += 1
            except (OSError, ValueError):
                continue
    return removed


def start_sweeper(interval_seconds: int = 15) -> threading.Thread:
    """Start sweeper.
    
    Args:
        interval_seconds: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    def loop() -> None:
        """Loop.
        
        Args:
            None.
        
        Returns:
            Function result, or None when no value is returned.
        """
        while True:
            try:
                purge_expired()
            except Exception:
                pass
            time.sleep(max(5, int(interval_seconds)))

    thread = threading.Thread(target=loop, name="cbs-trash-sweeper", daemon=True)
    thread.start()
    return thread
