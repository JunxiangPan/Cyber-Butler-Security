"""Generic pinned + hashed dependency gate."""
from __future__ import annotations

RULE_ID = "CBP-DEP-001"

import re

from .config import GateConfig

PIN = re.compile(r"^[A-Za-z0-9_.-]+(?:\[[A-Za-z0-9_,.-]+\])?(?:===|==)\S+$")
HASH = re.compile(r"^--hash=sha256:[0-9a-fA-F]{64}$")


def _pins(text: str) -> tuple[list[str], str]:
    pins: list[str] = []
    has_hash = False
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("--hash=sha256:"):
            if not pins:
                return [], "dependency hash appears before a requirement"
            if not HASH.fullmatch(line.rstrip("\\").strip()):
                return [], "dependency lock has an invalid sha256 hash"
            has_hash = True
            continue
        line = line.rstrip("\\").strip()
        requirement = line.split(";", 1)[0].strip()
        if "==" not in requirement:
            return [], f"dependency lock has an unpinned requirement: {line[:80]}"
        if not PIN.match(requirement):
            return [], f"dependency lock has a malformed requirement: {line[:80]}"
        pins.append(requirement)
    if not pins:
        return [], "dependency lock has no pinned requirements"
    if not has_hash:
        return [], "dependency lock has no sha256 hashes"
    return pins, ""


def _installer_enforces(installer: str) -> tuple[bool, str]:
    effective: list[str] = []
    for raw in installer.splitlines():
        line = raw.split("#", 1)[0].strip()
        if line:
            effective.append(line)
    pip_lines = [
        line for line in effective
        if re.search(r"\bpip(?:\.exe)?\b", line, re.I) and re.search(r"\binstall\b", line, re.I)
    ]
    if not pip_lines:
        return False, "installer has no effective pip install command"
    if any("--require-hashes" in line for line in pip_lines):
        return True, ""
    # PowerShell installers often build the command on a later assignment line.
    if any(re.search(r"\bcommand\b.*\+=.*--require-hashes", line, re.I) for line in effective):
        return True, ""
    return False, "installer's effective pip install command lacks --require-hashes"


def run(cfg: GateConfig) -> tuple[bool, str]:
    """Require a fully pinned, hashed lock and an effective hash-checking install."""
    lock = cfg.path(cfg.dependency_lock)
    installer = cfg.path(cfg.install_command)
    if not lock.is_file():
        return False, f"{cfg.dependency_lock} is missing"
    pins, problem = _pins(lock.read_text(encoding="utf-8"))
    if problem:
        return False, problem
    if not installer.is_file():
        return False, f"{cfg.install_command} is missing"
    enforced, problem = _installer_enforces(installer.read_text(encoding="utf-8"))
    if not enforced:
        return False, problem
    return True, f"dependency={len(pins)} pinned with hashes"
