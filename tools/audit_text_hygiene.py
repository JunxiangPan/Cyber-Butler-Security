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

import re
import sys
from pathlib import Path

BINARY_SUFFIXES = {
    ".exe", ".dll", ".whl", ".png", ".jpg", ".jpeg", ".gif", ".ico",
    ".pyc", ".pyd", ".pdb", ".zip", ".gz", ".ttf", ".woff", ".woff2",
    ".db", ".graph", ".pdf",
}
SKIP_PARTS = {".git", ".venv", "__pycache__", "wheelhouse", "node_modules", "backups", "vendor-audit"}
SKIP_FILES = {"tools/audit_text_hygiene.py"}
FORBIDDEN = (
    ("private_path", re.compile("C:" + re.escape(chr(92)) + "Users", re.IGNORECASE)),
    ("private_name", re.compile("".join(chr(c) for c in (0x5927, 0x80A5, 0x9C7C)))),
    ("legacy_qq", re.compile("235167" + "1738")),
    ("third_party", re.compile("".join(chr(c) for c in (0x0041,0x0073,0x0074,0x0072,0x0042,0x006f,0x0074)) + "|" + "".join(chr(c) for c in (0x0053,0x006e,0x006f,0x0077,0x004c,0x0075,0x006d,0x0061)) + "|" + "".join(chr(c) for c in (0x004f,0x006e,0x0065,0x0042,0x006f,0x0074)) + "|" + "".join(chr(c) for c in (0x45,0x78,0x74,0x65,0x72,0x6e,0x61,0x6c,0x41,0x67,0x65,0x6e,0x74)) + "|" + "".join(chr(c) for c in (0x45,0x78,0x74,0x65,0x72,0x6e,0x61,0x6c,0x41,0x70,0x70)) + "|" + "".join(chr(c) for c in (0x82CF,0x8C28,0x8A00)), re.IGNORECASE)),
)


def scan(root: Path) -> list[str]:
    """Scan.
    
    Args:
        root: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
    problems: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix.lower() in BINARY_SUFFIXES:
            continue
        if any(part in SKIP_PARTS for part in path.parts):
            continue
        if any(part.startswith(("tmp-", "pytest-of-")) for part in path.parts):
            continue
        rel = path.relative_to(root).as_posix()
        if rel in SKIP_FILES:
            continue
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
            text = data.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            problems.append(f"{rel}: invalid UTF-8: {exc}")
            continue
        for label, pattern in FORBIDDEN:
            if pattern.search(text):
                problems.append(f"{rel}: forbidden {label}")
    return problems


def main(argv: list[str]) -> int:
    """Main.
    
    Args:
        argv: caller-supplied value.
    
    Returns:
        Function result, or None when no value is returned.
    """
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
