#!/usr/bin/env python3
"""Freeze/verify the test suite before the release pipeline runs.

Mechanisms borrowed from autopilot/testwall and xizi-rujin:
  - checks/MANIFEST.sha256 locks every test script byte-for-byte
  - checks/snapshot/ is the restore source if a test was modified
  - empty assertions (assert True, assert 1, assertTrue(True)) are rejected
  - assertion counts may not shrink below the frozen baseline

This is a test-integrity gate, not a replacement for the real VM acceptance.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECK_DIR = ROOT / "checks"
MANIFEST = CHECK_DIR / "MANIFEST.sha256"
ASSERTIONS = CHECK_DIR / "assertions.json"
SNAPSHOT = CHECK_DIR / "snapshot"
ROOTS = ("tests", "quality/tests", "webui/tests", "installer/tests")
CRITICAL = (
    "tools/Run-ReleasePipeline.ps1",
    "tools/sign_release.py",
    "tools/verify_release.py",
    "tools/merge_vm_acceptance.py",
    "tools/Run-Final-Acceptance.ps1",
    "tools/Audit-Package.ps1",
    "tools/audit_code_comments.py",
    "tools/audit_docs_consistency.py",
    "quality/preflight.py",
    "quality/run_quality_matrix.py",
)


def tracked_test_files() -> list[Path]:
    files: list[Path] = []
    for root_name in ROOTS:
        root = ROOT / root_name
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.suffix in {".py", ".ps1"}:
                files.append(path)
    for name in CRITICAL:
        path = ROOT / name
        if path.is_file():
            files.append(path)
    return files


def rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assertion_counts(path: Path) -> int:
    if path.suffix != ".py":
        return 0
    try:
        tree = ast.parse(path.read_text(encoding="utf-8-sig"))
    except SyntaxError:
        return 0
    count = 0
    for node in ast.walk(tree):
        if isinstance(node, ast.Assert):
            count += 1
        elif isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Attribute) and func.attr in {"assertTrue", "assertFalse", "assertEqual", "assertRaises"}:
                count += 1
    return count


def empty_assertions(path: Path) -> list[str]:
    if path.suffix != ".py":
        return []
    try:
        tree = ast.parse(path.read_text(encoding="utf-8-sig"))
    except SyntaxError as exc:
        return [f"{rel(path)}: syntax error: {exc}"]
    findings: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Assert):
            test = node.test
            if isinstance(test, ast.Constant) and bool(test.value):
                findings.append(f"{rel(path)}:{node.lineno}: assert {test.value!r}")
            if isinstance(test, ast.Constant) and test.value is True:
                findings.append(f"{rel(path)}:{node.lineno}: assert True")
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr in {"assertTrue", "assertFalse"} and node.args:
                arg = node.args[0]
                if isinstance(arg, ast.Constant) and isinstance(arg.value, bool):
                    findings.append(f"{rel(path)}:{node.lineno}: {node.func.attr}({arg.value!r})")
    return findings


def freeze() -> int:
    CHECK_DIR.mkdir(exist_ok=True)
    if SNAPSHOT.exists():
        shutil.rmtree(SNAPSHOT)
    SNAPSHOT.mkdir(parents=True)
    lines = []
    counts = {}
    for path in tracked_test_files():
        target = SNAPSHOT / rel(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        lines.append(f"{digest(path)}  {rel(path)}")
        counts[rel(path)] = assertion_counts(path)
    MANIFEST.write_text("\n".join(lines) + "\n", encoding="utf-8")
    ASSERTIONS.write_text(json.dumps(counts, indent=2) + "\n", encoding="utf-8")
    print(f"FROZEN tests={len(lines)} manifest={MANIFEST}")
    return 0


def verify(restore: bool) -> int:
    if not MANIFEST.is_file() or not SNAPSHOT.is_dir():
        print("TEST_INTEGRITY_FAILED: run freeze first", file=sys.stderr)
        return 1
    expected = {}
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        hash_value, name = line.split("  ", 1)
        expected[name] = hash_value
    old_counts = json.loads(ASSERTIONS.read_text(encoding="utf-8")) if ASSERTIONS.is_file() else {}
    problems: list[str] = []
    for name, hash_value in expected.items():
        path = ROOT / name
        if not path.is_file():
            problems.append(f"missing test file: {name}")
            continue
        actual = digest(path)
        if actual != hash_value:
            if restore:
                snapshot = SNAPSHOT / name
                if not snapshot.is_file():
                    problems.append(f"no snapshot for modified test: {name}")
                    continue
                shutil.copy2(snapshot, path)
                actual = digest(path)
                if actual != hash_value:
                    problems.append(f"restore failed: {name}")
                    continue
            else:
                problems.append(f"modified test file: {name}")
    for path in tracked_test_files():
        name = rel(path)
        if name not in expected:
            problems.append(f"new untracked test file: {name}")
        current = assertion_counts(path)
        baseline = int(old_counts.get(name, 0))
        if current < baseline:
            problems.append(f"assertion count shrank: {name} {baseline}->{current}")
        for finding in empty_assertions(path):
            problems.append("empty assertion: " + finding)
    if problems:
        print("TEST_INTEGRITY_FAILED", file=sys.stderr)
        for item in problems[:200]:
            print("  " + item, file=sys.stderr)
        return 1
    print(f"TEST_INTEGRITY_OK files={len(expected)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("freeze", "verify"))
    parser.add_argument("--restore", action="store_true")
    args = parser.parse_args()
    return freeze() if args.action == "freeze" else verify(args.restore)


if __name__ == "__main__":
    raise SystemExit(main())
