"""Bounded diff semantics for pre-write approval."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class DiffBoundary:
    root: str
    max_files: int = 1
    max_bytes: int = 262144
    allow_create: bool = False
    allow_delete: bool = False


def check_diff(boundary: DiffBoundary, changes: Iterable[dict]) -> tuple[bool, str]:
    """Return (ok, reason); this function performs no write."""
    try:
        root = Path(boundary.root).resolve(strict=False)
    except (OSError, ValueError):
        return False, "invalid boundary root"
    count = 0
    total = 0
    for change in changes:
        if not isinstance(change, dict):
            return False, "change must be an object"
        kind = str(change.get("kind", "modify")).lower()
        if kind not in {"modify", "create", "delete"}:
            return False, "unsupported change kind"
        if kind == "create" and not boundary.allow_create:
            return False, "create is outside this boundary"
        if kind == "delete" and not boundary.allow_delete:
            return False, "delete is outside this boundary"
        try:
            path = Path(str(change.get("path", ""))).resolve(strict=False)
            path.relative_to(root)
        except (OSError, ValueError):
            return False, "path escapes boundary root"
        size = int(change.get("size", 0) or 0)
        if size < 0:
            return False, "size must be non-negative"
        count += 1
        total += size
        if count > boundary.max_files:
            return False, "file count exceeds boundary"
        if total > boundary.max_bytes:
            return False, "byte count exceeds boundary"
    return True, "within boundary"
