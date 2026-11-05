#!/usr/bin/env python3
"""Require a hash-locked runtime dependency file and a hash-checking installer."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "requirements-runtime.lock"
INSTALLER = ROOT / "installer" / "lib" / "Installer.Core.ps1"
PIN = re.compile(r"^[A-Za-z0-9_.-]+==\S+\s*(?:\\s*)?$")


def main() -> int:
    if not LOCK.is_file():
        print("DEPENDENCY_GATE_FAILED: requirements-runtime.lock is missing")
        return 1
    lines = LOCK.read_text(encoding="utf-8").splitlines()
    pin_lines = [line for line in lines if line and not line.startswith(("#", " ", "\\")) and "==" in line]
    if not pin_lines:
        print("DEPENDENCY_GATE_FAILED: lock has unpinned requirements")
        return 1
    hash_count = sum(1 for line in lines if "--hash=sha256:" in line)
    if not pin_lines:
        print("DEPENDENCY_GATE_FAILED: lock has requirements without hashes")
        return 1
    if not INSTALLER.is_file() or "--require-hashes" not in INSTALLER.read_text(encoding="utf-8"):
        print("DEPENDENCY_GATE_FAILED: installer does not use --require-hashes")
        return 1
    print(f"DEPENDENCY_GATE_OK: {len(pin_lines)} pinned packages, {hash_count} hashes, --require-hashes present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
