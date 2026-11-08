#!/usr/bin/env python3
"""CBP supply-chain gate: the installed runtime lock must be hash-pinned."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "requirements-runtime.txt"
LOCK = ROOT / "requirements-runtime.lock"


def _canonical(name: str) -> str:
    """PEP 503-style normalization so Pillow == pillow."""
    return re.sub(r"[-_.]+", "-", name).lower()


def _name(block: str) -> str:
    match = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)", block)
    return _canonical(match.group(1)) if match else ""


def _logical_blocks(text: str) -> list[str]:
    """Join pip-compile backslash continuations, then drop comments/blanks."""
    joined = re.sub(r"\\\s*\r?\n", " ", text)
    blocks: list[str] = []
    for line in joined.splitlines():
        line = " ".join(line.split())
        if not line or line.startswith("#"):
            continue
        blocks.append(line)
    return blocks


def _source_names(text: str) -> list[str]:
    names: list[str] = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("-"):
            continue
        match = re.match(r"^([A-Za-z0-9][A-Za-z0-9._-]*)", line)
        if match:
            names.append(_canonical(match.group(1)))
    return names


def check(source: Path, lock: Path) -> list[str]:
    """Return human-readable problems; empty means PASS."""
    if not source.is_file():
        return [f"{source.name} missing"]
    if not lock.is_file():
        return [f"{lock.name} missing"]

    blocks = _logical_blocks(lock.read_text(encoding="utf-8"))
    if not blocks:
        return [f"{lock.name} has no requirements"]

    problems: list[str] = []
    for block in blocks:
        if "--hash=" not in block:
            problems.append(f"unpinned requirement in {lock.name}: {block[:140]}")

    locked = {_name(block) for block in blocks}
    for name in sorted(set(_source_names(source.read_text(encoding="utf-8")))):
        if name not in locked:
            problems.append(f"top-level requirement missing from {lock.name}: {name}")
    return problems


def main() -> int:
    problems = check(SOURCE, LOCK)
    if problems:
        print("DEPENDENCY_GATE_FAILED", file=sys.stderr)
        for item in problems:
            print("  " + item, file=sys.stderr)
        return 1
    blocks = _logical_blocks(LOCK.read_text(encoding="utf-8"))
    top_level = len(set(_source_names(SOURCE.read_text(encoding="utf-8"))))
    print(f"DEPENDENCY_GATE_OK pins={len(blocks)} top_level={top_level}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
