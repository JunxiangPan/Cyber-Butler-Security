"""Append-only JSONL audit chain with explicit tamper detection."""

from __future__ import annotations

import hashlib
import json
import os
import threading
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

_LOCK = threading.Lock()


@contextmanager
def _process_lock(path: Path):
    """Process lock.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    lock_path = path.with_name(path.name + ".lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    if os.name == "nt":
        import msvcrt

        handle = lock_path.open("a+b")
        try:
            msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)
            yield
        finally:
            try:
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            finally:
                handle.close()
    else:
        import fcntl
        from typing import Any, cast
        fcntl_any = cast(Any, fcntl)

        handle = lock_path.open("a+b")
        try:
            fcntl_any.flock(handle.fileno(), fcntl_any.LOCK_EX)
            yield
        finally:
            fcntl_any.flock(handle.fileno(), fcntl_any.LOCK_UN)
            handle.close()
ZERO_HASH = "0" * 64


class AuditChainError(ValueError):
    """Raised when a chain record is malformed or tampered with."""


def _canonical(seq: int, previous: str, event: dict) -> str:
    """Canonical.
    
    Args:
        seq: caller-supplied value.
        previous: caller-supplied value.
        event: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    payload = json.dumps(
        {"seq": seq, "prev": previous, "event": event},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )
    return payload


def _hash(seq: int, previous: str, event: dict) -> str:
    """Hash.
    
    Args:
        seq: caller-supplied value.
        previous: caller-supplied value.
        event: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return hashlib.sha256(_canonical(seq, previous, event).encode("utf-8")).hexdigest()


def _tail(path: Path) -> tuple[int, str]:
    """Tail.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if not path.exists():
        return 0, ZERO_HASH
    last = None
    try:
        with path.open("rb") as handle:
            for line in handle:
                if line.strip():
                    last = line
    except OSError as exc:
        raise AuditChainError(f"cannot read audit chain: {exc}") from exc
    if last is None:
        return 0, ZERO_HASH
    try:
        record = json.loads(last)
    except ValueError as exc:
        raise AuditChainError("last audit line is not valid JSON") from exc
    return int(record.get("seq", 0)), str(record.get("hash", ""))


def append_event(path: Path, event: dict) -> dict:
    """Append one event; the previous head is chained into the new hash."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with _LOCK, _process_lock(path):
        seq, previous = _tail(path)
        seq += 1
        record = {
            "seq": seq,
            "at": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
            "prev": previous,
            "event": event,
            "hash": _hash(seq, previous, event),
        }
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
    return record


def verify_chain(path: Path) -> tuple[bool, str]:
    """Verify every link and sequence; return (ok, reason)."""
    path = Path(path)
    if not path.exists():
        return True, "empty chain"
    expected_seq = 1
    previous = ZERO_HASH
    try:
        with path.open("r", encoding="utf-8") as handle:
            for number, line in enumerate(handle, 1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except ValueError:
                    return False, f"line {number}: invalid JSON"
                if int(record.get("seq", -1)) != expected_seq:
                    return False, f"line {number}: sequence gap"
                if str(record.get("prev", "")) != previous:
                    return False, f"line {number}: previous hash mismatch"
                event = record.get("event")
                if not isinstance(event, dict):
                    return False, f"line {number}: event is not an object"
                actual = _hash(expected_seq, previous, event)
                if str(record.get("hash", "")) != actual:
                    return False, f"line {number}: hash mismatch"
                previous = actual
                expected_seq += 1
    except OSError as exc:
        return False, f"cannot read chain: {exc}"
    return True, f"valid through seq {expected_seq - 1}"


def anchor(path: Path, anchor_path: Path) -> dict:
    """Write a small head anchor outside the append-only JSONL file."""
    ok, reason = verify_chain(path)
    if not ok:
        raise AuditChainError(reason)
    seq, head = _tail(path)
    anchor = {
        "seq": seq,
        "head": head,
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    anchor_path.parent.mkdir(parents=True, exist_ok=True)
    anchor_path.write_text(json.dumps(anchor, sort_keys=True, indent=2), encoding="utf-8")
    return anchor
