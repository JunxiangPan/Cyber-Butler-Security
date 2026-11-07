"""Versioned rule-pack loading with content hash verification."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path


class PackError(ValueError):
    """Raised when a pack is malformed or its hash does not match."""


def load_pack(path: Path, expected_sha256: str = "") -> dict:
    """Load one JSON pack and reject a hash mismatch."""
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if expected_sha256 and expected_sha256.lower() != digest:
        raise PackError(f"pack hash mismatch for {path.name}")
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise PackError(f"pack is not valid JSON: {path.name}") from exc
    if not isinstance(data.get("rules"), list):
        raise PackError(f"pack has no rules array: {path.name}")
    if not data.get("name") or not data.get("version"):
        raise PackError(f"pack needs name and version: {path.name}")
    data["_sha256"] = digest
    return data
