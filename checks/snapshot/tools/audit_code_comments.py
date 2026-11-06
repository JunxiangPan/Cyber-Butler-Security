#!/usr/bin/env python3
"""AST-based code-comment gate.

Python: every function and class in tools/, webui/, installer/ must have a
docstring. Parsing uses ast.parse, never regex.

PowerShell: every function longer than 20 lines must have a comment block
near it. The PowerShell parser supplies the AST and comment tokens.
"""
from __future__ import annotations

import ast
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PY_ROOTS = ("tools", "webui", "installer")
PS_ROOTS = ("tools", "webui", "installer")
SKIP_PARTS = {".venv", "__pycache__", ".git", "wheelhouse", "node_modules"}


def python_findings() -> tuple[list[str], list[dict], int]:
    """Python findings.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    problems: list[str] = []
    missing: list[dict] = []
    total = 0
    for root_name in PY_ROOTS:
        root = ROOT / root_name
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.py")):
            if any(part in SKIP_PARTS for part in path.parts):
                continue
            rel = path.relative_to(ROOT).as_posix()
            try:
                tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=rel)
            except SyntaxError as exc:
                problems.append(f"{rel}:{exc.lineno}: Python syntax error: {exc.msg}")
                continue
            for node in ast.walk(tree):
                if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                    total += 1
                    if not ast.get_docstring(node):
                        missing.append({
                            "file": rel,
                            "line": int(node.lineno),
                            "name": node.name,
                            "kind": type(node).__name__,
                        })
    return problems, missing, total


def powershell_findings() -> tuple[list[str], list[dict], int]:
    """Powershell findings.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    script = ROOT / "tools" / "audit_ps_comments.ps1"
    if not script.is_file():
        return ["tools/audit_ps_comments.ps1 is missing"], [], 0
    result = subprocess.run(
        ["pwsh.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
         "-File", str(script), "-Root", str(ROOT)],
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300,
    )
    payload = (result.stdout or "").strip()
    try:
        data = json.loads(payload[payload.find("{"):])
    except Exception:
        return [f"PowerShell AST audit failed: {result.stdout} {result.stderr}"], [], 0
    problems = list(data.get("syntax_errors", []))
    missing = []
    for item in data.get("missing_comments", []):
        missing.append({
            "file": item.get("file", ""),
            "line": int(item.get("line", 0)),
            "name": item.get("name", ""),
            "kind": "Function",
        })
        problems.append(
            f"{item.get('file')}:{item.get('line')}: complex PowerShell function "
            f"{item.get('name')} has no block comment"
        )
    return problems, missing, int(data.get("functions", 0))


def main() -> int:
    """Main.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    py_syntax, py_missing, py_total = python_findings()
    ps_problems, ps_missing, ps_total = powershell_findings()
    missing = py_missing + ps_missing
    report = {
        "python_functions": py_total,
        "python_missing_docstrings": len(py_missing),
        "powershell_functions": ps_total,
        "powershell_missing_block_comments": len(ps_missing),
        "missing": missing[:500],
    }
    (ROOT / "DOC_STATUS_REPORT.code.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    problems = py_syntax + ps_problems
    if py_missing:
        problems.extend(f"{item['file']}:{item['line']}: missing Python docstring: {item['name']}" for item in py_missing)
    if ps_missing:
        problems.extend(f"{item['file']}:{item['line']}: missing PowerShell block comment: {item['name']}" for item in ps_missing)
    if problems:
        print("CODE_COMMENT_GATE_FAILED", file=sys.stderr)
        for item in problems[:300]:
            print("  " + item, file=sys.stderr)
        return 1
    print("CODE_COMMENT_GATE_OK")
    print(
        f"python_functions={py_total} missing_docstrings={len(py_missing)} "
        f"powershell_functions={ps_total} missing_block_comments={len(ps_missing)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
