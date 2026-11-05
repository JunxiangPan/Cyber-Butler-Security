"""Tail Windows Firewall logs without freezing the process on an alert.

Windows Firewall/WFP blocked-connection logs are line-oriented and rotate. We
persist a byte offset plus a file identity; a truncated or replaced log is read
from the beginning. Every event is written as NETWORK_EXFILTRATION_ATTEMPT.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class Cursor:
    """Cursor helper/type."""
    inode: int = 0
    size: int = 0
    offset: int = 0
    mtime_ns: int = 0
    tail: str = ""

    @classmethod
    def load(cls, path: Path) -> "Cursor":
        """Load.
        
        Args:
            path: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            return cls(
                int(data.get("inode", 0)),
                int(data.get("size", 0)),
                int(data.get("offset", 0)),
                int(data.get("mtime_ns", 0)),
                str(data.get("tail", "")),
            )
        except (OSError, ValueError, TypeError):
            return cls()

    def save(self, path: Path) -> None:
        """Save.
        
        Args:
            path: caller-supplied value.
        
        Returns:
            Function result, or None when no value is returned.
        """
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.__dict__, sort_keys=True), encoding="utf-8")


def _stat_identity(path: Path) -> tuple[int, int, int]:
    """Stat identity.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    stat = path.stat()
    return int(getattr(stat, "st_ino", 0)), int(stat.st_size), int(getattr(stat, "st_mtime_ns", 0))


def parse_firewall_line(line: str) -> dict | None:
    """Parse firewall line.
    
    Args:
        line: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    fields = line.split()
    if len(fields) < 8:
        return None
    if fields[2].upper() not in {"DROP", "BLOCK", "DENY"}:
        return None
    return {
        "at": " ".join(fields[:2]),
        "action": fields[2].upper(),
        "protocol": fields[3],
        "src": fields[4],
        "dst": fields[5],
        "src_port": fields[6],
        "dst_port": fields[7],
        "line": line.strip()[:500],
        "event": "NETWORK_EXFILTRATION_ATTEMPT",
    }


def read_new(log_path: Path, cursor_path: Path) -> list[dict]:
    """Read new.
    
    Args:
        log_path: caller-supplied value.
        cursor_path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    log_path = Path(log_path)
    cursor = Cursor.load(cursor_path)
    if not log_path.exists():
        return []
    inode, size, mtime_ns = _stat_identity(log_path)
    skip_tail = ""
    reset = inode != cursor.inode or size < cursor.offset
    if cursor.offset and cursor.tail:
        tail_bytes = cursor.tail.encode("utf-8", "replace")
        tail_start = max(0, cursor.offset - len(tail_bytes))
        try:
            with log_path.open("rb") as probe:
                probe.seek(tail_start)
                if probe.read(len(tail_bytes)) != tail_bytes:
                    reset = True
        except OSError:
            reset = True
    if size == cursor.size and mtime_ns != cursor.mtime_ns:
        reset = True
    if reset:
        skip_tail = cursor.tail
        cursor = Cursor(inode, size, 0, mtime_ns)
    events = []
    last_raw = b""
    skipped_tail = False
    with log_path.open("rb") as handle:
        handle.seek(cursor.offset)
        for raw in handle:
            last_raw = raw
            line = raw.decode("utf-8", errors="replace")
            if skip_tail and not skipped_tail and line.rstrip(chr(13) + chr(10)) == skip_tail.rstrip(chr(13) + chr(10)):

                skipped_tail = True
                continue
            parsed = parse_firewall_line(line)
            if parsed:
                parsed["event"] = "NETWORK_EXFILTRATION_ATTEMPT"
                parsed["observed_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
                events.append(parsed)
        cursor.offset = handle.tell()
    cursor.inode = inode
    cursor.size = size
    cursor.mtime_ns = mtime_ns
    if last_raw:
        cursor.tail = last_raw.decode("utf-8", errors="replace").rstrip(chr(13) + chr(10))
    cursor.save(cursor_path)
    return events


def append_events(audit_path: Path, events: list[dict]) -> None:
    """Append events.
    
    Args:
        audit_path: caller-supplied value.
        events: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if not events:
        return
    from audit_chain import append_event

    for event in events:
        append_event(audit_path, event)
