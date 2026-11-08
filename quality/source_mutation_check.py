#!/usr/bin/env python3
"""CBP source mutation gate: mutate production logic, require tests to fail."""
from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MUTATIONS = (
    (
        "tools/broker.py",
        'if action == "delete" and target.is_dir():',
        'if action == "delete" and False:',
        "quality/tests/test_security_redlines.py::test_directory_delete_is_rejected_400",
    ),
    (
        "tools/broker.py",
        'if not _url_host_allowed(raw_path):',
        'if False:',
        "tests/test_broker_manifest.py::test_send_url_requires_allowlist",
    ),
    (
        "tools/broker.py",
        'scoped_minutes = 0',
        'scoped_minutes = 30',
        "quality/tests/test_security_redlines.py::test_broker_source_forces_scoped_minutes_zero",
    ),
)


def main() -> int:
    failures = 0
    for relative, original, mutated, test in MUTATIONS:
        path = ROOT / relative
        before = path.read_bytes()
        original_hash = hashlib.sha256(before).hexdigest()
        if original.encode("utf-8") not in before:
            print(f"MUTATION_FAILED: source marker missing: {original}", file=sys.stderr)
            failures += 1
            continue
        path.write_bytes(before.replace(original.encode("utf-8"), mutated.encode("utf-8"), 1))
        try:
            run = subprocess.run(
                [sys.executable, "-m", "pytest", "-q", test, "-p", "no:cacheprovider"],
                cwd=ROOT,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=300,
            )
        finally:
            path.write_bytes(before)
        restored = hashlib.sha256(path.read_bytes()).hexdigest() == original_hash
        if run.returncode == 0:
            print(f"MUTATION_SURVIVED {relative}: {original} -> {mutated}", file=sys.stderr)
            failures += 1
        if not restored:
            print(f"MUTATION_RESTORE_FAILED {relative}", file=sys.stderr)
            failures += 1
        print(f"MUTATION {relative}: {original} -> {mutated} exit={run.returncode} restored={restored}")
    if failures:
        print(f"MUTATION_FAILED count={failures}", file=sys.stderr)
        return 1
    print("MUTATION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
