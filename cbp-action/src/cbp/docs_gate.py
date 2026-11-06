"""Generic incident-history manifest gate."""
from __future__ import annotations

RULE_ID = "CBP-DOC-001"

import hashlib
import json

from .config import GateConfig


def run(cfg: GateConfig) -> tuple[bool, str]:
    """Verify every incident postmortem against its recorded SHA256."""
    manifest = cfg.path(cfg.docs_manifest)
    if not manifest.is_file():
        return False, f"{cfg.docs_manifest} is missing"
    data = json.loads(manifest.read_text(encoding="utf-8"))
    entries = {entry["path"]: entry["sha256"].upper() for entry in data.get("files", [])}
    if not entries:
        return False, "history manifest is empty"
    for path, digest in entries.items():
        target = cfg.path(path)
        if not target.is_file():
            return False, f"{path} is missing"
        actual = hashlib.sha256(target.read_bytes().replace(bytes([13, 10]), bytes([10]))).hexdigest().upper()
        if actual != digest:
            return False, f"{path} hash changed"
    return True, f"docs={len(entries)} files"
