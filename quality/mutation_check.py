#!/usr/bin/env python3
"""Mutation check: invert real assertions, require the tests to fail, restore.

This is a source-level mutation, not an ``if False`` wrapper. The original file
is saved in memory and restored in a finally block; the before/after SHA-256 is
recorded. No test assertion is permanently changed.
"""
from __future__ import annotations

import ast
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests"
ART = ROOT / "quality" / "artifacts" / "mutation"


def test_functions(path: Path) -> list[tuple[str, int, ast.FunctionDef]]:
    try:
        tree = ast.parse(path.read_text(encoding="utf-8-sig"))
    except SyntaxError:
        return []
    result: list[tuple[str, int, ast.FunctionDef]] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name.startswith("test_"):
            result.append((node.name, node.lineno, node))
    return result


def invert_assert(path: Path, lineno: int) -> tuple[str, str] | None:
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    index = lineno - 1
    if index < 0 or index >= len(lines):
        return None
    line = lines[index]
    if "==" in line:
        mutated = line.replace("==", "!=", 1)
    elif "!=" in line:
        mutated = line.replace("!=", "==", 1)
    elif "assert " in line and "assert not " not in line:
        mutated = line.replace("assert ", "assert not ", 1)
    else:
        return None
    if mutated == line:
        return None
    lines[index] = mutated
    return line, "\n".join(lines) + "\n"


def main() -> int:
    ART.mkdir(parents=True, exist_ok=True)
    candidates: list[tuple[Path, str, int]] = []
    for path in sorted(TESTS.glob("test_*.py")):
        for name, lineno, node in test_functions(path):
            for item in ast.walk(node):
                if isinstance(item, ast.Assert):
                    candidates.append((path, name, item.lineno))
                    break
    candidates = sorted(set(candidates), key=lambda item: (str(item[0]), item[1], item[2]))
    # Deterministic sample, no network/random dependency.
    sample = candidates[:3]
    if len(sample) < 3:
        print("MUTATION_FAILED: fewer than 3 assertions", file=sys.stderr)
        return 1
    targets: list[dict[str, object]] = []
    results: list[str] = []
    failures = 0
    for path, name, lineno in sample:
        original = path.read_text(encoding="utf-8-sig")
        original_hash = hashlib.sha256(original.encode("utf-8")).hexdigest()
        mutated_text = invert_assert(path, lineno)
        if not mutated_text:
            print(f"MUTATION_FAILED: cannot invert {path}:{lineno}", file=sys.stderr)
            failures += 1
            continue
        before, after = mutated_text
        results.append(f"TARGET {path}:{lineno} {name}")
        results.append(f"ORIGINAL {before.strip()}")
        results.append(f"MUTATED  {after.splitlines()[lineno - 1].strip()}")
        path.write_text(after, encoding="utf-8-sig")
        try:
            command = [
                sys.executable, "-m", "pytest", "-q", f"{path}::{name}",
                "--basetemp", str(ART / ("pytest-" + name)),
                "-p", "no:cacheprovider",
            ]
            run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=300)
            killed = run.returncode != 0
            results.append(f"EXIT={run.returncode} KILLED={killed}")
            targets.append({
                "file": str(path.relative_to(ROOT)),
                "line": lineno,
                "test": name,
                "original": before.strip(),
                "mutated": after.splitlines()[lineno - 1].strip(),
                "exit_code": run.returncode,
                "killed": killed,
            })
            if not killed:
                failures += 1
        finally:
            path.write_text(original, encoding="utf-8")
            restored = hashlib.sha256(path.read_text(encoding="utf-8").encode("utf-8")).hexdigest()
            restored_ok = restored == original_hash
            results.append(f"RESTORED={restored_ok} SHA256={restored}")
            if not restored_ok:
                failures += 1
    (ART / "targets.json").write_text(json.dumps(targets, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ART / "result.txt").write_text("\n".join(results) + "\n", encoding="utf-8")
    print("\n".join(results))
    for index, item in enumerate(targets, 1):
        print(f"TARGET_{index}={item['file']}:{item['line']} {item['original']} -> {item['mutated']}")
    all_red = len(targets) == 3 and all(bool(item["killed"]) for item in targets)
    restore_ok = all("RESTORED=True" in line for line in results if line.startswith("RESTORED="))
    print(f"ALL_TURNED_RED={all_red}")
    print(f"RESTORE_OK={restore_ok}")
    if failures or not all_red or not restore_ok:
        print("MUTATION_FAILED", file=sys.stderr)
        return 1
    print("MUTATION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
