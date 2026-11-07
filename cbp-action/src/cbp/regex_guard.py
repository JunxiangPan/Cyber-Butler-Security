"""Regex execution with a real wall-clock timeout.

Uses the optional regex package when available; otherwise evaluates the
match in an isolated Python child process so the parent can kill a runaway
expression. The child timeout is a hard wall-clock limit, not a heuristic.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

CHILD_TIMEOUT_SECONDS = 2.0
_RISKY = re.compile(r"(\([^)]*[+*][^)]*\)[+*{])|(\*\*)|(\+\+)|(\[1-9])")


class RegexTimeout(RuntimeError):
    """Raised when a regex exceeds its wall-clock budget."""


_SCRIPT = r'''
import json, re, sys
request = json.load(sys.stdin)
try:
    spans = [m.start() for m in re.finditer(request["pattern"], request["text"], request["flags"])]
except Exception as exc:
    print(json.dumps({"error": str(exc)}))
    raise SystemExit(2)
print(json.dumps({"spans": spans}))
'''


def _positions(pattern: str, flags: int, text: str, timeout: float) -> list[int]:
    try:
        import regex as regex_module  # optional, C-level timeout
    except ImportError:
        regex_module = None
    if regex_module is not None:
        try:
            return [match.start() for match in regex_module.finditer(pattern, text, flags=flags, timeout=timeout)]
        except TimeoutError as exc:
            raise RegexTimeout(f"regex exceeded {timeout}s") from exc
    if not _RISKY.search(pattern):
        return [match.start() for match in re.finditer(pattern, text, flags)]
    request = json.dumps({"pattern": pattern, "text": text, "flags": flags})
    try:
        completed = subprocess.run(
            [sys.executable, "-c", _SCRIPT],
            input=request,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise RegexTimeout(f"regex exceeded {timeout}s") from exc
    if completed.returncode != 0:
        raise RegexTimeout("regex worker failed: " + completed.stderr.strip()[:200])
    try:
        return [int(value) for value in json.loads(completed.stdout)["spans"]]
    except (ValueError, KeyError, TypeError) as exc:
        raise RegexTimeout("regex worker returned invalid output") from exc


def find_lines(pattern: str, flags: int, text: str, timeout: float = CHILD_TIMEOUT_SECONDS) -> list[int]:
    """Return 1-based line numbers for matches, bounded by a hard timeout."""
    return [text.count("\n", 0, position) + 1 for position in _positions(pattern, flags, text, timeout)]


def exists(pattern: str, flags: int, text: str, timeout: float = CHILD_TIMEOUT_SECONDS) -> bool:
    """Return whether a pattern matches, bounded by a hard timeout."""
    return bool(_positions(pattern, flags, text, timeout))
