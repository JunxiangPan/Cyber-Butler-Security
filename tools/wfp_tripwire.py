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
    inode: int = 0
    size: int = 0
    offset: int = 0
    mtime_ns: int = 0

    @classmethod
    def load(cls, path: Path) -> "Cursor":
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            return cls(
                int(data.get("inode", 0)),
                int(data.get("size", 0)),
                int(data.get("offset", 0)),
                int(data.get("mtime_ns", 0)),
            )
        except (OSError, ValueError, TypeError):
            return cls()

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.__dict__, sort_keys=True), encoding="utf-8")


def _stat_identity(path: Path) -> tuple[int, int, int]:
    stat = path.stat()
    return int(getattr(stat, "st_ino", 0)), int(stat.st_size), int(getattr(stat, "st_mtime_ns", 0))


def parse_firewall_line(line: str) -> dict | None:
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
    log_path = Path(log_path)
    cursor = Cursor.load(cursor_path)
    if not log_path.exists():
        return []
    inode, size, mtime_ns = _stat_identity(log_path)
    replaced = size == cursor.size and cursor.offset and mtime_ns != cursor.mtime_ns
    if inode != cursor.inode or size < cursor.offset or replaced:
        cursor = Cursor(inode, size, 0, mtime_ns)
    events = []
    with log_path.open("rb") as handle:
        handle.seek(cursor.offset)
        for raw in handle:
            line = raw.decode("utf-8", errors="replace")
            parsed = parse_firewall_line(line)
            if parsed:
                parsed["event"] = "NETWORK_EXFILTRATION_ATTEMPT"
                parsed["observed_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
                events.append(parsed)
        cursor.offset = handle.tell()
    cursor.inode = inode
    cursor.size = size
    cursor.mtime_ns = mtime_ns
    cursor.save(cursor_path)
    return events


def append_events(audit_path: Path, events: list[dict]) -> None:
    if not events:
        return
    from audit_chain import append_event

    for event in events:
        append_event(audit_path, event)
