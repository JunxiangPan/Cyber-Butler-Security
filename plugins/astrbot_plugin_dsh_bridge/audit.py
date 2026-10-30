"""Append-only JSONL audit sink for /dsh operations."""

from __future__ import annotations

import json
import os
import threading
from datetime import datetime
from pathlib import Path

COMMAND_NAMES = frozenset({"status", "health", "logs", "unknown"})
RESULT_NAMES = frozenset(
    {"ok", "degraded", "invalid", "denied", "rate_limited", "unavailable", "error"}
)


class AuditError(RuntimeError):
    """The audit sink cannot be written; the caller must fail closed."""


class AuditWriter:
    """Write exactly three fields per line: ts, command and result."""

    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self._lock = threading.Lock()
        try:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            fd = os.open(
                self.path,
                os.O_APPEND | os.O_CREAT | os.O_WRONLY,
                0o600,
            )
            os.close(fd)
        except OSError as exc:
            raise AuditError("audit path is not writable") from exc

    def write(self, command: str, result: str) -> None:
        """Append one audit record.

        Args:
            command: One of status, health, logs, unknown.
            result: One of the fixed result values.

        Raises:
            AuditError: The command/result is invalid or the append fails.
        """
        if command not in COMMAND_NAMES:
            raise AuditError("invalid audit command")
        if result not in RESULT_NAMES:
            raise AuditError("invalid audit result")
        record = {
            "ts": datetime.now().astimezone().isoformat(timespec="milliseconds"),
            "command": command,
            "result": result,
        }
        line = json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n"
        try:
            with self._lock:
                fd = os.open(
                    self.path,
                    os.O_APPEND | os.O_CREAT | os.O_WRONLY,
                    0o600,
                )
                with os.fdopen(fd, "a", encoding="utf-8", newline="\n") as handle:
                    handle.write(line)
                    handle.flush()
                    os.fsync(handle.fileno())
        except OSError as exc:
            raise AuditError("audit append failed") from exc
