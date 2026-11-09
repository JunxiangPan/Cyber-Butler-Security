#!/usr/bin/env python3
"""Canonical CBP base-body hash binding (CBP-BODY-001)."""
from __future__ import annotations

import hashlib
from pathlib import Path

MARKER = b"<!-- CBP-BODY-BASE-END -->"


def base_bytes(body: bytes) -> bytes:
    """Return bytes before the marker, or the whole body when absent."""
    index = body.find(MARKER)
    return body if index < 0 else body[:index]


def base_hash(body: bytes) -> str:
    """Return the lowercase SHA-256 of the base bytes."""
    return hashlib.sha256(base_bytes(body)).hexdigest()


def file_hash(path: Path) -> str:
    """Return the base hash of a body file's exact bytes."""
    return base_hash(path.read_bytes())
