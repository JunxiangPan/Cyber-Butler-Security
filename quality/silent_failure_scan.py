#!/usr/bin/env python3
"""CBP silent-failure gate: empty catch/except blocks are forbidden."""
from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CRITICAL = (
    "tools/broker.py",
    "tools/audit_chain.py",
    "tools/approval_preview.py",
    "tools/win_path_guard.py",
    "webui/services.py",
    "webui/auth.py",
)
PS1_FILES = ("tools/broker.py", "tools/update.ps1", "tools/Run-Final-Acceptance.ps1")


def _handler_is_silent(handler: ast.ExceptHandler) -> bool:
    body = handler.body
    if not body:
        return True
    for node in body:
        if isinstance(node, ast.Pass):
            continue
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant):
            continue
        return False
    return True


def main() -> int:
    problems: list[str] = []
    for relative in CRITICAL:
        path = ROOT / relative
        if not path.is_file():
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8-sig"))
        except SyntaxError as exc:
            problems.append(f"{relative}: parse error {exc}")
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.ExceptHandler) and _handler_is_silent(node):
                problems.append(f"{relative}:{node.lineno}: silent except handler")
    for relative in PS1_FILES:
        path = ROOT / relative
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8-sig")
        for match in re.finditer(r"catch\s*\{\s*\}", text, re.IGNORECASE):
            line = text[: match.start()].count("\n") + 1
            problems.append(f"{relative}:{line}: empty catch block")
    if problems:
        print("SILENT_FAILURE_GATE_FAILED", file=sys.stderr)
        for item in problems:
            print("  " + item, file=sys.stderr)
        return 1
    print("SILENT_FAILURE_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
