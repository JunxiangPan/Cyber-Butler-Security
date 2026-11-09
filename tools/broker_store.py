#!/usr/bin/env python3
"""Pure Broker store/manifest helpers extracted from broker.py."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from broker_state import _url_host_allowed


def _sha256_file(path: Path) -> str:
    """Sha256 file.
    
    Args:
        path: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_manifest(items) -> list[dict]:
    """Validate a complete send manifest and recompute every local hash."""
    if not isinstance(items, list) or not items:
        raise ValueError("manifest is required")
    if len(items) > 5:
        raise ValueError("manifest has more than 5 entries")
    canonical: list[dict] = []
    total_bytes = 0
    for item in items:
        if not isinstance(item, dict):
            raise ValueError("manifest entry must be an object")
        kind = str(item.get("kind", "file")).lower()
        raw_path = str(item.get("path", "")).strip()
        if not raw_path:
            raise ValueError("manifest entry has no path")
        if kind == "url":
            if not raw_path.startswith(("http://", "https://")):
                raise ValueError("manifest URL is invalid")
            if not _url_host_allowed(raw_path):
                raise ValueError("manifest URL host is not allowlisted")
            canonical.append(
                {"kind": "url", "path": raw_path, "size": 0, "sha256": ""}
            )
            continue
        if kind != "file":
            raise ValueError("unsupported manifest entry kind")
        path = Path(raw_path).resolve(strict=True)
        if not path.is_file():
            raise ValueError("manifest target is not a file")
        size = int(path.stat().st_size)
        total_bytes += size
        if total_bytes > 50 * 1024 * 1024:
            raise ValueError("manifest exceeds 50MB")
        digest = _sha256_file(path)
        expected = str(item.get("sha256", "")).lower()
        expected_size = item.get("size")
        if expected and expected != digest:
            raise ValueError("manifest SHA-256 mismatch")
        if expected_size is not None and int(expected_size) != size:
            raise ValueError("manifest size mismatch")
        canonical.append(
            {"kind": "file", "path": str(path), "size": size, "sha256": digest}
        )
    return canonical


def _manifest_equal(left: list[dict], right: list[dict]) -> bool:
    """Manifest equal.
    
    Args:
        left: caller-supplied value.
        right: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    return json.dumps(left, sort_keys=True, ensure_ascii=False) == json.dumps(
        right, sort_keys=True, ensure_ascii=False
    )


def _path_summary(path_text: str) -> str:
    """Full path + type + size + content hash for an approval prompt."""
    try:
        path = Path(path_text).resolve(strict=False)
    except (OSError, ValueError):
        return f"{path_text} | unresolved"
    if not path.exists():
        return f"{path} | missing"
    if path.is_file():
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return f"{path} | file | {path.stat().st_size} bytes | sha256={digest.hexdigest()}"
    if path.is_dir():
        digest = hashlib.sha256()
        count = 0
        for child in sorted(path.rglob("*")):
            if child.is_file():
                count += 1
                rel = str(child.relative_to(path)).replace("\\", "/")
                digest.update(rel.encode("utf-8", "surrogateescape"))
                digest.update(b"\0")
                digest.update(str(child.stat().st_size).encode("ascii"))
                digest.update(b"\0")
        return f"{path} | directory | {count} files | tree-sha256={digest.hexdigest()}"
    return f"{path} | other"

