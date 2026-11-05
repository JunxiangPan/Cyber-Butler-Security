"""Record the external content an agent reports reading.

This is an evidence trail, not an injection detector. It never stores page
content or model reasoning; only a bounded source label and timestamp.
"""

from __future__ import annotations

import json
import os
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(os.environ.get("CBS_ROOT", r"C:\CyberButler")).resolve()
EVENT_FILE = ROOT / "tools" / "external-reads.jsonl"
WARNING = "提示：Agent 最近读取了外部网页/文件，请仔细核对本次操作的合理性。"
_LOCK = threading.Lock()
MAX_SOURCE = 300


def record(kind: str, source: str, summary: str = "") -> dict:
    """Record.
    
    Args:
        kind: caller-supplied value.
        source: caller-supplied value.
        summary: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    kind = str(kind or "").strip().lower()
    if kind not in {"web", "file", "tool"}:
        raise ValueError("kind must be web, file or tool")
    source = str(source or "").strip()[:MAX_SOURCE]
    if not source:
        raise ValueError("source is required")
    event = {
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "kind": kind,
        "source": source,
        "summary": str(summary or "")[:200],
    }
    EVENT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with _LOCK:
        with EVENT_FILE.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
    return event


def recent(minutes: int = 10) -> list[dict]:
    """Recent.
    
    Args:
        minutes: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    if not EVENT_FILE.exists():
        return []
    cutoff = time.time() - max(1, int(minutes)) * 60
    items = []
    try:
        lines = EVENT_FILE.read_text(encoding="utf-8-sig").splitlines()
    except OSError:
        return []
    for line in lines[-500:]:
        try:
            event = json.loads(line)
            stamp = datetime.fromisoformat(str(event.get("at", "")).replace("Z", "+00:00"))
            if stamp.timestamp() >= cutoff:
                items.append(event)
        except (ValueError, TypeError, OSError):
            continue
    return items


def warning(minutes: int = 10) -> str:
    """Warning.
    
    Args:
        minutes: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return WARNING if recent(minutes) else ""
