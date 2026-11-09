#!/usr/bin/env python3
"""Canonical CBP base-body hash binding (CBP-BODY-001)."""
from __future__ import annotations

import hashlib
from pathlib import Path


def canonical_body_bytes(data: bytes) -> bytes:
    """Apply the single CBP canonical body transform."""
    text = data.decode("utf-8-sig")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.rstrip("\n")
    if text:
        text += "\n"
    return text.encode("utf-8")


def canonical_body_hash(data: bytes) -> str:
    """Return the lowercase SHA-256 of the canonical body bytes."""
    return hashlib.sha256(canonical_body_bytes(data)).hexdigest()


def canonical_body_hash_file(path: Path) -> str:
    """Return the canonical hash of a body file's exact bytes."""
    return canonical_body_hash(path.read_bytes())
