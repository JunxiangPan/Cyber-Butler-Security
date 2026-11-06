#!/usr/bin/env python3
"""Verify a downloaded dogfood manifest against its hash and CI metadata."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.dogfood_manifest import validate_manifest

COUNT = re.compile(r"(?m)^QUALITY_COUNTS:\s*(\d+/\d+)\s*$")


class ArtifactError(RuntimeError):
    """Raised when a release artifact fails verification."""


def _hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(
    manifest_path: Path,
    hash_path: Path,
    notes_path: Path,
    expected_run_id: str,
    expected_commit_sha: str,
) -> dict[str, Any]:
    """Verify hash, run id, commit, and generated release notes."""
    if not manifest_path.is_file():
        raise ArtifactError(f"manifest missing: {manifest_path}")
    if not hash_path.is_file():
        raise ArtifactError(f"manifest hash missing: {hash_path}")
    if not notes_path.is_file():
        raise ArtifactError(f"generated release notes missing: {notes_path}")
    expected = hash_path.read_text(encoding="utf-8").split()[0].strip().lower()
    actual = _hash(manifest_path)
    if actual != expected:
        raise ArtifactError(f"manifest hash mismatch: actual={actual} expected={expected}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    problems = validate_manifest(manifest, actions=True)
    if problems:
        raise ArtifactError("manifest validation failed: " + "; ".join(problems))
    if str(manifest.get("ci_run_id")) != str(expected_run_id):
        raise ArtifactError(
            f"ci_run_id mismatch: manifest={manifest.get('ci_run_id')} expected={expected_run_id}"
        )
    if str(manifest.get("ci_commit_sha")) != str(expected_commit_sha):
        raise ArtifactError(
            f"ci_commit_sha mismatch: manifest={manifest.get('ci_commit_sha')} expected={expected_commit_sha}"
        )
    counts = manifest.get("counts", {})
    expected_line = f"{counts.get('passed')}/{counts.get('total')}"
    match = COUNT.search(notes_path.read_text(encoding="utf-8"))
    if not match:
        raise ArtifactError("generated notes have no QUALITY_COUNTS line")
    if match.group(1) != expected_line:
        raise ArtifactError(f"notes counts {match.group(1)} != manifest {expected_line}")
    print(f"MANIFEST_ARTIFACT_OK sha256={actual} run_id={expected_run_id} commit={expected_commit_sha}")
    return manifest


def main(argv: list[str] | None = None) -> int:
    """Run the release artifact verification and print the result."""
    parser = argparse.ArgumentParser(prog="verify-manifest-artifact")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--hash", required=True)
    parser.add_argument("--notes", required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--commit-sha", required=True)
    args = parser.parse_args(argv)
    try:
        verify(Path(args.manifest), Path(args.hash), Path(args.notes), args.run_id, args.commit_sha)
    except (ArtifactError, OSError, ValueError) as exc:
        print(f"MANIFEST_ARTIFACT_FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
