#!/usr/bin/env python3
"""Sanitize a release tree and fail on likely secrets.

This is the public, generic version. Pass your real values explicitly:

  python tools/sanitize_for_release.py . \
    --qq YOUR_REAL_QQ --user-path "C:\\Users\\YOUR_NAME" --apply

No real identifiers are embedded in this file.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

TEXT_SUFFIXES = {".py", ".ps1", ".bat", ".cmd", ".md", ".yaml", ".yml", ".json", ".txt", ".toml"}
SKIP_DIRS = {
    ".git", ".venv", "venv", "node_modules", "__pycache__", "data", "logs",
    "backups", "downloads", "playwright-profile", "playwright-output",
    "playwright-qa-profile", "playwright-qa-output", "broker", "temp", "tmp",
}
SECRET_PATTERNS = [
    re.compile(r"sk-[A-Za-z0-9]{20,}"),
    re.compile(r"gh[pousr]_[A-Za-z0-9_]{20,}"),
    re.compile(r"github_pat_[A-Za-z0-9_]{30,}"),
    re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----"),
    re.compile(
        r"(?i)\b(api[_-]?key|secret|token|password|passwd)\b\s*[:=]\s*"
        r"[\"'][^\"']{12,}[\"']"
    ),
]


def iter_text_files(root: Path):
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        yield path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("--qq", default="")
    parser.add_argument("--user-path", default="")
    parser.add_argument("--project-path", default="")
    parser.add_argument("--host", default="")
    parser.add_argument("--service-user", default="")
    parser.add_argument("--platform", default="")
    parser.add_argument("--agent-name", default="")
    parser.add_argument("--shared-folder", default="")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    replacements: list[tuple[str, str]] = []
    if args.qq:
        replacements.append((re.escape(args.qq), "YOUR_QQ_ID"))
    if args.user_path:
        replacements.append((re.escape(args.user_path), "YOUR_USER_PATH"))
    if args.project_path:
        replacements.append((re.escape(args.project_path), "YOUR_PROJECT_PATH"))
    if args.host:
        replacements.append((re.escape(args.host), "YOUR_HOST"))
    if args.service_user:
        replacements.append((re.escape(args.service_user), "YOUR_SERVICE_USER"))
    if args.platform:
        replacements.append((re.escape(args.platform), "YOUR_PLATFORM_ID"))
    if args.agent_name:
        replacements.append((re.escape(args.agent_name), "YOUR_AGENT_NAME"))
    if args.shared_folder:
        replacements.append((re.escape(args.shared_folder), "YOUR_SHARED_FOLDER"))

    root = Path(args.root).resolve()
    changed = 0
    findings: list[str] = []
    for path in sorted(iter_text_files(root)):
        try:
            original = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        text = original
        for pattern, replacement in replacements:
            text, count = re.subn(pattern, replacement, text, flags=re.I)
            if count:
                print(f"CHANGED {path}: {count} -> {replacement}")
        if text != original:
            changed += 1
            if args.apply:
                path.write_text(text, encoding="utf-8")
        for number, line in enumerate(text.splitlines(), 1):
            for pattern in SECRET_PATTERNS:
                if pattern.search(line):
                    findings.append(f"{path}:{number}: {pattern.pattern}")
                    break

    print(f"\nfiles changed: {changed}")
    print(f"secret-like findings: {len(findings)}")
    for finding in findings:
        print(f"FINDING {finding}")
    return 1 if args.strict and findings else 0


if __name__ == "__main__":
    sys.exit(main())
