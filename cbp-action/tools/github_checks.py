#!/usr/bin/env python3
"""Publish one GitHub check run per CBP gate (dry-run capable)."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.request

LINE = re.compile(r"^([a-z]+): (PASS|FAIL|SKIPPED)", re.IGNORECASE)


def parse_gates(output: str) -> list[tuple[str, str]]:
    """Extract gate name and PASS/FAIL/SKIPPED from CLI output."""
    gates = []
    for line in output.splitlines():
        match = LINE.match(line.strip())
        if match:
            gates.append((match.group(1), match.group(2).upper()))
    return gates


def post(repo: str, sha: str, token: str, gate: str, status: str, detail: str) -> None:
    conclusion = "success" if status == "PASS" else "failure" if status == "FAIL" else "neutral"
    body = json.dumps({
        "name": "CBP / " + gate,
        "head_sha": sha,
        "status": "completed",
        "conclusion": conclusion,
        "output": {"title": gate, "summary": detail[:60000]},
    }).encode("utf-8")
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/check-runs",
        data=body,
        method="POST",
        headers={"Authorization": "Bearer " + token, "Accept": "application/vnd.github+json", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        response.read()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--repo", default="")
    parser.add_argument("--sha", default="")
    parser.add_argument("--token", default="")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    completed = subprocess.run(
        [sys.executable, "-m", "cbp.cli", "--root", args.root, "--mode", "audit"],
        capture_output=True, text=True, timeout=300, check=False,
    )
    gates = parse_gates(completed.stdout)
    if not gates:
        print("CHECKS_FAILED no gate output")
        return 1
    for gate, status in gates:
        if args.dry_run:
            print(f"CHECK gate={gate} status={status}")
        else:
            post(args.repo, args.sha, args.token, gate, status, completed.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
