"""Canonical JSON hashing shared by freeze and signing-report tools."""
from __future__ import annotations

import hashlib
import json


def canonical_json(value: object) -> bytes:
    """RFC 8785-compatible subset used by the release evidence tools."""
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")


def payload_sha256(value: object) -> str:
    """Return the canonical JCS SHA-256 of a payload."""
    return hashlib.sha256(canonical_json(value)).hexdigest()
