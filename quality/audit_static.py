#!/usr/bin/env python3
"""Run the static gates that cannot be replaced by a green unit test.

mypy, pyright, vulture and PSScriptAnalyzer must all return zero errors.
PSScriptAnalyzer is loaded from CBS_PSSA_MODULE or C:\\PSSA.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(name: str, command: list[str]) -> tuple[bool, str]:
    try:
        result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=1800)
    except FileNotFoundError as exc:
        return False, f"{name}: executable missing: {exc}"
    output = (result.stdout + "\n" + result.stderr).strip()
    print(f"===== {name} (exit {result.returncode}) =====")
    print(output[-12000:])
    return result.returncode == 0, output


def main() -> int:
    failures = 0
    ok, _ = run("mypy", [
        sys.executable, "-m", "mypy", "--ignore-missing-imports",
        "--follow-imports=silent", "tools", "webui", "installer",
    ])
    failures += 0 if ok else 1
    ok, _ = run("pyright", [
        sys.executable, "-m", "pyright", "tools", "webui", "installer",
    ])
    failures += 0 if ok else 1
    ok, _ = run("vulture", [
        sys.executable, "-m", "vulture", "tools", "webui", "installer",
        "vulture_whitelist.py", "--min-confidence", "60",
        "--exclude", "webui/.venv",
    ])
    failures += 0 if ok else 1
    module = os.environ.get("CBS_PSSA_MODULE", r"C:\PSSA\PSScriptAnalyzer.psd1")
    pssa = ROOT / "quality" / "audit_pssa.ps1"
    ok, _ = run("PSScriptAnalyzer", [
        "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", str(pssa), "-ModulePath", module,
    ])
    failures += 0 if ok else 1
    if failures:
        print(f"STATIC_GATE_FAILED components={failures}", file=sys.stderr)
        return 1
    print("STATIC_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
