"""Quarantine for high-risk Broker deletes and overwrites.

A deleted file is moved into a per-request directory with a manifest. The
original handle is re-checked immediately before the move so a path swap cannot
silently redirect the operation.
"""

from __future__ import annotations

import json
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

from win_path_guard import TargetSnapshot

ROOT = Path(os.environ.get("CBS_ROOT", r"C:\CyberButler"))
QUARANTINE_ROOT = ROOT / "tools" / "broker" / "quarantine"


def _manifest_path(entry: Path) -> Path:
    return entry / "manifest.json"


def quarantine_file(
    snapshot: TargetSnapshot,
    request_id: str,
    *,
    original_path: str,
    action: str,
    reason: str = "",
) -> Path:
    """Move an approved file into quarantine and write its manifest."""
    snapshot.assert_unchanged()
    QUARANTINE_ROOT.mkdir(parents=True, exist_ok=True)
    safe_id = "".join(ch for ch in request_id if ch.isalnum() or ch in "-_")[:80]
    entry = QUARANTINE_ROOT / f"{safe_id}_{snapshot.path.name}"
    if entry.exists():
        raise FileExistsError(f"quarantine entry already exists: {entry}")
    entry.mkdir(parents=False, exist_ok=False)
    destination = entry / snapshot.path.name
    try:
        snapshot.copy_to(destination)
        snapshot.assert_unchanged()
        snapshot.delete()
    except Exception:
        try:
            destination.unlink(missing_ok=True)
            entry.rmdir()
        finally:
            raise
    snapshot.close()
    manifest = {
        "request_id": request_id,
        "action": action,
        "original_path": original_path,
        "quarantine_path": str(destination),
        "sha256": snapshot.sha256,
        "size": snapshot.identity[2],
        "mtime_ns": snapshot.identity[3],
        "reason": reason[:300],
        "created_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    _manifest_path(entry).write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return entry


def restore_quarantine(entry: Path, destination: Path) -> Path:
    """Restore a quarantined file; caller must require a fresh TOTP first."""
    manifest = json.loads(_manifest_path(entry).read_text(encoding="utf-8"))
    source = Path(manifest["quarantine_path"])
    if not source.is_file():
        raise FileNotFoundError(source)
    if destination.exists():
        raise FileExistsError(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(destination))
    manifest["restored_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    manifest["restored_to"] = str(destination)
    _manifest_path(entry).write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return destination
