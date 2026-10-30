#!/usr/bin/env python3
"""Fail CI on accidental private identifiers in the public release tree.

Rules:
  * any @163.com address is rejected;
  * a real C:\\Users\\<name> path is rejected; YOUR_* placeholders are allowed;
  * standalone 9-12 digit numbers are rejected;
  * 5-8 digit numbers are rejected only when the same line has QQ/owner context.

The contextual rule avoids flagging ports, CVE ids and test fixture numbers.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCANNED_SUFFIXES = {".md", ".py", ".ps1", ".yaml", ".yml", ".json", ".txt"}
EXCLUDED_NAMES = {"privacy_scan.py"}
EXCLUDED_PARTS = {".git", "__pycache__", ".venv", "node_modules", "backups", "data"}
ALLOWED_NUMBERS = {
    "11434", "18090", "18085", "6185", "5099",
    "24576", "49152", "262144", "16000", "20261028",
    "46233", "99999", "10000", "10001", "134217728",
}
NUMBER_RE = re.compile(r"(?<![0-9A-Za-z])(\d{5,12})(?![0-9A-Za-z])")
QQ_CONTEXT_RE = re.compile(
    r"(?i)(qq|owner|uin|umo|私聊|好友|账号|群号|群聊|用户|sender)"
)
USER_PATH_RE = re.compile(r"C:\\Users\\(?!YOUR_|USER|user|<|%|\$|\.\.\.)")
EMAIL_RE = re.compile(r"@163\.com", re.I)


def iter_files():
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path.name in EXCLUDED_NAMES:
            continue
        if any(part in EXCLUDED_PARTS for part in path.parts):
            continue
        if path.suffix.lower() not in SCANNED_SUFFIXES:
            continue
        yield path


def scan_file(path: Path) -> list[str]:
    findings: list[str] = []
    try:
        text = path.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeDecodeError):
        return findings
    for number, line in enumerate(text.splitlines(), 1):
        if EMAIL_RE.search(line):
            findings.append(f"{path}:{number}: private @163.com address")
        if USER_PATH_RE.search(line):
            findings.append(f"{path}:{number}: real C:\\Users\\ path")
        for match in NUMBER_RE.finditer(line):
            value = match.group(1)
            if value in ALLOWED_NUMBERS:
                continue
            if len(value) >= 9:
                findings.append(f"{path}:{number}: suspicious 9-12 digit number {value}")
            elif QQ_CONTEXT_RE.search(line):
                findings.append(f"{path}:{number}: QQ-context number {value}")
    return findings


def main() -> int:
    findings: list[str] = []
    for path in iter_files():
        findings.extend(scan_file(path))
    if findings:
        for finding in findings:
            print("PRIVACY_FINDING " + finding)
        return 1
    print("privacy scan: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
