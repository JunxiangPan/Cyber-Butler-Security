"""Generic pinned + hashed dependency gate."""
from __future__ import annotations

RULE_ID = "CBP-DEP-001"

import re

from .config import GateConfig

PIN = re.compile(r"^[A-Za-z0-9_.-]+==\S+")


def run(cfg: GateConfig) -> tuple[bool, str]:
    """Require a pinned, hashed lock and a hash-checking installer."""
    lock = cfg.path(cfg.dependency_lock)
    installer = cfg.path(cfg.installer_core)
    if not lock.is_file():
        return False, f"{cfg.dependency_lock} is missing"
    text = lock.read_text(encoding="utf-8")
    pins = [line for line in text.splitlines() if line.strip() and not line.startswith(("#", " ", "\\")) and "==" in line]
    if not pins or any(not PIN.match(line) for line in pins):
        return False, "dependency lock has unpinned requirements"
    if "--hash=sha256:" not in text:
        return False, "dependency lock has no sha256 hashes"
    if not installer.is_file() or "--require-hashes" not in installer.read_text(encoding="utf-8"):
        return False, "installer does not enforce --require-hashes"
    return True, f"dependency={len(pins)} pinned with hashes"
