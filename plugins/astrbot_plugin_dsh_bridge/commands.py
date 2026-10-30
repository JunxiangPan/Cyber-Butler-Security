"""Exact command parser for the owner-only /dsh bridge."""

from __future__ import annotations

import re
from dataclasses import dataclass

USAGE = "用法：/dsh status | /dsh health | /dsh logs <1-200>"

_FIXED = {
    "/dsh status": "status",
    "/dsh health": "health",
}
_LOGS_RE = re.compile(r"/dsh logs ([1-9][0-9]{0,2})\Z")
_MAX_LOG_LINES = 200


@dataclass(frozen=True)
class Command:
    kind: str
    n: int = 0


def parse_command(text: str) -> Command | None:
    """Return a command only for the exact three supported forms.

    Outer whitespace is ignored. Everything else, including double spaces,
    mixed case, full-width slashes, extra arguments and natural language, is
    rejected. No fuzzy matching and no LLM parsing.
    """
    value = str(text or "").strip()
    kind = _FIXED.get(value)
    if kind:
        return Command(kind)
    match = _LOGS_RE.fullmatch(value)
    if match:
        n = int(match.group(1))
        if 1 <= n <= _MAX_LOG_LINES:
            return Command("logs", n)
    return None
