#!/usr/bin/env python3
"""Fail build on text hygiene defects that have previously broken Windows.

Checks:
  * C0 control bytes other than TAB/CR/LF
  * NUL bytes in text files
  * invalid UTF-8 text
  * double UTF-8 BOM

Binary payloads (exe/dll/whl/images/db/pyd) are skipped by suffix.
"""
from __future__ import annotations

import sys
from pathlib import Path

BINARY_SUFFIXES = {
    ".exe", ".dll", ".whl", ".png", ".jpg", ".jpeg", ".gif", ".ico",
    ".pyc", ".pyd", ".pdb", ".zip", ".gz", ".ttf", ".woff", ".woff2",
    ".db", ".graph", ".pdf",
}
SKIP_PARTS = {".git", ".venv", "__pycache__", "wheelhouse", "node_modules"}


def scan(root: Path) -> list[str]:
    problems: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix.lower() in BINARY_SUFFIXES:
            continue
        if any(part in SKIP_PARTS for part in path.parts):
            continue
        rel = path.relative_to(root).as_posix()
        data = path.read_bytes()
        if b"\x00" in data:
            problems.append(f"{rel}: NUL byte")
            continue
        for index, value in enumerate(data):
            if value < 32 and value not in (9, 10, 13):
                problems.append(f"{rel}: control byte 0x{value:02x} at {index}")
                break
        if data.startswith(b"\xef\xbb\xbf\xef\xbb\xbf"):
            problems.append(f"{rel}: double UTF-8 BOM")
        try:
            data.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            problems.append(f"{rel}: invalid UTF-8: {exc}")
    return problems


def main(argv: list[str]) -> int:
    root = Path(argv[1]).resolve() if len(argv) > 1 else Path.cwd()
    problems = scan(root)
    if problems:
        print("TEXT_HYGIENE_FAILED", file=sys.stderr)
        for item in problems:
            print("  " + item, file=sys.stderr)
        return 1
    print("TEXT_HYGIENE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
