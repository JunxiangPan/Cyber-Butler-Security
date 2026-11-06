#!/usr/bin/env python3
"""AST anti-slop audit for public broker classes and functions."""
from __future__ import annotations

import ast
import re
import sys
import tokenize
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [ROOT / "tools" / "broker.py", ROOT / "tools" / "broker_policy.py", ROOT / "tools" / "broker_state.py", ROOT / "tools" / "broker_config.py"]
GENERIC = ("caller-supplied value", "function result, or none", "helper/type")
SLOP = re.compile(r"#\s*(send|get|set|run|handle|process|check|do|call)", re.IGNORECASE)


def _check(node: ast.AST, path: Path) -> list[str]:
    findings: list[str] = []
    name = getattr(node, "name", "")
    if name.startswith("_") or not name:
        return findings
    doc = ast.get_docstring(node) or ""
    if len(doc.strip()) < 20:
        findings.append(f"{path.name}:{node.lineno}: {name} has no substantive docstring")
        return findings
    args = [a.arg for a in getattr(node, "args", ast.arguments(posonlyargs=[], args=[], kwonlyargs=[], kw_defaults=[], defaults=[])).args if a.arg not in {"self", "cls"}]
    if "Args:" in doc or "Parameters:" in doc:
        for arg in args:
            if arg not in doc:
                findings.append(f"{path.name}:{node.lineno}: {name} docstring does not name parameter {arg}")
    # Generic phrases are warnings; missing docstrings and Args mismatches block.
    return findings


def main() -> int:
    findings: list[str] = []
    for path in TARGETS:
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"))
        except SyntaxError as exc:
            findings.append(f"{path.name}: parse failed: {exc}")
            continue
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                findings.extend(_check(node, path))
        with path.open("r", encoding="utf-8") as handle:
            for token in tokenize.generate_tokens(handle.readline):
                if token.type == tokenize.COMMENT and SLOP.search(token.string):
                    findings.append(f"{path.name}:{token.start[0]}: slop comment {token.string.strip()}")
    if findings:
        print("COMMENT_AUDIT_FAILED")
        for item in findings[:80]:
            print("  " + item)
        print(f"COMMENT_FINDINGS={len(findings)}")
        return 1
    print("COMMENT_AUDIT_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
