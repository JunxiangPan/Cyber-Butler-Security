"""Generic AST/token comment gate."""
from __future__ import annotations

RULE_ID = "CBP-CMT-001"

import ast
import re
import tokenize

from .config import GateConfig

SLOP = re.compile(r"#\s*(send|get|set|run|handle|process|check|do|call)\b", re.IGNORECASE)
GENERIC = ("caller-supplied value", "function result, or none", "helper/type")


def _check(path, findings):
    tree = ast.parse(path.read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            continue
        name = getattr(node, "name", "")
        if name.startswith("_"):
            continue
        doc = ast.get_docstring(node) or ""
        if len(doc.strip()) < 20:
            findings.append(f"{path.name}:{node.lineno}: public {name} lacks substantive docstring")
            continue
        if any(phrase in doc.casefold() for phrase in GENERIC):
            findings.append(f"{path.name}:{node.lineno}: public {name} docstring is generic boilerplate")
        args = [a.arg for a in node.args.args if a.arg not in {"self", "cls"}] if hasattr(node, "args") else []
        if "Args:" in doc or "Parameters:" in doc:
            for arg in args:
                if arg not in doc:
                    findings.append(f"{path.name}:{node.lineno}: docstring misses {arg}")
    with path.open("r", encoding="utf-8") as handle:
        for token in tokenize.generate_tokens(handle.readline):
            if token.type == tokenize.COMMENT and SLOP.search(token.string):
                findings.append(f"{path.name}:{token.start[0]}: slop comment {token.string.strip()}")


def run(cfg: GateConfig) -> tuple[bool, str]:
    """Reject missing docstrings, argument mismatches, and slop comments."""
    findings: list[str] = []
    for relative in cfg.comment_files:
        path = cfg.path(relative)
        if path.is_file():
            try:
                _check(path, findings)
            except SyntaxError as exc:
                findings.append(f"{path.name}: parse failed: {exc}")
    if findings:
        return False, "\n".join(findings[:80]) + f"\nfindings={len(findings)}"
    return True, f"comments={len(cfg.comment_files)} files"
